#!/usr/bin/env perl
#
# Author: Rasan Rasch <rasan@nyu.edu>

use strict;
use warnings;
use utf8;
use MyLogger;
use XML::LibXML;
use MyConfig;


$SIG{HUP} = 'IGNORE';

my $log = MyLogger->get_logger();

my $rstar_dir = config('rstar_dir');

my $onix_file = "onix.xml";

my $onix = XML::LibXML->load_xml(location => $onix_file);

for my $product ($onix->findnodes('/ONIXMessage/Product'))
{
	my %isbn;
	for my $id ($product->findnodes('./ProductIdentifier'))
	{
		my $idval = $id->findvalue('./IDValue');
		$isbn{length($idval)} = $idval;
	}

	my $xml_file = "$isbn{13}.xml";
	open(my $out, ">$xml_file") or $log->logdie("Can't open $xml_file: $!");
	print $out $product->toString();
	close($out);
}

