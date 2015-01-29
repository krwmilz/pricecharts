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

my ($new_products, $errors);

while (my ($type, $name) = each %product_map) {
	print "Enumerating $type\n";

	# this returns a search results page, link found through trial and error
	my $class_url = "http://www.memoryexpress.com/Category/" .
		"$name?PageSize=40&Page=";

	# get first page of results
	my $dom = get_dom($class_url . "1", $ua, $args{v});
	next if (!defined $dom);

	# extract the first of two pager widgets on the page
	my ($pager_html) = $dom->find(".AJAX_List_Pager")->html_array();
	next if (!defined $pager_html);
	print "info: .AJAX_List_Pager found\n" if ($args{v});

	# find how many pages of results we have, each page is one <li> element
	my $pager = HTML::Grabber->new(html => $pager_html);
	my $pages = $pager->find("li")->html_array();
	next unless ($pages);

	# if more than 1 <li> is found, one <li> is always a "next" arrow
	$pages-- if ($pages > 1);
	print "info: .AJAX_List_Pager: $pages pages\n" if ($args{v});

	# loop over results pages and append product thumbnails
	my @thumbnails;
	for (1..$pages) {
		# slow this down a bit
		sleep int(rand(5));

		$dom = get_dom($class_url . "$_", $ua, $args{v});
		next if (!defined $dom);

		# each product thumbnail has class=PIV_Regular
		push @thumbnails, $dom->find(".PIV_Regular")->html_array();

		next if ($args{t});
	}

	my $total = scalar @thumbnails;
	print "info: found $total $type, scraping individually\n" if ($args{v});

	# extract part number, brand, and description
	my ($new, $old, $start, $i) = (0, 0, time, 0);
	for my $thumbnail_html (@thumbnails) {
		$i++;
		my $hdr = "$type: $i/$total";

		my $sleep = int(rand(20));
		print "info: $hdr ($sleep s wait)\n" if ($args{v});
		sleep $sleep;

		# make new html grabber instance with the thumbnail html
		my $thumbnail_dom = HTML::Grabber->new(html => $thumbnail_html);

		# has to be found otherwise we can't do anything
		my $product_id = get_tag_text($thumbnail_dom, ".ProductId");
		if (!defined $product_id) {
			print "error: $hdr: .ProductId not found\n";
			next;
		}
		else {
			print "info: $hdr: .ProductId = $product_id\n" if ($args{v});
		}

		# visit the extended description page
		my $product_url = "http://www.memoryexpress.com/Products/";
		my $product_dom = get_dom("$product_url$product_id", $ua, $args{v});

		# the part number is inside of id=ProductAdd always
		my $part_num = get_tag_text($product_dom, "#ProductAdd");
		if (!defined $part_num) {
			print "error: $hdr: #ProductAdd not found\n";
			next;
		}

		# extract the part number, always is text inside of the tag
		($part_num) = ($part_num =~ m/Part #:\s*(.*)\r/);
		if (!defined $part_num || $part_num eq "") {
			print "error: $hdr: part num regex failed\n";
			next;
		}
		else {
			print "info: $hdr: part_num = $part_num\n" if ($args{v});
		}

		# extract the product tile
		my $desc = get_tag_text($thumbnail_dom, ".ProductTitle");
		if (!defined $desc) {
			print "error: $hdr: .ProductTitle was not found.\n";
			next;
		}
		else {
			my $tmp_desc = $desc;
			if (length($tmp_desc) > 35) {
				$tmp_desc = substr($tmp_desc, 0, 40) . "...";
			}
			print "info: $hdr: .ProductTitle = $tmp_desc\n" if ($args{v});
		}

		# extract the brand, sometimes shows up as text
		my $brand = $thumbnail_dom->find(".ProductBrand")->text();
		if ($brand eq "") {
			print "info: $hdr: .ProductBrand not text\n" if ($args{v});
			# and sometimes shows up inside the tag attributes
			$brand = $thumbnail_dom->find(".ProductBrand")->html();
			($brand) = ($brand =~ m/Brand: ([A-Za-z]+)/);
		}
		if (!defined $brand || $brand eq "") {
			print "error: $hdr: .ProductBrand not found, html:\n";
			print "$thumbnail_html\n";
			next;
		}
		else {
			print "info: $hdr: .ProductBrand = $brand\n" if ($args{v});
		}

		# use existence of part_num to decide on update or insert new
		my $sql = "select * from products where part_num = ?";
		if ($dbh->selectrow_arrayref($sql, undef, $part_num)) {
			# update
			$update_sth->execute(time, $part_num);
			print "info: $hdr: db updated\n" if ($args{v});
			$old++;
		}
		else {
			# insert new
			$insert_sth->execute($part_num, $brand, $desc,
				$type, time, time, 0);
			print "info: $hdr: db inserted\n" if ($args{v});
			$new_products .= "$brand $desc ($part_num)\n";
			$new++;
		}
		last if ($args{t});
	}

	$summary .= sprintf("%-11s %7s %5s %3s %6s %8s\n", $type, $new + $old,
		$total, $new, $total - ($new + $old), time - $start);
	print "\n" if ($args{v});
}

$dbh->disconnect();

my $mail;
$mail .= "$vendor\n";
$mail .= "=" for (1..length $vendor);
$mail .= "\n\n";

$mail .= "$summary\n"      if ($summary);
$mail .= "$new_products\n" if ($new_products);
$mail .= $errors           if ($errors);

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
}
else {
	my $sender = Email::Send->new({mailer => 'SMTP'});
	$sender->mailer_args([Host => $cfg->{"general"}{"smtp"}]);
	$sender->send($email->as_string()) || print "Couldn't send email\n";
}

sub get_tag_text
{
	my $dom = shift;
	my $tag = shift;

	my $field = $dom->find($tag)->text();
	if (!defined $field || $field eq "") {
		$errors .= "error: could not find $tag, html was:\n";
		$errors .= $dom->html();
		$errors .= "\n\n";
		print $errors if ($args{v});

		return undef;
	}
	return $field;
}
