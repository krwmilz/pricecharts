#!/usr/bin/env perl -T
use strict;
use warnings;

# all dependencies explicitly listed
use Config::Grammar;
use DBD::SQLite;
use Encode;
use FCGI;
use Getopt::Std;
use Template;
use Template::Context;
use Template::Filters;
use Template::Iterator;
use Template::Parser;
use Template::Plugins;
use Template::Stash::XS;
use PriceSloth;
use Unix::Syslog qw(:macros :subs);
use URI::Escape;


my %args;
getopts("v", \%args);

# fork into background unless verbose
unless ($args{v}) {
	if (fork()) {
		exit();
	}
}

my $cfg = get_config();
my %http_cfg = %{$cfg->{http}};

openlog("ps_fcgi", LOG_PID, LOG_DAEMON);

if (-e $http_cfg{socket}) {
	my $msg = "error: socket $http_cfg{socket} exists\n";
	print "$msg\n" if ($args{v});
	syslog(LOG_ERR, $msg);
	exit;
}

my $socket = FCGI::OpenSocket($http_cfg{socket}, 1024);
my $request = FCGI::Request(\*STDIN, \*STDOUT, \*STDERR, \%ENV, $socket,
	FCGI::FAIL_ACCEPT_ON_INTR);

# XXX: sqlite_open_flags => DBD::SQLite::OPEN_READONLY
my $dbh = get_dbh($cfg->{general}{db_dir}, $args{v});
my $sql = qq{select distinct manufacturer, part_num from prices where
	manufacturer like ? or part_num like ?};
my $srch_sth = $dbh->prepare($sql);

my ($user, $group) = ($http_cfg{uid}, $http_cfg{gid});
my $uid = getpwnam($user)  or die "error: user $user does not exist\n";
my $gid = getgrnam($group) or die "error: group $group does not exist\n";
chown $uid, $gid, $http_cfg{socket} or die "error: chown $uid:$gid: $!";

if (fork()) {
	# parent
	$0 = "ps_fcgi [priv]";

	# child should catch sigint and exit nicely, then we exit nicely here
	$SIG{INT} = "IGNORE";

	print "info: parent: alive\n" if ($args{v});
	syslog(LOG_INFO, "parent: alive");

	wait();

	print "info: parent: cleaning up\n" if ($args{v});
	syslog(LOG_INFO, "parent: shutdown");

	$dbh->disconnect();
	FCGI::CloseSocket($socket);
	unlink($http_cfg{socket}) or warn "unlink $http_cfg{socket} failed: $!";
	closelog();

	exit 0;
}

# child
$0 = "ps_fcgi sloth";

print "info: child: chroot $http_cfg{chroot}\n" if ($args{v});
chroot $http_cfg{chroot} or die "chroot $http_cfg{chroot} failed: $!\n";
chdir "/" or die "cd / failed: $!\n" ;

$( = $) = "$gid $gid";
$< = $> = $uid;
print "info: child: uid:gid appears to be $<:$(\n" if ($args{v});

# catch ctrl-c and default kill(1) signal
$SIG{INT} =  \&child_sig_handler;
$SIG{TERM} = \&child_sig_handler;

# remove chroot dir from beginning of htdocs dir
my $chroot_tt_dir = "$http_cfg{htdocs}/tt";
$chroot_tt_dir =~ s/$http_cfg{chroot}//;
print "chroot tt dir is $chroot_tt_dir\n";

my $config = { INCLUDE_PATH => $chroot_tt_dir };
my $template = Template->new($config) || die $Template::ERROR . "\n";

syslog(LOG_INFO, "child: ready");
print "info: child: ready\n" if ($args{v});

while ($request->Accept() >= 0) {
	# header, XXX: cache control timestamps?
	print "Content-Type: text/html\r\n\r\n";

	# incoming query string is http mangled
	my (undef, $input) = split("=", $ENV{QUERY_STRING});
	$input = uri_unescape($input);

	# fuzzy search on manufacturer and part number
	$srch_sth->execute("%$input%", "%$input%");
	my $vars = { query => $input, results => $srch_sth->fetchall_arrayref() };

	$template->process("search.tt", $vars)
		|| print "template: " . $template->error();
}

sub child_sig_handler
{
	$request->LastCall();
	print "info: child: caught sig" . lc shift . "\n" if ($args{v});
}
