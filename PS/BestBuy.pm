package PS::BestBuy;
use strict;

use HTML::Grabber;
use Log::Log4perl qw(:easy);
use URI::Escape;

use PS::Database;
use PS::UserAgent;

my $logger = get_logger('pricesloth.best_buy');

sub new {
	my ($class) = @_;

	my $self = {
		color => "#003B64",
		url => "http://www.bestbuy.ca/Search/SearchResults.aspx?query=",
		ua => PS::UserAgent->new(),
		db => PS::Database->new()
	};

	bless ($self, $class);
	$logger->debug("new(): success");

	# XXX: make sure row in retailer table is created

	return $self;
}

sub create_search {
	my ($self, $manufacturer, $part_num) = @_;

	return $self->{url} . uri_escape("$manufacturer $part_num");
}

sub scrape_part_num {
	my ($self, $resp) = @_;
	my $dom = HTML::Grabber->new( html => $resp->decoded_content );

	# Part number is inside this ridiculous tag. Seems to be page unique
	# too.
	my $part_num = $dom->find("#ctl00_CP_ctl00_PD_lblModelNumber")->text();
	return $part_num;
}

sub scrape_description {
	my ($self, $resp) = @_;
	my $dom = HTML::Grabber->new( html => $resp->decoded_content );

	my $title = $dom->find("#ctl00_CP_ctl00_PD_lblProductTitle")->text();
	# Part number is at the end, regex that out
	my ($descr) = ($title =~ /(.*) \(.+\)/);
	return $descr;
}

sub scrape_price {
	my ($self, $resp) = @_;
	my $dom = HTML::Grabber->new( html => $resp->decoded_content );

	my $price = $dom->find(".price-wrapper .prodprice")->text();
	$price =~ s/^\s+//;
	$price =~ s/\s+$//;
	# Remove dollar sign and any commas between digits
	$price =~ s/^\$//;
	$price =~ s/,//;

	return $price;
}

sub find_product_page {
	my ($self, $resp) = @_;
	my $ua = $self->{ua};

	my $product_url = "http://www.bestbuy.ca/en-CA/product/";
	my $search_url = "http://www.bestbuy.ca/Search/SearchResults.aspx?";
	# The search url has "//" characters that need to be escaped before
	# being used in regular expressions
	$search_url = quotemeta $search_url;
	$product_url = quotemeta $product_url;

	my $uri = $resp->base;
	if ($uri =~ /$product_url/) {
		# We landed on the product page directly, great.
		return ($resp);
	}
	elsif ($uri =~ m/$search_url/) {
		# We landed on the search page.
		my $dom = HTML::Grabber->new( html => $resp->decoded_content );

		my ($first_result, @others) = $dom->find(".listing-items .listing-item")->html_array();
		return unless $first_result;

		my $first_dom = HTML::Grabber->new( html => $first_result );
		my $product_url = $first_dom->find(".prod-title a")->attr("href");

		my $base_url = "http://www.bestbuy.ca";
		my $resp = $ua->get_dom($base_url . $product_url);
		return unless $resp->is_success;

		return ($resp, @others);
	}
	else {
		$logger->error("find_product_page(): unexpected search URI '$uri'");
		return;
	}
}

sub scrape {
	my ($self, $manufacturer, $part_num) = @_;
	my $ua = $self->{ua};
	my $db = $self->{db};
	my $start = time;

	my $search = $self->create_search($manufacturer, $part_num);
	my $resp = $ua->get_dom($search);
	return unless ($resp->is_success);

	# Searching can sometimes take you to different places
	($resp) = $self->find_product_page($resp);
	return unless ($resp);

	# my $part_num = $self->scrape_part_num($resp);
	my ($price) = $self->scrape_price($resp);
	my $desc = $self->scrape_description($resp);

	$db->insert_price($manufacturer, $part_num, "Best Buy", $price, time - $start);
	$db->insert_descr($manufacturer, $part_num, "Besy Buy", $desc) if ($desc);

	$logger->debug("scrape_price(): added price \$$price\n");
	return $price;
}
