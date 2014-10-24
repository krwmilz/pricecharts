#!/usr/bin/env perl

package shared;
use Config::Grammar;
use DBI;
use Exporter;
use Getopt::Std;
use HTML::Grabber;
use LWP::Simple;

@ISA = ("Exporter");
@EXPORT = qw(get_dom get_ua get_log vprint vprintf %args $cfg $dbh);


our %args;
getopts('f:np:v', \%args);

$| = 1 if ($args{v});

if (!$args{f}) {
	if (-e "etc/pricechart.cfg") {
		$cfg_file = "etc/pricechart.cfg";
	} else {
		$cfg_file = "/etc/pricechart.cfg";
	}
}

my $parser = Config::Grammar->new({
	_sections => ['vendors', 'general'],
	vendors	=> {
		# vendor regular expression
		_sections => ['/[A-Za-z ]+/'],
		'/[A-Za-z ]+/' => {
			_vars => ['search_uri', 'reg_price', 'sale_price', 'color'],
		},
	},
	general => {
		_vars => [
			'var',
			'user_agent',
			'email',
			'smtp',
		],
	},
});

our $cfg =$parser->parse($cfg_file) or die "error: $parser->{err}\n";
make_dir($cfg->{general}{var});

my $db_dir = "$cfg->{general}{var}/db";
make_dir($db_dir);
our $dbh = DBI->connect(
	"dbi:SQLite:dbname=$db_dir/pricechart.db",
	"",
	"",
	{ RaiseError => 1 }
) or die $DBI::errstr;


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
	my $ua = LWP::UserAgent->new(agent => $cfg->{general}{user_agent});
	$ua->default_header("Accept" => "*/*");
	return $ua;
}

sub get_log
{
	my $file = shift;
	my $log_dir = "$cfg->{general}{var}/log";

	make_dir($log_dir);
	open my $log, ">>", "$log_dir/$file.txt";
	return $log;
}

sub make_dir
{
	my $dir = shift;

	unless (-e $dir or mkdir $dir) {
		die "Could not create directory $dir: $!\n"
	}
}

sub vprint
{
	print $_[0] if ($args{v});
}

sub vprintf
{
	printf(@_) if ($args{v});
}

1;
