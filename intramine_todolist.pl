# intramine_todolist.pl: a Kanban-style TODO list using a single text (actually JSON) file.
# List is stored in one file (typ. data/ToDo.txt) so everybody sees the same list.
# ToDo tracks three categories, To Do, Doing, and Done. There are fillable fields in items for
# Title, Description and Due Date. Overdue items are emphasized with a bit of color.
# This Perl prog mainly gets things going with an HTML skeleton, and saves and loads data.
# The interface handling, and WebSockets handling, are done in JavaScript - 
# see todo.js, todoFlash.js, and todoGetPutData.js.
# jQuery is NOT used in this version.

# perl -c C:\perlprogs\IntraMine\intramine_todolist.pl

use strict;
use warnings;
use utf8;
use JSON;
use URI::Escape;
# TEST ONLY
use Data::Dumper;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use win_wide_filepaths;
use swarmserver;
use gloss;

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
# $ToDoArchivePath is same as $ToDoPath, with "Archive" added before extension.
my $ToDoArchivePath = $ToDoPath;
$ToDoArchivePath =~ s!(\.[^\.]+)!Archive$1!;

MakeArchiveFile(); # We want the archive file to always exist, so the link works.

my $OverdueCount = GetOverdueCount(); # $OverdueCount is also set in PutData().

# Master date stamp: time stamp for last save of TODO data.
my $MasterDateStamp = '';

my %RequestAction;
$RequestAction{'req|main'} = \&ToDoPage; 			# req=main
$RequestAction{'req|css'} = \&GetRequestedFile; 	# req=css
$RequestAction{'req|js'} = \&GetRequestedFile; 		# req=js
#$RequestAction{'req|getputdatajs'} = \&GetPutDataJS; # req=getputdatajs - NOT USED
$RequestAction{'req|getData'} = \&GetData; 			# req=getData
$RequestAction{'req|getModDate'} = \&DataModDate; 	# req=getModDate
$RequestAction{'req|overduecount'} = \&OverdueCount; 	# req=overduecount

$RequestAction{'data'} = \&PutData; 				# data=the todo list
$RequestAction{'saveToArchive'} = \&ArchiveOneItem; 		# saveToArchive=one ToDo item
$RequestAction{'signal'} = \&HandleToDoSignal; 		# signal = anything, but for here specifically signal=allServersUp
#$RequestAction{'req|id'} = \&Identify; 			# req=id - now done by swarmserver.pm#ServerIdentify()

# Over to swarmserver.pm.
MainLoop(\%RequestAction);

################### subs

