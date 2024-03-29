#!/usr/bin/env perl
use strict;
use warnings;

use BSD::arc4random qw(arc4random_uniform);
use Config::Grammar;
use Email::Simple;
use Email::Send;
use Getopt::Std;
use HTML::Grabber;
use IO::Tee;
use List::Util qw(min);
use LWP::Simple;
use PriceSloth;
use POSIX;
use Term::ReadKey;
use URI::Escape;


my %args;
getopts("nptv", \%args);

$| = 1 if ($args{v});

sleep_if_cron();
my $cfg = get_config();
my $ua  = new_ua($cfg->{general}, $args{v});
my $dbh = get_dbh($cfg->{general}{db_dir}, $args{v});
my $tmp_file = "/tmp/product_scraper.txt";
my $tmp_log = get_log($tmp_file, $args{v});
srand;

if ($args{p}) {
	mem_exp_scrape_products();
}
else {
	scrape_prices();
}

sub scrape_prices
{
	my $log_path = $cfg->{general}{log_dir} . "/pricesloth";
	my $log = get_log($log_path, $args{v});

	# allow products to go out of stock. if we haven't seen them for > 30 days
	# chances are retailers aren't carrying them anymore
	my $cutoff = time - (30 * 24 * 60 * 60);
	my $sql = "select part_num, manufacturer, type from products " .
	"where last_seen > $cutoff order by last_scraped asc";
	my ($part_num, $manufacturer, $type) = $dbh->selectrow_array($sql);

	unless (defined $part_num && defined $manufacturer) {
		print "error: no parts seen in the last 30 days\n";
		print "       run a product scrape to freshen the part numbers\n";
		exit 1;
	}

	# prevent races with other scrapers, claim ownership as soon as possible
	$dbh->do("update products set last_scraped = ? where part_num = ? and manufacturer = ?",
		undef, time, $part_num, $manufacturer);

	print "info: scraping $manufacturer $part_num\n" if ($args{v});

	$sql = qq{insert into prices(date, manufacturer, part_num, retailer,
		price, duration) values (?, ?, ?, ?, ?, ?)};
	my $prices_sth = $dbh->prepare($sql);

	$sql = qq{update products set last_seen = ?, svg_stale = 1
		where part_num = ? and manufacturer = ?};
	my $products_sth = $dbh->prepare($sql);

	$sql = "insert or replace into retailers(name, color, url) values (?, ?, ?)";
	my $retailer_sth = $dbh->prepare($sql);

	$sql = qq{insert or replace into descriptions(manufacturer, part_num,
		retailer, description, date) values (?, ?, ?, ?, ?)};
	my $descriptions_sth = $dbh->prepare($sql);

	my $timestamp = strftime("%F %T> ", localtime);
	my ($start, @status, $i) = (time, "", -1);
	for my $retailer (sort keys %{$cfg->{retailers}}) {
		my %props =	%{$cfg->{retailers}{$retailer}};
		# this could probably be done smarter
		my $url =	$props{url};
		my $color =	$props{color};
		my $price_tag =	$props{reg_tag};
		my $sale_tag =	$props{sale_tag};
		my $desc_tag =  $props{title};

		my $retailer_start = time;
		$status[++$i] = " ";

		# for products with short part numbers, also search manufacturer
		my $search;
		if (length($part_num) < 6) {
			$search = uri_escape("$manufacturer $part_num");
		} else {
			$search = uri_escape($part_num);
		}

		# get a page of search results from a retailer
		my $search_results = get_dom($url . $search, $ua, $args{v}, $log);
		next unless defined $search_results;

		# search search_results for particular html tags that should be prices
		my $price_r = get_valid_price($price_tag, $search_results, $retailer, $log);
		my $price_s = get_valid_price($sale_tag,  $search_results, $retailer, $log);
		next unless ($price_r || $price_s);

		# choose the lowest that exists
		my $price;
		$price = $price_r if ($price_r);
		$price = $price_s if ($price_s);
		$price = min($price_r, $price_s) if ($price_r && $price_s);

		# opportunistically scrape descriptions
		my ($found_descr, $descr);
		if ($desc_tag) {
			# scrape description, use first one found on page
			($descr) = $search_results->find($desc_tag)->text_array();
			if (defined $descr && $descr ne "") {
				$descr =~ s/^\s+//;
				$descr =~ s/\s+$//;
				$descr =~ s/$manufacturer//;
				$descr =~ s/$part_num//;

				my $descr_s = trunc_line($descr, length($retailer) + 8);
				print "info: $retailer: $descr_s\n" if ($args{v});
				$found_descr = 1;
			}
		}

		# everything looks good
		$status[$i] = substr($retailer, 0, 1);

		next if ($args{n});
		$dbh->begin_work;
		$retailer_sth->execute($retailer, $color, $url);
		$prices_sth->execute($start, $manufacturer, $part_num, $retailer, $price,
			time - $retailer_start);
		$products_sth->execute($start, $part_num, $manufacturer);
		$descriptions_sth->execute($manufacturer, $part_num, $retailer,
			$descr, time) if (defined $found_descr);
		$dbh->commit;

		print "info: $retailer: db: inserted \$$price\n" if ($args{v});
	}

	printf $log "%s %-12s %-10s %-20s [%s] (%i s)\n", $timestamp, $type,
	$manufacturer, $part_num, join("", @status), time - $start;

	$log->close();
	$retailer_sth = undef;
	$prices_sth = undef;
	$products_sth = undef;
	$descriptions_sth = undef;
	$dbh->disconnect();

	exit 0;
}

