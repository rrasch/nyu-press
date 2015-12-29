#!/usr/bin/env perl
#
# Split onix xml file by Product tag.
#
# Author: Rasan Rasch <rasan@nyu.edu>

use strict;
use warnings;
use Cwd qw(abs_path);
use Getopt::Std;
use File::Basename;
use File::Path;
use File::Temp qw(tempdir);
use MyLogger;
use XML::LibXML;
use XML::Twig;

our ($opt_f, $opt_p);
getopts('fp:');

if (!@ARGV)
{
	print STDERR "\nUsage: $0 [-f FORCE] [-p PREFIX] ONIX_FILE ...\n\n";
	exit 1;
}

my $log = MyLogger->get_logger();

$log->debug("Prefix will be set to $opt_p") if $opt_p;

my @combined_onix_files = map(abs_path($_), @ARGV);

for my $combined_onix_file (@combined_onix_files)
{
	$log->logdie("Onix file $combined_onix_file doesn't exist")
	  if !-f $combined_onix_file;
	my $onix = XML::LibXML->load_xml(location => $combined_onix_file);
	eval { $onix->validate() };
	$log->logdie("Onix file $combined_onix_file is invalid: $@") if $@;
}

for my $combined_onix_file (@combined_onix_files)
{
	my $prefix;
	if ($opt_p) {
		$prefix = $opt_p;
	} else {
		($prefix = $combined_onix_file) =~ s/onix.xml$//;
	}
	$log->debug("Splitting $combined_onix_file.");
	split_xml($combined_onix_file, $prefix);
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
		my $split_file = "${prefix}${isbn}_onix.xml";
		$product->replace($placeholder);
		$placeholder = $product;
		$log->logdie("$split_file already exists.")
		  if -f $split_file && !$opt_f;
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

