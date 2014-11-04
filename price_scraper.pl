#!/usr/bin/env perl

use strict;
use warnings;

use shared;


my $ua  = get_ua();

my $part_num;
if ($args{p}) {
	$part_num = $args{p};
}
else {
	my $cutoff = time - (30 * 24 * 60 * 60);
	my $results = $dbh->selectrow_arrayref("select part_num from products " .
	"where last_seen > $cutoff order by last_scraped asc");
	if (! @$results) {
		print "Product table empty, run product_scraper.pl\n";
		exit;
	}
	$part_num = $results->[0];
	$dbh->do("update products set last_scraped = ? where part_num = ?",
		undef, time, $part_num);
}

$dbh->do("create table if not exists prices(" .
	"date int not null, " .
	"part_num text not null, " .
	"vendor text not null, " .
	"price int not null, " .
	"duration int, " .
	"primary key(date, part_num, vendor, price))") or die $DBI::errstr;

my $log = get_log("pricechart_scrapes");
printf $log "%-15s [", $part_num;

vprint("$part_num\n");

my $qry = "insert into prices(date, part_num, vendor, price, duration) " .
	"values (?, ?, ?, ?, ?)";
my $prices_sth = $dbh->prepare($qry);

$qry = "update products set last_seen = ? where part_num = ?";
my $products_sth = $dbh->prepare($qry);

my $date = time;
for (sort keys $cfg->{vendors}) {
	my $start = time;
	my $vendor = $cfg->{vendors}{$_};

	vprint("$_:\n");

	my $dom = get_dom("$vendor->{search_uri}$part_num", $ua);
	if (!defined $dom) {
		msg("e", "error: dom");
		next;
	}

	my $price = get_price($vendor->{"reg_price"}, $dom);
	if ($vendor->{sale_price}) {
		my $sale_price = get_price($vendor->{"sale_price"}, $dom);
		$price = $sale_price if (defined $sale_price);
	}
	if (! $price) {
		msg(" ", "error: price not found");
		next;
	}

	my @prices = ($price =~ m/(\d[\d,]+)/);
	if (@prices != 1) {
		msg("r", "error: too many regex matches: " . @prices);
		next;
	}

	$price = $prices[0];
	$price =~ s/,//;
	if ($price <= 0 || $price > 10000) {
		msg("o", "error: price \$$price out of range");
		next;
	}

	msg(substr($_, 0, 1), "price = \$$price");

	next if ($args{n});

	$prices_sth->execute($date, $part_num, $_, $price, time - $start);
	$products_sth->execute($date, $part_num);

	vprint("\tdb updated\n");
}

my $duration = time - $date;
print $log "] ($duration s)\n";

close $log;
$dbh->disconnect();

sub get_price
{
	my $dom_element = shift;
	my $dom = shift;

	my @prices = $dom->find($dom_element)->text_array();
	vprintf("\t%s = %i\n", $dom_element, scalar @prices);

	return $prices[0];
}

sub msg
{
	my $log_char = shift;
	my $verbose_msg = shift;

	print $log $log_char;
	vprint("\t$verbose_msg\n");
}
