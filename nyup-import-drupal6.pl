#!/usr/bin/env perl
#
# Script to import nyu press content into drupal via services module.
#
# Author: Rasan Rasch <rasan@nyu.edu>

use strict;
use warnings;
use utf8;
use Cwd qw(abs_path);
use Data::Dumper;
use File::Basename;
use File::MimeInfo;
use File::Temp qw(tempdir);
use Image::ExifTool;
use JSON;
use IO::CaptureOutput qw(capture_exec_combined);
use Log::Log4perl qw(:easy :no_extra_logdie_message);
use MIME::Base64 qw(encode_base64);
use Spreadsheet::ParseExcel;
use Time::Duration;
use WWW::Mechanize;
use XML::LibXML;
use XML::Simple;
# use XMLRPC::Lite +trace => "debug";
use XMLRPC::Lite;
use nyup;


my $xls_file = "Metadata.xls";

# url for drupal
my $baseurl = "http://localhost/nyu/books";

# url for RestfulHS service for creating handles
my $handle_service_url = "https://localhost/path/to/handles/service";

# url for drupal's xmlrpc service proxy
my $drupal_services_proxy = "$baseurl/path/to/services/endpoint";

# base directory for drupal installation
my $drupal_home = "/path/to/drupal/home";

# directory where drupal fetches content
my $drupal_files_dir = "sites/default/files";

####################################################################

Log::Log4perl->easy_init(
    {
        level  => $TRACE,
        file   => "STDERR",
        layout => "[%d %p] %m%n"
    }
);

my $log = get_logger();

$SIG{__WARN__} = sub { $log->logdie(@_) };

# find directory where this script resides
my $app_home = dirname(abs_path($0));

{
	no warnings;
	@LWP::Protocol::http::EXTRA_SOCK_OPTS = (
		SendTE    => 0,
		KeepAlive => 1,
	);
}

# create www agent to in to RestfulHS
my $agent = WWW::Mechanize->new();
$agent->credentials($nyup::handle_user, $nyup::handle_pass);
$agent->add_handler("request_send",  sub { shift->dump; return });
$agent->add_handler("response_done", sub { shift->dump; return });


# construct xmlrpc agent to talk to drupal services,
# we define our basic authentication credentials and create
# a cookie jar to hold the authentication cookie we receive
# from server.
sub SOAP::Transport::HTTP::Client::get_basic_credentials
{
	return ($nyup::http_user => $nyup::http_pass);
}

my $cookie_jar = HTTP::Cookies->new(ignore_discard => 1);


my $on_fault = sub {
	my ($xmlrpc, $res) = @_;
	$log->logdie(ref $res ? $res->faultstring : $xmlrpc->transport->status);
};

my $xmlrpc = XMLRPC::Lite
	-> proxy($drupal_services_proxy)
	-> on_fault($on_fault);

# login in to services interface
my $result = rpc("system.connect");
my $sessid = $result->{sessid};

$log->debug("Logging into drupal services interface");
$result = rpc("user.login", $nyup::drupal_user, $nyup::drupal_pass);
$log->debug("login user: ", Dumper($result));

$sessid = $result->{sessid};
$log->debug("Session id: $sessid");

$log->debug("Cookie Jar: ", $cookie_jar->as_string);

# my $tmpdir = tempdir(CLEANUP => 1);
my $tmpdir = "/tmp";
$log->debug("Temp directory: $tmpdir");


my $pkg_dir = dirname($xls_file);

my $excel = Spreadsheet::ParseExcel::Workbook->Parse($xls_file);

my $sheet = $excel->{Worksheet}[0];

$log->debug("Sheet: $sheet->{Name}");

for (qw(MinRow MaxRow MinCol MaxCol))
{
	$log->debug("$_: $sheet->{$_}");
}

my @field_names = get_row($sheet, 0);

my @pdf_types = (
	"Universal PDF",
	"Print PDF",
	"POD PDF",
	"PDF-A",
);

my %field_cck_map = (
	title         => 'TITLE',
	identifier    => 'ISBN 13',
	subtitle      => 'SUBTITLE',
	description   => 'DESCRIPTION',
	bisac_subject => 'BISAC TEXT',
	publisher     => 'PUB NAME',
	date          => 'PUBLICATION DATE',
	language_code => 'LANGUAGE',
	image_count   => 'NO OF PAGES',
);


