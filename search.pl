use strict;
use warnings;

use FCGI;
use Template;
use Proc::Daemon;

use shared;


my $pid_file = "/var/www/run/search.pid";
if (-e $pid_file) {
	print "Not starting, pid file $pid_file exists\n";
	exit;
}

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

my $socket_path = "/var/www/run/search.sock";

print "made run dir\n";

my $socket = FCGI::OpenSocket($socket_path, 1024);
my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV,
	$socket, FCGI::FAIL_ACCEPT_ON_INTR);
print "made socket and request objects\n";

my $config = {
	# XXX: this needs to be fixed
	INCLUDE_PATH => "/home/kyle/src/pricechart/html"
};
my $template = Template->new($config);
print "made new template config\n";

my $dbh = get_dbh();
print "opened db\n";

my $sql = "select part_num, manufacturer, description from products " .
	"where description like ? or part_num like ? or manufacturer like ?";
my $search_sth = $dbh->prepare($sql);

print "starting main loop\n";
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

print "shutting down\n";
FCGI::CloseSocket($socket);
unlink($socket_path, $pid_file);
$dbh->disconnect();

sub sig_handler
{
	$request->LastCall();
	print "caught signal\n";
}