sub get_valid_price
{
	my ($dom_tag, $search_results, $retailer, $log) = @_;
	return undef unless defined $dom_tag;

	# break the search_results page down into individual results
	my @search_prices = $search_results->find($dom_tag)->text_array();
	my $num_prices = @search_prices;
	return undef if ($num_prices == 0);

	print "info: $retailer: $dom_tag: $num_prices elements\n" if ($args{v});
	my $hdr = "$retailer: $dom_tag" . "[0]";

	# do a fuzzy search for digit combinations that look like a price
	# XXX: uses the first found price in the page
	# XXX: this does not work on single digit prices, ie $7.00
	my ($price, @others) = ($search_prices[0] =~ m/(\d[\d,]+)/);
	if (!defined $price || @others) {
		print $log "error: $hdr: wrong number of regexs\n";
		return undef;
	}

	# sanity check the numerical price value
	$price =~ s/,//;
	if ($price <= 0 || $price > 10000) {
		print $log "error: $hdr: price $price out of range\n";
		return undef;
	}

	print "info: $hdr: \$$price\n" if ($args{v});
	return $price;
}


# --- PRODUCT SCRAPE ---

sub mem_exp_scrape_products
{
	my $sql = qq{insert into products(part_num, manufacturer, retailer, type,
	first_seen, last_seen, last_scraped) values (?, ?, ?, ?, ?, ?, ?)};
	my $insert_sth = $dbh->prepare($sql);

	$sql = "insert or replace into descriptions(manufacturer, part_num, retailer, ".
	"description, date) values (?, ?, ?, ?, ?)";
	my $descriptions_sth = $dbh->prepare($sql);

	# also update description, manufacturer?
	$sql = "update products set last_seen = ? where part_num = ?";
	my $update_sth = $dbh->prepare($sql);

	#
	# Memory Express
	#
	print $tmp_log "Memory Express\n==============\n\n";
	print $tmp_log "type                 ok percent errors new duration\n";
	print $tmp_log "--------------- ------- ------- ------ --- --------\n";

	my %product_map = (
		"Television" => "Televisions",
		"Laptop" => "LaptopsNotebooks",
		"Hard Drive" => "HardDrives",
		"Memory" => "Memory",
		"Video Card" => "VideoCards",
		"Processor" => "Processors"
	);
	while (my ($type, $name) = each %product_map) {
		mem_exp_scrape_class($type, $name, $insert_sth, $descriptions_sth,
			$update_sth);
	}

	$update_sth = undef;
	$insert_sth = undef;
	$dbh->disconnect();
	$tmp_log->close();
	send_email($args{v});

	exit 0;
}

