#!/usr/bin/env perl
#
# Script to convert NYU Press ONIX file to MODS.
#
# Author: Rasan Rasch <rasan@nyu.edu>

use FindBin;
use lib "$FindBin::Bin/lib";
use strict;
use warnings;
use File::Copy;
use Getopt::Std;
use HTML::Entities;
use ONIX;
use XML::LibXML;

my $schema_loc = "http://www.loc.gov/standards/mods/v3/mods-3-4.xsd";

our $opt_f;
getopts('f');

if (@ARGV != 2)
{
	print STDERR "\nUsage: $0 [ -f ] <input_onix_file> <output_mods_file>\n\n";
	print STDERR "\t-f\tforce overwrite of output_mods_file\n\n";
	exit 1;
}

my $onix_file = shift;
my $mods_file = shift;

if (-e $mods_file && !$opt_f)
{
 	die("Output file $mods_file already exists");
}

my $onix = ONIX->new($onix_file);

my $isbn      = $onix->isbn;
my $title     = enc($onix->title);
my @authors   = map(enc($_), $onix->author);
my $subtitle  = enc($onix->subtitle);
my $desc      = enc($onix->description);
my @subjects  = $onix->subject;
my $publisher = enc($onix->publisher);
my $pub_date  = $onix->pub_date;
my $lang_code = $onix->lang_code;
my $num_pages = $onix->num_pages;

my $xml = <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<mods xmlns:xlink="http://www.w3.org/1999/xlink" version="3.4" 
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.loc.gov/mods/v3"
  xsi:schemaLocation="http://www.loc.gov/mods/v3 http://www.loc.gov/standards/mods/v3/mods-3-4.xsd">

  <titleInfo>
    <title>$title</title>
    <subTitle>$subtitle</subTitle>
  </titleInfo>

EOF

for my $author (@authors)
{
	$xml .= <<EOF;
  <name type="personal">
    <namePart>$author</namePart>
    <role>
      <roleTerm authority="marcrelator">Author</roleTerm>
    </role>
  </name>
EOF
}

$xml .= <<EOF;

  <originInfo>
    <publisher>$publisher</publisher>
    <dateIssued>$pub_date</dateIssued>
  </originInfo>

  <language>
    <languageTerm authority="iso639-2b" type="code"
      authorityURI="http://id.loc.gov/vocabulary/iso639-2"
      valueURI="http://id.loc.gov/vocabulary/iso639-2/$lang_code">$lang_code</languageTerm>
  </language>

  <abstract>$desc</abstract>

EOF

for my $subject (@subjects)
{
	my $topic = enc($subject->{text});
	$xml .= '  <subject';
	$xml .= ' authority="BISAC Subject Heading"'
	  if $subject->{scheme_id} == 10;
	$xml .= ">\n";
	$xml .= "    <topic>$topic</topic>\n";
	$xml .= "  </subject>\n";
}

$xml .= <<EOF;

  <physicalDescription>
    <extent>$num_pages pages</extent>
  </physicalDescription>

  <identifier type="isbn">$isbn</identifier>

</mods>
EOF

my $schema = XML::LibXML::Schema->new(location => $schema_loc);

my $mods = XML::LibXML->load_xml(string => $xml);

$mods->validate($schema);

open(my $out, ">$mods_file") or die("can't open $mods_file: $!");
print $out $xml;
close($out);


sub enc
{
	my $val = shift;
	return encode_entities($val, q|<>&"'|);
}

