# intramine_video.pl: show a video in a browser tab, with standard nav bar at top.
# Short name: Video. This is a second level server, under top level "Search".
# data/serverlist.txt entry:
# 1	Search				Video		intramine_video.pl


# perl C:\perlprogs\intramine\intramine_video.pl

use strict;
use warnings;
use utf8;
use FileHandle;
use Encode::Guess;
use HTML::Entities;
use URI::Escape;
use Win32::Process;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;
use win_wide_filepaths;
use win_user32_local;

$|  = 1;

my $PAGENAME = '';
my $SHORTNAME = '';
my $server_port = '';
my $port_listen = '';

my %VideMimeTypeForExtension;
$VideMimeTypeForExtension{'mp4'} = 'video/mp4';
$VideMimeTypeForExtension{'m4v'} = 'video/MP4V-ES';
$VideMimeTypeForExtension{'webm'} = 'video/webm';
$VideMimeTypeForExtension{'3gp'} = 'video/3gpp';
$VideMimeTypeForExtension{'mkv'} = 'video/x-matroska';
$VideMimeTypeForExtension{'avi'} = 'video/x-msvideo';
$VideMimeTypeForExtension{'mpeg'} = 'video/mpeg';
$VideMimeTypeForExtension{'ogv'} = 'video/ogg';
$VideMimeTypeForExtension{'ts'} = 'video/mp2t';
$VideMimeTypeForExtension{'3g2'} = 'video/3gpp2';
$VideMimeTypeForExtension{'ogg'} = 'application/ogg';


SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

my $kLOGMESSAGES = 0;			# 1 == Log Output() messages
my $kDISPLAYMESSAGES = 0;		# 1 == print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print.
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);

Output("Starting $SHORTNAME on port $port_listen\n\n");

my %RequestAction;
$RequestAction{'href'} = \&ShowVideo; 					# Open file, href = anything
#$RequestAction{'href'} = \&FullFile; 					# Open file, href = anything
#$RequestAction{'/file/'} = \&FullFile; 				# RESTful alternative, /file/is followed by file path in $obj

MainLoop(\%RequestAction);

################### subs

sub ShowVideo {
	my ($obj, $formH, $peeraddress) = @_;
	if (defined($formH->{'href'}))
		{
		$formH->{'FULLPATH'} = $formH->{'href'};
		}

	my $filePath = $formH->{'FULLPATH'};
	my $exists = FileOrDirExistsWide($filePath);
	if (!$exists)
		{
		$filePath = "Error, |$filePath| not found on disk.\n";
		}
	my $ctrlSPath = $filePath;
	$ctrlSPath = encode_utf8($ctrlSPath);
	$ctrlSPath =~ s!%!%25!g;
	$ctrlSPath =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
	my $title = $filePath;
	my $theBody = VideoFileTemplate();
	my $fileName = FileNameFromPath($title);
	$fileName = &HTML::Entities::encode($fileName);
	$theBody =~ s!_TITLE_!$fileName!;
	$title =~ s!/!\\!g;
	$title = &HTML::Entities::encode($title);
	$theBody =~ s!_TITLEHEADER_!$title!;
	# Keep this last, else a casual mention of _TITLE_ etc in the file contents
	# could get replaced by one of the above substitutions.
	my $fileContents = VideoElement($filePath);
	$theBody =~ s!_FILECONTENTS_!$fileContents!;

	my $tempFilePath = SaveTempVideoFile($theBody);
	OpenTempVideoFile($tempFilePath);
	}

sub VideoFileTemplate {
	my $theBody = <<'FINIS';
<!doctype html>
<html lang="en">
<head>
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>_TITLE_</title>
</head>
<body>
<h2>_TITLEHEADER_</h2>
_FILECONTENTS_
</body></html>
FINIS

	return($theBody);

	}

sub SaveTempVideoFile {
	my ($theBody) = @_;
	my $LogDir = FullDirectoryPath('LogDir');
	my $basePath = $LogDir . 'temp/tempvideo';
	my $randomInteger2 = random_int_between(1001, 60000);
	my $tempVideoPath = $basePath . time . $randomInteger2 . '.html';
	# TEST ONLY
	#print("SaveTempVideoFile \$tempVideoPath: |$tempVideoPath|\n");
	WriteBinFileWide($tempVideoPath, $theBody);
	return($tempVideoPath);
	}