#
# scrape an entire class of products, inserting or updating the db as needed.
# general flow is get all thumbnails on the unfiltered search results page, then
# for each of these get the part number, brand, and description.
#
sub mem_exp_scrape_class
{
	my ($type, $name, $insert_sth, $descriptions_sth, $update_sth) = @_;

	my $info_hdr = "info: " . lc($type);

	my $thumbnails = mem_exp_get_thumbnails($name, $info_hdr);
	return undef unless defined $thumbnails;

	my $total = scalar @$thumbnails;
	print "$info_hdr: $total total\n" if ($args{v});

	# randomize the combined results so we don't linearly visit them
	my @rand_thumbnails = sort { rand > .5 } @$thumbnails;

	# extract and store part number, brand, and description
	my ($new, $old, $err, $start, $i) = (0, 0, 0, time, 0);
	for my $thumbnail_html (@rand_thumbnails) {
		$i++;
		my $thumb_hdr = "$info_hdr: $i/$total";

		# look less suspicious
		sleep_rand($thumb_hdr, 20);

		# attempt to extract information from thumbnail html
		my ($brand, $part_num, $desc) =
			mem_exp_scrape_thumbnail("$type: $i/$total", $thumbnail_html);
		unless (defined $brand && defined $part_num && defined $desc) {
			$err++;
			next;
		}

		# memory express has bundles, we're not really interested in
		# those
		next if ($part_num =~ /^BDL_/);

		$dbh->begin_work;

		# sanitize $brand against known good manufacturer names
		my $sql = qq{select manufacturer from products where
			lower(manufacturer) = ?};
		my $manufs = $dbh->selectcol_arrayref($sql, undef, lc($brand));
		if (@$manufs) {
			# take a risk that the first one is spelled right
			if ($manufs->[0] ne $brand) {
				print "warn: forcing misspelled $brand to ";
				print $manufs->[0] . "\n";
				$brand = $manufs->[0];
			}
		}

		# extraction looks good, insert or update the database
		$sql = "select * from products where manufacturer = ? and
			part_num = ?";
		if ($dbh->selectrow_arrayref($sql, undef, $brand, $part_num)) {
			# also check description and manufacturer are consistent?
			$update_sth->execute(time, $part_num) or die $dbh->errstr();
			$old++;
		}
		else {
			$insert_sth->execute($part_num, $brand, "Memory Express", $type,
				time, time, 0) or die $dbh->errstr();
			print "$thumb_hdr: inserted into db\n" if ($args{v});
			$new++;
		}

		# this has a foreign key constraint on the product table
		$descriptions_sth->execute($brand, $part_num, "Memory Express",
			$desc, time);

		$dbh->commit;
	}

	my $ok = $new + $old;
	my $time_str = sprintf("%dh %dm %ds", (gmtime(time - $start))[2, 1, 0]);
	print $tmp_log sprintf("%-15s %7s %6.1f%% %6i %3i %s\n", lc($type),
		"$ok/$total", $ok * 100.0 / $total, $err, $new, $time_str);
}

#
# get all thumbnails from generic unfiltered search page
#
sub mem_exp_get_thumbnails
{
	my ($name, $info_hdr) = @_;

	# this returns a search results page, link found through trial and error
	my $class_url = "http://www.memoryexpress.com/Category/" .
		"$name?PageSize=40&Page=";

	# get first page of results
	my $dom = get_dom($class_url . "1", $ua, $args{v}, $tmp_log);
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
		sleep_rand($page_hdr, 5);

		# get a search pages dom
		$dom = get_dom($class_url . "$_", $ua, $args{v}, $tmp_log);
		next if (!defined $dom);

		# each product thumbnail has class=PIV_Regular
		my @temp_thumbs = $dom->find(".PIV_Regular")->html_array();
		if ($args{t}) {
			@temp_thumbs = ($temp_thumbs[0]);
		}
		my $num_thumbs = scalar @temp_thumbs;
		print "$page_hdr: $num_thumbs thumbs found\n" if ($args{v});
		push @thumbnails, @temp_thumbs;

		last if ($args{t});
	}

	return \@thumbnails;
}

