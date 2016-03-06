package PS::Database;

use DBI;
use Log::Log4perl qw(:easy);
use File::Path qw(make_path);
use POSIX;

use PS::Config;

my $logger = get_logger('pricesloth.database');

sub new {
	my $class = shift;

	my $cfg = PS::Config->new();
	my $db_dir = $cfg->{cfg}->{general}{db_dir};

	my $self = {};
	bless ($self, $class);

	make_path($db_dir);
	my $dbh = DBI->connect(
		"dbi:SQLite:dbname=$db_dir/db",
		"",
		"",
		{ RaiseError => 1 }
	) or die $DBI::errstr;

	$self->{dbh} = $dbh;
	$dbh->do("PRAGMA foreign_keys = ON");
	create_tables($dbh);

	$dbh->{AutoCommit} = 1;

	$logger->debug("opened $db_dir/db\n");
	return $self;
}

sub create_tables {
	my ($dbh) = @_;

	$dbh->do(qq{
		create table if not exists products(
			manufacturer text not null,
			part_num text not null,
			retailer text not null,
			type text,
			first_seen int,
			last_seen int,
			last_scraped int,
			svg_stale int default 1,
			primary key(manufacturer, part_num))
	}) or die $DBI::errstr;

	$dbh->do(qq{
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

	$dbh->do(qq{
		create table if not exists retailers(
			name text not null primary key,
			color text not null,
			url text not null)
	}) or die $DBI::errstr;

	$dbh->do(qq{
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

	# $dbh->do("create table if not exists scrapes");
}

1;