#!/usr/bin/env perl
#
# Script to validate incoming transfers.
#
# Author: Rasan Rasch <rasan@nyu.edu>

use strict;
use warnings;
use Capture::Tiny qw(capture_merged);
use Cwd qw(abs_path cwd);
use File::Basename;
use File::Copy;
use File::Find;
use File::Temp qw(tempdir);
use Util;
use MyConfig;
use MyLogger;

my $dropbox_dir = "/path/to/dropbox";

my $base_tmp_dir = "/tmp";

my $csv_file = "results.csv";

$SIG{HUP} = 'IGNORE';

umask 022;

my $log = MyLogger->get_logger();

# find directory where this script resides
my $app_home = dirname(abs_path($0));

my $cwd = cwd();

my @ids = @ARGV ? @ARGV : Util::get_dir_contents($dropbox_dir);

my $tmpdir = tempdir(
	CLEANUP => 1,
	DIR     => $base_tmp_dir,
);

$log->debug("Temp directory: $tmpdir");

my %pdf_cfg = (
	a => ["Paperback Print"],
# 	b => ["POD PDF", "Cover PDF"],
	b => ["POD PDF"],
	c => ["Cloth Originals"],
	d => ["WebPDF"],
# 	e => ["Print PDF", "Cover PDF"],
	e => ["Print PDF"],
	f => ["Universal PDF"],
);

open(my $out, ">$csv_file") or $log->logdie("Can't open $csv_file: $!");

for my $id (@ids)
{

	$log->trace("Processing $id");

	my $book_dir = "$dropbox_dir/$id";
	
	my @files;

	chdir($book_dir);

	find(
		sub {
			system("unzip -u -j $_ '$id*.pdf' >> $cwd/unzip.log 2>&1")
			  if /\.zip$/;
		},
		"."
	);

	my $num_fail = 0;

	find(
		sub {
			my $filename = fileparse($_, qr/\.[^.]*/);
# 			if (/$id.*\.pdf$/ && !-f "$filename.pdfa")
			if (/$id.*\.pdf$/)
			{
				my $pdf_file = $File::Find::name;
				$pdf_file =~ s/^\.\///;
				$pdf_file = "$book_dir/$pdf_file";
				my $pdfa_file = "${pdf_file}a";

				if (-f $pdfa_file)
				{
					if (system("$app_home/validate-pdfa.sh '$pdfa_file'"))
					{
						$log->info("'$pdfa_file' failed to validate");
						unlink($pdfa_file);
						system("$app_home/pdf2pdfa.new '$pdf_file'");
					}
				}

# 				if (system("$app_home/pdf2pdfa.new '$pdf_file'"))
# 				{
# 					$num_fail++;
# 				}
			}
			push(@files, $File::Find::name) if -f && !/\.pdfa$/;
		},
		"."
	);

# 	find(sub { push(@files, $File::Find::name) if -f  }, ".");
# 	find(sub { push(@files, $File::Find::name) if -f  }, $book_dir);

	chdir($cwd);

	if ($num_fail) {
		print $out ",rejected,", join("|", @files), "\n";
		next;
	}

	my $pdf_file;

	my $pass = 0;

	for my $cfg_name (sort keys %pdf_cfg)
	{
		$log->trace("Checking pdf configuration $cfg_name");

		my @types = @{$pdf_cfg{$cfg_name}};

		my $num_found = 0;
		my $num_required = scalar(@types);

		for my $type (@types)
		{
			my $pdf_file = "$dropbox_dir/$id/$type/$id.pdf";
			$log->trace("Checking for $pdf_file");
			if (-f $pdf_file) {
				$num_found++;
			}
		}

		if ($num_found == $num_required) {
			$pass = 1;
			last;
		}

	}

	print $out $id;
	
	if ($pass) {
		$log->info("ISBN $id ACCEPTED");
		print $out ",accepted\n";
	} else {
		$log->info("ISBN $id REJECTED");
		print $out ",rejected,", join("|", @files), "\n";
	}


}

close($out);


