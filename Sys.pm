package Sys;

use strict;
use warnings;
our $VERSION = '0.01';

use base 'Exporter';
our @EXPORT = qw(sys);

use Capture::Tiny qw(capture_merged);
use MyLogger;
use Time::Duration;

my $log = MyLogger->get_logger();

sub sys
{
	my @cmd = @_;
	$log->debug("running command " . join(" ", @cmd));
	my $start_time = time;
	my ($retval, $errno);
	my $output = capture_merged {
		$retval = system(@cmd);
		$errno = $!;
	};
	my $end_time = time;
	$output =~ s/\r/\n/g;  # replace carriage returns with newlines
	$log->debug("output: $output");
	$log->debug("run time: ", duration_exact($end_time - $start_time));
	if ($retval)
	{
		if ($? == -1)
		{
			$log->logdie("failed to execute $cmd[0]: $errno");
		}
		elsif ($? & 127)
		{
			$log->logdie(
				sprintf(
					"child died with signal %d, %s coredump",
					($? & 127),
					($? & 128) ? 'with' : 'without'
				)
			);
		}
		else
		{
			$log->logdie(sprintf("child exited with value %d", $? >> 8));
		}
	}
	return $output;
}

1;
