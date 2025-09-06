# intramine_reindex.pl: a service to rebuild the
# Elasticsearch index, set directories to monitor,
# and build a list of full paths of interest
# from the contents of those directories.
# Directories are listed in data/search_directories.txt.
# ri.pl is run to do the actual work.
#
# See also Documentation/Reindex.html.
#

# To start and run this service see Documentation/Reindex.html (or .txt).

# perl c:\perlprogs\IntraMine\intramine_reindex.pl

use strict;
use warnings;
use utf8;
use Win32;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use win_wide_filepaths;
use swarmserver;
use cmd_monitor;

binmode(STDOUT, ":encoding(UTF-8)");
Win32::SetConsoleCP(65001);

$| = 1;

my $PAGENAME    = '';
my $SHORTNAME   = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

my $kLOGMESSAGES     = 0;    # 1 == Log Output() messages, and print to console window
my $kDISPLAYMESSAGES = 0;    # 1 == just print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print. See swarmserver.pm#Output().
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);
Output("Starting $SHORTNAME on port $port_listen\n\n");

my $LogDir = FullDirectoryPath('LogDir');
InitCommandMonitoring($LogDir . 'temp/tempout', 'REINDEX');

my $UseAppForLocalEditing  = CVal('USE_APP_FOR_EDITING');
my $UseAppForRemoteEditing = CVal('USE_APP_FOR_REMOTE_EDITING');
my $AllowLocalEditing      = CVal('ALLOW_LOCAL_EDITING');
my $AllowRemoteEditing     = CVal('ALLOW_REMOTE_EDITING');

my %RequestAction;
$RequestAction{'req|main'}    = \&OurPage;               # req=main
$RequestAction{'req|open'}    = \&RunTheCommand;         # req=open, called by Reindex button
$RequestAction{'req|ping'}    = \&MainServerResponse;    # req=ping
$RequestAction{'req|monitor'} = \&CommandOutput;         # req=monitor

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
<h2>IGNORE list</h2>
<table id="ignore_table">
_IGNORE_LIST_
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
<script src="restart.js"></script>
<script src="topnav.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
<script src="cmd_monitor_WS.js"></script>
<script src="tooltip.js"></script>
<script src="viewerLinks.js"></script>
<script src="cmd_monitor.js"></script>
<script src="reindex.js"></script>
</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);    # The top navigation bar, with our page name highlighted
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
	if (   $peeraddress ne '127.0.0.1'
		&& $peeraddress ne $serverAddr)    #if ($peeraddress ne $serverAddr)
										   #if ($peeraddress ne '127.0.0.1')
		{
		$clientIsRemote = 1;
		}

	my $allowEditing =
		(($clientIsRemote && $AllowRemoteEditing) || (!$clientIsRemote && $AllowLocalEditing));
	my $useAppForEditing = 0;
	if ($allowEditing)
		{
		$useAppForEditing = (($clientIsRemote && $UseAppForRemoteEditing)
				|| (!$clientIsRemote && $UseAppForLocalEditing));
		}

	my $amRemoteValue      = $clientIsRemote     ? 'true' : 'false';
	my $tfAllowEditing     = ($allowEditing)     ? 'true' : 'false';
	my $tfUseAppForEditing = ($useAppForEditing) ? 'true' : 'false';
	my $port               = $port_listen;

	$theBody =~ s!_WEAREREMOTE_!$amRemoteValue!;
	$theBody =~ s!_ALLOW_EDITING!$tfAllowEditing!;
	$theBody =~ s!_USE_APP_FOR_EDITING!$tfUseAppForEditing!;

	my $editorShortName = CVal('EDITORSHORTNAME');
	$theBody =~ s!_EDITORSHORTNAME_!$editorShortName!;
	$theBody =~ s!_THEPORT_!$port!;

	my ($folderList, $ignoreList) = ReindexFolderList();
	$theBody =~ s!_FOLDER_LIST_!$folderList!;
	$theBody =~ s!_IGNORE_LIST_!$ignoreList!;

	# Note the Reindex button must be made before Edit button, so that
	# Reindex has an id of Cmd1. Edit button's id Cmd2 is stripped.
	# If it were made first, there would be no Cmd1 id and
	# the Reindex button would not be disabled during a run.
	# A bit ugly, sorry about that.
	my $reindexButton = ReindexButton();
	$theBody =~ s!_REINDEX_BUTTON_!$reindexButton!;

	my $editButton = EditButton($peeraddress);
	$theBody =~ s!_EDIT_BUTTON_!$editButton!;


	# Put in main IP, main port (def. 81), and our Short name (Reindex) for JavaScript.
	# These are needed in intramine_config.js for example
	PutPortsAndShortnameAtEndOfBody(\$theBody);   # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()

	return ($theBody);
}

sub ReindexDescription {
	my $title       = "Rebuild Elasticsearch index and set directories to monitor";
	my $description = '<h2>' . $title . '</h2>' . "\n";
	$description .= "<p>Edit will open your data/search_directories.txt file where";
	$description .= " you can adjust your folders to index or monitor";
	$description .= " (instructions are at the top).</p>\n";

	$description .= "<p>Reindex will replace your current Elasticsearch index";
	$description .= "  and rebuild your full paths list. IntraMine will continue to run.</p>\n";

	$description .= "<p>Note you will be asked to Run as administrator.</p>\n";

	return $description;
}

