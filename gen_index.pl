#!/usr/bin/env perl

use strict;
use warnings;

use File::Copy;
use PriceChart;
use Template;


my $dbh = get_dbh();

my $config = {
	INTERPOLATE => 1,
	POST_CHOMP => 1,
	EVAL_PERL => 1,
	# XXX: this needs to be changed
	INCLUDE_PATH => "/home/kyle/src/pricechart/html",
	OUTPUT_PATH => "/var/www/htdocs/pricechart"
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
copy("html/pricechart.css", "/var/www/htdocs/pricechart/pricechart.css");

$dbh->disconnect();
