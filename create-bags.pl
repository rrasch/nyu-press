#!/usr/bin/env perl
#
# Generate bags for newly transferred NYU Press content.
#
# Author: Rasan Rasch <rasan@nyu.edu>

use strict;
use warnings;
use Cwd;
use Data::UUID;
use File::Basename;
use File::Path;
use File::Temp qw(tempdir);
use MyLogger;
use POSIX;
use Time::Duration;
use Sys;
use XML::LibXML;
use XML::Twig;


my $dropbox_dir = "/path/to/dropbox";

my $bindir = "/path/to/rstar/bin";

my $tmp_root = "/tmp";

if (!@ARGV)
{
	print STDERR "\nUsage: $0 [ONIX_FILE] ...\n\n";
	exit 1;
}

$SIG{HUP} = 'IGNORE';

umask 022;

my $log = MyLogger->get_logger();

my @combined_onix_files = @ARGV;

for my $combined_onix_file (@combined_onix_files)
{
	$log->logdie("Onix file $combined_onix_file doesn't exist")
	  if !-f $combined_onix_file;
	my $onix = XML::LibXML->load_xml(location => $combined_onix_file);
	eval { $onix->validate() };
	$log->logdie("Onix file $combined_onix_file is invalid: $@") if $@;
}

my $tmpdir = tempdir(
	CLEANUP => 0,
	DIR     => $tmp_root,
);

$log->debug("Temp directory: $tmpdir");

my @onix_files = ();

for my $combined_onix_file (@combined_onix_files)
{
	my $prefix = basename($combined_onix_file);
	$prefix =~ s/_onix.xml$//;
	$prefix = "$tmpdir/$prefix";
	$log->debug("Splitting $combined_onix_file.");
	push(@onix_files, split_xml($combined_onix_file, $prefix));
}

my $cwd = cwd();

for my $onix_file (@onix_files)
{
	$log->debug("Processing $onix_file");

	my $onix = XML::LibXML->load_xml(location => $onix_file);
	my ($product) = $onix->findnodes('/ONIXMessage/Product');

	my %isbn;
	for my $id ($product->findnodes('./ProductIdentifier'))
	{
		my $idval = $id->findvalue('./IDValue');
		my $len   = length($idval);
		$isbn{$len} = $idval;
		$log->debug("isbn[$len]: $isbn{$len}");
	}
	$log->debug("ISBN: $isbn{13}");

	my ($prev_bagdir) = glob("$tmpdir/$isbn{13}-*");
	if ($prev_bagdir)
	{
		$log->warn("$prev_bagdir already exists. Skipping $isbn{13}.");
		unlink($onix_file)
		  or $log->logdie("can't unlink $onix_file: $!");
		next;
	}

	my $uuid = Data::UUID->new->create_str();

	my $srcdir  = "$dropbox_dir/$isbn{13}";
	my $bagdir  = "$tmpdir/$isbn{13}-$uuid";
	my $datadir = "$bagdir/data";

	my $md5_file  = "$bagdir/manifest-md5.txt";
	my $info_file = "$bagdir/bag-info.txt";

	$log->debug("bagdir: $bagdir");

	if (!-d $srcdir)
	{
		$log->warn("$srcdir doesn't exist. Skipping $isbn{13}.");
		next;
	}

	mkpath($datadir);
	sys("cp -av $srcdir $datadir");
	sys("mv $onix_file $datadir");

	chdir($bagdir) or $log->logdie("can't chdir $bagdir: $!");
	sys("$bindir/gen-bagit.sh .");
# 	sys("md5deep -rl data > manifest-md5.txt");
	chdir($cwd) or $log->logdie("can't chdir $cwd: $!");

	my $now = POSIX::strftime('%Y-%m-%d-T%H%M%S', localtime);
	open(my $out, ">$info_file")
	  or $log->logdie("can't open $info_file: $!");
	print $out "nyu-dl-project-name: nyup/nyupress\n";
	print $out "Bagging-Date: $now\n";
	close($out);
	sys("$bindir/gen-oxum.sh $bagdir >> $info_file");
	sys("/usr/local/bin/bag update $bagdir");
	sys("/usr/local/bin/bag updatetagmanifests $bagdir");

	sys("$bindir/check-bag.sh $bagdir");

	$log->info("bagging complete for $isbn{13}");

}


sub split_xml
{
	my ($xml_file, $prefix) = @_;
	my @split_files = ();

	my $twig = new XML::Twig(
		pretty_print => 'indented',
	);

	$twig->parsefile($xml_file);

	my $root = $twig->root;

	my @products = $root->cut_children('Product');

	my $placeholder = $root->new('Product');

	$placeholder->paste(last_child => $root);
	
	while (@products)
	{
		my $product = shift @products;
		my $isbn = get_isbn($product);
		my $split_file = "${prefix}_${isbn}_onix.xml";
		$product->replace($placeholder);
		$placeholder = $product;
# 		$log->logdie("$split_file already exists.") if -f $split_file;
		open(my $out, ">$split_file")
		  or $log->logdie("Can't open $split_file: $!");
		$twig->print($out);
		close($out);
		$log->debug("Wrote $split_file");
		push(@split_files, $split_file);
	}

	return @split_files;
}


sub get_isbn
{
	my $product = shift;
	my ($id_type) =
	  $product->findnodes('./ProductIdentifier/ProductIDType[string()="15"]');
	my $isbn = $id_type->next_sibling_text;
	$log->debug("ISBN: $isbn");
	return $isbn;
}

