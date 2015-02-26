package PriceChart;

use DBI;
use Exporter;

@ISA = ("Exporter");
@EXPORT = qw(get_config get_dom new_ua get_log get_dbh);


sub get_config
{
	my $parser = Config::Grammar->new({
		_sections => ["general", "http", "vendors"],
		general => {
			_vars => [
				'user_agent',
				'email',
				'smtp',
				"db"
			],
		},
		http => {
			_vars => [
				"socket_file",
				"uid",
				"gid",
				"chroot",
				"db_dir",
				"htdocs",
				"templates",
			],
		},
		vendors => {
			_sections => ["/[A-Za-z ]+/"],
			"/[A-Za-z ]+/" => {
				_vars => [
					"search_url",
					"price_regular",
					"price_sale",
					"color",
					"title"
				]
			}
		}
	});

	my $cfg_file = "/etc/pricechart.cfg";
	my $cfg = $parser->parse($cfg_file) or die "error: $parser->{err}\n";

	return $cfg;
}

sub get_dbh
{
	my $cfg = shift;
	my $db_dir = shift || $cfg->{"db"};
	mkdir $db_dir;

	my $dbh = DBI->connect(
		"dbi:SQLite:dbname=$db_dir/pricechart.db",
		"",
		"",
		{ RaiseError => 1 }
	) or die $DBI::errstr;

	return $dbh;
}

sub get_dom
{
	my $url = shift;
	my $ua = shift;
	my $verbose = shift;

	my $resp = $ua->get($url);
	if ($resp->is_success) {
		if (length($url) > 55) {
			$url = "..." . substr($url, length($url) - 55);
		}
		print "info: GET $url " . $resp->status_line . "\n" if ($verbose);
		return HTML::Grabber->new(html => $resp->decoded_content);
	}

	print "error: GET $url " . $resp->status_line . "\n";
	return undef;
}

sub new_ua
{
	my $cfg = shift;
	my $verbose = shift || 0;

	my $ua = LWP::UserAgent->new();
	$ua->default_header("Accept" => "*/*");
	$ua->default_header("Accept-Encoding" => scalar HTTP::Message::decodable());
	$ua->default_header("Accept-Charset" => "utf-8");
	$ua->default_header("Accept-Language" => "en-US");
	$ua->default_header("Host" => "localhost:8177");
	$ua->default_header("User-Agent" => $cfg->{"user_agent"});

	while (my ($name, $value) = each %{$ua->default_headers}) {
		print "info: new_ua: $name: $value\n";
	}

	return $ua;
}

sub get_log
{
	my $file = shift;
	my $verbose = shift;
	my $log_dir = "/var/www/logs/pricechart";

	if ($verbose) {
		open my $log, '>&', STDOUT or die "$!";
		return $log;
	}

	mkdir $log_dir;
	open my $log, ">>", "$log_dir/$file.log" or die "$!";
	return $log;
}

1;
