#!/usr/bin/env perl

use strict;
use warnings;

use Config::Grammar;
use Email::Simple;
use Email::Send;
use Getopt::Std;
use HTML::Grabber;
use LWP::Simple;

use shared;


my %args;
getopts("v", \%args);

$| = 1 if ($args{v});

my $cfg = get_config();
my $ua  = get_ua($cfg);
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
# use this to look up individual products
my $product_url = "http://www.memoryexpress.com/Products/";
my %product_map = ("televisions" => "Televisions",
	"laptops" => "LaptopsNotebooks",
	"hard_drives" => "HardDrives");

my $qry = "insert into products(part_num, manufacturer, description, type, " .
	"first_seen, last_seen, last_scraped) values (?, ?, ?, ?, ?, ?, ?)";
my $insert_sth = $dbh->prepare($qry);

# also update description, manufacturer?
$qry = "update products set last_seen = ? where part_num = ?";
my $update_sth = $dbh->prepare($qry);

my $summary .= "type        scraped total new errors time (s)\n";
$summary    .= "----------- ------- ----- --- ------ --------\n";

my $new_products;
my $errors;

for my $type (keys %product_map) {
	my $class_url = "http://www.memoryexpress.com/Category/" .
		"$product_map{$type}?PageSize=120&Page=";
	my $dom = get_dom($class_url . "1", $ua);
	next if (! defined $dom);

	print "GET " . $class_url . "1 OK\n" if ($args{v});

	$dom = $dom->find(".AJAX_List_Pager");
	my @elements = $dom->find("li")->html_array();
	my $pages;
	if (@elements == 2) {
		$pages = 1;
	} else {
		$pages = (@elements / 2) - 1;
	}

	print "$pages pages of products found\n" if ($args{v});

	my @thumbnails;
	for (1..$pages) {
		$dom = get_dom($class_url . "$_", $ua);
		return if (! defined $dom);

		print "GET " . $class_url . "$_ OK\n" if ($args{v});

		# $dom->filter(".AJAX_List_Body");
		push @thumbnails, $dom->find(".PIV_Regular")->html_array();
	}

	my $total = scalar @thumbnails;
	print "\nprocessing $type: ($total)\n" if ($args{v});

	my ($new, $old) = (0, 0);
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
			$errors .= "could not find .ProductBrand, html was:\n";
			$errors .= "$thumbnail_html\n\n";
			print $errors if ($args{v});
			next;
		}

		my $sql = "select * from products where part_num = ?";
		if ($dbh->selectrow_arrayref($sql, undef, $part_num)) {
			$update_sth->execute(time, $part_num);
			print "updated $part_num\n" if ($args{v});
			$old++;
		}
		else {
			$insert_sth->execute($part_num, $brand, $description,
				$type, time, time, 0);
			print "inserted $part_num\n" if ($args{v});
			$new_products .= "$brand $description ($part_num)\n";
			$new++;
		}
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
		To	=> $cfg->{general}{email},
		Subject	=> "PriceChart product scrape",
	],
	body => $mail);

if ($args{v}) {
	print $email->as_string();
}
else {
	my $sender = Email::Send->new({mailer => 'SMTP'});
	$sender->mailer_args([Host => $cfg->{general}{smtp}]);
	$sender->send($email->as_string()) || print "Couldn't send email\n";
}

sub get_tag_text
{
	my $dom = shift;
	my $tag = shift;

	my $field = $dom->find($tag)->text();
	if (!defined $field || $field eq "") {
		$errors .= "could not find $tag, html was:\n";
		$errors .= $dom->html();
		$errors .= "\n\n";
		print $errors if ($args{v});

		return undef;
	}
	return $field;
}