#
# this checks the input html for 3 things, part num, manufacturer, and
# description. if any of these aren't found, fail.
#
sub mem_exp_scrape_thumbnail
{
	my ($thumb_hdr, $html) = @_;

	my $error_hdr = "error: $thumb_hdr";
	my $info_hdr = "info: $thumb_hdr";

	# make new html grabber instance with the thumbnail html
	my $dom = HTML::Grabber->new(html => $html);

	# has to be found otherwise we can't do anything
	my $product_id = get_tag_text($dom, ".ProductId", $error_hdr);
	return undef unless defined $product_id;

	# visit the extended description page
	my $product_url = "http://www.memoryexpress.com/Products/";
	my $product_dom = get_dom("$product_url$product_id", $ua, $args{v}, $tmp_log);

	# the part number is inside of id=ProductAdd always
	my $part_num = get_tag_text($product_dom, "#ProductAdd", $error_hdr);
	return undef unless defined $part_num;

	# extract the part number, always is text inside of the tag
	($part_num) = ($part_num =~ m/Part #:\s*(.*)\r/);
	if (!defined $part_num) {
		print $tmp_log "$error_hdr: part num regex failed\n";
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
		# XXX: revisit this regex, it should be less strict
		($brand) = ($brand =~ m/Brand: ([0-9A-Za-z\. ]+)/);
	}
	if (!defined $brand || $brand eq "") {
		print $tmp_log "$error_hdr: .ProductBrand not found, html was:\n";
		print $tmp_log "$html\n";
		return undef;
	}

	my $shortened_desc = trunc_line($desc, length($info_hdr) + 2);
	print "$info_hdr: $brand $part_num\n" if ($args{v});
	print "$info_hdr: $shortened_desc\n" if ($args{v});

	return ($brand, $part_num, $desc);
}

#
# unwrap the plain text inside of an html tag
#
sub get_tag_text
{
	my ($dom, $tag, $error_hdr) = @_;

	my $field = $dom->find($tag)->text();
	if (!defined $field || $field eq "") {
		print $tmp_log "$error_hdr: $tag not found or empty, html was:\n";
		print $tmp_log $dom->html() . "\n";
		return undef;
	}

	return $field;
}

#
# send an email with the summary of the scrape
#
sub send_email
{
	my $verbose = shift || 0;

	open my $fh, "<", $tmp_file or die "couldn't open $tmp_file: $!";
	my $mail;
	$mail .= $_ for (<$fh>);
	close $fh;
	unlink($tmp_file) or warn "couldn't unlink $tmp_file: $!";

	return if ($verbose);
	my $email = Email::Simple->create(
		header => [
			From	=> "Price Sloth <www\@pricesloth.com>",
			To	=> $cfg->{general}{email},
			Subject	=> "weekly product scrape",
		],
		body => $mail
	);

	my $sender = Email::Send->new({mailer => "SMTP"});
	$sender->mailer_args([Host => $cfg->{"general"}{"smtp"}]);
	$sender->send($email->as_string()) || print "Couldn't send email\n";
}

sub sleep_rand
{
	my $header = shift;
	my $upper_limit = shift || 0;

	my $sleep = int(rand($upper_limit));
	printf "$header: (%ss wait)\n", $sleep if ($args{v});
	sleep $sleep unless ($args{t});
}

sub can_open_tty
{
	no autodie;
	return open(my $tty, '+<', '/dev/tty');
}

sub sleep_if_cron
{
	if (can_open_tty()) {
		return;
	}

	# 577s is appx 9.5 min
	my $sleep = arc4random_uniform(577);
	print "info: script run from cron, sleeping $sleep s\n" if ($args{v});

	# modify ps output to show what state the program is in
	my $old_argv0 = $0;
	$0 .= " (sleeping)";
	sleep $sleep;
	$0 = $old_argv0;
}
