use strict;
use PS::UserAgent;
use PS::MemoryExpress;
use Log::Log4perl qw(:easy);
use Test;

BEGIN { plan tests => 17 }

Log::Log4perl->easy_init($INFO);

my $ua = PS::UserAgent->new();
my $me = PS::MemoryExpress->new();

# Search for a Seagate hard drive I know about
#
my $search_url = $me->create_search("ST8000AS0002");
my $resp = $ua->get_dom($search_url);
ok($resp->is_success);

# Check the returned URI is the product page directly
my $uri = $resp->base;
ok($uri =~ /.*\/Products\/.*/);

# Check that the object is working
my $obj_resp = $me->find_product_page($resp);
ok($obj_resp->base, $resp->base);

# Make sure the part number we scrape is correct
my $part_num = $me->scrape_part_num($resp);
ok($part_num, "ST8000AS0002");

# Make sure the price we scrape is at least close to correct
my ($price, @others) = $me->scrape_price($resp);
ok($price);
ok(@others == 0);
ok($price > 200.0);
ok($price < 400.0);


# Search for something I know has multiple results
#
my $search_url = $me->create_search("ST8000");
$resp = $ua->get_dom($search_url);
ok($resp->is_success);

# The returned URI should have been the search results page
$uri = $resp->base;
ok($uri =~ /.*\/Search\/.*/);

# Searching for the above product yields two results
my ($obj_resp, @others) = $me->find_product_page($resp);
ok($obj_resp->base =~ /.*\/Products\/.*/);
ok(@others, 1);
ok($obj_resp->is_success);


# Search for something that returns 0 results
#
my $search_url = $me->create_search("some nonexistent product here");
$resp = $ua->get_dom($search_url);
ok($resp->is_success);

$uri = $resp->base;
ok($uri =~ /.*\/Search\/.*/);

my ($obj_resp) = $me->find_product_page($resp);
ok( !defined $obj_resp );

# Check we get the no results found error
ok( $resp->decoded_content,
    "/We're sorry, but there are no products with the specified search parameters./");