sub OpenTempVideoFile {
	my ($tempVideoPath) = @_;
	my $proc;
	my $status = '';
	# TEST ONLY
	#print("OpenTempVideoFile \$tempVideoPath: |$tempVideoPath|\n");

	Win32::Process::Create($proc, $ENV{COMSPEC}, "/c $tempVideoPath", 0, 0, ".")
			|| ($status = Win32::FormatMessage( Win32::GetLastError() ));
	}

sub FullFile {
	my ($obj, $formH, $peeraddress) = @_;
	my $theBody = FullFileTemplate();

	if (defined($formH->{'href'}))
		{
		$formH->{'FULLPATH'} = $formH->{'href'};
		}

	my $filePath = $formH->{'FULLPATH'};
	my $title = $filePath;
	my $exists = FileOrDirExistsWide($filePath);
	my $ctrlSPath = $filePath;
	if ($exists == 1)
		{
		$title = $filePath;
		
		$ctrlSPath = encode_utf8($ctrlSPath);
		$ctrlSPath =~ s!%!%25!g;
		$ctrlSPath =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
		}
	
	# The top navigation bar, with our page name highlighted.
	# See swarmserver.pm#TopNav();
	my $topNav = TopNav($PAGENAME);				
	$theBody =~ s!_TOPNAV_!$topNav!;

	my $customCSS = '';
	$theBody =~ s!_CSS_!$customCSS!;
	my $customJS = '';
	$theBody =~ s!_JAVASCRIPT_!$customJS!;
	# Full path is unhelpful in the <title>, trim down to just file name.
	my $fileName = FileNameFromPath($title);
	$fileName = &HTML::Entities::encode($fileName);
	$theBody =~ s!_TITLE_!$fileName!;
	# Flip the slashes for file path in _TITLEHEADER_ at top of the page, for easier
	# copy/paste into notepad++ etc.
	$title =~ s!/!\\!g;
	$title = &HTML::Entities::encode($title);
	$theBody =~ s!_TITLEHEADER_!$title!;
	# Use $ctrlSPath for $filePath beyond this point.
	# Why? It works. Otherwise Unicode is messed up.
	$filePath = $ctrlSPath;
	$theBody =~ s!_PATH_!$filePath!g;
	$theBody =~ s!_ENCODEDPATH_!$ctrlSPath!g;

	# Put in main IP, main port, our short name for JavaScript.
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()

	# Keep this last, else a casual mention of _TITLE_ etc in the file contents
	# could get replaced by one of the above substitutions.
	my $fileContents = VideoElement($filePath);
	$theBody =~ s!_FILECONTENTS_!$fileContents!;

	return($theBody);
	}

sub FullFileTemplate {
	my $theBody = <<'FINIS';
<!doctype html>
<html lang="en">
<head>
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="apple-touch-fullscreen" content="yes" />
<meta name="google" content="notranslate">
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>_TITLE_</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="forms.css" />
_CSS_
<link rel="stylesheet" type="text/css" href="tooltip.css" />
<link rel="stylesheet" type="text/css" href="dragTOC.css" />
</head>
<body>
_TOPNAV_
<div id="title-block">
<span id="viewEditTitle">_TITLEHEADER_</span><br />
</div>
_FILECONTENTS_
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>

<script>
window.addEventListener('wsinit', function (e) { wsSendMessage('activity ' + shortServerName + ' ' + ourSSListeningPort); }, false);
</script>
</body></html>
FINIS

	return($theBody);
	}

sub VideoElement {
	my ($filePath) = @_;

my $theBody = <<'FINIS';
<video controls>
  <source src="_FILEPATH_"_MIMETYPE_ />
  <p>Sorry, your browser doesn't support this video.</p>
</video>
FINIS

	$filePath =~ s!\\!/!g;
	$theBody =~ s!_FILEPATH_!$filePath!;
	my $mimeType = VideoMimeTypeForPath($filePath);
	my $mimeTypeAtt = '';
	if ($mimeType ne '')
		{
		$mimeTypeAtt = " type='$mimeType'";
		}
	$theBody =~ s!_MIMETYPE_!$mimeTypeAtt!;

	return($theBody);
	}

sub VideoMimeTypeForPath {
	my ($filePath) = @_;
	my $mimeType = '';

	$filePath =~ m!\.([^.]+)$!;
	my $ext = $1;
	$ext ||= '';

	if (defined($VideMimeTypeForExtension{$ext}))
		{
		$mimeType = $VideMimeTypeForExtension{$ext};
		}
	
	return($mimeType);
	}