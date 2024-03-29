#!/usr/bin/env perl
use strict;
use warnings;

use BSD::arc4random qw(:all);
use Config::Grammar;
use Data::Dumper;
use Getopt::Std;
use Lingua::EN::Inflect qw(PL);
use Math::MatrixReal;
use Number::Format qw(:subs :vars);
use POSIX;
use PriceSloth;
use SVG;
use Template;


my %args;
getopts("av", \%args);

$| = 1 if ($args{v});

my $cfg = get_config();
my $dbh = get_dbh($cfg->{general}{db_dir}, $args{v});

my $work_dir = $cfg->{http}{htdocs};
my $svg_dir  = $work_dir . "/svg";
print "info: work, svg dirs $work_dir/\{,svg\}\n" if ($args{v});

my $config = {
	POST_CHOMP => 1, EVAL_PERL => 1,
	INCLUDE_PATH => "$work_dir/tt", OUTPUT_PATH => $work_dir
};
my $www = Template->new($config) || die Template->error(), "\n";

my $and_stale = $args{a} ? "" : "and products.svg_stale = 1";
my $where_stale = $args{a} ? "" : "where products.svg_stale = 1";

my $desc_sth = $dbh->prepare(qq{select description from descriptions where
	manufacturer = ? and part_num = ? order by date});

# catmull-rom to cubic bezier conversion matrix
my $catrom_to_bezier = Math::MatrixReal->new_from_rows(
	[[0,     1,   0,    0],
	 [-1/6,  1, 1/6,    0],
	 [0,   1/6,   1, -1/6],
	 [0,     0,   1,    0]]
);
my $m_t = ~$catrom_to_bezier;

# make a logo file map using massaged names as keys
opendir(DH, "$cfg->{http}{htdocs}/logo");
my @files = readdir(DH);
closedir(DH);

my %logo_hash;
for my $filename (@files) {
	my $last_dot = rindex($filename, ".");
	my $logo_name = substr($filename, 0, $last_dot);
	$logo_hash{$logo_name} = "/logo/$filename";
}

#
# manufacturers
#
my $stale_list = qq{select distinct manufacturer from products $where_stale};

my $types = qq{select distinct type from products where manufacturer = ? $and_stale};

my $products_fine = qq{select distinct manufacturer, part_num
	from products where type = ? and manufacturer = ?};

my $summary = qq{select type, count(*) from products where manufacturer = ? group by type};

generate_folder($stale_list, $types, $products_fine, "Manufacturers", $summary);

# most natural grouping is manufacturer then type
# (answers the question: what types of products does this manufacturer make?)
my $coarse_sql = qq{select manufacturer, count(distinct part_num) as count,
	type from products group by manufacturer, type};
my @key_fields = ("manufacturer", "type");

# second most natural grouping is manufacturer then retailer
# (answers the question: which places sell this manufacturer?)

my $manufacturer_list = $dbh->selectall_hashref($coarse_sql, \@key_fields);
# print Dumper($manufacturer_list);


#
# retailers
#
$stale_list = qq{select distinct prices.retailer from prices, products where
	products.manufacturer = prices.manufacturer and
	products.part_num = prices.part_num $and_stale};

$types = qq{select distinct prices.manufacturer from prices, products where
	prices.retailer = ? $and_stale and
	products.manufacturer = prices.manufacturer and
	products.part_num = prices.part_num};

$products_fine = qq{select distinct manufacturer, part_num
	from prices where manufacturer = ? and retailer = ?};

$summary = qq{select manufacturer, count(*) from prices where retailer = ?
	group by manufacturer};

generate_folder($stale_list, $types, $products_fine, "Retailers", $summary);

# most natural grouping here is a toss up between type and manufacturer
# (answers the question: what manufacturers does this retailer sell?)
$coarse_sql = qq{select retailer, count(distinct part_num) as count,
	manufacturer from prices group by retailer, manufacturer};
@key_fields = ("retailer", "manufacturer");

# second grouping is retailer then type
# (answers the question: what types of products does this retailer sell?)

my $retailer_list = $dbh->selectall_hashref($coarse_sql, \@key_fields);
# print Dumper($retailer_list);

#
# product types
#
$stale_list = qq{select distinct type from products $where_stale};

$types = qq{select distinct manufacturer from products where type = ?};

$products_fine = qq{select distinct manufacturer, part_num from products where
	manufacturer = ?  and type = ?};

$summary = qq{select manufacturer, count(*) from products where type = ?
	group by manufacturer};

generate_folder($stale_list, $types, $products_fine, "Types", $summary);

$coarse_sql = qq{select type, count(distinct part_num) as count,
	manufacturer from products group by type, manufacturer};
