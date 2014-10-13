#!/usr/bin/env perl

package shared;
use Config::Grammar;
use Exporter;
use LWP::Simple;

@ISA = ("Exporter");
@EXPORT = ("get_dom", "get_config", "get_dbh", "get_ua");

sub get_dom
{
	my $url = shift;
	my $ua = shift;

	my $resp = $ua->get($url);
	if (! $resp->is_success) {
		print "getting $url failed: " . $resp->status_line . "\n";
		return undef;
	}
	return HTML::Grabber->new(html => $resp->decoded_content);
}

sub get_config
{
	my $cfg_file = shift;

	if (!defined $cfg_file) {
		if (-e "pricechart.cfg") {
			$cfg_file = "pricechart.cfg";
		} else {
			$cfg_file = "/etc/pricechart.cfg";
		}
	}

	my $parser = Config::Grammar->new({
		_sections => ['vendors', 'general'],
		vendors	=> {
			# vendor regular expression
			_sections => ['/[A-Za-z ]+/'],
			'/[A-Za-z ]+/' => {
				_vars => ['search_uri', 'reg_price', 'sale_price', 'color'],
			},
		},
		general => {
			_vars => [
				'http_path',
				'log_file',
				'user_agent',
				'email',
				'smtp',
				'db_file'
			],
		},
	});
	return $parser->parse($cfg_file) or die "ERROR: $parser->{err}\n";
}

sub get_dbh
{
	my $cfg = shift;

	my $dbh = DBI->connect(
		"dbi:SQLite:dbname=$cfg->{general}{db_file}",
		"",
		"",
		{ RaiseError => 1 },) or die $DBI::errstr;
	return $dbh;
}

sub get_ua
{
	my $cfg = shift;

	my $ua = LWP::UserAgent->new(agent => $cfg->{general}{user_agent});
	$ua->default_header("Accept" => "*/*");
	return $ua;
}

1;
