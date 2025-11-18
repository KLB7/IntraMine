# mon.pm: write messages to disk and send a WS message when one is written.
# This is for use by the intramine_mon.pl server (and mon.js).
# Basically, what would otherwise be print() statements to a console
# window are instead saved to a temp file, and a WebSockets message
# goes out signalling that new output is available. The messages
# are displayed by the "Mon" service (intramine_mon.pl).
# For services based on swarmserver.pm all the setup is done
# under the hood, and one need only call
# Monitor("text\n");
# to see results in the Mon browser tab.
# See eg intramine_main.pl#StartAllServers().

package mon;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use Time::HiRes qw(usleep);
use Path::Tiny  qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
#use lib ".";
use common;
use win_wide_filepaths;


my $MonitorFilePath = '';                   # Full path to main log file.
my $CallbackNotify;                         # Send a WebSockets message
my $WebsocketsMessage = 'NEWRUNMESSAGE';    # The message
my $OkToSend          = 0;                  # Becomes 1 when WebSockets are available
my @MessageCache;                           # For messages sent before init

# Call once, only in Main.
# The main log file is deleted.
sub MainInitIntraMineMonitor {
	my ($filePath, $callbackForMessageNotification) = @_;
	$MonitorFilePath   = $filePath;
	$CallbackNotify    = $callbackForMessageNotification;
	$OkToSend          = 0;
	$WebsocketsMessage = 'NEWRUNMESSAGE';
	DeleteFileWide($MonitorFilePath);
}

# Call in non-Main services.
# The main log file is NOT deleted.
sub ServiceInitIntraMineMonitor {
	my ($filePath, $callbackForMessageNotification) = @_;
	$MonitorFilePath   = $filePath;
	$CallbackNotify    = $callbackForMessageNotification;
	$OkToSend          = 0;
	$WebsocketsMessage = 'NEWRUNMESSAGE';
}

# Call when WebSockets is available, see
# swarmserver.pm#MainLoop() and intramine_main.pl#MainLoop().
sub MonNowOkToSend {
	$OkToSend = 1;
}

# Pump out the $msg to a text file and send a WebSockets notification.
# Some HTML elements are acceptable, eg <strong> and <pre>.
# NOTE if you send a <pre> element it must be sent as
# a single message in order to display properly
# - see intramin_main.pl#ShowHummingbird() around #3462.
# In theory this can be called before Init or MonNowOkToSend,
# although no notication will happen until after those.
sub Monitor {
	my ($msg)    = @_;
	my $goodSave = 0;
	my $tryCount = 0;
	my $maxTries = 5;

	# Delay saving if we are not initialized yet.
	if (!defined($MonitorFilePath) || $MonitorFilePath eq '')
		{
		push @MessageCache, $msg;
		return;
		}

	my $numCachedMessages = @MessageCache;
	if ($numCachedMessages)
		{
		my $oneBigMessage = join("", @MessageCache);
		while (!$goodSave && ++$tryCount <= $maxTries)
			{
			$goodSave = AppendToTextFileWide($MonitorFilePath, $oneBigMessage);
			if (!$goodSave)
				{
				usleep(100000);    # 0.1 seconds
				}
			}

		if ($goodSave)
			{
			# Reset for the while loop just below and clear messages.
			$goodSave     = 0;
			$tryCount     = 0;
			@MessageCache = ();
			}
		else    # There is no good reason to end up here, except a bad $MonitorFilePath.
			{
			return;
			}
		}

	while (!$goodSave && ++$tryCount <= $maxTries)
		{
		$goodSave = AppendToTextFileWide($MonitorFilePath, $msg);
		if (!$goodSave)
			{
			usleep(100000);    # 0.1 seconds
			}
		}

	if ($OkToSend && defined($CallbackNotify) && $goodSave)
		{
		# Send only to "MON" subscribers, ie "Mon" web pages.
		my $msg = "PUBLISH__TS_MONITOR_TE_" . $WebsocketsMessage;
		# Ooops $WebsocketsMessage = "PUBLISH__TS_MONITOR_TE_" . $WebsocketsMessage;
		$CallbackNotify->($msg);
		}
}

use ExportAbove;
1;

