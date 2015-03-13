#!/usr/bin/env perl

use strict;
use warnings;

use Config::Grammar;
use Getopt::Std;
use HTML::Grabber;
use IO::Tee;
use List::Util qw(min);
use LWP::Simple;
use PriceChart;
use POSIX;
use Term::ReadKey;
use URI::Escape;


my %args;
getopts("m:np:v", \%args);

$| = 1 if ($args{v});

my $cfg = get_config();
my $log = get_log($cfg->{"http"}, "price_scrapes.txt", $args{v});
my $ua  = new_ua($cfg->{"general"}, $args{v});
my $dbh = get_dbh($cfg->{"general"}, undef, $args{v});

# allow products to go out of stock. if we haven't seen them for > 30 days
# chances are retailers aren't carrying them anymore
my $cutoff = time - (30 * 24 * 60 * 60);
my $sql = "select part_num, manufacturer from products " .
	"where last_seen > $cutoff order by last_scraped asc";
my ($part_num, $manufacturer) = $dbh->selectrow_array($sql);

# prevent races with other scrapers, claim ownership as soon as possible
$dbh->do("update products set last_scraped = ? where part_num = ?",
	undef, time, $part_num);

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

print "info: scraping $manufacturer $part_num\n" if ($args{v});

$sql = "insert into prices(date, part_num, vendor, color, price, duration, title) " .
	"values (?, ?, ?, ?, ?, ?, ?)";
my $prices_sth = $dbh->prepare($sql);

$sql = "update products set last_seen = ? where part_num = ?";
my $products_sth = $dbh->prepare($sql);

my $timestamp = strftime("%F %T", localtime);
my ($start, @status, $i) = (time, "", -1);
for my $vendor (sort keys %{$cfg->{"vendors"}}) {
	my %props =	%{$cfg->{"vendors"}{$vendor}};
	# this could probably be done smarter
	my $url =	$props{"search_url"};
	my $color =	$props{"color"};
	my $price_tag =	$props{"price_regular"};
	my $sale_tag =	$props{"price_sale"};
	my $desc_tag =  $props{"title"};

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

	my $desc = "";
	if ($desc_tag) {
		# scrape description
		$desc = $search_results->find($desc_tag)->text();
		$desc =~ s/^\s+//;
		$desc =~ s/\s+$//;
		if ($desc ne "" && $args{v}) {
			my $desc_s = trunc_line($desc, length($vendor) + 8);
			print "info: $vendor: $desc_s\n";
		}
	}

	# everything looks good
	$status[$i] = substr($vendor, 0, 1);

	next if ($args{n});
	$prices_sth->execute($start, $part_num, $vendor, $color,
		$price, time - $vendor_start, $desc);
	$products_sth->execute($start, $part_num);

	print "info: $vendor: db: inserted \$$price\n" if ($args{v});
}

printf $log "%s %-10s %-20s [%s] (%i s)\n", $timestamp, $manufacturer,
	$part_num, join("", @status), time - $start;

$log->close();
$prices_sth = undef;
$products_sth = undef;
$dbh->disconnect();

exit 0;

sub get_valid_price
{
	my $dom_tag = shift || return undef;
	my $search_results = shift;
	my $vendor = shift;

	# break the search_results page down into individual results
	my @search_prices = $search_results->find($dom_tag)->text_array();
	my $num_prices = @search_prices;
	return undef if ($num_prices == 0);

	print "info: $vendor: $dom_tag ($num_prices)\n" if ($args{v});

	# do a fuzzy search for digit combinations that look like a price
	# XXX: uses the first found price in the page
	# XXX: this does not work on single digit prices, ie $7.00
	my ($price, @others) = ($search_prices[0] =~ m/(\d[\d,]+)/);
	return undef unless defined $price;

	# print total regex matches we had above
	$num_prices = @others + 1;
	print "info: $vendor: $dom_tag" . "[0] ($num_prices)\n" if ($args{v});
	return undef if (@others);

	# sanity check the numerical price value
	$price =~ s/,//;
	if ($price <= 0 || $price > 10000) {
		print $log "error: $vendor: price $price out of range\n";
		return undef;
	}

	print "info: $vendor: $dom_tag" . "[0]: \$$price\n" if ($args{v});
	return $price;
}
