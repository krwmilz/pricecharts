#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use DBI;
use File::Basename;
use Getopt::Std;
use JSON;
use HTML::Grabber;
use LWP::Simple;
use POSIX;


my %args;
getopts("v", \%args);

if ($args{v}) {
	# Disable buffering on STDOUT
	$| = 1;
	select STDOUT;
}

my $dbh = DBI->connect(
	"dbi:SQLite:dbname=pricechart.db",
	"",
	"",
	{ RaiseError => 1 },) or die $DBI::errstr;

$dbh->do("create table if not exists products(" .
	"part_num text not null primary key, " .
	"brand text, " .
	"title text, " .
	"type text, " .
	"first_seen int, " . 
	"last_seen int)") or die $DBI::errstr;

# Chrome 36 Win7 64bit
my $user_agent = "Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/36.0.1985.125 Safari/537.36";
my $ua = LWP::UserAgent->new(agent => $user_agent);
$ua->default_header("Accept" => "*/*");

#
# Memory Express
#
my %product_map = ("televisions" => "Televisions",
	"laptops" => "LaptopsNotebooks",
	"hard_drives" => "HardDrives");
for (keys %product_map) {

	print "*** $_ ***\n";

	my $class_url = "http://www.memoryexpress.com/Category/" .
		"$product_map{$_}?PageSize=120&Page=";
	my $dom = get_dom($class_url . "1");
	return if (! defined $dom);

	$dom = $dom->find(".AJAX_List_Pager");
	my @elements = $dom->find("li")->html_array();
	my $pages;
	if (@elements == 2) {
		$pages = 1;
	} else {
		$pages = (@elements / 2) - 1;
	}

	my @results;
	for (1..$pages) {
		$dom = get_dom($class_url . "$_");
		return if (! defined $dom);

		# $dom->filter(".AJAX_List_Body");
		push @results, $dom->find(".PIV_Regular")->html_array();
	}

	my $scraped = 0;
	my @new_products = ();
	for my $node (@results) {
		my $product = HTML::Grabber->new(html => $node);

		# title is easier to parse from general results page
		my $title = $product->find(".ProductTitle")->text();
		next if (not_defined($title, "title", $node));

		# brand is easier to parse from general results page
		my $brand = $product->find(".ProductBrand")->html();
		($brand) = ($brand =~ m/Brand: ([A-Za-z]+)/);
		next if (not_defined($brand, "brand", $node));

		# used to visit the actual product page
		my $product_id = $product->find(".ProductId")->text();
		next if (not_defined($product_id, "product ID", $node));

		my $product_url = "http://www.memoryexpress.com/Products/";
		my $product_dom = get_dom("$product_url$product_id");

		# part number only found on product page
		my $part_num = $product_dom->find("#ProductAdd")->text;
		($part_num) = ($part_num =~ m/Part #: (.*)/);
		next if (not_defined($part_num, "part number", $product_dom));

		my $query = "select * from products where part_num = ?";
		my $sth = $dbh->prepare($query);
		$sth->execute($part_num);
		if ($sth->fetchrow_array()) {
			$dbh->do("update products set last_seen = ? where part_num = ?",
				undef, time, $part_num);
		}
		else {
			$dbh->do("insert into products(" .
				"part_num, brand, title, type, first_seen, last_seen)" .
				" values (?, ?, ?, ?, ?, ?)",
				undef, $part_num, $brand, $title, $_, time, time);
			#$dbh->do("create table [$part_num]" .
			#	"(unix_time int not null primary key)");
			push @new_products, ([$brand, $title, $part_num]);
		}

		$scraped++;
		last;
	}

	print "scraped/total: $scraped/" . @results . "\n";
	print "new: " . scalar @new_products . "\n";
	print " - $_->[0] $_->[1] $_->[2]\n" for (@new_products);
	print "\n";
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

#
# Best Buy
#
# my %product_map = {televisions => "led-tvs/25993.aspx"};

#
# Visions
#
# televisions = http://www.visions.ca/Catalogue/Category/ProductResults.aspx?categoryId=5&menu=9&pz=30
# televisions_page = &px=<PAGE>
# product_list = .centerPanel

sub not_defined
{
	my $var = shift;
	my $var_name = shift;
	my $dom = shift;

	if (!defined $var) {
		print "could not find $var_name, DOM was:\n";
		print "$dom\n";
		return 1;
	}
	return 0;
}

sub get_dom
{
	my $url = shift;

	my $resp = $ua->get($url);
	if (! $resp->is_success) {
		print STDERR "getting $url failed: " . $resp->status_line . "\n";
		return undef;
	}
	return HTML::Grabber->new(html => $resp->decoded_content);
}
