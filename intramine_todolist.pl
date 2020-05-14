# intramine_todolist.pl: a Kanban-style TODO list using a single text (actually JSON) file.
# List is stored in one file (typ. data/ToDo.txt) so everybody sees the same list.
# Most Save conflicts are avoided with a Server-Sent Event sent to all open ToDo pages
# when any ToDo page changes (see PutData() below).
# ToDo tracks three categories, To Do, Doing, and Done. There are fields in items for
# Title, Description and Due Date. Overdue items are emphasized with a bit of color.
# This Perl prog mainly gets things going with an HTML skeleton, and saves and loads data.
# The interface handling, and Server-Sent Events handling, is done in JavaScript - 
# see todo.js, todoEvents.js, and todoGetPutData.js. jQuery is used.

# perl C:\perlprogs\mine\intramine_todolist.pl  81 43131

use strict;
use warnings;
use utf8;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use win_wide_filepaths;
use swarmserver;

#binmode(STDOUT, ":unix:utf8");
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

my $CSS_DIR = FullDirectoryPath('CSS_DIR');
my $JS_DIR = FullDirectoryPath('JS_DIR');
my $ToDoPath = FullDirectoryPath('TODODATAPATH');

# Master date stamp: time stamp for last save of TODO data.
my $MasterDateStamp = '';

my %RequestAction;
$RequestAction{'req|main'} = \&ToDoPage; 			# req=main
$RequestAction{'req|css'} = \&GetRequestedFile; 	# req=css
$RequestAction{'req|js'} = \&GetRequestedFile; 		# req=js
#$RequestAction{'req|getputdatajs'} = \&GetPutDataJS; # req=getputdatajs - NOT USED
$RequestAction{'req|getData'} = \&GetData; 			# req=getData
$RequestAction{'req|getModDate'} = \&DataModDate; 	# req=getModDate
$RequestAction{'data'} = \&PutData; 				# data=the todo list
$RequestAction{'signal'} = \&HandleToDoSignal; 		# signal = anything, but for here specifically signal=allServersUp
#$RequestAction{'req|id'} = \&Identify; 			# req=id - now done by swarmserver.pm#ServerIdentify()

# Over to swarmserver.pm.
MainLoop(\%RequestAction);

################### subs

# 2020-03-11 14_09_25-To Do.png
sub ToDoPage {
	my ($obj, $formH, $peeraddress) = @_;

	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<title>To Do</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
<!--
<link rel="stylesheet" type="text/css" href="jquery.ui.min.css" />
-->
<link rel="stylesheet" type="text/css" href="jquery-ui.min.css" />

<link rel="stylesheet" type="text/css" href="todo.css" />

</head>
<body>
_TOPNAV_
<div id="scrollAdjustedHeight">
<div id="header"> To Do List <span id="loadError">&nbsp;<span></div>
<!-- <div id="theTextWithoutJumpList"> -->
	<div id="container">
		<div class="task-list task-container" id="pending">
			<h3>To Do</h3>
			<!--<div class="todo-task">
				<div class="task-header">Sample Header</div>
				<div class="task-date">25/06/1992</div>
				<div class="task-description">Lorem Ipsum Dolor Sit Amet</div>
			</div>-->
		</div>

		<!-- Comment out div below to remove "In Progress" -->
		<div class="task-list task-container" id="inProgress">
			<h3>Doing</h3>
		</div>
		
		<div class="task-list task-container" id="completed">
			<h3>Done</h3>
		</div>

		<div class="task-list">
			<h3>Add/Edit a Task</h3><p id="addedittasknote">Drag here to edit</p>
			<form id="todo-form">
				<input type="text" placeholder="Title" />
				<textarea rows="10" placeholder="Description, optional"></textarea>
				<input type="text" id="datepicker" placeholder="Due Date (yy/mm/dd), optional" />
				<input type="button" class="btn btn-primary" value="Save" onclick="todo.add();" />
				<input type="hidden" value="1" />
			</form>

			<!-- <input type="button" class="btn btn-primary" value="Clear Data" onclick="todo.clear();" /> -->

			<div id="delete-div" class="delete-div-class">
				Drag Here to Delete
			</div>
		</div>

		<div style="clear:both;"></div>
	</div>
<!-- </div> -->
</div>


<script src="jquery.min.js"></script>


<!-- too many errors
<script src="jquery-3.4.1.min.js"></script>
-->


<script src="jquery.ui.min.js"></script>


<!-- also errors
<script src="jquery-ui.min.js"></script>
-->


<script src="jquery.ui.touch-punch.min.js"></script>

<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="tooltip.js"></script>
<script>
let thePort = '_THEPORT_';
let mainPort = '_MAINPORT_';
let sseServerShortName = 'SSE_SERVER_SHORT_NAME';
let contentID = '_CONTENTID_';
</script>
<script src="todoGetPutData.js"></script>
<script src="todo.js"></script>
<script src="todoEvents.js"></script>
<script src="todoLinks.js"></script>
</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);
	$theBody =~ s!_TOPNAV_!$topNav!;
	
	$theBody =~ s!_CSS_DIR_!$CSS_DIR!g;
	$theBody =~ s!_JS_DIR_!$JS_DIR!g;
	
	# $peeraddress eq '127.0.0.1' determines whether we are local.
	# The IPv4 Address for this server is  (eg 192.168.0.14);
	my $serverAddr = ServerAddress();
	my $mainServerPort = MainServerPort();
	my $host = $serverAddr;
	my $port = $port_listen;
	my $sseServerShortName = CVal('ACTIVITY_MONITOR_SHORT_NAME');
	$theBody =~ s!_THEPORT_!$port!g;
	$theBody =~ s!_MAINPORT_!$mainServerPort!g;
	$theBody =~ s!SSE_SERVER_SHORT_NAME!$sseServerShortName!;
	
	my $contentID = 'scrollAdjustedHeight';
	$theBody =~ s!_CONTENTID_!$contentID!g;
	
	# Put in main IP, main port, our short name for JavaScript.
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()

	return $theBody;
	}

