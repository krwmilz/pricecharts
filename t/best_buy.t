use strict;
use PS::BestBuy;
use Log::Log4perl qw(:easy);
use Test;

BEGIN { plan tests => 13 }

Log::Log4perl->easy_init($INFO);

my $ua = PS::UserAgent->new();
my $bb = PS::BestBuy->new();

#
# Search for a Samsung television I know they have
my $search_url = $bb->create_search("Samsung", "UN55JS8500FXZC");
my $resp = $ua->get_dom($search_url);
ok($resp->is_success);

# Check that the object is working
my ($obj_resp) = $bb->find_product_page($resp);
ok($obj_resp->base, $resp->base);

# Make sure the part number we scrape is correct
my $part_num = $bb->scrape_part_num($resp);
ok($part_num, "UN55JS8500FXZC");

# Make sure the price we scrape is at least close to correct
my $price = $bb->scrape_price($resp);
ok($price);
ok($price > 2000.0);
ok($price < 2400.0);

my $descr = $bb->scrape_description($resp);
ok($descr, "Samsung 55\" 4K Ultra HD 3D LED Tizen Smart OS TV");

#
# Search for something that returns multiple results
my $search_url = $bb->create_search("Samsung", "UN55");
$resp = $ua->get_dom($search_url);
ok($resp->is_success);

my ($obj_resp, @others) = $bb->find_product_page($resp);
ok(@others, 10);
ok($obj_resp->is_success);

#
# Search for something non existent
my $search_url = $bb->create_search("", "some non-existent product name");
$resp = $ua->get_dom($search_url);
ok($resp->is_success);

my ($obj_resp) = $bb->find_product_page($resp);
ok( !defined $obj_resp );

# Check we get the no results found error
ok( $resp->decoded_content, "/Sorry, we couldn.t find any results./");
