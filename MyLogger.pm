package MyLogger;

use Log::Log4perl qw(:easy :no_extra_logdie_message);

use base 'Log::Log4perl';

MyLogger->easy_init(
	{
		level  => $DEBUG,
# 		level  => $TRACE,
		file   => "STDERR",
		layout => "[%d %p] %m%n"
	}
);

1;
