# restartFWWS.pl: restart File Watcher Windows Service/
# Requires Run as administrator.

use strict;
use warnings;
use Win32::Service;
use Win32::RunAsAdmin qw(force);

my %status;
my %status_code = (
	Stopped       => 1,
	StartPending  => 2,
	StopPending   => 3,
	Running       => 4,
	ResumePending => 5,
	PausePending  => 6,
	Paused        => 7
);

RestartService("File Watcher Windows Service");

sub RestartService {
	my ($serviceName) = @_;
	my $startCounter  = 1;
	my $maxAttempts   = 3;

	while ($startCounter <= $maxAttempts)
		{
		Win32::Service::StartService('', $serviceName);
		sleep(3);
		Win32::Service::GetStatus('', $serviceName, \%status);
		if ($status{"CurrentState"} eq $status_code{Running})
			{
			last;
			}
		$startCounter++;
		}
}
