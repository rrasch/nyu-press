#!/usr/bin/env perl
#
# Generate AIPs NYU Press content.
#
# Author: Rasan Rasch <rasan@nyu.edu>

use FindBin;
use lib "$FindBin::Bin/lib";
use strict;
use warnings;
use Cwd qw(abs_path);
use DB_File;
#use Digest::SHA1;
use File::Basename;
use File::Copy;
use File::Copy::Recursive qw(dircopy);
use File::Find;
use File::Path;
use File::Temp qw(tempdir);
use MyLogger;
use ONIX;
use POSIX;
use Util;


my %pdf_config = (
	a => ["Universal PDF"],
	b => ["Print PDF", "Cover PDF"],
	c => ["POD PDF", "Cover PDF"],
);

my $work_dir = "/path/to/work/dir";

my $valid_aip_dir = "$work_dir/valid";

my $status_db_file = "status_aips.db";

if (!@ARGV)
{
	print STDERR "\nUsage: $0 ONIX_FILE ...\n\n";
	exit 1;
}

my @onix_files = @ARGV;

$SIG{HUP} = 'IGNORE';

umask 022;

my $log = MyLogger->get_logger();

our %status;
our $id;

tie(%status, "DB_File", $status_db_file, O_RDWR | O_CREAT, 0666, $DB_HASH)
  or $log->logdie("can't open $status_db_file: $!");

for (sort keys %status)
{
	$log->trace("status $_: $status{$_}");
}

$SIG{__DIE__} = sub {
	if ($id && !$status{$id}) {
		$status{$id} = "FAILED";
	}
};

END {
	untie %status;
}

my $tmpdir = tempdir(
	CLEANUP => 1,
	DIR     => "$work_dir/tmp",
);

$log->debug("Temp directory: $tmpdir");

my $now = now();

my $aip_version = "v0001";

