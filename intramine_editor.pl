# intramine_editor.pl ("Editor"): a file editor using CodeMirror.
# This Editor does not have an entry in the top navigation bar. It's invoked by clicking
# on an "edit" link. These can be found as pencil icons in Search result hits, file lists
# under Files, autolinks within read-only views, and as Edit buttons in read-only views.
# In rhw Editor itself, the edit link is a purple rectangle at the end of a link
# CodeMirror is used for all edit views here, and it does all of the work of
# presenting an editable view of a file complete with syntax highlighting - see editor.js.
# This Perl file puts up the basic HTML for the view and provides load and save subs.
# A typical url that calls up an Editor view is
# http://192.168.1.132:43128/Editor/?href=C:/perlprogs/mine/test/googlesuggest.cpp&rddm=49040
# which triggers the 'href' handler FullFile() via the %RequestAction entry below.
# editor.js#loadFileIntoCodeMirror() then calls LoadTheFile() here with a 'req=loadfile' request.
# The Editor also shows autolinks and hover images, and glossary popups.
#
# See also Documentation/Editor.html.
#

# perl C:\perlprogs\intramine\intramine_editor.pl server_port our_listening_port

use strict;
use warnings;
use utf8;
use FileHandle;
use Encode;
use Encode::Guess;
use HTML::Entities;
use Text::Tabs;
$tabstop = 4;
use Win32;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;
use win_wide_filepaths;
use win_user32_local;
use toc_local;

binmode(STDOUT, ":encoding(UTF-8)");
Win32::SetConsoleCP(65001);

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

my $LogDir = FullDirectoryPath('LogDir');
my $ctags_dir = CVal('CTAGS_DIR');
my $HashHeadingRequireBlankBefore = CVal("HASH_HEADING_NEEDS_BLANK_BEFORE");
InitTocLocal($LogDir . 'temp/tempctags', $port_listen, $LogDir, $ctags_dir, $HashHeadingRequireBlankBefore);

my %RequestAction;
$RequestAction{'href'} = \&FullFile; 			# href=anything, treated as a file path
$RequestAction{'req|loadfile'} = \&LoadTheFile; # req=loadfile
$RequestAction{'req|loadTOC'} = \&GetTOC; 		# req=loadTOC
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

<link rel="stylesheet" type="text/css" href="cm_editor_links.css" />
<link rel="stylesheet" type="text/css" href="cm_editor_fix.css" />
<link rel="stylesheet" type="text/css" href="dragTOC.css" />

