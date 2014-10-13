#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use DBI;
use Getopt::Std;
use HTML::Grabber;
use LWP::Simple;
use Shared;
use POSIX;


my %args;
getopts('f:np:v', \%args);

my $cfg = get_config($args{f});

my $dbh = DBI->connect(
	"dbi:SQLite:dbname=$cfg->{general}{db_file}",
	"",
	"",
	{ RaiseError => 1 },) or die $DBI::errstr;

$| = 1 if ($args{v});

open my $log, ">>", "$cfg->{general}{log_file}" or die $!;

my $part_no;
if ($args{p}) {
	$part_no = $args{p};
}
else {
	my $results = $dbh->selectcol_arrayref("select part_num from products");
	# sequentially pick one product every hour
	my $index = (time / 3600) % scalar(@$results);
	$part_no = $results->[$index];
}

$dbh->do("create table if not exists prices(" .
	"date int not null, " .
	"part_no text not null, " .
	"vendor text not null, " .
	"price int not null, " .
	"duration int, " .
	"primary key(date, part_no, vendor, price))");

my $ua = LWP::UserAgent->new(agent => $cfg->{general}{user_agent});
$ua->default_header('Accept' => '*/*');

print $log strftime "%b %e %Y %H:%M ", localtime;
printf $log "%-15s [", $part_no;

print "$part_no:\n" if ($args{v});

my $date = time;
for (sort keys $cfg->{vendors}) {
	my $start = time;
	my $vendor = $cfg->{vendors}{$_};

	printf "%-15s: ", $_ if ($args{v});

	my $dom = get_dom("$vendor->{search_uri}$part_no", $ua);
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

	$dbh->do("insert into prices(date, part_no, vendor, price, duration)" .
	       "values (?, ?, ?, ?, ?)",
		undef, $date, $part_no, $_, $price, time - $start);
}

my $duration = time - $date;
print $log "] ($duration s)\n";

close $log;
$dbh->disconnect();
