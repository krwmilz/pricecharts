#!/usr/bin/env perl

use strict;
use warnings;

use Config::Grammar;
use DBI;
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
my $ua  = new_ua($cfg->{"general"}, $args{v});
my $dbh = get_dbh($cfg->{"general"});
# my $log = get_log("products.txt", $args{v});
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

my $sql = "insert into products(part_num, manufacturer, description, type, " .
	"first_seen, last_seen, last_scraped) values (?, ?, ?, ?, ?, ?, ?)";
my $insert_sth = $dbh->prepare($sql);

# also update description, manufacturer?
$sql = "update products set last_seen = ? where part_num = ?";
my $update_sth = $dbh->prepare($sql);

#
# Memory Express
#
my $mail = "Memory Express\n==============\n\n";
$mail   .= "type                 ok percent errors new duration\n";
$mail   .= "--------------- ------- ------- ------ --- --------\n";

my %product_map = (
	"televisions" => "Televisions",
	"laptops" => "LaptopsNotebooks",
	"hard drives" => "HardDrives"
);
while (my ($type, $name) = each %product_map) {
	mem_exp_scrape_class($type, $name);
}

$dbh->disconnect();
send_email($mail, $args{v});

#
# scrape an entire class of products, inserting or updating the db as needed.
# general flow is get all thumbnails on the unfiltered search results page, then
# for each of these get the part number, brand, and description.
#
sub mem_exp_scrape_class
{
	my $type = shift;
	my $name = shift;

	my $info_hdr = "info: $type";
	print "$info_hdr\n" if ($args{v});

	# this returns a search results page, link found through trial and error
	my $class_url = "http://www.memoryexpress.com/Category/" .
		"$name?PageSize=40&Page=";

	# get first page of results
	my $dom = get_dom($class_url . "1", $ua, $args{v});
	return undef if (!defined $dom);

	my $pager_hdr = "$info_hdr: .AJAX_List_Pager";

	# extract the first of two pager widgets on the page
	my ($pager_html) = $dom->find(".AJAX_List_Pager")->html_array();
	return undef if (!defined $pager_html);
	print "$pager_hdr found\n" if ($args{v});

	# find how many pages of results we have, each page is one <li> element
	my $pager = HTML::Grabber->new(html => $pager_html);
	my $pages = $pager->find("li")->html_array();
	return undef unless ($pages);

	# if more than 1 <li> is found, one <li> is always a "next" arrow
	$pages-- if ($pages > 1);
	print "$pager_hdr: $pages pages\n" if ($args{v});

	# loop over results pages and append product thumbnails
	my @thumbnails;
	for (1..$pages) {
		my $page_hdr = "$pager_hdr: $_/$pages";

		# slow this down a bit
		my $sleep = int(rand(5));
		printf "$page_hdr: (%is wait)\n", $sleep if ($args{v});
		sleep $sleep unless ($args{t});

		$dom = get_dom($class_url . "$_", $ua, $args{v});
		next if (!defined $dom);

		# each product thumbnail has class=PIV_Regular
		my @temp_thumbs = $dom->find(".PIV_Regular")->html_array();
		my $num_thumbs = scalar @temp_thumbs;
		print "$page_hdr: $num_thumbs thumbs found\n" if ($args{v});
		push @thumbnails, @temp_thumbs;

		last if ($args{t});
	}

	my $total = scalar @thumbnails;
	print "$info_hdr: $total total\n" if ($args{v});

	# extract and store part number, brand, and description
	my ($new, $old, $err, $start, $i) = (0, 0, 0, time, 0);
	for my $thumbnail_html (@thumbnails) {
		$i++;
		my $thumb_hdr = "$info_hdr: $i/$total";

		# look less suspicious
		my $sleep = int(rand(20));
		printf "$thumb_hdr (%ss wait)\n", $sleep if ($args{v});
		sleep $sleep unless ($args{t});

		# attempt to extract information from thumbnail_html
		my ($brand, $part_num, $desc) =
			mem_exp_scrape_thumbnail("$type: $i/$total", $thumbnail_html);
		if (!defined $brand) {
			$err++;
			next;
		}

		# extraction looks good, insert or update the database
		my $sql = "select * from products where part_num = ?";
		if ($dbh->selectrow_arrayref($sql, undef, $part_num)) {
			# also check description and manufacturer are consistent?
			$update_sth->execute(time, $part_num);
			print "$thumb_hdr: updated db\n" if ($args{v});
			$old++;
		}
		else {
			$insert_sth->execute($part_num, $brand, $desc, $type,
				time, time, 0);
			print "$thumb_hdr:  inserted into db\n" if ($args{v});
			$new++;
		}

		last if ($args{t});
	}

	my $ok = $new + $old;
	$mail .= sprintf("%-15s %7s %6.1f%% %6i %3i %7is\n", $type,
		"$ok/$total", $ok * 100.0 / $total, $err, $new, time - $start);
}

#
# this checks the input html for 3 things, part num, manufacturer, and
# description. if any of these aren't found, fail.
#
sub mem_exp_scrape_thumbnail
{
	my $thumb_hdr = shift;
	my $html = shift;

	my $error_hdr = "error: $thumb_hdr";
	my $info_hdr = "info: $thumb_hdr";

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

	return ($brand, $part_num, $desc);
}

#
# unwrap the plain text inside of an html tag
#
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

#
# send an email with the summary of the scrape
#
sub send_email
{
	my $mail = shift;
	my $verbose = shift || 0;

	if ($verbose) {
		print $mail;
		return;
	}

	my $email = Email::Simple->create(
		header => [
			From	=> "Santa Claus <sc\@np.com>",
			To	=> $cfg->{"general"}{"email"},
			Subject	=> "pricechart product scrape",
		],
		body => $mail
	);

	my $sender = Email::Send->new({mailer => "SMTP"});
	$sender->mailer_args([Host => $cfg->{"general"}{"smtp"}]);
	$sender->send($email->as_string()) || print "Couldn't send email\n";
}