for my $onix_file (sort @onix_files)
{
	$log->debug("ONIX file: $onix_file");
	
	my $base_dir = dirname(abs_path($onix_file));

	my $onix = ONIX->new($onix_file);

	$id = $onix->isbn;
	$log->debug("id: $id");

	if ($status{$id} && $status{$id} =~ /PASSED/)
	{
		$log->warn("$id already processed with status $status{$id}");
		next;
	}

	my $book_dir  = "$base_dir/$id";

	if (!-d $book_dir)
	{
		$log->logdie("$id directory does not exist.");
	}

	# Test if we have the right pdfs to archive
	my $is_valid = 0;
	my @archive_pdfs = ();
	for my $cfg_name (sort keys %pdf_config)
	{
		$log->debug("Checking if content conforms to config '$cfg_name' ...");
		my $num_missing = 0;
		@archive_pdfs = ();
		for my $dir (@{$pdf_config{$cfg_name}})
		{
			my $pdf_file = "$book_dir/$dir/$id.pdf";
			if (! -f $pdf_file)
			{
				$log->debug("Can't find pdf: '$pdf_file'");
				$num_missing++;
			}
			else
			{
				push(@archive_pdfs, $pdf_file);
			}
		}
		$log->debug("Num missing $cfg_name: $num_missing");
		if (!$num_missing)
		{
			$log->debug("Content is a valid '$cfg_name' config");
			$is_valid = 1;
			last;
		}
	}

	if (!$is_valid)
	{
		$log->logdie("Book $id does not conform to valid configuration.");
	}

	# Now try to convert pdfs to PDF/A archival format.
	my $num_err = 0;
	for my $pdf_file (@archive_pdfs)
	{
		my $pdfa_file = "${pdf_file}a";
		sys("./pdf2pdfa", $pdf_file, $pdfa_file);
		if (!-f $pdfa_file)
		{
			$log->warn("Can't generate PDF/A file for '$pdf_file'");
			$num_err++;
			next;
		}
	}

	if ($num_err)
	{
		$log->logdie("There was a problem with PDFA/A conversion for $id");
	}

	my $aip_root = Util::get_noids(1);
	$log->debug("AIP root: $aip_root");

	my $aip_root_dir    = "$tmpdir/$aip_root";
	my $aip_files_dir   = "$aip_root_dir/files";
	my $aip_version_dir = "$aip_files_dir/$aip_version";
	my $aip_data_dir    = "$aip_version_dir/data";
	my $aip_meta_dir    = "$aip_version_dir/metadata";

	rmtree($aip_root_dir);

	mkpath($aip_meta_dir);

	# Copy over files to our new AIP directory
	$log->info("Copying $book_dir to $aip_data_dir");
	dircopy($book_dir, $aip_data_dir)
	  or $log->logdie("Can't copy $book_dir to $aip_data_dir: $!");

	# Normalize file paths
	finddepth(\&rename_file, $aip_data_dir);

	# Get list of all pdf/epub files.
	my @book_files = ();
	find(sub { push(@book_files, $File::Find::name) if /\.(epub|pdfa?)$/i },
		$aip_data_dir);

	# Generate technical metadata for book files.
	for my $book_file (@book_files)
	{
		$log->debug("book file: $book_file");
		my $meta_file = $book_file;
		$meta_file =~ s,/data/,/metadata/,;
		$meta_file =~ s/\.([^.]+)$/_$1/;

		my %meta_files =
		  map { $_ => "${meta_file}_$_.xml" } qw(jhove exiftool mediainfo);

		$meta_files{pdftk} = "${meta_file}_pdftk.txt";

		my $dirname = dirname($meta_file);
		if (! -d $dirname) {
			$log->info("Creating directory $dirname.");
			mkpath($dirname);
		}

		for my $mfile (sort keys %meta_files)
		{
			if (-f $mfile) {
				$log->logdie("Metadata file $mfile already exists.");
			}
		}

		sys("jhove -h xml -o $meta_files{jhove} $book_file");

		if ($book_file =~ /pdfa?$/i) {
			sys("pdftk $book_file dump_data > $meta_files{pdftk}");
		} elsif ($book_file =~ /jpe?g$/i) {
			sys("exiftool -X $book_file > $meta_files{exiftool}");
		} elsif ($book_file =~ /mp4$/i) {
			sys("mediainfo --Full --Language=raw "
			  . "--Output=XML $book_file > $meta_files{mediainfo}");
		}

	}

	my $new_onix_file = "$aip_meta_dir/${id}_onix.xml";
	copy($onix_file, $new_onix_file)
	  or $log->logdie("can't copy $onix_file to $new_onix_file: $!");

	# Convert ONIX to MODS
	my $mods_file = $new_onix_file;
	$mods_file =~ s/_onix.xml$/_mods.xml/;
	sys("./onix2mods.pl $new_onix_file $mods_file");

	# Generate METS Rights from template file.
	my $rights_tmpl = "aip-templates/aip-rights.xml.tmpl";
	my $rights_file = "$aip_root_dir/$aip_root-aip-rights.xml";
	my ($in, $out, $line);
	open($in,  "<$rights_tmpl") or $log->logdie("can't open $rights_tmpl: $!");
	open($out, ">$rights_file") or $log->logdie("can't open $rights_file: $!");
	while ($line = <$in>)
	{
		print $out $line;
	}
	close($in);
	close($out);
	my $rights_checksum = get_sha1_checksum($rights_file);

	# Generate METS for data files using Harvard's METS java lib
	my $aip_mets_file = "$aip_root_dir/$aip_root-$aip_version.xml";
	my $aip_mets_tmpfile = "$aip_mets_file.tmp";
	sys("java -jar GenNyupAipMets/lib/gennyupaipmets.jar "
	  . "$aip_root $aip_version $aip_root_dir $aip_mets_tmpfile");
	sys("xsltproc -o $aip_mets_file add-namespace.xsl $aip_mets_tmpfile");
	unlink($aip_mets_tmpfile)
		or $log->logdie("can't unlink $aip_mets_tmpfile: $!");
	my $aip_mets_checksum = get_sha1_checksum($aip_mets_file);

	# Generate AIP METS from template file
	my $aip_tmpl = "aip-templates/aip.xml.tmpl";
	my $aip_file = "$aip_root_dir/aip.xml";
	open($in,  "<$aip_tmpl") or $log->logdie("can't open $aip_tmpl: $!");
	open($out, ">$aip_file") or $log->logdie("can't open $aip_file: $!");
	while ($line = <$in>)
	{
		$line =~ s/<ISBN>/$id/g;
		$line =~ s/<CREATE_DATE>/$now/g;
		$line =~ s/<AIP_ROOT>/$aip_root/g;
		$line =~ s/<AIP_VERSION>/$aip_version/g;
		$line =~ s/<METS_RIGHTS_CHECKSUM>/$rights_checksum/g;
		$line =~ s/<METS_AIP_CHECKSUM>/$aip_mets_checksum/g;
		print $out $line;
	}
	close($in);
	close($out);

	# Validate AIP
	sys("/usr/local/dlib/pr/bin/pr-qa-pr-aip-v1.0.1 -V -d $aip_root_dir");

	sys("mv $aip_root_dir $valid_aip_dir");
	sys("mv $onix_file $valid_aip_dir");

	$status{$id} = "PASSED";
}


sub rename_file
{
	my $old_name = $_;
	my $new_name = $old_name;

	if ($old_name =~ /^\..+/
		or -f $old_name && $old_name !~ /\.(pdfa?|jpe?g)$/i)
	{
		$log->debug("Removing $old_name.");
		if (-d $old_name)
		{
			rmdir($old_name) or $log->logdie("can't rmdir $old_name: $!");
		}
		else
		{
			unlink($old_name) or $log->logdie("can't unlink $old_name: $!");
		}
	}

	if ($new_name =~ s/[^A-Za-z0-9\-\._]/_/g)
	{
		$log->debug("Renaming $old_name to $new_name.");
		rename($old_name, $new_name)
		  or $log->logdie("can't rename $old_name to $new_name: $!");
	}
}


sub get_mod_date
{
	my $file = shift;
	my $mtime = (stat($file))[9];
	return format_date($mtime);
}


sub now
{
	return format_date();
}


sub format_date
{ 
	my $time = shift || time;
	return strftime('%Y-%m-%dT%H:%M:%S', localtime($time));
}


sub get_sha1_checksum
{
	my $file = shift;
	open(my $in, $file) or $log->logdie("can't open $file: $!");
	my $sha1 = Digest::SHA1->new;
	$sha1->addfile($in);
	my $digest = $sha1->hexdigest;
	close($in);
	return $digest;
}

