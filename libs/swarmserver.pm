# swarmserver.pm: the common server core for swarm servers.
# See eg intramine_boilerplate.pl for a simple example of using this module. There, it consists
# of calling SSInitialize(), setting up request actions, and then calling MainLoop(), passing
# it the request actions. boilerplate's port is then listened to, and a registered request
# action is called when MainLoop() receives an incoming HTTP request.
# A call to TopNav() will build the top navigation bar for a standard IntraMine web page,
# see eg intramine_boilerplate.pl#ThePage().
# Most of this module deals with the tedium of listening for and responding to HTTP requests.
# If you look at a couple of the supplied servers, such as the aforementioned "boiler plate" and
# intramine_db_example.pl you'll see how to use this module.
# Then later if you decide to do something heroic like port IntraMine to go, well I've tried to
# make the code below readable. I really did try.
 
# perl -c C:/perlprogs/IntraMine/libs/swarmserver.pm

package swarmserver;
require Exporter;
use Exporter qw(import);
use strict;
use warnings;
use utf8;
use Time::HiRes qw ( time );
use HTML::Entities;
use FileHandle;
use IO::Socket;
use IO::Select;
use Win32::Process;
use Win32::API;
use Win32API::File qw( getLogicalDrives GetVolumeInformation );
use File::Slurp;
use Scalar::Util 'refaddr';
use Encode;
use URI::Escape;
use URI::Encode qw(uri_encode uri_decode);
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
#use lib ".";
use common;
use LogFile;	# For logging - log files are closed between writes.
use intramine_config;
use win_wide_filepaths;
use intramine_websockets_client;

my $QUICKDRIVELIST = 1; # Set to 0 for slower but more accurate list

{ ##### Server address
my $ServerAddress;

# Called by MainLoop() below, to determine server's local IP address eg 192.168.0.14.
# The address saved by intramine_main.pl when it starts up is preferred.
sub InitServerAddress {
	my ($S) = @_;
	
	$ServerAddress = CVal('SERVER_ADDRESS');
	if ($ServerAddress eq '')
		{
		print("Server address not found, calling GetReadableAddress().\n");
		my $ipaddr = GetReadableAddress($S);
		$ServerAddress = $ipaddr;
		}
	
	#print "Swarmserver Server IP: $ServerAddress\n";
	}

# Look for an IPv4 address and convert it to human readable.
# If none found, take the last address seen (which will probably fail).
sub GetReadableAddress {
	my ($S) = @_;

	my $packdaddr = getsockname($S);
	my ($err, $hostname, $servicename) = Socket::getnameinfo($packdaddr);

	my $mainPort = MainServerPort();
	my ($error, @res) = Socket::getaddrinfo($hostname, $mainPort,
		{socktype => Socket::SOCK_RAW, flags => Socket::AI_PASSIVE});
	die "Cannot getaddrinfo - $error" if $error;
	my $bestI = -1;
	for (my $i = 0; $i < @res; ++$i)
		{
		#print("$i family: |$res[$i]->{family}|\n");

		if ($res[$i]->{family} eq AF_INET)
			{
			$bestI = $i;
			last;
			;#print("$i IPv4 addr: |$res[$i]->{addr}|\n");
			}
		else # IPv6
			{
			;#print("$i IPv6 addr: |$res[$i]->{addr}|\n");
			}

		# my ($err2, $ipaddr) = Socket::getnameinfo($res[$i]->{addr}, Socket::NI_NUMERICHOST, Socket::NIx_NOSERV);
		# print("|$ipaddr|\n");
		}
		
	my ($err2, $ipaddr) = Socket::getnameinfo($res[$bestI]->{addr}, Socket::NI_NUMERICHOST, Socket::NIx_NOSERV);
	return($ipaddr);		
	}

sub ServerAddress {
	return($ServerAddress);
	}
} ##### Server address

