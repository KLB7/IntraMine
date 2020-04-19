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
use File::ReadBackwards;
use IO::Socket;
use IO::Socket::Timeout;
use IO::Select;
use Win32::Process;
# To grab output from command being run and show it in main page.
use Win32::Process 'STILL_ACTIVE';
use HTML::Entities;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;

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
InitCommandMonitoring($LogDir . 'temp/tempout');

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
<script src="tooltip.js"></script>
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
	_COMMANDS_
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
	$cmdLs .= OneCommandString('perl ' . $serverDirectory . 'test/test_backwards_tell.pl', 'Test ReadBackwards tell()', 0, 1);
	
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
	if (!$clientIsRemote)
		{
		$cmdLs .= OneCommandString('start winword', 'Start Microsoft Word Locally Only', 0, 0);
		}
	
	# "Extract method": copy some Perl, run this, Paste into an editor for the method and call.
	$cmdLs .= OneCommandString($serverDirectory . 'bats/extract_method.bat', 'Extract Perl Method (Copy code, run this and Ok resulting dialog, Paste)', 0, 1);	
		
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

{ ##### Command Strings
my $commandNumber;

sub InitCommandStrings {
	$commandNumber = 1;
}

# OneCommandString($cmdPath, $displayedName, $willRestart, $monitorUntilDone , $optionalArg(s))
# If $cmdPath starts with a file path, we get href='file:///...'
# but for $cmdPath starting with eg 'perl C:/perlprogs.../ we get href='http://serveraddr:port/...'
# so cmdServer.js#runTheCommand() needs to look for both of those at the
# start of the href. We get either href='http://localhost:81/'
# or href='http://192.168.0.14:81/' (where 192.168.0.14 is the server IP)
# if accessing the Cmd page from the server. Remote access always has the numeric main
# server address (eg 192.168.0.14 when accessed from 192.168.0.15).
# Anyway...
# if $willRestart then 'willrestart=1' is added to url. 'willrestart' triggers pinging of main
# server until it is back up, but does not redirect the command's output.
# if $monitorUntilDone then 'monitor=1' is added to url, UNLESS $willRestart.
# 'monitor' redirects command's output to a file, which is periodically reported in the
# id='theTextWithoutJumpList' div that follows the commands (see cmdServer.js#monitorCmdOutUntilDone()).
# To run something and not monitor it set, $willRestart and $monitorUntilDone to 0, eg
#	$cmdLs .= OneCommandString('start winword', 'Start Microsoft Word From Anywhere', 0, 0);
sub OneCommandString {
	my @passedIn = @_;
	my $idx = 0;
	my $cmdPath = $passedIn[$idx++];
	my $displayedName = $passedIn[$idx++];
	my $willRestart = $passedIn[$idx++];
	my $monitorUntilDone = $passedIn[$idx++];
	
	# Any additional params are treated as inputs for additional arguments to the command
	# being executed,  with supplied param value as the default input field value.
	# For a blank input field, pass in "". Argument values with spaces should be "put in quotes"
	# that are passed along to the command line.
	my $argInputs = '';
	my $argNumber = 1;
	while (defined($passedIn[$idx]))
		{
		my $value = $passedIn[$idx];
		if ($argNumber == 1)
			{
			$argInputs = "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<input name='Arg${commandNumber}_$argNumber' value='$value' size='8' style='margin-top: 8px;'>";
			}
		else
			{
			$argInputs .= "&nbsp;<input name='Arg${commandNumber}_$argNumber' value='$value' size='8' style='margin-top: 8px;'>";
			}
		++$idx;
		++$argNumber;
		}
	
	my $rdm = random_int_between(1, 65000);
	my $rdmStr = "rddm=$rdm";
	my $cmdHtmlStart = "<div class='cmdItem'>";
	my $cmdHtmlEnd = '</div>';
	my $willRestartStr = ($willRestart) ? '&willrestart=1' : '';
	my $monitorStr = ($monitorUntilDone && !$willRestart) ? '&monitor=1' : '';
	my $onClick = "onclick='runTheCommand(this); return false;'";
	# onmouseOver=\"showhint('$tipStr', this, event, '250px')\"
	#my $tipStr = '<p>' . &HTML::Entities::encode($cmdPath) . '</p>';
	my $tipStr = $cmdPath;
	$tipStr =~ s!\"([^"]*?)\"!&ldquo;$1&rdquo;!g;
	$tipStr =~ s!\"!&ldquo;!g;
	$tipStr =~ s!\<!&lt;!g;
	$tipStr =~ s!\>!&gt;!g;
	$tipStr =~ s!\\!\\\\!g;
	# nope $tipStr = &HTML::Entities::decode($tipStr);
	$tipStr = "<p>$tipStr</p>";
	my $onmouseOver = "onmouseOver='showhint(\"$tipStr\", this, event, \"500px\", false)'";
	my $cmdString = $cmdHtmlStart . "<a href='$cmdPath?$rdmStr$willRestartStr$monitorStr' class='plainhintanchor'  $onClick $onmouseOver id='Cmd$commandNumber'>$displayedName</a>" .$argInputs . $cmdHtmlEnd . "\n";

	++$commandNumber;
	return($cmdString);	
	}
} ##### Command Strings

