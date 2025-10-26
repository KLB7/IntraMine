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
$| = 1;

my $PAGENAME    = '';
my $SHORTNAME   = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

my $kLOGMESSAGES     = 0;    # 1 == Log Output() messages
my $kDISPLAYMESSAGES = 0;    # 1 == print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print.
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);
Output("Starting $SHORTNAME on port $port_listen\n\n");

my $LogDir                        = FullDirectoryPath('LogDir');
my $ctags_dir                     = CVal('CTAGS_DIR');
my $HashHeadingRequireBlankBefore = CVal("HASH_HEADING_NEEDS_BLANK_BEFORE");
my $GLOSSARYFILENAME              = lc(CVal('GLOSSARYFILENAME'));
InitTocLocal(
	$LogDir . 'temp/tempctags',
	$port_listen, $LogDir, $ctags_dir, $HashHeadingRequireBlankBefore,
	$GLOSSARYFILENAME
);

# For the file name / datetime / file size span width array @widths.
my $FILENAMEWIDTH = 0;
my $DATETIMEWIDTH = 1;
my $SIZEWIDTH     = 2;

# For file names when doing Save As.
my $GOODNAME    = 1;    # eg file.txt
my $BADNAME     = 2;    # eg COM7
my $BADCHAR     = 3;    # eg file?.txt
my $MISSINGNAME = 4;    # ''


my %RequestAction;
$RequestAction{'href'}            = \&FullFile;           # href=anything, treated as a file path
$RequestAction{'req|loadfile'}    = \&LoadTheFile;        # req=loadfile
$RequestAction{'req|loadTOC'}     = \&GetTOC;             # req=loadTOC
$RequestAction{'req|dateandsize'} = \&GetDateAndSize;     # req=dateandsize
$RequestAction{'req|save'}        = \&Save;               # req=save
$RequestAction{'dir'}             = \&GetDirsAndFiles;    # $formH->{'dir'} is directory path
$RequestAction{'req|oktosaveas'}  = \&OkToSaveAs;         # req=oktosaveas
$RequestAction{'req|saveas'}      = \&SaveAs;             # req=save

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
<link rel="stylesheet" type="text/css" href="hide_contents.css" />

<link rel="stylesheet" type="text/css" href="jqueryFileTree.css" />
<link rel="stylesheet" type="text/css" href="newFileButton.css" />

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
let theFileName = '_FILENAME_';
let theEncodedPath = '_ENCODEDPATH_';
let pathForNotification = '_NOTIFYPATH_';
let usingCM = _USING_CM_;
let cmTextHolderName = '_CMTEXTHOLDERNAME_';
let tocHolderName = '_TOCHOLDERNAME_';
let ourServerPort = '_THEPORT_';
let errorID = "editor_error";
let dateSizeHolderID = 'viewEditDateSize';

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

let chevronWidth = '600px';

let weAreEditing = true; // Don't adjust user selection or do internal links if editing.

//let onMobile = false; // mobile is going away. Too difficult to test.

let arrowHeight = 18;

</script>
</head>
<body>
<!-- added for touch scrolling, an indicator -->
<div id="indicator"></div> <!-- iPad -->
<!-- <div id="indicatorPC"></div> -->
_TOPNAV_
<div id="title-block">
_TITLEHEADER_
</div>
<div id="button-block">
_SAVEACTION_ _REVERT_ _ARROWS_ _UNDOREDO_ _TOGGLEPOSACTION_ _SEARCH_ _CHECKSPELLING_ _VIEWBUTTON__SAVE_AS_ACTION_<span id="editor_error">&nbsp;</span>
</div>
_SAVEASFILEPICKER_
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
<script src="saveAsButton.js"></script>
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
<!-- <script src="indicator.js" ></script> -->

