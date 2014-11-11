#!/usr/bin/env perl

use strict;
use warnings;

use FCGI;
use Getopt::Std;
use Template;
use Proc::Daemon;
use Unix::Syslog qw(:macros :subs);
use URI::Escape;

use shared;


my %args;
getopts("d", \%args);

my $socket_file = "/var/www/run/search.sock";
if (-e $socket_file) {
	print "Not starting, socket $socket_file exists\n";
	exit;
}

openlog("pricechart_search", 0, LOG_DAEMON);
syslog(LOG_INFO, "startup");

my (undef, undef, $www_uid)           = getpwnam("www");
my (undef, undef, undef, $daemon_gid) = getpwnam("daemon");

my $socket = FCGI::OpenSocket($socket_file, 1024);
chown $www_uid, $daemon_gid, $socket_file;
syslog(LOG_INFO, "$socket_file created");

my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
	$socket, FCGI::FAIL_ACCEPT_ON_INTR);

if ($args{d}) {
	# stay in foreground, catch ctrl-c's
	$SIG{INT} = \&sig_handler;
}
else {
	# background
	my $daemon = Proc::Daemon->new(
		setuid       => $www_uid,
		work_dir     => "/var/www",
		dont_close_fd => [ $socket ],
	);
	$daemon->Init();
}

# shut down cleanly on kill
$SIG{TERM} = \&sig_handler;

my $config = {
	# XXX: this needs to be fixed
	INCLUDE_PATH => "/home/kyle/src/pricechart/html"
};
my $template = Template->new($config);

my $dbh = get_dbh();
syslog(LOG_INFO, "database opened");

my $sql = "select part_num, manufacturer, description from products " .
	"where description like ? or part_num like ? or manufacturer like ?";
my $search_sth = $dbh->prepare($sql);

syslog(LOG_INFO, "ready, listening for connections");
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

	$template->process("search.html", $vars) || print $template->error();
}

syslog(LOG_INFO, "shutting down");

FCGI::CloseSocket($socket);
unlink($socket_file) or syslog(LOG_WARNING, "could not unlink $socket_file: $!");

closelog();
$dbh->disconnect();

sub sig_handler
{
	my $signame = shift;

	$request->LastCall();
	syslog(LOG_INFO, "caught SIG$signame");
}