<link rel="stylesheet" type="text/css"  href="/theme/3024-day.css">
<link rel="stylesheet" type="text/css"  href="/theme/3024-night.css">
<link rel="stylesheet" type="text/css"  href="/theme/abbott.css">
<link rel="stylesheet" type="text/css"  href="/theme/abcdef.css">
<link rel="stylesheet" type="text/css"  href="/theme/ambiance.css">
<link rel="stylesheet" type="text/css"  href="/theme/ayu-dark.css">
<link rel="stylesheet" type="text/css"  href="/theme/ayu-mirage.css">
<link rel="stylesheet" type="text/css"  href="/theme/base16-dark.css">
<link rel="stylesheet" type="text/css"  href="/theme/bespin.css">
<link rel="stylesheet" type="text/css"  href="/theme/base16-light.css">
<link rel="stylesheet" type="text/css"  href="/theme/blackboard.css">
<link rel="stylesheet" type="text/css"  href="/theme/cobalt.css">
<link rel="stylesheet" type="text/css"  href="/theme/colorforth.css">
<link rel="stylesheet" type="text/css"  href="/theme/dracula.css">
<link rel="stylesheet" type="text/css"  href="/theme/duotone-dark.css">
<link rel="stylesheet" type="text/css"  href="/theme/duotone-light.css">
<link rel="stylesheet" type="text/css"  href="/theme/eclipse.css">
<link rel="stylesheet" type="text/css"  href="/theme/elegant.css">
<link rel="stylesheet" type="text/css"  href="/theme/erlang-dark.css">
<link rel="stylesheet" type="text/css"  href="/theme/gruvbox-dark.css">
<link rel="stylesheet" type="text/css"  href="/theme/hopscotch.css">
<link rel="stylesheet" type="text/css"  href="/theme/icecoder.css">
<link rel="stylesheet" type="text/css"  href="/theme/isotope.css">
<link rel="stylesheet" type="text/css"  href="/theme/juejin.css">
<link rel="stylesheet" type="text/css"  href="/theme/lesser-dark.css">
<link rel="stylesheet" type="text/css"  href="/theme/liquibyte.css">
<link rel="stylesheet" type="text/css"  href="/theme/lucario.css">
<link rel="stylesheet" type="text/css"  href="/theme/material.css">
<link rel="stylesheet" type="text/css"  href="/theme/material-darker.css">
<link rel="stylesheet" type="text/css"  href="/theme/material-palenight.css">
<link rel="stylesheet" type="text/css"  href="/theme/material-ocean.css">
<link rel="stylesheet" type="text/css"  href="/theme/mbo.css">
<link rel="stylesheet" type="text/css"  href="/theme/mdn-like.css">
<link rel="stylesheet" type="text/css"  href="/theme/midnight.css">
<link rel="stylesheet" type="text/css"  href="/theme/monokai.css">
<link rel="stylesheet" type="text/css"  href="/theme/moxer.css">
<link rel="stylesheet" type="text/css"  href="/theme/neat.css">
<link rel="stylesheet" type="text/css"  href="/theme/neo.css">
<link rel="stylesheet" type="text/css"  href="/theme/night.css">
<link rel="stylesheet" type="text/css"  href="/theme/nord.css">
<link rel="stylesheet" type="text/css"  href="/theme/oceanic-next.css">
<link rel="stylesheet" type="text/css"  href="/theme/panda-syntax.css">
<link rel="stylesheet" type="text/css"  href="/theme/paraiso-dark.css">
<link rel="stylesheet" type="text/css"  href="/theme/paraiso-light.css">
<link rel="stylesheet" type="text/css"  href="/theme/pastel-on-dark.css">
<link rel="stylesheet" type="text/css"  href="/theme/railscasts.css">
<link rel="stylesheet" type="text/css"  href="/theme/rubyblue.css">
<link rel="stylesheet" type="text/css"  href="/theme/seti.css">
<link rel="stylesheet" type="text/css"  href="/theme/shadowfox.css">
<link rel="stylesheet" type="text/css"  href="/theme/solarized.css">
<link rel="stylesheet" type="text/css"  href="/theme/the-matrix.css">
<link rel="stylesheet" type="text/css"  href="/theme/tomorrow-night-bright.css">
<link rel="stylesheet" type="text/css"  href="/theme/tomorrow-night-eighties.css">
<link rel="stylesheet" type="text/css"  href="/theme/ttcn.css">
<link rel="stylesheet" type="text/css"  href="/theme/twilight.css">
<link rel="stylesheet" type="text/css"  href="/theme/vibrant-ink.css">
<link rel="stylesheet" type="text/css"  href="/theme/xq-dark.css">
<link rel="stylesheet" type="text/css"  href="/theme/xq-light.css">
<link rel="stylesheet" type="text/css"  href="/theme/yeti.css">
<link rel="stylesheet" type="text/css"  href="/theme/idea.css">
<link rel="stylesheet" type="text/css"  href="/theme/darcula.css">
<link rel="stylesheet" type="text/css"  href="/theme/yonce.css">
<link rel="stylesheet" type="text/css"  href="/theme/zenburn.css">
_NON_CM_THEME_CSS_

<script type="text/javascript" src="tooltip.js"></script>

<script type="text/javascript">
let thePath = '_PATH_';
let theEncodedPath = '_ENCODEDPATH_';
let usingCM = _USING_CM_;
let cmTextHolderName = '_CMTEXTHOLDERNAME_';
let tocHolderName = '_TOCHOLDERNAME_';
let ourServerPort = '_THEPORT_';
let errorID = "editor_error";