<script src="diff_match_patch_uncompressed.js" ></script>
<script src="restore_edits.js" ></script>
<script src="cmScrollTOC.js" ></script>
<script src="dragTOC.js" ></script>
<script src="go2def.js" ></script>
<script src="cmEditorHandlers.js" ></script>
<script src="editor_auto_refresh.js" ></script>
<script src="jquery-3.4.1.min.js"></script>
<script src="jquery.easing.1.3.min.js"></script>
<script src="jqueryFileTree.js"></script>
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
	my $title        = $filePath . ' NOT RETRIEVED!';

	my $serverAddr     = ServerAddress();
	my $host           = $serverAddr;
	my $port           = $port_listen;
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
	my $nonCmThemeCssFile = NonCodeMirrorThemeCSS($theme);
	$theBody =~ s!_NON_CM_THEME_CSS_!$nonCmThemeCssFile!;

	if (FileOrDirExistsWide($filePath) == 1)
		{
		$title = $filePath;
		}

	# Buttons:
	my $saveButton = SaveButton($filePath);
	$theBody =~ s!_SAVEACTION_!$saveButton!;
	my $saveAsButton = SaveAsButton($filePath);
	$theBody =~ s!_SAVE_AS_ACTION_!$saveAsButton!;

	my $saveAsFilePicker = SaveAsFilePicker();
	$theBody =~ s!_SAVEASFILEPICKER_!$saveAsFilePicker!;

	my $revertButton = RevertButton($filePath);
	$theBody =~ s!_REVERT_!$revertButton!;

	my $arrows =
		  "<img src='left3.png' id='left2' class='img-arrow-left'> "
		. "<img src='up3.png' id='up2' class='img-arrow-up'> "
		. "<img src='down3.png' id='down2' class='img-arrow-down'> "
		. "<img src='right3.png' id='right2' class='img-arrow-right'> ";
	# With CodeMirror, I don't think the on-screen arrow keys or Find will be needed:
	$theBody =~ s!_ARROWS_!!;
	#$theBody =~ s!_ARROWS_!$arrows!;
	my $search =
		"<input id=\"search-button\" class=\"submit-button\" type=\"submit\" value=\"Find\" />";
	$theBody =~ s!_SEARCH_!$search!;
	my $undoRedo =
		  "<input id=\"undo-button\" class=\"submit-button\" type=\"submit\" value=\"Undo\" /> "
		. "<input id=\"redo-button\" class=\"submit-button\" type=\"submit\" value=\"Redo\" />";
	$theBody =~ s!_UNDOREDO_!$undoRedo!;
	# Spell check is only for .txt files in the editor.
	my $checkSpelling = '';
	if ($filePath =~ m!\.txt$!i)
		{
		$checkSpelling =
"<input id=\"spellcheck-button\" class=\"submit-button\" type=\"submit\" value=\"Check\" />";
		}
	$theBody =~ s!_CHECKSPELLING_!$checkSpelling!;

	my $viewerShortName = CVal('VIEWERSHORTNAME');
	my $viewButton      = ViewButton($filePath);
	$theBody =~ s!_VIEWBUTTON_!$viewButton!;

	my $togglePositionButton = '';
	# Mardown Toggle won't work because there are no line numbers.
	if ($filePath !~ m!\.md$!i)
		{
		$togglePositionButton = PositionToggle();
		}
	$theBody =~ s!_TOGGLEPOSACTION_!$togglePositionButton!;


	# Full path is unhelpful in the <title>, trim down to just file name.
	my $fileName          = FileNameFromPath($title);
	my $unencodedFileName = $fileName;
	$fileName = &HTML::Entities::encode($fileName);
	my $displayedTitle = '&#128393' . $fileName;    # "lower left pencil"

	### TEST OUT
	#$theBody =~ s!_TITLE_! !;
	$theBody =~ s!_TITLE_!$displayedTitle!;

	# Flip the slashes for file path in _TITLEHEADER_ at top of the page, for the "standard" look.
	$title =~ s!/!\\\\!g;
	$title = &HTML::Entities::encode($title);

	# Show full path ($title) as expandable/collapsible with links to directories in the path.
	my $expandImg             = "<img src='expand.jpg'>";
	my $chevronControlForPath = ChevronFilePathControl($title, $fileName);
	# For padding, to make the height match the Viewer.
	$chevronControlForPath .= "<br><span id='viewEditDateSize'><span>&nbsp;</span></span>";
	$theBody =~ s!_TITLEHEADER_!$chevronControlForPath!;

	my $canHaveTOC = CanHaveTOC($filePath);

	# Watch out for apostrophe in path, it's a killer in the JS above.
	$filePath =~ s!'!\\'!g;

	my $ctrlSPath = encode_utf8($filePath);
	$ctrlSPath =~ s!%!%25!g;
	$ctrlSPath =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

	$theBody =~ s!_PATH_!$ctrlSPath!g;
	$theBody =~ s!_ENCODEDPATH_!$ctrlSPath!g;
	$theBody =~ s!_NOTIFYPATH_!$ctrlSPath!g;

	my $encFileName = encode_utf8($unencodedFileName);
	$encFileName =~ s!%!%25!g;
	$encFileName =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

	$theBody =~ s!_FILENAME_!$encFileName!g;

	# my $encPath = $filePath;
	# $encPath = &HTML::Entities::encode($encPath);
	# $theBody =~ s!_PATH_!$encPath!g;

	# $theBody =~ s!_ENCODEDPATH_!$encPath!g;
	# $theBody =~ s!_FILENAME_!$fileName!g;


	# $theBody   =~ s!_NOTIFYPATH_!$ctrlSPath!g;

	my $cmTextHolderName = $canHaveTOC ? 'scrollTextRightOfContents' : 'scrollText';
	my $tocHolderName    = $canHaveTOC ? 'scrollContentsList'        : '';
	$theBody =~ s!_CMTEXTHOLDERNAME_!$cmTextHolderName!g;
	$theBody =~ s!_TOCHOLDERNAME_!$tocHolderName!g;
	my $usingCM = 'true';
	$theBody =~ s!_USING_CM_!$usingCM!;

	# Set the selected CodeMirror theme.
	$theBody =~ s!_THEME_!$theme!;

	# Put in the TOC and contents divs.
	my $holderHTML =
		$canHaveTOC
		? "<div id='scrollContentsList'></div><div class='panes-separator' id='panes-separator'></div><div id='scrollTextRightOfContents'></div>"
		: "<div id='scrollText'></div>";
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
	my $filesShortName  = CVal('FILESSHORTNAME');
	my $videoShortName  = CVal('VIDEOSHORTNAME');
	$theBody =~ s!_VIEWERSHORTNAME_!$viewerShortName!;
	$theBody =~ s!_OPENERSHORTNAME_!$openerShortName!;
	$theBody =~ s!_EDITORSHORTNAME_!$editorShortName!;
	$theBody =~ s!_LINKERSHORTNAME_!$linkerShortName!;
	$theBody =~ s!_FILESSHORTNAME_!$filesShortName!;
	$theBody =~ s!_VIDEOSHORTNAME_!$videoShortName!;

	my $dtime = DoubleClickTime();
	$theBody =~ s!_DOUBLECLICKTIME_!$dtime!;

	# The highlight class for table of contents selected element - see also non_cm_test.css
	# and cm_editor_links.css.
	$theBody =~ s!_SELECTEDTOCID_!tocitup!;

	# Put in main IP, main port, our short name for JavaScript.
	PutPortsAndShortnameAtEndOfBody(\$theBody);   # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()

	return $theBody;
}