# 2021-06-09 14_02_16-To Do.png
sub ToDoPage {
	my ($obj, $formH, $peeraddress) = @_;

	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-touch-fullscreen" content="yes">
<meta name="google" content="notranslate">
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>To Do</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="non_cm_text.css" />
<link rel="stylesheet" type="text/css" href="todo_gloss_tables.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
<!-- <link rel="stylesheet" type="text/css" href="jquery-ui.min.css" /> -->
<link rel="stylesheet" type="text/css" href="dragula.css" />
<link rel="stylesheet" type="text/css" href="datepicker.css" />
<link rel="stylesheet" type="text/css" href="todo.css" />

</head>
<body>
_TOPNAV_
<div id="header"> To Do List <span id="todoarchive">&nbsp;&nbsp;&nbsp;_ARCHIVELINK_</span> <span id="loadError">&nbsp;<span></div><div id="scrollAdjustedHeight">
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

		<div class="task-list" id="addEditTaskContainer">
			<h3>Add/Edit a Task</h3><p id="addedittasknote">Drag here to edit</p>
			<form id="todo-form">
				<input type="text" placeholder="Title" />
				<textarea rows="10" placeholder="Description, optional"></textarea>
				<input type="text" id="datepicker" placeholder="Due Date (yyyy/mm/dd), optional" />
				<input type="button" class="btn btn-primary" value="Save" onclick="todoAddNewItem();" />
				<input type="hidden" value="1" /> <!-- code, 1==ToDo 2=Doing 3=Done -->
				<input type="hidden" value="" /> <!-- Created date -->
				<input type="hidden" value="0" /> <!-- Item existed before editing -->
			</form>

			<div id="delete-div" class="delete-div-class">
				Drag Here to Delete
			</div>
		</div>

		<!-- <div style="clear:both;"></div> -->
	</div>
<!-- </div> -->
</div>


<!--
<script src="jquery.min.js"></script>
<script src="jquery.ui.min.js"></script>

<script src="jquery.ui.touch-punch.min.js"></script>
-->

<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="tooltip.js"></script>
<script>
let thePort = '_THEPORT_';

let contentID = '_CONTENTID_';

let weAreRemote = _WEAREREMOTE_;
let allowEditing = _ALLOW_EDITING_;
let useAppForEditing = _USE_APP_FOR_EDITING_;
let clientIPAddress = '_CLIENT_IP_ADDRESS_'; 	// ip address of client
let viewerShortName = '_VIEWERSHORTNAME_';
let openerShortName = '_OPENERSHORTNAME_';
let editorShortName = '_EDITORSHORTNAME_';
let errorID = "loadError";

let onMobile = false; // Set below, true if we have touch events.
if (typeof window.ontouchstart !== 'undefined')
	{
	onMobile = true;
	}

</script>
<script src="dragula.min.js"></script>
<script src="datepicker-full.min.js"></script>
<script src="websockets.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
<script src="todo.js"></script>
<script src="todoGetPutData.js"></script>
<script src="viewerLinks.js" ></script>
</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);
	$theBody =~ s!_TOPNAV_!$topNav!;
	
	$theBody =~ s!_CSS_DIR_!$CSS_DIR!g;
	$theBody =~ s!_JS_DIR_!$JS_DIR!g;
	
	# $peeraddress eq '127.0.0.1' determines whether we are local.
	# The IPv4 Address for this server is  (eg 192.168.0.14);
	my $serverAddr = ServerAddress();
	
	my $host = $serverAddr;
	my $port = $port_listen;
	$theBody =~ s!_THEPORT_!$port!g;
	
	my $contentID = 'scrollAdjustedHeight';
	$theBody =~ s!_CONTENTID_!$contentID!g;

	my $clientIsRemote = 0;
	# If client is on the server then peeraddress can be either 127.0.0.1 or $serverAddr:
	# if client is NOT on the server then peeraddress is not 127.0.0.1 and differs from $serverAddr.
	if ($peeraddress ne '127.0.0.1' && $peeraddress ne $serverAddr)	#if ($peeraddress ne $serverAddr)
	#if ($peeraddress ne '127.0.0.1')
		{
		$clientIsRemote = 1;
		}

	my $UseAppForLocalEditing = CVal('USE_APP_FOR_EDITING');
	my $UseAppForRemoteEditing = CVal('USE_APP_FOR_REMOTE_EDITING');
	my $AllowLocalEditing = CVal('ALLOW_LOCAL_EDITING');
	my $AllowRemoteEditing = CVal('ALLOW_REMOTE_EDITING');
	my $viewerShortName = CVal('VIEWERSHORTNAME');
	my $openerShortName = CVal('OPENERSHORTNAME');
	my $editorShortName = CVal('EDITORSHORTNAME');


	my $allowEditing = (($clientIsRemote && $AllowRemoteEditing) || (!$clientIsRemote && $AllowLocalEditing));
	my $useAppForEditing = 0;
	if ($allowEditing)
		{
		$useAppForEditing = (($clientIsRemote && $UseAppForRemoteEditing) || (!$clientIsRemote && $UseAppForLocalEditing));
		}
	my $amRemoteValue = $clientIsRemote ? 'true' : 'false';
	my $tfAllowEditing = ($allowEditing) ? 'true' : 'false';
	my $tfUseAppForEditing = ($useAppForEditing) ? 'true' : 'false';

	$theBody =~ s!_CLIENT_IP_ADDRESS_!$peeraddress!;
	$theBody =~ s!_VIEWERSHORTNAME_!$viewerShortName!;
	$theBody =~ s!_OPENERSHORTNAME_!$openerShortName!;
	$theBody =~ s!_EDITORSHORTNAME_!$editorShortName!;
	$theBody =~ s!_WEAREREMOTE_!$amRemoteValue!;
	$theBody =~ s!_ALLOW_EDITING_!$tfAllowEditing!;
	$theBody =~ s!_USE_APP_FOR_EDITING_!$tfUseAppForEditing!;
	
	# Link to archive file holding ToDo items more permanently.
	my $archiveLink = ArchiveLink();
	$theBody =~ s!_ARCHIVELINK_!$archiveLink!;
	
	
	# Put in main IP, main port, our short name for JavaScript.
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()

	return $theBody;
	}

