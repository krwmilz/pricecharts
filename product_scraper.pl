#!/usr/bin/env perl

use strict;
use warnings;

use Email::Simple;
use Email::Send;
use HTML::Grabber;
use POSIX;

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

vprint("$vendor:\n");

my $email;
$email .= "*** $vendor ***\n\n";
$email .= "type            scraped total new time\n";
$email .= "------------    ------- ----- --- ----\n";

my $product_sth = $dbh->prepare("select * from products where part_num = ?");

my $qry = "insert into products(part_num, manufacturer, description, type, " .
	"first_seen, last_seen, last_scraped) values (?, ?, ?, ?, ?, ?, ?)";
my $insert_sth = $dbh->prepare($qry);

# also update description, manufacturer?
$qry = "update products set last_seen = ? where part_num = ?";
my $update_sth = $dbh->prepare($qry);

my @new = ();
for (keys %product_map) {

	$email .= sprintf("%-15s ", $_);

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

	vprint("$_: found " . @thumbnails . " products\n");

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
		next if (not_defined($brand, ".ProductBrand", $thumbnail_html));

		$product_sth->execute($part_num);
		if ($product_sth->fetchrow_arrayref()) {
			$update_sth->execute(time, $part_num);
			vprint("  ");
			$old++;
		}
		else {
			$insert_sth->execute($part_num, $brand, $description,
				$_, time, time, 0);
			push @new, ([$_, $brand, $description, $part_num]);
			vprint("+ ");
			$new++;
		}

		vprint("($part_num) $brand $description\n");
	}

	$email .= sprintf("%7s %5s %3s %4s\n",
		$new + $old, scalar @thumbnails, $new, time - $start);
}

$email .= "\nNew products:\n" if (@new);
$email .= "- ($_->[0]) $_->[1] $_->[2] $_->[3]\n" for (@new);

$product_sth->finish();
$dbh->disconnect();

my $date = strftime "%d/%m/%Y", localtime;
my $e_mail = Email::Simple->create(
	header => [
		From	=> "Santa Claus <sc\@np.com>",
		To	=> $cfg->{general}{email},
		Subject	=> "PriceChart product scrape $date",
	],
	body => $email);

vprint($e_mail->as_string());

my $sender = Email::Send->new({mailer => 'SMTP'});
$sender->mailer_args([Host => $cfg->{general}{smtp}]);
$sender->send($e_mail->as_string()) || print "Couldn't send email\n";

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
	my $field = shift;
	my $field_name = shift;
	my $html = shift;

	if (!defined $field || $field eq "" ) {
		vprint("could not find $field_name, html was:\n");
		vprint("$html\n");
		return 1;
	}
	return 0;
}

sub get_tag_text
{
	my $dom = shift;
	my $tag = shift;

	my $field = $dom->find($tag)->text();
	if (!defined $field || $field eq "" ) {
		vprint("could not find $tag, html was:\n");
		vprint($dom->html());
		vprint("\n");
		return undef;
	}
	return $field;
}
