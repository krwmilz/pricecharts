#!/usr/bin/env perl

use strict;
use warnings;

use FCGI;
use Template;

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

my $config = {
	INCLUDE_PATH => "html"
};
my $template = Template->new($config);

while ($request->Accept() >= 0) {
	print "Content-Type: text/html\r\n\r\n";

	# for (sort keys %ENV) {
	# 	print "$_: $ENV{$_} <br>\n";
	# }

	read(STDIN, my $input, $ENV{CONTENT_LENGTH});
	(undef, $input) = split("=", $input);

	my $query = "select part_num from products where title like ? or part_num like ?";
	my $products = $dbh->selectcol_arrayref($query, undef,
		"%$input%", "%$input%");

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