# onclick='runTheCommand(this);... See cmdServer.js#runTheCommand() which uses Ajax to
# call back here with argument "req=open", which is tied to this sub - see %RequestAction above.
sub RunTheCommand {
	my ($obj, $formH, $peeraddress) = @_;
	my $status = 'OK';
	
	my $filepath = defined($formH->{'file'})? $formH->{'file'}: '';
	$filepath =~ s!\\!/!g;
	Output("Starting |$filepath|\n");

	# $ENV{COMSPEC} is typically %SystemRoot%\system32\cmd.exe
	# $Proc->GetExitCode($exitcode) will return STILL_ACTIVE if the process is still running.
	
	my $proc;
	if (defined($formH->{'monitor'}))
		{
		my $cmdFilePath = CommandFilePath();
		unlink($cmdFilePath);
		Win32::Process::Create($proc, $ENV{COMSPEC}, "/c $filepath 1> $cmdFilePath 2>&1", 0, 0, ".")
			|| ($status = Win32::FormatMessage( Win32::GetLastError() ));
		StartMonitoringCmdOutput($proc);
		}
	else # will restart, or monitoring not wanted
		{
		Win32::Process::Create($proc, $ENV{COMSPEC}, "/c $filepath", 0, 0, ".")
			|| ($status = Win32::FormatMessage( Win32::GetLastError() ));
		SetProc($proc);
		}

	# If restarting, we will wait for main server to return - see MainServerResponse() just below.
	if (defined($formH->{'willrestart'}))
		{
		print("NOTE RunTheCommand() has detected restart request...\n");
		}
		
	return($status); # meaningless, but required
	}

# 'Ping' main server with req=ruthere until it comes back to life.
# Currently no errors, all responses from here start with 'OK'.
# cmdServer.js#monitorUntilRestart() is looking for "OK restarted"
# to stop calling this repeatedly.
sub MainServerResponse {
	my ($obj, $formH, $peeraddress) = @_;
	my $srverPort = MainServerPort();
	my $srvrAddr = ServerAddress();
	print("   Pinging $srvrAddr:$srverPort\n");
	
	my $remote = IO::Socket::INET->new(
	                Proto   => 'tcp',       			# protocol
	                PeerAddr=> "$srvrAddr", 			# Address of server
	                PeerPort=> "$srverPort",      		# port of server (eg 81)
	                ) or (return("OK main server did not respond"));
	
	IO::Socket::Timeout->enable_timeouts_on($remote);
	# setup the timeouts
	$remote->read_timeout(1.0); # was 5.0
	$remote->write_timeout(1.0); # was 5.0
	
	print $remote "GET /?req=ruthere HTTP/1.1\n\n";
	my $line = <$remote>;
	chomp($line) if (defined($line));
	close $remote;
	my $restarted = (defined($line) && length($line) > 0);
	my $result = $restarted ? "OK restarted" : "OK connection but no response from $srvrAddr:$srverPort";
	print("MainServerResponse received: |$result|\n");
	return($result);
	}

{ ##### Monitor Command Output
my $CmdOutputPath;
my $Proc;
my $FilePosition;
my $FileMissingCheckCount;

sub InitCommandMonitoring {
	my ($cmdOutputPath) = @_;
	my $port = $port_listen; # TOO SOON OurListeningPort();
	$CmdOutputPath = $cmdOutputPath . '_' . $port . '.txt';
	$Proc = undef;
	}

sub StartMonitoringCmdOutput {
	my ($proc) = @_;
	SetProc($proc);
	$FilePosition = 0;
	$FileMissingCheckCount = 0;
	}

sub SetProc {
	my ($proc) = @_;
	$Proc = $proc;
	}

sub GetProc {
	return($Proc);
	}

sub ClearProc {
	$Proc = undef;
	}

sub CommandFilePath {
	return($CmdOutputPath);
	}

# Return lines from cmd file output,
# Or '***N-O-T-H-I-N-G***N-E-W***' if nothing new since last check.
# When $proc is done, do one last read and clear $proc: then on the next
# read request, return '***A-L-L***D-O-N-E***'.
# If there's a problem, return "***E-R-R-O-R***$errorDescription".
# We trust the JavaScript xmlhttprequest monitoring function will call this at reasonable
# intervals, at most once per second. This is called in response to 'req=monitor', which
# in turn is triggered by cmdServer.js#runTheCommand() 'req=open&monitor=1'.
sub CommandOutput {
	my ($obj, $formH, $peeraddress) = @_;
	my $proc = GetProc();
	if (!defined($proc))
		{
		return('***A-L-L***D-O-N-E***');
		}

	my $result = ''; # NOTE there must be some result, else an error 404 is triggered.
	my $exitcode = 1;
	$proc->GetExitCode($exitcode);
	if ( $exitcode == STILL_ACTIVE )
		{
		; # business as usual
		}
	else
		{
		ClearProc();
		}
	
	# Read, even if not still active, to pick up all lines.
	my $cmdFilePath = CommandFilePath();
	if (-f $cmdFilePath)
		{
		my $bw = File::ReadBackwards->new($cmdFilePath) or
			return("***E-R-R-O-R***Could not open '$cmdFilePath'!");
		my $line = '';
		my $newFilePosition = $bw->tell;
		
		my @lines;
		my $currentFilePosition = $newFilePosition;
		while ($currentFilePosition > $FilePosition && defined($line = $bw->readline))
			{
			chomp($line);
			unshift @lines, $line;
			$currentFilePosition = $bw->tell;
			}
		$bw->close();
		
		my $numLines = @lines;
		if ($numLines > 0)
			{
			$FilePosition = $newFilePosition;
			$result = join("<br>\n", @lines) . "<br>\n";
			}
		else
			{
			$result = '***N-O-T-H-I-N-G***N-E-W***';
			}
		}
	else
		{
		++$FileMissingCheckCount;
		if ($FileMissingCheckCount <= 300)
			{
			$result = '***N-O-T-H-I-N-G***N-E-W***';
			}
		else
			{
			ClearProc();
			$result = "***E-R-R-O-R***'$cmdFilePath' cannot be found after waiting five minutes!";
			}
		}
	}
} ##### Monitor Command Output
