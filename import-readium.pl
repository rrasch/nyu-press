#!/usr/bin/env perl
#
# Import epubs into Readium JS viewer
#
# Author: Rasan Rasch <rasan@nyu.edu>

use FindBin;
use lib "$FindBin::Bin/lib";
use strict;
use warnings;
use Capture::Tiny qw(capture_stdout);
use Data::Dumper;
use EPUB;
use EPUB::OPF;
use File::Basename;
use File::Copy;
use File::Find;
use HTML::FormatText;
use JSON;
use MyConfig;
use MyLogger;
use ONIX;
use Util;
use WebService::Solr;


my $tsv_file = "oa_books.tsv";

my $handle_file = "oa_handles.txt";

my $www_dir = "/path/to/readium/readium/js/viewer/epub_content";

my $meta_file = "$www_dir/epub_library.json";

my $wip_dir = config('rstar_dir') . '/wip';

my $log = MyLogger->get_logger();

$SIG{__WARN__} = sub { $log->logdie(@_) };

for (@INC) { $log->trace($_); }

my $solr_url = config('solr_url');

my $solr = WebService::Solr->new($solr_url);

my $is_solr_up = $solr->ping();
if (!$is_solr_up) {
	$log->logdie("Can't ping solr at $solr_url");
}

# $solr->delete_by_query('*:*');

my %book;

my $book_meta = [];

my $limit = 0;

my $i = 0;

my (%handle_list, $isbn, $handle);
my $line;
open(my $in, $handle_file) or $log->logdie("can't open $handle_file: $!");
while ($line = <$in>)
{
	chomp($line);
	($isbn, $handle) = split(/\s+/, $line);
	$handle =~ s,^http://hdl.handle.net/,,;
	$handle_list{$isbn} = $handle;
}
close($in);

open($in, $tsv_file) or $log->logdie("can't open $tsv_file: $!");
chomp($line = <$in>);
my @fields = split(/\t/, $line);
while ($line = <$in>)
{
	chomp($line);
	@book{@fields} = split(/\t/, $line);

	$log->debug("Processing ISBN $book{ISBN}");

	my $data_dir = "$wip_dir/$book{ISBN}/data";

	my $book_url = config('readium_url') . $book{ISBN};

	if (!$book{'epub file available'})
	{
		$log->warn("No EPUB avaialble for ISBN $book{ISBN}");
		next;
	}

	$handle_file = "$wip_dir/$book{ISBN}/handle";
	$handle = $handle_list{$book{ISBN}} || Util::get_handle($handle_file);
	Util::update_handle($handle, $book_url);

	my $onix_file = find_file("NYUP*$book{ISBN}_onix.xml");
	if (!$onix_file) {
		$log->warn("Can't find ONIX file for $book{ISBN}");
	}
	$log->debug("ONIX file: $onix_file") if $onix_file;

	my $epub_file = find_file("$book{ISBN}.epub");
	if (!$epub_file) {
		$log->warn("Can't find EPUB file for $book{ISBN}");
		next;
	}
	$log->debug("EPUB file: $epub_file");

	my $onix;
	$onix = ONIX->new($onix_file) if $onix_file;

	my $epub = EPUB->new($epub_file, "$www_dir/$book{ISBN}");
	
	my $opf = $epub->opf();
	
	my $old_cover = "$www_dir/$book{ISBN}/ops/xhtml/cover.html";
	my $new_cover;

	if (-f $old_cover)
	{
		my @files = $opf->manifest("text|xml");
		
		Util::sys("perl", "-pi", "-e", "s/cover.html/cover.xhtml/g",
			$opf->filename(), @files);

		$new_cover = $old_cover;
		$new_cover =~ s/\.html/.xhtml/;

		rename($old_cover, $new_cover)
		  or $log->logdie("can't rename $old_cover to $new_cover: $!");
	}

	my $cover_large = "$www_dir/$book{ISBN}/ops/images/$book{ISBN}.jpg";
	(my $cover_small = $cover_large) =~ s/\.jpg$/-th.jpg/;

	Util::sys('convert', $cover_large, '-strip', '-resize', '160>',
		$cover_small);

	my $ops_dir = "epub_content/$book{ISBN}/ops";

	my $meta = $opf->metadata;
	$meta->{author} = delete($meta->{creator});
	$log->debug("Author: $meta->{author}");
	$meta->{coverHref} = "$ops_dir/images/$book{ISBN}.jpg";
	$meta->{thumbHref} = "$ops_dir/images/$book{ISBN}-th.jpg";
	$meta->{packageUrl} = "epub_content/$book{ISBN}";
	$meta->{handle} = "http://hdl.handle.net/$handle";
	if ($onix)
	{
		my $desc  = $onix->description;
		$meta->{description} = clean($desc);
		$meta->{description_html} = $desc;
		$meta->{author}  = $onix->author;
		$meta->{title}   = $onix->title;
		$meta->{subject} = $onix->subject;
		$log->debug("ONIX Author:  $meta->{author}");
		$log->debug("ONIX Subject: $meta->{subject}");
	}
	$log->trace("Metadata $book{ISBN}: ", Dumper($meta));

	push $book_meta, $meta;

	# Had to patch WebService::Solr so that it did not doubly
	# encode fields that are already utf8 encoded
	# See: https://rt.cpan.org/Public/Bug/Display.html?id=47012
	if ($is_solr_up)
	{
		$log->debug("Indexing ISBN $book{ISBN} with solr ...");
		my $doc = WebService::Solr::Document->new;
		$doc->add_fields(new_field('id', $book{ISBN}));
		for my $field (sort keys %$meta)
		{
			$doc->add_fields(new_field($field, $meta->{$field}));
		}
		$log->trace($doc->to_xml());
		$solr->add($doc);
	}

	$i++;
	last if $limit && $i == $limit;
}

close($in);

$log->trace(Dumper($book_meta));

$log->debug("Writing $meta_file.");
open(my $out, ">$meta_file") or $log->logdie("can't open $meta_file: $!");
print $out to_json($book_meta, {pretty => 1});
close($out);


sub find_file
{
	my $pattern = shift;
	$log->debug("entering find_file($pattern)");
	my $cmd = qq{mdfind "kMDItemDisplayName=='$pattern'"};
	my $output = capture_stdout { system($cmd) };
	my @files = split(/\n/, $output);
	return $files[0];
}


sub read_json
{
	my $json_file = shift;
	local $/;
	open(my $in, $json_file) or die("can't open $json_file: $!");
	my $json_text = <$in>;
	close($in);
	decode_json($json_text);
}


sub clean
{
	my $html = shift;
	$html =~ s/&#151;/-/g;
	my $text = HTML::FormatText->format_string($html, leftmargin => 0);
	return $text;
}


sub new_field
{
	WebService::Solr::Field->new(@_);
}

