# intramine_status.pl:
# 1. Status of all running servers (UP, NOT RESPONDING, DEAD). Status is refreshed with
#    a periodic ajax call to the main server 'req=serverstatus' - see status.js#refreshStatus().
#    Start/Stop/Restart for all servers.
# 2. Add a server.
# 3. List of new/changed or deleted files.
#    This is also refreshed by status.js#refreshStatus(), which invokes a second
#    separate ajax call back to this server 'req=filestatus'
#    to update the latest lists of file system changes.
#    Only changes in folders monitored by File Watcher are reported.

# perl C:\perlprogs\mine\intramine_status.pl $server_port $port_listen

use strict;
use warnings;
use utf8;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;
use win_wide_filepaths;

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

my $FileWatcherDir = CVal('FILEWATCHERDIRECTORY');
my $CudPath = $FileWatcherDir . CVal('FWCURRENTCHANGESFILE');	# Changed Updated Deleted log path, typ. data/cud.log
my $LastCudModTime = '';
# Limit number of changed/new and deleted file paths displayed, both must separately
# be less than $STATUS_FILEDISPLAY_LIMIT;
my $STATUS_FILEDISPLAY_LIMIT = CVal('STATUS_FILEDISPLAY_LIMIT');
if ($STATUS_FILEDISPLAY_LIMIT eq '' || $STATUS_FILEDISPLAY_LIMIT < 10)
	{
	$STATUS_FILEDISPLAY_LIMIT = 10;
	}

my %RequestAction;
$RequestAction{'req|main'} = \&StatusPage; 						# req=main
$RequestAction{'req|addserverform'} = \&GetAddServerForm; 		# req=addserverform
$RequestAction{'req|filestatus'} = \&FileStatusHTML; 			# req=filestatus, return HTML tables of file changes/deletes
$RequestAction{'signal'} = \&HandleBroadcastRequest; 			# signal = anything, but for here specifically signal=filechange


# Current lists of new/changed and deleted files (full paths). These could be scoped better.
my @NewChangedFullPaths;
my @DeletedPaths;
my %EntryForPathSeen; # avoid duplicates

# Get things going. Not essential. We do intend to report changes AFTER
# this server has started, but not while it was shut down.
ReloadChangedDeletedFilesList();

# Over to swarmserver.pm.
MainLoop(\%RequestAction);

################ subs
# Status page: showing server status, an "Add one page server" form,
# and new/changed/deleted files in indexed folders.
# Called in response to eg http://localhost:81/Status
# which redirects to our port here, eg http://localhost:43138/Status/?req=main
# 2020-02-17 15_57_58-Status.png
sub StatusPage {
	my ($obj, $formH, $peeraddress) = @_;

	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>Status</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="status.css" />
<link rel="stylesheet" type="text/css" href="flashingLEDs.css" />
<link rel="stylesheet" type="text/css" href="forms.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
</head>
<body>
_TOPNAV_
<div id='headingAboveContents'>(refreshed every _STATUS_REFRESH_SECONDS_ seconds after startup)</div>
<div id="errorLine">&nbsp;</div>
<div id='scrollAdjustedHeight'>
	<div id='theTextWithoutJumpList'>
		<div id='serverStatusDetails'>
			&nbsp;
		</div>
		<div id='addServer'>
			&nbsp;
		</div>
		<div id='fileStatus'>
			&nbsp;
		</div>
	</div>
</div>
<script>
let statusRefreshMilliseconds = '_STATUS_REFRESH_MILLISECONDS_';
let thePort = '_THEPORT_';
let errorID = 'errorLine';
let fileContentID = 'fileStatus';
let serverStatusContentID = 'serverStatusDetails';
let pageServerTableId = 'PAGE_SERVER_STATUS_TABLE';
let backgroundServerTableId = 'BACKGROUND_SERVER_STATUS_TABLE';
let statusButtonClass = 'STATUS_BUTTON_HOLDER_CLASS';
let portHolderClass = 'PORT_STATUS_HOLDER_CLASS';
</script>
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="todoFlash.js"></script>
<script src="tooltip.js"></script>
<script src="status.js"></script>
<script src="sortTable.js"></script>
<script src="statusEvents.js"></script>
</body></html>
FINIS

	my $refreshMilliseconds = CVal('STATUS_REFRESH_MILLISECONDS');
	if ($refreshMilliseconds eq '' || $refreshMilliseconds < 5000)
		{
		$refreshMilliseconds = 5000;
		}
	my $refreshSeconds = int(($refreshMilliseconds + 500)/1000);
	$theBody =~ s!_STATUS_REFRESH_SECONDS_!$refreshSeconds!g;
	
	my $topNav = TopNav($PAGENAME);
	$theBody =~ s!_TOPNAV_!$topNav!;
	
	# The IPv4 Address for this server (eg 192.168.0.14);
	# peeraddress might be eg 192.168.0.17
	my $serverAddr = ServerAddress();
	
	my $port = $port_listen;
	my $mainPort = $server_port;
	my $errorID = "'errorLine'";
	my $fileContentID = "'fileStatus'";
	my $serverStatusContentID = "'serverStatusDetails'";

	$theBody =~ s!_STATUS_REFRESH_MILLISECONDS_!$refreshMilliseconds!;
	# Put in the dynamic port numbers that status.js needs to know.
	$theBody =~ s!_THEPORT_!$port_listen!;
	
	# HTML id's etc that status.js needs.
	my $pageServerTableId = CVal('PAGE_SERVER_STATUS_TABLE');
	my $backgroundServerTableId = CVal('BACKGROUND_SERVER_STATUS_TABLE');
	my $statusButtonClass = CVal('STATUS_BUTTON_HOLDER_CLASS');
	my $portHolderClass = CVal('PORT_STATUS_HOLDER_CLASS');
	$theBody =~ s!PAGE_SERVER_STATUS_TABLE!$pageServerTableId!;
	$theBody =~ s!BACKGROUND_SERVER_STATUS_TABLE!$backgroundServerTableId!;
	$theBody =~ s!STATUS_BUTTON_HOLDER_CLASS!$statusButtonClass!;
	$theBody =~ s!PORT_STATUS_HOLDER_CLASS!$portHolderClass!;
	
	# Put in main IP, main port, our short name for JavaScript.
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()
	
	return $theBody;
	}

