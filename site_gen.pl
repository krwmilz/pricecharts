#!/usr/bin/env perl

use strict;
use warnings;

use File::Copy;
use SVG;
use Template;
use POSIX;

use shared;

my $cfg = get_config();
my $dbh = get_dbh($cfg);
my $log = get_log($cfg, "pricecharts_webgen");

my $config = {
	INTERPOLATE => 1,
	POST_CHOMP => 1,
	EVAL_PERL => 1,
	INCLUDE_PATH => "html",
	OUTPUT_PATH => "www/htdocs"
};

my $template = Template->new($config);

my $query = "select distinct brand from products";
my $manuf = $dbh->selectcol_arrayref($query);

$query = "select part_num from products";
my $products = $dbh->selectcol_arrayref($query);

my $vendors = keys $cfg->{vendors};

my $vars = {
	num_vendors => $vendors,
	num_manufacturers => scalar @$manuf,
	num_products => scalar @$products
};

$template->process("index.html", $vars, "index.html") || die $template->error();
copy("html/pricechart.css", "www/htdocs/pricechart.css");

# $query = "select part_num from products";
# my $products = $dbh->selectcol_arrayref($query);

print $log strftime "%b %e %Y %H:%M ", localtime;

my $svg_dir = "$cfg->{general}{var}/www/htdocs/svg";
mkdir $svg_dir;

if ($args{p}) {
	gen_chart($args{p});
	print $log "$args{p} generated\n";
}
else {
	gen_chart($_) for (@$products);
	print $log scalar(@$products) . " products generated\n";
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

	my $svg = SVG->new(width => 800, height => 200);

	$query = "select distinct vendor from prices where part_num = ?";
	my $vendors = $dbh->selectcol_arrayref($query, undef, $part_num);
	vprintf("\tvendors: ");

	for (@$vendors) {
		$query = "select date from prices where " .
			"part_num = ? and vendor = ? order by date";
		my $dates = $dbh->selectcol_arrayref($query, undef,
			$part_num, $_);
		vprintf("\tdates found: " . scalar @$dates . "\n");
		$query = "select price from prices where " .
			"part_num = ? and vendor = ? order by date";
		my $prices = $dbh->selectcol_arrayref($query, undef,
			$part_num, $_);
		vprintf("\tprices found: " . scalar @$prices . "\n");

		my $points = $svg->get_path(x => $dates, y => $prices,
			-closed => "false");

		$svg->path(
			%$points,
			id => $_,
			style => {
				'fill-opacity' => 0,
				'fill' => 'green',
				'stroke' => 'rgb(250, 123, 123)'
			}
		);
	}

	$svg->text(id => 'l1', x => 10, y => 30)->cdata($part_num);

	open my $svg_fh, ">", "$svg_dir/$part_num.svg" or die $!;
	print $svg_fh $svg->xmlify;
	close $svg_fh;
}

close $log;
$dbh->disconnect();
