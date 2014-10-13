#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use DBI;
use Email::Simple;
use Email::Send;
use Getopt::Std;
use HTML::Grabber;
use LWP::Simple;
use POSIX;

use shared;


my %args;
getopts("vf:", \%args);

my $cfg = get_config($args{f});
my $dbh = get_dbh($cfg);
my $ua  = get_ua($cfg);

$| = 1 if ($args{v});

$dbh->do("create table if not exists products(" .
	"part_num text not null primary key, " .
	"brand text, " .
	"title text, " .
	"type text, " .
	"first_seen int, " . 
	"last_seen int, " .
	"last_scraped int)") or die $DBI::errstr;

my $email;

#
# Memory Express
#

$dbh->do("create table if not exists [Memory Express](" .
	"date int not null primary key)");

my %product_map = ("televisions" => "Televisions",
	"laptops" => "LaptopsNotebooks",
	"hard_drives" => "HardDrives");

$email .= "*** Memory Express ***\n\n";
$email .= "product type    scraped total new\n";
$email .= "------------    ------- ----- ---\n";

my @new = ();
for (keys %product_map) {

	$email .= sprintf("%-15s ", "$_:");

	my $class_url = "http://www.memoryexpress.com/Category/" .
		"$product_map{$_}?PageSize=120&Page=";
	my $dom = get_dom($class_url . "1", $ua);
	next if (! defined $dom);

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
		$dom = get_dom($class_url . "$_", $ua);
		return if (! defined $dom);

		# $dom->filter(".AJAX_List_Body");
		push @results, $dom->find(".PIV_Regular")->html_array();
	}

	my $scraped = 0;
	for my $node (@results) {
		my $product = HTML::Grabber->new(html => $node);

		# title is easier to parse from general results page
		my $title = $product->find(".ProductTitle")->text();
		next if (not_defined($title, "title", $node));

		# brand is easier to parse from general results page, sometimes
		# shows up as text
		my $brand = $product->find(".ProductBrand")->text();
		if ($brand eq "") {
			my $brand = $product->find(".ProductBrand")->html();
			($brand) = ($brand =~ m/Brand: ([A-Za-z]+)/);
		}
		next if (not_defined($brand, "brand", $node));

		# used to visit the actual product page
		my $product_id = $product->find(".ProductId")->text();
		next if (not_defined($product_id, "product ID", $node));

		my $product_url = "http://www.memoryexpress.com/Products/";
		my $product_dom = get_dom("$product_url$product_id", $ua);

		# part number only found on product page
		my $part_num = $product_dom->find("#ProductAdd")->text();
		($part_num) = ($part_num =~ m/Part #: (.*)\r/);
		next if (not_defined($part_num, "part number", $product_dom));

		my $query = "select * from products where part_num = ?";
		my $sth = $dbh->prepare($query);
		$sth->execute($part_num);
		if ($sth->fetchrow_array()) {
			$dbh->do("update products set last_seen = ? where part_num = ?",
				undef, time, $part_num);
			# also update title, brand here?
		}
		else {
			$dbh->do("insert into products(part_num, brand, title," .
				"type, first_seen, last_seen, last_scraped) " .
				"values (?, ?, ?, ?, ?, ?, ?)", undef,
				$part_num, $brand, $title, $_, time, time, 0);
			#$dbh->do("create table [$part_num]" .
			#	"(unix_time int not null primary key)");
			push @new, ([$_, $brand, $title, $part_num]);
		}

		$scraped++;
		last;
	}

	$email .= sprintf("%7s %5s %3s\n", $scraped, scalar @results,
			scalar @new);
	next;

	my $sth = $dbh->prepare("select * from [Memory Express]");
	my @columns = @{$sth->{NAME}};
	for my $column (@columns) {
		next if ($column ne $_);
	}
	$dbh->do("alter table [Memory Express] add column $_");
}

$email .= "\nNew products:\n" if (@new);
$email .= "- ($_->[0]) $_->[1] $_->[2] $_->[3]\n" for (@new);

$dbh->disconnect();

my $date = strftime "%d/%m/%Y", localtime;
my $e_mail = Email::Simple->create(
	header => [
		From	=> "Santa Claus <sc\@np.com>",
		To	=> $cfg->{general}{email},
		Subject	=> "PriceChart product scrape $date",
	],
	body => $email);

print $e_mail->as_string();

my $sender = Email::Send->new({mailer => 'SMTP'});
$sender->mailer_args([Host => $cfg->{general}{smtp}]);
$sender->send($e_mail->as_string());

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
