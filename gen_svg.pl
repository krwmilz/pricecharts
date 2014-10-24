#!/usr/bin/env perl

use strict;
use warnings;

use SVG;
use POSIX;

use shared;


my $log = get_log("pricechart_gen_svg");

my $svg_dir = "$cfg->{general}{var}/www/htdocs/svg";
mkdir $svg_dir;

my $query = "select part_num from products";
my $products = $dbh->selectcol_arrayref($query);


if ($args{p}) {
	gen_chart($args{p});
	print $log "$args{p} generated\n";
}
else {
	gen_chart($_) for (@$products);
	print $log @$products . " products generated\n";
}

sub gen_chart
{
	my $part_num = shift;
	vprint("$part_num:\n");

	$query = "select min(date) from prices where part_num = ?";
	my $x_min = $dbh->selectrow_array($query, undef, $part_num);

	$query = "select max(date) from prices where part_num = ?";
	my $x_max = $dbh->selectrow_array($query, undef, $part_num);

	$query = "select min(price) from prices where part_num = ?";
	my $y_min = $dbh->selectrow_array($query, undef, $part_num);

	$query = "select max(price) from prices where part_num = ?";
	my $y_max = $dbh->selectrow_array($query, undef, $part_num);

	vprintf("\tdomain: $x_min - $x_max\n");
	vprintf("\trange:  $y_min - $y_max\n");

	my $svg = SVG->new(viewBox => "0 0 1000 250");

	$query = "select distinct vendor from prices where part_num = ?";
	my $vendors = $dbh->selectcol_arrayref($query, undef, $part_num);
	vprintf("\tvendors: " . @$vendors . "\n");

	for (@$vendors) {
		vprintf("\t$_:\n");

		$query = "select date from prices where " .
			"part_num = ? and vendor = ? order by date";
		my $dates = $dbh->selectcol_arrayref($query, undef,
			$part_num, $_);
		vprintf("\t\tdates found: " . @$dates . "\n");
		$query = "select price from prices where " .
			"part_num = ? and vendor = ? order by date";
		my $prices = $dbh->selectcol_arrayref($query, undef,
			$part_num, $_);
		vprintf("\t\tprices found: " . @$prices . "\n");

		my @xs = map { ($_ - $x_min) / ($x_max - $x_min) * 900 + 30 } @$dates;
		my @ys = map { ($_ - $y_min) / ($y_max - $y_min) * 210 + 20 } @$prices;

		my $vendor_color = "#$cfg->{vendors}{$_}{color}";

		my $i = 0;
		for (@xs) {
			$svg->circle(cx => $xs[$i], cy => $ys[$i], r => 2,
			style => {
				'fill-opacity' => 1,
				'fill' => $vendor_color,
				'stroke' => $vendor_color
			}
			);
			$i++;
		}

		my $points = $svg->get_path(x => \@xs, y => \@ys,
			-closed => "false");
		$svg->path(
			%$points,
			id => $_,
			style => {
				'fill-opacity' => 0,
				'fill' => $vendor_color,
				'stroke' => $vendor_color,
				'stroke-width' => 2,
			}
		);
	}

	for my $i (0..5) {
		my $price = $y_max - $i * ($y_max - $y_min) / 5;
		my $y = 20 + $i * (210 / 5);
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
		my $time = $x_min + $i * ($x_max - $x_min) / 5;
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