# A button to bring up data/search_directories.txt in an editor.
sub EditButton {
	my ($peeraddress) = @_;

	my $button         = '';
	my $serverAddr     = ServerAddress();
	my $clientIsRemote = 0;
	# If client is on the server then peeraddress can be either 127.0.0.1 or $serverAddr:
	# if client is NOT on the server then peeraddress is not 127.0.0.1 and differs from $serverAddr.
	if ($peeraddress ne '127.0.0.1' && $peeraddress ne $serverAddr)
		{
		$clientIsRemote = 1;
		}

	if (!$clientIsRemote)
		{
		my $serverDirectory = BaseDirectory();    # intramine_config.pm#BaseDirectory()
		$button = OneCommandButton(
			$serverDirectory . "data/search_directories.txt",
			'Edit search_directories.txt',
			0, 0, "editButton"
		);
		# Strip id=Cmd2 to avoid having button disabled during a Reindex.
		$button =~ s!\s+id\=\'Cmd\d\'!!;
		}
	else
		{
		my $searchDirectoriesPath = FullDirectoryPath('ELASTICSEARCHDIRECTORIESPATH');
		$button =
			  "<a href=\"$searchDirectoriesPath\" onclick=\"editOpen(this.href); return false;\">"
			. "<input class=\"submit-button\" type=\"submit\" value=\"Edit search directories\">"
			. "</a>";
		}

	return ($button);
}

sub ReindexFolderList {
	my $skipComments = 1;
	my ($list, $ignoreList) = ReadIndexList($skipComments);
	return ($list, $ignoreList);
}

# Return a list of directories with index and monitor 0/1 values
# from data/search_directories.txt, as an HTML table.
# Comments are optionally skipped, to keep the list short.
sub ReadIndexList {
	my ($skipComments) = @_;

	my $searchDirectoriesPath = FullDirectoryPath('ELASTICSEARCHDIRECTORIESPATH');
	my $list                  = ReadTextFileDecodedWide($searchDirectoriesPath);
	my @lines                 = split(/\n/, $list);
	my @tableLines;
	my $ignoreList       = '';
	my @ignoreTableLines = '';

	my $firstLine     = $lines[0];
	my $firstLineToDo = 0;
	if ($firstLine =~ m!location\t+index\t+monitor!i)
		{
		$firstLineToDo = 1;
		}
	my $headerRow = "<tr><th>Location</th><th>Index</th><th>Monitor</th></tr>";
	push @tableLines, $headerRow;
	my $ignoreHeaderRow = "<tr><th>Location</th></tr>";
	push @ignoreTableLines, $ignoreHeaderRow;

	for (my $i = $firstLineToDo ; $i < @lines ; ++$i)
		{
		my $line = $lines[$i];
		$line =~ s!\\!/!g;
		my $nextRow       = '';
		my $nextIgnoreRow = '';
		if (length($line) && $line !~ m!^\s*#!)
			{
			my @kv               = split(/\t+/, $line, 3);
			my $numEntriesOnLine = @kv;
			if ($numEntriesOnLine == 3)
				{
				my $dir    = $kv[0];
				my $exists = (FileOrDirExistsWide($dir) == 2);
				if (!$exists && $dir eq '_INTRAMINE_')
					{
					$exists = 1;
					}

				if ($exists)
					{
					$nextRow = "<tr><td>$kv[0]</td><td>$kv[1]</td><td>$kv[2]</td></tr>";
					}
				else
					{
					$nextRow =
"<tr><td><span class='badDirectory'>$kv[0]</span></td><td>$kv[1]</td><td>$kv[2]</td></tr>";
					}
				}
			elsif ($numEntriesOnLine == 2 && $kv[0] =~ m!IGNORE!i)
				{
				my $dir    = $kv[1];
				my $exists = (FileOrDirExistsWide($dir) == 2);
				if ($exists)
					{
					$nextIgnoreRow = "<tr><td>$dir</td></tr>";
					}
				else
					{
					$nextIgnoreRow = "<tr><td><span class='badDirectory'>$dir</span></td></tr>";
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
		elsif ($nextIgnoreRow ne '')
			{
			push @ignoreTableLines, $nextIgnoreRow;
			}
		}

	# Embolden the main folder part of an IGNORE subfolder.
	for (my $i = 0 ; $i < @ignoreTableLines ; ++$i)
		{
		my $ig = lc($ignoreTableLines[$i]);
		for (my $j = 0 ; $j < @tableLines ; ++$j)
			{
			my $line = lc($tableLines[$j]);
			# "<tr><td>$kv[0]</td><td>$kv[1]</td><td>$kv[2]</td></tr>"
			if ($line =~ m!^<tr><td>([^<]+)<!)
				{
				my $dir = $1;
				if ($ig =~ m!$dir!i)
					{
					$ignoreTableLines[$i] =~ s!$dir!<strong>$dir</strong>!i;
					last;
					}
				}
			}
		}
	$list       = join("\n", @tableLines);
	$ignoreList = join("\n", @ignoreTableLines);
	return ($list, $ignoreList);
}

# The "reindex" button (see _REINDEX_BUTTON_ above).
# IM_REINDEX.bat calls ri.pl to do the actual reindexing.
sub ReindexButton {
	my $serverDirectory = BaseDirectory();    # intramine_config.pm#BaseDirectory()
	my $btn = OneCommandButton($serverDirectory . 'bats/IM_REINDEX.bat', 'Reindex', 0, 1,
		"reindexButton");

	return ($btn);
}

# Called in response to req=open request.
# See cmd_monitor.js#runTheCommand() for the call.
sub RunTheCommand {
	my ($obj, $formH, $peeraddress) = @_;

	my $ignoreProc = 1;
	my $status     = _RunTheCommand($obj, $formH, $peeraddress, $ignoreProc);
	return ($status);
}