sub GetDateAndSize {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = ' ';
	if (defined($formH->{'file'}))
		{
		my $filePath = $formH->{'file'};
		my $modDate  = GetFileModTimeWide($filePath);
		my $size     = GetFileSizeWide($filePath);
		$result = DateSizeString($modDate, $size);
		}

	return ($result);
}

# Show a chevron (>>) and file name, attach a showhint() with links to all directories
# in the fullpath for our file. toggleFilePath expands the file name to the full path
# and back again.
sub ChevronFilePathControl {
	my ($filePath, $fileName) = @_;
	$filePath =~ s!\\!/!g;
	$filePath =~ s!//!/!g;
	my $currentPath         = $filePath;
	my $directoryAnchorList = "<em>Click above to expand/contract</em><br><hr>";

	# One could put in an Edit link, but we're in the Editor for the file already.
	# my $fileAnchor = "<a href='$currentPath' onclick='editOpen(this.href); return false;'>$currentPath</a><br>";
	# $directoryAnchorList .= $fileAnchor ;

	# Just a whine, the placement of single and double quotes and
	# also back ticks and &quot; is extremely delicate below.

	my $lastSlashPos = rindex($currentPath, '/');
	while ($lastSlashPos > 0)
		{
		$currentPath = substr($currentPath, 0, $lastSlashPos);
		my $directoryAnchor =
"<a href='' onclick='openDirectory(&quot;$currentPath&quot;); return false;'>$currentPath</a><br>";
		$directoryAnchorList .= $directoryAnchor;
		$lastSlashPos = rindex($currentPath, '/');
		}

	my $result =
"<span id=\"viewEditTitle\" class=\"slightShadow\" onclick=\"toggleFilePath(this, 'expand.jpg', 'contract.jpg'); return(false);\" onmouseover=\"showChevronHint(`$directoryAnchorList`, this, event, false, false);\" ><img src='expand.jpg'>&nbsp;$fileName</span>";

	return ($result);
}

sub NonCodeMirrorThemeCSS {
	my ($themeName) = @_;
	# If css file doesn't exist, return '';
	# Location is .../IntraMine/css_for_web_server/viewer_themes/$themeName.css
	my $cssPath = BaseDirectory() . 'css_for_web_server/viewer_themes/' . $themeName . '_IM.css';
	if (FileOrDirExistsWide($cssPath) != 1)
		{
		return ('');
		}

	return (  "\n"
			. '<link rel="stylesheet" type="text/css"  href="/viewer_themes/'
			. $themeName
			. '_IM.css">'
			. "\n");
}

sub PositionToggle {
	my $result =
'<input onclick="toggle();" id="togglehits" class="submit-button" type="submit" value="Toggle" />';
	return ($result);
}

