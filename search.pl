#!/usr/bin/env perl

use strict;
use warnings;

use FCGI;
use Template;

use shared;


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

my $config = {
	INCLUDE_PATH => "html"
};
my $template = Template->new($config);

my $query = "select part_num from products where title like ? or part_num like ?";
my $search_sth = $dbh->prepare($query);

while ($request->Accept() >= 0) {
	print "Content-Type: text/html\r\n\r\n";

	# for (sort keys %ENV) {
	# 	print "$_: $ENV{$_} <br>\n";
	# }

	my (undef, $input) = split("=", $ENV{QUERY_STRING});

	$search_sth->execute("%$input%", "%$input%");
	my $products = $search_sth->fetchall_arrayref();

	my $vars = {
		query => "\"$input\"",
		num_results => scalar @$products,
		results => $products
	};

	my $r = $template->process("search.html", $vars);
	if ($r) {
		print $template->error();
	}
}

FCGI::CloseSocket($socket);
$dbh->disconnect();
