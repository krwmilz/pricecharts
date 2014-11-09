#!/usr/bin/env perl

use strict;
use warnings;

use SVG;
use POSIX;

use shared;

#
# Spline code here:
# http://www.particleincell.com/wp-content/uploads/2012/06/bezier-spline.js
#

# my $log = get_log("gen_svg");

my $svg_dir = "/var/www/htdocs/pricechart/svg";
mkdir $svg_dir;

my ($width, $height) = (900, 210);
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

	my $domain = $x_max - $x_min;
	my $range = $y_max - $y_min;
	next if ($domain == 0);
	next if ($range == 0);

	vprint("$part_num:\n");
	vprint("\tdomain: $x_min - $x_max\n");
	vprint("\trange:  $y_min - $y_max\n");

	my $x_scale = $width / $domain;
	my $y_scale = $height / $range;

	my $svg = SVG->new(viewBox => "0 0 $total_width $total_height");

	$vendor_sth->execute($part_num);
	while (my ($vendor) = $vendor_sth->fetchrow_array()) {
		vprintf("\t$vendor: ");

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
		vprintf(@xs . " data points\n");

		my $points = $svg->get_path(x => \@xs, y => \@ys);
		$svg->path(
			%$points,
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
		dur => "1s",
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
			style => "font-size: 12px; fill: #666",
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
			style => "font-size: 12px; fill: #666",
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

close $log;
$dbh->disconnect();
