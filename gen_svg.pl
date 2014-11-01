#!/usr/bin/env perl

use strict;
use warnings;

use List::Util qw(min max);
use SVG;
use POSIX;

use shared;


my $log = get_log("pricechart_gen_svg");

my $part_nums;
if ($args{p}) {
	$part_nums->[0] = $args{p};
	print $log "$args{p} generated\n";
}
else {
	my $query = "select part_num from products";
	$part_nums = $dbh->selectcol_arrayref($query);

	print $log @$part_nums . " products generated\n";
}

my $svg_dir = "$cfg->{general}{var}/www/htdocs/svg";
mkdir $svg_dir;

my ($width, $height) = (900, 210);
my ($margin_left, $margin_right) = (30, 70);
my ($margin_top, $margin_bottom) = (20, 20);
my $total_width = $width + $margin_right + $margin_left;
my $total_height = $height + $margin_top + $margin_bottom;

my $query = "select date, price from prices where " .
	"part_num = ? and vendor = ? order by date";
my $point_sth = $dbh->prepare($query);

$query = "select distinct vendor from prices where part_num = ?";
my $vendor_sth = $dbh->prepare($query);

for my $part_num (@$part_nums) {
	$query = "select distinct date from prices where part_num = ?";
	my $dates = $dbh->selectcol_arrayref($query, undef, $part_num);
	$query = "select distinct price from prices where part_num = ?";
	my $prices = $dbh->selectcol_arrayref($query, undef, $part_num);

	if (@$dates == 0 || @$dates == 1) {
		next;
	}

	vprint("$part_num:\n");

	my ($x_min, $x_max) = (min(@$dates), max(@$dates));
	my ($y_min, $y_max) = (min(@$prices), max(@$prices));

	vprintf("\tdomain: $x_min - $x_max\n");
	vprintf("\trange:  $y_min - $y_max\n");
	my $domain = $x_max - $x_min;
	my $range = $y_max - $y_min;
	my $x_scale = $width / $domain;
	my $y_scale = $height / $range;

	my $svg = SVG->new(viewBox => "0 0 $total_width $total_height");

	$vendor_sth->execute($part_num);
	while (my ($vendor) = $vendor_sth->fetchrow_array()) {
		vprintf("\t$vendor: ");
		my $vendor_color = "#$cfg->{vendors}{$vendor}{color}";

		my (@xs, @ys);
		$point_sth->execute($part_num, $vendor);
		while (my ($date, $price) = $point_sth->fetchrow_array) {
			push @xs, (($date - $x_min) * $x_scale + $margin_left);
			push @ys, (($price - $y_min) * $y_scale + $margin_top);

			$svg->circle(cx => $xs[-1], cy => $ys[-1], r => 2,
				style => {
					'fill-opacity' => 1,
					'fill' => $vendor_color,
					'stroke' => $vendor_color
				}
			);
		}
		vprintf(@xs . " data points\n");

		my $points = $svg->get_path(x => \@xs, y => \@ys,
			-closed => "false");
		$svg->path(
			%$points,
			id => $vendor,
			style => {
				'fill-opacity' => 0,
				'fill' => $vendor_color,
				'stroke' => $vendor_color,
				'stroke-width' => 2,
			}
		);
	}

	for my $i (0..5) {
		my $price = $y_max - $range * $i / 5;
		my $y = $margin_top + $height * $i / 5;
		$svg->text(id => $i, x => 950, y => $y,
			style => "font-size: 12px; fill: #666",
			"text-anchor" => "start")->cdata("\$$price");
		$svg->line(id => "line_$i", x1 => 30, y1 => $y,
			x2 => 930, y2 => $y,
				"fill" => "#CCC",
				"stroke" => "#CCC",
				"stroke-width" => 1,
			);
	}

	for my $i (0..5) {
		my $time = $x_min + $i * $domain / 5;
		my $date = strftime "%b %e %Y", localtime($time);
		my $x = 30 + $i * 900 / 5;
		$svg->text(id => $time, x => $x, y => 250,
			style => "font-size: 12px; fill: #666",
			"text-anchor" => "middle")->cdata($date);
	}

	open my $svg_fh, ">", "$svg_dir/$part_num.svg" or die $!;
	print $svg_fh $svg->xmlify;
	close $svg_fh;
}

close $log;
$dbh->disconnect();
