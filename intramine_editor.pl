# intramine_editor.pl ("Editor"): a file editor using CodeMirror.
# This Editor does not have an entry in the top navigation bar. It's invoked by clicking
# on an "edit" link. These can be found as pencil icons in Search result hits, file lists
# under Files, autolinks within read-only views, and as Edit buttons in read-only views.
# CodeMirror is used for all edit views here, and it does all of the work of
# presenting an editable view of a file complete with syntax highlighting - see editor.js.
# This Perl file puts up the basic HTML for the view and provides load and save subs.
# A typical url that calls up an Editor view is
# http://192.168.1.132:43128/Editor/?href=C:/perlprogs/mine/test/googlesuggest.cpp&rddm=49040
# which triggers the 'href' handler FullFile() via the %RequestAction entry below.
# editor.js#loadFileIntoCodeMirror() then calls LoadTheFile() here with a 'req=loadfile' request.

# perl C:\perlprogs\mine\intramine_editor.pl server_port our_listening_port

use strict;
use warnings;
use utf8;
use FileHandle;
use Encode;
use Encode::Guess;
use HTML::Entities;
use Text::Tabs;
$tabstop = 4;
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

my %RequestAction;
$RequestAction{'href'} = \&FullFile; 			# href=anything, treated as a file path
$RequestAction{'req|loadfile'} = \&LoadTheFile; # req=loadfile
$RequestAction{'req|save'} = \&Save; 			# req=save
# not needed, done in swarmserver: $RequestAction{'req|id'} = \&Identify; # req=id

# Over to swarmserver.pm.
MainLoop(\%RequestAction);

################### subs
sub FullFile {
	my ($obj, $formH, $peeraddress) = @_;
	my $theBody = <<'FINIS';
<!doctype html>
<html lang="en"><head>
<meta http-equiv="content-type" content="text/plain; charset=utf-8">
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="apple-touch-fullscreen" content="yes" />
<title>_TITLE_</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="forms.css" />
<link rel="stylesheet" type="text/css" href="lib/codemirror.css" />
<link rel="stylesheet" type="text/css" href="addon/dialog/dialog.css" />
<link rel="stylesheet" type="text/css" href="addon/search/matchesonscrollbar.css" />
<link rel="stylesheet" type="text/css" media="screen" href="cm_edit.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />

<script type="text/javascript" src="tooltip.js"></script>

<script type="text/javascript">
let thePath = '_PATH_';
let theEncodedPath = '_ENCODEDPATH_';
let usingCM = _USING_CM_;
let cmTextHolderName = '_CMTEXTHOLDERNAME_';
let ourServerPort = '_THEPORT_';
let errorID = "editor_error";
</script>
</head>
<body>
<div id="indicator"></div> <!-- iPad scroll indicator -->
_TOPNAV_
<span id="viewEditTitle">_TITLEHEADER_</span>_SAVEACTION_ _ARROWS_ _SEARCH_ _UNDOREDO_ <span id="editor_error">&nbsp;</span>
<hr id="rule_above_editor" />
<div id='scrollAdjustedHeight'><div id='scrollText'></div></div>

<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="todoFlash.js"></script>
<script type="text/javascript" src="lib/codemirror.js" ></script>
<!-- script type="text/javascript" src="mode/javascript/javascript.js"></script> -->
<script type="text/javascript" src="addon/mode/loadmode.js"></script>
<script type="text/javascript" src="mode/meta.js"></script>

<script src="addon/dialog/dialog.js"></script>
<script src="addon/search/searchcursor.js"></script>
<script src="addon/search/search.js"></script>
<script src="addon/scroll/annotatescrollbar.js"></script>
<script src="addon/search/matchesonscrollbar.js"></script>
<script src="addon/search/match-highlighter.js"></script>
<script src="addon/search/jump-to-line.js"></script>
<script src="debounce.js"></script>
<script type="text/javascript" src="editor.js" ></script>
<script type="text/javascript" src="cmMobile.js" ></script>
</body></html>
FINIS
	
	# The file path may arrive here as $formH->{'href'}, or in $obj as
	# Editor/Open/filepath... where file path continues to '/?' or end of $obj.
	my $filePath = '';
	if (defined($filePath = $formH->{'href'}))
		{
		$filePath = $formH->{'href'};
		}
	my $fileContents = '<p>Read error!</p>';
	my $title = $filePath . ' NOT RETRIEVED!';
	
	my $serverAddr = ServerAddress();
	my $host = $serverAddr;
	my $port = $port_listen;
	
	my $topNav = TopNav($PAGENAME);
	$theBody =~ s!_TOPNAV_!$topNav!;
	
	if (FileOrDirExistsWide($filePath) == 1)
		{
		$title = $filePath;
		}

	my $ctrlSPath = $filePath;
	$ctrlSPath = encode_utf8($ctrlSPath);
	$ctrlSPath =~ s!%!%25!g;
	$ctrlSPath =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
	$ctrlSPath =~ s!'!\\'!g;
	
	# Buttons:
	my $saveAction = "<input onclick=\"saveFile('$ctrlSPath');\" id=\"save-button\" class=\"submit-button\" type=\"submit\" value=\"Save\" />";
	$theBody =~ s!_SAVEACTION_!$saveAction!;
	my $arrows = "<img src='left3.png' id='left2' class='img-arrow-left'> " .
				 "<img src='up3.png' id='up2' class='img-arrow-up'> " .
				 "<img src='down3.png' id='down2' class='img-arrow-down'> " .
				 "<img src='right3.png' id='right2' class='img-arrow-right'> ";
	# With CodeMirror, I don't think the on-screen arrow keys will be needed:
	$theBody =~ s!_ARROWS_!!;
	#$theBody =~ s!_ARROWS_!$arrows!;
	my $search = "<input id=\"search-button\" class=\"submit-button\" type=\"submit\" value=\"Find\" />";
	$theBody =~ s!_SEARCH_!$search!;
	my $undoRedo =  "<input id=\"undo-button\" class=\"submit-button\" type=\"submit\" value=\"Undo\" /> " .
					"<input id=\"redo-button\" class=\"submit-button\" type=\"submit\" value=\"Redo\" />";
	$theBody =~ s!_UNDOREDO_!$undoRedo!;

	# Full path is unhelpful in the <title>, trim down to just file name.
	my $fileName = FileNameFromPath($title);
	$fileName = &HTML::Entities::encode($fileName);
	$theBody =~ s!_TITLE_!$fileName!;
	# Flip the slashes for file path in _TITLEHEADER_ at top of the page, for the "traditional" look.
	$title =~ s!/!\\!g;
	$title = &HTML::Entities::encode($title);
	$theBody =~ s!_TITLEHEADER_!$title!;

	# Watch out for apostrophe in path, it's a killer in the JS above.
	$filePath =~ s!'!\\'!g;
	$theBody =~ s!_PATH_!$filePath!g;
	$theBody =~ s!_ENCODEDPATH_!$ctrlSPath!g;
	
	my $cmTextHolderName = 'scrollText';
	$theBody =~ s!_CMTEXTHOLDERNAME_!$cmTextHolderName!g;
	my $usingCM = 'true';
	$theBody =~ s!_USING_CM_!$usingCM!;

	$theBody =~ s!_THEPORT_!$port!g;
	
	# Put in main IP, main port, our short name for JavaScript.
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()
	
	return $theBody;	
	}

