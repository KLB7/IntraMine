# intramine_commandserver.pl: run specific programs.
# Typically these are .bat files and Perl programs, but anything goes.
# Each "command" can have variable input fields.
# Any stdout/stderr from the program being run is captured here
# and displayed on the web page, if wanted:
#  for that, pass $monitorUntilDone = 1 in calls to
# OneCommandString($cmdPath, $displayedName, $willRestart, $monitorUntilDone , $optionalArg(s)).
# If monitoring, for more responsive results put
#   select((select(STDOUT), $|=1)[0]);
# at the top of your Perl program, to unbuffer stdout: then output on the web page will be updated
# regularly. Otherwise, the output might buffer up until the Perl
# program is finished, then dump out all at once. Which can be disappointing.
# For Perl programs, print statements will be redirected to the Cmd page more reliably if you
# call the program via a bat file - see extract_method.bat in Commands() below.
# Commands are set in Commands() below.
#
# Having said all that, this is probably
##############################################
# THE MOST DANGEROUS SERVER EVER.
##############################################
# There are no restrictions on access here, so anyone who can get at this Cmd server can run
# any program they want on the IntraMine box. This server is suitable for running
# *only* on an intranet with adequate security, with access given only to people you trust.
#
# This server is disabled by default. To run it, uncomment the line
#1	Cmd					Cmd			intramine_commandserver.pl	PERSISTENT
# in data/serverlist.txt

# perl C:\perlprogs\mine\intramine_commandserver.pl 81 43130

use strict;
use warnings;
use utf8;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;
use cmd_monitor;

$|  = 1;

my $PAGENAME = '';
my $SHORTNAME = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

my $kLOGMESSAGES = 0;			# 1 == Log Output() messages
my $kDISPLAYMESSAGES = 0;		# 1 == print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print.
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);
Output("Starting $SHORTNAME on port $port_listen\n\n");

my $LogDir = FullDirectoryPath('LogDir');
InitCommandMonitoring($LogDir . 'temp/tempout', $port_listen);

# Requests come from browsers, and from JavaScript for this page in response to user actions.
my %RequestAction;
$RequestAction{'req|main'} = \&CommandPage; 			# req=main
$RequestAction{'req|css'} = \&GetRequestedFile; 		# req=css
$RequestAction{'req|js'} = \&GetRequestedFile; 			# req=js
$RequestAction{'req|content'} = \&Commands; 			# req=content, cmdServer.js#loadPageContent()
$RequestAction{'req|open'} = \&RunTheCommand; 			# req=open
$RequestAction{'req|ping'} = \&MainServerResponse; 		# req=ping
$RequestAction{'req|monitor'} = \&CommandOutput; 		# req=monitor
#$RequestAction{'req|id'} = \&Identify; 				# req=id

# Over to swarmserver.pm.
MainLoop(\%RequestAction);

################# subs
# Show the Cmd page, in response to a request such as http://192.168.1.132:43136/Cmd
# This page provides honking huge buttons to exec commands, as specified below
# in Commands(). The lower part of the page will show any output from the commands.
sub CommandPage {
	my ($obj, $formH, $peeraddress) = @_;

	my $theBody = <<'FINIS';
<!doctype html>
<html>
<head>
<title>Commands</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="cmd.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
<script type="text/javascript">
</script>
</head>
<body>
  _TOPNAV_
    <div id="runmessage">&nbsp;</div>
    <!--Div that will hold the commands-->
    <div id="cmdcontainer">
    <p>Loading...</p>
    </div>
    <div id='cmdOutputTitle'>&nbsp;</div>
    <div id='scrollAdjustedHeight'>
    	<div id='theTextWithoutJumpList'>
    	&nbsp;
    	</div>
    </div>
<script>
let weAreRemote = _WEAREREMOTE_;
let thePort = '_THEPORT_';
let runMessageDiv = 'runmessage';
let commandContainerDiv = 'cmdcontainer';
let commandOutputDiv = 'theTextWithoutJumpList';
let cmdOutputContainerDiv = 'scrollAdjustedHeight';
</script>
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
<script src="cmd_monitor_WS.js"></script>
<script src="tooltip.js"></script>
<script src="cmd_monitor.js"></script>
<script src="cmdServer.js"></script>
</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);
	$theBody =~ s!_TOPNAV_!$topNav!;

	my $serverAddr = ServerAddress();
	my $host = $serverAddr;
	my $port = $port_listen;
	my $clientIsRemote = 0;
	# If client is on the server then peeraddress can be either 127.0.0.1 or $serverAddr:
	# if client is NOT on the server then peeraddress is not 127.0.0.1 and differs from $serverAddr.
	if ($peeraddress ne '127.0.0.1' && $peeraddress ne $serverAddr)
		{
		$clientIsRemote = 1;
		}
	my $amRemoteValue = $clientIsRemote ? 'true' : 'false';
	$theBody =~ s!_WEAREREMOTE_!$amRemoteValue!;
	$theBody =~ s!_THEPORT_!$port!;
	
	# Put in main IP, main port, our short name for JavaScript.
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()

	return $theBody;	
	}

