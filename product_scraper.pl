#!/usr/bin/env perl

use strict;
use warnings;

use Email::Simple;
use Email::Send;
use HTML::Grabber;

use shared;


my $ua  = get_ua();

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
# use this to look up individual products
my $product_url = "http://www.memoryexpress.com/Products/";
my %product_map = ("televisions" => "Televisions",
	"laptops" => "LaptopsNotebooks",
	"hard_drives" => "HardDrives");

my $email;
tee("$vendor\n");
tee("=") for (1..length $vendor);
tee("\n\n");

my $product_sth = $dbh->prepare("select * from products where part_num = ?");

my $qry = "insert into products(part_num, manufacturer, description, type, " .
	"first_seen, last_seen, last_scraped) values (?, ?, ?, ?, ?, ?, ?)";
my $insert_sth = $dbh->prepare($qry);

# also update description, manufacturer?
$qry = "update products set last_seen = ? where part_num = ?";
my $update_sth = $dbh->prepare($qry);

for (keys %product_map) {
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

	my @thumbnails;
	for (1..$pages) {
		$dom = get_dom($class_url . "$_", $ua);
		return if (! defined $dom);

		# $dom->filter(".AJAX_List_Body");
		push @thumbnails, $dom->find(".PIV_Regular")->html_array();
	}

	tee("*** $_ (" . @thumbnails . ") ***\n");

	my $new = 0;
	my $old = 0;
	my $start = time;
	for my $thumbnail_html (@thumbnails) {
		sleep int(rand(10));

		my $thumbnail_dom = HTML::Grabber->new(html => $thumbnail_html);

		# used to visit the actual product page
		my $product_id = get_tag_text($thumbnail_dom, ".ProductId");
		next unless (defined $product_id);

		# get the part number from the product page as early as possible
		my $product_dom = get_dom("$product_url$product_id", $ua);
		my $part_num = get_tag_text($product_dom, "#ProductAdd");
		next unless (defined $part_num);

		($part_num) = ($part_num =~ m/Part #:\s*(.*)\r/);
		next unless (defined $part_num && $part_num ne "");

		my $description = get_tag_text($thumbnail_dom, ".ProductTitle");
		next unless (defined $description);

		# brand sometimes shows up as text
		my $brand = $thumbnail_dom->find(".ProductBrand")->text();
		if ($brand eq "") {
			$brand = $thumbnail_dom->find(".ProductBrand")->html();
			($brand) = ($brand =~ m/Brand: ([A-Za-z]+)/);
		}
		if (!defined $brand || $brand eq "") {
			vprint("could not find .ProductBrand, html was:\n");
			vprint("$thumbnail_html\n\n");
			next;
		}

		$product_sth->execute($part_num);
		if ($product_sth->fetchrow_arrayref()) {
			$update_sth->execute(time, $part_num);
			vprint("  ($part_num) $brand $description\n");
			$old++;
		}
		else {
			$insert_sth->execute($part_num, $brand, $description,
				$_, time, time, 0);
			tee("+ ($part_num) $brand $description\n");
			$new++;
		}
	}

	tee("\n");
	tee("scraped total new   time\n");
	tee("------- ----- ---   ----\n");
	tee(sprintf("%7s %5s %3s %4s s\n",
		$new + $old, scalar @thumbnails, $new, time - $start));
}

$product_sth->finish();
$dbh->disconnect();

my $e_mail = Email::Simple->create(
	header => [
		From	=> "Santa Claus <sc\@np.com>",
		To	=> $cfg->{general}{email},
		Subject	=> "PriceChart product scrape",
	],
	body => $email);

my $sender = Email::Send->new({mailer => 'SMTP'});
$sender->mailer_args([Host => $cfg->{general}{smtp}]);
$sender->send($e_mail->as_string()) || print "Couldn't send email\n";

sub get_tag_text
{
	my $dom = shift;
	my $tag = shift;

	my $field = $dom->find($tag)->text();
	if (!defined $field || $field eq "" ) {
		vprint("could not find $tag, html was:\n");
		vprint($dom->html());
		vprint("\n\n");
		return undef;
	}
	return $field;
}

sub tee
{
	my $line = shift;

	vprint($line);
	$email .= $line;
}
