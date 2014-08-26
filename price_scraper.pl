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

my $ua = LWP::UserAgent->new(agent => $cfg->{general}{user_agent});
$ua->default_header('Accept' => '*/*');

print $log strftime "%b %e %Y %H:%M ", localtime;
printf $log "%-15s [", $part_no;

print "$part_no:\n" if ($args{v});

my $time_start = time;
my %prices;
for (sort keys $cfg->{vendors}) {
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
	$prices{"\"$_\""} = $price;

	printf "\$%i\n", $price if ($args{v});
}

my $duration = time - $time_start;
print $log "] ($duration s)\n";

close $log;

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
