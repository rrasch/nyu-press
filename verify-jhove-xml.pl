#!/usr/bin/env perl

use strict;
use warnings;
use Data::Dumper;
use XML::Simple;

my $xml = XMLin('-');
# print STDERR  Dumper($xml);

my $uri = $xml->{repInfo}{uri};
# print STDERR  "uri=$uri\n";

my $status = $xml->{repInfo}{status};
# print STDERR  "status=$status\n";

my $profile = $xml->{repInfo}{profiles}{profile} || "";
# print STDERR  "profile=$profile\n";

unless ($status eq "Well-Formed and valid" && $profile =~ m,PDF/A,)
{
	die("PDF '$uri' failed validation");
}

