#!/usr/bin/env perl

use strict;
use warnings;
use DBI;
use File::Basename;
use MyConfig;
use MyLogger;
use Util;


$SIG{HUP} = 'IGNORE';

my $log = MyLogger->get_logger();

my @files = @ARGV;

my $dsn =
  "DBI:mysql:database=" . config('dbname') . ';host=' . config('dbhost');
my $dbh = DBI->connect($dsn, config('dbuser'), config('dbpass'))
  or $log->logdie($DBI::errstr);

my $stmt =
    "UPDATE "
  . config('dbprefix')
  . "file_managed SET filesize = ? WHERE filename = ?";

my $sth = $dbh->prepare($stmt) or $log->logdie($dbh->errstr);

open(my $in, "copy.sh") or $log->logdie("can't open copy.sh: $!");

while (my $line = <$in>)
{
	next unless $line =~ /'(.*)'/;
	my $file = $1;
	my $size = (stat($file))[7];
	$log->debug("file: $file, size: $size");

	my $status = $sth->execute($size, basename($file));
	if ($status eq "0E0") {
		$log->warn("No rows updated for $file.");
	} elsif (!$status) {
		$log->warn("Problem updating file info for $file.");
	}
}

$sth->finish;
$dbh->disconnect;