let weAreRemote = _WEAREREMOTE_;
let allowEditing = _ALLOW_EDITING_;
let useAppForEditing = _USE_APP_FOR_EDITING_;
let clientIPAddress = '_CLIENT_IP_ADDRESS_';
let viewerShortName = '_VIEWERSHORTNAME_';
let openerShortName = '_OPENERSHORTNAME_';
let editorShortName = '_EDITORSHORTNAME_';
let linkerShortName = '_LINKERSHORTNAME_';
let filesShortName = '_FILESSHORTNAME_';
let videoShortName = '_VIDEOSHORTNAME_';
let peeraddress = '_PEERADDRESS_';	// ip address of client
let b64ToggleImage = '';
let selectedTocId = '_SELECTEDTOCID_';
let doubleClickTime = _DOUBLECLICKTIME_;
let selectedTheme = '_THEME_';

let weAreEditing = true; // Don't adjust user selection or do internal links if editing.

//let onMobile = false; // mobile is going away. Too difficult to test.

</script>
</head>
<body>
<div id="indicator"></div> <!-- iPad scroll indicator -->
_TOPNAV_
<span id="viewEditTitle">_TITLEHEADER_</span>_SAVEACTION_ _REVERT_ _ARROWS_ _UNDOREDO_ _TOGGLEPOSACTION_ _SEARCH_ _CHECKSPELLING_ _VIEWBUTTON_<span id="editor_error">&nbsp;</span>
<hr id="rule_above_editor" />
<div id='scrollAdjustedHeight'>_TOCANDCONTENTHOLDER_</div>

<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="restart.js"></script>
<script src="topnav.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
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
<script src="addon/selection/active-line.js"></script>
<script src="addon/edit/matchbrackets.js"></script>
<script src="debounce.js"></script>
<script src="spellcheck.js"></script>
<script type="text/javascript" src="editor.js" ></script>
<!-- <script type="text/javascript" src="cmMobile.js" ></script> -->

