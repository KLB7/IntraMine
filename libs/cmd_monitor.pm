# cmd_monitor.pm: run a monitor a process, typically
# a cmd.exe. Save output to a text file and report when
# asked to a web page, to show feedback.

package cmd_monitor;
require Exporter;
use Exporter qw(import);

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
			$argInputs = "&nbsp;&nbsp;<input name='Arg${commandNumber}_$argNumber' value='$value' size='8' style='margin-top: 8px;'>";
			}
		else
			{
			$argInputs .= "&nbsp;<input name='Arg${commandNumber}_$argNumber' value='$value' size='8' style='margin-top: 8px;'>";
			}
		++$idx;
		++$argNumber;
		}
	
	# Put args in a separate cell.
	if ($argInputs eq "")
		{
		$argInputs = "&nbsp;";
		}
	$argInputs = "</td><td>$argInputs</td>";

	my $rdm = random_int_between(1, 65000);
	my $rdmStr = "rddm=$rdm";
	my $cmdHtmlStart = "<tr><td><div class='cmdItem'>";
	my $cmdHtmlEnd = '</tr>';
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
	my $cmdString = $cmdHtmlStart . "<a href='$cmdPath?$rdmStr$willRestartStr$monitorStr' class='plainhintanchor' $onClick $onmouseOver id='Cmd$commandNumber'>$displayedName</a></div>" .$argInputs . $cmdHtmlEnd . "\n";

	++$commandNumber;

	return($cmdString);	
	}

# Like above, but a button instead of table row, and extra arguments are not supported.
# Instead, pass an id as the last argument.
sub OneCommandButton {
	my @passedIn = @_;
	my $idx = 0;
	my $cmdPath = $passedIn[$idx++];
	my $displayedName = $passedIn[$idx++];
	my $willRestart = $passedIn[$idx++];
	my $monitorUntilDone = $passedIn[$idx++];
	my $id = $passedIn[$idx++];

	my $rdm = random_int_between(1, 65000);
	my $rdmStr = "rddm=$rdm";
	my $willRestartStr = ($willRestart) ? '&willrestart=1' : '';
	my $monitorStr = ($monitorUntilDone && !$willRestart) ? '&monitor=1' : '';
	my $onClick = "onclick='runTheCommand(this); return false;'";
	my $tipStr = $cmdPath;
	$tipStr =~ s!\"([^"]*?)\"!&ldquo;$1&rdquo;!g;
	$tipStr =~ s!\"!&ldquo;!g;
	$tipStr =~ s!\<!&lt;!g;
	$tipStr =~ s!\>!&gt;!g;
	$tipStr =~ s!\\!\\\\!g;
	# nope $tipStr = &HTML::Entities::decode($tipStr);
	$tipStr = "<p>$tipStr</p>";
	my $onmouseOver = "onmouseOver='showhint(\"$tipStr\", this, event, \"500px\", false)'";
	my $button = "<input id=\"$id\" class=\"submit-button\" type=\"submit\" value=\"$displayedName\" />";
	my $cmdString = "<a href='$cmdPath?$rdmStr$willRestartStr$monitorStr' class='plainhintanchor' $onClick $onmouseOver id='Cmd$commandNumber'>$button</a>" . "\n";

	++$commandNumber;

	return($cmdString);	

	}
} ##### Command Strings

# onclick='runTheCommand(this);... See cmdServer.js#runTheCommand() which uses Ajax to
# call back with argument "req=open",
# which calls RunTheCommand() in the calling script, and which in turn calls
# this sub to run the actual command.
sub _RunTheCommand {
	my ($obj, $formH, $peeraddress, $ignoreProc) = @_;
	$ignoreProc ||= 0;
	SetIgnoreProc($ignoreProc);

	my $status = 'OK';
	
	my $filepath = defined($formH->{'file'})? $formH->{'file'}: '';
	$filepath =~ s!\\!/!g;

	# $ENV{COMSPEC} is typically %SystemRoot%\system32\cmd.exe
	# $Proc->GetExitCode($exitcode) will return STILL_ACTIVE if the process is still running.
	
	my $proc;
	if (defined($formH->{'monitor'}))
		{
		my $cmdFilePath = CommandFilePath();
		unlink($cmdFilePath);

		# If $ignoreProc, the running program will write directly to $cmdFilePath.
		if ($ignoreProc)
			{
			Win32::Process::Create($proc, $ENV{COMSPEC}, "/c $filepath", 0, 0, ".")
				|| ($status = Win32::FormatMessage( Win32::GetLastError() ));
			}
		else
			{
			Win32::Process::Create($proc, $ENV{COMSPEC}, "/c $filepath 1> $cmdFilePath 2>&1", 0, 0, ".")
				|| ($status = Win32::FormatMessage( Win32::GetLastError() ));
			}
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
my $IgnoreProc;
my $FilePosition;
my $FileMissingCheckCount;

sub InitCommandMonitoring {
	my ($cmdOutputPath, $suffix) = @_;
	$CmdOutputPath = $cmdOutputPath . '_' . $suffix . '.txt';
	$Proc = undef;
	}

sub SetIgnoreProc {
	my ($ignoreProc) = @_;
	$IgnoreProc = $ignoreProc;
	}

sub ShouldIgnoreProc {
	return($IgnoreProc);
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
# We trust the JavaScript fetch() monitoring function will call this at reasonable
# intervals, at most once per second. This is called in response to 'req=monitor', which
# in turn is triggered by cmdServer.js#runTheCommand() 'req=open&monitor=1'.
sub CommandOutput {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = ''; # NOTE there must be some result, else an error 404 is triggered.

	if (!ShouldIgnoreProc())
		{
		my $proc = GetProc();
		if (!defined($proc))
			{
			return('***A-L-L***D-O-N-E***');
			}

		my $exitcode = 1;
		$proc->GetExitCode($exitcode);
		if ($exitcode == STILL_ACTIVE)
			{
			; # business as usual
			}
		else
			{
			ClearProc();
			}
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
			$result = "***E-R-R-O-R***'$cmdFilePath' cannot be found after waiting five minutes!\n";
			$result .= "***A-L-L***D-O-N-E***";
			}
		}

	return($result);
	}
} ##### Monitor Command Output

use ExportAbove;

# Borrowed from common.pm (sorry, didn't want to include the whole module).
sub random_int_between {
	my($min, $max) = @_;
	# Assumes that the two arguments are integers!
	return $min if $min == $max;
	($min, $max) = ($max, $min)  if  $min > $max;
	return $min + int rand(1 + $max - $min);
	}

return 1;