@key_fields = ("type", "manufacturer");

my $types_list = $dbh->selectall_hashref($coarse_sql, \@key_fields);
# print Dumper($types_list);

#
# index
#
my $vars = {
	manufacturer_list => $manufacturer_list,
	retailer_list => $retailer_list,
	types_list => $types_list,
	logo_hash => \%logo_hash,
};
$www->process("index.tt", $vars, "index.html") or die $www->error(), "\n";

#
# about
#
my ($p, $m) = $dbh->selectrow_array(qq{select count(*),
	count(distinct manufacturer) from products});
my ($nprice) = $dbh->selectrow_array("select count(*) from prices");

# anything we haven't seen for over 30 days is stale
my ($prod_stale) = $dbh->selectrow_array(qq{select count(*) from products
	where last_seen < ?}, undef, time - (30 * 24 * 60 * 60));

my ($r) = $dbh->selectrow_array("select count(*) from retailers");

# draw a graph of total number of products vs time
my ($first_seen) = $dbh->selectrow_array("select first_seen from products order by first_seen limit 1");
my $num_weeks = (time - $first_seen) / (60 * 60 * 24 * 7);
my %totals_series;
for my $i (0..$num_weeks) {
	my $x = $first_seen + $i * (60 * 60 * 24 * 7);
	my ($y) = $dbh->selectrow_array("select count(*) from products where first_seen < ?", undef, $x);
	$totals_series{"Total"}{$x} = { "price" => $y };

	($y) = $dbh->selectrow_array("select count(*) from products where last_seen < ?", undef, $x - (60 * 60 * 24 * 30));
	$totals_series{"Out of date"}{$x} = { "price" => $y };
}

# print Dumper(%totals_series);
my %series_metadata;
$series_metadata{"Total"} = { url => "", color => "000" };
$series_metadata{"Out of date"} = { url => "", color => "F00" };
my $svg = make_svg(\%totals_series, "no_part_num", \%series_metadata, "");

make_path($svg_dir, { verbose => $args{v} });
my $svg_path = "$svg_dir/history_summary.svg";

open my $svg_fh, ">", "$svg_path" or die "couldn't open $svg_path: $!";
print $svg_fh $svg->xmlify;
close $svg_fh;

# this is supposed to work??? alternative sucks
# $THOUSANDS_SEP = '/';
my $de = new Number::Format(-thousands_sep => ' ',
	                    -decimal_point => '.');

$vars = { nprice => $de->format_number($nprice),
	nret => $r,
	nmanuf => $m,
	nprod => $de->format_number($p - $prod_stale),
	nprod_stale => $prod_stale
};
$www->process("about.tt", $vars, "about.html") or die $www->error(), "\n";
print "info: about\n" if ($args{v});


#
# products
#
my $sql = "select * from products $where_stale";
my $products = $dbh->selectall_hashref($sql, "part_num");
while (my ($part_num, $row) = each %$products) {
	my $part_link = linkify($part_num);
	my $manuf_link = linkify($row->{manufacturer});

	$row->{description} =
		get_description($row->{manufacturer}, $row->{part_num});

	my $url = "products/$manuf_link/$part_link.html";
	$www->process("product.tt", $row, $url) or die $www->error(), "\n";
}
print "info: products (" . scalar(keys %$products) . ")\n" if ($args{v});


#
# product svg;s
#
print "info: svg  " if ($args{v});

my @series_keys = ("retailer", "date");
my $series_sth = $dbh->prepare(qq{select retailer, date, price from prices
	where manufacturer = ? and part_num = ?});

my $retailer_info = $dbh->selectall_hashref(qq{select name, url, color from
	retailers}, "name");

my $parts_sth = $dbh->prepare(qq{select distinct manufacturer,
	part_num from products $where_stale});
$parts_sth->execute();

my $rendered = 0;
while (my ($manufacturer, $part_num) = $parts_sth->fetchrow_array()) {
	spin() if ($args{v});

	my $series = $dbh->selectall_hashref($series_sth, \@series_keys, undef,
		$manufacturer, $part_num);
	my $svg = make_svg($series, $part_num, $retailer_info, "\$");

	my $manufacturer_dir = linkify($manufacturer);
	my $part_link = linkify($part_num);

	make_path("$svg_dir/$manufacturer_dir", { verbose => $args{v} });
	my $svg_path = "$svg_dir/$manufacturer_dir/$part_link.svg";

	open my $svg_fh, ">", "$svg_path" or die "couldn't open $svg_path: $!";
	print $svg_fh $svg->xmlify;
	close $svg_fh;

	$rendered++;
}
print "\b($rendered)\n" if ($args{v});

$dbh->begin_work;
$dbh->do("update products set svg_stale = 0");
$dbh->commit;
$dbh->disconnect();

