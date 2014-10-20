#!/usr/bin/env perl

use strict;
use warnings;

use GD::SVG;
use GD::Polyline;
use Template;
use POSIX;

use shared;

my $cfg = get_config();
my $dbh = get_dbh($cfg);
my $log = get_log($cfg, "pricecharts_webgen");

my $config = {
	INTERPOLATE => 1,
	POST_CHOMP => 1,
	EVAL_PERL => 1
};

my $template = Template->new($config);

my $query = "select distinct brand from products";
my $manuf = $dbh->selectcol_arrayref($query);

$query = "select part_num from products";
my $products = $dbh->selectcol_arrayref($query);

my @vendors = sort keys $cfg->{vendors};

my $vars = {
	vendors => \@vendors,
	manufacturers => scalar @$manuf,
	num_products => scalar @$products
};

my $input = "html/index.tt2";
$template->process($input, $vars, "www/htdocs/index.html") || die $template->error();

# $query = "select part_num from products";
# my $products = $dbh->selectcol_arrayref($query);

print $log strftime "%b %e %Y %H:%M ", localtime;

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

	my $image = new GD::SVG::Image(800, 200);
	my $polyline = new GD::Polyline;

	$query = "select * from prices where part_num = ?";
	my $prices = $dbh->selectall_arrayref($query, undef, $part_num);

	vprintf("\t# prices = %i\n", scalar @$prices);
}

close $log;
$dbh->disconnect();
