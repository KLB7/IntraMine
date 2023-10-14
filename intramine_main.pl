# intramine_main.pl: a round-robin request redirector, creating and using
# a "server swarm" of Perl services in separate processes to do the heavy lifting.
# The server swarm is started here, and stopped on exit, and responds well to an EXIT request.
# Page names and Perl program names for the pages are listed in 
# /data/serverlist.txt,
# which is also used in swarmserver.pm to create the top navigation for our site.
# If the "Count" field for a server is greater than one, Count instances of the server will
# be created here running on different ports, and requests will be cycled through the running
# instances.
#
# A note on how requests are handled (this server is called "main" below, and the Search
# server (which shows a Search dialog and shows search results) is used as an example server).
# Request are matched up with servers based on the unique "Short name" of the
# server as listed in the third field for it in data/serverlist.txt, so if main here receives
# a request such as
# http://192.168.1.132:81/Search
# the request will be redirected to a running Search server, such as
# http://192.168.1.132:43128/Search
# This main server is *not* a two-way conduit for results, and communicates back to clients only with
# redirects in response to a page request. If a user issues a request such as "...:81/Search"
# just above to main running on port 81, then the request will be redirected to a running
# Search server, on port 43128 say, and "...:43128/Search" will show up in the user's
# browser address bar. A typical round robin server might send a request to the Search server,
# insist on receiving back the full response itself, and forward the results to the client, so
# the user would always see a single port number in the address bar (more typically the port
# isn't even shown, but remains constant).
# Anyway, this main server is typically under very light load, and just redirects to other servers
# that do the real work. The one drawback of this approach is that the user will see a
# variable port number, and any bookmarks made will contain that potentially variable port
# number. Hoops are jumped through to try to ensure that any wrong port numbers in bookmarks
# are automatically fixed with a redirect when detected. Specifically, any swarm server that
# receives a request for a different Short name will ask Main to redirect it if possible,
# and Main monitors a few ports above the ones currently in use in case one of those higher
# port numbers was ever involved in a favorite/bookmark.
#
# This server isn't quite a "dumb pipe" since it participates in the handling of signals
# (see BroadcastSignal() below).
# And it also helps coordinate planned maintenance outages, as happens for example when a
# Linker server decides it needs to go away for a couple of minutes to rebuild its in-memory
# hash of file names and folder paths in response to a folder rename: when such a signal is
# received, this server will instruct all running Linker servers to carry out the maintenance
# one at a time, so at least one Linker will be available at all times.
# To see that Linker maintenance example in detail, look for
# "MAINTENANCE_SERVER_EVENTS" in data/intramine_config.txt, and "folderrenamed"
# below and in intramine_linker.pl
#
# A note on port numbers.
# This program needs two port numbers from data/intramine_config.
# The first is 'INTRAMINE_MAIN_PORT', the port to use for
# this main service. And the second is 'INTRAMINE_FIRST_SWARM_SERVER_PORT', the first port number
# to use for the other services that are started here (the "server swarm"), in accordance with
# the listings in serverlist.txt.
# The default for main service port is 81, but if that's busy you could use 8080 or 8081.
# There can be many swarm servers, and they will use consecutive port numbers starting with
# one above the port number supplied. The default 43124 is probably safe for you. To look for
# a free range of ports you can try running "netstat -ab" at the command prompt as Admin.
# (See https://www.howtogeek.com/howto/28609/how-can-i-tell-what-is-listening-on-a-tcpip-port-in-windows/)
# You should allow for needing about 50 ports, if you can. To minimize the number of ports needed,
# work out how many servers you will actually be running, corresponding to the server and their
# counts in data/serverlist.txt, and adjust the TOTAL_SWARM_PORTS_TO_MONITOR number in
# data/intramine_config.txt to that number plus one (that's not slop, the extra one is needed
# to communicate with other computers if an application is being used for remote editing).
#
# START INTRAMINE
# It's simplest to start up IntraMine by running bats/START_INTRAMINE.bat. There is no need
# to run as administrator.
# STOP INTRAMINE
# Run bats/STOP_INTRAMINE.bat to stop all IntraMine services including this one.
# TEST INTRAMINE
# Put the servers you want to test in data/serverlist_for_testing.txt, set their Count to 1,
# and run
# bats/TEST_INTRAMINE.bat.

# Syntax check (your path is probably different):
# perl -c C:\perlprogs\IntraMine\intramine_main.pl
# Command line (see bats/START_INTRAMINE.bat for a handier way to run):
# perl C:\perlprogs\IntraMine\intramine_main.pl

use strict;
use warnings;
use utf8;
use Carp;
use URI::Escape;
use FileHandle;
use IO::Socket;
use IO::Select;
use Win32::Process 'STILL_ACTIVE';
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use LogFile;	# For logging - log files are closed between writes.
use intramine_config;
use win_wide_filepaths;
use intramine_websockets_client;

# "-t" on the command line means we are testing.
# $TESTING is used in ReceiveInfo() below to start the tests with RunAllTests()
# after all services have loaded.
# $TESTING is also used in StartServerSwarm() to start only the services that want testing,
# as listed in data/serverlist_for_testing.txt.
my $TESTING = shift @ARGV;
$TESTING ||= '';
if ($TESTING eq '-t')
	{
	$TESTING = 1;
	}
else
	{
	$TESTING = 0;
	}

my $SERVERNAME = 'IM_MAIN';

#$|  = 1;

SetCommonOutput(\&Output); # common.pm

# Copy any new config files from /_copy_and_rename_to_data to /data.
CopyNewConfigFiles();

# Load data/intramine_config.txt. See eg $IMAGES_DIR just below.
LoadConfigValues();

my $port_listen = CVal('INTRAMINE_MAIN_PORT'); 									# default 81
# Note first port number is reserved for use by Opener's PowerShell server.
my $kSwarmServerStartingPort = CVal('INTRAMINE_FIRST_SWARM_SERVER_PORT') + 1; 	# default 43124 + 1

my $IGNOREEXITREQUEST = 0;	# This should be 0 for main, to allow a clean restart.
my $kLOGMESSAGES = 0;		# Log Output() messages
my $kDISPLAYMESSAGES = 0;	# Display Output() messages in cmd window

#my $DriveLetter = CVal('DRIVELETTER');
my $IMAGES_DIR = FullDirectoryPath('IMAGES_DIR');
my $CSS_DIR = FullDirectoryPath('CSS_DIR');
my $JS_DIR = FullDirectoryPath('JS_DIR');
my $FONT_DIR = FullDirectoryPath('FONT_DIR');
my $FULL_ACCESS_STR = CVal('FULL_ACCESS_STR');
my $LogDir = FullDirectoryPath('LogDir');

my $StartTimeStamp = NiceToday();

my $logDate = DateTimeForFileName();
my $OutputLog = '';
if ($kLOGMESSAGES)
	{
	my $LogPath = $LogDir . "$SERVERNAME $logDate.txt";
	print("LogPath: |$LogPath|\n");
	MakeDirectoriesForFile($LogPath);
	$OutputLog = LogFile->new($LogPath);
	$OutputLog->Echo($kDISPLAYMESSAGES);
	}

CheckNeededFoldersExist();

Output("Starting $SERVERNAME on port $port_listen, and swarm servers\n\n");

# Special handling for 'PERSISTENT' pages: at present only the 'Cmd' page is marked as
# PERSISTENT in /data/serverlist.txt, meaning it ignores an EXITEXITEXIT request so that it can
# continue to monitor and report when other servers have restarted. For a typical use see
# bats/elastic_stop_except_cmd_rebuild_start.bat, which:
#  - calls intramine_stop.pl to pass an EXITEXITEXIT request to the main server, which is
#     in turn passed on to all swarm servers - the Cmd servers ignore it
#  - calls elastic_indexer.pl to rebuild the Elasticsearch search indexes
#  - and then calls this program, intramine_main.pl, to restart all servers. When this program
#  is starting up it will notice ( AnyCommandServerIsUp() ) if a Cmd page server is still 
#  running: if so, our main program here will postpone starting the Cmd servers until it has
#  started all other swarm servers, and only then stop (with FORCEEXIT) and restart the
#  Cmd page servers, or any other server you've marked as PERSISTENT in serverlist.txt.
# Having said all that, there is really no need to ever use this PERSISTENT notion, you're
# better off just stopping IntraMine completely, so please forgive me this one
# solution without a problem:)
my $CommandServerHasBeenNotified = 0;
my $CommandServersHaveBeenRestarted = 0;

# Some signals will knock out a server while it's doing heavy maintenance. For these, it's
# best to send the signal to the affected servers one by one, so only one server is out of
# commission at a time. Servers and signal names for those affected are listed in
# CVal('MAINTENANCE_SERVER_EVENTS'), see data/intramne_config.txt.
# To avoid confusion, signal names should be globally unique.
# Each affected server should send 'signal=backinservice&sender=SenderShortServerName'
# when the outage due to maintenance is over.
# For an example, search all of IntraMine's main Perl files for "folderrenamed".
LoadMaintenanceSignalsForServers();

# Start up all the swarm servers, based on the list in data/serverlist.txt.
StartServerSwarm($kSwarmServerStartingPort);

my $WebSockIsUp = 0;

# Listen for requests.
MainLoop($port_listen);

################### subs
# Print, to cmd line and log file.
sub Output {
	my ($text) = @_;
	if ($kLOGMESSAGES)
		{
		$OutputLog->Log("MAIN: $text");
		}
	if ($kDISPLAYMESSAGES)
		{
		print("MAIN: $text");
		}
	}

# Not all needed folders are shipped with IntraMine, the logs/ folder in particular is missing.
sub CheckNeededFoldersExist {
	my $logDir = FullDirectoryPath('LogDir');
	my $tempDir = $LogDir . 'temp/';
	if (!MakeAllDirsWide($tempDir))
		{
		print("Error (will continue), could not make |$tempDir|\n");
		}
	}

{ ##### Server short names and associated signal names for heavy maintenance events.
# For tracking temporary server outages due to heavy maintenance, so they can be asked to do
# the maintenance one by one, and not asked to service a request while doing the maintenance.
# Any server doing such maintenance should do a
# RequestBroadcast('signal=backinservice&sender=SenderShortServerName')
# when back in service. Of course, this does nothing if only one instance of the service is running.
my %ServerShortNameForSignal; # $ServerShortNameForSignal{'folderrenamed'} = 'Linker';
# Track server short names under maintenance: cleared when all server instances are done.
my %ServerShortNameIsUnderMaintenance; # $ServerShortNameIsUnderMaintenance{'Linker'} = 1;
my %PortUnderMaintenance; # $PortUnderMaintenance{43124} = 1;
# For stepping through servers under maintenance to send them maintenance signals:
my %MaintenanceIndexForShortServerName; # 0..count = @{$PortsForShortServerNames{$shortName}}

# Note all maintenance signal names, in intramine_config.txt under 'MAINTENANCE_SERVER_EVENTS'.
# The format of the MAINTENANCE_SERVER_EVENTS value string is
# ShortServerName|signalName<spaces>ShortServerName|signalName...
# Eg
# MAINTENANCE_SERVER_EVENTS	Linker|folderrenamed Other|signalName
sub LoadMaintenanceSignalsForServers {
	# Eg MAINTENANCE_SERVER_EVENTS	Linker|folderrenamed<space>OtherServer|signalValue
	my $maintenanceStr = CVal('MAINTENANCE_SERVER_EVENTS');
	
	my @serverSignalsArr = split(/\s+/, $maintenanceStr);
	for (my $i = 0; $i < @serverSignalsArr; ++$i)
		{
		my @serverAndSignal = split(/\|/, $serverSignalsArr[$i]);
		my $numFields = @serverAndSignal;
		if ($numFields == 2)
			{
			$ServerShortNameForSignal{$serverAndSignal[1]} = $serverAndSignal[0];
			}
		}
	}

sub SignalIndicatesMaintenanceOutage {
	my ($signalName) = @_;
	my $result = defined($ServerShortNameForSignal{$signalName}) ? 1 : 0;
	return($result);
	}

sub ShortServerNameForMaintenanceSignal {
	my ($signalName) = @_;
	my $result = defined($ServerShortNameForSignal{$signalName}) ?
						 $ServerShortNameForSignal{$signalName} : '';
	return($result);
	}

sub StartShortServerNameMaintenance {
	my ($shortName) = @_;
	# TEST ONLY
	print("Start of maintenance for $shortName.\n");
	$ServerShortNameIsUnderMaintenance{$shortName} = 1;
	$MaintenanceIndexForShortServerName{$shortName} = -1; # pre-incremented by NextPort... below.
	}

sub EndShortServerNameMaintenance {
	my ($shortName) = @_;
	# TEST ONLY
	print("END of maintenance for $shortName.\n");
	$ServerShortNameIsUnderMaintenance{$shortName} = 0;
	}

sub ShortServerNameIsUndergoingMaintenance {
	my ($shortName) = @_;
	my $result = (defined($ServerShortNameIsUnderMaintenance{$shortName})
					&& $ServerShortNameIsUnderMaintenance{$shortName} == 1);
	return($result);
	}

# Return next port for server short name (eg 'Viewer'), or 0.
# Stopped servers and servers undergoing maintenance are skipped.
sub NextPortForServerUnderMaintenance {
	my ($shortName) = @_;
	my $port = 0;
	my $previousPortUnderMaintenance = 0;
	if (ShortServerNameIsUndergoingMaintenance($shortName))
		{
		if ($MaintenanceIndexForShortServerName{$shortName} >= 0)
			{
			my $prevIndex = $MaintenanceIndexForShortServerName{$shortName};
			$previousPortUnderMaintenance = IndexedPortForShortServerName($shortName, $prevIndex);
			if ($previousPortUnderMaintenance != 0)
				{
				delete($PortUnderMaintenance{$previousPortUnderMaintenance});
				}
			}
		
		my $numPortsTotal = NumServersTotalForShortName($shortName);
		$MaintenanceIndexForShortServerName{$shortName} += 1;
		my $index = $MaintenanceIndexForShortServerName{$shortName};
		if ($numPortsTotal > 1)
			{
			my $previousIndex = $index;
			my $foundNextPort = 0;
			while ($index < $numPortsTotal && !$foundNextPort)
				{
				my $proposedPort = IndexedPortForShortServerName($shortName, $index);
				if (ServerOnPortIsRunning($proposedPort))
					{
					$foundNextPort = 1;
					}
				else
					{
					$MaintenanceIndexForShortServerName{$shortName} += 1;
					$index = $MaintenanceIndexForShortServerName{$shortName};
					}
				}
			if ($foundNextPort)
				{
				$port = IndexedPortForShortServerName($shortName, $index);
				}
			}
		else
			{
			if ($index == 0)
				{
				$port = IndexedPortForShortServerName($shortName, $index);
				}
			}
		}
		
	if ($port == 0)
		{
		EndShortServerNameMaintenance($shortName);
		}
	else
		{
		$PortUnderMaintenance{$port} = 1;
		}
	return($port);
	}

# Call this to avoid sending requests to a server currently doing maintenance.
# Returns index >= 0 if some server associated with $shortName is currently doing
# maintenance, or -1.
sub IndexOfShortServerNameUnderMaintenance {
	my ($shortName) = @_;
	my $result = (ShortServerNameIsUndergoingMaintenance($shortName)) ?
					$MaintenanceIndexForShortServerName{$shortName}: -1;
	return($result);
	}

sub PortIsUnderMaintenance {
	my ($port) = @_;
	my $result = defined($PortUnderMaintenance{$port}) ? 1 : 0;
	return($result);
	}
} ##### Server short names and associated signal names for heavy maintenance events.