# 'req|dataModDate': returns $MasterDateStamp.
sub DataModDate {
	my ($obj, $formH, $peeraddress) = @_;
	return($MasterDateStamp);
	}

# Called by AJAX "req=overduecount".
sub OverdueCount {
	my ($obj, $formH, $peeraddress) = @_;
	return($OverdueCount);
	}

# 'req|getData': return raw contents of the ToDo data file
# as "stringified" JSON. The Gloss version of the description
# is added here, as the "html" field.
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

		my $serverAddr = ServerAddress();
		my $mainServerPort = $server_port;
		my $p  = decode_json $result;
		my $arr = $p->{'items'};
		my $len = scalar(@{$arr});
		for (my $i = 0; $i < $len; ++$i)
			{
			my $ih = $arr->[$i];
			my $desc = $ih->{"description"};

			# Generate html version of text, with Gloss markdown.
			my $gloss;
			Gloss($desc, $serverAddr, $mainServerPort, \$gloss);
			$gloss = uri_escape_utf8($gloss);

			# Spurious LF's, stomp them with malice.
			$gloss =~ s!\%0A!!g;

			$ih->{"html"} = $gloss;
			
			# Creation date, add if missing.
			if (!defined($ih->{"created"}))
				{
				$ih->{"created"} = '';
				}
			}

		# Convert JSON back to text and return that.
		$result = encode_json $p;

		# TEST ONLY dump json string
		#print("GetaData JSON string: |$result|\n");
		}
	return($result);
	}

# data=...
# Called by todoGetPutData.js#putData().
# Set $MasterDateStamp, return that or 'FILE ERROR...'.
# Save all data in $formH->{'data'} to the ToDo data file.
# BroadcastOverdueCount() to all running instances of this page to let them know
# a reload is needed.
sub PutData {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = '';
	my $filePath = $ToDoPath;
	my $data = $formH->{'data'};

	$data = uri_unescape($data);

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
		
		$OverdueCount = GetOverdueCount($data);
		
		# Let other servers know if overdue count has changed.
		BroadcastOverdueCount();
		
		# SSE handling in IntraMine has been replaced by WebSockets.
		# See todoGetPutData.js#putData() for the new approach.
		# Let other ToDo clients know ToDo data has changed.
		#####BroadcastSSE('todochanged', $SHORTNAME); # swarmserver.pm#BroadcastSSE()
		# Tell all web pages that ToDo has changed. Nav bar will flash.
		#####BroadcastSSE('todoflash', $SHORTNAME);
		
		# Make the Status light flash for this server.
		ReportActivity($SHORTNAME);
		}
	return($result);
	}

# Bring up a Gloss version in the Viewer if it's running,
# otherwise just a plain text view.
sub ArchiveLink {
	my $path = $ToDoArchivePath;
	my $viewerShortName = CVal('VIEWERSHORTNAME');
	my $viewerIsRunning = ServiceIsRunning($viewerShortName);
	
	my $result = '';
	if ($viewerIsRunning)
		{
		my $host  = ServerAddress();
		my $port = $server_port;
		$result = "<a href=\"http://$host:$port/$viewerShortName/?href=$path\" target=\"_blank\">(Archived Items)</a>";
		}
	else
		{
		#$result = "<a href=\"$path\" target=\"_blank\">Archived Items</a>";
		$result = "(For archived items see $path)";
		}
	
	return($result);
	}

