# DO NOT USE, it just doesn't work.
# intramine_reindex.pl: an attempt at providing a service to rebuild the
# Elasticsearch index and set directories to monitor.
# In the end, I couldn't improve on IM_INIT_INDEX.bat and gave up.

# perl c:\perlprogs\IntraMine\intramine_reindex.pl

use strict;
use warnings;
use utf8;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use win_wide_filepaths;
use swarmserver;
use cmd_monitor;

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

my $LogDir = FullDirectoryPath('LogDir');
InitCommandMonitoring($LogDir . 'temp/tempout', 'REINDEX');

my $UseAppForLocalEditing = CVal('USE_APP_FOR_EDITING');
my $UseAppForRemoteEditing = CVal('USE_APP_FOR_REMOTE_EDITING');
my $AllowLocalEditing = CVal('ALLOW_LOCAL_EDITING');
my $AllowRemoteEditing = CVal('ALLOW_REMOTE_EDITING');

my %RequestAction;
$RequestAction{'req|main'} = \&OurPage; 			# req=main
$RequestAction{'req|open'} = \&RunTheCommand; 			# req=open
$RequestAction{'req|ping'} = \&MainServerResponse; 		# req=ping
$RequestAction{'req|monitor'} = \&CommandOutput; 		# req=monitor
#$RequestAction{'req|reindex'} = \&Reindex; 			# req=reindex

MainLoop(\%RequestAction);

################# subs

sub OurPage {
	my ($obj, $formH, $peeraddress) = @_;

	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>Reindex</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="forms.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
<link rel="stylesheet" type="text/css" href="reindex.css" />
</head>
<body>
_TOPNAV_
_DESCRIPTION_
<div id='top_buttons'>_EDIT_BUTTON_ _REINDEX_BUTTON_ <span id='running'></span>
</div>
<div id="runmessage">&nbsp;</div>
<h2>Directory list</h2>
<table id="directories_table">
_FOLDER_LIST_
</table>
<div id="cmdcontainer">
 
</div>
<div id='cmdOutputTitle'>&nbsp;</div>
<div id='scrollAdjustedHeight'>
	<div id='theTextWithoutJumpList'>
	&nbsp;
	</div>
</div>
<script>
let thePort = '_THEPORT_';
let weAreRemote = _WEAREREMOTE_;
let allowEditing = _ALLOW_EDITING;
let useAppForEditing = _USE_APP_FOR_EDITING;
let runMessageDiv = 'runmessage';
let commandContainerDiv = 'cmdcontainer';
let commandOutputDiv = 'theTextWithoutJumpList';
let cmdOutputContainerDiv = 'scrollAdjustedHeight';
let dirtable = 'directories_table';
let editorShortName = '_EDITORSHORTNAME_';
let errorID = "runMessageDiv";
</script>
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
<script src="cmd_monitor_WS.js"></script>
<script src="tooltip.js"></script>
<script src="viewerLinks.js"></script>
<script src="cmd_monitor.js"></script>
<script src="reindex.js"></script>
</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);		# The top navigation bar, with our page name highlighted
	$theBody =~ s!_TOPNAV_!$topNav!;

	my $description = ReindexDescription();
	$theBody =~ s!_DESCRIPTION_!$description!;

	InitCommandStrings();

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
	
	my $allowEditing = (($clientIsRemote && $AllowRemoteEditing) 
						|| (!$clientIsRemote && $AllowLocalEditing));
	my $useAppForEditing = 0;
	if ($allowEditing)
		{
		$useAppForEditing = (($clientIsRemote && $UseAppForRemoteEditing)
							|| (!$clientIsRemote && $UseAppForLocalEditing));
		}

	my $amRemoteValue = $clientIsRemote ? 'true' : 'false';
	my $tfAllowEditing = ($allowEditing) ? 'true' : 'false';
	my $tfUseAppForEditing = ($useAppForEditing) ? 'true' : 'false';
	my $port = $port_listen;

	$theBody =~ s!_WEAREREMOTE_!$amRemoteValue!;
	$theBody =~ s!_ALLOW_EDITING!$tfAllowEditing!;
	$theBody =~ s!_USE_APP_FOR_EDITING!$tfUseAppForEditing!;

	my $editorShortName = CVal('EDITORSHORTNAME');
	$theBody =~ s!_EDITORSHORTNAME_!$editorShortName!;
	$theBody =~ s!_THEPORT_!$port!;

	my $folderList = ReindexFolderList();
	$theBody =~ s!_FOLDER_LIST_!$folderList!;

	# Note Reindex button must be made before Edit button, so
	# Reindex has an id of Cmd1. Edit button's id is stripped.
	# If it were made first, there would be no Cmd1 id and
	# the Reindex button would not be disabled during a run.
	# A bit ugly, sorry about that.
	my $reindexButton = ReindexButton();
	$theBody =~ s!_REINDEX_BUTTON_!$reindexButton!;

	my $editButton = EditButton($peeraddress);
	$theBody =~ s!_EDIT_BUTTON_!$editButton!;


	# Put in main IP, main port (def. 81), and our Short name (DBX) for JavaScript.
	# These are needed in intramine_config.js for example
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()
	
	return($theBody);
	}

