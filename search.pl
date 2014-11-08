#!/usr/bin/env perl

use strict;
use warnings;

use FCGI;
use Template;
use Proc::Daemon;

use shared;
print "disconnecting dbh\n";
$dbh->disconnect();

my $pid_file = "$cfg->{general}{var}/run/pricegraph_search.pid";

if (-e $pid_file) {
	print "pid file $pid_file exists, search may already be running\n";
	print "make sure that search is not running and remove\n";
	exit
}

print "daemonizing\n";


my $daemon = Proc::Daemon->new(
	work_dir     => "/home/kyle/src/pricegraph",
	child_STDOUT => "log/search.txt",
	child_STDERR => "log/search.txt",
	pid_file     => $pid_file
);

$daemon->Init();

$SIG{INT} = \&sig_handler;
$SIG{TERM} = \&sig_handler;

print "assigned sig handlers\n";

mkdir "$cfg->{general}{var}/www/run";
my $socket_path = "$cfg->{general}{var}/www/run/search.sock";

print "made run dir\n";

my $socket = FCGI::OpenSocket($socket_path, 1024);
my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
	$socket, FCGI::FAIL_ACCEPT_ON_INTR);

print "made socket and request objects\n";

chmod 0777, $socket_path;

print "chmod 0777\n";

my $config = {
	INCLUDE_PATH => "html"
};
my $template = Template->new($config);

print "made new template config\n";

my $db_dir = "$cfg->{general}{var}/db";
my $dbh = DBI->connect(
	"dbi:SQLite:dbname=$db_dir/pricechart.db",
	"",
	"",
	{ RaiseError => 1 }
) or die $DBI::errstr;

print "opened db\n";

my $sql = "select part_num, manufacturer, description from products " .
	"where description like ? or part_num like ? or manufacturer like ?";
my $search_sth = $dbh->prepare($sql);

print "about to start main loop\n";

while ($request->Accept() >= 0) {
	print "Content-Type: text/html\r\n\r\n";

	# for (sort keys %ENV) {
	# 	print "$_: $ENV{$_} <br>\n";
	# }

	my (undef, $input) = split("=", $ENV{QUERY_STRING});

	$search_sth->execute("%$input%", "%$input%", "%$input%");
	my $products = $search_sth->fetchall_arrayref();

	my $vars = {
		query => "$input",
		num_results => scalar @$products,
		results => $products
	};

	my $r = $template->process("search.html", $vars);
	if ($r) {
		print $template->error();
	}
}

FCGI::CloseSocket($socket);
unlink($socket_path, $pid_file);
$dbh->disconnect();

sub sig_handler
{
	$request->LastCall();
	print "caught signal\n";
}