{ ##### Swarm Server management
# Servers associated with pages: these include directly accessible servers with entries
# in the top navigation such as Search and Files, and also servers called by them to
# show results, such as Viewer (which is called by links in Search and Files to show a
# read-only view of a file). If a server doesn't have "BACKGROUND" in its config line
# in data/serverlist.txt, then it's a page server.
# Note "WEBSOCKET" also counts basically as a background server (single instance etc)
# and in addition only communicates by the ws:// (websockets) protocol, as opposed to http://.
# (And shouldn't it be called an "application" rather than a protocol? Never mind.)
my @ServerCommandLines;			# One entry per server, eg "C:/Progs/Intramine/intramine_viewer.pl Search Viewer 81 43126"
my @ServerCommandProgramNames;	# Just the program name, eg "intramine_search.pl" for a $ServerCommandLines[] entry.
my @ServerCommandPorts;			# Just the port used for a server.
my $SwarmServerStartingPort; 	# 'INTRAMINE_FIRST_SWARM_SERVER_PORT' plus one
my $SomeCommandServerIsRunning;	# Postpone starting Cmd or other PERSISTENT page if it is stll running
my $NumServerPages;				# Count of entries that appear in the top nav on each browser page: Search, File, Days etc
my @PageNames;					# $PageNames[1] = 'Files' indexed by page
my @PageServerNames;			# $PageServerNames[1][2] = 'intramine_open_with.pl' indexed by server
my %PageProcIDs;				# proc ID, used when restarting and to check server process is still running
my %PageIndexForPageName;		# $PageIndexForPageName['Files'] = 1 indexed by page
my @ShortServerNames;			# $ShortServerNames[1][2] = 'Opener' indexed by server
my %ShortServerNameForPort;		# $ShortServerNameForPort{'43129'} = 'Viewer'
my %PageNameForShortServerName;	# $PageNameForShortServerName{'Viewer'} = 'Search';
my %PageIsPersistent;			# $PageIsPersistent{'Cmd'} = 1 means it survives a shutdown so it can continue monitoring status - this is mainly for the "Cmd" page
my @PageIndexIsPersistent;		# $PageIndexIsPersistent[n] = 1 means associated Page is persistent, see line above
my @PageIndexForCommandLineIndex; # PageIndexForCommandLineIndex[4] = 1 for Files intramine_fileserver.pl   to find out if it's persistent

# "Background" servers not associated with pages: names are UPPERCASE as listed in data/serverlist.txt.
# For example intramine_filewatcher.pl checks
# the File Watcher log file for changes, and calls out to Elasticsearch to index the changed
# files, after which it sends a "signal=filechange" signal that can be picked up by any
# server interested in file system changes (it's Status in this case).
# There is at most one of each Background server, regardless the Count field in serverlist.txt.
my @BackgroundCommandLines;			# $BackgroundCommandLines[0] = "$scriptFullDir$BackgroundServerNames[$idx] $port_listen " .  $currentPort;
my @BackgroundCommandProgramNames;	# Like above, but just the program name, eg "intramine_filewatcher.pl"
my @BackgroundCommandPorts;			# and just the port number for a $BackgroundCommandLines[] entry
my $NumBackgroundServers;			# 0..up
my @BackgroundNames;				# $BackgroundNames[0] = 'FILEWATCHER'
my @BackgroundServerNames;			# $BackgroundServerNames[0] = 'intramine_filewatcher.pl'
my @ShortBackgroundServerNames;		# $ShortBackgroundServerNames[0] = 'Watcher';
my %ShortBackgroundServerNameForPort;	# $ShortBackgroundServerNameForPort{'43139'} = 'Watcher';
my %PortForShortBackgroundServerName;	# $PortForShortBackgroundServerName{'Watcher'} = 43139;
my %BackgroundProcIDs;				# proc ID, used when restarting and to check server process is still running
# For broadcasting to servers by name, it helps to know the server name for each command line. See BroadcastSignal() below.
my @ServerCommandLinePageNames;
my @BackgroundCommandLineNames;

# For WEBSOCKET servers (BACKGROUND servers that communicate using WebSockets only).
my %PortIsForWEBSOCKETServer;		# $PortIsForWEBSOCKETServer{'43128'} = 1
my %IsWEBSOCKETServer;				# $IsWEBSOCKETServer{$shortServerName} = 1
my $PrimaryWEBSOCKETPort;			# See WebSocketServerPort() etc below

# For redirect based on short server name:
# Eg
# http://192.168.1.132:81/Viewer/?href=C:/perlprogs/mine/docs/domain%20name%20for%20intramine.txt&viewport=81&editport=81&rddm=1
# should be redirected to
# http://192.168.1.132:43125/Viewer/?href=C:/perlprogs/mine/docs/domain%20name%20for%20intramine.txt&viewport=81&editport=81&rddm=1
# where 43125 is a port number for a Viewer that is currently up.
my %PortsForShortServerNames; 				# $PortsForShortServerNames{'Viewer'}[portlist 0-up]
my %CurrentlyUsedIndexForShortServerNames; 	# $CurrentlyUsedIndexForShortServerNames{'Viewer'} = index into above portlist

# For adding a server on the fly:
my $HighestUsedServerPort;	# $startingPort plus num servers started - 1

# For starting and stopping servers:
my %ServerPortIsRunning; # $ServerPortIsRunning{port number} = 1; if server on port number is running.

# Server monitoring: how many to start, how many actually started.
my $TotalServersWanted;
my $TotalServersStarted;
my %ServerPortIsStarting; # $ServerPortIsStarting{port number} = 1 if server on port is starting up. See ReceiveInfo().
my $DoingInitialStartup; # ==1 only during startup, for calling BroadcastAllServersUp()

# Main self-test.
my $MainSelfTest;

# Start all servers listed in data/serverlist.txt. The "Count" field in serverlist.txt
# determines how many of each server to start.
# First create cmd lines for all servers, then start them.
sub StartServerSwarm {
	my ($startingPort) = @_;
	$SwarmServerStartingPort = $startingPort;
	my $currentPort = $startingPort;
	my $webSocketPort = 0;
	$TotalServersStarted = 0;
	$DoingInitialStartup = 1;
	SetMainSelfTest(0);
	
	my $configFilePath = $TESTING ? FullDirectoryPath('TESTSERVERLISTPATH') : FullDirectoryPath('SERVERLISTPATH');
	my $serverCount = LoadServerList($configFilePath);
	print("$serverCount server entries loaded from serverlist for $NumServerPages main pages.\n");

	my $scriptFullPath = $0;
	my $scriptFullDir = DirectoryFromPathTS($scriptFullPath);
	
	CreateCommandLinesForServers(\$currentPort, $scriptFullDir, \$webSocketPort);

	StartAllServers($currentPort);
	}

sub CreateCommandLinesForServers {
	my ($currentPort_R, $scriptFullDir, $webSocketPort_R) = @_;

	# Command for page server [$pgIdx][$srv] (including PERSISTENT).
	for (my $pgIdx = 0; $pgIdx < $NumServerPages; ++$pgIdx)
		{
		my $pageName = $PageNames[$pgIdx];
		my $numServersForPage = @{$PageServerNames[$pgIdx]};
		for (my $srv = 0; $srv < $numServersForPage; ++$srv)
			{
			my $shortName = $ShortServerNames[$pgIdx][$srv];
			$ShortServerNameForPort{$$currentPort_R} = $shortName;
			$PageNameForShortServerName{$shortName} = $pageName;
			my $cmdLine = "$scriptFullDir$PageServerNames[$pgIdx][$srv] $pageName $shortName $port_listen $$currentPort_R";
			push @ServerCommandLines, $cmdLine;
			push @ServerCommandProgramNames, $PageServerNames[$pgIdx][$srv];
			push @ServerCommandPorts, $$currentPort_R;
			
			push @ServerCommandLinePageNames, $pageName;
			my $cmdIdx = @ServerCommandLines - 1;
			$PageIndexForCommandLineIndex[$cmdIdx] = $pgIdx;
			
			# For redirects, remember port list for each short server name.
			push @{$PortsForShortServerNames{$shortName}}, $$currentPort_R;
			$CurrentlyUsedIndexForShortServerNames{$shortName} = 0;
			# Set server on current port as running (perhaps optimistic).
			SetServerPortIsRunning($$currentPort_R, 1);
			++$$currentPort_R;
			}
		}
	
	# Command for BACKGROUND server.
	# $NumBackgroundServers = @BackgroundNames;
	# Start any WEBSOCKET server first.
	for (my $loop = 1; $loop <= 2; ++$loop)
		{
		for (my $idx = 0; $idx < $NumBackgroundServers; ++$idx)
			{
			my $shortName = $ShortBackgroundServerNames[$idx];
			if (   ($loop == 1 && ShortNameIsForWEBSOCKServer($shortName))
				|| ($loop == 2 && !ShortNameIsForWEBSOCKServer($shortName)) )
				{
				$ShortBackgroundServerNameForPort{$$currentPort_R} = $shortName;
				$PortForShortBackgroundServerName{$shortName} = $$currentPort_R;
				# A background server doesn't have a "page" name since it isn't associated with
				# a page, it just lurks in the background. So we send the $shortName in place of
				# the page name, just to keep the interface simple.
				my $cmdLine = "$scriptFullDir$BackgroundServerNames[$idx] $shortName $shortName $port_listen $$currentPort_R";
				push @BackgroundCommandLines, $cmdLine;
				push @BackgroundCommandProgramNames, $BackgroundServerNames[$idx];		
				push @BackgroundCommandPorts, $$currentPort_R;
				push @BackgroundCommandLineNames, $BackgroundNames[$idx];
				# Set server on current port as running (perhaps optimistic).
				SetServerPortIsRunning($$currentPort_R, 1);
		
				if (ShortNameIsForWEBSOCKServer($shortName))
					{
					$PortIsForWEBSOCKETServer{$$currentPort_R} = 1;
					$$webSocketPort_R = $$currentPort_R;
					SetWebSocketServerPort($$currentPort_R);
					}
			
				++$$currentPort_R;
				} # if first $loop and WEBSOCKET, or second $loop
			} # for BACKGROUND servers
		} # two $loops
	
	# Reget $$webSocketPort_R, in case we are testing (see up around line 605);
	$$webSocketPort_R = WebSocketServerPort();
	# Revisit the command lines for all servers and put in " $$webSocketPort_R" at end.
	for (my $i = 0; $i < @ServerCommandLines; ++$i)
		{
		$ServerCommandLines[$i] .= " $$webSocketPort_R";
		}
	for (my $i = 0; $i < @BackgroundCommandLines; ++$i)
		{
		$BackgroundCommandLines[$i] .= " $$webSocketPort_R";
		}
	}

sub StartAllServers {
	my ($currentPort) = @_;

	# Postpone 'persistent' (command) server starts if any are running.
	$SomeCommandServerIsRunning = AnyCommandServerIsUp();
	
	# Start the Page servers, from $PageIndexForCommandLineIndex[].
	my $numServers = @ServerCommandLines;
	my $numServersStarted = 0;
	for (my $i = 0; $i < $numServers; ++$i)
		{
		my $pgIdx = $PageIndexForCommandLineIndex[$i];
		my $isPersistent = $PageIndexIsPersistent[$pgIdx];
		
		if (!$isPersistent || !$SomeCommandServerIsRunning)
			{
			Output("   STARTING '$ServerCommandLines[$i]' \n");
			my $proc;
			Win32::Process::Create($proc, $ENV{COMSPEC}, "/c $ServerCommandLines[$i]", 0, 0, ".")
				|| die ServerErrorReport();
			$PageProcIDs{$ServerCommandLines[$i]} = $proc;
			++$numServersStarted;
			}
		else
			{
			Output("(Command server, skipping for now since it's already running.)\n");
			}
		}
	Output("$numServersStarted out of $numServers page servers started\n------------\n");
		
	$TotalServersWanted = $numServers;
	
	# Start one of each BACKGROUND (or WEBSOCKET) server.
	$numServers = @BackgroundCommandLines;
	for (my $i = 0; $i < $numServers; ++$i)
		{
		Output("   STARTING '$BackgroundCommandLines[$i]' \n");
		my $proc;
		Win32::Process::Create($proc, $ENV{COMSPEC}, "/c $BackgroundCommandLines[$i]", 0, 0, ".")
			|| die ServerErrorReport();
		$BackgroundProcIDs{$BackgroundCommandLines[$i]} = $proc;
		++$numServersStarted;
		}
	Output("$numServers background servers started\n------------\n");
	
	$TotalServersWanted += $numServers;
	$HighestUsedServerPort = $currentPort - 1;
	}

sub SwarmServerFirstPort {
	return($SwarmServerStartingPort);
	}

# Load data/serverlist.txt. Using '|' to mean 'one or more tabs', file format there is:
# Count|Page Name|Unique short name|Perl program name(*optional*|PERSISTENT or BACKGROUND or WEBSOCKET)
# Count is how many of each server. The second entry is the name of the associated web page,
# third is a unique short name for the server,
# fourth entry is the name of associated Perl program that runs the server for the page.
# "intramine_search.pl" shows the Search page, with search form and (Elasticsearch) search results.
# "intramine_viewer.pl" shows read-only views of files, mostly using codemirror (cm).
# "intramine_editor.pl" opens an editable view of a file using the CodeMirror editor etc.
# The "Cmd" page is special, associated server can stay running response to a restart request so that
# it can continue monitoring during the restart. The serverlist.txt entry for it is
# Cmd	Cmd		intramine_commandserver.pl	PERSISTENT
# with 'PERSISTENT' signalling that it should be treated specially. See $CommandServerHasBeenNotified etc.
# An entry with trailing 'BACKGROUND' signals a server that has no top navigation entry or association
# with same, typically just lurking in the background doing maintenance. Eg
# FILEWATCHER	Watcher	intramine_filewatcher.pl	BACKGROUND
# monitors the file system for changes, and asks Elasticsearch to reindex changed/new files.
# See serverlist.txt.
sub LoadServerList {
	my ($configFilePath) = @_;
	my $count = 0;
	
	if (-f $configFilePath)
		{
		my $fileH = FileHandle->new("$configFilePath") or die("No config file found at |$configFilePath|!\n");
		my $line;
		my $pageIndex = -1;
		my %pageNameSeen;
		
		# Load the WS service line first and always.
		my $webSocketLine = '1	WEBSOCKETS			WS			intramine_websockets.pl		WEBSOCKET';
		# FOR TESTING ONLY, start the WS service in a separate cmd window if 1.
		my $runWSServerSeparately = 0;
		if (!$runWSServerSeparately) # business as usual
			{
			LoadOneServer($webSocketLine, \$count, \$pageIndex, \%pageNameSeen);
			}
		else # Make sure the names and numbers are right!
			{
			$IsWEBSOCKETServer{'WS'} = 1;
			SetWebSocketServerPort('43140');
			$PortIsForWEBSOCKETServer{'43140'} = 1;
			$ShortBackgroundServerNameForPort{'43140'} = 'WS';
			$PortForShortBackgroundServerName{'WS'} = '43140';
			}
		
		# Aug 2021 the SSE server has been dropped. Don't start it.
		while ($line = <$fileH>)
	    	{
	        chomp($line);
	        if (length($line) && $line !~ m!^\s*(#|$)! && $line !~ m!^0\s!) # skip blank lines and comments and zero Count
	        	{
	        	# Avoid loading the WS service twice. And avoid loading the SSE server always.
	        	if ($line !~ m!intramine_websockets\.pl! && $line !~ m!intramine_SSE\.pl!)
	        		{
	        		LoadOneServer($line, \$count, \$pageIndex, \%pageNameSeen);
	        		}
	        	}
	        }
	    close $fileH;
	
		if ($count == 0)
			{
			die("ERROR could not load anything useful from config file |$configFilePath|!\n");
			}
		else
			{
			$NumServerPages = @PageNames;
			$NumBackgroundServers = @BackgroundNames;
			}
		}
	else
		{
		die("No config file found at |$configFilePath|!\n");
		}
	
	return($count);
	}

sub LoadOneServer {
	my ($line, $countR, $pageIndexR, $pageNameSeenH) = @_;

	my @fields = split(/\t+/, $line); # Split on one or more tabs
	my $instanceCount = $fields[0];
	my $pageName = $fields[1];
	my $shortServerName = $fields[2]; # for %ShortServerNameForPort, eventually
	my $serverProgramName = $fields[3];
	my $specialType = (defined($fields[4])) ? $fields[4]: '';
	
	if ($shortServerName eq 'Main')
		{
		# Main entry just triggers a self-test if its Count field is positive.
		if ($instanceCount > 0)
			{
			SetMainSelfTest(1);
			
			# Fudge up an entry for intramine_test_main.pl.
			my $mainTestProgram = CVal('INTRAMINE_TEST_SERVICE');
			my $mainTestShortname = CVal('INTRAMINE_TEST_NAME');
			$line = "";
			$instanceCount = 2; # Run two to test round robin.
			$pageName = $mainTestShortname;
			$shortServerName = $pageName;
			$serverProgramName = $mainTestProgram;
			$specialType = '';
			}
		}

	# 'BACKGROUND' programs do not correspond to pages, and have no web interface.
	# Only one of each is started, and they do not appear in the navigation at top of page.
	# A WEBSOCKET program is a BACKGROUND program that communicates only with WebSockets.
	if ($specialType eq 'BACKGROUND' || $specialType eq 'WEBSOCKET')
		{
		push @BackgroundNames, $pageName;
		push @BackgroundServerNames, $serverProgramName;
		push @ShortBackgroundServerNames, $shortServerName;
		
		if ($specialType eq 'WEBSOCKET')
			{
			$IsWEBSOCKETServer{$shortServerName} = 1;
			}
		}
	else # a regular Page server, main entry will show up in nav bar.
		{
		if (!defined($pageNameSeenH->{$pageName}))
			{
			$pageNameSeenH->{$pageName} = 1;
			++$$pageIndexR;
			push @PageNames, $pageName;
			$PageIndexForPageName{$pageName} = $$pageIndexR;
			}
			
		my $currPageIndex = $PageIndexForPageName{$pageName};
		
		if ($specialType eq 'PERSISTENT')
			{
			$PageIsPersistent{$pageName} = 1; # eg "Cmd" server, will ignore regular 'EXITEXITEXIT' requests so it can monitor during restart
			$PageIndexIsPersistent[$currPageIndex] = 1;
			}
		elsif (!defined($PageIndexIsPersistent[$currPageIndex]))
			{
			$PageIndexIsPersistent[$currPageIndex] = 0;
			}
		
		for (my $j = 0; $j < $instanceCount; ++$j)
			{
			push @{$PageServerNames[$currPageIndex]}, $serverProgramName;
			push @{$ShortServerNames[$currPageIndex]}, $shortServerName;
			}
		}
	++$$countR; # includes backgrounds, just used to report count of servers seen	
	}

sub ServerErrorReport{
        print Win32::FormatMessage( Win32::GetLastError() );
        return 1;
    }

# This "Stop" is ignored by Cmd page servers, so they can keep running when
# the server swarm and this server are stopped and restarted from a particular
# Cmd page somewhere. As mentioned at the top of this file, you can safely ignore this "feature."
sub StopAllSwarmServers {
	# TEST ONLY
	print("Asking all servers to stop.\n");

	my $srvrAddr = ServerAddress();
	
	# Page servers.
	my $numServers = @ServerCommandLines;
	for (my $i = 0; $i < $numServers; ++$i)
		{
		my $port = $ServerCommandPorts[$i];
		AskSwarmServerToExit($port, $srvrAddr);
		}
	
	# Background servers.
	$numServers = @BackgroundCommandLines;
	for (my $i = 0; $i < $numServers; ++$i)
		{
		my $port = $BackgroundCommandPorts[$i];
		if (!PortIsForWEBSOCKServer($port))
			{
			AskSwarmServerToExit($port, $srvrAddr);
			}
		}

	# Do the WebSockets server last.
	for (my $i = 0; $i < $numServers; ++$i)
		{
		my $port = $BackgroundCommandPorts[$i];
		if (PortIsForWEBSOCKServer($port))
			{
			AskSwarmServerToExit($port, $srvrAddr);
			}
		}

	}

sub AskSwarmServerToExit {
	my ($portNumber, $serverAddress) = @_;
	
	if (ServerOnPortIsRunning($portNumber))
		{
		Output("Attempting to stop $serverAddress:$portNumber\n");
		
		if (PortIsForWEBSOCKServer($portNumber))
			{
			WebSocketSend('EXITEXITEXIT');
			Output("Exit request sent to $serverAddress:$portNumber\n");
			SetServerPortIsRunning($portNumber, 0);
			}
		else
			{
			my $remote = IO::Socket::INET->new(
			                Proto   => 'tcp',       		# protocol
			                PeerAddr=> "$serverAddress", 	# Address of server
			                PeerPort=> "$portNumber"      	# port of swarm server, default is 43124..up
			                ) or (ServerErrorReport() && return);
			
			print $remote "GET /?EXITEXITEXIT=1 HTTP/1.1\n\n";
			close $remote;
			Output("Exit request sent to $serverAddress:$portNumber\n");
			
			# A persistent server such as "Cmd" will not stop for this request.
			my $numServers = @ServerCommandLines;
			my $isPersistent = 0; 
			for (my $i = 0; $i < $numServers; ++$i)
				{
				my $port = $ServerCommandPorts[$i];
				if ($port == $portNumber)
					{
					my $pgIdx = $PageIndexForCommandLineIndex[$i];
					$isPersistent = $PageIndexIsPersistent[$pgIdx];
					last;
					}
				}
			if (!$isPersistent)
				{
				SetServerPortIsRunning($portNumber, 0);
				}
			}
		}
	else
		{
		Output("$serverAddress:$portNumber has already been asked to stop.\n");
		}
	}

# This "ForceStop" will stop all swarm servers, including Cmd page intramine_commandserver.pl servers.
sub ForceStopAllSwarmServers {
	print("Forcing all servers to stop.\n");

	my $srvrAddr = ServerAddress();
	
	# Page servers.
	my $numServers = @ServerCommandLines;
	for (my $i = 0; $i < $numServers; ++$i)
		{
		my $port = $ServerCommandPorts[$i];
		print("Forcing stop of Page server on port $port\n");
		ForceStopServer($port, $srvrAddr);
		}
	# Background servers.
	$numServers = @BackgroundCommandLines;
	for (my $i = 0; $i < $numServers; ++$i)
		{
		my $port = $BackgroundCommandPorts[$i];
		if (!PortIsForWEBSOCKServer($port))
			{
			print("Forcing stop of BACKGROUND server on port $port\n");
			ForceStopServer($port, $srvrAddr);
			}
		}

	# Do the WebSockets server last.
	for (my $i = 0; $i < $numServers; ++$i)
		{
		my $port = $BackgroundCommandPorts[$i];
		if (PortIsForWEBSOCKServer($port))
			{
			print("Forcing stop of WebSockets server on port $port\n");
			ForceStopServer($port, $srvrAddr);
			}
		}
	}

sub ForceStopServer {
	my ($portNumber, $serverAddress) = @_;
	# TEST ONLY
	print("Attempting to FORCE stop $serverAddress:$portNumber\n");
	
	if (ServerOnPortIsRunning($portNumber))
		{
		Output("Attempting to FORCE stop $serverAddress:$portNumber\n");
		
		if (PortIsForWEBSOCKServer($portNumber))
			{
			WebSocketSend('FORCEEXIT');
			Output("FORCEEXIT sent to $serverAddress:$portNumber\n");
			SetServerPortIsRunning($portNumber, 0);
			}
		else
			{
			my $remote = IO::Socket::INET->new(
			                Proto   => 'tcp',       		# protocol
			                PeerAddr=> "$serverAddress", 	# Address of server
			                PeerPort=> "$portNumber"      	# port of server typ. 43124..up
			                ) or (ServerErrorReport() && return);
			
			print $remote "GET /?FORCEEXIT=1 HTTP/1.1\n\n";
			close $remote;
			Output("FORCEEXIT sent to $serverAddress:$portNumber\n");
			SetServerPortIsRunning($portNumber, 0);
			}		
		}
	else
		{
		Output("$serverAddress:$portNumber has already been stopped.\n");
		}
	}

# BroadcastSignal():
# Send message to some or all IntraMine servers, in response to a swarmserver.pm#RequestBroadcast().
# TLDR; $formH->{'signal'} must be defined for signal to be sent, and $msg should start
# off with '/?signal=someSignal' in order for some recipient to notice that it's an incoming signal.
#
# Recipients, and whether or not to even send the signal, are determined by $formH entries:
# $formH->{'signal'} must be defined in order to send the signal.
# $formH->{'name'} can optionally be defined to limit the recipients:
#   $formH->{'name'} == 'PageServers' will send to non-background servers
#   $formH->{'name'} == 'BackgroundServers' will send to background "background" servers
#   $formH->{'name'} == entry in @ServerCommandLinePageNames will send to just servers associated with that page
#   $formH->{'name'} == entry in @BackgroundCommandLineNames will send to just that background server
#
# The "short name" for each swarm server is appended here to the $msg payload, eg
# 'name=Upload' when sending to an instance of intramine_uploader.pl. ("Short" names are
# in the third column of data/serverlist.txt.)
#
# A BroadcastSignal() can originate here (see BroadcastDateHasChanged() below), but it is more often
# called in response to a request to forward a signal as received from elsewhere. The line
# $RequestAction{'signal'} = \&BroadcastSignal; 	# signal=anything
# near the top of MainLoop() sets up the signal handler.
#
# Typically it's a server other than this main one that sends the signal.
# For example, BroadcastOverdueCount() in intramine_todolist.pl sends off
# "signal=todoCount&count=$overdueCount&name=PageServers"
# to this main server. In initial processing here, the parameters 'signal', 'count' etc
# are put in $formH, so the contents of $obj and $formH as received here from another
# server are essentially the same. The 'name=PageServers' param ends up in $formH as
# $formH->{'name'} == 'PageServers', resulting in a broadcast to all page servers.
#
# If the sender name is important, supply it as 'sender=ShortServerName', eg 'sender=Viewer'.
#
# Some signals imply that a server will be out of action carrying out maintenance for a while.
# For these signals, if there are two or more instances of the server running we signal them
# to carry out the maintenance one at a time, to avoid a total service outage.
#
# TODO currently there is no way to send a signal to a top level servers such as Search without
# also sending the signal to its associated second level servers (Viewer Opener Editor Linker).
# This is inefficient, but a server that doesn't want a signal can just ignore it.
#
# Note WEBSOCKET servers are skipped, they only talk through ws:// connections, not http://.
sub BroadcastSignal {
	my ($obj, $formH, $peeraddress) = @_;
	if (!defined($formH->{'signal'}))
		{
		return;
		}
	my $name = (defined($formH->{'name'})) ? $formH->{'name'}: '';
	my $msg = $obj; # '/?signal=todoCount&count=3&name=PageServers' or '/?signal=reindex' etc
	$msg =~ s!^/\?!!;

	my $srvrAddr = ServerAddress();
	
	# Maintenance signal handling: a known maintenance signal (see ) starts this off.
	# Each server that finishes maintenance will send us a 'backinservice' signal, together with
	# its short name and the signal it was responding to. We signal all ports for the service in
	# turn until done. Note the sender of the signal is typically not the server that will respond
	# to it by doing maintenance, eg Watcher sends a 'folderrenamed' signal and Linker is the one
	# that will respond to it by doing maintenance on all its corresponding active ports, one by one.
	# When one Linker is done, it will send a 
	# 'signal=backinservice&sender=Linker&respondingto=folderrenamed'
	# signal, so we will know here which server to send to, and what maintenance signal.
	my $maintenanceShortName = '';
	my $maintenancePort = 0;
	HandleMaintenanceSignal($formH, \$maintenanceShortName, \$maintenancePort);
		
	# Non-maintenance routine signal handling. Fire the signal off, but avoid sending signal
	# to any instance of a server that is undergoing maintenance.
	# %portSignalled: avoid sending signal twice to same port. Might be needed some day....
	my %portSignalled; # $portSignalled{portnumber} = 1 if signal sent to it.
	# Page servers.
	SignalPageServers($name, \%portSignalled, $msg, $srvrAddr);

	# Also broadcast to a specific page server short name.
	# There can be more than one server with the same short name (running on different ports).
	SignalShortNamePageServers($name, \%portSignalled, $msg, $srvrAddr);

	# Background servers too
	SignalBackgroundServers($name, \%portSignalled, $msg, $srvrAddr);

	# Also broadast to a specific background server short name $PortForShortBackgroundServerName{$shortName}
	SignalShortNameBackgroundServers($name, \%portSignalled, $msg, $srvrAddr);
	
	return("OK");
	}

sub SignalPageServers {
	my ($name, $portSignalled_H, $msg, $srvrAddr) = @_;

	my $numServers = @ServerCommandLines;
	for (my $i = 0; $i < $numServers; ++$i)
		{
		my $pageName = $ServerCommandLinePageNames[$i];
		if ($name eq '' || $name eq $pageName || $name eq 'PageServers')
			{
			my $port = $ServerCommandPorts[$i];
			# Append short name of server to all signals going out.
			my $shortName = $ShortServerNameForPort{$port};
			if (!ShortServerNameIsUndergoingMaintenance($shortName))
				{
				$portSignalled_H->{$port} = 1;
				my $message = $msg;
				$message .= ($message =~ m!\&$!) ? "shortname=$shortName": "&shortname=$shortName";
				SendOneSignal($port, $srvrAddr, $message);
				}
			}
		}
	}

sub SignalShortNamePageServers {
	my ($name, $portSignalled_H, $msg, $srvrAddr) = @_;

	my $numEntriesForShortName = NumServersTotalForShortName($name);
	if ($numEntriesForShortName)
		{
		for (my $i = 0; $i < $numEntriesForShortName; ++$i)
			{
			my $proposedPort = $PortsForShortServerNames{$name}->[$i];
			if (ServerOnPortIsRunning($proposedPort))
				{
				my $port = $proposedPort;
				my $shortName = $name;
				if (!ShortServerNameIsUndergoingMaintenance($shortName) && !defined($portSignalled_H->{$port}))
					{
					$portSignalled_H->{$port} = 1;
					my $message = $msg;
					$message .= ($message =~ m!\&$!) ? "shortname=$shortName": "&shortname=$shortName";
					SendOneSignal($port, $srvrAddr, $message);
					}
				}
			}
		}
	}

sub SignalBackgroundServers {
	my ($name, $portSignalled_H, $msg, $srvrAddr) = @_;

	my $numServers = @BackgroundCommandLines;
	for (my $i = 0; $i < $numServers; ++$i)
		{
		my $backgroundName = $BackgroundCommandLineNames[$i];
		if ($name eq '' || $name eq $backgroundName || $name eq 'BackgroundServers')
			{
			my $port = $BackgroundCommandPorts[$i];
			# Append short name of server to all signals going out.
			my $shortName = $ShortBackgroundServerNameForPort{$port};
			if (   !ShortServerNameIsUndergoingMaintenance($shortName)
				&& !defined($portSignalled_H->{$port})
				&& !PortIsForWEBSOCKServer($port) )
				{
				$portSignalled_H->{$port} = 1;
				my $message = $msg;
				$message .= ($message =~ m!\&$!) ? "shortname=$shortName": "&shortname=$shortName";			
				SendOneSignal($port, $srvrAddr, $message);
				}
			}
		}
	}

sub SignalShortNameBackgroundServers {
	my ($name, $portSignalled_H, $msg, $srvrAddr) = @_;

	if (defined($PortForShortBackgroundServerName{$name}))
		{
		my $port = $PortForShortBackgroundServerName{$name};
		# Append short name of server to all signals going out.
		my $shortName = $name;
		if (   !ShortServerNameIsUndergoingMaintenance($shortName)
			&& !defined($portSignalled_H->{$port})
			&& !PortIsForWEBSOCKServer($port) )
			{
			$portSignalled_H->{$port} = 1;
			my $message = $msg;
			$message .= ($message =~ m!\&$!) ? "shortname=$shortName": "&shortname=$shortName";
			SendOneSignal($port, $srvrAddr, $message);
			}
		}
	}

sub HandleMaintenanceSignal {
	my ($formH, $maintenanceShortNameR, $maintenancePortR) = @_;

	my $srvrAddr = ServerAddress();

	if (SignalIndicatesMaintenanceOutage($formH->{'signal'}))
		{
		my $shortName = ShortServerNameForMaintenanceSignal($formH->{'signal'});
		StartShortServerNameMaintenance($shortName);
		$$maintenanceShortNameR = $shortName;
		my $port = NextPortForServerUnderMaintenance($shortName);
		if ($port != 0)
			{
			my $numServers = NumServersTotalForShortName($$maintenanceShortNameR);
			my $serverSP = ($numServers == 1) ? 'server' : 'servers';
			$$maintenancePortR = $port;
			SendOneSignal($port, $srvrAddr, "signal=$formH->{'signal'}&shortname=$$maintenanceShortNameR");
			}
		}
	elsif ($formH->{'signal'} eq 'backinservice')
		{
		if (defined($formH->{'respondingto'}))
			{
			if (defined($formH->{'sender'}) && IsShortName($formH->{'sender'}))
				{
				$$maintenanceShortNameR = $formH->{'sender'};
				my $port = NextPortForServerUnderMaintenance($$maintenanceShortNameR);
				if ($port != 0)
					{
					$$maintenancePortR = $port;
					SendOneSignal($port, $srvrAddr, "signal=$formH->{'respondingto'}&shortname=$$maintenanceShortNameR");
					}
				}
			}
		}	
	}

sub SendOneSignal {
	my ($portNumber, $serverAddress, $msg) = @_;
	Output("Sending $msg to $serverAddress:$portNumber\n");
	my $remote = IO::Socket::INET->new(
	                Proto   => 'tcp',       		# protocol
	                PeerAddr=> "$serverAddress", 	# Address of server
	                PeerPort=> "$portNumber"      	# port of server typ. 43124..up
	                ) or (ServerErrorReport() && return);
	
	print $remote "GET /?$msg HTTP/1.1\n\n";
	close $remote;	# No reply needed.
	}

# Handle an "ssinfo" signal.
# For example, when a swarm server finishes starting up it calls
# RequestBroadcast('ssinfo=serverUp&port=' . $ListeningPort);
# (see swarmserver.pm#RequestBroadcast())
# which arrives here, and the server is counted as up and running.
sub ReceiveInfo {
	my ($obj, $formH, $peeraddress) = @_;
	if (!defined($formH->{'ssinfo'}))
		{
		return;
		}
	my $info = $formH->{'ssinfo'};
	
	if ($info eq 'serverUp')
		{
		ReceiveServerUp($formH);
		}
	elsif ($info eq 'starting')
		{
		if (defined($formH->{'port'}))
			{
			my $senderPort = $formH->{'port'};
			SetServerOnPortIsStarting($senderPort, 1);
			}
		}
	elsif ($info eq 'doneTesting')
		{
		ServerTestIsDone($formH);
		}
	
	# All servers are started? Do some housekeeping. Mainly let all other servers know that
	# all servers have fully started.
	# If we are $TESTING, start the tests.
	if (   $DoingInitialStartup
		&& ($TotalServersStarted == $TotalServersWanted
		|| ($WebSockIsUp && $TotalServersStarted == $TotalServersWanted - 1)) )
		{
		BroadcastAllServersUp();
		SetAllServersToNotStarting();
		$DoingInitialStartup = 0;
		if ($TESTING)
			{
			RunAllTests();
			}
		}
	
	return("OK");
	}

sub ReceiveServerUp {
	my ($formH) = @_;
	
	if ($DoingInitialStartup)
		{
		++$TotalServersStarted;
		}
	
	if (defined($formH->{'port'}))
		{
		my $senderPort = $formH->{'port'};

		# Announce specific server has started, short name and port.
		my $srvr = (defined($ShortServerNameForPort{$senderPort})) ? $ShortServerNameForPort{$senderPort}: '';
		if ($srvr eq '')
			{
			$srvr = (defined($ShortBackgroundServerNameForPort{$senderPort})) ? 
					$ShortBackgroundServerNameForPort{$senderPort}: '(PORT NOT RECOGNISED)';
			}
		Output("$srvr server has started on port $senderPort.\n");
		if (!$kDISPLAYMESSAGES) # Avoid duplicated print.
			{
			print("$srvr server has started on port $senderPort.\n");
			}
			
		SetServerOnPortIsStarting($senderPort, 0);
		}
	}

# Here we "dummy up" a broadcast with an allServersUp signal, which triggers ToDo server to do a
# refresh behind the scenes, and then calculate and broadcast the current overdue ToDo count.
# All page servers pick up on the count, and show it in the top nav of pages next to "ToDo",
# eg "ToDo [3]".
# From BroadcastSignal():
#	my ($obj, $formH, $peeraddress) = @_;
#	if (!defined($formH->{'signal'}))
#		{
#		return;
#		}
#	my $name = (defined($formH->{'name'})) ? $formH->{'name'}: '';
#	my $msg = $obj; # '/?signal=todoCount&count=3&name=PageServers' or '/?signal=reindex' etc
#	$msg =~ s!^/\?!!;
sub BroadcastAllServersUp {
	my %form;
	$form{'signal'} = 'allServersUp';
	# Revision, send to all swarm servers.
	#$form{'name'} = 'PageServers';
	#my $ob = '/?signal=allServersUp&name=PageServers';
	my $ob = '/?signal=allServersUp';
	my $ignoredPeerAddress = '';
	# TEST ONLY
	print("All $TotalServersWanted servers have started.\n");
	BroadcastSignal($ob, \%form, $ignoredPeerAddress);
	}

# Command page server(s) might still be running - try to stop them before starting new instances.
sub AnyCommandServerIsUp {
	my $result = 0;
	my $numServers = @ServerCommandLines;

	# At this point ServerAddress() has not been initted, so we have to use localhost.
	my $srvrAddr = 'localhost';
	
	for (my $i = 0; $i < $numServers; ++$i)
		{
		my $pgIdx = $PageIndexForCommandLineIndex[$i];
		my $isPersistent = $PageIndexIsPersistent[$pgIdx];
		
		if ($isPersistent)
			{
			my $port = $ServerCommandPorts[$i];
			$result = ServerOnPortIsRunning($port) && ServerIsUp($srvrAddr, $port);
			if ($result)
				{
				last;
				}
			}
		}
	
	return($result);
	}

# Returns 1 if server at $serverAddress:$portNumber responds to an 'id' request, 0 if not.
sub ServerIsUp {
	my ($serverAddress, $portNumber) = @_;
	Output("Pinging $serverAddress:$portNumber\n");
	my $result = 0;
	
	if (PortIsForWEBSOCKServer($portNumber))
		{
		$result = WebSocketSend('Main hello WS are you there');
		}
	else
		{
		my $remote = IO::Socket::INET->new(
		                Proto   => 'tcp',       		# protocol
		                PeerAddr=> "$serverAddress", 	# Address of server
		                PeerPort=> "$portNumber"      	# port of server 591 or 8008 are standard HTML variants
		                ) or (return(0));
		print $remote "GET /?req=id HTTP/1.1\n\n";
		my $line = <$remote>;
		chomp($line) if (defined($line));
		close $remote;
		$result = (defined($line) && length($line) > 0);
		}
	
	return($result);
	}

# Restart just servers for pages marked PERSISTENT in /data/serverlist.txt, eg "Cmd" server(s).
sub RestartCommandServers {
	my $numServers = @ServerCommandLines;
	
	my $srvrAddr = ServerAddress();

	for (my $i = 0; $i < $numServers; ++$i)
		{
		my $pgIdx = $PageIndexForCommandLineIndex[$i];
		my $isPersistent = $PageIndexIsPersistent[$pgIdx];
		# Command page server(s) might still be running - try to stop them before starting new instances.
		if ($isPersistent)
			{
			my $port = $ServerCommandPorts[$i];
			if (ServerOnPortIsRunning($port))
				{
				ForceStopServer($port, $srvrAddr);
				}

			Output("   STARTING COMMAND SRVR '$ServerCommandLines[$i]' \n");
			print("NOTE MAIN reSTARTING COMMAND SRVR '$ServerCommandLines[$i]' \n");
			my $proc;
			Win32::Process::Create($proc, $ENV{COMSPEC}, "/c $ServerCommandLines[$i]", 0, 0, ".")
				|| die ServerErrorReport();
			$PageProcIDs{$ServerCommandLines[$i]} = $proc;
			SetServerPortIsRunning($port, 1);
			}
		}	
	}

# Respond to a 'req=redirect' request from another server. Such a request is sent when another
# server receives a request for a different server, due to the port number being out of date.
# Coming in, $formH->{'resource'} holds a copy of params for a request that had the wrong port number.
# If the beginning of the params is a recognised short name, '/ShortName/' then we cook up
# a redirect to the correct port (known here from $ShortServerNameForPort{$port} = 'ShortName')
# and send it back to the patiently waiting swarmserver.pm#RedirectFromMain().
# Returns '' for any problem (no short name in params, short name not found in %ShortServerNameForPort values).
# (Note #anchors are not forwarded by browsers in requests, so a redirect will lose the #anchor.
# I don't have an easy workaround for that.)
sub RedirectToCorrectedPort {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = '';
	
	# Typical 'resource':  %20name%20for%20intramine.txt&viewport=43126&editport=43127&rddm=1'
	my $params = defined($formH->{'resource'}) ? $formH->{'resource'}: '';
	if ($params =~ m!^/(\w+)(/|$)!)
		{
		my $potentialShortName = $1;
		if (IsShortName($potentialShortName))
			{
			$params =~ s!\"!%22!g;
			$params =~ s!\%!%25!;
			
			$result = RedirectBasedOnShortName($params, $potentialShortName);
			}
		}
	
	return($result);
	}

# Access to @PageNames array, needed by ResultPage() to verify page is known to us.
sub GetPageNames {
	return(\@PageNames);
	}

sub ShortServerNameForPort {
	my ($portNumber) = @_;
	my $result = (defined($ShortServerNameForPort{$portNumber})) ? $ShortServerNameForPort{$portNumber}: '';
	return($result);
	}

# Return an HTML table listing servers and status. One should preferably
# use YAML or JSON or something agreed upon. It's on my To Do List:) Meanwhile
# I'm calling it an "HTML Fragment."
# This is called by the Status server, see status.js#refreshStatus() ("req=filestatus").
sub ServerStatus {
	my ($obj, $formH, $peeraddress) = @_;
	my $pageServerTableId = CVal('PAGE_SERVER_STATUS_TABLE');
	my $backgroundServerTableId = CVal('BACKGROUND_SERVER_STATUS_TABLE');
	my $statusButtonClass = CVal('STATUS_BUTTON_HOLDER_CLASS');
	my $portHolderClass = CVal('PORT_STATUS_HOLDER_CLASS');

	my $result = '';
	
	# Page servers.
	ReportOnPageServers(\$result);
	
	# Background servers too. They cannot be stopped with a 'Stop' button.
	ReportOnBackgroundServers(\$result);
	
	# Throw in summary lines at the top.
	AddSummaryLines(\$result);
		
	return($result);
	}

sub ReportOnPageServers {
	my ($resultR) = @_;
	my $pageServerTableId = CVal('PAGE_SERVER_STATUS_TABLE');
	my $portHolderClass = CVal('PORT_STATUS_HOLDER_CLASS');
	my $statusButtonClass = CVal('STATUS_BUTTON_HOLDER_CLASS');

	my $srvrAddr = ServerAddress();
	
	$$resultR .= '<table id="' . $pageServerTableId . '"><caption><strong>Page servers</strong></caption><thead><tr>' .
		'<th onclick="sortTable(\'' . $pageServerTableId. '\', 0); pageSortColumn = 0;">Server program&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>' .
		'<th onclick="sortTable(\'' . $pageServerTableId. '\', 1); pageSortColumn = 1;">Name&nbsp;&nbsp;&nbsp;</th>' .
		'<th onclick="sortTable(\'' . $pageServerTableId. '\', 2); pageSortColumn = 2;">Port</th>' .
		'<th onclick="sortTable(\'' . $pageServerTableId. '\', 3); pageSortColumn = 3;">Status</th>' .
		'<th>Manage</th>' .
		'</tr></thead><tbody>' . "\n";
	
	my $numServers = @ServerCommandLines;
	my $numPageServers = $numServers;
	for (my $i = 0; $i < $numServers; ++$i)
		{
		if (defined($PageProcIDs{$ServerCommandLines[$i]}))
			{
			my $port = $ServerCommandPorts[$i];
			my $serverShouldBeRunning = ServerOnPortIsRunning($port);
			my $cmdProper = $ServerCommandProgramNames[$i];
			my $name = $ShortServerNameForPort{$port};
			my $procID = $PageProcIDs{$ServerCommandLines[$i]};
			my $exitcode = 1;
			my $serverStatus = 'UP';
			if ($serverShouldBeRunning)
				{
				$procID->GetExitCode($exitcode);
				}
			my $statusImg = "<div class='led-green'></div>";
			if ($serverShouldBeRunning &&  $exitcode eq STILL_ACTIVE )
				{
				# Don't pester the server if it has already said that it's starting.
				if (ServerOnPortIsStarting($port))
					{
					$serverStatus = 'STARTING UP';
					$statusImg = "<div class='led-yellow'></div>";
					}
				else
					{
					# business as usual, probably UP....
					# Note there's no point asking the Status server if it's up, it's the only
					# server asking about Status.
					my $pageName = $ServerCommandLinePageNames[$i];
					if ($pageName !~ m!status!i && !ShortServerNameIsUndergoingMaintenance($name))
						{
						my $stillResponding = ServerIsUp($srvrAddr, $port);
						if (!$stillResponding)
							{
							$serverStatus = 'NOT RESPONDING';
							$statusImg = "<div class='led-red-noblink'></div>";
							}
						}
					}
				}
			else
				{
				$serverStatus = 'DEAD';
				$statusImg = "<div class='led-red-noblink'></div>";
				}
			$$resultR .= "<tr><td>$cmdProper</td><td>$name</td><td><span class='$portHolderClass'>$port</span></td><td><div class='divAlignCenter'>$statusImg<div class='divAlignCenter'>&nbsp;$serverStatus</div></div></td><td>&nbsp;&nbsp;<span class='$statusButtonClass'>BUTTONS</span></td></tr>\n";
			}
		}
	$$resultR .= "</tbody></table><div>&nbsp;</div>";
	}

# Report if servers are UP DEAD etc.
# The WEBSOCKET server is just checked to see if it responds, so UP or DEAD.
sub ReportOnBackgroundServers {
	my ($resultR) = @_;
	my $backgroundServerTableId = CVal('BACKGROUND_SERVER_STATUS_TABLE');
	my $portHolderClass = CVal('PORT_STATUS_HOLDER_CLASS');

	my $srvrAddr = ServerAddress();
	
	$$resultR .= '<table id="' . $backgroundServerTableId . '"><caption><strong>Background servers</strong></caption><thead><tr>' .
		'<th onclick="sortTable(\'' . $backgroundServerTableId. '\', 0); backgroundSortColumn = 0;">Server program&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</th>' .
		'<th onclick="sortTable(\'' . $backgroundServerTableId. '\', 1); backgroundSortColumn = 1;">Name&nbsp;&nbsp;&nbsp;</th>' .
		'<th onclick="sortTable(\'' . $backgroundServerTableId. '\', 2); backgroundSortColumn = 2;">Port</th>' .
		'<th onclick="sortTable(\'' . $backgroundServerTableId. '\', 3); backgroundSortColumn = 3;">Status</th>' .
		'</tr></thead><tbody>' . "\n";	
	
	my $numServers = @BackgroundCommandLines;
	my $numBackgoundServers = $numServers;
	for (my $i = 0; $i < $numServers; ++$i)
		{
		if (defined($BackgroundProcIDs{$BackgroundCommandLines[$i]}))
			{
			my $port = $BackgroundCommandPorts[$i];
			my $cmdProper = $BackgroundCommandProgramNames[$i];
			my $name = $ShortBackgroundServerNameForPort{$port};
			my $procID = $BackgroundProcIDs{$BackgroundCommandLines[$i]};
			my $exitcode = 1;
			my $serverStatus = 'UP';
			$procID->GetExitCode($exitcode);
			my $statusImg = "<div class='led-green'></div>";
			if ( $exitcode eq STILL_ACTIVE )
				{
				# Don't pester the server if it has already said that it's starting.
				if (ServerOnPortIsStarting($port))
					{
					$serverStatus = 'STARTING UP';
					$statusImg = "<div class='led-yellow'></div>";
					}
				else
					{
					# business as usual, probably....
					if (!ShortServerNameIsUndergoingMaintenance($name))
						{
						my $stillResponding = ServerIsUp($srvrAddr, $port);
						if (!$stillResponding)
							{
							$serverStatus = 'NOT RESPONDING';
							$statusImg = "<div class='led-red'></div>";
							}
						}
					}
				}
			else
				{
				$serverStatus = 'DEAD';
				#$statusImg = "<img style='vertical-align:middle' src='square_red.jpg' width='15' height='15'>"; # red
				$statusImg = "<div class='led-red'></div>";
				}
			$$resultR .= "<tr><td>$cmdProper</td><td>$name</td><td><span class='$portHolderClass'>$port</span></td><td><div class='divAlignCenter'>$statusImg<div class='divAlignCenter'>&nbsp;$serverStatus</div></div></td></tr>\n"
			}
		}
	$$resultR .= '</tbody></table>' . "\n";
	}

sub AddSummaryLines {
	my ($resultR) = @_;
	
	my $numPageServers = @ServerCommandLines;
	my $numBackgoundServers = @BackgroundCommandLines;
	my $numberOfSwarmServers = $numPageServers + $numBackgoundServers;
	my $startTime = $StartTimeStamp;
	my $remoteEditPort =  CVal('INTRAMINE_FIRST_SWARM_SERVER_PORT');
	my $firstSwarmPort = $remoteEditPort + 1;
	my $numSwarmPorts = CVal('TOTAL_SWARM_PORTS_TO_MONITOR');
	my $lastSwarmPort = $firstSwarmPort + $numSwarmPorts - 1;
	my $mainPort = $port_listen;

	my $summary = "<table id='statusSummarytable'>";
	my $cellAlign = ''; #" class='right_cell'";
	$summary .= "<tr><td$cellAlign>Main port</td><td>$mainPort</td></tr>";
	$summary .= "<tr><td$cellAlign>Swarm ports</td><td>$firstSwarmPort .. $lastSwarmPort</td></tr>";
	$summary .= "<tr><td$cellAlign>Remote edit port</td><td>$remoteEditPort</td></tr>";
	$summary .= "<tr><td$cellAlign>Active servers</td><td>$numberOfSwarmServers</td></tr>";
	$summary .= "<tr><td$cellAlign>Session start</td><td>$startTime</td></tr>";
	$summary .= "</table>";
	
	$$resultR = $summary . $$resultR;
	}

sub IsShortName {
	my ($potentialShortName) = @_;
	my $result = (defined($CurrentlyUsedIndexForShortServerNames{$potentialShortName})) ? 1: 0;
	if (!$result)
		{
		$result = (defined($PortForShortBackgroundServerName{$potentialShortName})) ? 1: 0;
		}
	return($result);
	}

# The round robin. Return the next port number for a service. Of course, this only returns
# different port numbers for requests to a service if more than one instance of the
# service is running. Service on a port must be running, and preferably not undergoing maintenance.
# Called by RedirectBasedOnShortName().
sub NextPortForShortName {
	my ($shortName) = @_;
	my $currentIndex = $CurrentlyUsedIndexForShortServerNames{$shortName};
	my $numEntriesForShortName = NumServersTotalForShortName($shortName);
	my $portNumber = 0;
	
	if ($numEntriesForShortName > 1)
		{
		my $previousIndex = $currentIndex;
		my $proposedPort = 0;
		
		# Look for next server that's running and not under maintenance, drop out if wrapped.
		# I don't like do-while loops, just saying.
		my $foundAGoodPort = 0;
		do
			{
			++$currentIndex;
			if ($currentIndex > $numEntriesForShortName - 1)
				{
				$currentIndex = 0;
				}
			$proposedPort = $PortsForShortServerNames{$shortName}->[$currentIndex];
			if (ServerOnPortIsRunning($proposedPort)
				&& IndexOfShortServerNameUnderMaintenance($shortName) != $currentIndex)
				{
				$foundAGoodPort = 1;
				}
			} while ( $currentIndex != $previousIndex && !$foundAGoodPort );
		
		# Nothing? Try again, but allow server under maintenance.
		if (!$foundAGoodPort)
			{
			$currentIndex = $CurrentlyUsedIndexForShortServerNames{$shortName};
			do
				{
				++$currentIndex;
				if ($currentIndex > $numEntriesForShortName - 1)
					{
					$currentIndex = 0;
					}
				$proposedPort = $PortsForShortServerNames{$shortName}->[$currentIndex];
				if (ServerOnPortIsRunning($proposedPort))
					{
					$foundAGoodPort = 1;
					}
				} while ( $currentIndex != $previousIndex  && !$foundAGoodPort );
			}
		
		if ($foundAGoodPort)
			{
			$portNumber = $proposedPort;
			$CurrentlyUsedIndexForShortServerNames{$shortName} = $currentIndex;
			}
		}
	elsif ($numEntriesForShortName == 1)
		{
		my $proposedPort = $PortsForShortServerNames{$shortName}->[$currentIndex];
		# With only one server running, ignore being under maintenance. Still, there's
		# no point returning a real port number if the server is dead.
		if (ServerOnPortIsRunning($proposedPort))
			{
			$portNumber = $PortsForShortServerNames{$shortName}->[$currentIndex];
			}
		}
	
	if ($portNumber == 0)
		{
		Output("ERROR no ports active for short name |$shortName|!\n");
		}
	
	return($portNumber);
	}

sub IndexedPortForShortServerName {
	my ($shortName, $index) = @_;
	my $portNumber = 0;
	my $numEntriesForShortName = NumServersTotalForShortName($shortName);
	if ($index >= 0 && $index < $numEntriesForShortName)
		{
		$portNumber = $PortsForShortServerNames{$shortName}->[$index];
		}
	
	return($portNumber);
	}

sub NumServersTotalForShortName {
	my ($shortName) = @_;
	my $result = (defined( $PortsForShortServerNames{$shortName})) ?
						 @{$PortsForShortServerNames{$shortName}}: 0;
	return($result);
	}

sub PortForBackgroundShortServerName {
	my ($shortName) = @_;
	my $result = (defined($PortForShortBackgroundServerName{$shortName})) ?
					$PortForShortBackgroundServerName{$shortName}: 0;
	return($result);
	}

# Start up one additional server. Non BACKGROUND, non PERSISTENT. This lasts only for the
# current run of Intramine, for a permanent addition change the Count field for the server
# in data/serverlist.txt.
# See status.js#addServerSubmit() for a typical XMLHttpRequest() to add a server.
sub AddOneServer {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = 'ERROR unknown short server name!';
	if (defined($formH->{'shortname'}))
		{
		my $shortName = $formH->{'shortname'};
		if (IsShortName($shortName))
			{
			AddOneServerBasedOnShortName($shortName, \$result);
			}
		}
	
	return($result);
	}

sub AddOneServerBasedOnShortName {
	my ($shortName, $resultR) = @_;
	
	my $pageName = $PageNameForShortServerName{$shortName};
	my $pageIndex = $PageIndexForPageName{$pageName};
	my $numServersForPage = @{$PageServerNames[$pageIndex]};
	my $wsPort = WebSocketServerPort();
	
	for (my $srv = 0; $srv < $numServersForPage; ++$srv)
		{
		my $cmdShortName = $ShortServerNames[$pageIndex][$srv];
		if ($cmdShortName eq $shortName)
			{
			my $isPersistent = $PageIndexIsPersistent[$pageIndex];
			if (!$isPersistent)
				{
				my $currentPort = ++$HighestUsedServerPort;
				my $progamName = $PageServerNames[$pageIndex][$srv];
				my $scriptFullPath = $0;
				my $scriptFullDir = DirectoryFromPathTS($scriptFullPath);
				my $cmdLine = "$scriptFullDir$progamName $pageName $shortName $port_listen $currentPort $wsPort";
				push @ServerCommandLines, $cmdLine;
				push @ServerCommandProgramNames, $progamName;
				push @ServerCommandPorts, $currentPort;
				
				push @ServerCommandLinePageNames, $pageName;
				my $cmdIdx = @ServerCommandLines - 1;
				$PageIndexForCommandLineIndex[$cmdIdx] = $pageIndex;

				# For redirects, remember port list for each short server name.
				push @{$PortsForShortServerNames{$shortName}}, $currentPort;
				# And it's nice to have the other way too.
				$ShortServerNameForPort{$currentPort} = $shortName;
				# Remember it's running on the current port.
				SetServerPortIsRunning($currentPort, 1);
				
				ShutdownFirstExtraPortInUse();
				
				Output("   STARTING '$cmdLine' \n");
				my $proc;
				Win32::Process::Create($proc, $ENV{COMSPEC}, "/c $cmdLine", 0, 0, ".")
					|| die ServerErrorReport();
				$PageProcIDs{$cmdLine} = $proc;
				
				++$TotalServersWanted;
				
				$$resultR = 'OK';
				}
			last;
			}
		}
	}

# Start up a server on specific port that has been stopped.
sub StartOneServer {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = 'ERROR unknown port number!';
	if (defined($formH->{'portNumber'}))
		{
		my $portNumber = $formH->{'portNumber'};
		if (ServerOnPortIsStopped($portNumber))
			{
			StartOneServerBasedOnPort($portNumber, \$result);
			}
		}
		
	return($result);
	}

sub StartOneServerBasedOnPort {
	my ($portNumber, $resultR) = @_;
	my $shortName = (defined($ShortServerNameForPort{$portNumber})) ? $ShortServerNameForPort{$portNumber}: '';
	if ($shortName ne '') # just a double check, not really needed
		{
		my $cmdLine = '';
		my $numServers = @ServerCommandLines;
		for (my $i = 0; $i < $numServers; ++$i)
			{
			my $port = $ServerCommandPorts[$i];
			if ($port == $portNumber)
				{
				if (defined($PageProcIDs{$ServerCommandLines[$i]}))
					{
					$cmdLine = $ServerCommandLines[$i];
					last;
					}
				}
			}
		if ($cmdLine ne '')
			{
			Output("   (re)STARTING '$cmdLine' \n");
			my $proc;
			Win32::Process::Create($proc, $ENV{COMSPEC}, "/c $cmdLine", 0, 0, ".")
				|| die ServerErrorReport();
			$PageProcIDs{$cmdLine} = $proc;
			SetServerPortIsRunning($portNumber, 1);
			$$resultR = 'OK';
			}
		}
	}

# Stop a running server on specific port.
sub StopOneServer {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = 'ERROR unknown port number!';
	if (defined($formH->{'portNumber'}))
		{
		my $portNumber = $formH->{'portNumber'};
		if (ServerOnPortIsRunning($portNumber))
			{
			StopOneServerBasedOnPort($portNumber, \$result);
			}
		}
		
	return($result);
	}

sub StopOneServerBasedOnPort {
	my ($portNumber, $resultR) = @_;
	my $shortName = (defined($ShortServerNameForPort{$portNumber})) ? $ShortServerNameForPort{$portNumber}: '';
	if ($shortName ne '') # just a double check, not really needed
		{
		my $srvrAddr = ServerAddress();
		ForceStopServer($portNumber, $srvrAddr);
		SetServerPortIsRunning($portNumber, 0);
		$$resultR = 'OK';
		}
	}

# Stop then start a server on a specific port.
sub RestartOneServer {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = 'ERROR unknown port number!';
	if (defined($formH->{'portNumber'}))
		{
		my $portNumber = $formH->{'portNumber'};
		if (ServerOnPortIsRunning($portNumber))
			{
			StopOneServerBasedOnPort($portNumber, \$result);
			}
		StartOneServerBasedOnPort($portNumber, \$result);
		}
		
	return($result);
	}

sub SetServerPortIsRunning {
	my ($portNumber, $isRunning) = @_;
	$ServerPortIsRunning{$portNumber} = $isRunning; # 0 == stopped, 1 == running
	}

sub ServerOnPortIsStopped {
	my ($portNumber) = @_;
	my $result = (defined($ServerPortIsRunning{$portNumber})) ? ($ServerPortIsRunning{$portNumber} == 0): 1;
	return($result);
	}

sub ServerOnPortIsRunning {
	my ($portNumber) = @_;
	my $result = (defined($ServerPortIsRunning{$portNumber})) ? ($ServerPortIsRunning{$portNumber} == 1): 0;
	return($result);
	}
	
sub SetServerOnPortIsStarting {
	my ($portNumber, $isStarting) = @_;
	$ServerPortIsStarting{$portNumber} = $isStarting; # 0 == not in startup phase, 1 == starting
	}

sub SetAllServersToNotStarting {
	%ServerPortIsStarting = ();
	}

sub ServerOnPortIsStarting {
	my ($portNumber) = @_;
	my $result = (defined($ServerPortIsStarting{$portNumber})) ? ($ServerPortIsStarting{$portNumber} == 1): 0;
	return($result);
	}

sub HighestPortInUse {
	return($HighestUsedServerPort);
	}

# This responds to serverswarm.pm#ServiceIsRunning(), which translates the
# "yes"/"no" returned here into 1/0.
sub ServiceIsRunning {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = 'no';
	my $shortName = defined($formH->{'shortname'}) ? $formH->{'shortname'} : '';
	if ($shortName ne '')
		{
		my $numServicesRunning = (defined( $PortsForShortServerNames{$shortName})) ?
						 @{$PortsForShortServerNames{$shortName}}: 0;
		if ($numServicesRunning > 0)
			{
			for (my $i = 0; $i < $numServicesRunning; ++$i)
				{
				my $portNumber = $PortsForShortServerNames{$shortName}->[$i];
				my $isRunning = ServerOnPortIsRunning($portNumber);
				if ($isRunning)
					{
					$result = 'yes';
					last;
					}
				}
			}
		elsif (defined($PortForShortBackgroundServerName{$shortName}))
			{
			my $portNumber = $PortForShortBackgroundServerName{$shortName};
			if (ServerOnPortIsRunning($portNumber))
				{
				$result = 'yes';
				}
			}
		}
	
	return($result);
	}

# Some helpers for WEBSOCKET servers.
sub ShortNameIsForWEBSOCKServer {
	my ($shortName) = @_;
	my $result = defined($IsWEBSOCKETServer{$shortName}) ? 1 : 0;
	return($result);
	}

sub PortIsForWEBSOCKServer {
	my ($port) = @_;
	my $result = defined($PortIsForWEBSOCKETServer{$port}) ? 1 : 0;
	return($result);
	}

sub SetWebSocketServerPort {
	my ($port) = @_;
	$PrimaryWEBSOCKETPort = $port;
	}

sub WebSocketServerPort {
	return($PrimaryWEBSOCKETPort);
	}

# Set host and port for the WebSocket client.
sub InitWebSocketClient {
	
	# TEST ONLY OUT
	#return;
	
	my $srvrAddr = ServerAddress();
	foreach my $key (sort keys %PortIsForWEBSOCKETServer)
		{
		my $port = $key;
		InitWebSocket($srvrAddr, $port);
		last; # Start a client for the first one only.
		}
	}

sub SetMainSelfTest {
	my ($shouldTest) = @_;
	$MainSelfTest = $shouldTest;
	return($MainSelfTest);
	}

sub ShouldSelfTestMain {
	return($MainSelfTest);
	}
} ##### Swarm Server management


{ ##### Server address
my $ServerAddress;

# Get our (currently IPv4 only) server address, eg '192.168.40.8'.
# After, it can be retrieved with $addr = ServerAddress();
sub InitServerAddress {
	my ($S) = @_;
	
	my $ipaddr = GetReadableAddress($S);
	$ServerAddress = $ipaddr;
	print "Main Server IP: $ipaddr\n";

	# Save server address for use by other programs, as CVal('SERVER_ADDRESS');
	my %addrH;
	$addrH{'SERVER_ADDRESS'} = $ServerAddress;
	my $extraConfigName = 'SRVR';
	SaveExtraConfigValues($extraConfigName, \%addrH);
	}

# Look for an IPv4 address and convert it to human readable.
# If none found, take the last address seen (which will probably fail).
sub GetReadableAddress {
	my ($S) = @_;

	my $packdaddr = getsockname($S);
	my ($err, $hostname, $servicename) = Socket::getnameinfo($packdaddr);

	my ($error, @res) = Socket::getaddrinfo($hostname, $port_listen,
		{socktype => Socket::SOCK_RAW, flags => Socket::AI_PASSIVE});
	die "Cannot getaddrinfo - $error" if $error;
	my $bestI = -1;
	for (my $i = 0; $i < @res; ++$i)
		{
		#print("$i family: |$res[$i]->{family}|\n");
		my $fam = '';

		if ($res[$i]->{family} eq AF_INET)
			{
			$fam = '4';
			if ($bestI < 0)
				{
				$bestI = $i;
				}
			#last;
			#print("$i IPv4 addr: |$res[$i]->{addr}|\n");
			}
		else # IPv6
			{
			$fam = '6';
			#print("$i IPv6 addr: |$res[$i]->{addr}|\n");
			}

		# my ($err2, $ipaddr) = Socket::getnameinfo($res[$i]->{addr}, Socket::NI_NUMERICHOST, Socket::NIx_NOSERV);
		#print("$fam |$ipaddr|\n");
		}
		
	my ($err2, $ipaddr) = Socket::getnameinfo($res[$bestI]->{addr}, Socket::NI_NUMERICHOST, Socket::NIx_NOSERV);
	return($ipaddr);		
	}

sub ServerAddress {
	return($ServerAddress);
	}
} ##### Server address

{ ##### MainLoop and friends
my @listenerArray;
my $readable;
my %RequestAction;
my $Date; # YYYYMMDD

# For maintenance timeouts: if server is so busy that timeout is never triggered, force a call to
# DoMaintenance() if more than $timeout seconds has elapsed.
my $LastPeriodicCallTime;

# If no time is supplied, use "now".
sub SetLastPeriodicCallTime {
	my ($lrt) = @_;
	$lrt ||= time;
	$LastPeriodicCallTime = $lrt;
	}

sub GetLastPeriodicCallTime {
	return($LastPeriodicCallTime);
	}

sub GetCurrentTime {
	my $ct = time;
	return($ct);
	}

# Handle all requests until 'EXITEXITEXIT' or 'FORCEEXIT' is received.
# Maintenance, if any, is done about once a minute. Currently just a check for date change.
# Most of the real work is done by Respond below, which in turn calls GrabArguments and ResultPage.
sub MainLoop {
	my ($port_listen) = @_;
	
	my $maintenanceTimeoutSeconds = 60;
	
	$Date = DateYYYYMMDD();
	
	# Handle http://host:port/Viewer/?req=redirect etc.
	SetUpRequestActionHandlers();
	
	$readable = IO::Select->new;     # Create a new IO::Select object
	
	AddAllListeners($readable);
	
	SetLastPeriodicCallTime();
	
	# Start WEBSOCKET client. Only for the first WEBSOCKET server seen (lowest port number,
	# and that's the first one in the data/serverlist.txt list).
	#print("Main starting WEBSOCKET client.\n");
	InitWebSocketClient();
	
	$WebSockIsUp = WebSocketSend("Main first call to WS");
	
	# Warn if WS not up, might be someone upgrading.
	if (!$WebSockIsUp)
		{
		print("ERROR, the WEBSOCKET server intramine_websockets.pl is not running!\n");
		print("No likely cause for that, sorry.\n");
		}
	
	my %InputLines; # $InputLines->{$s}[$i] = an input line for $s, first line is incoming address
	
	while(1)
		{
		my ($ready) = IO::Select->select($readable, undef, undef, $maintenanceTimeoutSeconds);
		
		my $forcePeriodic = 0;
		if (!defined($ready))
			{
			DoMaintenance();
			SetLastPeriodicCallTime();
			}
		else
			{
			my $ct = GetCurrentTime;
			my $lastTime = GetLastPeriodicCallTime();
			if ($ct - $lastTime >= $maintenanceTimeoutSeconds)
				{
				$forcePeriodic = 1;
				}
			}
		
		foreach my $sock (@$ready)
			{
			# New connection?
			my $theListenerOrBlank = SockIsInListenerList($sock);
			if ($theListenerOrBlank ne '' && $sock == $theListenerOrBlank)
				{
				AcceptNewConnection($theListenerOrBlank, \%InputLines);
				}
			else
				{
				if (!HandleEstablishedConnection($sock, \%InputLines))
					{
					return;
					}
				}
			} # foreach my $sock (@$ready)
		
		if ($forcePeriodic)
			{
			DoMaintenance();
			SetLastPeriodicCallTime();
			}
		} # while(1)
	}

sub AcceptNewConnection {
	my ($newReadySocket, $InputLinesH) = @_;
	# Accept the connection and add it to our readable list.
	my ($new_sock, $iaddr) = $newReadySocket->accept;
	$readable->add($new_sock) if $new_sock;
	my($port,$inaddr) = sockaddr_in($iaddr);
	my $thePeerAddress = inet_ntoa($inaddr);
	Output("NEW SOCKET, accepted request from $thePeerAddress\n");
	$InputLinesH->{$new_sock}[0] = $thePeerAddress;
	binmode $new_sock;
	}

sub HandleEstablishedConnection {
	my ($sock, $InputLinesH) = @_;
	my $buff;
	my $closed = 0;
	my $contentLengthSeen = 0; # content-length
	my $contentLengthExpected = 0;
	my $emptyLineSeen = 0;
	my $contentLengthReceived = 0;
	my $posted = '';
	my $result = 1; # Exit requests return 0, meaning the whole server is done.
	
	while ($buff=<$sock>)
		{
		push @{$InputLinesH->{$sock}}, $buff;
		Output("Rcvd: |$buff|\n");
		
		if ($emptyLineSeen)
			{
			$contentLengthReceived += length($buff);
			my $buffCopy = $buff;
			chomp($buffCopy);
			$posted .= $buffCopy;
			}
	
		if ($buff =~ m!EXITEXITEXIT! && $buff !~ m!req\=!)
			{
			if (ExitExitExitObeyed($sock))
				{
				return(0);
				}
			}
		elsif ($buff =~ m!FORCEEXIT! && $buff !~ m!req\=!)
			{
			ForceExit($sock);
			return(0);
			}
		elsif ($buff =~ m!content-length!i) # "content-length: $cl \r\n";
			{
			$contentLengthSeen = 1;
			RecordContentLength($buff, \$contentLengthExpected);
			}
		elsif ($buff =~ m!^\s*$!)
			{
			$emptyLineSeen = 1;
			$contentLengthReceived = $sock->read($posted, $contentLengthExpected); # data for POST request
			}
		
		if ( $emptyLineSeen
			&& (($contentLengthSeen && $contentLengthReceived >= $contentLengthExpected)
			|| (!$contentLengthSeen)) )
			{
			RespondNormally($sock, $InputLinesH, $posted);
			$closed = 1;
			last;
			}
		}
	
	if (!$closed)
		{
		RespondToUnexpectedClose($sock, $InputLinesH, $posted);
		$closed = 1;
		}
	
	return(1);
	}

sub ExitExitExitObeyed {
	my ($sock) = @_;
	my $result = 1;
	
	if ($IGNOREEXITREQUEST)
		{
		Output("EXITEXITEXIT received - ignoring.\n");
		$result = 0;
		}
	else
		{
		print $sock "Ouch\r\n";
		$readable->remove($sock);
		$sock->close;
		StopAllSwarmServers();
		sleep(1);
		Output("EXITEXITEXIT bye!\n");
		print("$SERVERNAME EXITEXITEXIT bye!\n");
		}
	
	return($result);
	}

sub ForceExit {
	my ($sock) = @_;
	
	$readable->remove($sock);
	$sock->close;
	ForceStopAllSwarmServers();
	sleep(1);
	Output("FORCEEXIT bye!\n");
	print("$SERVERNAME FORCEEXIT bye!\n");
	}

sub RecordContentLength {
	my ($buff, $contentLengthExpectedR) = @_;
	
	$buff =~ m!\s(\d+)!;
	$$contentLengthExpectedR = $1;
	}

sub RespondNormally {
	my ($sock, $InputLinesH, $posted) = @_;
	
	Output("Finished receiving normally, will close\n");
	
	Output("Copy of received lines:\n-----------------\n");
	my $numLines = defined($InputLinesH->{$sock}[0]) ?  @{$InputLinesH->{$sock}}: 0;
	for (my $i = 0; $i < $numLines; ++$i)
		{
		Output("|$InputLinesH->{$sock}[$i]|\n");
		}
	Output("-----------------\n");
	
	Respond($sock, \@{$InputLinesH->{$sock}}, $posted);
	Output("Normal connection close after response\n");
	
	$readable->remove($sock);
	$sock->close;
	@{$InputLinesH->{$sock}} = ();
	delete $InputLinesH->{$sock};
	
	if ($CommandServerHasBeenNotified)
		{
		RestartCommandServers();
		$CommandServerHasBeenNotified = 0;
		$CommandServersHaveBeenRestarted = 1;
		}
	}

sub RespondToUnexpectedClose {
	my ($sock, $InputLinesH, $posted) = @_;
	Output("UNEXPECTED END OF INPUT, responding and closing anyway\n");
	Respond($sock, \@{$InputLinesH->{$sock}}, $posted);
	$readable->remove($sock);
	$sock->close;
	Output("UNEXPECTED END OF INPUT, copy of received lines after close:\n-----------------\n");
	my $numLines = defined($InputLinesH->{$sock}[0]) ?  @{$InputLinesH->{$sock}}: 0;
	for (my $i = 0; $i < $numLines; ++$i)
		{
		Output("|$InputLinesH->{$sock}[$i]|");
		}
	Output("-----------------\n");
	@{$InputLinesH->{$sock}} = ();
	delete $InputLinesH->{$sock};
	}

# Set up handlers for http://host:port/Viewer/?req=redirect etc.
sub SetUpRequestActionHandlers {
	$RequestAction{'req|redirect'} = \&RedirectToCorrectedPort; # req=redirect
	$RequestAction{'req|add_one_specific_server'} = \&AddOneServer; 		# $obj holds server short name
	$RequestAction{'req|start_one_specific_server'} = \&StartOneServer; 	# $obj holds server port
	$RequestAction{'req|stop_one_specific_server'} = \&StopOneServer; 		# $obj holds server port
	$RequestAction{'req|restart_one_specific_server'} = \&RestartOneServer; # $obj holds server port
	$RequestAction{'req|ruthere'} = \&RUThere; 					# req=ruthere
	$RequestAction{'req|serverstatus'} = \&ServerStatus; 		# req=serverstatus
	$RequestAction{'req|running'} = \&ServiceIsRunning; 		# req=running
	$RequestAction{'req|id'} = \&Identify; 						# req=id
	$RequestAction{'signal'} = \&BroadcastSignal; 				# signal=anything
	$RequestAction{'ssinfo'} = \&ReceiveInfo; 					# ssinfo=anything, eg 'ssinfo=serverUp'
	}

# Add listeners for main port (us) and all unused swarm server ports.
sub AddAllListeners {
	my ($readable) = @_;

	my $listener = 
  		IO::Socket::INET->new( LocalPort => $port_listen, Listen => SOMAXCONN, ReuseAddr => 1 );
	die "Can't create socket on port $port_listen for listening: $!" unless $listener;
	$readable->add($listener);          # Add the listener to it
	push @listenerArray, $listener;
	
	# Add listeners for $HighestUsedServerPort+1 up, so total of swarm ports listened to
	# is TOTAL_SWARM_PORTS_TO_MONITOR.
	# TOTAL_SWARM_PORTS_TO_MONITOR is in data\intramine_config.txt, default value 48.
	my $firstFreePort = HighestPortInUse() + 1;
	my $totalSwarmPortsToMonitor = CVal('TOTAL_SWARM_PORTS_TO_MONITOR') + 0;
	my $numSwarmPortsInUse = $firstFreePort - $kSwarmServerStartingPort;
	my $numExtraPortsToMonitor = $totalSwarmPortsToMonitor - $numSwarmPortsInUse;
	if ($numExtraPortsToMonitor < 0)
		{
		$numExtraPortsToMonitor = 0;
		}
	for (my $port = $firstFreePort; $port < $firstFreePort + $numExtraPortsToMonitor; ++$port)
		{
		my $listener = 
	  		IO::Socket::INET->new( LocalPort => $port, Listen => 20, ReuseAddr => 1 );
		die "Can't create socket on port $port for listening: $!" unless $listener;
		$readable->add($listener);          # Add the listener to it
		push @listenerArray, $listener;
		}
	Output("$SERVERNAME: listening for connections on port $port_listen\n");
	
	InitServerAddress($listener);	
	}

# Port monitored here is either the main port (default 81) or one of the unused swarm
# server ports.
sub SockIsInListenerList {
	my ($sock) = @_;
	my $result = '';
	my $numListeners = @listenerArray;
	for (my $i = 0; $i < $numListeners; ++$i)
		{
		if ($listenerArray[$i] ne '' && $sock == $listenerArray[$i])
			{
			$result = $listenerArray[$i];
			last;
			}
		}
	
	return($result);
	}

# Free up the lowest extra port that MainLoop is listening to, it will become
# the port for our added server. The lowest entry 0 is our main port (eg),
# first extra port is at index 1 in @listenerArray. There may be several
# added servers, so shut down the first one after 0 that isn't ''.
sub ShutdownFirstExtraPortInUse {
	my $result = 0;
	my $numListeners = @listenerArray;
	for (my $i = 1; $i < $numListeners; ++$i)
		{
		if ($listenerArray[$i] ne '')
			{
			$readable->remove($listenerArray[$i]);
			shutdown($listenerArray[$i], 2);
			$listenerArray[$i] = '';
			$result = 1;
			last;
			}
		}
	
	return($result);
	}

# Send back full HTTP response. Headers are minimal.
# "Access-Control-Allow-Origin: *" is important, it helps with traffic between servers
# when doing XMLHttpRequest calls from one swarm server to another.
sub Respond {
	my ($s, $arr, $posted) = @_;
	Output("Responding\n");
	
	my $mimeType = '';
	my $numInputLines = @$arr;
	if ($numInputLines >= 2)
		{
		my $clientAddr = $arr->[0];
		my %form;
		my $isOptionsRequest = 0;
		GrabArguments($arr, $posted, \%form, \$isOptionsRequest);
		
		if (!($IGNOREEXITREQUEST && defined($form{'EXITEXITEXIT'})))
			{
			if ($isOptionsRequest)
				{
				print $s "HTTP/1.1 200 OK\r\n";
				print $s "Server: $SERVERNAME\r\n";
				print $s "Cache-Control: public\r\n";
				print $s "Allow: GET,POST,OPTIONS\r\n";
				print $s "Access-Control-Allow-Methods: GET,POST,OPTIONS\r\n";
				print $s "Access-Control-Allow-Origin: *\r\n";
				print $s "Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With\r\n";
				}
			else
				{
				my $contents = ResultPage($arr, \%form, $clientAddr, \$mimeType);
				my $cl = length($contents);
				if ($cl)
					{
					print $s "HTTP/1.1 200 OK\r\n";
					print $s "Server: $SERVERNAME\r\n";
					print $s "Cache-Control: public\r\n";
					if ($mimeType ne '')
						{
						print $s "Content-Type: $mimeType\r\n";
						}
					print $s "content-length: $cl \r\n";
					print $s "Allow: GET,POST,OPTIONS\r\n";
					print $s "Access-Control-Allow-Origin: *\r\n";
					print $s "Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With\r\n";
					print $s "\r\n";
					print $s "$contents";
					}
				else
					{
					Output("ERROR, no content found, returning 404\n");
					print $s "HTTP/1.1 404 Not Found\r\n";
					print $s "Access-Control-Allow-Origin: *\r\n";
					print("404 MAIN |@$arr|\n");
					}
				}
			}
		}
	else
		{
		Output("ERROR, nothing received from client, returning 404\n");
		print $s "HTTP/1.1 404 Not Found\r\n";
		}
	Output("END RESPONSE\n");
	}

# GET /path/?one=two&three=another HTTP/1.0
# or
# POST /path HTTP/1.0 blankline one=two&three=another
sub GrabArguments {
	my ($arr, $posted, $formH, $isOptionsR) = @_;
	my $obj = $arr->[1];
	
	# Get headers.
	my $numReqLines = @$arr;
	for (my $i = 2; $i < $numReqLines; ++$i)
		{
		my $value = $arr->[$i];
		if ($value =~ m!^([a-zA-Z0-9-]+):!)
			{
			my $headerName = $1;
			my $headerVal = $value;
			$headerVal =~ s!^[a-zA-Z0-9-]+:\s*!!;
			$formH->{$headerName} = $headerVal;
			}
		}
	
	my $doingPost = 0; # post contents can sometimes? be encoded twice for some unknown reason.
	my @parts = split(" ", $obj);
	if (@parts == 3)
		{
		$formH->{METHOD} = $parts[0];
		$formH->{OBJECT} = $parts[1];
		my $arguments = '';
		
		if ($formH->{METHOD} =~ m!post!i)
			{
			$arguments = $posted;
			$doingPost = 1;
			}
		elsif ($formH->{METHOD} =~ m!options!i)
			{
			$$isOptionsR = 1;
			Output("OPTIONS request\n");
			# Ignore arguments.
			}
		else # get
			{
			my $pastQidx = index($parts[1], '?') + 1;
			$arguments = ($pastQidx > 0) ? substr($parts[1], $pastQidx) : '';
			}
		
		if ($arguments ne '')
			{
			my @pairs = split(/&/, $arguments);
			# Then for each name/value pair....
			foreach my $pair (@pairs)
				{
				# Separate the name and value:
				my ($name, $value) = split(/=/, $pair);
				# Convert + signs to spaces:
				$value =~ tr/+/ /;
				# Convert hex pairs (%HH) to ASCII characters:
				$value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
				if ($doingPost)
					{
					# Decode again, just in case. I think.
					$value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
					}
				# Store values in a hash:
				$formH->{$name} = $value;
				} 
			}
		}
	else
		{
		my $numParts = @parts;
		Output("ERROR num parts is $numParts!\n");
		Output(" - obj received was |$obj|\n");
		}
	}

# Return JS to change window.location for redirects, or various content for a request
# based on 'req=...' such as req=redirect, req=id.
# req=redirect is explicitly sent by swarm servers when a server can't handle a request,
# and the resulting redirect here sends the request to the right server, based on the
# unique short server name such as 'Search' at the start of the request. A redirect also
# happens if main here receives a request that should obviously be handled by a
# different server, eg something like
# http://192.168.1.132:81/Files
# will be redirected to 
# http://192.168.1.132:43128/Files
# (assuming main here is on port 81, and the 'Files' server is on port 43128).
# req=ruthere and req=id are sent by swarm servers, response is just server name and port.
sub ResultPage {
	my ($arr, $formH, $peeraddress, $mimeTypeR) = @_;
	my $result = '';
	my $obj = $formH->{OBJECT};
	
	my $requestHandled = 0;
	
	# Handle redirects up front.
	if ($obj =~ m!^/(\w+)(/|$)!)
		{
		my $potentialShortName = $1;
		if (IsShortName($potentialShortName))
			{
			Output("Redirecting \$obj |$obj|\n");
			$result = RedirectBasedOnShortName($obj, $potentialShortName);
			$$mimeTypeR = CVal('html');
			$requestHandled = 1;
			}
		}
	
	if (!$requestHandled)
		{
		foreach my $nameValue (keys %RequestAction)
			{
			my @keyParts = split(/\|/, $nameValue);
			my $namePart = $keyParts[0];
			my $optionalValuePart = (defined($keyParts[1])) ? $keyParts[1]: '';
			# Eg $formH->{'href'} = path to file, or $formH->{'req'} eq 'id'
			if ( defined($formH->{$namePart})
			 && ($optionalValuePart eq '' || $optionalValuePart eq $formH->{$namePart}) )
				{
				Output(" for $nameValue.\n");
				$result = $RequestAction{$nameValue}->($obj, $formH, $peeraddress);
				$requestHandled = 1;
				last;
				}
			}
		}

	if ($requestHandled)
		{
		$$mimeTypeR = CVal('html');
		}
	else
		{
		GetResultFromFile($obj, \$result, \$mimeTypeR);
		}
	
	Output("ResultPage bottom, Raw \$obj: |$obj|\n");
	return $result;	
	}

# CSS JS images.
# Note this version of GetResultFromFile() doesn't try as hard as
# swarmserver.pm#GetResultFromFile(), there should be very few
# file requests that go through Main.
sub GetResultFromFile {
	my ($obj, $result_R, $mimeTypeR_R) = @_;

	# Image: try supplied path first, else look in our web server images folder
	# eg |/C:/perlprogs/mine/images_for_web_server/110.gif|
	# (.ico is needed, all the rest is not needed methinks)
	if ($obj =~ m!\.(gif|jpe?g|png|ico|webp)$!i)
		{
		my $ext = lc($1);
		Output("for image: |$obj|\n");
		my $filePath = $obj;
		$filePath =~ s!^/!!; # vs substr($obj, 1);
		#print("Image file path: |$filePath|\n");
		my $gotIt = 0;
		if (-f $filePath)
			{
			#print("Got it!\n");
			$gotIt = 1;
			$$result_R = GetBinFile($filePath);
			}
		
		if (!$gotIt)
			{
			#print("Image open of |$filePath| FAILED, falling back to images folder\n");
			$obj =~ m!/([^/]+)$!;
			my $filePath = $IMAGES_DIR . $1;
			$$result_R = GetBinFile($filePath);
			}
		$$$mimeTypeR_R = CVal($ext);
		}
	elsif ($obj =~ m!\.css$!i)
		{
		Output(" for CSS.\n");
		$obj =~ m!/([^/]+)$!;
		my $filePath = $CSS_DIR . $1;
		$$result_R = GetTextFile($filePath);
		$$$mimeTypeR_R = CVal('css');
		}
	elsif ($obj =~ m!\.js$!i)
		{
		Output(" for JS.\n");
		$obj =~ m!/([^/]+)$!;
		my $filePath = $JS_DIR . $1;
		$$result_R = GetTextFile($filePath);
		$$$mimeTypeR_R = CVal('js');
		}
	elsif ($obj =~ m!\.ttf$!i)
		{
		Output(" for FONT.\n");
		$obj =~ m!/([^/]+)$!;
		my $filePath = $FONT_DIR . $1;
		$$result_R = GetBinFile($filePath);
		$$$mimeTypeR_R = CVal('ttf');
		}
	}

sub Identify {
	my ($obj, $formH, $peeraddress) = @_;
	my $portNumber = $port_listen;
	my $srvrAddr = ServerAddress();
	my $result = "$SERVERNAME on $srvrAddr:$portNumber";
	
	return($result);
	}

# Respond to req=ruthere from a command server, which is waiting for restart.
sub RUThere {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = Identify($obj, $formH, $peeraddress);
	
	# Ok to restart command servers after responding to this
	# - but just to be safe, only do it once - after all how many times should
	# we be restarting during a session? Once, methinks.
	if (!$CommandServersHaveBeenRestarted)
		{
		$CommandServerHasBeenNotified = 1; 
		}
	
	return($result);
	}

# Called once a minute or so, check for important changes such as change of date.
sub DoMaintenance {
	HandleDateChange();
	
	# Call WebSocketReceiveAllMessages() periodically (currently one a minute)
	# to "drain" all pending WebSockets messages.
	#print("About to call WebSocketReceiveAllMessages\n");
	my $numMessagesSeen = WebSocketReceiveAllMessages();
	}

sub HandleDateChange {
	# Compare last known date against current date. If changed, broadcast 'signal=dayHasChanged'.
	my $currentDate = DateYYYYMMDD();
	if ($Date != $currentDate)
		{
		$Date = $currentDate;
		BroadcastDateHasChanged();
		}
	}

# 'send 'signal=dayHasChanged' to all servers. ToDo responds by recalculating the
# number of overdue pending ToDo items.
sub BroadcastDateHasChanged {
	my %form;
	$form{'signal'} = 'dayHasChanged';
	my $ob = '/?signal=dayHasChanged';
	my $ignoredPeerAddress = '';
	BroadcastSignal($ob, \%form, $ignoredPeerAddress);
	}

} ##### MainLoop and friends

sub GetBinFile {
	my ($filePath) = @_;
	return(ReadBinFileWide($filePath));
	}

sub GetTextFile {
	my ($filePath) = @_;
	my $result = ReadTextFileWide($filePath);
	if (!defined($result))
		{
		$result = '';
		}
	
	return($result);
	}

sub RedirectTemplateForShortName {
	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<script type="text/javascript">
	window.location = "http://_THEHOST_:_THEPORT__ARGS_";
</script>
</head><body></body></html>
FINIS

	return($theBody);
	}

# Redirect to port that's handling requests based on short name (Search, Viewer etc).
# However if it's a "req=portNumber" request, just return a current port number for the short name.
sub RedirectBasedOnShortName {
	my ($obj, $shortName) = @_;
	
	my $goodPort = NextPortForShortName($shortName);
	if (!$goodPort)
		{
		$goodPort = PortForBackgroundShortServerName($shortName);
		}
	
	my $serverAddr = ServerAddress();
	my $theBody = '';
	if ($goodPort == 0) # No port available for $shortName service.
		{
		$theBody = 'Not up!';
		}
	elsif ($obj =~ m!req=portNumber!)
		{
		$theBody = $goodPort;
		}
	else
		{
		$theBody = RedirectTemplateForShortName();
		$theBody =~ s!_THEHOST_!$serverAddr!;
		$theBody =~ s!_THEPORT_!$goodPort!;
		# If $obj ends with $shortName and optional trailing slash, and nothing else,
		# tack on '/?req=main' on the assumption it's a "main" page.
		if ($obj =~ m!/$shortName$!)
			{
			$obj .= '/?req=main';
			}
		elsif ($obj =~ m!/$shortName/$!)
			{
			$obj .= '?req=main';
			}
			
		$obj = encode_utf8($obj);
		
		$theBody =~ s!_ARGS_!$obj!;
		}
	
	return($theBody);
	}

{##### TESTING
my $NumServersUnderTest;
my $NumServersFinishedTesting;
my $TotalFailures;

# Tell all servers to start testing. When a server is finished testing, we'll get a signal back,
# 'signal=done_testing', and when all done are TestingIsComplete() will be called and we'll
# wrap things up.
# Limit tests to one instance per Short name, in case two or more instances of the service
# are running.
sub RunAllTests {
	$NumServersUnderTest = 0;
	$NumServersFinishedTesting = 0;
	$TotalFailures = 0;
	
	print("TESTING BEGINS\n");
	if (ShouldSelfTestMain())
		{
		RunMainTests(); # This is us
		}
	
	my $firstSwarmPort = SwarmServerFirstPort();
	my $lastSwarmPort = HighestPortInUse();
	my %shortNameTested;
	
	for (my $port = $firstSwarmPort; $port <= $lastSwarmPort; ++$port)
		{
		my $shortName = ShortServerNameForPort($port);
		if (!defined($shortNameTested{$shortName}))
			{
			$shortNameTested{$shortName} = 1;
			my $initialResponse = TestOneServer($shortName, $port);
			if ($initialResponse =~ m!ok!i)
				{
				# Tests are running on $shorName.
				++$NumServersUnderTest;
				}
			else
				{
				print("Skipping $shortName server, test program did not start properly.\n");
				}
			}
		}
	}
	
sub RunMainTests {
	print("############## Internal Main tests #################\n");
	
	my @errors;
	
	# Check we have Page names.
	my $pgA = GetPageNames();
	my $numPages = @$pgA;
	if ($numPages == 0)
		{
		push @errors, "GetPageNames() returned an empty array.";
		}
	my $testServerName = CVal('INTRAMINE_TEST_NAME');
	my $haveTestName = 0;
	for (my $i = 0; $i < $numPages; ++$i)
		{
		if ($pgA->[$i] eq $testServerName)
			{
			$haveTestName = 1;
			last;
			}
		}
	if (!$haveTestName)
		{
		push @errors, "$testServerName not found in Page names.";
		}
	
	# Check Short names.
	$haveTestName = IsShortName($testServerName);
	if (!$haveTestName)
		{
		push @errors, "$testServerName not found in Short names.";
		}
	
	# Test adding a server.
	my %formH;
	$formH{'shortname'} = $testServerName;
	my $result = AddOneServer('', \%formH, '');
	if ($result ne 'OK')
		{
		push @errors, "Could not ADD an instance of $testServerName.";
		}
	# Test stopping a server.
	my $testPortNumber = NextPortForShortName($testServerName);
	$formH{'portNumber'} = $testPortNumber;
	$result = StopOneServer('', \%formH, '');
	if ($result ne 'OK')
		{
		push @errors, "Could not STOP instance of $testServerName on port $testPortNumber.";
		}
	# Test starting a server.
	$result = StartOneServer('', \%formH, '');
	if ($result ne 'OK')
		{
		push @errors, "Could not RESTART instance of $testServerName on port $testPortNumber.";
		}
	
	# Stop the added server.
	StopOneServer('', \%formH, '');
	
	# Run a maintenance test. test_MainTest.pl will check to see how things went.
	# This isn't a full test, MainLoop() is busy so it can't pick up on backinservice
	# signals. We send one backinservice for each instance of the test service, hoping
	# the first one will trigger maintenance of the second test service and the second one
	# will end maintenance of the service.
	%formH = ();
	$formH{'signal'} = 'testMaintenance';
	$formH{'name'} = $testServerName;
	my $ob = '/?signal=testMaintenance';
	BroadcastSignal($ob, \%formH, '');
	$formH{'signal'} = 'backinservice';
	BroadcastSignal($ob, \%formH, '');
	BroadcastSignal($ob, \%formH, '');
	
	if (ShortServerNameIsUndergoingMaintenance($testServerName))
		{
		push @errors, "$testServerName not removed from maintenance.";
		}
	
	sleep(2); # Allow maintenance to happen in the test services
	
	print("############## End Internal Main tests #############\n");
	}

sub TestOneServer {
	my ($shortName, $port) = @_;
	print("Testing $shortName on port $port\n");
	my $serverAddress = ServerAddress();
	
	my $remote = IO::Socket::INET->new(
	                Proto   => 'tcp',       		# protocol
	                PeerAddr=> $serverAddress, 		# Address of server
	                PeerPort=> "$port"      		# port of server typ. 43124..up
	                ) or (ServerErrorReport() && return(''));
	
	#print $remote "GET /?req=test HTTP/1.1\n\n"; 		# Argument-based approach
	print $remote "GET /$shortName/test/ HTTP/1.1\n\n"; # A more RESTful approach.
	
	my $response = '';
	my $line = <$remote>; 	# 200 OK typically to start off the response
	
	# We want the lines after a blank line.	
	my $collectingResults = 0;
	while (defined($line))
		{
		chomp($line);
		if ($collectingResults)
			{
			if ($response eq '')
				{
				$response = $line;
				}
			else
				{
				$response .= "\n$line";
				}
			}
		if ($line=~ m!^\s*$!)
			{
			$collectingResults = 1;
			}
		$line = <$remote>;
		}
		
	return($response);
	}
	
sub ServerTestIsDone {
	my ($formH) = @_;
	my $shortName = defined($formH->{'shortname'}) ? $formH->{'shortname'}: 'UNKNOWN SERVER';
	my $testResults = defined($formH->{'result'}) ? $formH->{'result'} : '(NO RESULTS REPORTED)';
	
	if ($testResults eq 'ok')
		{
		print("-----\n$shortName OK\n-----\n");
		}
	else
		{
		my @errors = split(/__SEP__/, $testResults);
		my $count = @errors;
		print("-----\n");
		my $testWord = ($count > 1) ? 'tests' : 'test';
		print("$shortName failed $count $testWord:\n");
		for (my $i = 0; $i < $count; ++$i)
			{
			print("$errors[$i]\n");
			}
		print("-----\n");
		$TotalFailures += $count;
		}
	
	++$NumServersFinishedTesting;
	if ($NumServersFinishedTesting >= $NumServersUnderTest)
		{
		TestingIsComplete();
		}
	}

sub TestingIsComplete {
	if ($TotalFailures)
		{
		my $testWord = ($TotalFailures > 1) ? 'tests' : 'test';
		print("\nTESTING ENDS - $TotalFailures $testWord failed!\n\n");
		}
	else
		{
		print("\nTESTING ENDS - all tests passed.\n\n");
		}
	ForceStopAllSwarmServers();
	system( 'pause' ); # Press any key to continue
	exit(0);
	}
} ##### TESTING
