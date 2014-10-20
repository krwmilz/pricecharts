#!/usr/bin/env perl

use strict;
use warnings;

use FCGI;

use shared;

my $cfg = get_config();
my $dbh = get_dbh($cfg);

mkdir "$cfg->{general}{var}/www/run";
my $socket_path = "$cfg->{general}{var}/www/run/search.sock";

my $socket = FCGI::OpenSocket($socket_path, 1024);
my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
	$socket, FCGI::FAIL_ACCEPT_ON_INTR);

chmod 0777, $socket_path;
sub sigint
{
	$request->LastCall();
}
$SIG{INT} = \&sigint;

while ($request->Accept() >= 0) {
	print "Content-Type: text/html\r\n\r\n";
	print "Hello, World!<br>\n";

	for (sort keys %ENV) {
		print "$_: $ENV{$_} <br>\n";
	}

	read(STDIN, my $input, $ENV{CONTENT_LENGTH});
	(undef, $input) = split("=", $input);
	print "querying for: $input <br>\n";

	my $query = "select * from products where title like ?";
	my $products = $dbh->selectall_arrayref($query, undef, "%$input%");

	print "found " . scalar @$products . " products <br>\n";

	for (@$products) {
		print "$_->[2] <br>\n";
	}
}

FCGI::CloseSocket($socket);
$dbh->disconnect();
