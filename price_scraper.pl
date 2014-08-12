#!/usr/bin/env perl

use strict;
use warnings;

use Config::Grammar;
use Data::Dumper;
use DBI;
use File::Basename;
use Getopt::Std;
use HTML::Grabber;
use LWP::Simple;
use POSIX;


my %args;
getopts('df:i:np:v', \%args);

my $parser = Config::Grammar->new({
	_sections => ['vendors', 'paths'],
	vendors	=> {
		# vendor regular expression
		_sections => ['/[A-Za-z ]+/'],
		'/[A-Za-z ]+/' => {
			_vars => ['search_uri', 'reg_price', 'sale_price', 'color'],
		},
	},
	paths => {
		_vars => ['http', 'data', 'log'],
	},
});

my $cfg_file;
if ($args{f}) {
	$cfg_file = $args{f};
}
elsif (-e "/etc/price_scraper.cfg") {
	$cfg_file = "/etc/price_scraper.cfg";
}
elsif (-e "price_scraper.cfg") {
	$cfg_file = "price_scraper.cfg";
}

my $cfg = $parser->parse($cfg_file) or die "ERROR: $parser->{err}\n";

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
	open my $logfile, ">>", "$cfg->{paths}{log}" or die $!;
	select $logfile;
}

if ($args{d}) {
	print Dumper($cfg);
}
elsif ($args{p}) {
	scrape_vendors($args{p});
}
else {
	scrape_vendors();
}

sub scrape_vendors
{
	my $time_start = time;
	my @prices;

	my $results = $dbh->selectcol_arrayref("select part_num from products");
	# sequentially pick one product every hour
	my $index = (time / 3600) % scalar(@$results);
	my $part_no = $results->[$index];

	print strftime "%b %e %Y %H:%M ", localtime;
	printf "%-15s [", $part_no;

	my $ua = LWP::UserAgent->new(agent => 'Mozilla/5.0');
	# some sites need this (amazon I think?)
	$ua->default_header('Accept' => '*/*');

	while (my ($name, $vendor) = each ($cfg->{vendors})) {

		my $resp = $ua->get("$vendor->{search_uri}$part_no");
		if (! $resp->is_success) {
			print STDERR "$name: " . $resp->status_line . "\n";
			print ' ';
			next;
		}

		my $dom = HTML::Grabber->new(html => $resp->decoded_content);

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

		print substr($name, 0, 1);
		push @prices, "$name=$price";
	}

	print '] (' . (time - $time_start) . " s)\n";
	if ($args{v}) {
		print "$_\n" for @prices;
	}

	return if ($args{n} || (scalar @prices) == 0);

	mkdir $cfg->{paths}{data};
	open FILE, ">>", "$cfg->{paths}{data}/$part_no.txt" or die $!;
	print FILE time * 1000;
	print FILE "\t$_" for @prices;
	print FILE "\n";
	close FILE;
}