for my $row (1 .. $sheet->{MaxRow})
{
	my $fields;
	my @values = get_row($sheet, $row);
	for my $col (0 .. $#values)
	{
		$fields->{$field_names[$col]} = $values[$col];
	}

	for my $name (sort keys %$fields)
	{
		$log->debug("xls field $name: $fields->{$name}");
	}

	my $isbn = $fields->{"ISBN 13"};
	my $title = $fields->{"TITLE"};
	
	my $doc_dir = "$pkg_dir/$isbn";

	$log->debug("document dir: $doc_dir");

	my $epub_file = "$doc_dir/ePub/$isbn.epub";

	if (! -f $epub_file) {
		$log->warn("Epub file $epub_file doesn't exist");
		next;
	}
	
	$fields->{EPUB_FILE} = $epub_file;

	my $pdf_file;

	for my $type (@pdf_types)
	{
		my $book_pdf = "$doc_dir/$type/$isbn.pdf";
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
	
	$fields->{PDF_FILE} = $pdf_file;
	
	my $thumb_file = "$tmpdir/${isbn}_thumb.png";
	create_thumb($pdf_file, $thumb_file);
	
	$log->debug("Setting CCK fields.");

	my $book = {
		node_type => "nyup_book",
		title     => $title,
		epub_file => [$epub_file, $isbn],
		pdf_file  => [$pdf_file, $isbn],
		thumbnail => [$thumb_file, $isbn],
	};

	my $cck_column;
	for $cck_column (keys %field_cck_map)
	{
		$log->debug("cck name: $cck_column");
		$book->{$cck_column} = $fields->{$field_cck_map{$cck_column}};
	}

	for my $i (1 .. 4)
	{
		my $contrib = $fields->{"CONTRIBUTOR $i"};
		if ($contrib)
		{
			my $role = lc($fields->{"CONTRIBUTOR $i ROLE"} || "");
			if ($role =~ /(author|editor)/) {
				$cck_column = $1;
			} else {
				$cck_column = "contributor";
			}
			push(@{$book->{$cck_column}}, $contrib);
		}
	}

	my $book_nid = create_node($book);

	$book = get_node($book_nid);

	create_pages($fields, $book);

	create_chapters($fields, $book);

}


sub create_thumb
{
	my ($input_file, $output_file) = @_;
	sys("convert -thumbnail x300 '$input_file\[0\]' $output_file");
}


sub create_pages
{
	my ($fields, $book) = @_;
	
	my $isbn     = $fields->{'ISBN 13'};
	my $pdf_file = $fields->{PDF_FILE};

	sys("pdfinfo '$pdf_file'");
	sys("pdftk '$pdf_file' dump_data");
# 	sys("convert '$pdf_file' -scene 1 x'$tmpdir/${isbn}_page_%04d.jp2'");

	opendir(my $dirh, $tmpdir) or $log->logdie("can't open $tmpdir: $!");
	my @images = sort(grep { /_\d{4}\.jp2$/ } readdir($dirh));
	close($dirh);

	for my $img (@images)
	{
		my ($page_num) = $img =~ /_(\d{4}).jp2$/;
		$page_num += 0;
		my $img_file = "$tmpdir/$img";
		$log->debug("img: $img_file");

		my $page = {
			node_type      => "nyup_page",
			title          => create_page_title($book->{title}, $page_num),
			book           => $book->{nid},
			page_number    => $page_num,
			image_number   => $page_num,
			page_type      => "normal",
			hand_side      => "unknown",
			visible        => 1,
			cropped_master => [$img_file, $isbn],
		};

		my $page_nid = create_node($page);
	}
}


sub create_chapters
{
	my ($fields, $book) = @_;

	my $isbn      = $fields->{'ISBN 13'};
	my $epub_file = $fields->{EPUB_FILE};
	my $epub_dir  = "$tmpdir/epub";
	my $files_dir = "$drupal_files_dir/$isbn/epub/";  

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
				add_file([$content_file, $isbn]);
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
			node_type    => "nyup_chapter",
			title        => "$book->{title} Chapter $item->{id}",
			book         => $book->{nid},
			chapter_name => $nav{$item->{href}}{chapter_name},
			play_order   => $nav{$item->{href}}{play_order},
			body         => $buf,
		};

		my $chapter_nid = create_node($chapter);
	}
}


sub get_row
{
	my ($sheet, $row) = @_;
	my @row = ();
	for my $col (0 .. $sheet->{MaxCol})
	{
		my $cell = $sheet->{Cells}[$row][$col];
		my $val = $cell->{Val} || "";
		$val =~ s/^\s+//;
		$val =~ s/\s+$//;
		push(@row, $val);
	}
	return @row;
}


