#!/usr/bin/env perl

use strict;
use warnings;
no warnings 'uninitialized';

use XML::Rules;

die "Usage: $0 split_tag filename(s)\n" unless @ARGV >= 2;
my ($split_tag, @files) = @ARGV;

my $parser = XML::Rules->new(
	rules => [
		_default => 'raw',
		$split_tag => sub {
			my ($file, $id) = ( $_[4]->{parameters}{'file'}, ++$_[4]->{parameters}{'id'});
			$id = sprintf "%04d", $id;
			$file =~ s/(?:\.xml)?$/-$id.xml/i;

			if (ref $_[3]->[-1]{_content}) {
				$_[3]->[-1]{_content}[-1] =~ s/^.*(\n[^\n]+)$/$1/s;
			} else {
				$_[3]->[-1]{_content} =~ s/^.*(\n[^\n]+)$/$1/s;
			}

			print " $file\n";
			open my $FH, '>:utf8', $file or die qq{Can't create "$file": $^E\n};
			print $FH $_[4]->parentsToXML();
			print $FH $_[4]->ToXML( $_[0], $_[1]),"\n";
			print $FH $_[4]->closeParentsToXML();
			close $FH;

			return;
		}
	]
);


foreach my $file (@files) {
	$parser->parsefile( $file, {file => $file});
}
