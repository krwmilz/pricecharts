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
my $ua  = get_ua($cfg->{"general"});
my $dbh = get_dbh($cfg->{"general"});

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

$dbh->do("create table if not exists prices(" .
	"date int not null, " .
	"part_num text not null, " .
	"vendor text not null, " .
	"price int not null, " .
	"color text not null, " .
	"duration int, " .
	"title text, " .
	"primary key(date, part_num, vendor, price))"
) or die $DBI::errstr;

print "info: $manufacturer $part_num\n" if ($args{v});

$sql = "insert into prices(date, part_num, vendor, color, price, duration) " .
	"values (?, ?, ?, ?, ?, ?)";
my $prices_sth = $dbh->prepare($sql);

$sql = "update products set last_seen = ? where part_num = ?";
my $products_sth = $dbh->prepare($sql);

my ($start, @status, $i) = (time, "", -1);
while (my ($vendor, $props) = each %{$cfg->{"vendors"}}) {
	my $url =	$props->{"search_url"};
	my $color =	$props->{"color"};
	my $price_tag =	$props->{"price_regular"};
	my $sale_tag =	$props->{"price_sale"};
	my $title_tag = $props->{"title"};

	my $vendor_start = time;
	$status[++$i] = " ";

	print "info: $vendor\n" if ($args{v});

	# for products with short part numbers, also search manufacturer
	my $search;
	if (length($part_num) < 6) {
		$search = uri_escape("$manufacturer $part_num");
	} else {
		$search = uri_escape($part_num);
	}

	# get a page of search results from a vendor
	my $search_results = get_dom($url . $search, $ua, $args{v});
	next unless defined $search_results;

	# search search_results for particular html tags that should be prices
	my $price_r = get_valid_price($price_tag, $search_results, $vendor);
	my $price_s = get_valid_price($sale_tag,  $search_results, $vendor);
	next unless ($price_r || $price_s);

	# choose the lowest that exists
	my $price;
	$price = $price_r if ($price_r);
	$price = $price_s if ($price_s);
	$price = min($price_r, $price_s) if ($price_r && $price_s);

	# scrape and display title, don't do anything with it yet
	my $title = $search_results->find($title_tag)->text();
	$title =~ s/^\s+//;
	$title =~ s/\s+$//;
	print "info: $vendor: title = $title\n" if ($args{v});

	# everything looks good
	$status[$i] = substr($vendor, 0, 1);
	print "info: $vendor: final = \$$price\n" if ($args{v});

	next if ($args{n});
	$prices_sth->execute($start, $part_num, $vendor, $color,
		$price, time - $vendor_start);
	$products_sth->execute($start, $part_num);

	print "info: $vendor: db updated\n" if ($args{v});
}

printf $log "%s %-10s %-15s [%s] (%i s)\n", strftime("%F %T", localtime),
	$manufacturer, $part_num, join("", @status), time - $start;

close $log;

# record that we finished scraping this product
$dbh->do("update products set last_scraped = ? where part_num = ?",
	undef, time, $part_num);

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
	# XXX: uses the first found price in the page
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
