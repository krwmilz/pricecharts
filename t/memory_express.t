use strict;
use PS::UserAgent;
use PS::MemoryExpress;
use Log::Log4perl qw(:easy);
use Test;

BEGIN { plan tests => 20 }

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

my $dom = HTML::Grabber->new( html => $resp->decoded_content );
ok($dom);

# Product part number is inside of this div id
my $product_add = $dom->find("#ProductAdd")->text();
my ($part_num) = ($product_add =~ m/Part #:\s*(.*)\r/);
ok($part_num, "ST8000AS0002");

# We know we're on the product page
my $grand_total_tag = $dom->find(".GrandTotal")->text();
# ->text() doesn't trim all the garbage whitespace
$grand_total_tag =~ s/^\s+//;
$grand_total_tag =~ s/\s+$//;

# Final massaging, remove "Only" text that's right beside the price
my ($price, @others) = ($grand_total_tag =~ m/(\d[\d,]+.\d\d)/);
ok($price);
ok(@others == 0);

# Remove any commas we may have matched earlier
$price =~ s/,//;

ok($price > 0.0);
ok($price < 10000.0);


# Search for something I know has multiple results
#
my $search_url = $me->create_search("ST8000");
$resp = $ua->get_dom($search_url);
ok($resp->is_success);

# The returned URI should have been the search results page
$uri = $resp->base;
ok($uri =~ /.*\/Search\/.*/);

my $dom = HTML::Grabber->new( html => $resp->decoded_content );
ok($dom);

# There's two of these tags, one at the top of the page and one at the bottom
my ($ajax_list_pager) = $dom->find('.AJAX_List_Pager')->text_array();
ok($ajax_list_pager);

# Match multiple lines and replace multiple times
$ajax_list_pager =~ s/\r\n//mg;
ok($ajax_list_pager, "/1/");

# Searching for the above product yields two results
my ($first_result, @other) = $dom->find('.PIV_Regular')->html_array();
ok(@other, 1);

my $thumb = HTML::Grabber->new( html => $first_result );
my $product_id = $thumb->find(".ProductId")->text();
ok($product_id);

my $product_url = "http://www.memoryexpress.com/Products/" . $product_id;
$resp = $ua->get_dom($product_url);
ok($resp->is_success);


# Search for something that returns 0 results
#
my $search_url = $me->create_search("some nonexistent product here");
$resp = $ua->get_dom($search_url);
ok($resp->is_success);

$uri = $resp->base;
ok($uri =~ /.*\/Search\/.*/);

my $dom = HTML::Grabber->new( html => $resp->decoded_content );
ok($dom);

# Check we get the no results found error
ok($dom->text, "/We're sorry, but there are no products with the specified search parameters./");