<script src="isW.js" ></script>
<script src="viewerLinks.js" ></script>
<script src="cmTocAnchors.js" ></script>
<script src="cmAutoLinks.js" ></script>
<script src="showHideTOC.js" ></script>
<script src="cmShowSearchItems.js" ></script>
<script src="cmToggle.js" ></script>
<script src="cmMobile.js" ></script>
<script src="diff_match_patch_uncompressed.js" ></script>
<script src="restore_edits.js" ></script>
<script src="cmScrollTOC.js" ></script>
<script src="dragTOC.js" ></script>
<script src="go2def.js" ></script>
<script src="cmEditorHandlers.js" ></script>
<script src="editor_auto_refresh.js" ></script>
<script>
window.addEventListener('wsinit', function (e) { wsSendMessage('activity ' + shortServerName + ' ' + ourSSListeningPort); }, false);
</script>
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
	
	my $clientIsRemote = 0;
	# If client is on the server then peeraddress can be either 127.0.0.1 or $serverAddr:
	# if client is NOT on the server then peeraddress is not 127.0.0.1 and differs from $serverAddr.
	if ($peeraddress ne '127.0.0.1' && $peeraddress ne $serverAddr)	
		{
		$clientIsRemote = 1;
		}
	
	my $topNav = TopNav($PAGENAME);
	$theBody =~ s!_TOPNAV_!$topNav!;

	# Get the selected CodeMirror theme.
	my $theme = CVal('THEME');
	if ($theme eq '')
		{
		$theme = 'default';
		}

	# Determine non-CM CSS theme file. Add it in for non-CodeMirror parts of display.
	my $nonCmThemeCssFile =  NonCodeMirrorThemeCSS($theme);
	$theBody =~ s!_NON_CM_THEME_CSS_!$nonCmThemeCssFile!;
	
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
	my $revert = "<input onclick=\"revertFile('$ctrlSPath');\" id=\"revert-button\" class=\"submit-button\" type=\"submit\" value=\"Revert\" title=\"Revert to last saved version\" />";
	$theBody =~ s!_REVERT_!$revert!;
	my $arrows = "<img src='left3.png' id='left2' class='img-arrow-left'> " .
				 "<img src='up3.png' id='up2' class='img-arrow-up'> " .
				 "<img src='down3.png' id='down2' class='img-arrow-down'> " .
				 "<img src='right3.png' id='right2' class='img-arrow-right'> ";
	# With CodeMirror, I don't think the on-screen arrow keys or Find will be needed:
	$theBody =~ s!_ARROWS_!!;
	#$theBody =~ s!_ARROWS_!$arrows!;
	my $search = "<input id=\"search-button\" class=\"submit-button\" type=\"submit\" value=\"Find\" />";
	$theBody =~ s!_SEARCH_!$search!;
	my $undoRedo =  "<input id=\"undo-button\" class=\"submit-button\" type=\"submit\" value=\"Undo\" /> " .
					"<input id=\"redo-button\" class=\"submit-button\" type=\"submit\" value=\"Redo\" />";
	$theBody =~ s!_UNDOREDO_!$undoRedo!;
	# Spell check is only for .txt files in the editor.
	my $checkSpelling = '';
	if ($filePath =~ m!\.txt$!i)
		{
		$checkSpelling = "<input id=\"spellcheck-button\" class=\"submit-button\" type=\"submit\" value=\"Check\" />";
		}
	$theBody =~ s!_CHECKSPELLING_!$checkSpelling!;

	my $viewerShortName = CVal('VIEWERSHORTNAME');
	my $viewButton = ViewButton($filePath);
	$theBody =~ s!_VIEWBUTTON_!$viewButton!;
	
	
	my $togglePositionButton = '';
	# Mardown Toggle won't work because there are no line numbers.
	if ($filePath !~ m!\.md$!i)
		{
		$togglePositionButton = PositionToggle();
		}
	$theBody =~ s!_TOGGLEPOSACTION_!$togglePositionButton!;


	# Full path is unhelpful in the <title>, trim down to just file name.
	my $fileName = FileNameFromPath($title);
	$fileName = &HTML::Entities::encode($fileName);
	my $displayedTitle = '&#128393' . $fileName; # "lower left pencil"
	$theBody =~ s!_TITLE_!$displayedTitle!;
	# $theBody =~ s!_TITLE_!$fileName!;
	# Flip the slashes for file path in _TITLEHEADER_ at top of the page, for the "traditional" look.
	$title =~ s!/!\\!g;
	$title = &HTML::Entities::encode($title);
	$theBody =~ s!_TITLEHEADER_!$title!;

	my $canHaveTOC = CanHaveTOC($filePath);

	# Watch out for apostrophe in path, it's a killer in the JS above.
	$filePath =~ s!'!\\'!g;

	$theBody =~ s!_PATH_!$ctrlSPath!g;
	$theBody =~ s!_ENCODEDPATH_!$ctrlSPath!g;
	
	my $cmTextHolderName = $canHaveTOC ? 'scrollTextRightOfContents': 'scrollText';
	my $tocHolderName = $canHaveTOC ? 'scrollContentsList': '';
	$theBody =~ s!_CMTEXTHOLDERNAME_!$cmTextHolderName!g;
	$theBody =~ s!_TOCHOLDERNAME_!$tocHolderName!g;
	my $usingCM = 'true';
	$theBody =~ s!_USING_CM_!$usingCM!;

	# Set the selected CodeMirror theme.
	$theBody =~ s!_THEME_!$theme!;

	# Put in the TOC and contents divs.
	my $holderHTML = $canHaveTOC ? "<div id='scrollContentsList'></div><div class='panes-separator' id='panes-separator'></div><div id='scrollTextRightOfContents'></div>": 
		"<div id='scrollText'></div>";
	$theBody =~ s!_TOCANDCONTENTHOLDER_!$holderHTML!g;
	
	my $amRemoteValue = $clientIsRemote ? 'true' : 'false';
	$theBody =~ s!_WEAREREMOTE_!$amRemoteValue!;
	
	my $tfAllowEditing = 'true';
	$theBody =~ s!_ALLOW_EDITING_!$tfAllowEditing!;
	
	my $tfUseAppForEditing = 'false';
	$theBody =~ s!_USE_APP_FOR_EDITING_!$tfUseAppForEditing!;
	
	$theBody =~ s!_CLIENT_IP_ADDRESS_!$peeraddress!;

	$theBody =~ s!_THEPORT_!$port!g;
	$theBody =~ s!_PEERADDRESS_!$peeraddress!g;
	
	my $openerShortName = CVal('OPENERSHORTNAME');
	my $editorShortName = CVal('EDITORSHORTNAME');
	my $linkerShortName = CVal('LINKERSHORTNAME');
	my $filesShortName = CVal('FILESSHORTNAME');
	my $videoShortName = CVal('VIDEOSHORTNAME');
	$theBody =~ s!_VIEWERSHORTNAME_!$viewerShortName!;
	$theBody =~ s!_OPENERSHORTNAME_!$openerShortName!;
	$theBody =~ s!_EDITORSHORTNAME_!$editorShortName!;
	$theBody =~ s!_LINKERSHORTNAME_!$linkerShortName!;
	$theBody =~ s!_FILESSHORTNAME_!$filesShortName!;
	$theBody =~ s!_VIDEOSHORTNAME_!$videoShortName!;

	my $dtime = DoubleClickTime();
	$theBody =~ s!_DOUBLECLICKTIME_!$dtime!;

	# Hilight class for table of contents selected element - see also non_cm_test.css
	# and cm_editor_links.css.
	$theBody =~ s!_SELECTEDTOCID_!tocitup!; 
	
	# Put in main IP, main port, our short name for JavaScript.
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()
	
	return $theBody;	
	}

