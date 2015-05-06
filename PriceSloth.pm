package PriceSloth;

use DBI;
use File::Path qw(make_path);
use Exporter;

@ISA = ("Exporter");
@EXPORT = qw(get_config get_dom get_log get_dbh trunc_line new_ua make_path spin);


sub get_config
{
	my $parser = Config::Grammar->new({
		_sections => ["general", "http", "retailers"],
		general => {
			_vars => [
				"agent",
				"email",
				"smtp",
				# XXX: add simple regex validation here
				"addrs",
				"db_dir",
				"log_dir",
			],
		},
		http => {
			_vars => [
				"socket",
				"uid",
				"gid",
				"chroot",
				"htdocs",
			],
		},
		retailers => {
			_sections => ["/[A-Za-z ]+/"],
			"/[A-Za-z ]+/" => {
				_vars => [
					"url",
					"reg_tag",
					"sale_tag",
					"color",
					"title"
				]
			}
		}
	});

	my $cfg_file = "/etc/pricesloth.cfg";
	my $cfg = $parser->parse($cfg_file) or die "error: $parser->{err}\n";

	return $cfg;
}

sub get_dbh
{
	my $db_dir = shift;
	my $verbose = shift || undef;

	make_path($db_dir, { verbose => $verbose });
	print "info: get_dbh: opening $db_dir/db\n" if ($verbose);
	my $dbh = DBI->connect(
		"dbi:SQLite:dbname=$db_dir/db",
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
	my $log = shift;

	my $resp = $ua->get($url);
	if ($resp->is_success) {
		my $short_url = trunc_line($url, length($resp->status_line) + 16);
		print "info: get_dom: " . $resp->status_line . " $short_url\n" if ($verbose);
		return HTML::Grabber->new(html => $resp->decoded_content);
	}

	print $log "error: get_dom: " . $resp->status_line . " $url\n";
	return undef;
}

sub new_ua
{
	my $cfg = shift;
	my $verbose = shift || 0;
	my $ua;

	# it's optional to list ip addresses to scrape on
	if ($cfg->{addrs}) {
		my @addresses = split(" ", $cfg->{addrs});
		my $addr = $addresses[rand @addresses];
		print "info: new_ua: using ip $addr\n" if ($verbose);
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

	my $headers = $ua->default_headers;
	for (sort keys %$headers) {
		my $header = trunc_line($headers->{$_}, length($_) + 18);
		print "info: new_ua: $_ => $header\n" if ($verbose);
	}

	return $ua;
}

sub get_log
{
	my $log_path = shift || return undef;
	my $verbose = shift || 0;

	# if $log_path has a / in it, make sure the path to it is made
	make_path(substr($log_path, 0, rindex($log_path, '/')), { verbose => $verbose });

	print "info: get_log: opening $log_path, append mode\n" if ($verbose);
	open my $log, ">>", $log_path or die "can't open $log_path: $!";

	if ($verbose) {
		print "info: get_log: outputting to tee\n";
		open my $std_out, '>&', STDOUT or die "$!";

		return IO::Tee->new($log, $std_out);
	}

	return IO::Tee->new($log);
}

#
# make a possibly long line fit on a single line, with ellipses
#
sub trunc_line
{
	my $line = shift || return undef;
	my $prefix = shift || 0;

	# if stdout is not a tty, it's likely a log file, output everything
	return $line unless (POSIX::isatty(STDOUT));

	my ($term_width) = Term::ReadKey::GetTerminalSize();
	my $len = $term_width - $prefix - 3;
	if (length($line) < $len) {
		return $line;
	}

	my $chopped = substr($line, 0, $len);
	return $chopped . "...";
}

my $state = 0;
sub spin
{
	my @spin_states = ("-", "\\", "|", "/");

	print "\b";
	print $spin_states[++$state % 4];
}

1;