{ ##### Server List and TopNav()
my $NumServerPages;				# Count of main pages Search, File, Days etc
my @PageNames;					# $PageNames[1] = 'Files' indexed by page  == @GroupNameForIdx

my %ShortServerNames;			# A list of the short names, so we can recogize them and redirect if the name is not for us.
my %ShortServerNamesType;		# 'PERSISTENT', 'BACKGROUND', or ''
my %PageIsPersistent;			# $PageIsPersistent{'Cmd'} = 1 means it survives a shutdown so it can continue monitoring status - this is mainly for the "Cmd" page
my @PageIndexIsPersistent;		# $PageIndexIsPersistent[n] = 1 means associated Page is persistent, see line above
# A 'zombie' service has a count of 0 in serverlist.txt. It won't be started when
# this Main service starts, but will be available for starting on the Status page.
my %ShortNameIsForZombie; # $ShortNameIsForZombie{'Reindex'} = 1; undef if not a zombie.

my $TopNavTemplate;

# LoadServerList:
# Load up servers from the serverlist.txt file. The format there is
# Count<tabs>Page name<tabs>Short name<tabs>Perl program name [optional <tabs> 'PERSISTENT' or 'BACKGROUND']
# "Count" is the number of instances to start for the server.
# The "Page name" and "Short name" are used to tell one server for another. Servers can have
# the same Page name, but must have unique Short names. If the Page name and Short name are
# the same, then it's a "top level" page server, meaning it will show up in IntraMine's
# top navigation bar.
# If Page has more than one associated program then the main program should be listed first,
# followed on separate lines by associated program names, with the Page name repeated, eg
# 1	Search				Search		intramine_search.pl
# 1	Search				Viewer		intramine_viewer.pl
# 1	Search				Linker		intramine_linker.pl
# 1	Search				Opener		intramine_open_with.pl
# 1	Search				Editor		intramine_editor.pl
# The "Cmd" page is special, the associated server is not shut down in response to a routine
# restart request (EXITEXITEXIT) so that it can continue monitoring during the restart.
# This "feature" however can be safely ignored.
# The serverlist.txt entry for it is
# 1	Cmd					Cmd			intramine_commandserver.pl	PERSISTENT
# with the (optional) 'PERSISTENT' signalling that it should be treated specially.
# See $CommandServerHasBeenNotified etc.
# An entry with trailing 'BACKGROUND' signals a server that has no top navigation entry. Eg
# 1	FILEWATCHER			Watcher		intramine_filewatcher.pl	BACKGROUND
# There can be only one of each BACKGROUND server, and it can't be stopped using the Status page.
sub LoadServerList {
	if (NumPages())
		{
		return; # prevent an accidental double load
		}
	my $configFilePath = FullDirectoryPath('SERVERLISTPATH');
	my $count = 0;
	
	if (-f $configFilePath)
		{
		my $fileH = FileHandle->new("$configFilePath") or
									die("No config file found at |$configFilePath|!\n");
		my $line;
		my $pageIndex = 0;
		my $previousPageName = '';
		while ($line = <$fileH>)
	    	{
	        chomp($line);
	        # Skip blank lines and comments as we load in the details for each 
			# server. Zero count page services are loaded as "zombie" services,
			# listed but not enabled.
	        if (length($line) && $line !~ m!^\s*(#|$)!)
	        	{
				my $isZombie = ($line =~ m!^0\s!);
	        	my @fields = split(/\t+/, $line); # Split on one or more tabs
	        	my $instanceCount = $fields[0];
	        	my $pageName = $fields[1];
	        	my $shortServerName = $fields[2];
	        	$ShortServerNames{$shortServerName} += 1;
	        	$ShortServerNamesType{$shortServerName} = '';
				if ($isZombie)
					{
					$ShortNameIsForZombie{$shortServerName} = 1;
					}

	        	my $serverProgramName = $fields[3];
	        	my $specialType = (defined($fields[4])) ? $fields[4]: '';
	        	# Skip BACKGROUND servers (they have no web pages, just lurk darkly).
	        	if ($specialType ne 'BACKGROUND' && $specialType ne 'WEBSOCKET')
	        		{
		        	if ($pageName ne $previousPageName && $pageName eq $shortServerName)
		        		{
		        		if ($previousPageName ne '')
		        			{
		         			++$pageIndex;
		       				}
		        		push @PageNames, $pageName;
		         		}
		         	#$PageIndexForPage_ServerName{$pageName . '_' . $serverProgramName} = $pageIndex;
		        	if ($specialType eq 'PERSISTENT')
		        		{
		        		$PageIsPersistent{$pageName} = 1; # eg "Cmd" server, will ignore regular 'EXITEXITEXIT' requests so it can monitor during restart
		        		$PageIndexIsPersistent[$pageIndex] = 1;
		        		$ShortServerNamesType{$shortServerName} = 'PERSISTENT';
		        		}
		        	elsif (!defined($PageIndexIsPersistent[$pageIndex]))
		        		{
		        		$PageIndexIsPersistent[$pageIndex] = 0;
		        		}
		        	$previousPageName = $pageName;
		         	++$count;
	        		}
	        	else
	        		{
	        		$ShortServerNamesType{$shortServerName} = 'BACKGROUND';
	        		}
	        	}
	        }
	    close $fileH;
	
		if ($count == 0)
			{
			die("ERROR could not load config file |$configFilePath|!\n");
			}
		else
			{
			$NumServerPages = @PageNames;
			}
		}
	else
		{
		die("No config file found at |$configFilePath|!\n");
		}

	return($count);
	}

# Set $TopNavTemplate.
sub MakeTopNavTemplate {
	my ($forRefresh) = @_;
	my $theTopNav = "\n";
	if (!$forRefresh)
		{
		$theTopNav = "<ul id='nav'>\n";
		}
	
	for (my $pgIdx = 0; $pgIdx < @PageNames; ++$pgIdx)
		{
		my $pageName = $PageNames[$pgIdx];
		my $entry;
		# Discover if the $pageName server has any running instances.
		my $count = NumInstancesOfShortNameRunning($pageName);
		my $hideShowClass = ($count <= 0) ? ' class="navHidden"': '';
		#my $zombieClass = ($ShortNameIsForZombie{$pageName}) ? ' class=navHidden': '';
		#my $disabled = ($ShortNameIsForZombie{$pageName}) ? ' disabled': '';
		if ($pageName =~ m!todo!i)
			{
			my $overdueCount = ToDoOverdueCount();
			my $overdue = ($overdueCount > 0) ? " [$overdueCount]": '';
			$entry = "<li$pageName$hideShowClass><a href='_RESTRICTED_$pageName'>$pageName$overdue</a></li>\n";
			}
		else
			{
			$entry = "<li$pageName$hideShowClass><a href='_RESTRICTED_$pageName'>$pageName</a></li>\n";
			}
		$theTopNav .= $entry;
		}
	if (!$forRefresh)
		{
		$theTopNav .= "<div id='spinnerParent'><img id='spinner' src='globe.gif' width='30.0' height='24.0' /></div>\n";
		$theTopNav .= "</ul>\n";
		$theTopNav .= "<div class='shimclear'></div>\n";
		}
	else
		{
		$theTopNav .= "<div id='spinnerParent'>" . "<a href='./" . "contents.html" . "' target='_blank'>"
		. "<img id='spinner' src='question4-44.png' width='30.0' height='24.0' /></a></div>\n";
		}

	$TopNavTemplate = $theTopNav;
	}

sub TopNavTemplate {
	my ($forRefresh) = @_;
	$forRefresh ||= 0;

	MakeTopNavTemplate($forRefresh);
	return($TopNavTemplate);
	}

# Navigation bar at the top of each page. Current page is highlighted. Any standard
# IntraMine server that wants an entry in the top navigation bar should call this.
sub TopNav {
	my ($currentPageName) = @_; # $PAGENAME in swarm server, eg my $PAGENAME = 'Cmd';

	my $theTopNav = TopNavTemplate();

	my $FULL_ACCESS_STR = CVal('FULL_ACCESS_STR');
	my $mainServerIP = ServerAddress();
	my $mainServerPort = MainServerPort();
	$theTopNav =~ s!_RESTRICTED_!http://$mainServerIP:$mainServerPort/${FULL_ACCESS_STR}!g;
	# Set current page.
	$theTopNav =~ s!$currentPageName!$currentPageName class=\"current\"!;
	$theTopNav =~ s!<li\w+!<li!g;

	return $theTopNav;
	}

# For refreshing the top navigation bar, like above TopNav()
# but leave off the <ul> wrapper.
sub TopNavForRefresh {
	my ($obj, $formH, $peeraddress) = @_; # Not used

	my $forRefresh = 1;
	my $theTopNav = TopNavTemplate($forRefresh);
	my $currentPageName =  OurPageName();

	my $FULL_ACCESS_STR = CVal('FULL_ACCESS_STR');
	my $mainServerIP = ServerAddress();
	my $mainServerPort = MainServerPort();
	$theTopNav =~ s!_RESTRICTED_!http://$mainServerIP:$mainServerPort/${FULL_ACCESS_STR}!g;
	# Set current page.
	$theTopNav =~ s!$currentPageName!$currentPageName class=\"current\"!;
	$theTopNav =~ s!<li\w+!<li!g;

	return $theTopNav;
	}

sub NumPages {
	my $numPages = @PageNames;
	return($numPages);
	}

sub SetToDoOverdueCount {
	my ($count) = @_;
	SetCVal('OverdueCount', $count);
	}

sub ToDoOverdueCount {
	my $val = CVal('OverdueCount');
	return($val);
	}

sub PageIsPersistent {
	my ($pgName) = @_;
	my $result = defined($PageIsPersistent{$pgName}) ? 1 : 0;
	return($result);
	}

sub IsShortServerName {
	my ($name) = @_;
	my $result = defined($ShortServerNames{$name}) ? 1 : 0;
	return($result);
	}

sub GetShortServerNamesType {
	my ($serverNamesH) = @_;
	%{$serverNamesH} = %ShortServerNamesType;
	}
} ##### Server List and TopNav()

{ ##### MainLoop and friends
my %ReqActions;			# Request actions, supplied via MainLoop().
my $IgnoreExitRequest;
my $MainPort;
my $OurPort;
# Log and print:
my $kLOGMESSAGES;
my $kDISPLAYMESSAGES;
my $OutputLog = undef;

# 'Search', 'Files' etc, name of Nav Page for the group that server belongs to.
# For background server, this is the 'short name'.
my $OurPageName;
# A (fairly) distinctive name for the current server,
# eg 'Viewer' for intramine_viewer.pl under the 'Search' page.
my $OurShortName;
my $IMAGES_DIR;
my $COMMON_IMAGES_DIR;
my $CSS_DIR;
my $JS_DIR;
my $FONT_DIR;
my $JSEDITOR_DIR;
my $HIGHLIGHT_DIR;
my $HELP_DIR;
my $DEFAULT_UPLOAD_DIR;
my $DefaultDir; # for HTML pages off disk, the dir containing the file
my $PreviousRefererDir;

# Send messages to any activity monitor.
my $ActivityMonitorShortName;
my %socketForClientId;
my $readable; # sockets

# WebSocket handling requires knowing the port that the WS server is running on.
# This is supplied as the last argument on the command line for a server program.
my $WebSocketPort;
my $WebSockIsUp;

# SSInitialize: call this at the start of every IntraMine server, page or background. Except
# the Main server intramine_main.pl, of course. See any server program for an example.
# Passing undef here as an arg means "not interested in the value."
# Background servers have no associated page names, so pass undef for the $pageNameR
# in those cases. Normally all other parameters are of interest.
sub SSInitialize {
	my ($pageNameR, $shortNameR, $serverPortR, $listeningPortR) = @_;
	GrabParameter($pageNameR);
	SetOurPageName($$pageNameR);
	GrabParameter($shortNameR);
	SetOurShortName($$shortNameR);
	GrabParameter($serverPortR);
	$MainPort = $$serverPortR;
	GrabParameter($listeningPortR);
	$OurPort = $$listeningPortR;
	
	WebSocketPortInitialize();
	
	binmode(STDOUT, ":unix:utf8");
	
	# Set the console code page to UTF8
	my $SetConsoleOutputCP = Win32::API->new( 'kernel32.dll', 'SetConsoleOutputCP', 'N','N' );
	$SetConsoleOutputCP->Call(65001);

	SetCommonOutput(\&Output);			# common.pm
	# A wee sleep to allow Main to set any additional config values.
	sleep(1);
	LoadConfigValues($$shortNameR, 'SRVR');		# intramine_config.pm
	}

sub GrabParameter {
	my($paramR) = @_;
	my $value = shift @ARGV;
	if (defined($paramR))
		{
		$$paramR = $value;
		}
	}

sub WebSocketPortInitialize {
	GrabParameter(\$WebSocketPort);
	if (!defined($WebSocketPort))
		{
		$WebSocketPort = 0;
		}
	}

# Call StartNewLog() before any Output() calls.
# $kLOGMESSAGES: 1 == log and print ($DISPLAYMESSAGES is ignored). 0 == don't log or print.
# $kDISPLAYMESSAGES: 1 == print, if $kLOGMESSAGES == 0, don't print otherwise.
# 0 == don't print (ignored if $kLOGMESSAGES == 1).
sub StartNewLog {
	my ($kLogMessages, $kDisplayMessages) = @_;
	$kLOGMESSAGES = $kLogMessages;
	$kDISPLAYMESSAGES = $kDisplayMessages;
	$OutputLog = undef;
	
	if ($kLOGMESSAGES)
		{
		my $LogDir = FullDirectoryPath('LogDir');
		my $logDate = DateTimeForFileName();
		my $LogPath = $LogDir . "$OurShortName $OurPort $logDate.txt";
		print("LogPath: |$LogPath|\n");
		MakeDirectoriesForFile($LogPath);
		$OutputLog = LogFile->new($LogPath);
		$OutputLog->Echo($kDISPLAYMESSAGES); # 1 == also print to console
		}
	}

# Print, to cmd line or log file.
# $kLOGMESSAGES: 1 == log and print ($DISPLAYMESSAGES is ignored). 0 == don't log or print.
# $kDISPLAYMESSAGES: 1 == print, if $kLOGMESSAGES == 0, don't print otherwise.
# 0 == don't print (ignored if $kLOGMESSAGES == 1).
sub Output {
	my ($text) = @_;
	if ($kLOGMESSAGES)
		{
		$OutputLog->Log("$OurShortName: $text");
		}
	elsif ($kDISPLAYMESSAGES)
		{
		print("$OurShortName: $text");
		}
	}

sub LogPath {
	my $logPath = defined($OutputLog) ? $OutputLog->Path(): undef;
	return($logPath);
	}

# This is the port that the Main round-robin server is running on, eg 81.
sub MainServerPort {
	return($MainPort);
	}

# Put the ports and short name at the bottom of a body.
# And sseServerShortName
sub PutPortsAndShortnameAtEndOfBody {
	my ($theBodyR) = @_;
	my $portsAndShortName = PortsAndShortNameForJavaScript();
	$$theBodyR =~ s!</body>\s*</html>\s*$!$portsAndShortName</body></html>!;
	}

# Some "canned" JavaScript giving:
# current server IP or "server address" (eg 192.168.132)
# port for main IntraMine server (eg 81)
# port for server using this instance of swarmserver (eg 43125).
# "theHost" is an alias for mainIP that I'm too lazy to remove.
sub PortsAndShortNameForJavaScript {
	my $result = <<'FINIS';

<script>
let theMainPort = '_THEMAINPORT_';
let mainIP = '_THEHOST_';
let theHost = mainIP;
let shortServerName = '_SHORTSERVERNAME_';
let sseServerShortName = 'SSE_SERVER_SHORT_NAME';
// Added for talking to the WebSockets server
let wsShortName = 'WS';
let ourSSListeningPort = '_OURSSLISTENINGPORT_';
</script>

FINIS

	my $host = ServerAddress();
	my $sseServerShortName = CVal('ACTIVITY_MONITOR_SHORT_NAME');
	$result =~ s!_THEMAINPORT_!$MainPort!;
	$result =~ s!_THEHOST_!$host!g;
	$result =~ s!_SHORTSERVERNAME_!$OurShortName!;
	$result =~ s!SSE_SERVER_SHORT_NAME!$sseServerShortName!;
	my $port = OurListeningPort();
	$result =~ s!_OURSSLISTENINGPORT_!$port!;

	return($result);
	}

# MainLoop(\%RequestAction, $timeout, $DoPeriodic, $callbackInit):
# Don't poke Identify into %RequestAction for 'req|id', ServerIdentify is added for you just below.
# GetRequestedFile() is also defined here, no need for a copy in the swarmserver proper.
# If $timeout is undef (not supplied as an argument), we will loop here forever. If there is a timeout
# supplied, MainLoop will call $DoPeriodic() after the timeout if there are no pending requests,
# and then keep going, also forever.
# If $timeout is supplied then $DoPeriodic must also be supplied.
# If $callbackInit is supplied then $timeout, $DoPeriodic should be supplied as undef
# if they aren't wanted, to keep params in their proper places (I know, that's lazy).
# Requires: call SSInitialize() before calling this sub.
sub MainLoop {
	my ($requestActionH, $timeout, $DoPeriodic, $callbackInit) = @_;
	
	if (defined($timeout) && !defined($DoPeriodic))
		{
		die("$OurShortName fatal error, \$timeout is defined but \$DoPeriodic is not defined. $!");
		}
	
	LoadServerList();
	SetToDoOverdueCount(0);
	
	# As shipped only the 'Cmd' page is PERSISTENT - see data/serverlist.txt.
	my $pgName = OurPageName(); 					# As set by SSInitialize()
	$IgnoreExitRequest = PageIsPersistent($pgName);	# Determined in LoadServerList()
	
	# Copy request actions, 'req|main' etc.
	%ReqActions = %$requestActionH;
	
	$IMAGES_DIR = FullDirectoryPath('IMAGES_DIR');
	$COMMON_IMAGES_DIR = CVal('COMMON_IMAGES_DIR');
	if (FileOrDirExistsWide($COMMON_IMAGES_DIR) != 2)
		{
		$COMMON_IMAGES_DIR = '';
		}
	$CSS_DIR = FullDirectoryPath('CSS_DIR');
	# Trim trailing slash from $CSS_DIR, typically an incoming $obj in ResultPage() has a leading slash.
	$CSS_DIR =~ s!/$!!;	
	$JS_DIR = FullDirectoryPath('JS_DIR');
	# Trim trailing slash from $JS_DIR, typically an incoming $obj in ResultPage() has a leading slash.
	$JS_DIR =~ s!/$!!;
	$FONT_DIR = FullDirectoryPath('FONT_DIR');
	$FONT_DIR =~ s!/$!!;
	$HELP_DIR = FullDirectoryPath('HELP_DIR');
	$JSEDITOR_DIR = FullDirectoryPath('JSEDITOR_DIR'); # for the tinymce or ace or codemirror or whatnot editor
	$HIGHLIGHT_DIR = FullDirectoryPath('HIGHLIGHT_DIR'); # for highlight.js
	$DEFAULT_UPLOAD_DIR = FullDirectoryPath('DEFAULT_UPLOAD_DIR'); # for file uploads to the server box
	$DefaultDir = '';
	$PreviousRefererDir = '';
	$ActivityMonitorShortName = CVal('ACTIVITY_MONITOR_SHORT_NAME'); # default 'SSE'
	
	# Simple "id yourself" requests are handled for all servers here, returning server name.
	if (!defined($ReqActions{'req|id'}))
		{
		$ReqActions{'req|id'} = \&ServerIdentify;
		}
	
	# Top nav bar refresh, called after IntraMine restarts (restart.js#refreshNavBar()).
	if (!defined($ReqActions{'req|navbar'}))
		{
		$ReqActions{'req|navbar'} = \&TopNavForRefresh;
		}

	# Default handler for 'signal' broadcasts: the default is called first, then any
	# server-specific 'signal' handler.
	$ReqActions{'SIGNAL'} = \&DefaultBroadcastHandler;
	
	# Handle for configuration value requests from JavaScript.
	# req=configvalueforjs&key='the_key'
	$ReqActions{'req|configvalueforjs'} = \&ConfigValue;
	

	# Set up to listen for requests on $OurPort.
	my $listener = 
  		IO::Socket::INET->new( LocalPort => $OurPort, Listen => SOMAXCONN, ReuseAddr => 1 );
	die "Can't create socket for listening: $!" unless $listener;
	Output("$OurShortName: Listening for connections on port $OurPort\n");
	
	$readable = IO::Select->new;     # Create a new IO::Select object
	$readable->add($listener);          # Add the listener to it
	InitServerAddress($listener);

	# Start up WebSocket communications.
	InitWebSocketClient();
	my $sname = OurShortName();
	$WebSockIsUp = WebSocketSend("$sname checking in");
	
	
	if (defined($callbackInit))
		{
		# Speak to main if there is an init callback that might take some time, we are starting up.
		# During this phase the Status page will show the server as "STARTING UP".
		# See eg the MainLoop() call in intramine_linker.pl.
		RequestBroadcast('ssinfo=starting&port=' . $OurPort);
		$callbackInit->();
		}

	# We are started at this point, let the main server know. See intramine_main.pl#ReceiveInfo().
	RequestBroadcast('ssinfo=serverUp&port=' . $OurPort);
	
	SetLastPeriodicCallTime();
	
	# Over to main loop proper.
	my %InputLines; # $InputLines->{$s}[$i] = an input line for $s, first line is incoming address
	_MainLoop($listener, $readable, \%InputLines, $timeout, $DoPeriodic);
	}

# Listen forever, until an "EXIT" request.
# Handle GET, POST and OPTIONS requests. When things go well, RespondNormally()
# handles the request and returns a response.
sub _MainLoop {
	my ($listener, $readable, $InputLinesH, $timeout, $DoPeriodic) = @_;
		
	while(1)
		{
		my ($ready) = IO::Select->select($readable, undef, undef, $timeout);
		
		my $forcePeriodic = 0;
		# If we timed out, caller wants to do something.
		if (defined($timeout))
			{
			if (!defined($ready))
				{
				if (defined($DoPeriodic))
					{
					$DoPeriodic->();
					}
								
				SetLastPeriodicCallTime();
				}
			else
				{
				my $ct = GetCurrentTime();
				my $lastTime = GetLastPeriodicCallTime();
				if ($ct - $lastTime >= $timeout)
					{
					$forcePeriodic = 1;
					}
				}
			}

		foreach my $sock (@$ready)
			{
			# New connection?
			if ($sock == $listener)
				{
				# Accept the connection and add it to our readable list.
				AcceptNewConnection($readable, $sock, $InputLinesH);
				}
			else # It's an established connection
				{
				my $buff;
				my $closed = 0;
				my $contentLengthSeen = 0; # content-length
				my $contentLengthExpected = 0;
				my $emptyLineSeen = 0;
				my $contentLengthReceived = 0;
				my $posted = '';
				my $multiPartFormPostBoundary = '';
				while ($buff=<$sock>)
					{
					push @{$InputLinesH->{$sock}}, $buff;
					
					if ($emptyLineSeen)
						{
						$contentLengthReceived += length($buff);
						my $buffCopy = $buff;
						chomp($buffCopy);
						$posted .= $buffCopy;
						}

					# The command server ignores EXIT requests - it stays around to monitor main server
					# if the main server sends an EXITEXITEXIT request here while stopping.
					# Note format of request, the '=1' is needed: "GET /?EXITEXITEXIT=1 HTTP/1.1\n\n"
					if ($buff =~ m!EXITEXITEXIT! && $buff !~ m!req\=!)
						{
						if (ExitExitExitObeyed($readable, $sock))
							{
							return;
							}
						}
					# HOWEVER, all servers obey a 'FORCEEXIT'.
					elsif ($buff =~ m!FORCEEXIT! && $buff !~ m!req\=!)
						{
						ForceExit($readable, $sock);
						return;
						}
					elsif ($buff =~ m!^content-length!i) # "content-length: $cl \r\n";
						{
						$contentLengthSeen = 1;
						RecordContentLength($buff, \$contentLengthExpected);
						}
					elsif ($buff =~ m!^Content-Type:\s+multipart/form-data;\s+boundary=(.+?)$!i)
						{ # Content-Type: multipart/form-data; boundary=----WebKitFormBoundaryFPkwxXjlBimbXHzJ
						$multiPartFormPostBoundary = $1;
						$multiPartFormPostBoundary =~ s/\R/\n/g;
						chomp($multiPartFormPostBoundary);
						}
					elsif ($buff =~ m!^\s*$!)
						{
						$emptyLineSeen = 1;
						$contentLengthReceived = $sock->read($posted, $contentLengthExpected);
						}
					
					if ( $emptyLineSeen && (($contentLengthSeen
											&& $contentLengthReceived >= $contentLengthExpected)
										|| (!$contentLengthSeen)) )
						{
						RespondNormally($readable, \$closed, $sock, $InputLinesH, $posted, $multiPartFormPostBoundary);
						last;
						}
					} # while ($buff...)
				
				if (!$closed)
					{
					RespondToUnexpectedClose($readable, \$closed, $sock, $InputLinesH, $posted, $multiPartFormPostBoundary);
					}
				}
			}
		
		# If we have fallen behind, force $DoPeriodic() to run.
		if ($forcePeriodic)
			{
			if (defined($DoPeriodic))
				{
				$DoPeriodic->();
				}

			SetLastPeriodicCallTime();
			}
		}	
	}

sub AcceptNewConnection {
	my ($readable, $newReadySocket, $InputLinesH) = @_;
	
	my ($new_sock, $iaddr) = $newReadySocket->accept;
	$readable->add($new_sock) if $new_sock;
	my($port,$inaddr) = sockaddr_in($iaddr);
	my $thePeerAddress = inet_ntoa($inaddr);
	Output("NEW SOCKET, accepted request from $thePeerAddress:$port\n");
	$InputLinesH->{$new_sock}[0] = $thePeerAddress;
	binmode $new_sock;
	}

sub ExitExitExitObeyed {
	my ($readable, $sock) = @_;
	my $result = 1;
	
	if ($IgnoreExitRequest)
		{
		Output("EXITEXITEXIT received - ignoring.\n");
		$result = 0;
		# See also Respond() - which doesn't respond in this case.
		}
	else
		{
		print $sock "Ouch\r\n";
		$readable->remove($sock);
		$sock->close;
		Output("EXITEXITEXIT bye!\n");
		print("$OurShortName EXITEXITEXIT bye!\n");
		}
	
	return($result);
	}

sub ForceExit {
	my ($readable, $sock) = @_;
	
	$readable->remove($sock);
	$sock->close;
	Output("FORCEEXIT bye!\n");
	print("$OurShortName FORCEEXIT bye!\n");
	}

sub RecordContentLength {
	my ($buff, $contentLengthExpectedR) = @_;
	
	$buff =~ m!\s(\d+)!;
	$$contentLengthExpectedR = $1;
	}

sub RespondNormally {
	my ($readable, $closedR, $sock, $InputLinesH, $posted, $multiPartFormPostBoundary) = @_;
	
	Output("Finished receiving normally, will close\n");
	
	Output("Copy of received lines:\n-----------------\n");
	my $numLines = defined($InputLinesH->{$sock}[0]) ?  @{$InputLinesH->{$sock}}: 0;
	for (my $i = 0; $i < $numLines; ++$i)
		{
		Output("|$InputLinesH->{$sock}[$i]|");
		}
	Output("-----------------\n");
		
	my $reportShortName = '';
	Respond(\$reportShortName, $readable, $sock, \@{$InputLinesH->{$sock}},
			$posted, $multiPartFormPostBoundary);
	
	Output("Normal connection close after response\n");
	$$closedR = 1;
	$readable->remove($sock);
	$sock->close;
	# Delete {$sock} array
	@{$InputLinesH->{$sock}} = ();
	delete $InputLinesH->{$sock};
	
	# Activity reporting is now mostly done in the JS web client.
	#ReportActivity($reportShortName) if ($ActivityMonitorShortName ne '' && $reportShortName ne '');
	}

sub RespondToUnexpectedClose {
	my ($readable, $closedR, $sock, $InputLinesH, $posted, $multiPartFormPostBoundary) = @_;
	
	Output("UNEXPECTED END OF INPUT, responding and closing anyway\n");
	my $reportShortName = '';
	Respond(\$reportShortName, $readable, $sock, \@{$InputLinesH->{$sock}},
			$posted, $multiPartFormPostBoundary);
	
	$$closedR = 1;
	$readable->remove($sock);
	$sock->close;
	Output("UNEXPECTED END OF INPUT, copy of received lines after close:\n-----------------\n");
	my $numLines = defined($InputLinesH->{$sock}[0]) ?  @{$InputLinesH->{$sock}}: 0;
	for (my $i = 0; $i < $numLines; ++$i)
		{
		Output("|$InputLinesH->{$sock}[$i]|");
		}
	Output("-----------------\n");
	# Delete {$sock} array
	@{$InputLinesH->{$sock}} = ();
	delete $InputLinesH->{$sock};
	
		
	# Activity reporting is now mostly done in the JS web client.
	#ReportActivity($reportShortName) if ($ActivityMonitorShortName ne '' && $reportShortName ne '');
	}

# Send back ResultPage(), with a few headers. Also handle just a request for options.
# Server-Sent Events for a socket are also initialized.
sub Respond {
	my ($reportItR, $readable, $s, $arr, $posted, $multiPartFormPostBoundary) = @_;
	Output("Responding\n");
	
	my $mimeType = '';
	my $numInputLines = @$arr;
	if ($numInputLines >= 2)
		{
		my $clientAddr = $arr->[0];
		my %form;
		my $isOptionsRequest = 0;
		#my $isSSERequest = 0;
		GrabArguments($arr, $posted, $multiPartFormPostBoundary, \%form, \$isOptionsRequest);
		
		if (!($IgnoreExitRequest && defined($form{'EXITEXITEXIT'})))
			{
			if ($isOptionsRequest)
				{
				print $s "HTTP/1.1 200 OK\r\n";
				print $s "Server: $OurShortName\r\n";
				print $s "Cache-Control: public\r\n";
				print $s "Allow: GET,POST,OPTIONS,DELETE\r\n";
				print $s "Access-Control-Allow-Methods: GET,POST,OPTIONS,DELETE\r\n";
				# HEAD deleted, it was sometimes doubling Viewer file load times.
#				print $s "Allow: GET,POST,OPTIONS,DELETE,HEAD\r\n";
#				print $s "Access-Control-Allow-Methods: GET,POST,OPTIONS,DELETE,HEAD\r\n";
				print $s "Access-Control-Allow-Origin: *\r\n";
				print $s "Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With\r\n";
				}
			#else # use this instead of the elsif if you want HEAD requests
			elsif (!(defined($form{'METHOD'}) && $form{'METHOD'} =~ m!head!i))
				{
				# HEAD handling: unfortunately, IntraMine's Viewer
				# is not able to handle HEAD requests well, because the size of the file
				# returned has to be calculated by creating the actual stream to return,
				# and a HEAD followed by GET can double the file load time. If you want to
				# handle HEAD requests, this sub and ResultPage() will need modifying.
				
				my @extraHeaders;
				# Hack, put \@extraHeaders into %form under key 'EXTRAHEADERSA' 
				$form{'EXTRAHEADERSA'} = \@extraHeaders;
				
				my $contents = ResultPage($reportItR, $arr, \%form, $clientAddr, \$mimeType);
				
				my $cl = length($contents);
				if ($cl)
					{
					print $s "HTTP/1.1 200 OK\r\n";
					print $s "Server: $OurShortName\r\n";
					print $s "Cache-Control: public\r\n";
					print $s "Allow: GET,POST,OPTIONS,DELETE\r\n";
					print $s "Access-Control-Allow-Methods: GET,POST,OPTIONS,DELETE\r\n";
#					print $s "Allow: GET,POST,OPTIONS,DELETE,HEAD\r\n";
#					print $s "Access-Control-Allow-Methods: GET,POST,OPTIONS,DELETE,HEAD\r\n";
					if ($mimeType ne '')
						{
						# @extraHeaders might supply a Content-Type override, don't duplicate it.
						my $haveMimeTypeOverride = 0;
						for (my $i = 0; $i < @extraHeaders; ++$i)
							{
							if ($extraHeaders[$i] =~ m!^content-type!i)
								{
								$haveMimeTypeOverride = 1;
								last;
								}
							}
						if (!$haveMimeTypeOverride)
							{
							print $s "Content-Type: $mimeType\r\n";
							}
						}
					print $s "content-length: $cl \r\n";
					print $s "Access-Control-Allow-Origin: *\r\n";
					print $s "Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With\r\n";
					for (my $i = 0; $i < @extraHeaders; ++$i)
						{
						print $s "$extraHeaders[$i]\r\n";
						}
					print $s "\r\n";
					# HEAD request handling: this is just the last piece. If you want to
					# deal with HEAD requests, ResultPage() should also be modified to return
					# the anticipated length of $contents somehow, and not return the full $contents.
					if ($form{'METHOD'} !~ m!head!i)
						{
						print $s "$contents";
						}
					}
				else
					{
					Output("ERROR, no content found, returning 404\n");
					print $s "HTTP/1.1 404 Not Found\r\n";
					print("404 |$arr->[1]|\n");
					}
				}
			else # delete this 'else' if you want to handle HEAD requests
				{
				# We have no HEAD, alas.
				print $s "HTTP/1.1 405 Method Not Allowed\r\n";
				print $s "Allow: GET,POST,OPTIONS,DELETE\r\n";
				print $s "Access-Control-Allow-Methods: GET,POST,OPTIONS,DELETE\r\n";
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
	my ($arr, $posted, $multiPartFormPostBoundary, $formH, $isOptionsR) = @_;
	my $obj = $arr->[1];
	
	# Grab Referer href if any, and headers in general.
	my $numReqLines = @$arr;
	for (my $i = 2; $i < $numReqLines; ++$i)
		{
		my $value = $arr->[$i];
		# Any headers.
		if ($value =~ m!^([a-zA-Z0-9-]+):!)
			{
			my $headerName = $1;
			my $headerVal = $value;
			$headerVal =~ s!^[a-zA-Z0-9-]+:\s*!!;
			$formH->{$headerName} = $headerVal;
			}
		# Look for Referer href=path.
		if ($value =~ m!Referer:!)
			{
			GetReferer($value, $formH);
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
			# Have your cake and eat it too, as the saying goes. We also check for "get" style arguments,
			# if it's a "Content-Type: multipart/form-data;" post.
			if ($multiPartFormPostBoundary ne '')
				{
				my $pastQidx = index($parts[1], '?') + 1;
				$arguments = ($pastQidx > 0) ? substr($parts[1], $pastQidx) : '';
				
				if (!GetPostedFileArguments(\$posted, $multiPartFormPostBoundary, $formH))
					{
					Output("ERROR could not decipher multipart/form-data form data post |$posted|!\n");
					}
				}
			else
				{
				$arguments = $posted;
				$doingPost = 1;
				}
			}
		elsif ($formH->{METHOD} =~ m!options!i)
			{
			$$isOptionsR = 1;
			}
		else # get
			{
			my $pastQidx = index($parts[1], '?') + 1;
			$arguments = ($pastQidx > 0) ? substr($parts[1], $pastQidx) : '';
			}
		
		if ($arguments ne '')
			{
			GetNamesAndValuesOfArguments($arguments, $doingPost, $formH);
			}
		}
	else
		{
		my $numParts = @parts;
		Output("ERROR num parts is $numParts!\n");
		Output(" - obj received was |$obj|\n");
		}
	}

sub GetReferer {
	my ($value, $formH) = @_;

	if ($value =~ m!href=!)
		{
		$value = encode_utf8($value);
		$value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
		$value = decode_utf8($value);
		$value =~ m!href=([^&]+)!;
		my $referer = $1; # 
		if ($referer =~ m!^[a-z]:/!i)
			{
			$formH->{REFERER_HREF} = $referer;
			$PreviousRefererDir = $formH->{REFERER_HREF};
			}
		else
			{
			$formH->{REFERER_HREF} = $PreviousRefererDir; # This is a bit dicey
			}
		}
	else
		{
		$formH->{REFERER_HREF} = $PreviousRefererDir; # This is a bit dicey
		}
	}

# Put each name=value from $arguments into $formH{name} = value;
sub GetNamesAndValuesOfArguments {
	my ($arguments, $doingPost, $formH) = @_;
	
	my @pairs = split(/&/, $arguments);
	# Then for each name/value pair....
	foreach my $pair (@pairs)
		{
		if ($pair ne '')
			{
			# Separate the name and value:
			my ($name, $value) = split(/=/, $pair);
			
			# Convert + signs to spaces:
			$value =~ tr/+/ /;
			
			if ($name eq 'findthis')
				{
				while ($value =~ m!%([a-fA-F0-9][a-fA-F0-9])!)
					{
					my $bytesha = $1;
					my $byteh = chr(hex($bytesha));
					$value =~ s!%[a-fA-F0-9][a-fA-F0-9]!$byteh!;
					}
				my $decodedValue = decode_utf8($value);
				$value = $decodedValue;
				}
			else
				{
				# $value is utf8 at this point: convert to "a bunch of bytes", replace
				# %N, then convert back to utf8. ouch. While I'm on the subject, these encode/decode
				# names are even less distinguishable after a quarter of an hour than
				# Rozencranz and Guildenstern.
				$value = encode_utf8($value);
				$value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
				$value = decode_utf8($value);
				}
			
			if ($doingPost)
				{
				# Decode again, just in case.
				$value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
				}
	
			# Store values in a hash:
			$formH->{$name} = $value;
			}
		} 
	}

#Critical elements of multipart/form-data
#----------------------------------------
#1. main header Content-Type: multipart/form-data; boundary=---------------------------7e0b641750fd8
#(all the following are in $$postedR)
#2. POST should begin with '--' . boundary
#3. Next line, Content-Disposition with filename="file.ext"
#4. Next content type, probably skip
#5. Look for blank line, which should be next
#6. Content follows, down to next instance of '--' . boundary
#7. Then another Content-Disposition, should see name="directory" 
#8. The traditional blank line
#9. Then one line containing server directory to use.
#10. Not essential for us, post should end with --boundary--
# File name goes in: 	$formH->{'filename'}
# File contents in: 	$formH->{'contents'}
# Upload directory: 	$formH->{'directory'}
# Example post: (boundary is '----WebKitFormBoundaryD8RvDCQCBrUsrvBH', note it's two hypens short)
#------WebKitFormBoundaryD8RvDCQCBrUsrvBH
#Content-Disposition: form-data; name="filename"; filename="abe.txt"
#Content-Type: text/plain
#
#first content line
#second content line
#third content line
#------WebKitFormBoundaryD8RvDCQCBrUsrvBH
#Content-Disposition: form-data; name="directory"
#
#path should go here
#------WebKitFormBoundaryD8RvDCQCBrUsrvBH--
#
# This is **not** general, at the moment it is for a single file upload with file first
# followed by directory. The uploader (intramine_uploader.pl) expects the following
# keys in $formH:
# $formH->{'filename'}: the name of the file being uploaded
# $formH->{'contents'}: contents of the file being uploaded
# $formH->{'directory'}: server directory for the file (set to $DEFAULT_UPLOAD_DIR here if blank).
sub GetPostedFileArguments {
	my ($postedR, $multiPartFormPostBoundary, $formH) = @_;
	my $result = 0;

	$$postedR =~ s/\R/\n/g;
	my @postLines = split(/\n/, $$postedR);
	
	my $dirFieldName = '';
	my $numPostLines = @postLines;
	if ($numPostLines >= 8 && $postLines[0] =~ m!^--$multiPartFormPostBoundary!)
		{
		my $i = 1;
		
		# Skip to Content-Disposition, which should be second line.
		for ( ; $i < $numPostLines; ++$i)
			{
			if ($postLines[$i] =~ m!^Content-Disposition:\s+form-data;\s+name=['"]([^'"]+)['"];\s+filename=['"]([^'"]+)['"]!i)
				{
				my $keyName = $1;
				my $fileName = $2;
				$formH->{$keyName} = $fileName;
				last;
				}
			}
		
		# Skip to just after first blank line.
		while ($i < $numPostLines && $postLines[$i] ne '')
			{
			++$i;
			}
		++$i;
		if ($i < $numPostLines)
			{
			$formH->{'contents'} = '';
			while ($i < $numPostLines && $postLines[$i] !~ m!^--$multiPartFormPostBoundary!)
				{
				$formH->{'contents'} .= $postLines[$i] . "\n";
				++$i;
				}
			}
		
		# Avoid adding a bogus blank line at end of file.
		chomp($formH->{'contents'});
		++$i;
		# Skip to next "Content-Disposition" line
		while ($i < $numPostLines && $postLines[$i] !~ m!^Content-Disposition:!i)
			{
			++$i;
			}
		
		# Pick up name of the "directory" field, from Content-Disposition: form-data; name="directory"
		$postLines[$i] =~ m!^Content-Disposition:\s+form-data;\s+name=['"]([^'"]+)['"]!i;
		$dirFieldName = defined($1) ? $1 : '';
		++$i;
		# Skip to just after another blank line;
		while ($i < $numPostLines && $postLines[$i] ne '')
			{
			++$i;
			}
		++$i;
		
		# Pick up value of second form field as server directory to use.
		if ($i < $numPostLines)
			{
			$formH->{$dirFieldName} = $postLines[$i];
			# We are done.
			$result = 1;
			}
		}
	
	if ($result && $formH->{$dirFieldName} eq '')
		{
		$formH->{$dirFieldName} = $DEFAULT_UPLOAD_DIR;
		}
	return($result);
	}

# ResultPage: redirect, do default page action, handle a signal, return a file.
sub ResultPage {
	my ($reportItR, $arr, $formH, $peeraddress, $mimeTypeR) = @_;
	my $obj = $formH->{OBJECT};
	my $result = '';
	
	# Convert to octets, chrhex, then convert to utf8.
	$obj = encode_utf8($obj);
	$obj =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
	$obj = decode_utf8($obj);
	
	# "Drive:" might be received here as "Drive_"  - put back to "Drive:"
	# Failed, no help at all.
	#$obj =~ s!^(/\w+/\w+/\w)_/!$1:/!;
	
	my $requestHandled = 0;

	# Since IntraMine uses many non-permanent ports, in particular since the port in
	# a bookmark/favorite might not match the proper current port if IntraMine has since been
	# restarted with a different mix or order of servers, we check our port's short name against
	# any short name in the request. If they differ, punt to intramine_main.pl and hope for a response
	# that includes a proper redirect.
	my $ourName = OurShortName();
	if ($obj =~ m!^/(\w+)(/|$)!)
		{
		my $incomingName = $1;
		if ($ourName ne $incomingName && IsShortServerName($incomingName))
			{
			# Talk to main, see if it can determine the right port from the short server name.
			# Or rather "a port" since there might be more than one available.
			$$mimeTypeR = CVal('html');
			return(RedirectFromMain($obj));
			}
		elsif ($ourName eq $incomingName)
			{
			HandleDefaultPageAction($obj, $formH, $peeraddress, $ourName, \$requestHandled, \$result);
			$$reportItR = $ourName;
			}
		}
	
	# Handle 'signal=...' or indeed any 'this=that' in the request where 'this' is a key
	# in %ReqActions.
	HandleRequestAction($obj, $formH, $peeraddress, \$requestHandled, \$result);
	
	# Strip our short name from start of $obj before continuing, leaving one hopes something like a file path.
	if (!$requestHandled && $obj =~ m!^/(\w+)/!)
		{
		my $incomingName = $1;
		if (IsShortServerName($incomingName))
			{
			$obj =~ s!^/(\w+)/!!;
			}
		}
	
	if ($requestHandled)
		{
		$$mimeTypeR = CVal('html');
		# If we just served an HTML file from our local storage,
		# the directory containing the file will be in $formH->{'DEFAULTDIR'}.
		if (defined($formH->{'DEFAULTDIR'}))
			{
			$DefaultDir = $formH->{'DEFAULTDIR'};
			}
		}
	else
		{
		GetResultFromFile($obj, $formH, $mimeTypeR, \$result);
		}
	
	Output("ResultPage, Raw obj: |$obj|\n");
	Output("ResultPage bottom\n");
	return $result;	
	}

# Call the default page action for 'req=main' if $obj ends with "$ourName/?".
sub HandleDefaultPageAction {
	my ($obj, $formH, $peeraddress, $ourName, $requestHandledR, $resultR) = @_;

	# Call the default page action for 'req=main' if $obj ends with $ourName/?
	if ($obj =~ m!/$ourName$! || $obj =~ m!/$ourName/$!)
		{
		if ($obj =~ m!/$ourName$!)
			{
			$obj .= '/?req=main';
			}
		else
			{
			$obj .= '?req=main';
			}
		foreach my $nameValue (keys %ReqActions)
			{
			my @keyParts = split(/\|/, $nameValue);
			my $namePart = $keyParts[0];
			my $optionalValuePart = (defined($keyParts[1])) ? $keyParts[1]: '';
			if ($namePart eq 'req' && $optionalValuePart eq 'main')
				{
				Output("Calling 'req=main' action for |$ourName|.\n");
				$$resultR = $ReqActions{$nameValue}->($obj, $formH, $peeraddress);
				$$requestHandledR = 1;
				last;
				}
			}
		}
	
	}

# 'signal' requests have a default handler, which can be supplemented with a server-specific handler.
# If a 'signal' is received, the default handler is called first, then any specific handler.
# Defer setting $requestHandled until after calling any specific %ReqActions.
sub HandleRequestAction {
	my ($obj, $formH, $peeraddress, $requestHandledR, $resultR) = @_;
	my $defaultSignalHandled = 0; 
	
	if (!$$requestHandledR && defined($formH->{'signal'}) )
		{
		$$resultR = $ReqActions{'SIGNAL'}->($obj, $formH, $peeraddress);
		$defaultSignalHandled = 1;
		}
	
	if (!$$requestHandledR)
		{
		# Check for RESTful and argument-based requests:
		# RESTful example:
		# invoked by $RequestAction{'/file/'} = \&LoadTheFile;
		# Request /Viewer/file/pathToFile
		#	triggers LoadTheFile($obj, $formH, $peeraddress)
		#	and $obj holds pathToFile
		# Argument-based example:
		# Request /Viewer/?href=pathToFile
		#	triggers LoadTheFile($obj, $formH, $peeraddress)
		#	and $formH->{'href'} holds pathToFile
		# NOTE if it's a RESTful invocation then the action sub must return
		# something, a return of '' means some error happened.
		my $objWithTS = $obj . '/';
		my $shortName = OurShortName();
		
		foreach my $nameValue (keys %ReqActions)
			{
			my @keyParts = split(/\|/, $nameValue);
			my $namePart = $keyParts[0];
			my $optionalValuePart = (defined($keyParts[1])) ? $keyParts[1]: '';
			if ($nameValue =~ m!^/.+?/$! && $objWithTS =~ m!$shortName$nameValue!)
				{
				# Reject if action returns ''. Anything else counts as success. Note this
				# requirement is for RESTful actions only.
				#print("HRA REST BASED calling action |$nameValue| on \$obj |$obj|\n");
				$$resultR = $ReqActions{$nameValue}->($obj, $formH, $peeraddress);
				if ($$resultR ne '')
					{
					$$requestHandledR = 1;
					last;
					}
				else
					{
					# This is routine.
					#print("HRA empty result for |$nameValue|, \$obj |$obj|.\n");
					}
				}
			# Eg $formH->{'href'} = path to file, or $formH->{'req'} eq 'id'
			elsif ( defined($formH->{$namePart})
			 && ($optionalValuePart eq '' || $optionalValuePart eq $formH->{$namePart}) )
				{
				#print("HRA ARG BASED calling action |$nameValue| on \$obj |$obj|\n");
				$$resultR = $ReqActions{$nameValue}->($obj, $formH, $peeraddress);
				$$requestHandledR = 1;
				last;
				}
			}
		}
	
	if (!$$requestHandledR && $defaultSignalHandled)
		{
		$$requestHandledR = 1;
		}
	}

sub GetResultFromFile {
	my ($obj, $formH, $mimeTypeR, $resultR) = @_;
	
	my $trimmedObj = RightmostWantedPartialPath($obj);
	
	# Image: try supplied path first, else look in our web server images folder
	# eg |/C:/perlprogs/mine/images_for_web_server/110.gif|
	if ($trimmedObj =~ m!\.(gif|jpe?g|png|ico|webp)$!i)
		{
		GetImageResult($trimmedObj, $formH, $mimeTypeR, $resultR);
		}
	elsif ($trimmedObj =~ m!\.css$!i)
		{
		GetCssResult($trimmedObj, $formH, $mimeTypeR, $resultR);
		}
	elsif ($trimmedObj =~ m!\.(js|xml|json)$!i)
		{
		GetJsResult($trimmedObj, $formH, $mimeTypeR, $resultR);
		}
	elsif ($trimmedObj =~ m!\.(ttf|woff)$!i)
		{
		GetFontResult($trimmedObj, $formH, $mimeTypeR, $resultR);
		}
	else
		{
		my $gotIt = 0;
		# Help file, handled specially.
		if ($trimmedObj =~ m!\.(txt|html?)/?$!i)
			{
			my $helpFileName = $trimmedObj;
			$helpFileName =~ s!/$!!;
			$gotIt = GetHelpFile($helpFileName, $mimeTypeR, $resultR);
			}
		
		if (!$gotIt)
			{
			GetUnknownTypeResult($trimmedObj, $formH, $mimeTypeR, $resultR);
			}
		}	
	}

# RightmostWantedPartialPath():
# => "/Viewer/file/C:/perlprogs/mine/test/googlesuggest.cpp/addon/search/cm_small_tip.css/?arg=7"
# <= "addon/search/cm_small_tip.css"
# - trim any args on right
# - look for \w: drive letter, trim anything before that
# - given \w: look backwards from the right for \.w+ signalling file name
# - we want the second last one
# - trim off any full path, and return remainder eg "addon/search/cm_small_tip.css"
sub RightmostWantedPartialPath {
	my ($fullObj) = @_;
	my $wantedObj = $fullObj;
	
	# Trim any args from right end.
	my $qIndex = index($wantedObj, '?');
	if ($qIndex > 0)
		{
		$wantedObj = substr($wantedObj, 0, $qIndex);
		$wantedObj =~ s!/$!!;
		}
	
	# Look for a full path preceeding wanted partial path, trim it if found.
	if ($wantedObj =~ m!\w\:!)
		{
		my $startPos = $-[0]; # position of \w, potential drive letter
		my $testObj = substr($wantedObj, $startPos);
		$wantedObj = $testObj;
		#print ("Path to end: |$testObj|\n");
		
		# Check for a "leftover" after a full path only if $obj begins with
		# something more than just /\w: or \w:.
		if ($startPos > 1)
			{
			# Check $testObj to see if it begins with a full path and has something on the
			# right left over. Do that by stripping /bits/ from the right until a potential
			# end of a full path is seen, or we go too far.
			my $filePathCopy = $testObj;
			my $fnPosition = rindex($filePathCopy, '/');
			my $foundRightmostFullPath = 0;
			
			while ($fnPosition > 3)
				{
				$filePathCopy = substr($filePathCopy, 0, $fnPosition);
				#print("Checking |$filePathCopy|\n");
				if ($filePathCopy =~ m!\.\w+$!)
					{
					$foundRightmostFullPath = 1;
					last;
					}
				else
					{
					$fnPosition = rindex($filePathCopy, '/');
					}
				#print("\$fnPosition: |$fnPosition|\n");
				}
			
			if ($foundRightmostFullPath)
				{
				$wantedObj = substr($testObj, $fnPosition + 1);
				#print("Trimmed obj: |$wantedObj|\n");
				}
			}
		}
	
	return($wantedObj);
	}

sub GetHelpFile {
	my ($helpFileName, $mimeTypeR, $resultR) = @_;
	$helpFileName =~ m!\.(\w+)$!;
	my $ext = $1;
	my $gotIt = 0;
	$$resultR = GetTextFile($HELP_DIR . $helpFileName);
	if ($$resultR ne '')
		{
		if ($ext =~ m!html?!i)
			{
			$mimeTypeR = CVal('html');
			}
		else
			{
			$mimeTypeR = CVal('txt');
			}
		$gotIt = 1;
		}
		
	return($gotIt);
	}

sub GetImageResult {
	my ($obj, $formH, $mimeTypeR, $resultR) = @_;
	
	$obj =~ m!\.(gif|jpe?g|png|ico|webp)$!i;
	my $ext = lc($1);
	Output("for image: |$obj|\n");
	my $filePath = $obj;
	$filePath =~ s!^/!!; # vs substr($obj, 1);
	my $gotIt = 0;

	if (FileOrDirExistsWide($filePath) == 1)
		{
		$gotIt = 1;
		$$resultR = GetBinFile($filePath);
		}
	else
		{
		my $fileName;
		my $fnPosition;
		if (($fnPosition = rindex($obj, '/')) >= 0)
			{
			$fileName = substr($obj, $fnPosition + 1);
			}
		else
			{
			$fileName = $obj;
			}
		
		my $stdPath = $IMAGES_DIR . $fileName;
		
		if (FileOrDirExistsWide($stdPath) == 1)
			{
			$gotIt = 1;
			$$resultR = GetBinFile($stdPath);
			}
		elsif ($COMMON_IMAGES_DIR ne '')
			{
			$stdPath = $COMMON_IMAGES_DIR . $fileName;
			if (FileOrDirExistsWide($stdPath) == 1)
				{
				$gotIt = 1;
				$$resultR = GetBinFile($stdPath);
				}
			elsif ($DefaultDir ne '')
				{
				$filePath =~ s!^\./!!; # Trim any leading ./
				my $actualDir = $DefaultDir; # has trailing slash
				while ($filePath =~ m!^\.\./!) # ../ == go up one level
					{
					$filePath =~ s!^\.\./!!;
					$actualDir =~ s![^/]+/$!!;
					}
				
				$stdPath = $actualDir . $filePath;
				if (FileOrDirExistsWide($stdPath) == 1)
					{
					$gotIt = 1;
					$$resultR = GetBinFile($stdPath);
					}
				}
			}
		}
		
	# Check any "special" directories if still not found.
	if (!$gotIt)
		{
		$gotIt = LoadFileFromSpecificDirectory($JSEDITOR_DIR, $obj, 1, $formH->{REFERER_HREF}, $mimeTypeR, $resultR);
		}
	if (!$gotIt)
		{
		$gotIt = LoadFileFromSpecificDirectory($HIGHLIGHT_DIR, $obj, 1, $formH->{REFERER_HREF}, $mimeTypeR, $resultR);
		}
	}

sub GetCssResult {
	my ($obj, $formH, $mimeTypeR, $resultR) = @_;
	
	Output(" for CSS.\n");
	
	my $fileName;
	my $fnPosition;
	if (($fnPosition = rindex($obj, '/')) >= 0)
		{
		$fileName = substr($obj, $fnPosition + 1);
		}
	else
		{
		$fileName = $obj;
		}
	
	my $filePath = $CSS_DIR . "/$fileName";
	my $gotIt = 0;
	my $exists = FileOrDirExistsWide($obj);
	if ($exists == 1)
		{
		$gotIt = 1;
		$$resultR = GetTextFile($obj);
		}
	elsif (FileOrDirExistsWide($filePath) == 1)
		{
		$gotIt = 1;
		$$resultR = GetTextFile($filePath);
		}
	elsif (FileOrDirExistsWide($CSS_DIR . $obj) == 1)
		{
		$gotIt = 1;
		$$resultR = GetTextFile($CSS_DIR . $obj);
		}
	elsif ($DefaultDir ne '')
		{
		$filePath = $obj;
		$filePath =~ s!^\./!!; # Trim any leading ./
		my $actualDir = $DefaultDir; # has trailing slash
		while ($filePath =~ m!^\.\./!) # ../ == go up one level
			{
			$filePath =~ s!^\.\./!!;
			$actualDir =~ s![^/]+/$!!;
			}
		my $stdPath = $actualDir . $filePath;
		$exists = FileOrDirExistsWide($stdPath);
		if ($exists == 1)
		#if (-f $stdPath)
			{
			$gotIt = 1;
			$$resultR = GetTextFile($stdPath);
			}
		}
	
	# Check any "special" directories if still not found.
	if (!$gotIt)
		{
		$gotIt = LoadFileFromSpecificDirectory($JSEDITOR_DIR, $obj, 0, $formH->{REFERER_HREF}, $mimeTypeR, $resultR);
		}
	if (!$gotIt)
		{
		$gotIt = LoadFileFromSpecificDirectory($HIGHLIGHT_DIR, $obj, 0, $formH->{REFERER_HREF}, $mimeTypeR, $resultR);
		}
	}

sub GetJsResult {
	my ($obj, $formH, $mimeTypeR, $resultR) = @_;
	
	Output(" for JS.\n");
	
	my $fileName;
	my $fnPosition;
	if (($fnPosition = rindex($obj, '/')) >= 0)
		{
		$fileName = substr($obj, $fnPosition + 1);
		}
	else
		{
		$fileName = $obj;
		}
		
	# TEST ONLY
	my $originalFileName = $fileName;

	# Bad idea, can conflict with files in $JSEDITOR_DIR: my $filePath = $JS_DIR . "/$fileName";
	my $relativePath = $obj;
	$relativePath =~ s!^\.?/!!; # Trim leading ./ or just /
	my $stdPath = $JS_DIR . "/$relativePath"; # $JS_DIR has no trailing slash
	my $gotIt = 0;
	my $exists = FileOrDirExistsWide($obj);
	if ($exists == 1)
		{
		$gotIt = 1;
		$$resultR = GetTextFile($obj);
		}
	elsif (FileOrDirExistsWide($stdPath) == 1)
		{
		$gotIt = 1;
		$$resultR = GetTextFile($stdPath);
		}
	elsif ($DefaultDir ne '')
		{
		my $filePath = $obj;
		$filePath =~ s!^\./!!; # Trim any leading ./
		my $actualDir = $DefaultDir; # has trailing slash
		while ($filePath =~ m!^\.\./!) # ../ == go up one level
			{
			$filePath =~ s!^\.\./!!;
			$actualDir =~ s![^/]+/$!!;
			}
		my $stdPath = $actualDir . $filePath;
		$exists = FileOrDirExistsWide($stdPath);
		if ($exists == 1)
			{
			$gotIt = 1;
			$$resultR = GetTextFile($stdPath);
			}
		}
		
	if (!$gotIt)
		{
		$gotIt = LoadFileFromSpecificDirectory($JSEDITOR_DIR, $obj, 0, $formH->{REFERER_HREF}, $mimeTypeR, $resultR);
		}
	if (!$gotIt)
		{
		$gotIt = LoadFileFromSpecificDirectory($HIGHLIGHT_DIR, $obj, 0, $formH->{REFERER_HREF}, $mimeTypeR, $resultR);
		}
	}

sub GetFontResult {
	my ($obj, $formH, $mimeTypeR, $resultR) = @_;
	
	Output(" for FONT.\n");
	
	my $fileName;
	my $fnPosition;
	if (($fnPosition = rindex($obj, '/')) >= 0)
		{
		$fileName = substr($obj, $fnPosition + 1);
		}
	else
		{
		$fileName = $obj;
		}
	
	my $filePath = $FONT_DIR . "/$fileName";
	my $gotIt = 0;
	my $exists = FileOrDirExistsWide($obj);
	if ($exists == 1)
		{
		$gotIt = 1;
		$$resultR = GetBinFile($obj);
		}
	elsif (FileOrDirExistsWide($filePath) == 1)
		{
		$gotIt = 1;
		$$resultR = GetBinFile($filePath);
		}
	elsif (FileOrDirExistsWide($FONT_DIR . $obj) == 1)
		{
		$gotIt = 1;
		$$resultR = GetBinFile($FONT_DIR . $obj);
		}
	elsif ($DefaultDir ne '')
		{
		$filePath = $obj;
		$filePath =~ s!^\./!!; # Trim any leading ./
		my $actualDir = $DefaultDir; # has trailing slash
		while ($filePath =~ m!^\.\./!) # ../ == go up one level
			{
			$filePath =~ s!^\.\./!!;
			$actualDir =~ s![^/]+/$!!;
			}
		my $stdPath = $actualDir . $filePath;
		$exists = FileOrDirExistsWide($stdPath);
		if ($exists == 1)
			{
			$gotIt = 1;
			$$resultR = GetBinFile($stdPath);
			}
		}
	
	if (!$gotIt)
		{
		$gotIt = LoadFileFromSpecificDirectory($JSEDITOR_DIR, $obj, 1, $formH->{REFERER_HREF}, $mimeTypeR, $resultR);
		}
	if (!$gotIt)
		{
		$gotIt = LoadFileFromSpecificDirectory($HIGHLIGHT_DIR, $obj, 1, $formH->{REFERER_HREF}, $mimeTypeR, $resultR);
		}
	}

sub GetUnknownTypeResult {
	my ($obj, $formH, $mimeTypeR, $resultR) = @_;
	
	Output(" for UNKNOWN FILE TYPE.\n");
	if ($DefaultDir ne '')
		{
		my $filePath = $obj;
		$filePath =~ s!^\./!!; # Trim any leading ./
		my $actualDir = $DefaultDir; # has trailing slash
		while ($filePath =~ m!^\.\./!) # ../ == go up one level
			{
			$filePath =~ s!^\.\./!!;
			$actualDir =~ s![^/]+/$!!;
			}
		my $stdPath = $actualDir . $filePath;
		my $exists = FileOrDirExistsWide($stdPath);
		if ($exists == 1)
			{
			$$resultR = GetBinFile($stdPath);
			}			
		}
	else
		{
		# If there's a referer, try using that.
		if (defined($formH->{REFERER_HREF}))
			{
			$$resultR = GetResourceUsingReferer($obj, $formH->{REFERER_HREF}, 1); # 1==binary
			}
		}
	}

sub GetResourceUsingReferer {
	my ($obj, $referer, $binaryWanted) = @_;
	
	# First clean up $obj, which can look like
	# /images/nav-bg-l.png
	# or
	# /Viewer/images/clock2.gif
	my $shortName = OurShortName();
	$obj =~ s!^/!!;
	$obj =~ s!^$shortName/!!;
	
	# Referer, eg "C:/dewtell/public_html/tenclock/index.htm"
	# From referer get refererParent and refererGrandParent one level up.
	# Arg, some refers are less than helpful, eg
	# Referer: http://192.168.0.3:43129/css/topglow.css
	# for 
	# /images/item-secondary-bg.jpg  (sic, but should be ../images/item-secondary-bg.jpg)
	# For these, as a last resort we can try the last referer, although that's a bit of a hack.
	my $lastSlashPos = rindex($referer, "/");
	my $refererParent = substr($referer, 0, $lastSlashPos);
	$lastSlashPos = rindex($refererParent, "/");
	my $refererGrandParent = substr($refererParent, 0, $lastSlashPos+1);
	$refererParent .= "/";
	
	my $result = '';
	my $path = '';
	if (FileOrDirExistsWide($refererParent . $obj))
		{
		$path = $refererParent . $obj;
		}
	elsif (FileOrDirExistsWide($refererGrandParent . $obj))
		{
		$path = $refererGrandParent . $obj;
		}
	
	if ($path ne '')
		{
		if ($binaryWanted)
			{
			$result = GetBinFile($path);
			}
		else
			{
			$result = GetTextFile($path);
			}
		}
	
	return($result);
	}

# Load contents of a file, as binary or text, by
# looking in a specific directory in the IntraMine folder
# such as CodeMirror-master/.
# $referrer is $formH->{REFERER_HREF} if supplied.
sub LoadFileFromSpecificDirectory {
	my ($specificDir, $partialPath, $asBinary, $referrer, $mimeTypeR, $resultR) = @_;
	my $loader = $asBinary ? \&GetBinFile : \&GetTextFile;
	my $gotIt = 0;
	
	# Try the whole supplied $filePathCopy, then parts of it.
	my $filePathCopy = $partialPath;
	my $filePathCopynoS = $partialPath;
	$filePathCopynoS =~ s!^/!!;
	
	my $stdPath = $specificDir . $filePathCopynoS;
	if (FileOrDirExistsWide($stdPath) == 1)
		{
		$gotIt = 1;
		$$resultR = $loader->($stdPath);
		}

	my $fileName;
	my $fnPosition;
	if (($fnPosition = rindex($partialPath, '/')) >= 0)
		{
		$fileName = substr($partialPath, $fnPosition + 1);
		}
	else
		{
		$fileName = $partialPath;
		}

	if (!$gotIt)
		{
		my $partialPath = '';
		my $fnPosition = rindex($filePathCopy, '/');
		while ($fnPosition >= 0)
			{
			if ($partialPath ne '')
				{
				$partialPath = substr($filePathCopy, $fnPosition + 1) . '/' . $partialPath;
				}
			else
				{
				$partialPath = substr($filePathCopy, $fnPosition + 1);
				}
			$filePathCopy = substr($filePathCopy, 0, $fnPosition);
			my $stdPath = $specificDir . $partialPath;
			
			if (FileOrDirExistsWide($stdPath) == 1)
				{
				$gotIt = 1;
				$$resultR = $loader->($stdPath);
				last;
				}
			$fnPosition = rindex($filePathCopy, '/');
			}
		}

	# Try just the supplied file name, look in $specificDir.
	if (!$gotIt)
		{
		my $stdPath = $specificDir . $fileName;
		my $exists = FileOrDirExistsWide($stdPath);
		if ($exists == 1)
			{
			$gotIt = 1;
			$$resultR = $loader->($stdPath);
			}
		}

	# If there's a referer, try using that.
	if (!$gotIt && defined($referrer))
		{
		$$resultR = GetResourceUsingReferer($partialPath, $referrer, $asBinary); # 1==binary
		if ($$resultR ne '')
			{
			$gotIt = 1;
			}
		}

	# Still nothing - try $specificDir with just the file name.
	if (!$gotIt)
		{
		my $fileName;
		my $fnPosition;
		if (($fnPosition = rindex($partialPath, '/')) >= 0)
			{
			$fileName = substr($partialPath, $fnPosition + 1);
			my $filePath = $specificDir . "/$fileName";
			my $exists = FileOrDirExistsWide($filePath);
			if ($exists == 1)
				{
				$gotIt = 1;
				$$resultR = $loader->($filePath);
				}
			}
		}

	# Set mime type
	if ($partialPath =~ m!\.(\w+)$!)
		{
		my $ext = lc($1);
		$$mimeTypeR = CVal($ext);
		if ($$mimeTypeR eq '')
			{
			$$mimeTypeR = CVal('js');
			}
		}
	
	return($gotIt);
	}

# eg /Viewer/?href=C:/perlprogs/mine/docs/domain
# %20name%20for%20intramine.txt&rddm=1
sub RedirectFromMain {
	my ($obj) = @_;
	my $result = '';
	
	my $serverAddress = ServerAddress(); 			# This is common to all servers in IntraMine, local IP
	my $portNumber = MainServerPort();				# Typ. 81
	my $mains = IO::Socket::INET->new(
	                Proto   => 'tcp',       		# protocol
	                PeerAddr=> "$serverAddress",
	                PeerPort=> "$portNumber"
	                ) or (ServerErrorReport() && return);
	
	$obj = uri_escape($obj); # This is needed due to the '?' and '=' and '&' in $obj.
	
	print $mains "GET /?req=redirect&resource=$obj HTTP/1.1\r\n\r\n";
	my $line = '';
	while ($line=<$mains>)
		{
		$result .= $line . "\n";
		}
	close $mains;

	return($result);
	}
	
# If you know the short name for a service (see data/serverlist.txt)
# you can call this sub to find out if an instance is currently running.
# Returns 1 if Main thinks the service is running, 0 otherwise.
# Eg "if (ServiceIsRunning('Files'))...".
sub ServiceIsRunning {
	my ($shortName) = @_;
	my $result = 0;
	
	my $serverAddress = ServerAddress(); 			# This is common to all servers in IntraMine, local IP
	my $portNumber = MainServerPort();				# Typ. 81
	my $mains = IO::Socket::INET->new(
	                Proto   => 'tcp',       		# protocol
	                PeerAddr=> "$serverAddress",
	                PeerPort=> "$portNumber"
	                ) or (ServerErrorReport() && return(0));
	
	print $mains "GET /?req=running&shortname=$shortName HTTP/1.1\r\n\r\n";
	my $line = '';
	my $rawResult = '';

	# Pick up some headers, and then a 'yes' or 'no' at the end.
	while ($line=<$mains>)
		{
		$rawResult .= $line . "\n";
		}
	close $mains;
	
	if ($rawResult =~ m!yes\s*$!i)
		{
		$result = 1;
		}

	return($result);
	}

# Like above ServiceIsRunning, but returns count of running instances.
sub NumInstancesOfShortNameRunning {
	my ($shortName) = @_;
	my $result = 0;

	# TEST ONLY
	#return(1);
	
	my $serverAddress = ServerAddress(); 			# This is common to all servers in IntraMine, local IP
	my $portNumber = MainServerPort();				# Typ. 81
	my $mains = IO::Socket::INET->new(
	                Proto   => 'tcp',       		# protocol
	                PeerAddr=> "$serverAddress",
	                PeerPort=> "$portNumber"
	                ) or (ServerErrorReport() && return(0));
	
	print $mains "GET /?req=servercount&shortname=$shortName HTTP/1.1\r\n\r\n";
	my $line = '';
	my $rawResult = '';

	# Pick up some headers, and then a number at the end.
	while ($line=<$mains>)
		{
		$rawResult .= $line . "\n";
		}
	close $mains;
	
	if ($rawResult =~ m!(\d+)\s*$!i)
		{
		$result = $1;
		}

	return($result);
	}

sub ServerIdentify {
	my ($obj, $formH, $peeraddress) = @_;
	my $portNumber = $OurPort;
	my $srvrAddr = ServerAddress();
	my $result = "$OurShortName on $srvrAddr:$portNumber";
	
	return($result);
	}

sub DefaultBroadcastHandler {
	my ($obj, $formH, $peeraddress) = @_;
	
	if (defined($formH->{'signal'}) && $formH->{'signal'} eq 'todoCount'
	  && defined($formH->{'count'}) )
		{
		SetToDoOverdueCount($formH->{'count'});
		}
	return('OK');	
	}

sub ConfigValue {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = 'UNKNOWN';
	if (defined($formH->{'key'}))
		{
		$result = CVal($formH->{'key'});
		}
	
	return($result);
	}

sub OurListeningPort {
	return($OurPort);
	}

sub DefaultUploadDirectory {
	return($DEFAULT_UPLOAD_DIR);
}

sub SetOurPageName {
	my ($pageName) = @_;
	if (!defined($pageName))
		{
		$pageName = 'NOT DEFINED';
		}
	$OurPageName = $pageName;
	}

sub OurPageName {
	return($OurPageName);
}

sub SetOurShortName {
	my ($shortname) = @_;
	$OurShortName = $shortname;
	}

sub OurShortName {
	return($OurShortName);
}

# Set host and port for the WebSocket client.
sub InitWebSocketClient {
	my $srvrAddr = ServerAddress();
	InitWebSocket($srvrAddr, $WebSocketPort);
	}

# A server such as intramine_filewatcher.pl might want to send a message 'signal=reindex' etc to
# all instances running of intramine_linker.pl: so it calls this sub, which forwards requestS
# to the main redirect server intramine_main.pl, which in turn shotguns it out to ALL servers,
# page and background, including the one making the original request.
# UNLESS 'name=Search' or 'name=FILEWATCHER' or some other specific page server
# or background server name is provided, in which case the message just goes to those servers.
# At present a signal with 'name=Search' will be sent to all Search page
# servers, both main intramine_search.pl and sub servers intramine_viewer.pl, intramine_linker.pl,
# intramine_open_with.pl, and intramine_editor.pl. 
# Any server using this module is given a default responder DefaultBroadcastHandler()
# which does nothing in response to a 'signal' message. Anyone wanting to respond to a 'signal'
# message properly should put an "override" entry in %RequestAction, see eg intramine_linker.pl
# ($RequestAction{'signal'} = \&HandleBroadcastRequest;);
# This is fairly tolerant, so it will also send a 'ssinfo=up' back to the main server, as is done
# near the top of MainLoop() here when a server is properly started.
sub RequestBroadcast {
	my ($msg) = @_;
	my $serverAddress = ServerAddress(); 			# This is common to all servers in IntraMine, local IP
	my $portNumber = MainServerPort();				# Typ. 81
	my $remote = IO::Socket::INET->new(
	                Proto   => 'tcp',       		# protocol
	                PeerAddr=> "$serverAddress",
	                PeerPort=> "$portNumber"
	                ) or (ServerErrorReport() && return);
#	print "Connected to ", $remote->peerhost,
#	      " on port: ", $remote->peerport, "\n";
	
	$msg = uri_encode($msg);
	print $remote "GET /?$msg HTTP/1.1\n\n"; # Eg "GET /?signal=reindex&name=Search HTTP/1.1\n\n"
	close $remote;
	}

# Send out an "activity" WebSockets message. This is picked up by statusEvents.js.
# Note only FileWatcher calls this. Other activity reporting is done in web client JavaScript
# using websockets.js#wsSendMessage().
sub ReportActivity {
	my ($activeShortName) = @_; # ignored
	
	my $name = OurShortName();
	my $port = OurListeningPort();
	
	WebSocketSend('activity ' . $name . ' ' . $port);
	}

sub ServerErrorReport{
	print Win32::FormatMessage( Win32::GetLastError() );
	return 1;
    }

sub GetRequestedFile {
	my ($obj, $formH, $peeraddress) = @_;
	my $filePath = $formH->{'file'};
	
	my $result = GetTextFile($filePath);
	
	return $result;
	}

sub GetBinFile {
	my ($filePath) = @_;
	return(ReadBinFileWide($filePath));
	}

sub PutBinFile {
	my ($data, $filePath) = @_;
	WriteBinFileWide($filePath, $data);
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

# (This is experimental, use it only if you're bored.)
# GetStandardPageLoader(): see eg intramine_eventsserver.pl#EventsPage() for an example.
# Generic LoadHeaderFilesAndGo(), replaces _LOADANDGO_ at top of result page.
# _LOADITEMS_, _ERRORID_, _THEHOST_, _THEPORT_ below are replaced here by supplied args.
# $loadItems should contain at most one 'req=content'.
sub GetStandardPageLoader {
	my ($loadItems, $contentID, $host, $port) = @_; # contentID is also errorID
	
	my $standardPageLoader = <<'FINIS';
// Call loader when ready.
function ready(fn) {
	if (document.readyState != 'loading')
		{
		fn();
		}
	else
		{
		document.addEventListener('DOMContentLoaded', fn);
		}
	}

var loadItems = [_LOADITEMS_];
var itemIndex = 0;
var contentID = '_CONTENT_';
var errorID = contentID;

ready(LoadHeaderFilesAndGo);

// File, or request, or function -- typically a function comes last and gets things going once everything is loaded.
// All the kinds of loadItems are optional.
// A req= can be for 'req=content' or for a js or css file where for example 'req|cmdpagejs' should be matched
// by a corresponding %RequestAction entry (see top of intramine_commandserver.pl). There can be optional
// trailing arguments in all three cases.
// A file item is just the file name of a css or js file, no trailing args.
// [June 18 2016 I am adding a tailEnd() called at the end, currently it does nothing.]
function LoadHeaderFilesAndGo() {
	// As a special case, just call tailEnd() if loadItems is empty.
	if (loadItems.length == 0)
		{
		// All done.
		tailEnd();
		hideSpinner();
		return;
		}
	
	var nextItem = loadItems[itemIndex];
	var isAjaxCall = /(^req\=)|(\.(css|js)$)/.exec(nextItem);
	// If entry isn't an ajax call it should be a JS function.
	if (isAjaxCall !== null)
		{
		var request = new XMLHttpRequest();
		var isContentRequest = false;
		var isJS = false;
		var isCSS = false;
		var mtch;
		
		if ( (mtch = /^req\=content/.exec(nextItem)) !== null )
			{
			isContentRequest = true;
			request.open('get', 'http://_THEHOST_:_THEPORT_/?' + nextItem, true);
			}
		else if ( (mtch = /^req\=/.exec(nextItem)) !== null ) // js or css, streamed, with optional trailing args
			{
			var jsMtch = /js(\&|$)/.exec(nextItem); // req=somejs or req=somejs&arg2=77...
			isJS = (jsMtch !== null);
			isCSS = !isJS;
			request.open('get', 'http://_THEHOST_:_THEPORT_/?' + nextItem, true);
			}
		else if ( (mtch = /\.js$/.exec(nextItem)) !== null ) //js, from disk
			{
			isJS = true;
			request.open('get', 'http://_THEHOST_:_THEPORT_/?req=js&file=_JS_DIR_' + nextItem, true);
			}
		else if ( (mtch = /\.css$/.exec(nextItem)) !== null ) //css, from disk
			{
			isCSS = true;
			request.open('get', 'http://_THEHOST_:_THEPORT_/?req=css&file=_CSS_DIR_' + nextItem, true);
			}
		else
			{
			var e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>LoadHeaderFilesAndGo Error, unknown next item |' + nextItem + '|!</p>';
			hideSpinner();
			}
		request.onload = function() {
		  if (request.status >= 200 && request.status < 400)
			{
			// Success!
			// Note we do NOT arrive here for fn requests: just content, js,  css.
			if (isContentRequest) // use std #pageContent
				{
				var e1 = document.getElementById(contentID);
				e1.innerHTML = request.responseText;
				}
			else if (isJS)
				{
				var script = document.createElement("script");
				script.type = "text/javascript";
				script.text = request.responseText;
				document.body.appendChild(script);
				}
			else // css, or by golly we are in trouble
				{
				var oNew = document.createElement('style');
				oNew.rel = 'STYLESHEET';
				oNew.type = 'text/css';
				oNew.textContent = request.responseText;
				document.getElementsByTagName("head")[0].appendChild(oNew);
				}
			// Next.
			if (++itemIndex !== loadItems.length)
				{
				LoadHeaderFilesAndGo();
				}
			else
				{
				// All done.
				tailEnd();
				hideSpinner();
				}
			}
		  else
			{
			// We reached our target server, but it returned an error
			var e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>LoadHeaderFilesAndGo Error, server reached but it returned an error!</p>';
			hideSpinner();
			}
		};
		
		request.onerror = function() {
			// There was a connection error of some sort
			var e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>LoadHeaderFilesAndGo Connection error!</p>';
			hideSpinner();
			};
		request.send();
		}
	else if (typeof nextItem === 'function')
		{
		nextItem(''); // empty single argument, needed eg by EventsPage loadPageContent()
		// Next.
		if (++itemIndex !== loadItems.length)
			{
			LoadHeaderFilesAndGo();
			}
		else
			{
			// All done.
			tailEnd();
			hideSpinner();
			}
		}
	else // ERROR
		{
		var e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>MAINTENANCE ERROR, unknown LoadHeaderFilesAndGo() entry ' + nextItem + '!</p>';
		hideSpinner();
		}
	}

function tailEnd() {
	// Nothing at the moment, maybe you'll think of something:)
	}

FINIS
	$standardPageLoader =~ s!_LOADITEMS_!$loadItems!;
	$standardPageLoader =~ s!_CONTENT_!$contentID!;
	$standardPageLoader =~ s!_THEHOST_!$host!g;
	$standardPageLoader =~ s!_THEPORT_!$port!g;
	$standardPageLoader =~ s!_JS_DIR_!$JS_DIR/!g; 	# OK that trailing slash is a bit ugly. Mea culpa.
	$standardPageLoader =~ s!_CSS_DIR_!$CSS_DIR/!g;	# Ditto.

	return($standardPageLoader);
	}
} ##### MainLoop and friends

{ ##### Last call time
# For timeouts: if server is so busy that timeout is never triggered, force a call to $DoPeriodic
# if more than $timeout seconds has elapsed.
my $LastPeriodicCallTime;

# If no time is supplied, uses "now".
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
}  ##### Last call time

{ ##### Drive list
my @drives;
my @driveInfo;

# Drive [$i] is usable
# if (defined($driveInfo[$i][5]) && $driveInfo[$i][5] ne '')
sub InitDriveList {
	@drives = ();
	@driveInfo = ();
	@drives= getLogicalDrives();
	
	foreach my $d (  @drives  )
		{
	    my @v= (undef)x7;
	    GetVolumeInformation( $d, @v ); # Win32API::File
	    $d =~ s!\\!/!g;
	    push @driveInfo, \@v;
	    ##print "|$d| |$x[0]| ($x[5])\n"; # |L:\| |Optional name| |(File system)| - don't list if (File sytem) is empty
		}
	}

# my $driveSelectorOptions = <<'FINIS';
#		<option value='C:/' selected>C:</option>
#		<option value='E:/'>E:</option>
#		<option value='P:/'>P:</option>
# FINIS
# $QUICKDRIVELIST 1 uses fsutil, which is faster but lists mapped drives that aren't connected
# and also doesn't list drive names.
# $QUICKDRIVELIST 0 lists only connected drives, with names, but is sometime very slow (6 seconds).
sub DriveSelectorOptions {
	my $result = '';
	
	if ($QUICKDRIVELIST)
		{
		my $driveList = qx/fsutil fsinfo drives/;
		my @parts = split(" ", $driveList);
		my $numDrives = 0;
		
		for (my $i = 1; $i < @parts; ++$i) # Skip "Drives:"
			{
			my $drive = $parts[$i];
			$drive =~ s!\\!/!;
			my $selected = '';
			if ($numDrives == 0)
				{
				$selected = ' selected';
				}
			my $driveName = substr($drive, 0, -1);
			$result .= "<option value='$drive'$selected>$driveName</option>\n";
			++$numDrives;
			}
		}
	else
		{
		InitDriveList();
		
		my $numDrives = 0;
		for (my $i = 0; $i < @drives; ++$i)
			{
			if (defined($driveInfo[$i][5]) && $driveInfo[$i][5] ne '')
				{
				my $drive = $drives[$i];
				my $driveName = substr($drive, 0, -1);
				my $selected = '';
				my $optionalName = (defined($driveInfo[$i][0]) && $driveInfo[$i][0] ne '') ? " ($driveInfo[$i][0])" : '';
				if ($numDrives == 0)
					{
					$selected = ' selected';
					}
				$result .= "<option value='$drive'$selected>$driveName$optionalName</option>\n";
				++$numDrives;
				}
			}
		}
		
	return($result);
	}
} ##### Drive list

# Run test program for one server.
sub SelfTest {
	my ($obj, $formH, $peeraddress) = @_;
	#my $result = "$SHORTNAME testing started.";
	my $serverIp = ServerAddress();
	my $port = MainServerPort();
	my $shortName = OurShortName();
	my $swarmserverPort = OurListeningPort();
	
	my $result = 'ok';
	my $running = LaunchTestProgram($serverIp, $port, $shortName, $swarmserverPort);
	if (!$running)
		{
		$result = "Error, test program for $shortName did not start!";
		}

	return($result);
	}

# LaunchTestProgram(): called by a server's SelfTest() sub if we are testing.
sub LaunchTestProgram {
	my ($serverAddress, $mainPort, $shortName, $swarmserverPort) = @_;
	my $testProgramPath = TestProgramPathForShortName($shortName);
	my $result = 1;
	if ($testProgramPath ne '')
		{
		print("Launching |$testProgramPath|\n");
		my $running = RunPerlProgram($testProgramPath, $serverAddress, $mainPort, $shortName, $swarmserverPort);
		if (!$running)
			{
			print("ERROR: |$testProgramPath| did not run!\n");
			print("Time to ctrl-C and fix the problem.\n");
			$result = 0;
			}
		else
			{
			print("|$testProgramPath| is running.\n");
			}
		}
	else
		{
		print("No test program 'test_$shortName.pl' found for $shortName.\n");
		$result = 0;
		}
		
	return($result);
	}

sub TestProgramPathForShortName {
	my ($shortName) = @_;
	my $result = '';
	my $testProgDir = FullDirectoryPath('TEST_PROGRAM_DIR');
	my $fullProgPath = $testProgDir . "test_$shortName.pl";
	if (FileOrDirExistsWide($fullProgPath) == 1)
		{
		$result = $fullProgPath;
		}
	
	return($result);
	}

sub RunPerlProgram {
	my ($path, $serverAddress, $mainPort, $shortName, $swarmserverPort) = @_;
	my $proc;
	my $isRunning = 1;
	Win32::Process::Create($proc, $ENV{COMSPEC}, "/c $path $serverAddress $mainPort $shortName $swarmserverPort", 0, 0, ".")
			|| ($isRunning = 0);
	return($isRunning);
	}

use ExportAbove;
1;

