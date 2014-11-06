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

my $query = "select count(distinct manufacturer) from products";
my ($manufacturers) = $dbh->selectrow_array($query);

$query = "select count(part_num) from products";
my ($products) = $dbh->selectrow_array($query);

$query = "select count(name) from vendors";
my ($vendors) = $dbh->selectrow_array($query);

my $vars = {
	num_vendors => $vendors,
	num_manufacturers => $manufacturers,
	num_products => $products
};

$template->process("index.html", $vars, "index.html") || die $template->error();
copy("html/pricechart.css", "www/htdocs/pricechart.css");

$dbh->disconnect();