# 'req|dataModDate': returns $MasterDateStamp.
sub DataModDate {
	my ($obj, $formH, $peeraddress) = @_;
	return($MasterDateStamp);
	}

# 'req|getData': return raw contents of the ToDo data file.
sub GetData {
	my ($obj, $formH, $peeraddress) = @_;
	my $filePath = $ToDoPath;
	my $result = ReadBinFileWide($filePath);
	if ($result eq '')
		{
		$result = '{"items":[]}';
		}
	else
		{
		if ($MasterDateStamp eq '')
			{
			$MasterDateStamp = GetFileModTimeWide($filePath) . '';
			}
		}
	return($result);
	}

# data=...
# Called by todoGetPutData.js#putData().
# Set $MasterDateStamp, return that or 'FILE ERROR...'.
# Save all data in $formH->{'data'} to the ToDo data file.
# Send a Server-Sent Event to all running instances of this page to let them know
# a reload is needed. In todoEvents.js#requestSSE() a listener is added for
# "todochanged" SSE's, which calls todoGetPutData.js#getToDoData().
# (Under the hood, the $formH->{'data'} value is picked up by swarmserver.pm#GrabArguments().)
sub PutData {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = '';
	my $filePath = $ToDoPath;
	my $data = $formH->{'data'};
	
	my $didit = WriteBinFileWide($filePath, $data);
	my $tryCount = 0;
	while (!$didit && ++$tryCount <= 3)
		{
		sleep(1);
		$didit = WriteBinFileWide($filePath, $data);
		}
	
	if (!$didit)
		{
		$result = "FILE ERROR! Could not access todo file |$filePath|.\n";
		}
	else
		{
		# Set $MasterDateStamp.
		$MasterDateStamp = GetFileModTimeWide($filePath) . '';
		$result = $MasterDateStamp;
		# Let other servers know if overdue count has changed.
		BroadcastOverdueCount();
		# Let other ToDo clients know ToDo data has changed.
		BroadcastSSE('todochanged', $SHORTNAME); # swarmserver.pm#BroadcastSSE()
		}
	return($result);
	}

# 'signal' handler, here we are interested in 'signal=allServersUp', and 'dayHasChanged'.
# This is called eg in response to 'signal=allServersUp' as broadcasted by intramine_main.pl#BroadcastAllServersUp(),
# which is called when all expected servers report in main that they are up and running.
# intramine_main.pl also sends a 'dayHasChanged' in BroadcastDateHasChanged().
# Return value is ignored.
# We have jumped through a lot of hoops to reach this point:
#  - IntraMine starts
#  - all swarm servers notify main when they have fully started
#  - main sends 'signal=allServersUp' to all running servers, most of which ignore it
#  - this server reacts here by calculating the number of overdue ToDo items.
#  - the count is sent back to main, which then (re)broadcasts the count to all running page servers. In this case,
#    all (main) page servers are interested, since the overdue count is shown in the top nav for each page
#  - after that, any new or refreshed page will show the current overdue count in the nav bar.
# And the overdue count is recalculated and rebroadcasted if we go past midnight into a new day.
sub HandleToDoSignal {
	my ($obj, $formH, $peeraddress) = @_;
	if (  defined($formH->{'signal'})
	  && ($formH->{'signal'} eq 'allServersUp' || $formH->{'signal'} eq 'dayHasChanged') )
		{
		BroadcastOverdueCount();
		}

	return('OK');	# Returned value is ignored by broadcaster - this is more of a "UDP" than "TCP" approach to communicating.
	}

# Ask Main to broadcast an overdue signal to all Page servers.
sub BroadcastOverdueCount {
	my $overdueCount = GetOverdueCount();
	RequestBroadcast("signal=todoCount&count=$overdueCount&name=PageServers");
	}

# NOTE this is fragile, depends on format of /data/ToDo.txt.
# Return number of pending ("code":"1") items that are due today or earlier.
sub GetOverdueCount {
	my $overdueCount = 0;
	
	# Load file in one lump (typically it's a one-liner).
	my $data = GetData(undef, undef, undef); # standard args aren't needed for this sub
	my @dates;
	# Items are in no particular order, so we look for all "code":"1" items. Typical item:
	# "code":"1","title":"INCOME TAX!","date":"2016/04/25"
	while ($data =~ m!\"code\"\:\"1\".+?date\"\:\"(\d\d\d\d)/(\d\d)/(\d\d)\"!g)
		{
		my $date = $1 . $2 . $3;
		push @dates, $date;
		}
	my $today = DateYYYYMMDD();
	my $numDates = @dates;
	for (my $i = 0; $i < $numDates; ++$i)
		{
		if ($dates[$i] <= $today)
			{
			++$overdueCount;
			}
		}
	
	return($overdueCount);
	}
