#!/usr/bin/env perl

use strict;
use warnings;

use File::Copy;
use Template;

use shared;


my $cfg = get_config();
my $dbh = get_dbh($cfg);

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

$dbh->disconnect();