# See editor.js#loadFileIntoCodeMirror(), which calls back here with "req=loadfile",
# which calls this sub, see %RequestAction above.
# The contents from here are fed into CodeMirror for display.
sub LoadTheFile {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = '';

	my $filepath = defined($formH->{'file'}) ? $formH->{'file'} : '';
	if ($filepath ne '')
		{
		# This decode pairs with the
		# &HTML::Entities::encode()
		# above.
		$filepath = &HTML::Entities::decode($filepath);

		$result = uri_escape_utf8(ReadTextFileDecodedWide($filepath));

		if ($result eq '')
			{
			$result = '___THIS_IS_ACTUALLY_AN_EMPTY_FILE___';
			}
		}

	return ($result);
}

sub GetTOC {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = '';

	my $filepath = defined($formH->{'file'}) ? $formH->{'file'} : '';
	if ($filepath ne '')
		{
		GetCMToc($filepath, \$result);
		if ($filepath !~ m!txt$!i)
			{
			$result = decode_utf8($result);
			}
		}

	return ($result);
}

# Called by editor.js#saveFile() (via "req=save").
sub Save {
	my ($obj, $formH, $peeraddress) = @_;
	my $status = 'OK';

	ReportActivity($SHORTNAME);

	my $filepath = defined($formH->{'file'}) ? $formH->{'file'} : '';
	if ($filepath ne '')
		{
		$filepath = &HTML::Entities::decode($filepath);
		$filepath =~ s!\\!/!g;
		Output("Saving |$filepath|\n");

		my $contents = $formH->{'contents'};
		# Does not help, in fact it hurts: $contents = encode_utf8($contents);
		$contents = uri_unescape($contents);

		if (!WriteBinFileWide($filepath, $contents))    # win_wide_filepaths.pm#WriteBinFileWide()
			{
			$status = "FILE ERROR! Could not save file to |$filepath|.\n";
			sleep(1);
			if (WriteBinFileWide($filepath, $contents))
				{
				$status = 'OK';
				}
			}
		}
	else
		{
		print("ERROR, file_editor received empty file path!\n");
		}

	return ($status);
}

# Return "ok", "exists" etc in preparation for calling SaveAs().
# Called by saveAsButton.js#saveFileAs().
sub OkToSaveAs {
	my ($obj, $formH, $peeraddress) = @_;

	my $path = (defined($formH->{'path'})) ? $formH->{'path'} : '';
	if ($path eq '')
		{
		return ('nopath');
		}
	my $fileName   = FileNameFromPath($path);
	my $nameStatus = IsGoodFileName($fileName);
	if ($nameStatus == $BADNAME)
		{
		return ('badname');
		}
	elsif ($nameStatus == $BADCHAR)
		{
		return ('badchar');
		}
	elsif ($nameStatus == $MISSINGNAME)
		{
		return ('noname');
		}
	if (FileOrDirExistsWide($path) == 1)
		{
		return ('exists');
		}

	# if (!WriteUTF8FileWide($path, ''))
	# 	{
	# 	return('error');
	# 	}

	return ('ok');
}

