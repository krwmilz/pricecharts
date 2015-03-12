package PriceChart;

use DBI;
use Exporter;

@ISA = ("Exporter");
@EXPORT = qw(get_config get_dom get_log get_dbh trunc_line new_ua);


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
	my $verbose = shift || undef;

	mkdir $db_dir;
	my $dbh = DBI->connect(
		"dbi:SQLite:dbname=$db_dir/pricechart.db",
		"",
		"",
		{RaiseError => 1}
	) or die $DBI::errstr;

	print "info: get_dbh: opened $db_dir/pricechart.db\n" if ($verbose);
	return $dbh;
}

sub get_dom
{
	my $url = shift;
	my $ua = shift;
	my $verbose = shift;

	my $resp = $ua->get($url);
	if ($resp->is_success) {
		my $short_url = trunc_line($url, length($resp->status_line) + 11, 1);
		print "info: get_dom: " . $resp->status_line . " $short_url\n" if ($verbose);
		return HTML::Grabber->new(html => $resp->decoded_content);
	}

	print "error: get_dom: $url failed\n";
	print "error: " . $resp->status_line . "\n";
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
	$ua->default_header("User-Agent" => $cfg->{"user_agent"});

	my $headers = $ua->default_headers;
	for (sort keys %$headers) {
		my $header = trunc_line($headers->{$_}, length($_) + 18);
		print "info: new_ua: $_ => $header\n" if ($verbose);
	}

	return $ua;
}

sub get_log
{
	my $file = shift;
	my $verbose = shift || 0;
	my $log_dir = "/var/www/logs/pricechart";

	return undef unless defined $file;

	if ($verbose) {
		open my $log, '>&', STDOUT or die "$!";
		return $log;
	}

	mkdir $log_dir;
	open my $log, ">>", "$log_dir/$file.log" or die "$!";
	return $log;
}

sub trunc_line
{
	my $line = shift;
	my $prefix = shift || 0;
	my $front = shift || 0;

	my ($wchar) = Term::ReadKey::GetTerminalSize();
	if (length($line) < ($wchar - $prefix - 3)) {
		return $line;
	}

	if ($front) {
		my $chopped = substr($line, length($line) - ($wchar - $prefix - 3));
		return "..." . $chopped;
	}
	my $chopped = substr($line, 0, ($wchar - $prefix - 3));
	return $chopped . "...";
}

1;
