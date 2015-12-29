#!/usr/bin/env perl
#
# Generate AIPs NYU Press content.
#
# Author: Rasan Rasch <rasan@nyu.edu>

use strict;
use warnings;
use Digest::MD5;
use Digest::SHA1;
use File::Basename;
use File::Copy;
use File::Copy::Recursive qw(dircopy);
use File::Find;
use File::Path;
use File::Temp qw(tempdir);
use MyLogger;
use POSIX;
use Util;


$SIG{HUP} = 'IGNORE';

umask 022;

my $log = MyLogger->get_logger();

my $tmpdir = tempdir(
	CLEANUP => 1,
	DIR     => "/tmp",
);

$log->debug("Temp directory: $tmpdir");

my $rstar_dir = "/path/to/rstar/content";

my $xip_dir = "$rstar_dir/xip";

my @bagids = Util::get_dir_contents($xip_dir);

my $noid_file = "noid.txt";

my @noids = ();
my ($in, $out, $line);
open($in, $noid_file) or $log->logdie("can't open $noid_file: $!");
while ($line = <$in>)
{
	my ($noid) = $line =~ /^id:\s+(.*)$/;
	push(@noids, $noid);
	$log->debug("noid: $noid");
}
close($in);

my $now = now();

my $aip_version = "v0001";

for my $bagid (sort @bagids)
{	
	my ($id) = $bagid =~ /^(\d{13})\-/;
	$log->debug("id: $id");

	my $aip_root = shift(@noids);

	my $bag_root_dir  = "$xip_dir/$bagid";
	my $bag_data_dir  = "$bag_root_dir/data";
	my $bag_book_dir  = "$bag_data_dir/$id";
	my $bag_md5_file  = "$bag_root_dir/manifest-md5.txt";

	open($in, $bag_md5_file)
		or $log->logdie("can't open $bag_md5_file: $!");
	while ($line = <$in>)
	{
		my ($chksum, $file) = $line =~ /^(\w+)\s+(.*)$/;
		$log->debug("chksum: $chksum, file: $file");
	}
	close($in);

	my $aip_root_dir    = "$tmpdir/$aip_root";
	my $aip_files_dir   = "$aip_root_dir/files";
	my $aip_version_dir = "$aip_files_dir/$aip_version";
	my $aip_data_dir    = "$aip_version_dir/data";
	my $aip_meta_dir    = "$aip_version_dir/metadata";

	rmtree($aip_root_dir);

	mkpath($aip_meta_dir);

	$log->info("Copying $bag_book_dir to $aip_data_dir");
	dircopy($bag_book_dir, $aip_data_dir)
	  or $log->logdie("Can't copy $bag_book_dir to $aip_data_dir: $!");

	finddepth(\&rename_file, $aip_data_dir);


	my @book_files = ();

	find(sub { push(@book_files, $File::Find::name) if /\.(epub|pdfa?)$/i },
		$aip_data_dir);

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
			sys("mediainfo --Full --Language=raw --Output=XML $book_file > $meta_files{mediainfo}");
		}

	}

	my ($old_onix_file) = glob("$bag_data_dir/*_onix.xml");
	my $new_onix_file = "$aip_meta_dir/${id}_onix.xml";
	copy($old_onix_file, $new_onix_file)
	  or $log->logdie("can't copy $old_onix_file to $new_onix_file: $!");

	my $mods_file = $new_onix_file;
	$mods_file =~ s/_onix.xml$/_mods.xml/;
	sys("./onix2mods.pl $new_onix_file $mods_file");

	my $rights_tmpl = "aip-templates/aip-rights.xml.tmpl";
	my $rights_file = "$aip_root_dir/$aip_root-aip-rights.xml";
	open($in,  "<$rights_tmpl") or $log->logdie("can't open $rights_tmpl: $!");
	open($out, ">$rights_file") or $log->logdie("can't open $rights_file: $!");
	while ($line = <$in>)
	{
		print $out $line;
	}
	close($in);
	close($out);
	my $rights_checksum = get_sha1_checksum($rights_file);

	my $aip_mets_file = "$aip_root_dir/$aip_root-$aip_version.xml";
	my $aip_mets_tmpfile = "$aip_mets_file.tmp";
	sys("java -jar GenNyupAipMets/lib/gennyupaipmets.jar $aip_root $aip_version $aip_root_dir $aip_mets_tmpfile");
	sys("xsltproc -o $aip_mets_file add-namespace.xsl $aip_mets_tmpfile");
	unlink($aip_mets_tmpfile)
		or $log->logdie("can't unlink $aip_mets_tmpfile: $!");
	my $aip_mets_checksum = get_sha1_checksum($aip_mets_file);

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

	sys("/usr/local/dlib/pr/bin/pr-qa-pr-aip -d $aip_root_dir");

}


sub rename_file
{
	my $old_name = $_;
	my $new_name = $old_name;

	if ($new_name =~ /^\..+/ || $new_name =~ /\.DS_Store$/)
	{
		$log->debug("Removing $new_name.");
		if (-d $new_name) {
			rmdir($new_name) or $log->logdie("can't rmdir $new_name: $!");
		} else {
			unlink($new_name) or $log->logdie("can't unlink $new_name: $!");
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


