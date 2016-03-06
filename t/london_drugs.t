use strict;
use PS::UserAgent;
use PS::LondonDrugs;
use Log::Log4perl qw(:easy);
use Test;

BEGIN { plan tests => 14 }

Log::Log4perl->easy_init($INFO);

my $ua = PS::UserAgent->new();
my $ld = PS::LondonDrugs->new();

#
# Search for a Samsung television I know they have
my $search_url = $ld->create_search("Samsung", "UN55JS9000");
my $resp = $ua->get_dom($search_url);
ok($resp->is_success);

# Check that the object is working
my ($obj_resp) = $ld->find_product_page($resp);
ok($obj_resp->base, $resp->base);

# Make sure the part number we scrape is correct
my $part_num = $ld->scrape_part_num($resp);
ok($part_num, "UN55JS9000");

# Make sure the price we scrape is at least close to correct
my ($price, @others) = $ld->scrape_price($resp);
ok($price);
ok(@others == 0);
ok($price > 2000.0);
ok($price < 3000.0);

my $descr = $ld->scrape_description($resp);
ok($descr, "Samsung 55\" JS9000 Series SUHD 4K Curved Smart TV");

#
# Search for something that returns multiple results
my $search_url = $ld->create_search("Samsung", "UN55");
my $resp = $ua->get_dom($search_url);
ok($resp->is_success);

# Searching for the above product yields multiple results.
my ($obj_resp, @others) = $ld->find_product_page($resp);
ok(@others, 6);
ok($obj_resp->is_success);

#
# Search for something non existent
my $search_url = $ld->create_search("", "some product that for sure doesnot exist");
$resp = $ua->get_dom($search_url);
ok($resp->is_success);

#ok($resp->base =~ /.*\/Search\/.*/);

my ($obj_resp) = $ld->find_product_page($resp);
ok( !defined $obj_resp );

# Check we get the no results found error
ok( $resp->decoded_content,
    "/We're sorry, no products were found for your search/");