#
# generate an entire tree of html structure
#
sub generate_folder
{
	my ($sql_stale_outer, $sql_types, $sql_products, $name, $sql_summary) = @_;

	my $name_lc = lc ($name);

	my $stale_list = $dbh->selectcol_arrayref($sql_stale_outer);
	for my $it (@$stale_list) {

		my $it_link = linkify($it);
		my $types = $dbh->selectcol_arrayref($sql_types, undef, $it);
		for my $type (sort @$types) {

			my $products = $dbh->selectall_arrayref($sql_products, undef, $type, $it);
			$_->[2] = get_description($_->[0], $_->[1]) for (@$products);

			my $vars = {
				name => $it, type => PL($type, scalar @$products),
				products => $products, logo_hash => \%logo_hash
			};
			my $type_link = linkify($type);
			my $out_path = "$name_lc/$it_link/$type_link.html";
			$www->process("fine_list.tt", $vars, $out_path)
				or die $www->error(), "\n";
		}

		my $summary = $dbh->selectall_arrayref($sql_summary, undef, $it);
		my $vars = { type => $name_lc, name => $it, info => $summary };
		$www->process("summary.tt", $vars, "$name_lc/$it_link.html")
			or die $www->error(), "\n";

		print "info: $name_lc/$it_link\n" if ($args{v});
	}
}

