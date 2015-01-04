#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Std;
use SVG;
use POSIX;
use PriceChart;


my %args;
getopts("v", \%args);

$| = 1 if ($args{v});

# my $log = get_log("gen_svg");
my $dbh = get_dbh();

my $svg_dir = "/var/www/htdocs/pricechart/svg";
mkdir $svg_dir;

my ($width, $height) = (900, 160);
my ($margin_left, $margin_right) = (30, 70);
my ($margin_top, $margin_bottom) = (20, 20);
my $total_width = $width + $margin_right + $margin_left;
my $total_height = $height + $margin_top + $margin_bottom;

my $sql = "select date, price from prices where " .
	"part_num = ? and vendor = ? order by date";
my $point_sth = $dbh->prepare($sql);

$sql = "select distinct vendor from prices where part_num = ?";
my $vendor_sth = $dbh->prepare($sql);

my $parts_sth = $dbh->prepare("select part_num, description from products");
$parts_sth->execute();
while (my ($part_num, $description) = $parts_sth->fetchrow_array()) {

	$sql = "select min(date), max(date), min(price), max(price) " .
		"from prices where part_num = ?";
	my ($x_min, $x_max, $y_min, $y_max) =
		$dbh->selectrow_array($sql, undef, $part_num);
	next unless (defined $x_min);

	my ($domain, $range) = ($x_max - $x_min, $y_max - $y_min);
	next if ($domain == 0 || $range == 0);

	print "$part_num:\n" if ($args{v});

	my $svg = SVG->new(viewBox => "0 0 $total_width $total_height");
	my ($x_scale, $y_scale) = ($width / $domain, $height / $range);

	$vendor_sth->execute($part_num);
	while (my ($vendor) = $vendor_sth->fetchrow_array()) {
		print "\t$vendor: " if ($args{v});

		$sql = "select color from vendors where name = ?";
		my ($vendor_color) = $dbh->selectrow_array($sql, undef, $vendor);

		my (@xs, @ys);
		$point_sth->execute($part_num, $vendor);
		while (my ($date, $price) = $point_sth->fetchrow_array) {
			push @xs, ($date - $x_min) * $x_scale + $margin_left;
			push @ys, ($price - $y_min) * $y_scale + $margin_top;

			$svg->circle(
				cx => $xs[-1], cy => $ys[-1],
				r => 2,
				style => {
					"fill" => $vendor_color,
					"stroke" => $vendor_color
				}
			);
		}
		printf "%i data points\n", scalar @xs if ($args{v});

		my $px = compute_control_points(\@xs);
		my $py = compute_control_points(\@ys);
		my $p;
		for (0..(scalar @xs - 2)) {
			$p .= sprintf("M %f %f C %f %f %f %f %f %f ",
				$xs[$_], $ys[$_],
				$px->{"p1"}[$_], $py->{"p1"}[$_],
				$px->{"p2"}[$_], $py->{"p2"}[$_],
				$xs[$_ + 1], $ys[$_ + 1]
			);
		}
		$svg->path(
			d => $p,
			id => $vendor,
			style => {
				"fill-opacity" => 0,
				fill => $vendor_color,
				stroke => $vendor_color,
				"stroke-width" => 2,
			}
		);
	}

	my $mask = $svg->rectangle(
		x => 0, y => 0,
		width => 1000, height => 250,
		rx => 0, ry => 0,
		id => "mask",
		fill => "#FFF",
	);
	$mask->animate(
		attributeName => "x",
		values => "0;1000",
		dur => "0.8s",
		fill => "freeze",
	);

	my $num_labels = 5;
	for (0..$num_labels) {
		my $price = $y_max - $range * $_ / $num_labels;
		my $y = $margin_top + $height * $_ / $num_labels;

		$svg->text(
			id => $_,
			x => $margin_left + $width + 20,
			y => $y,
			style => "font-size: 14px; fill: #666",
			"text-anchor" => "start"
		)->cdata("\$$price");

		$svg->line(
			id => "line_$_",
			x1 => $margin_left, y1 => $y,
			x2 => $total_width - $margin_right, y2 => $y,
			fill => "#CCC",
			stroke => "#CCC",
			"stroke-width" => 1,
		);
	}

	for (0..$num_labels) {
		my $time = $x_min + $_ * $domain / $num_labels;
		my $date = strftime "%b %e %Y", localtime($time);
		my $x = $margin_left + $_ / $num_labels * $width;

		$svg->text(
			id => "time_$time",
			x => $x, y => $total_height,
			style => "font-size: 14px; fill: #666",
			"text-anchor" => "middle"
		)->cdata($date);

		$svg->line(
			id => "date_marker_$_",
			x1 => $x, y1 => $margin_top + $height,
			x2 => $x, y2 => $margin_top + $height + 5,
			fill => "#CCC",
			stroke => "#CCC",
			"stroke-width" => 1,
		);
	}

	open my $svg_fh, ">", "$svg_dir/$part_num.svg" or die $!;
	print $svg_fh $svg->xmlify;
	close $svg_fh;
}

# print $log @$part_nums . " products generated\n";

# close $log;
$dbh->disconnect();

# shamefully ported javascript from
# http://www.particleincell.com/wp-content/uploads/2012/06/bezier-spline.js
sub compute_control_points
{
	my $K = shift;
	my $n = @$K - 1;

	my (@p1, @p2);
	my (@a, @b, @c, @r);

	# left segment
	$a[0] = 0;
	$b[0] = 2;
	$c[0] = 1;
	$r[0] = $K->[0] + 2 * $K->[1];

	# internal segments
	for (1..($n - 2)) {
		$a[$_] = 1;
		$b[$_] = 4;
		$c[$_] = 1;
		$r[$_] = 4 * $K->[$_] + 2 * $K->[$_ + 1];
	}

	# right segment
	$a[$n - 1] = 2;
	$b[$n - 1] = 7;
	$c[$n - 1] = 0;
	$r[$n - 1] = 8 * $K->[$n - 1] + $K->[$n];

	# solves Ax=b with the Thomas algorithm
	for (1..($n - 1)) {
		my $m = $a[$_] / $b[$_ - 1];
		$b[$_] = $b[$_] - $m * $c[$_ - 1];
		$r[$_] = $r[$_] - $m * $r[$_ - 1];
	}

	$p1[$n - 1] = $r[$n - 1] / $b[$n - 1];
	for (reverse(0..($n - 2))) {
		$p1[$_] = ($r[$_] - $c[$_] * $p1[$_ + 1]) / $b[$_];
	}

	for (0..($n - 2)) {
		$p2[$_] = 2 * $K->[$_ + 1] - $p1[$_ + 1];
	}
	$p2[$n - 1] = 0.5 * ($K->[$n] + $p1[$n - 1]);

	return {"p1" => \@p1, "p2" => \@p2};
}
