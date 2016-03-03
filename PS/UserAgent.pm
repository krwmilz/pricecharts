package PS::UserAgent;

use LWP::UserAgent;
use Log::Log4perl qw(:easy);
use File::Path qw(make_path);

use PS::Config;

my $logger = Log::Log4perl->get_logger('pricesloth.useragent');

sub new {
	my $class = shift;
	my $self = {};
	bless ($self, $class);

	my $config = PS::Config->new();
	my $cfg = $config->{cfg}->{general};

	# it's optional to list ip addresses to scrape on
	my $ua;
	if ($cfg->{addrs}) {
		my @addresses = split(" ", $cfg->{addrs});
		my $addr = $addresses[rand @addresses];
		$logger->debug("new_ua: using ip $addr\n");
		$ua = LWP::UserAgent->new(local_address => $addr);
	}
	else {
		$ua = LWP::UserAgent->new();
	}

	$ua->default_header("Accept" => "*/*");
	$ua->default_header("Accept-Encoding" => scalar HTTP::Message::decodable());
	$ua->default_header("Accept-Charset" => "utf-8");
	$ua->default_header("Accept-Language" => "en-US");
	$ua->default_header("User-Agent" => $cfg->{agent});

	$self->{ua} = $ua;
	return $self;
}

sub get_dom {
	my ($self, $url) = @_;
	my $ua = $self->{ua};

	my $resp = $ua->get($url);
	if ($resp->is_success) {
		$logger->debug("get_dom: " . $resp->status_line . " $url\n");
		return $resp;
	}

	$logger->error("get_dom: " . $resp->status_line . " $url\n");
	return;
}

1;