sub rpc
{
	my ($method, @args) = @_;
	unshift(@args, $sessid) if $sessid;
	$log->debug("Method=$method Args=(", join(", ", @args), ")");
	$xmlrpc->call($method, @args)->result;
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


sub add_file
{
	my ($input_file, $subdir) = @{$_[0]};
	
	my $filename = basename($input_file);
	my $filepath = "$drupal_files_dir/$subdir/$filename";
	my $size     = (stat($input_file))[7];
	my $buf      = encode_file($input_file);
	my $mimetype = mimetype($input_file);
	my $now      = time;

	my $file = {
		file      => $buf,
		filename  => $filename,
		filepath  => $filepath,
		filemime  => $mimetype,
		filesize  => $size,
		uid       => 1,
		timestamp => $now,
	};

	$log->trace(Dumper($file));

# 	my $method = "file.create";
	my $method = "file.save";
	
	my $result = rpc($method, $file);
	$log->debug("$method result: ", Dumper($result));
# 	my $fid = $result->{fid};
	my $fid = $result;

	return [
		{
			'new'         => 1,
			'fid'         => $fid,
			'description' => $filename,
			'list'        => 1,
			'weight'      => 0,
		}
	];
}


sub create_node
{
	my ($obj) = @_;

	my $new_node = create_new_node();

	set_value($new_node, $obj);

	$log->trace("new $obj->{node_type} node: ", Dumper($new_node));

# 	my $method = "node.create";
	my $method = "node.save";
	my $result = rpc($method, $new_node);
	$log->debug("$method result: ", Dumper($result));
# 	my $nid = $result->{nid};
	my $nid = $result;

	$log->info("Saved $obj->{node_type} node $nid: $new_node->{title}");
	
	return $nid;
}


sub update_node
{
	my ($node, $new_vals) = @_;

	set_value($node, $new_vals);

	$log->trace("update $node->{type} node: ", Dumper($node));

	my $result = rpc("node.update", $node->{nid}, $node);
	$log->debug("node.update result: ", Dumper($result));
	my $nid = $result->{nid};

	$log->info("Saved $node->{type} node $node->{nid}: $node->{title}");
	return $nid;
}


sub set_value
{
	my ($node, $obj) = @_;

	for my $field (sort keys %$obj)
	{
		$log->trace("Setting $field");
		my $val = $obj->{$field};
		$log->trace("Setting $field to $val");
		if ($field eq "node_type")
		{
			$node->{type} = $val;
		}
		elsif ($field =~ /^(body|title)$/)
		{
			$node->{$field} = $val;
			if ($field eq "title")
			{
				$node->{field_title} = [{value => $val}];
			}
		}
		elsif ($field =~ /^(_ref|book)$/)
		{
			$node->{"field_$field"} = [{nid => $val}];
		}
		elsif ($field =~ /(_file|thumbnail|_master)$/)
		{
			$node->{"field_$field"} = add_file($val) if $val;
		}
		else
		{
			my @vals = ref($val) ? @$val : $val;
			$node->{"field_$field"} = [map { {value => $_} } @vals];
		}
		$log->trace("done");
	}

}


sub create_new_node
{
	my $now = time;
	return {
		type     => '',
		status   => 1,
		uid      => 1,
		title    => '',
		body     => '',
		created  => $now,
		changed  => $now,
		promote  => 1,
		sticky   => 0,
		format   => 1,
# 		language => 'und',
		name     => $nyup::drupal_user,
	};
}


sub get_node
{
	my $nodeid = shift;
# 	my $node = rpc("node.retrieve", $nodeid);
	my $node = rpc("node.get", $nodeid);
	$log->debug("node $nodeid: ", Dumper($node));
	return $node;
}


sub encode_file
{
	my $file = shift;
	my $encoded = "";
	my $buf;
	open(my $in, $file) or $log->logdie("can't open $file: $!");
	while (read($in, $buf, 60 * 57))
	{
		$encoded .= encode_base64($buf);
	}
	close($in);
	return $encoded;
}


sub sys
{
	my @cmd = @_;
	$log->debug("running command " . join(" ", @cmd));
	my $start_time = time;
	my ($output, $success, $exit_code) = capture_exec_combined(@cmd);
	my $end_time = time;
	$output =~ s/\r/\n/g;  # replace carriage returns with newlines
	$log->debug("output: $output");
	$log->debug("run time: ", duration_exact($end_time - $start_time));
	if (!$success) {
		$log->logdie("The exit code was " . ($exit_code >> 8));
	}
	return $output;
}


sub update_handle
{
	my ($agent, $handle, $node_url, $description) = @_;

	my $update_url = "$handle_service_url/$handle";

	my $xml = <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<hs:info xmlns:hs="info:nyu/dl/v1.0/identifiers/handle">
    <hs:binding>$node_url</hs:binding>
    <hs:description>$description</hs:description>
</hs:info>
EOF

	my $response = $agent->request(
		PUT(
			$update_url,
			Content_Type => 'text/xml',
			Content      => $xml
		)
	);

	if (!$response->is_success)
	{
		$log->logdie("Error updating handle at $update_url: ",
			$response->as_string);
	}

	$xml = XMLin($response->content, NormalizeSpace => 2);
	$log->debug(Dumper($xml));

	my $handle_url = "http://hdl.handle.net/$handle";
	if ($xml->{"hs:location"} ne $handle_url)
	{
		$log->logdie("Handle update failed. Expected '$handle_url' but got ",
			$xml->{"hs:location"});
	}
}


sub round
{
	my $num = shift;
	my $roundto = shift || 1;
	my $rounded = int($num / $roundto + 0.5) * $roundto;
	$log->debug("Rounded $num to $rounded");
	return $rounded;
}

