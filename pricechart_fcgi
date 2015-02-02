#!/usr/bin/env perl

use strict;
use warnings;

# because we chroot all dependencies must be explicitly listed
use Config::Grammar;
use DBD::SQLite;
use Encode;
use FCGI;
use Getopt::Std;
use Template;
use Template::Context;
use Template::Filters;
use Template::Iterator;
use Template::Parser;
use Template::Plugins;
use Template::Stash::XS;
use PriceChart;
use Unix::Syslog qw(:macros :subs);
use URI::Escape;


my %args;
getopts("v", \%args);

# fork into background unless verbose
unless ($args{v}) {
	if (fork()) {
		exit;
	}
}

my $cfg = get_config();
my $db_dir = $cfg->{"http"}{"db_dir"};
my $socket_file = $cfg->{"http"}{"socket_file"};
my $uid_name = $cfg->{"http"}{"uid"};
my $gid_name = $cfg->{"http"}{"gid"};

# this looks up information in /etc
my $uid = getpwnam($uid_name) or die "error: uid does not exist";
my $gid = getgrnam($gid_name) or die "error: gid does not exist";
print "info: $uid_name:$gid_name -> $uid:$gid\n" if ($args{v});;

chroot($cfg->{"http"}{"chroot"});
chdir("/");
print "info: chroot done\n" if ($args{v});

# XXX: verify we have indeed dropped privileges?
$< = $> = $uid;
$( = $) = "$gid $gid";
print "info: uid:gid set to $<:$(\n" if ($args{v});

openlog("pricechart_fcgi", LOG_PID, LOG_DAEMON);
print "info: open syslog ok\n" if ($args{v});

if (-e $socket_file) {
	my $msg = "socket file $socket_file exists\n";
	print "error: $msg\n" if ($args{v});
	syslog(LOG_ERR, $msg);
	exit;
}

# XXX: i need to be sudo for this to work? after we've dropped privileges?
my $socket = FCGI::OpenSocket($socket_file, 1024);
print "info: open $socket_file ok\n" if ($args{v});

my $dbh = get_dbh($db_dir);
print "info: open $db_dir/pricechart.db ok\n" if ($args{v});

my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
	$socket, FCGI::FAIL_ACCEPT_ON_INTR);

$SIG{INT} = \&child_sig;
$SIG{TERM} = \&child_sig;

my $config = {
	INCLUDE_PATH => "/htdocs/pricechart/templates"
};
my $template = Template->new($config) || die $Template::ERROR . "\n";
print "info: template config ok\n" if ($args{v});

my $sql = "select part_num, manufacturer, description from products " .
	"where description like ? or part_num like ? or manufacturer like ?";
my $search_sth = $dbh->prepare($sql);

syslog(LOG_INFO, "startup");
while ($request->Accept() >= 0) {
	print "Content-Type: text/html\r\n\r\n";
	my (undef, $input) = split("=", $ENV{QUERY_STRING});

	# incoming query string is http mangled
	$input = uri_unescape($input);

	$search_sth->execute("%$input%", "%$input%", "%$input%");
	my $products = $search_sth->fetchall_arrayref();

	my $vars = {
		query => $input,
		num_results => scalar @$products,
		results => $products
	};

	$template->process("search.html", $vars) or print $template->error();
}
syslog(LOG_INFO, "shutdown");
closelog();

$dbh->disconnect();

FCGI::CloseSocket($socket);
unlink($socket_file) or print "error: could not unlink $socket_file: $!";

sub child_sig
{
	my $signame = shift;

	$request->LastCall();
	print "info: caught SIG$signame\n" if ($args{v});
}
