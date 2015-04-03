
use strict;
use warnings;

use Config::Grammar;
use Getopt::Std;
use DBI;


my %args;
getopts("d:", \%args);

$| = 1;

print "info: unlinking old converted db file\n";
unlink "pricechart_converted.db";

my $cfg = get_config();

my $old_dbh = DBI->connect(
	"dbi:SQLite:dbname=$args{d}",
	"",
	"",
	{RaiseError => 1}
) or die $DBI::errstr;


my $new_dbh = DBI->connect(
	"dbi:SQLite:dbname=pricechart_converted.db",
	"",
	"",
	{RaiseError => 1}
) or die $DBI::errstr;

$new_dbh->do(qq{
	create table if not exists products(
		manufacturer text not null,
		part_num text not null,
		retailer text not null,
		type text,
		first_seen int,
		last_seen int,
		last_scraped int,
		primary key(manufacturer, part_num))
}) or die $DBI::errstr;

$new_dbh->do(qq{
	create table if not exists descriptions(
		manufacturer text not null,
		part_num text not null,
		retailer text not null,
		description text not null,
		date int not null,
		primary key(manufacturer, part_num, retailer, description),
		foreign key(manufacturer, part_num) references 
			products(manufacturer, part_num))
}) or die $DBI::errstr;

$new_dbh->do(qq{
	create table if not exists retailers(
		name text not null primary key,
		color text not null,
		url text not null)
}) or die $DBI::errstr;

$new_dbh->do(qq{
	create table if not exists prices(
	date int not null,
	manufacturer text not null,
	part_num text not null,
	retailer text not null,
	price int not null,
	duration int,
	primary key(date, part_num, retailer, price),
	foreign key(manufacturer, part_num) references products(manufacturer, part_num),
	foreign key(retailer) references retailers(name))
}) or die $DBI::errstr;

my $sql = "insert into products(manufacturer, part_num, retailer, type, first_seen,
	last_seen, last_scraped) values (?, ?, ?, ?, ?, ?, ?)"; 
my $product_sth = $new_dbh->prepare($sql);

$sql = "insert or replace into descriptions(manufacturer, part_num, retailer, ".
	"description, date) values (?, ?, ?, ?, ?)";
my $description_sth = $new_dbh->prepare($sql);

$sql = "insert or replace into retailers(name, color, url) values (?, ?, ?)";
my $retailer_sth = $new_dbh->prepare($sql);

$sql = "insert into prices(date, manufacturer, part_num, retailer, price, " .
	"duration) values (?, ?, ?, ?, ?, ?)";
my $price_sth = $new_dbh->prepare($sql);

my $type_map = {
	"televisions" => "Television",
	"laptops" => "Laptop",
	"hard drives" => "Hard Drive"
};

print "info: processing products  ";
$sql = "select * from products";
my $products = $old_dbh->selectall_hashref($sql, "part_num");
while (my ($part_num, $part_hash) = each %$products) {
	my $manuf = $part_hash->{manufacturer};
	my $first_seen = $part_hash->{first_seen};
	spin();
	# print "$manuf $part_num\n";

	$product_sth->execute($manuf, $part_num,
		"Memory Express", $type_map->{$part_hash->{type}},
		$first_seen, $part_hash->{last_seen}, $part_hash->{last_scraped});

	$description_sth->execute($manuf, $part_num, "Memory Express",
		$part_hash->{description}, $first_seen);
}
$description_sth->finish();
$product_sth->finish();
print "\b" . scalar(keys %$products) . " done\n";

print "info: processing prices  ";
$sql = "select * from prices";
my $prices = $old_dbh->selectall_arrayref($sql);
for (@$prices) {
	my ($date, $part_num, $retailer, $price, $color, $duration, $title) = @$_;
	spin();

	$sql = "select manufacturer from products where part_num = ?";
	my ($manuf) = $old_dbh->selectrow_array($sql, undef, $part_num);

	$retailer_sth->execute($retailer, $cfg->{retailers}{$retailer}{color},
		$cfg->{retailers}{$retailer}{url});

	$price_sth->execute($date, $manuf, $part_num, $retailer,
		$price, $duration);

	$description_sth->execute($manuf, $part_num, $retailer,
		$title, $date);
}
print "\b" . scalar @$prices . " done\n";

my $state = 0;
sub spin
{
	my @spin_states = ("-", "\\", "|", "/");

	print "\b";
	print $spin_states[++$state % 4];
}

sub get_config
{
	my $parser = Config::Grammar->new({
		_sections => ["general", "http", "retailers"],
		general => {
			_vars => [
				"agent",
				"email",
				"smtp",
				# XXX: add simple regex validation here
				"addrs"
			],
		},
		http => {
			_vars => [
				"socket",
				"uid",
				"gid",
				"chroot",
				"db_dir",
				"htdocs",
				"logs",
			],
		},
		retailers => {
			_sections => ["/[A-Za-z ]+/"],
			"/[A-Za-z ]+/" => {
				_vars => [
					"url",
					"reg_tag",
					"sale_tag",
					"color",
					"title"
				]
			}
		}
	});

	my $cfg_file = "/etc/pricechart.cfg";
	my $cfg = $parser->parse($cfg_file) or die "error: $parser->{err}\n";

	return $cfg;
}
