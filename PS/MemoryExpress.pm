package PS::MemoryExpress;
use strict;

use HTML::Grabber;
use Log::Log4perl qw(:easy);
use URI::Escape;

use PS::Database;
use PS::UserAgent;

my $logger = Log::Log4perl::get_logger('pricesloth.memory_express');


sub new {
	my ($class) = @_;

	my $self = {
		color => "#56B849",
		url => "http://www.memoryexpress.com/Search/Products?Search=",
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

	# As learned in the Seagate ST8000AS0002 case searching for manufacturer
	# concatenated to part num will hide valid search results.
	# Instead search only for part number. We'll have to deal with thumbnail
	# view return vs a full page product.
	return $self->{url} . uri_escape($part_num);
}

sub scrape_part_num {
	my ($self, $resp) = @_;
	my $dom = HTML::Grabber->new( html => $resp->decoded_content );

	# Product part number is inside of this div id
	my $product_add = $dom->find("#ProductAdd")->text();
	my ($part_num) = ($product_add =~ m/Part #:\s*(.*)\r/);
	return $part_num;
}

sub scrape_price {
	my ($self, $resp) = @_;
	my $dom = HTML::Grabber->new( html => $resp->decoded_content );

	my $grand_total_tag = $dom->find(".GrandTotal")->text();
	# -> text() does not trim all whitespace
	$grand_total_tag =~ s/^\s+//;
	$grand_total_tag =~ s/\s+$//;

	# Try and match a dollars dot cents format with leeway for comma
	# separated digits.
	# This also remove the "Only" text right beside the price.
	my ($price, @others) = ($grand_total_tag =~ m/(\d[\d,]+.\d\d)/);
	$logger->warn("memexp: found more than 1 price") if (@others);

	# Remove any commas we may have matched earlier
	$price =~ s/,//;

	return ($price, @others);
}

sub scrape_description {
	my ($self, $resp) = @_;
	my $dom = HTML::Grabber->new( html => $resp->decoded_content );

	# Product page description is inside <h1> tags
	my $description = $dom->find(".PDH_HeaderBlock h1")->text();
	return $description;
}

sub find_product_page {
	my ($self, $resp) = @_;
	my $ua = $self->{ua};

	my $uri = $resp->base;
	if ($uri =~ /.*\/Products\/.*/) {
		# We landed on the product page directly, great.
		return ($resp);
	}
	elsif ($uri =~ /.*\/Search\/.*/) {
		# We landed on the search page.
		my $dom = HTML::Grabber->new( html => $resp->decoded_content );

		# We're only going to search the first page of results
		my ($first_result, @others) = $dom->find('.PIV_Regular')->html_array();
		return unless ($first_result);

		my $thumb_dom = HTML::Grabber->new( html => $first_result );
		my $product_id = $thumb_dom->find(".ProductId")->text();
		return unless ($product_id);

		my $product_url = "http://www.memoryexpress.com/Products/" . $product_id;

		$resp = $ua->get_dom($product_url);
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
	return unless ($search);

	my $resp = $ua->get_dom($search);
	return unless ($resp->is_success);

	# Searching can sometimes take you to different places
	($resp) = $self->find_product_page($resp);
	return unless ($resp);

	# my $part_num = $self->scrape_part_num($resp);
	my ($price) = $self->scrape_price($resp);
	my $desc = $self->scrape_description($resp);

	$db->insert_price($manufacturer, $part_num, "Memory Express", $price, time - $start);
	$db->insert_descr($manufacturer, $part_num, "Memory Express", $desc) if ($desc);

	$logger->debug("scrape_price(): added price \$$price\n");
	return $price;
}
