package PS::MemoryExpress;
use strict;

use HTML::Grabber;
use Log::Log4perl qw(:easy);
use URI::Escape;

use PS::Database;
use PS::UserAgent;

my $logger = Log::Log4perl::get_logger('pricesloth.memory_express');


# On sale:
# <div class="PIV_BotPrices">
# 	<div class="PIV_PriceRegular">Reg: <span>$359.99</span></div>
# 	<div class="PIV_PriceSale">
# 		$279.99
# 	</div>
# </div>
#
# Regular price:
# <div class="PIV_BotPrices">
# 	<div class="PIV_Price">
#		<span>$359.99</span>
#	</div>
# </div>

sub new {
	my ($class) = @_;

	my $self = {
		color => "#56B849",
		url => "http://www.memoryexpress.com/Search/Products?Search=",
		title => ".ProductTitle",
		reg_tag => ".PIV_Price",
		sale_tag => ".PIV_PriceSale",
		ua => PS::UserAgent->new(),
		db => PS::Database->new()
	};

	bless ($self, $class);
	$logger->debug("new(): success");

	# XXX: make sure row in retailer table is created

	return $self;
}

# Creates the URL search string.
sub create_search {
	my ($self, $part_num) = @_;

	# As learned in the Seagate ST8000AS0002 case searching for manufacturer
	# concatenated to part num will hide valid search results.
	# Instead search only for part number. We'll have to deal with thumbnail
	# view return vs a full page product.

	return $self->{url} . uri_escape($part_num);
}

sub find_price {
	my ($self, $srch_results) = @_;

	my @prices = $srch_results->find($self->{reg_tag})->text_array();
	if (@prices == 0) {
		$logger->debug("get_price(): no prices found");
		return;
	}

	my ($price, @others) = ($prices[0] =~ m/(\d[\d,]+)/);
	if (! defined $price) {
		$logger->warn("get_price(): found price containers but they contained no numeric price");
		return;
	}
	if (@others) {
		$logger->warn("get_price(): price container had more than 1 price");
		return;
	}

	$price =~ s/,//;

	if ($price <= 0 || $price > 10000) {
		$logger->warn("get_price(): price '$price' out of range");
		return;
	}

	return $price;
}

sub scrape_price {
	my ($self, $manufacturer, $part_num) = @_;
	my $ua = $self->{ua};

	my $search = $self->create_search($part_num);
	return unless ($search);

	my $srch_results = $ua->get_dom($search);
	return unless ($srch_results);

	my $price = $self->find_price($srch_results);
	return unless ($price);

	my $sql = qq{insert into prices(date, manufacturer, part_num, retailer,
	price, duration) values (?, ?, ?, ?, ?, ?)};
	my $dbh = $self->{db}->{dbh};
	my $prices_sth = $dbh->prepare($sql);

	$dbh->begin_work;
	$prices_sth->execute(time, $manufacturer, $part_num, "Memory Express", $price, 99);
	$dbh->commit;

	$logger->debug("scrape_price(): added price \$$price\n");
	return $price;
}
