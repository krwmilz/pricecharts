#!/usr/bin/env perl

use strict;
use warnings;

use Config::Grammar;
use Data::Dumper;
use File::Copy;
use Getopt::Std;
use Lingua::EN::Inflect qw(PL);
use POSIX;
use PriceChart;
use SVG;
use Template;
use Time::Piece;
use URI::Escape;

my %args;
getopts("av", \%args);

$| = 1 if ($args{v});

my $cfg = get_config();
my $dbh = get_dbh($cfg->{http}, undef, $args{v});

my $sql = "update products set manufacturer = ? where manufacturer = ?";
my $products_sth = $dbh->prepare($sql);

$sql = "update prices set manufacturer = ? where manufacturer = ?";
my $prices_sth = $dbh->prepare($sql);

$sql = "update or ignore descriptions set manufacturer = ? where manufacturer = ?";
my $descr_sth = $dbh->prepare($sql);

$sql = "delete from descriptions where manufacturer = ?";
my $delete_sth = $dbh->prepare($sql);

my @bad = (["Samsung", "samsung"], ["Dell", "dell"], ["Panasonic", "panasonic"], ["Kingston", "kingston"], ["SanDisk", "Sandisk"]);

for (@bad) {
	print "info: updating $_->[1] to $_->[0]\n";

	$products_sth->execute($_->[0], $_->[1]);
	$prices_sth->execute($_->[0], $_->[1]);
	$descr_sth->execute($_->[0], $_->[1]);
	$delete_sth->execute($_->[1]);
}

$dbh->disconnect();
