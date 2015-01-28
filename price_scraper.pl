#!/usr/bin/env perl

use strict;
use warnings;

use Config::Grammar;
use Getopt::Std;
use HTML::Grabber;
use List::Util qw(min);
use LWP::Simple;
use PriceChart;
use POSIX;
use URI::Escape;


my %args;
getopts("m:np:v", \%args);

$| = 1 if ($args{v});

my $log = get_log("scrapes", $args{v});
my $cfg = get_config();
my $ua  = get_ua($cfg);
my $dbh = get_dbh();

# allow products to go out of stock. if we haven't seen them for > 30 days
# chances are retailers aren't carrying them anymore
my $cutoff = time - (30 * 24 * 60 * 60);
my $sql = "select part_num, manufacturer from products " .
	"where last_seen > $cutoff order by last_scraped asc";
my ($part_num, $manufacturer) = $dbh->selectrow_array($sql);
if ($args{p} && $args{m}) {
	$part_num = $args{p};
	$manufacturer = $args{m};
}
exit unless (defined $part_num);

# keep track of when we last tried to scrape this product
$dbh->do("update products set last_scraped = ? where part_num = ?",
	undef, time, $part_num);

$dbh->do("create table if not exists prices(" .
	"date int not null, " .
	"part_num text not null, " .
	"vendor text not null, " .
	"price int not null, " .
	"duration int, " .
	"primary key(date, part_num, vendor, price))"
) or die $DBI::errstr;


print "info: $manufacturer $part_num\n" if ($args{v});

$sql = "insert into prices(date, part_num, vendor, price, duration) " .
	"values (?, ?, ?, ?, ?)";
my $prices_sth = $dbh->prepare($sql);

$sql = "update products set last_seen = ? where part_num = ?";
my $products_sth = $dbh->prepare($sql);

$sql = "select * from vendors order by name";
my $vendor_sth = $dbh->prepare($sql);

my ($start, @status, $i) = (time, "", -1);
$vendor_sth->execute();
while (my ($vendor, $url, $price_tag, $sale_tag) = $vendor_sth->fetchrow_array) {
	my $vendor_start = time;
	$status[++$i] = " ";

	# for products with short part numbers, also search manufacturer
	my $search;
	if (length($part_num) < 6) {
		$search = uri_escape("$manufacturer $part_num");
	} else {
		$search = uri_escape($part_num);
	}

	# get a page of search results from a vendor
	my $search_results = get_dom($url . $search, $ua, $args{v});
	if (!defined $search_results) {
		print $log "error: $vendor: couldn't GET search results\n";
		next;
	}

	# search search_results for particular html tags that should be prices
	my $price_r = get_valid_price($price_tag, $search_results, $vendor);
	my $price_s = get_valid_price($sale_tag,  $search_results, $vendor);
	next unless ($price_r || $price_s);

	# choose the lowest that exists
	my $price;
	$price = $price_r if ($price_r);
	$price = $price_s if ($price_s);
	$price = min($price_r, $price_s) if ($price_r && $price_s);

	# everything looks good
	$status[$i] = substr($vendor, 0, 1);
	print "info: $vendor: final = \$$price\n" if ($args{v});

	next if ($args{n});
	$prices_sth->execute($start, $part_num, $vendor, $price, time - $vendor_start);
	$products_sth->execute($start, $part_num);

	print "info: $vendor: db updated\n" if ($args{v});
}

printf $log "%s %-10s %-15s [%s] (%i s)\n", strftime("%F %T", localtime),
	$manufacturer, $part_num, join("", @status), time - $start;

close $log;
$dbh->disconnect();

exit 0;

sub get_valid_price
{
	my $dom_tag = shift;
	my $search_results = shift;
	my $vendor = shift;
	return undef unless (defined $dom_tag);

	# break the search_results page down into individual results
	my @search_prices = $search_results->find($dom_tag)->text_array();
	my $num_prices = @search_prices;
	return undef if ($num_prices == 0);

	print "info: $vendor: $dom_tag ($num_prices)\n" if ($args{v});

	# do a fuzzy search for digit combinations that look like a price
	# XXX: use the first found price in the page
	my ($price, @others) = ($search_prices[0] =~ m/(\d[\d,]+)/);
	return undef unless defined $price;

	# print total regex matches we had above
	$num_prices = @others + 1;
	print "info: $vendor: $dom_tag" . "[0] ($num_prices)\n" if ($args{v});
	return undef if (@others);

	# sanity check on the numerical value of the price
	$price =~ s/,//;
	if ($price <= 0 || $price > 10000) {
		print $log "error: $vendor: price \$$price out of range\n";
		return undef;
	}

	print "info: $vendor: $dom_tag" . "[0]: \$$price\n" if ($args{v});
	return $price;
}