# Collect page server names and put them in a drop down in a form.
# status.js#addServerSubmit() submits a request to Main to add a server. 
sub GetAddServerForm {
	my ($obj, $formH, $peeraddress) = @_;
	
	# Get list of short server names available, as <select> options.
	# <option value="Name">Name</option>
	my $serverOptions = GetServerNamesAsOptions();
	
	my $addDropdown = <<"DROPIT";
<select name="addOne" id="addOne"">
$serverOptions
</select>
DROPIT

	my $theSource = <<"FINIS";
<form class="form-container-small" id="ftsform" method="get" action=_ACTION_ onsubmit="addServerSubmit(this); return false;">
<span><strong>Add one page server: &nbsp;</strong></span>
$addDropdown
<div class='submitbuttonthecontainer'>
<input class="submit-button" type="submit" value="Add" />
</div>
</form>
FINIS

	# Rev May 26 2021, localhost is no longer used here.
	# Possibly required by Chrome for "CORS-RFC1918 Support". Doesn't hurt to be safe.
	my $serverAddr = ServerAddress();
	my $action = "http://$serverAddr:$server_port/?rddm=1";

	$theSource =~ s!_ACTION_!\'$action\'!;
	
	return($theSource);
	}

# Skip non-empty values in %shortNamesType (currently 'PERSISTENT', 'BACKGROUND'). The
# empty values are for Page servers.
sub GetServerNamesAsOptions {
	my $result = '';
	my %shortNamesType;
	GetShortServerNamesType(\%shortNamesType); # swarmserver.pm
	
	foreach my $name (sort keys %shortNamesType)
		{
		if ($shortNamesType{$name} eq '')
			{
			$result .= "<option value=\"$name\">$name</option>\n";
			}
		}
	
	return($result);
	}

# Generic 'signal' handler, here we are especially interested in 'signal=filechange', emitted
# by intramine_filewatcher.pl#IndexChangedFiles(). Which means for us here that
# files have been added or changed or deleted in monitored directories, so
# load up the list from $CudPath into memory, erasing oldest entries if there are too many.
# $CudPath is roughly C:\wherever intramine is\data\cud.log. (data\cud.log)
# Contents of $CudPath are refreshed by intramine_filewatcher.pl#SaveChangedFilesList().
# (cud is short for created updated deleted)
sub HandleBroadcastRequest {
	my ($obj, $formH, $peeraddress) = @_;
	if (defined($formH->{'signal'}))
		{
		if ($formH->{'signal'} eq 'filechange')
			{
			ReloadChangedDeletedFilesList();
			}
		} # 'filechange' signal

	# Returned value is ignored by broadcaster
	# - this is more of a "UDP" than "TCP" approach to communicating.
	return('OK');
	}

