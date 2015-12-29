#!/usr/bin/env perl
#
# Script to import nyu press content into drupal via services module.
#
# Author: Rasan Rasch <rasan@nyu.edu>

use strict;
use warnings;
use utf8;
use MyLogger;
use Data::Dumper;
use File::Basename;
use File::Temp qw(tempdir);
use HTML::TreeBuilder;
use XML::LibXML;
use XML::Simple;
use Util;
use Node;
use MyConfig;


$SIG{HUP} = 'IGNORE';

my $log = MyLogger->get_logger();

my $rstar_dir = config('rstar_dir');

my @ids = @ARGV;

my $tmpdir = tempdir(CLEANUP => 1);
# my $tmpdir = "/tmp";
$log->debug("Temp directory: $tmpdir");

my $work_dir;

my @pdf_types = (
	"Universal PDF",
	"Print PDF",
	"POD PDF",
	"PDF-A",
);

my %role = (
	A01 => "author",
	B01 => "editor",
);

my $dropbox_dir = "/path/to/dropbox";

my @onix_files = glob("$dropbox_dir/*.xml");


for my $onix_file (@onix_files)
{
	$log->debug("Processing $onix_file");

	my $onix = XML::LibXML->load_xml(location => $onix_file);
	my ($product) = $onix->findnodes('/Product');

	my %isbn;
	for my $id ($product->findnodes('./ProductIdentifier'))
	{
		my $idval = $id->findvalue('./IDValue');
		$isbn{length($idval)} = $idval;
	}

	my $title     = $product->findvalue('./Title/TitleText');
	my $subtitle  = $product->findvalue('./Title/Subtitle');
	my $desc      = $product->findvalue('./OtherText');
	my $subject   = $product->findvalue('./Subject/SubjectHeadingText');
	my $publisher = $product->findvalue('./Publisher/PublisherName');
	my $pub_date  = $product->findvalue('./PublicationDate');
	my $lang_code = $product->findvalue('./Language/LanguageCode');
	my $num_pages = $product->findvalue('./NumberOfPages');

	$log->debug("Num pages: $num_pages");
	$log->debug("ISBN 13: $isbn{13}");

	my $doc_dir = "$rstar_dir/$isbn{13}";
	$log->debug("document dir: $doc_dir");

	my $pdf_file;
	for my $type (@pdf_types)
	{
		my $book_pdf = "$doc_dir/$type/$isbn{13}.pdf";
		$log->debug("Checking for $book_pdf");
		if (-f $book_pdf)
		{
			$log->debug("Found $book_pdf");
			$pdf_file = $book_pdf;
			last;
		}
	}
	
	if (! -f $pdf_file) {
		$log->warn("PDF file doesn't exist.");
		next;
	}

	$work_dir = "$tmpdir/$isbn{13}";
	if (! -d $work_dir) {
		mkdir($work_dir) or $log->logdie("Can't mkdir $work_dir: $!");
	}

	my $thumb_file = "$work_dir/$isbn{13}_thumb.jpg";
	create_thumb($pdf_file, $thumb_file);

	my ($epub_file) = glob("$doc_dir/ePub/*.epub");

	my $book = {
		node_type                  => 'dlts_book',
		title                      => $title,
		identifier                 => $isbn{13},
		handle                     => [],
		ocr_text                   => "",
		pdf_file_file              => $pdf_file,
# 		pdf_file_file              => '/tmp/foo.pdf',
# 		epub_file_file             => $epub_file,
		call_number                => "",
		isbn                       => $isbn{10},
		sequence_count             => $num_pages,
# 		binding_orientation_select => 1,
# 		read_order_select          => 0,
# 		scan_order_select          => 0,
		representative_image_file  => $thumb_file,
		scan_date                  => "",
		scanning_notes             => "",
		page_count                 => $num_pages,
		dimensions                 => "",
		author                     => [],
		creator                    => [],
		editor                     => [],
		contributor                => [],
		publisher                  => [$publisher],
		subject                    => "",
		language_code              => [$lang_code],
		language                   => "",
		volume                     => "",
		number                     => "",
		subtitle                   => $subtitle,
		description                => Util::trunc($desc),
		subject                    => $subject,
		pub_date                   => $pub_date,
	};


	for my $contributor ($product->findnodes('./Contributor'))
	{
		my $role_code = $contributor->findvalue('./ContributorRole');
		$log->debug("Role code: $role_code");
		my $contrib_name = $contributor->findvalue('./PersonName');
		$log->debug("Contributor name: $contrib_name");
		my $cck_column = $role{$role_code} || "contributor";
		push(@{$book->{$cck_column}}, $contrib_name);
	}

	$book = Node->new(obj => $book);

	create_pages($pdf_file, $isbn{13}, $book);
	
	my $files_dir = config('drupal_files_dir') . "/$isbn{13}";
	
	sys("ssh " . config('www_host') . " 'umask 000; mkdir -p $files_dir/{fonts,images,styles} &>/dev/null; true'");

	if (-f $epub_file) {
		create_chapters($epub_file, $isbn{13}, $book);
	} else {
		$log->warn("Epub file doesn't exist");
	}

}


sub create_thumb
{
	my ($input_file, $output_file) = @_;
	sys("convert -thumbnail x300 '$input_file\[0\]' $output_file");
}