# The archive file (nominally data/ToDoArchive.txt) holds a history of
# ToDo items, with items added here individually as they are created
# or edited - see todo.js#todoAddNewItem();
sub ArchiveOneItem {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = 'ok';
	my $filePath = $ToDoArchivePath;
	my $data = $formH->{'saveToArchive'};

	$data = uri_unescape($data);
	
	my $item  = decode_json $data;
	my $title = $item->{"title"};
	my $description = $item->{"description"};
	my $dueDate = $item->{"date"};
	my $created = $item->{"created"};
	my $code = $item->{"code"};
	
	my $itemString = "**$title**\nDue: $dueDate    Created: $created\n$description\n---\n";

	my $didit = AppendToBinFileWide($filePath, $itemString);
	my $tryCount = 0;
	while (!$didit && ++$tryCount <= 3)
		{
		sleep(1);
		$didit = AppendToBinFileWide($filePath, $itemString);
		}
	
	if (!$didit)
		{
		$result = "FILE ERROR! Could not access todo archive file |$filePath|.\n";
		}
	
	
	return($result);
	}

# Make the ToDo archive file if it doesn't exist. This way, the link on the ToDo
# page to the archive will always work. (FLW)
sub MakeArchiveFile {
	my $filePath = $ToDoArchivePath;
	
	if (FileOrDirExistsWide($filePath) == 0)
		{
		my $helloString = "ToDo items will be archived here when you save them, newest at the bottom.\n\n";
		my $didit = AppendToBinFileWide($filePath, $helloString);
		my $tryCount = 0;
		while (!$didit && ++$tryCount <= 3)
			{
			sleep(1);
			$didit = AppendToBinFileWide($filePath, $helloString);
			}
		
		if (!$didit)
			{
			print("FILE ERROR! Could not create todo archive file |$filePath|.\n");
			}
		
		}
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
#  - the overdue count is sent back to main, which then (re)broadcasts the count to all running page servers. In this case,
#    all (main) page servers are interested, since the overdue count is shown in the top nav for each page
#  - after that, any new or refreshed page will show the current overdue count in the nav bar.
# And the overdue count is recalculated and rebroadcasted if we go past midnight into a new day. In this case, the overdue count might have changed as we ticked over past
# midnight so we get a fresh overdue count and notify using WebSockets
# because all open clients need to know immediately.
sub HandleToDoSignal {
	my ($obj, $formH, $peeraddress) = @_;
	
	if (defined($formH->{'signal'}))
		{
		if ($formH->{'signal'} eq 'allServersUp')
			{
			BroadcastOverdueCount();
			}
		elsif ($formH->{'signal'} eq 'dayHasChanged')
			{
			$OverdueCount = GetOverdueCount();
			WebSocketSend("todochanged" . $OverdueCount);
			}
		}

	return('OK');	# Returned value is ignored by broadcaster - this is more of a "UDP" than "TCP" approach to communicating.
	}

# Ask Main to broadcast an overdue signal to all Page servers.
sub BroadcastOverdueCount {	
	RequestBroadcast("signal=todoCount&count=$OverdueCount&name=PageServers");
	}

# NOTE this depends on format of /data/ToDo.txt.
# Return number of pending ("code":"1") items that are due today or earlier.
# $data should be raw data, read from $ToDoPath with ReadBinFileWide().
sub GetOverdueCount {
	my ($data) = @_;
	my $overdueCount = 0;

	if (!defined($data) || $data eq '')
		{
		$data = ReadBinFileWide($ToDoPath);
		if ($data eq '')
			{
			return(0);
			}
		}
	
	my $today = DateYYYYMMDD();
	my $p  = decode_json $data;
	my $arr = $p->{'items'};
	my $len = scalar(@{$arr});
	for (my $i = 0; $i < $len; ++$i)
		{
		my $ih = $arr->[$i];
		my $code = $ih->{"code"};
		my $date = $ih->{"date"};
		$date =~ s!/!!g;
		if ($code == 1 && $date ne "" && $date <= $today)
			{
			++$overdueCount;
			}		
		}

	return($overdueCount);
	}

