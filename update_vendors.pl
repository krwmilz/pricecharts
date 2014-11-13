#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Std;
use PriceChart::Shared;


my %args;
getopt("v:u:r:s:c:", \%args);

if (!$args{v}) {
	print "Argument -v must be present\n";
	exit
}

my $dbh = get_dbh();

$dbh->do("create table if not exists vendors(" .
	"name text not null primary key, " .
	"search_url not null, " .
	"price_tag not null, " .
	"sale_tag, " .
	"color text not null)") or die $DBI::errstr;

my $sql = "update vendors set search_url = ?, price_tag = ?, sale_tag = ?, " .
	"color = ? where name = ?";
my $update_sth = $dbh->prepare($sql);

$sql = "insert into vendors(name, search_url, price_tag, sale_tag, color) " .
	"values (?, ?, ?, ?, ?)";
my $insert_sth = $dbh->prepare($sql);

$sql = "select * from vendors where name = ?";
if ($dbh->selectrow_arrayref($sql, undef, $args{v})) {
	$update_sth->execute($args{u}, $args{r}, $args{s}, $args{c}, $args{v});
}
else {
	$insert_sth->execute($args{v}, $args{u}, $args{r}, $args{s}, $args{c});
}

$dbh->disconnect();
