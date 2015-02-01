#!/usr/bin/env perl

use strict;
use warnings;

use Config::Grammar;
use Email::Simple;
use Email::Send;
use Getopt::Std;
use HTML::Grabber;
use LWP::Simple;
use PriceChart;


my %args;
getopts("tv", \%args);

$| = 1 if ($args{v});

my $cfg = get_config();
my $ua  = get_ua($cfg->{"general"});
my $dbh = get_dbh();
srand;

$dbh->do("create table if not exists products(" .
	"part_num text not null primary key, " .
	"manufacturer text, " .
	"description text, " .
	"type text, " .
	"first_seen int, " . 
	"last_seen int, " .
	"last_scraped int)") or die $DBI::errstr;

# $dbh->do("create table if not exists scrapes");

#
# Memory Express
#

my $vendor = "Memory Express";
my %product_map = (
	"televisions" => "Televisions",
	"laptops" => "LaptopsNotebooks",
	"hard drives" => "HardDrives");

my $sql = "insert into products(part_num, manufacturer, description, type, " .
	"first_seen, last_seen, last_scraped) values (?, ?, ?, ?, ?, ?, ?)";
my $insert_sth = $dbh->prepare($sql);

# also update description, manufacturer?
$sql = "update products set last_seen = ? where part_num = ?";
my $update_sth = $dbh->prepare($sql);

my $summary .= "type        scraped total new errors time (s)\n";
$summary    .= "----------- ------- ----- --- ------ --------\n";

my $new_products;
while (my ($type, $name) = each %product_map) {
	my $info_hdr = "info: $type";
	print "$info_hdr\n";

	# this returns a search results page, link found through trial and error
	my $class_url = "http://www.memoryexpress.com/Category/" .
		"$name?PageSize=40&Page=";

	# get first page of results
	my $dom = get_dom($class_url . "1", $ua, $args{v});
	next if (!defined $dom);

	my $pager_hdr = "$info_hdr: .AJAX_List_Pager";

	# extract the first of two pager widgets on the page
	my ($pager_html) = $dom->find(".AJAX_List_Pager")->html_array();
	next if (!defined $pager_html);
	print "$pager_hdr found\n" if ($args{v});

	# find how many pages of results we have, each page is one <li> element
	my $pager = HTML::Grabber->new(html => $pager_html);
	my $pages = $pager->find("li")->html_array();
	next unless ($pages);

	# if more than 1 <li> is found, one <li> is always a "next" arrow
	$pages-- if ($pages > 1);
	print "$pager_hdr: $pages pages\n" if ($args{v});

	# loop over results pages and append product thumbnails
	my @thumbnails;
	for (1..$pages) {
		# slow this down a bit
		my $sleep = int(rand(5));
		print "$pager_hdr: $_/$pages: $sleep s wait\n" if ($args{v});
		sleep $sleep;

		$dom = get_dom($class_url . "$_", $ua, $args{v});
		next if (!defined $dom);

		# each product thumbnail has class=PIV_Regular
		my @temp_thumbs = $dom->find(".PIV_Regular")->html_array();
		printf "$pager_hdr: $_/$pages: %i thumbs found\n", scalar @temp_thumbs if ($args{v});
		push @thumbnails, @temp_thumbs;
	}

	my $total = scalar @thumbnails;
	print "$info_hdr: $total total\n" if ($args{v});

	# extract part number, brand, and description
	my ($new, $old, $errors, $start, $i) = (0, 0, 0, time, 0);
	for my $thumbnail_html (@thumbnails) {
		$i++;

		my $ret = scrape_thumbnail($type, $thumbnail_html, "$i/$total");
		if (!defined $ret) {
			$errors++;
			last if ($args{t});
			next;
		}
		$ret ? $new++ : $old++;

		last if ($args{t});
	}

	$summary .= sprintf("%-11s %7s %5s %3s %6s %8s\n", $type, $new + $old,
		$total, $new, $errors, time - $start);
}