sub create_pages
{
	my ($pdf_file, $isbn, $book) = @_;

	sys("pdfinfo '$pdf_file'");
	sys("pdftk '$pdf_file' dump_data");
	sys("convert '$pdf_file' -scene 1 '$work_dir/${isbn}_page_%04d.jp2'");

	opendir(my $dirh, $work_dir) or $log->logdie("can't open $work_dir: $!");
	my @images = sort(grep { /_\d{4}\.jp2$/ } readdir($dirh));
	close($dirh);

	for my $img (@images)
	{
		my ($page_num) = $img =~ /_(\d{4}).jp2$/;
		$page_num += 0;
		my $img_file = "$work_dir/$img";
		$log->debug("img: $img_file");

		my $jpg_file = $img_file;
		$jpg_file =~ s/2$/g/;

		sys("convert $img_file $jpg_file");

		my $page = {
			node_type           => 'dlts_book_page',
			title               => create_page_title($book->title, $page_num),
			book_ref            => $book->auto_nid(),
			sequence_number     => $page_num,
			real_page_number    => $page_num,
			page_type_select    => 0,
# 			hand_side_select    => "",
			visible             => 1,
			cropped_master_file => $img_file,
# 			cropped_master_file => '/tmp/foo.jp2',
			service_copy_file   => $jpg_file,
			ocr_text            => "",
			is_part_of          => $book->get_field('identifier'),
		};

		$page = Node->new(obj => $page);
	}
}


sub create_chapters
{
	my ($epub_file, $isbn, $book) = @_;

	my $epub_dir  = "$work_dir/epub";
	my $files_dir = config('drupal_files_dir') . "/$isbn/epub/";  

	sys("unzip -d $epub_dir -o $epub_file");

	my $container_file = "$epub_dir/META-INF/container.xml";
	$log->debug("Reading $container_file to find opf file.");
	my $container = XMLin($container_file, ForceArray => ['rootfile']);
	$log->trace(Dumper($container));

	my $opf_file =
	  "$epub_dir/" . $container->{rootfiles}{rootfile}[0]{'full-path'};
	my $opf_dir = dirname($opf_file);
	$log->debug("Opf file: $opf_file");

	system("sed -i.bak 1d $opf_file");
	my $opf_xml = XML::LibXML->load_xml(location => $opf_file);
	my $xpc = XML::LibXML::XPathContext->new();
	$xpc->registerNs("o", "http://www.idpf.org/2007/opf");
	my $xpath = '//o:package/o:manifest'
	  . '/o:item[@media-type=\'application/x-dtbncx+xml\']';
	my ($toc_node) = $xpc->findnodes($xpath, $opf_xml);
	my $toc_file = "$opf_dir/" . $toc_node->findvalue('./@href');
	$log->debug("TOC file: $toc_file");
	my $toc       = XMLin($toc_file);
	my $nav_point = $toc->{navMap}{navPoint};
	$log->trace("Table of contents: ", Dumper($nav_point));

	my %nav;
	for my $id (keys %{$nav_point})
	{
		utf8::encode($nav_point->{$id}{navLabel}{text});
		$nav{$nav_point->{$id}{content}{src}} = {
			chapter_name => $nav_point->{$id}{navLabel}{text},
			play_order   => $nav_point->{$id}{playOrder},
		};
	}

	my $opf = XMLin($opf_file, KeyAttr => []);
	my $manifest = $opf->{manifest}{item};

	for my $item (@$manifest)
	{
		$log->trace(Dumper($item));
		my ($suffix) = $item->{href} =~ /\.([^.]+)$/;
		my $content_file = "$opf_dir/$item->{href}";
		
		if ($item->{'media-type'} !~ /xhtml/)
		{
			if ($item->{'media-type'} ne 'application/x-dtbncx+xml')
			{
				Node::add_file($content_file,
					"$isbn/" . dirname($item->{href}));
			}
			next;
		}

		$log->debug("xhtml file: $content_file");

		my $buf = "";
		open(my $in, $content_file)
		  or $log->logdie("can't open $content_file: $!");
		while (my $line = <$in>)
		{
			$line =~ s/\r//g;
			$buf .= $line;
		}
		close($in);

		$buf =~s/href="([^"]+)"/'href="'.$files_dir.basename($1).'"'/eg;
		$log->trace("xhtml file: $buf");

		my $chapter = {
			node_type    => "dlts_book_section",
			title        => $book->title() . " Chapter $item->{id}",
			book_ref     => $book->auto_nid(),
			section_name => $nav{$item->{href}}{chapter_name},
			play_order   => $nav{$item->{href}}{play_order},
			section_body => $buf,
		};

		$chapter = Node->new(obj => $chapter);
	}
}



sub create_page_title
{
	my ($title, $pagenum) = @_;
	my $max_title_length = 250;

	my $desc = "Page $pagenum";

	my $length_title = length($title);
	my $length_desc  = length($desc);
	my $length_total = $length_title + $length_desc + 1;

	if ($length_total > $max_title_length)
	{
		$title =
		  substr($title, 0,
			$length_title - ($length_total - $max_title_length));
	}

	return $title . " " . $desc;
}


