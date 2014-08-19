#!/usr/bin/env perl

package Shared;
use Config::Grammar;
use Exporter;

@ISA = ("Exporter");
@EXPORT = ("get_dom", "get_config");

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

1;
