#!/usr/bin/env perl

use strict;
use warnings;

use shared;


$dbh->do("create table if not exists vendors(" .
	"name text not null primary key, " .
	"search_url not null, " .
	"color text not null)") or die $DBI::errstr;

my $sql = "update vendors set search_url = ?, color = ? where name = ?";
my $update_sth = $dbh->prepare($sql);

$sql = "insert into vendors(name, search_url, color) values (?, ?, ?)";
my $insert_sth = $dbh->prepare($sql);

for (sort keys $cfg->{vendors}) {
	$sql = "select * from vendors where name = ?";
	if ($dbh->selectrow_arrayref($sql, undef, $_)) {
		$update_sth->execute($cfg->{vendors}{$_}{search_uri},
			"#$cfg->{vendors}{$_}{color}", $_);
	}
	else {
		$insert_sth->execute($_, $cfg->{vendors}{$_}{search_uri},
		 	"#$cfg->{vendors}{$_}{color}");
	}
}

$dbh->disconnect();
