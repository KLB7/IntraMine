# intramine_mon.pl: monitor (display) output from IntraMine that would
# otherwise go to a console window. This is being done in part because
# sometimes a "\n" sent from IntraMine to the console is
# interpreted as "♪◙" and not a newline.
#
# Main or some service calls Monitor($msg)
# which writes $msg to a temp file and sends a WebSockets
# message out, picked up by mon.js which asks this program
# for the LatestMessages() and displays them.
# See also mon.pm.

use strict;
use warnings;
use Win32;
use File::ReadBackwards;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use win_wide_filepaths;
use swarmserver;

binmode(STDOUT, ":encoding(UTF-8)");
Win32::SetConsoleCP(65001);

$|  = 1;

my $PAGENAME = '';
my $SHORTNAME = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

my $kLOGMESSAGES = 0;			# 1 == Log Output() messages, and print to console window
my $kDISPLAYMESSAGES = 0;		# 1 == just print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print. See swarmserver.pm#Output().
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);
Output("Starting $SHORTNAME on port $port_listen\n\n");

my $CmdOutputPath;
my $LogDir = FullDirectoryPath('LogDir');
my $monitorFileName = CVal('INTRAMINE_MAIN_LOG');
if ($monitorFileName eq '')
	{
	$monitorFileName = 'IM_LOG.txt';
	}
InitCommandMonitoring($LogDir . $monitorFileName);

my %RequestAction;
# Respond with the Mon page, where #theTextWithoutJumpList will show messages
# generated in Main and all swarmserver.pm-based services with Monitor($msg).
# (Include mon.js for message sending.)
$RequestAction{'req|main'} = \&OurPage; 			# req=main
# Return latest messages from the main log file.
$RequestAction{'req|monitor'} = \&LatestMessages; 	# req=monitor

MainLoop(\%RequestAction);

# The Mon page. Basically top nav bar, text placeholder,
# and some JavaScript (especially mon.js).
sub OurPage {
	my ($obj, $formH, $peeraddress) = @_;

	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>Mon</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="forms.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
<link rel="stylesheet" type="text/css" href="mon.css" />
</head>
<body>
_TOPNAV_
_DESCRIPTION_
<div id="runmessage">&nbsp;</div>
<div id="cmdcontainer">
</div>
<div id='cmdOutputTitle'>&nbsp;</div>
<div id='scrollAdjustedHeight'>
	<div id='theTextWithoutJumpList'>
	</div>
</div>
<script>
let thePort = '_THEPORT_';
let weAreRemote = _WEAREREMOTE_;
let runMessageDiv = 'runmessage';
let commandContainerDiv = 'cmdcontainer';
let commandOutputDiv = 'theTextWithoutJumpList';
let cmdOutputContainerDiv = 'scrollAdjustedHeight';
let errorID = "runMessageDiv";
</script>
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="restart.js"></script>
<script src="topnav.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
<script src="tooltip.js"></script>
<script src="mon.js"></script>
</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);		# The top navigation bar, with our page name highlighted
	$theBody =~ s!_TOPNAV_!$topNav!;

	my $description ="<h2>IntraMine Monitor</h2>";
	$theBody =~ s!_DESCRIPTION_!$description!;

	# $peeraddress eq '127.0.0.1' determines whether we are local.
	# The IPv4 Address for this server (eg 192.168.0.14);
	my $serverAddr = ServerAddress();

	my $clientIsRemote = 0;
	# If client is on the server then peeraddress can be either 127.0.0.1 or $serverAddr:
	# if client is NOT on the server then peeraddress is not 127.0.0.1 and differs from $serverAddr.
	if ($peeraddress ne '127.0.0.1' && $peeraddress ne $serverAddr)	#if ($peeraddress ne $serverAddr)
	#if ($peeraddress ne '127.0.0.1')
		{
		$clientIsRemote = 1;
		}
	
	my $amRemoteValue = $clientIsRemote ? 'true' : 'false';
	my $port = $port_listen;

	$theBody =~ s!_WEAREREMOTE_!$amRemoteValue!;

	$theBody =~ s!_THEPORT_!$port!;

	# Put in main IP, main port (def. 81), and our Short name (Reindex) for JavaScript.
	# These are needed in intramine_config.js for example
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()
	
	return($theBody);
	}

sub InitCommandMonitoring {
	my ($cmdOutputPath) = @_;
	$CmdOutputPath = $cmdOutputPath;
	}

sub CommandFilePath {
	return($CmdOutputPath);
	}

# Called by mon.js in response to a WebSockets notification that
# a new message is available.
# Return messages after file position 'filepos' together with
# updated file position. See mon.pm#Monitor() for saving the message.
sub LatestMessages {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = ''; # NOTE there must be some result, else an error 404 is triggered.

	my $cmdFilePath = CommandFilePath();
	my $lastFilePosition = 0;
	if (defined($formH->{'filepos'}))
		{
		$lastFilePosition = $formH->{'filepos'};
		}

	if (-f $cmdFilePath)
		{
		my $bw = File::ReadBackwards->new($cmdFilePath) or
			return("***E-R-R-O-R***Could not open '$cmdFilePath'!");
		my $line = '';
		my $newFilePosition = $bw->tell;
		
		my @lines;
		my $currentFilePosition = $newFilePosition;
		while ($currentFilePosition > $lastFilePosition && defined($line = $bw->readline))
			{
			chomp($line);
			unshift @lines, $line;
			$currentFilePosition = $bw->tell;
			}
		$bw->close();
		
		my $numLines = @lines;
		if ($numLines > 0)
			{
			$lastFilePosition = $newFilePosition;
			my $breaker = "<br>";
			for (my $i = 0; $i < @lines; ++$i)
				{
				if ($lines[$i] eq '<pre>')
					{
					$breaker = '';
					}
				elsif ($lines[$i] eq '</pre>')
					{
					$breaker = "<br>";
					}
				$result .= $lines[$i] . "$breaker\n";
				}
			}
		}
	# else no log file, no big deal, perhaps we're still starting up.
	$result = "|$lastFilePosition|" . $result;

	return($result);
	}
