#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use DBI;
use Getopt::Std;
use HTML::Grabber;
use LWP::Simple;
use POSIX;

use shared;


my %args;
getopts('f:np:v', \%args);

my $cfg = get_config($args{f});
my $dbh = get_dbh($cfg);
my $ua  = get_ua($cfg);

$| = 1 if ($args{v});

open my $log, ">>", "$cfg->{general}{log_file}" or die $!;

my $part_num;
if ($args{p}) {
	$part_num = $args{p};
}
else {
	my $results = $dbh->selectcol_arrayref("select part_num from products " .
	"order by last_scraped asc");
	if (scalar $results == 0) {
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
	"primary key(date, part_num, vendor, price))");

print $log strftime "%b %e %Y %H:%M ", localtime;
printf $log "%-15s [", $part_num;

print "$part_num\n" if ($args{v});

my $date = time;
for (sort keys $cfg->{vendors}) {
	my $start = time;
	my $vendor = $cfg->{vendors}{$_};

	printf "%-15s ", "$_:" if ($args{v});

	my $dom = get_dom("$vendor->{search_uri}$part_num", $ua);
	next if (!defined $dom);

	#if (substr($vendor->{context}, 0, 1) eq '@') {
	#	$vendor->{context} =~ s/@/#/;
	#}

	#my $context = $dom->find($vendor->{context})->html();
	#if ($context) {
	#	$dom = HTML::Grabber->new(html => $context);
	#}
	#else {
	#	print ' ';
	#	next;
	#}

	my $price = $dom->find($vendor->{reg_price})->text;
	if ($vendor->{sale_price}) {
		my $sale = $dom->find($vendor->{sale_price})->text;
		$price = $sale if ($sale ne '');
	}

	if (! $price) {
		print $log " ";
		print "\n" if ($args{v});
		next;
	}

	($price) = ($price =~ m/(\d[\d,]+)/);
	$price =~ s/,//;

	print $log substr($_, 0, 1);
	printf "\$%i\n", $price if ($args{v});

	next if ($args{n});

	$dbh->do("insert into prices(date, part_num, vendor, price, duration)" .
	       "values (?, ?, ?, ?, ?)",
		undef, $date, $part_num, $_, $price, time - $start);
}

my $duration = time - $date;
print $log "] ($duration s)\n";

close $log;
$dbh->disconnect();
