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
	"dbi:SQLite:dbname=pricechart.db",
	"",
	"",
	{ RaiseError => 1 },) or die $DBI::errstr;

if ($args{v}) {
	# Disable buffering on STDOUT
	$| = 1;
	select STDOUT;
}
else {
	open my $logfile, ">>", "$cfg->{general}{log_path}" or die $!;
	select $logfile;
}

my $time_start = time;
my %prices;

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

print strftime "%b %e %Y %H:%M ", localtime;
printf "%-15s [", $part_no;

my $ua = LWP::UserAgent->new(agent => $cfg->{general}{user_agent});
$ua->default_header('Accept' => '*/*');

for (sort keys $cfg->{vendors}) {
	my $vendor = $cfg->{vendors}{$_};
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
		print ' ';
		next;
	}

	($price) = ($price =~ m/(\d[\d,]+)/);
	$price =~ s/,//;

	print substr($_, 0, 1);
	$prices{"\"$_\""} = $price;
}

my $duration = time - $time_start;
print "] ($duration s)\n";
if ($args{v}) {
	print "$_: $prices{$_}\n" for (keys %prices);
}

if ($args{n} || (scalar(keys %prices)) == 0) {
	$dbh->disconnect();
	exit;
}

$dbh->do("create table if not exists [$part_no]" .
	"(date int not null primary key, duration int)");

my $sth = $dbh->prepare("select * from [$part_no]");
my @columns = @{$sth->{NAME}};
for my $vendor (keys %prices) {
	next if (grep {"\"$_\"" eq $vendor} @columns);
	$dbh->do("alter table [$part_no] add column $vendor");
}
$dbh->do("insert into [$part_no](date, duration, " .
	join(", ", keys %prices) . ") " .
	"values ($time_start, $duration, " .
	join(", ", values %prices) . ")");

$dbh->disconnect();