sub NonCodeMirrorThemeCSS {
	my ($themeName) = @_;
	# If css file doesn't exist, return '';
	# Location is .../IntraMine/css_for_web_server/viewer_themes/$themeName.css
	my $cssPath = BaseDirectory() . 'css_for_web_server/viewer_themes/' . $themeName . '_IM.css';
	if (FileOrDirExistsWide($cssPath) != 1)
		{
		# TEST ONLY
		#print("ERROR could not find |$cssPath|\n");
		return('');
		}

	return("\n" . '<link rel="stylesheet" type="text/css"  href="/viewer_themes/' . $themeName . '_IM.css">' . "\n");
	}

sub PositionToggle {
	my $result = '<input onclick="toggle();" id="togglehits" class="submit-button" type="submit" value="Toggle" />';
	return($result);
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
		$result =  uri_escape_utf8(ReadTextFileDecodedWide($filepath));

		if ($result eq '')
			{
			$result = '___THIS_IS_ACTUALLY_AN_EMPTY_FILE___';
			}
		
		#$result = encode_utf8(ReadTextFileDecodedWide($filepath));
		#####$result = uri_escape_utf8(ReadTextFileWide($filepath));
		}
	
	return($result);		
	}

sub GetTOC {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = '';

	my $filepath = defined($formH->{'file'})? $formH->{'file'}: '';
	if ($filepath ne '')
		{
		GetCMToc($filepath, \$result);
		if ($result ne '')
			{
			$result = uri_escape_utf8($result);
			}
		}
	
	return($result);
	}

# Called by editor.js#saveFile() (via "req=save").
sub Save {
	my ($obj, $formH, $peeraddress) = @_;
	my $status = 'OK';

	ReportActivity($SHORTNAME);
	
	my $filepath = defined($formH->{'file'})? $formH->{'file'}: '';
	if ($filepath ne '')
		{
		$filepath =~ s!\\!/!g;
		Output("Saving |$filepath|\n");
		
		my $contents = $formH->{'contents'};
		# Does not help, in fact it hurts: $contents = encode_utf8($contents);
		$contents = uri_unescape($contents);
		
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

sub ViewButton {
	my ($filePath, $viewerShortName) = @_;
	my $result = <<'FINIS';
<a href='_FILEPATH_' onclick='viewerOpenAnchor(this.href); return false;'><input class="submit-button" type="submit" value="View" /></a>
FINIS
		# TEST ONLY encode_utf8 out
		my $encFilePath = $filePath;
		#my $encFilePath = encode_utf8($filePath);
		$encFilePath =~ s!\\!/!g;
		$encFilePath =~ s!^file\:///!!;
		$encFilePath =~ s!%!%25!g;
		$encFilePath =~ s!\+!\%2B!g;
		# prob not needed $encFilePath = &HTML::Entities::encode($encFilePath);
		$result =~ s!_FILEPATH_!$encFilePath!;

		return($result);
	}