# Fill in the commands shown on the page. Called by cmdServer.js#loadPageContent() to fill in
# <div id="cmdcontainer">.
sub Commands {
	my ($obj, $formH, $peeraddress) = @_;

	my $theBody = <<'FINIS';
	<table id='cmdTable'>
	_COMMANDS_
	</table>
FINIS

	InitCommandStrings();

	# Handy for Perl progs in the IntraMine folder, and batch files etc in the bat/ subfolder.
	# But your program can be anywhere, just set the path to it as first argument to OneCommandString().
	# BaseDirectory() is the directory holding this program: it's the folder holding
	# Perl Intramine programs (including this one).
	# That's enough to call Perl programs. Batch files typically call Perl programs internally,
	# and they also need to know the BaseDirectory(), but they can figure it out for themselves,
	# assuming that the Perl progs are one level up from their own /bats/ folder.
	# For example, echo1.bat is in .../mine/bats/, and looks for the echo1.pl script one level
	# up in .../mine/.
	# A "known" program such as Microsoft Word can be started with "start programName"
	# as the path, see eg "start winword" below.
	
	my $serverDirectory = BaseDirectory(); # intramine_config.pm#BaseDirectory()
	
	#
	# OneCommandString params:
	# OneCommandString(path, tooltip, IntraMine will restart (0/1), display stdout from program (0/1), optionalArg(s))
	#
	my $cmdLs = '';
	$cmdLs .= OneCommandString($serverDirectory . 'bats/echo1.bat hello there', 'Batch say hello there', 0, 1);
	$cmdLs .= OneCommandString($serverDirectory . 'bats/echo1.bat', 'Batch say args', 0, 1, "arg_one", "\"this is arg_two\"", "and_three");
	$cmdLs .= OneCommandString('perl ' . $serverDirectory . 'echo1.pl hi you', 'Perl say hi you', 0, 1);
	$cmdLs .= OneCommandString('perl ' . $serverDirectory . 'test_programs/test_backwards_tell.pl', 'Test ReadBackwards tell()', 0, 1);
	
	# An example of calling an exe without monitoring (last two args to OneCommandString are 0,0),
	# made available **only** on the PC where Intramine is running.
	# Last two args to OneCommandString are 0,0 meaning no restart, no monitoring.
	my $serverAddr = ServerAddress();
	my $clientIsRemote = 0;
	# If client is on the server then peeraddress can be either 127.0.0.1 or $serverAddr:
	# if client is NOT on the server then peeraddress is not 127.0.0.1 and differs from $serverAddr.
	if ($peeraddress ne '127.0.0.1' && $peeraddress ne $serverAddr)
		{
		$clientIsRemote = 1;
		}

	# This works only if Word is installed, needless to say:)
	if (!$clientIsRemote)
		{
		$cmdLs .= OneCommandString('start winword', 'Start Microsoft Word (Locally Only)', 0, 0);
		}
	
	# "Extract method": copy some Perl, run this, Paste into an editor for the method and call.
	# Deleted, since Tk is not longer installed by default.
	#$cmdLs .= OneCommandString($serverDirectory . 'bats/extract_method.bat', 'Extract Perl Method (Copy code, run this and Ok resulting dialog, Paste)', 0, 1);	

	# Open data/search_directories.txt (in the IntraMine folder) using default text editor.
	# This will only work on the IntraMine machine.
	if (!$clientIsRemote)
		{
		$cmdLs .= OneCommandString($serverDirectory . "data/search_directories.txt", 'Open data/search_directories (Locally Only)', 0, 0);
		}
		
	# Other commands:
	###$cmdLs .= OneCommandString($serverDirectory . 'bats/backup.bat', 'Back up files', 0, 1);
	###$cmdLs .= OneCommandString($serverDirectory . 'bats/backup.bat list', 'List backup folders', 0, 1);
	###$cmdLs .= OneCommandString($serverDirectory . 'bats/intramain_stopstarttest.bat', 'Restart IntraMine', 1, 0);
	# An example of starting an exe on the server without monitoring, in this case
	# available to everyone.
	# Last two args to OneCommandString are 0,0 meaning no restart, no monitoring.
	###$cmdLs .= OneCommandString('start winword', 'Start Microsoft Word From Anywhere', 0, 0);

	$theBody =~ s!_COMMANDS_!$cmdLs!;
	return($theBody);
	}

sub RunTheCommand {
	my ($obj, $formH, $peeraddress) = @_;

	# Make the Status light flash for this server.
	# Not needed, see cmd_monitor.js#runTheCommand.
	#ReportActivity($SHORTNAME);

	my $status = _RunTheCommand($obj, $formH, $peeraddress);
	return($status);
	}

