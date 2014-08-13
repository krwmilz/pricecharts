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
	my $parser = Config::Grammar->new({
		_sections => ['vendors', 'paths'],
		vendors	=> {
			# vendor regular expression
			_sections => ['/[A-Za-z ]+/'],
			'/[A-Za-z ]+/' => {
				_vars => ['search_uri', 'reg_price', 'sale_price', 'color'],
			},
		},
		paths => {
			_vars => ['http', 'log'],
		},
	});

	return $parser->parse($cfg_file) or die "ERROR: $parser->{err}\n";
}

1;