package PS::LondonDrugs;
use strict;

use HTML::Grabber;
use Log::Log4perl qw(:easy);
use URI::Escape;

use PS::Database;
use PS::UserAgent;

my $logger = get_logger('pricesloth.london_drugs');

sub new {
	my ($class) = @_;

	my $self = {
		color => "#005DAB",
		url => "http://www.londondrugs.com/on/demandware.store/Sites-LondonDrugs-Site/default/Search-Show?q=",
		title => ".productname",
		reg_tag	=> ".pricing",
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

	# London drugs search looks like it work well when both manufacturer and
	# part number are given.
	return $self->{url} . uri_escape("$manufacturer $part_num");
}

sub scrape_part_num {
	my ($self, $resp) = @_;
	my $dom = HTML::Grabber->new( html => $resp->decoded_content );

	my ($title) = $dom->find(".productname")->text_array();
	my ($part_num) = ($title =~ m/.* - (.*)\r/);
	return $part_num;
}

sub scrape_description {
	my ($self, $resp) = @_;
	my $dom = HTML::Grabber->new( html => $resp->decoded_content );

	my ($title) = $dom->find(".productname")->text_array();
	my ($descr) = ($title =~ m/^\s+(.*) - .*\r/);
	return $descr;
}

sub scrape_price {
	my ($self, $resp) = @_;
	my $dom = HTML::Grabber->new( html => $resp->decoded_content );

	# There are many .salesprice tags on the page but only one is inside of
	# .productpricing which is the main product on the page.
	my $price_container = $dom->find(".productpricing .salesprice")->text();
	$price_container =~ s/^\s+//;
	$price_container =~ s/\s+$//;

	# Try and match a dollars dot cents format with leeway for comma
	# separated digits.
	my ($price, @others) = ($price_container =~ m/(\d[\d,]+.\d\d)/);
	$logger->warn("memexp: found more than 1 price") if (@others);

	# Remove any commas we may have matched earlier
	$price =~ s/,//;

	return ($price, @others);
}

sub find_product_page {
	my ($self, $resp) = @_;
	my $ua = $self->{ua};

	my $search_url = $self->{url};
	# The search url has "//" characters that need to be escaped before
	# being used in regular expressions
	$search_url = quotemeta $search_url;

	my $uri = $resp->base;
	if ($uri =~ /http:\/\/www.londondrugs.com\/.*\.html/) {
		# We landed on the product page directly, great.
		return ($resp);
	}
	elsif ($uri =~ /$search_url/) {
		# We landed on the search page.
		my $dom = HTML::Grabber->new( html => $resp->decoded_content );

		my ($first_result, @others) = $dom->find(".productlisting .product")->html_array();
		return unless ($first_result);

		my $num_total = scalar (@others) + 1;
		$logger->debug("find_product_page(): found $num_total thumbnails");

		# For every thumbnail there is a div with class="name" with a
		# link to the product page inside
		my $thumb_dom = HTML::Grabber->new( html => $first_result );
		my $product_url = $thumb_dom->find(".name a")->attr('href');

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

	my $search = $self->create_search($manufacturer, $part_num);
	my $resp = $ua->get_dom($search);
	return unless ($resp->is_success);

	# Searching can sometimes take you to different places
	($resp) = $self->find_product_page($resp);
	return unless ($resp);

	# my $part_num = $self->scrape_part_num($resp);
	my ($price) = $self->scrape_price($resp);
	my $desc = $self->scrape_description($resp);

	my $sql = qq{insert into prices(date, manufacturer, part_num, retailer,
	price, duration) values (?, ?, ?, ?, ?, ?)};
	my $dbh = $self->{db}->{dbh};
	my $prices_sth = $dbh->prepare($sql);

	$dbh->begin_work;
	$prices_sth->execute(time, $manufacturer, $part_num, "London Drugs", $price, 100);
	$dbh->commit;

	$logger->debug("scrape_price(): added price \$$price\n");
	return $price;
}
