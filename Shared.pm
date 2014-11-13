package PriceChart::Shared;

use DBI;
use Exporter;
use POSIX;

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

	my $resp = $ua->get($url);
	if (! $resp->is_success) {
		print "getting $url failed: " . $resp->status_line . "\n";
		return undef;
	}
	return HTML::Grabber->new(html => $resp->decoded_content);
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
	my $log_dir = "/var/www/logs/pricechart";

	mkdir $log_dir;
	open my $log, ">>", "$log_dir/$file.log" || die "$!";

	print $log strftime "%b %e %Y %H:%M ", localtime;
	return $log;
}

1;