$dbh->disconnect();

my $mail = "$vendor\n";
$mail .= "=" for (1..length $vendor);
$mail .= "\n\n";

$mail .= "$summary\n"      if ($summary);
$mail .= "$new_products\n" if ($new_products);

my $email = Email::Simple->create(
	header => [
		From	=> "Santa Claus <sc\@np.com>",
		To	=> $cfg->{"general"}{"email"},
		Subject	=> "PriceChart product scrape",
	],
	body => $mail
);

if ($args{v}) {
	print $email->as_string();
	exit 0;
}

my $sender = Email::Send->new({mailer => 'SMTP'});
$sender->mailer_args([Host => $cfg->{"general"}{"smtp"}]);
$sender->send($email->as_string()) || print "Couldn't send email\n";

sub scrape_thumbnail
{
	my $type = shift;
	my $html = shift;
	my $count = shift;

	my $error_hdr = "error: $type: $count";
	my $info_hdr = "info: $type: $count";

	my $sleep = int(rand(20));
	printf "$info_hdr (%ss wait)\n", $sleep if ($args{v});
	sleep $sleep;

	# make new html grabber instance with the thumbnail html
	my $dom = HTML::Grabber->new(html => $html);

	# has to be found otherwise we can't do anything
	my $product_id = get_tag_text($dom, ".ProductId", $error_hdr);
	return undef unless defined $product_id;

	# visit the extended description page
	my $product_url = "http://www.memoryexpress.com/Products/";
	my $product_dom = get_dom("$product_url$product_id", $ua, $args{v});

	# the part number is inside of id=ProductAdd always
	my $part_num = get_tag_text($product_dom, "#ProductAdd", $error_hdr);
	return undef unless defined $part_num;

	# extract the part number, always is text inside of the tag
	($part_num) = ($part_num =~ m/Part #:\s*(.*)\r/);
	if (!defined $part_num) {
		print "$error_hdr: part num regex failed\n";
		return undef;
	}

	# extract the product description
	my $desc = get_tag_text($dom, ".ProductTitle", $error_hdr);
	return undef unless defined $desc;

	# extract the brand, sometimes shows up as text
	my $brand = $dom->find(".ProductBrand")->text();
	if ($brand eq "") {
		# and sometimes shows up inside the tag attributes
		$brand = $dom->find(".ProductBrand")->html();
		($brand) = ($brand =~ m/Brand: ([A-Za-z]+)/);
	}
	if (!defined $brand || $brand eq "") {
		print "$error_hdr: .ProductBrand not found, html was:\n";
		print "$html\n";
		return undef;
	}

	my $tmp_desc = $desc;
	if (length($tmp_desc) > 50) {
		$tmp_desc = substr($tmp_desc, 0, 50) . "...";
	}
	print "$info_hdr: $brand $part_num\n" if ($args{v});
	print "$info_hdr: $tmp_desc\n" if ($args{v});

	# use existence of part_num to decide on update or insert new
	my $sql = "select * from products where part_num = ?";
	if ($dbh->selectrow_arrayref($sql, undef, $part_num)) {
		# update
		$update_sth->execute(time, $part_num);
		print "$info_hdr: db updated\n" if ($args{v});
		return 0;
	}
	else {
		# insert new
		$insert_sth->execute($part_num, $brand, $desc, $type, time,
			time, 0);
		print "$info_hdr: db inserted\n" if ($args{v});
		$new_products .= "$brand $desc ($part_num)\n";
		return 1;
	}
	# $scrapes_sth->execute("thumbnail", time - $start, time);
}

sub get_tag_text
{
	my $dom = shift;
	my $tag = shift;
	my $error_hdr = shift;

	my $field = $dom->find($tag)->text();
	if (!defined $field || $field eq "") {
		print "$error_hdr: $tag not found or empty, html was:\n";
		print $dom->html() . "\n";
		return undef;
	}

	return $field;
}