sub Reindex {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = 'OK';

	print("Reindex started.\n");

	my $serverDirectory = BaseDirectory(); # intramine_config.pm#BaseDirectory()
	my $proc; # not used
	my $reindexBatPath = $serverDirectory . 'bats/IM_REINDEX.bat';

	# TEST ONLY
	#$reindexBatPath = $serverDirectory . 'test/test_reindex.bat';

	Win32::Process::Create($proc, $ENV{COMSPEC}, "/c $reindexBatPath", 0, CREATE_NEW_CONSOLE, ".")
			|| ($result = Win32::FormatMessage( Win32::GetLastError() ));

	if ($result ne 'OK')
		{
		print("ERROR could not start IM_REINDEX.bat: $result\n");
		}
	return($result);
	}

sub ReindexDescription {
	my $title = "Rebuild Elasticsearch index and set directories to monitor";
	my $description = '<h2>' . $title . '</h2>' . "\n";
	$description .= "<p>Edit will open your data/search_directories.txt file where";
	$description .= " you can adjust your folders to index or monitor";
	$description .= " (instructions are at the top).</p>\n";

	$description .= "<p>Reindex will replace your current Elasticsearch index";
	$description .= "  and rebuild your full paths list. IntraMine will continue to run.</p>\n";

	$description .= "<p>Note you will be asked to Run as administrator.</p>\n";

	return $description;
	}

sub EditButton {
	my ($peeraddress) = @_;

	my $button = '';
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
		my $serverDirectory = BaseDirectory(); # intramine_config.pm#BaseDirectory()
		$button = OneCommandButton($serverDirectory . "data/search_directories.txt", 'Edit search_directories.txt', 0, 0, "editButton");
		# Strip id=Cmd2 to avoid having button disabled during a Reindex.
		$button =~ s!\s+id\=\'Cmd\d\'!!;
		}
	else
		{
		my $searchDirectoriesPath = FullDirectoryPath('ELASTICSEARCHDIRECTORIESPATH');
		$button = "<a href=\"$searchDirectoriesPath\" onclick=\"editOpen(this.href); return false;\">" .
			"<input class=\"submit-button\" type=\"submit\" value=\"Edit search directories\">" . 
			"</a>";
		}

	#my $button = '<input id="editButton" class="submit-button" type="submit" value="Edit" />';

	return($button);
	}

sub ReindexFolderList {
	my $skipComments = 1;
	my $list = ReadIndexList($skipComments);
	return($list);
	}

sub ReadIndexList {
	my ($skipComments) = @_;

	my $searchDirectoriesPath = FullDirectoryPath('ELASTICSEARCHDIRECTORIESPATH');
	my $list = ReadTextFileDecodedWide($searchDirectoriesPath);
	my @lines = split(/\n/, $list);
	my @tableLines;

	my $firstLine = $lines[0];
	my $firstLineToDo = 0;
	if ($firstLine =~ m!location\t+index\t+monitor!i)
		{
		$firstLineToDo = 1;
		}
	my $headerRow = "<tr><th>Location</th><th>Index</th><th>Monitor</th></tr>";
	push @tableLines, $headerRow;

	for (my $i = $firstLineToDo; $i < @lines; ++$i)
		{
		my $line = $lines[$i];
		my $nextRow = '';
		if (length($line) && $line !~ m!^\s*#!)
			{
			my @kv = split(/\t+/, $line, 3);
        	my $numEntriesOnLine = @kv;
        	if ($numEntriesOnLine == 3)
        		{
				my $dir = $kv[0];
				my $exists = (FileOrDirExistsWide($dir) == 2);
				if (!$exists && $dir eq '_INTRAMINE_')
					{
					$exists = 1;
					}
				
				if ($exists)
					{
					$nextRow = "<tr><td>$kv[0]</td><td>$kv[1]</td><td>$kv[2]</td></tr>"
					}
				else
					{
					$nextRow = "<tr><td><span class='badDirectory'>$kv[0]</span></td><td>$kv[1]</td><td>$kv[2]</td></tr>"
					}
				}
			else
				{
				if (!$skipComments)
					{
					$nextRow = "<tr><td colspan='3'>$line</td></tr>";
					}
				}
			}
		else
			{
			if (!$skipComments)
				{
				$nextRow = "<tr><td colspan='3'>$line</td></tr>";
				}
			}
		if ($nextRow ne '')
			{
			push @tableLines, $nextRow;
			}
		}

	$list = join("\n", @tableLines);
	return($list);
	}

sub ReindexButton {
	my $serverDirectory = BaseDirectory(); # intramine_config.pm#BaseDirectory()
	my $cmdLs .= OneCommandButton($serverDirectory . 'bats/IM_REINDEX.bat', 'Reindex', 0, 1, "reindexButton");

	# TEST ONLY
	# my $cmdLs .= OneCommandButton($serverDirectory . 'test_programs/test_backwards_tell.pl', 'Reindex', 0, 1, "reindexButton");

	return($cmdLs);
	}

sub RunTheCommand {
	my ($obj, $formH, $peeraddress) = @_;

	# Make the Status light flash for this server.
	# Not needed, see cmd_monitor.js#runTheCommand.
	#ReportActivity($SHORTNAME);

	my $ignoreProc = 1;
	my $status = _RunTheCommand($obj, $formH, $peeraddress, $ignoreProc);
	return($status);
	}
