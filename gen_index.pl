#!/usr/bin/env perl

use strict;
use warnings;

use File::Copy;
use Template;

use shared;


my $config = {
	INTERPOLATE => 1,
	POST_CHOMP => 1,
	EVAL_PERL => 1,
	INCLUDE_PATH => "html",
	OUTPUT_PATH => "www/htdocs"
};

my $template = Template->new($config);

my $query = "select distinct manufacturer from products";
my $manuf = $dbh->selectcol_arrayref($query);

$query = "select part_num from products";
my $products = $dbh->selectcol_arrayref($query);

$query = "select count(name) from vendors";
my @vendors = $dbh->selectrow_array($query);

my $vars = {
	num_vendors => $vendors[0],
	num_manufacturers => scalar @$manuf,
	num_products => scalar @$products
};

$template->process("index.html", $vars, "index.html") || die $template->error();
copy("html/pricechart.css", "www/htdocs/pricechart.css");

$dbh->disconnect();
