#!/usr/bin/env perl

use strict;
use warnings;

use Config::Grammar;
use Getopt::Std;
use File::Copy;
use PriceChart;
use Template;


my %args;
getopts("v", \%args);

$| = 1 if ($args{v});

my $cfg = get_config();
my $dbh = get_dbh($cfg->{"general"});

my $http_cfg = $cfg->{"http"};
my $include = $http_cfg->{"chroot"} . $http_cfg->{"templates"};
my $output =  $http_cfg->{"chroot"} . $http_cfg->{"htdocs"};

print "info: including from: $include\n" if ($args{v});
print "info: outputting to:  $output\n" if ($args{v});

my $config = {
	INTERPOLATE => 1,
	POST_CHOMP => 1,
	EVAL_PERL => 1,
	INCLUDE_PATH => $include,
	OUTPUT_PATH => $output
};
my $template = Template->new($config);

my $query = "select count(distinct manufacturer) from products";
my ($manufacturers) = $dbh->selectrow_array($query);
print "info: $manufacturers manufacturers\n" if ($args{v});

$query = "select count(part_num) from products";
my ($products) = $dbh->selectrow_array($query);
print "info: $products products\n" if ($args{v});

$query = "select count(distinct vendor) from prices";
my ($vendors) = $dbh->selectrow_array($query);
print "info: $vendors vendors\n" if ($args{v});

my $time = time - (7 * 24 * 60 * 60);
$query = "select count(part_num) from products where first_seen > ?";
my ($new_products) = $dbh->selectrow_array($query, undef, $time);
print "info: $new_products new products (1 week)\n" if ($args{v});

my $vars = {
	num_vendors => $vendors,
	num_manufacturers => $manufacturers,
	num_products => $products,
	new_products => $new_products
};

$template->process("index.html", $vars, "index.html") || die $template->error() . "\n";
copy("$include/pricechart.css", "$output/pricechart.css");
print "info: $include/pricechart.css -> $output/\n" if ($args{v});

$dbh->disconnect();