# See editor.js#loadFileIntoCodeMirror(), which calls back here with "req=open",
# which calls this sub, see %RequestAction above.
# The contents from here are fed into CodeMirror for display.
sub LoadTheFile {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = '';

	my $filepath = defined($formH->{'file'})? $formH->{'file'}: '';
	if ($filepath ne '')
		{
		$result = uri_escape_utf8(ReadTextFileDecodedWide($filepath));
		#####$result = uri_escape_utf8(ReadTextFileWide($filepath));
		}
	
	return($result);		
	}

# See editor.js#loadFileIntoCodeMirror(), which calls back here with "req=open",
# which calls this sub, see %RequestAction above.
# The contents from here are fed into CodeMirror for display.
sub olderLoadTheFile {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = '';

	my $filepath = defined($formH->{'file'})? $formH->{'file'}: '';
	if ($filepath ne '')
		{
		my $ctrlSPath = $filepath;
		$ctrlSPath = encode_utf8($ctrlSPath);
		$ctrlSPath =~ s!%!%25!g;
		$ctrlSPath =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
		$result = GetHtmlEncodedTextFile($filepath);
		}
	
	return($result);		
	}

# Called by editor.js#saveFile() (via "req=save").
sub Save {
	my ($obj, $formH, $peeraddress) = @_;
	my $status = 'OK';
	
	my $filepath = defined($formH->{'file'})? $formH->{'file'}: '';
	if ($filepath ne '')
		{
		$filepath =~ s!\\!/!g;
		Output("Saving |$filepath|\n");
		
		my $contents = $formH->{'contents'};
		$contents = encode_utf8($contents);
		$contents = uri_unescape($contents);
#		$contents = uri_unescape($contents);
#		$contents = encode_utf8($contents);
		
		if (!WriteBinFileWide($filepath, $contents)) # win_wide_filepaths.pm#WriteBinFileWide()
			{
			$status = "FILE ERROR! Could not save file to |$filepath|.\n";
			}
		}
	else
		{
		print("ERROR, file_editor received empty file path!\n");
		}
	
	return($status);
	}

# Called by editor.js#saveFile() (via "req=save").
sub olderSave {
	my ($obj, $formH, $peeraddress) = @_;
	my $status = 'OK';
	
	my $filepath = defined($formH->{'file'})? $formH->{'file'}: '';
	if ($filepath ne '')
		{
		$filepath =~ s!\\!/!g;
		# TEST ONLY codathon save to a different path.
		if ($filepath =~ m!^(.+?)\.(\w+)$!)
			{
			my $pre = $1;
			my $post = $2;
			$filepath = $pre . '1.' . $post;
			}
		else
			{
			print("FILE RENAME FAIL in Save()!\n");
			return('OK');
			}
		Output("Saving |$filepath|\n");
		
		my $contents = $formH->{'contents'};
		# TEST ONLY
		$contents =~ s!\&amp;!\&!g;
		
		$contents = encode_utf8($contents);
		
		if (!WriteBinFileWide($filepath, $contents)) # win_wide_filepaths.pm#WriteBinFileWide()
			{
			$status = "FILE ERROR! Could not save file to |$filepath|.\n";
			}
		}
	else
		{
		print("ERROR, file_editor received empty file path!\n");
		}
	
	return($status);
	}

# HTML encoded file contents, see LoadTheFile().
sub GetHtmlEncodedTextFile {
	my ($filePath) = @_;
	my $result = '';
	
	if (FileOrDirExistsWide($filePath) != 1)
	#if (!(-f $filePath))
		{
		return('');
		}
	else
		{
		return(GetHtmlEncodedTextFileWide($filePath)); # win_wide_filepaths.pm#GetHtmlEncodedTextFileWide()
		}
	}
