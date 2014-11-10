#!/usr/bin/env perl

use strict;
use warnings;

use FCGI;
use Template;
use Proc::Daemon;
use POSIX;
use URI::Escape;

use shared;


my $pid_file = "/var/www/run/search.pid";
if (-e $pid_file) {
	print "Not starting, pid file $pid_file exists\n";
	exit;
}

# third field is uid
my @struct_passwd = getpwnam("www");
my $daemon = Proc::Daemon->new(
	setuid       => $struct_passwd[2],
	work_dir     => "/var/www",
	child_STDOUT => "logs/pricechart/search.txt",
	child_STDERR => "logs/pricechart/search.txt",
	pid_file     => $pid_file
);
$daemon->Init();

# shut down cleanly on kill
$SIG{TERM} = \&sig_handler;
# stdout/err doesn't get flushed to the log file otherwise
$| = 1;

my $socket_file = "/var/www/run/search.sock";
my $socket = FCGI::OpenSocket($socket_file, 1024);
print ftime() . "socket created on $socket_file\n";
my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
	$socket, FCGI::FAIL_ACCEPT_ON_INTR);
print ftime() . "fcgi request object created\n";

my $config = {
	# XXX: this needs to be fixed
	INCLUDE_PATH => "/home/kyle/src/pricechart/html"
};
my $template = Template->new($config);
print ftime() . "templete config created\n";

my $dbh = get_dbh();
print ftime() . "database opened\n";

my $sql = "select part_num, manufacturer, description from products " .
	"where description like ? or part_num like ? or manufacturer like ?";
my $search_sth = $dbh->prepare($sql);

print ftime() . "starting main accept loop\n";
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

print ftime() . "shutting down\n";
FCGI::CloseSocket($socket);
unlink($socket_file, $pid_file);
$dbh->disconnect();

sub sig_handler
{
	$request->LastCall();
	print ftime() . "caught signal\n";
}

sub ftime
{
	return strftime "%b %e %Y %H:%M ", localtime;
}
