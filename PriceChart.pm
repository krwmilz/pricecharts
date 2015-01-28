package PriceChart;

use DBI;
use Exporter;

@ISA = ("Exporter");
@EXPORT = qw(get_config get_dom get_ua get_log get_dbh);


sub get_config
{
	my $parser = Config::Grammar->new({
		_vars => [
			'user_agent',
			'email',
			'smtp',
		],
	});
	my $cfg_file = "/etc/pricechart.cfg";
	return $parser->parse($cfg_file) or die "error: $parser->{err}\n";
}

sub get_dbh
{
	my $db_dir = "/var/www/db";
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
		if (length($url) > 60) {
			$url = "..." . substr($url, length($url) - 60);
		}
		print "GET $url " . $resp->status_line . "\n" if ($verbose);
		return HTML::Grabber->new(html => $resp->decoded_content);
	}

	print "GET $url " . $resp->status_line . "\n";
	return undef;
}

sub get_ua
{
	my $cfg = shift;

	my $ua = LWP::UserAgent->new(agent => $cfg->{user_agent});
	$ua->default_header("Accept" => "*/*");

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