sub linkify
{
	my $type = shift;

	my $type_link = lc($type);
	$type_link =~ s/[ #\/]/_/g;
	return $type_link;
}

sub get_description
{
	my $manufacturer = shift;
	my $part_num = shift;

	my $descriptions = $dbh->selectcol_arrayref($desc_sth, undef, $manufacturer,
		$part_num);
	unless (@$descriptions) {
		print "error: no descriptions for $manufacturer $part_num\n";
	}

	# pick the shortest non-zero description
	my $best = $descriptions->[0];
	for (@$descriptions) {
		next if ($_ eq "");
		$best = $_ if (length($_) < length($best));
	}

	return $best;
}

#
# make a new svg with provided coordinate and label data
#
sub make_svg
{
	my ($series, $part_num, $metadata, $right_axis_prefix) = @_;

	my ($left, $center, $right, $top, $middle, $bottom) =
		(20, 430, 50, 15, 150, 20);

	my $width = $right + $center + $left;
	my $height = $top + $middle + $bottom;

	my ($x_min, $x_max, $y_min, $y_max) = (100000000000, 0, 1000000, 0.00001);
	while (my ($retailer, $values) = each %$series) {
		for (keys %{$values}) {
			my ($x, $y) = ($_, $values->{$_}{price});
			$x_min = $x if ($x < $x_min);
			$x_max = $x if ($x > $x_max);
			$y_min = $y if ($y < $y_min);
			$y_max = $y if ($y > $y_max);
		}
	}

	my $num_digits = ceil(log($y_max) / log(10));
	my $magnitude = 10 ** ($num_digits - 1);

	$y_max = ceil($y_max / $magnitude) * $magnitude;
	$y_min = floor($y_min / $magnitude) * $magnitude;

	my ($domain, $range) = ($x_max - $x_min, $y_max - $y_min);
	$domain = 24 * 60 * 60 if ($domain <= 0);
	$range = 20 if ($range < 20);

	# clamp the total size of this thing with viewBox
	my $svg = SVG->new(viewBox => "0 0 $width $height");
	my $defs = $svg->defs();
	my ($x_scale, $y_scale) = ($center / $domain, $middle / $range);

	# $defs->tag("link", href => "/charts.css", type => "text/css",
	# 	rel => "stylesheet", xmlns => "http://www.w3.org/1999/xhtml");

	# y axis labels (prices)
	my $num_labels = 5;
	for (1..$num_labels) {
		my $step = ($_ - 1) / ($num_labels - 1);
		my $price = ceil($y_max - $range * $step);
		my $y = $top + $middle * $step;

		$svg->text(
			id => "price_$_", x => $left + $center + 5, y => $y - 2,
			fill => "black", "font-family" => "sans-serif",
			"font-size" => "0.8em"
		)->cdata("$right_axis_prefix$price");

		$svg->line(
			id => "horizontal_line_$_", x1 => $left, y1 => $y,
			x2 => $width , y2 => $y,
			style => "stroke: #BBB; stroke-width: 0.5px;"
		);
	}

	$num_labels = 4;

	# x axis labels (dates)
	if ($domain == 24 * 60 * 60) {
		$num_labels = 2;
	}
	for (1..$num_labels) {
		my $step = ($_ - 1) / ($num_labels - 1);

		# make the dates not hang off the ends of the chart
		my $text_anchor = "middle";
		$text_anchor = "start" if ($_ == 1);
		# $text_anchor = "end" if ($_ == $num_labels);

		# print the dates along the x axis
		my $x = $left + $center * $step;
		my $time = $x_min + $domain * $step;
		$svg->text(
			id => "date_$_", x => $x, y => $height,
			"text-anchor" => $text_anchor, "fill" => "black",
			"font-family" => "sans-serif", "font-size" => "0.8em"
		)->cdata(strftime("%b %e %Y", localtime($time)));

		# print the little tick marks down from the x axis
		my $x_axis = $top + $middle;
		$svg->line(
			id => "date_marker_$_", x1 => $x, y1 => $x_axis,
			x2 => $x, y2 => $x_axis + 5,
			style => "stroke: #BBB; stroke-width: 0.5px;"
		);
	}

	while (my ($series_name, $values) = each %$series) {
		my $retailer_id = lc($series_name);
		$retailer_id =~ s/ /_/;

		my (@xs, @ys);
		for (sort keys %{$values}) {
			my ($x, $y) = ($_, $values->{$_}{price});
			push @xs, sprintf "%.3f", ($x - $x_min) * $x_scale + $left;
			push @ys, sprintf "%.3f", $height - $bottom - ($y - $y_min) * $y_scale;
		}

		if (@xs < 3) {
			my $points = $svg->get_path(x => \@xs, y => \@ys, -type => "path");
			$defs->path(%$points, id => "path_$retailer_id");
		}
		else {
			# catmull rom time
			my $d = catmullrom_to_bezier(\@xs, \@ys);
			$defs->tag("path", "d" => $d, id => "path_$retailer_id");
		}

		my $info = $metadata->{$series_name};
		my ($url, $color) = ($info->{url}, $info->{color});

		# xlink:href's don't like raw ampersands
		$url =~ s/&/&amp;/g;

		# the line, points, and label can be grouped under one anchor
		my $anchor = $svg->anchor(-href => $url . $part_num,
			target => "new_window");

		# draw path first
		$anchor->use(
			-href => "#path_$retailer_id",
			style => qq{stroke: #$color; fill-opacity: 0;
				stroke-width: 2; stroke-opacity: 0.8;}
		);

		# now draw individual data points
		my $rand_token = sprintf("%x", arc4random());
		$defs->circle(id => $rand_token, cx => 0, cy => 0, r => 2,
			style => "stroke: #$color; fill: white; stoke-width: 2;"
		);
		while (my $i = each @xs) {
			$anchor->use(-href => "#$rand_token",
				x => $xs[$i], y => $ys[$i]
			);
		}

		# show series name along the start of the path
		$anchor->text(
			fill => "#$color", style => "font-family: sans-serif;"
		)->tag("textPath", -href => "#path_$retailer_id"
		)->tag("tspan", "dy" => "-5")->cdata($series_name);
	}

	# when graph is loaded make a sliding motion show the graph lines
	# my $mask = $svg->rectangle(
	# 	x => 0, y => 0, width => 1000, height => 250, rx => 0, ry => 0,
	# 	id => "mask", fill => "#FFF"
	# );
	# $mask->animate(
	# 	attributeName => "x", values => "0;1000", dur => "0.2s",
	# 	fill => "freeze", -method => ""
	# );

	return $svg
}

#
# taken from https://gist.github.com/njvack/6925609
#
sub catmullrom_to_bezier
{
	my $xs_ref = shift;
	my $ys_ref = shift;

	my $d = "M $xs_ref->[0], $ys_ref->[0] ";
	my $iLen = @$xs_ref;
	for (my $i = 0; $iLen - 1 > $i; $i++) {

		my @offsets = (-1, 0, 1, 2);
		if ($i == 0) {
			@offsets = (0, 0, 1, 2);
		} elsif ($i == ($iLen - 2)) {
			@offsets = (-1, 0, 1, 1);
		}

		my (@xs, @ys);
		for my $idx (@offsets) {
			push @xs, $xs_ref->[$i + $idx];
			push @ys, $ys_ref->[$i + $idx];
		}

		my $x_row = Math::MatrixReal->new_from_rows([[@xs]]);
		my $y_row = Math::MatrixReal->new_from_rows([[@ys]]);

		$x_row = $x_row * $m_t;
		$y_row = $y_row * $m_t;

		my ($x, $y) = ($x_row->[0][0], $y_row->[0][0]);

		# knock some digits of precision off
		$d .= sprintf("C %0.2f, %0.2f %0.2f, %0.2f %0.2f, %0.2f ",
			$x->[1], $y->[1], $x->[2], $y->[2], $x->[3], $y->[3]);
	}

	return $d;
}