# Returns
# my $GOODNAME = 1; 	# eg file.txt
# my $BADNAME = 2;		# eg COM7
# my $BADCHAR = 3;		# eg file?.txt
# my $MISSINGNAME = 4; 	# ''
sub IsGoodFileName {
	my ($fileName) = @_;
	my $result = $GOODNAME;
	if ($fileName eq '')
		{
		$result = $MISSINGNAME;
		}
	elsif ($fileName =~
m!^(CON|PRN|AUX|NUL|COM0|COM1|COM2|COM3|COM4|COM5|COM6|COM7|COM8|COM9|LPT0|LPT1|LPT2|LPT3|LPT4|LPT5|LPT6|LPT7|LPT8|LPT9)$!i
		)
		{
		$result = $BADNAME;
		}
	elsif ($fileName =~ m!["*:<>?/\\|]!)
		{
		$result = $BADCHAR;
		}

	return ($result);
}

sub SaveAs {
	my ($obj, $formH, $peeraddress) = @_;
	my $status = 'OK';

	ReportActivity($SHORTNAME);

	my $filepath = defined($formH->{'file'}) ? $formH->{'file'} : '';
	if ($filepath ne '')
		{
		$filepath = &HTML::Entities::decode($filepath);
		$filepath =~ s!\\!/!g;
		Output("Save As for |$filepath|\n");

		# TEST ONLY
		#Monitor("Save As path: |$filepath|\n");

		my $contents = $formH->{'contents'};
		$contents = uri_unescape($contents);
		if (!WriteBinFileWide($filepath, $contents))    # win_wide_filepaths.pm#WriteBinFileWide()
			{
			$status = "FILE ERROR! Could not do Save As for |$filepath|.\n";
			sleep(1);
			if (WriteBinFileWide($filepath, $contents))
				{
				$status = 'OK';
				}
			}

		}
	else
		{
		print("ERROR, file_editor received empty file path!\n");
		}

	return ($status);
}

sub ViewButton {
	my ($filePath) = @_;

	my $result = <<'FINIS';
<a href='_FILEPATH_' onclick='viewerOpenAnchor(this.href); return false;'><input class="submit-button" type="submit" value="View" /></a>
FINIS

	my $encFilePath = &HTML::Entities::encode($filePath);
	$result =~ s!_FILEPATH_!$encFilePath!;

	return ($result);
}

sub SaveButton {
	my ($filePath) = @_;

	my $result = <<'FINIS';
<input onclick="saveFile('_FILEPATH_');" id="save-button" class="submit-button" type="submit" value="Save" />
FINIS

	my $encFilePath = &HTML::Entities::encode($filePath);
	$result =~ s!_FILEPATH_!$encFilePath!;

	return ($result);
}

sub SaveAsButton {
	my ($filePath) = @_;

	my $result = <<'FINIS';
<input onclick="saveFileAsWithPicker();" id="save-as-button" class="submit-button" type="submit" value="Save As..." />
FINIS

	my $encFilePath = &HTML::Entities::encode($filePath);
	$result =~ s!_FILEPATH_!$encFilePath!;

	return ($result);

}

sub RevertButton {
	my ($filePath) = @_;

	my $result = <<'FINIS';
<input onclick="revertFile('_FILEPATH_');" id="revert-button" class="submit-button" type="submit" value="Revert" title="Revert to last saved version" />
FINIS

	my $encFilePath = &HTML::Entities::encode($filePath);
	$result =~ s!_FILEPATH_!$encFilePath!;

	return ($result);
}

# This is a simplified version of the file picker, file links are omitted here
# and there is a text field for entering the name of the new file.
sub SaveAsFilePicker {
	my $theSource = <<'FINIS';
<!--<form id="dirform">-->
<div id='dirpickerMainContainer'>
	<p id="directoryPickerTitle">Save As</p>
	<div id='dirpicker'>
		<div id="scrollAdjustedHeightDirPicker">
			<div id="fileTreeNew">
				<select id="driveselector_3" name="drive selector" onchange="driveChangedNew('scrollDriveListNew', this.value);">
				  _DRIVESELECTOROPTIONS_
				</select>
				<div id='scrollDriveListNew'>placeholder for drive list
				</div>
			</div>
		</div>
		<div id="pickerDisplayDiv">Selected directory:&nbsp;<span id="pickerDisplayedDirectory"></span></div>
		<div id="newFileDiv">File name: <input type="text" id="newFileName" name="newFileName" required minlength="3"></div>
	</div>
	<div id="okCancelHolder">
		<input type="button" id="dirOkButton" value="OK" onclick="setFullPathFromPicker(); return false;" />
		<input type="button" id="dirCancelButton" value="Cancel" onclick="hideNewFilePicker(); return false;" />
	</div>
	<input type="hidden" id="newFullPathField" name="newFullPathField" />
</div>

<!--</form>-->
FINIS

	# Put a list of drives in the drive selector.
	my $driveSelectorOptions = DriveSelectorOptions();
	$theSource =~ s!_DRIVESELECTOROPTIONS_!$driveSelectorOptions!g;
	return $theSource;
}

# Support subs for the Save As file picker

# Return a list of directories and files for the current drive or directory.
# Called by jqueryFileTree.js on line 69: "$.post(o.script, { dir: t, rmt: o.remote,..."
# which sends a "dir" request to the program (see %RequestAction above).
sub GetDirsAndFiles {
	my ($obj, $formH, $peeraddress) = @_;
	my $dir    = $formH->{'dir'};
	my $result = '';

	Output("GetDirsAndFiles request for dir: |$dir|\n");
	if (FileOrDirExistsWide($dir) != 2)
		{
		return (' ');    # return something (but not too much), to avoid 404
		}

	my @folders;
	my @files;
	my @modDates;
	my @fileSizes;

	GetFoldersFilesDatesAndSizes($dir, \@folders, \@files, \@modDates, \@fileSizes);

	my $numFolders = @folders;
	my $numFiles   = @files;
	my $total      = $numFolders + $numFiles;

	if ($total)
		{
		$result = "<ul class=\"jqueryFileTree\" style=\"display: none;\">";
		}

	if ($numFolders)
		{
		PutFolders($dir, \@folders, \$result);
		}

	if ($numFiles)
		{
		my $sortOrder = (defined($formH->{'sort'})) ? $formH->{'sort'} : '';
		SortFilesDatesAndSizes($sortOrder, \@files, \@modDates, \@fileSizes);

		my $rmt = defined($formH->{'rmt'}) ? $formH->{'rmt'} : 'undef';
		if ($rmt eq 'false')
			{
			$rmt = 0;
			}
		else
			{
			$rmt = 1;
			}
		# TEST ONLY
		#print("\$rmt: |$rmt|\n");

		my @modDatesStrings;
		my @fileSizesStrings;
		my @widths;
		GetDateSizeStringsAndColumnWidths(\@files, \@modDates, \@fileSizes, \@modDatesStrings,
			\@fileSizesStrings, \@widths);

		PutFiles($dir, $formH, $rmt, \@files, \@modDatesStrings, \@fileSizesStrings, \@widths,
			\$result);
		}

	if ($total)
		{
		$result .= "</ul>\n";
		}

	if ($result eq '')
		{
		$result = ' ';    # return something (but not too much), to avoid 404
		}

	return ($result);
}

sub GetFoldersFilesDatesAndSizes {
	my ($dir, $foldersA, $filesA, $modDatesA, $fileSizesA) = @_;
	my $fullDir = $dir . '*';

	# win_wide_filepaths.pm#FindFileWide().
	my @allEntries = FindFileWide($fullDir);
	my $numEntries = @allEntries;
	if (!$numEntries)
		{
		return;
		}

	# Break entries into folders and files.
	for (my $i = 0 ; $i < @allEntries ; ++$i)
		{
		my $theName = $allEntries[$i];
		# Not needed: $fileName = decode("utf8", $fileName);
		my $fullPath = "$dir$theName";
		if (FileOrDirExistsWide($fullPath) == 2)
			{
			if ($theName !~ m!^\.\.?$! && substr($theName, 0, 1) ne '$')
				{
				push @$foldersA, $theName;
				}
			}
		else
			{
			if ($theName =~ m!\.\w+$! && $theName !~ m!\.sys$! && substr($theName, 0, 1) ne '$')
				{
				push @$filesA, $theName;
				}
			}
		}

	my $numFiles = @$filesA;
	if ($numFiles)
		{
		FileDatesAndSizes($dir, $filesA, $modDatesA, $fileSizesA);
		}
}

sub PutFolders {
	my ($dir, $foldersA, $resultR) = @_;

	foreach my $folderName (sort {lc $a cmp lc $b} @$foldersA)
		{
		next if (FileOrDirExistsWide($dir . $folderName) == 0);
		$$resultR .=
			  '<li class="directory collapsed"><a href="#" rel="'
			. &HTML::Entities::encode($dir . $folderName) . '/">'
			. &HTML::Entities::encode($folderName)
			. '</a></li>';
		}
}

sub SortFilesDatesAndSizes {
	my ($sortOrder, $filesA, $modDatesA, $fileSizesA) = @_;
	my @idx;

	if ($sortOrder eq 'size_smallest')
		{
		@idx = sort {$fileSizesA->[$a] <=> $fileSizesA->[$b]} 0 .. $#$fileSizesA;
		}
	elsif ($sortOrder eq 'size_largest')
		{
		@idx = sort {$fileSizesA->[$b] <=> $fileSizesA->[$a]} 0 .. $#$fileSizesA;
		}
	elsif ($sortOrder eq 'date_newest')
		{
		# Newest first, so [$b] <=> [$a].
		@idx = sort {$modDatesA->[$b] <=> $modDatesA->[$a]} 0 .. $#$modDatesA;
		}
	elsif ($sortOrder eq 'date_oldest')
		{
		# Newest first, so [$b] <=> [$a].
		@idx = sort {$modDatesA->[$a] <=> $modDatesA->[$b]} 0 .. $#$modDatesA;
		}
	elsif ($sortOrder eq 'name_descending')
		{
		@idx = sort {lc $filesA->[$b] cmp lc $filesA->[$a]} 0 .. $#$filesA;
		}
	elsif ($sortOrder eq 'extension')
		{
		my @extensions;
		Extensions($filesA, \@extensions);
		@idx = sort {$extensions[$a] cmp $extensions[$b]} 0 .. $#extensions;
		}
	else    # 'name_ascending', the default
		{
		@idx = sort {lc $filesA->[$a] cmp lc $filesA->[$b]} 0 .. $#$filesA;
		}

	@$filesA     = @$filesA[@idx];
	@$modDatesA  = @$modDatesA[@idx];
	@$fileSizesA = @$fileSizesA[@idx];
}

sub GetDateSizeStringsAndColumnWidths {
	my ($filesA, $modDatesA, $fileSizesA, $modDatesStringsA, $fileSizesStringsA, $widthsA) = @_;
	my $numFiles       = @$filesA;
	my $filesWidth     = 0;
	my $modDatesWidth  = 0;
	my $fileSizesWidth = 0;
	for (my $i = 0 ; $i < $numFiles ; ++$i)
		{
		my $widthFiles = length($filesA->[$i]);
		if ($filesWidth < $widthFiles)
			{
			$filesWidth = $widthFiles;
			}

		my $dateTimeString = DateTimeString($modDatesA->[$i]);
		push @$modDatesStringsA, $dateTimeString;
		my $widthMDate = length($dateTimeString);
		if ($modDatesWidth < $widthMDate)
			{
			$modDatesWidth = $widthMDate;
			}

		my $sizeString = SizeInBytesString($fileSizesA->[$i]);
		push @$fileSizesStringsA, $sizeString;
		my $widthSize = length($sizeString);
		if ($fileSizesWidth < $widthSize)
			{
			$fileSizesWidth = $widthSize;
			}
		}

	# Put file name, date, size in separate spans with fixed width in characters ('ch').
	# Add 2 to $filesWidth for hover icons or edit pencil.
	$filesWidth += 2;
	my $wF = $filesWidth . 'ch';
	my $wD = $modDatesWidth . 'ch';
	my $wS = $fileSizesWidth . 'ch';

	$widthsA->[$FILENAMEWIDTH] = $wF;
	$widthsA->[$DATETIMEWIDTH] = $wD;
	$widthsA->[$SIZEWIDTH]     = $wS;
}

# For each file: file icon based on extension, file name, datetime, size in bytes.
# Fixed-width inline-block <span>s are used to align entries.
sub PutFiles {
	my ($dir, $formH, $rmt, $filesA, $modDatesStringsA, $fileSizesStringsA, $widthsA, $resultR) =
		@_;
	my $numFiles         = @$filesA;
	my $clientIsRemote   = ($formH->{'rmt'} eq 'false') ? 0 : 1;
	my $allowEditing     = ($formH->{'edt'} eq 'false') ? 0 : 1;
	my $useAppForEditing = ($formH->{'app'} eq 'false') ? 0 : 1;
	my $serverAddr       = ServerAddress();

	for (my $i = 0 ; $i < $numFiles ; ++$i)
		{
		my $file = $filesA->[$i];
		next if (FileOrDirExistsWide($dir . $file) == 0);
		my $modDate = $modDatesStringsA->[$i];
		my $size    = $fileSizesStringsA->[$i];

		$file =~ /\.([^.]+)$/;
		my $ext = $1;

		# Gray out unsuported file types. Show thumbnail on hover for images.
		# Note videos cannot be viewed remotely (at least for now).
		if (   defined($ext)
			&& IsTextDocxPdfOrImageOrVideoExtensionNoPeriod($ext)
			&& !(IsVideoExtensionNoPeriod($ext) && $rmt))
			{
			if (IsImageExtensionNoPeriod($ext))
				{
				$$resultR .= ImageLine($serverAddr, $dir, $file, $ext, $modDate, $size, $widthsA);
				}
			elsif (IsVideoExtensionNoPeriod($ext))
				{
				$$resultR .= VideoLine($serverAddr, $dir, $file, $ext, $modDate, $size, $widthsA);
				}
			else    # Text, for the most part - could also be pdf or docx
				{
				$$resultR .= TextDocxPdfLine($dir, $file, $ext, $modDate, $size,
					$allowEditing, $clientIsRemote, $widthsA);
				}
			}
		else # Unsupported type (and remote videos), can't produce a read-only HTML view. So no link.
			{
			my $dateSpanStart =
				"<span style='display: inline-block; width: $widthsA->[$DATETIMEWIDTH];'>";
			my $sizesSpanStart =
				"<span style='display: inline-block; width: $widthsA->[$SIZEWIDTH];'>";
			my $endSpan = '</span>';

			my $fileName = &HTML::Entities::encode($file);
			$$resultR .=
				  '<li class="file ext_'
				. $ext . '">'
				. "<span class='unsupported' style='display: inline-block; width: $widthsA->[$FILENAMEWIDTH];'>"
				. $fileName
				. '</span>'
				. $dateSpanStart
				. $modDate
				. $endSpan
				. $sizesSpanStart
				. $size
				. $endSpan . '</li>';
			}
		}
}

sub FileDatesAndSizes {
	my ($dir, $filesA, $modDatesA, $sizesA) = @_;
	my $numFiles = @$filesA;

	for (my $i = 0 ; $i < $numFiles ; ++$i)
		{
		my $file = $filesA->[$i];
		my @a;
		GetFileModTimeAndSizeWide($dir . $file, \@a);
		if (!defined($a[0]))
			{
			$a[0] = '0';
			}
		if (!defined($a[1]))
			{
			$a[1] = '';
			}
		push @$modDatesA, $a[0];
		push @$sizesA,    $a[1];
		}
}

sub Extensions {
	my ($filesA, $extA) = @_;
	my $numFiles = @$filesA;

	for (my $i = 0 ; $i < $numFiles ; ++$i)
		{
		my $file = $filesA->[$i];
		my $ext;
		if ($file =~ m!\.(\w+)$!)
			{
			$ext = lc $1;
			}
		else
			{
			$ext = '_NONE';
			}
		push @$extA, $ext;
		}
}

# Images get showhint() "hover" event listeners, as well as a link to open in a new tab.
# Put file name, mod date, and size in separate fixed-width spans for alignment.
sub ImageLine {
	my ($serverAddr, $dir, $file, $ext, $modDate, $size, $widthsA) = @_;
	my $imagePath      = $dir . $file;
	my $imageHoverPath = $imagePath;
	$imageHoverPath =~ s!%!%25!g;
	my $imageName = $file;
	$imageName      = &HTML::Entities::encode($imageName);        # YES this works fine.
	$imagePath      = &HTML::Entities::encode($imagePath);
	$imageHoverPath = &HTML::Entities::encode($imageHoverPath);

	my $serverImageHoverPath = "http://$serverAddr:$port_listen/$imageHoverPath";
	my $leftHoverImg =
		"<img src='http://$serverAddr:$port_listen/hoverleft.png' width='17' height='12'>";
	my $rightHoverImg =
		"<img src='http://$serverAddr:$port_listen/hoverright.png' width='17' height='12'>";

	my $result =
		  '<li class="file ext_'
		. $ext . '">'
		. "<span style='display: inline-block; width: $widthsA->[$FILENAMEWIDTH];'>"
		. '<a href="#" rel="'
		. $imagePath . '"'
		. "onmouseOver=\"showhint('<img src=&quot;$serverImageHoverPath&quot;>', this, event, '250px', true);\""
		. '>'
		. "$leftHoverImg$imageName$rightHoverImg"
		. '</a></span>'
		. "<span style='display: inline-block; width: $widthsA->[$DATETIMEWIDTH];'>"
		. $modDate
		. '</span>'
		. "<span style='display: inline-block; width: $widthsA->[$SIZEWIDTH];'>"
		. $size
		. '</span></li>';

	return ($result);
}

sub VideoLine {
	my ($serverAddr, $dir, $file, $ext, $modDate, $size, $widthsA) = @_;
	my $imagePath = $dir . $file . 'VIDEO';
	my $imageName = $file;
	$imageName = &HTML::Entities::encode($imageName);    # YES this works fine.
	$imagePath = &HTML::Entities::encode($imagePath);

	my $result =
		  '<li class="file ext_'
		. $ext . '">'
		. "<span style='display: inline-block; width: $widthsA->[$FILENAMEWIDTH];'>"
		. '<a href="#" rel="'
		. $imagePath . '"' . '>'
		. "$imageName"
		. '</a></span>'
		. "<span style='display: inline-block; width: $widthsA->[$DATETIMEWIDTH];'>"
		. $modDate
		. '</span>'
		. "<span style='display: inline-block; width: $widthsA->[$SIZEWIDTH];'>"
		. $size
		. '</span></li>';

	return ($result);
}

# Put link on file name, with optional edit pencil link.
# PDF and docx can't be edited on a remote PC, hence a bit of special handling.
# Put file name, mod date, and size in separate fixed-width spans for alignment.
sub TextDocxPdfLine {
	my ($dir, $file, $ext, $modDate, $size, $allowEditing, $clientIsRemote, $widthsA) = @_;
	my $filePath = &HTML::Entities::encode($dir . $file);
	my $fileName = &HTML::Entities::encode($file);

	my $result = '';
	# No editing if config says no, or it's pdf or docx on a remote PC.
	if (!$allowEditing || ($clientIsRemote && $ext =~ m!^(docx|pdf)!i))
		{
		$result .=
			  '<li class="file ext_'
			. $ext . '">'
			. "<span style='display: inline-block; width: $widthsA->[$FILENAMEWIDTH];'>"
			. '<a href="#" rel="'
			. $filePath . '">'
			. $fileName . '</a>'
			. '</span>'
			. "<span style='display: inline-block; width: $widthsA->[$DATETIMEWIDTH];'>"
			. $modDate
			. '</span>'
			. "<span style='display: inline-block; width: $widthsA->[$SIZEWIDTH];'>"
			. $size
			. '</span></li>';
		}
	else    # editing allowed
		{
		$result .=
			  '<li class="file ext_'
			. $ext . '">'
			. "<span style='display: inline-block; width: $widthsA->[$FILENAMEWIDTH];'>"
			. '<a href="#" rel="'
			. $filePath . '">'
			. $fileName . '</a>'
			. '<a href="#"><img src="edit1.png" width="17" height="12" rel="'
			. $filePath . '" />' . '</a>'
			. '</span>'
			. "<span style='display: inline-block; width: $widthsA->[$DATETIMEWIDTH];'>"
			. $modDate
			. '</span>'
			. "<span style='display: inline-block; width: $widthsA->[$SIZEWIDTH];'>"
			. $size
			. '</span></li>';
		}

	return ($result);
}
