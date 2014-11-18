#!/usr/bin/env perl

use strict;
use warnings;

use FCGI;
use Getopt::Std;
use Template;
use PriceChart::Shared;
use Unix::Syslog qw(:macros :subs);
use URI::Escape;


my %args;
getopts("d", \%args);

my $socket_file = "/var/www/run/search.sock";
if (-e $socket_file) {
	print "Not starting, socket $socket_file exists\n";
	exit;
}

if (!$args{d} && fork()) {
	exit;
}

openlog("pricechart_search", LOG_PID, LOG_DAEMON);

my $socket = FCGI::OpenSocket($socket_file, 1024);
syslog(LOG_DEBUG, "$socket_file created");

if (my $child_pid = fork()) {
	# keep the parent around to clean up the socket after we're done

	$SIG{INT} = \&parent_sig;
	$SIG{TERM} = \&parent_sig;
	sub parent_sig
	{
		my $signal = shift;
		kill $signal, $child_pid;
	}

	# wait for the child to finish
	waitpid($child_pid, 0);

	FCGI::CloseSocket($socket);
	unlink($socket_file) or
		syslog(LOG_WARNING, "could not unlink $socket_file: $!");
	closelog();
	exit;
}

my $uid = getpwnam("www");
my $gid = getgrnam("daemon");

# change ownership on socket otherwise httpd can't talk to us
chown $uid, $gid, $socket_file;

# drop privileges
$< = $> = $uid;
$( = $) = "$gid $gid";

my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
	$socket, FCGI::FAIL_ACCEPT_ON_INTR);

$SIG{INT} = \&child_sig;
$SIG{TERM} = \&child_sig;
sub child_sig
{
	my $signame = shift;

	$request->LastCall();
	syslog(LOG_DEBUG, "caught SIG$signame");
}

my $config = {
	# XXX: this needs to be fixed
	INCLUDE_PATH => "/home/kyle/src/pricechart/html"
};
my $template = Template->new($config);

my $dbh = get_dbh();
syslog(LOG_DEBUG, "database opened");

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

	$template->process("search.html", $vars) || print $template->error();
}
syslog(LOG_INFO, "shut down");
$dbh->disconnect();
