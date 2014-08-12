#!/usr/bin/env perl

use strict;
use warnings;

use Config::Grammar;
use Data::Dumper;
use DBI;
use File::Basename;
use Getopt::Std;
use JSON;
use HTML::Grabber;
use LWP::Simple;
use POSIX;


my %args;
getopts('adf:i:np:rv', \%args);

my $parser = Config::Grammar->new({
	_sections => ['products', 'vendors', 'paths'],
	products => {
		# manufacturer regular expression
		_sections => ['/[A-Za-z]+/'],
		'/[A-Za-z]+/' => {
			# part number regular expression
			_sections => ['/[A-Za-z0-9]+/'],
			'/[A-Za-z0-9]+/' => {
			},
		},
	},
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

if ($args{a}) {
	scrape_vendors($_) for (make_parts_list());
	regenerate_json();
}
elsif ($args{d}) {
	print Dumper($cfg);
}
elsif ($args{p}) {
	scrape_vendors($args{p});
}
elsif ($args{r}) {
	regenerate_json();
}
else {
	srand;
	my @parts = make_parts_list();
	scrape_vendors($parts[rand @parts]);
	regenerate_json();
}

sub make_parts_list
{
	my @parts;
	for (sort keys $cfg->{products}) {
		push @parts, sort keys $cfg->{products}{$_};
	}
	return @parts;
}

sub scrape_vendors
{
	my $time_start = time;
	my @prices;

	my $sth = $dbh->prepare("select part_num from products");
	$sth->execute();
	my @results = $sth->fetchrow_array();
	# sequentially pick one product every hour
	my $index = (time / 3600) % scalar(@results);
	my $part_no = $results[$index];

	print strftime '%b %e %Y %H:%M ', localtime;
	printf '%-10s [', $part_no;

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

	#for (keys %title_dict) {
	#	print "$_ " if ($title_dict{$_} / $total_titles >= 0.5);
	#}
	#			for (split(" ", $title)) {
	#			if (! $title_dict{$_}) {
	#				$title_dict{$_} = 0;
	#			}
	#			$title_dict{$_}++;
	#		}
	#		$total_titles++;
	#print "\n";

	return if ($args{n} || (scalar @prices) == 0);

	mkdir $cfg->{paths}{data};
	open FILE, ">>", "$cfg->{paths}{data}/$part_no.txt" or die $!;
	print FILE time * 1000;
	print FILE "\t$_" for @prices;
	print FILE "\n";
	close FILE;
}

sub regenerate_json
{
	my $pretty = 0;
	$pretty = 1 if $args{v};

	mkdir "$cfg->{paths}{http}/json";

	my @manufacturers = sort keys $cfg->{products};
	open my $fh, '>', "$cfg->{paths}{http}/json/manufacturers.json" or die $!;
	print $fh to_json(\@manufacturers, {pretty => $pretty});
	close $fh;

	open $fh, '>', "$cfg->{paths}{http}/json/vendors.json" or die $!;
	print $fh to_json($cfg->{vendors}, {pretty => $pretty});
	close $fh;

	print "Regenerating... " if $args{v};

	my %parts;
	opendir(DIR, $cfg->{paths}{data});
	while (my $file = readdir(DIR)) {
	        next if ($file =~ m/^\./);

		my %part;
		my $part_num = basename($file, '.txt');
		print $part_num if ($args{v});

		my %tmp;
		open FILE, "<", "$cfg->{paths}{data}/$file" or die $!;
		while (<FILE>) {
			chomp;
			my @fields = split("\t", $_);

			my $date = $fields[0];
			splice(@fields, 0, 1);
			foreach (@fields) {
				my ($l, $r) = split("=", $_);
				if (! defined $tmp{$l}) {
					$tmp{$l}{data} = [];
					$tmp{$l}{name} = $l;
					if ($cfg->{vendors}{$l}) {
						$tmp{$l}{color} = "#$cfg->{vendors}{$l}{color}";
					}
				}
				push @{$tmp{$l}{data}}, [int($date), int($r)];
			}
		}
		close FILE;

		@{$part{vendors}} = keys %tmp;
		@{$part{series}}  = values %tmp;
		$part{part_num}   = $part_num;

		for my $manuf (keys $cfg->{products}) {
			for (keys $cfg->{products}{$manuf}) {
				$part{manuf} = $manuf if ($_ eq $part_num);
			}
		}

		if ($args{v}) {
			print chr(0x08) for split("", $part_num);
		}

		$parts{$part_num} = \%part;
	}
	closedir(DIR);

	open $fh, ">$cfg->{paths}{http}/json/products.json" or die $!;
	print $fh to_json(\%parts, {pretty => $pretty});
	close $fh;

	print "done.     \n" if $args{v};
}
