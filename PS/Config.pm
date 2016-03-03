package PS::Config;

use Config::Grammar;

sub new {
	my $class = shift;
	my $self = {};
	bless ($self, $class);

	my $parser = Config::Grammar->new({
		_sections => [ "general", "http" ],
		general => {
			_vars => [
				"agent",
				"email",
				"smtp",
				# XXX: add simple regex validation here
				"addrs",
				"db_dir",
				"log_dir",
			],
		},
		http => {
			_vars => [
				"socket",
				"uid",
				"gid",
				"chroot",
				"htdocs",
			],
		},
	});

	my $cfg_file = "/etc/pricesloth.cfg";
	if (-e "etc/pricesloth.cfg") {
		$cfg_file = "etc/pricesloth.cfg";
	}
	$self->{cfg} = $parser->parse($cfg_file) or die "error: $parser->{err}\n";

	return $self;
}

sub get_cfg {
	return $self->{cfg};
}

1;