# Load lists of new/changed and deleted files from $CudPath, removing older entries from both
# if list size exceeds $STATUS_FILEDISPLAY_LIMIT.
# Called eg by HandleBroadcastRequest() just above.
sub ReloadChangedDeletedFilesList {
	# Load list of new file paths if $CudPath exists and has been changed (new $LastCudModTime)
	if (-f $CudPath)
		{
		my  ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
			$atime,$mtime,$ctime,$blksize,$blocks)
			= stat($CudPath);
		if ($LastCudModTime eq "" || $LastCudModTime != $mtime)
			{
			my %tempEntries;
			my $numEntries = LoadKeyTabValueHashFromFile(\%tempEntries, $CudPath, "new changed deleted files");
			
			if ($numEntries)
				{
				foreach my $path (sort keys %tempEntries)
					{
					my $action = substr($tempEntries{$path}, 0, 3);
					if ($action eq 'CHG' || $action eq 'NEW')
						{
						my $entry = $path;
						if (length($tempEntries{$path}) > 4)
							{
							# We have a time stamp, show it too.
							$entry .= "\t" . substr($tempEntries{$path}, 4);
							}
						if ($action eq 'NEW')
							{
							$entry .= " NEW";
							}
						# Avoid duplicates, which can sneak in sometimes. For example, if File Watcher is monitoring
						# a folder and also one of its subfolders. It happens.
						if (!(defined($EntryForPathSeen{$path}) && $EntryForPathSeen{$path} eq $entry))
							{
							push @NewChangedFullPaths, $entry;
							$EntryForPathSeen{$path} = $entry;
							}
						}
					elsif ($action eq 'DEL')
						{
						push @DeletedPaths, $path;
						}
					# else maintenance booboo, spank the dev.
					}
					
				# Limit number of current entries to $STATUS_FILEDISPLAY_LIMIT
				# in both @NewChangedFullPaths and @DeletedPaths.
				my $numChangedNew = @NewChangedFullPaths;
				my $overLimit = $numChangedNew - $STATUS_FILEDISPLAY_LIMIT;
				while ($overLimit-- > 0)
					{
					shift @NewChangedFullPaths;
					}
				my $numDeleted = @DeletedPaths;
				$overLimit = $numDeleted - $STATUS_FILEDISPLAY_LIMIT;
				while ($overLimit-- > 0)
					{
					shift @DeletedPaths;
					}
				}
			$LastCudModTime = $mtime;
			} # $CudPath has been modified
		} # $CudPath exists
	}

# Return two HTML tables listing 'New / Changed Files' and 'Deleted Files'.
# Called in response to 'req=filestatus' which is emitted by status.js#refreshStatus().
# Newest entries should come first, no? Which means reversing the arrays.
# The arrays are limited in length above in ReloadChangedDeletedFilesList();
sub FileStatusHTML {
	my ($obj, $formH, $peeraddress) = @_;
	
	my $result = '<table><tr><th>New / Changed Files</th></tr>' . "\n";
	my $numChangedNew = @NewChangedFullPaths;
	my @ReversedNew = reverse @NewChangedFullPaths;
	for (my $i = 0; $i < $numChangedNew; ++$i)
		{
		my $displayedPath = $ReversedNew[$i];
		my $displayedTime = '';
		if (index($displayedPath, "\t") > 0)
			{
			my @fields = split(/\t/, $displayedPath);
			$displayedTime = $fields[1];
			$displayedPath = $fields[0];
			}
		$displayedPath = encode_utf8($displayedPath);
		$displayedPath =~ s!%!%25!g;
		$displayedPath =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
		$displayedTime = encode_utf8($displayedTime);
		$displayedTime =~ s!%!%25!g;
		$displayedTime =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
		$result .= "<tr><td>$displayedPath</td><td>$displayedTime</td></tr>\n";
		}
	$result .= '</table><br>' . "\n";
	
	$result .= '<table><tr><th>Deleted Files</th></tr>' . "\n";
	my $numDeleted = @DeletedPaths;
	my @ReversedDeleted = reverse @DeletedPaths;
	for (my $i = 0; $i < $numDeleted; ++$i)
		{
		my $displayedPath = $ReversedDeleted[$i];
		$displayedPath = encode_utf8($displayedPath);
		$displayedPath =~ s!%!%25!g;
		$displayedPath =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
		$result .= "<tr><td>$displayedPath</td></tr>\n";
		}
	
	$result .= '</table>' . "\n";
	return($result);
	}
