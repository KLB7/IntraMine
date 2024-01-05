# intramine_viewer.pl: use CodeMirror to display most code files,
# with custom display (code below) for txt, Perl, and pod.
# Pdf and docx also have basic viewers.
# All code and text files have autolinks, and image hovers.
# Text files (.txt) are given the full Gloss (like Markdown) treatment with
# headings, lists, tables, autolinks, image hovers, special characters,
# horizontal rules and a table of contents on the left.
# Files with tables of contents: txt, pl, pm, pod, C(++), js, css, go,
# and many others supported by ctags such as PHP, Ruby - see GetCTagSupportedTypes() below.
# This is not a "top" server, meaning it doesn't have an entry in IntraMine's top navigation bar.
# Typically it's called by click on a link in Search page results, the Files page lists,
# or a link in a view provided by this Viewer or the Editor service.

# perl C:\perlprogs\mine\intramine_viewer.pl

use strict;
use warnings;
use utf8;
use FileHandle;
use Encode;
use Encode::Guess;
use HTML::Entities;
use URI::Escape;
use Text::Tabs;
$tabstop = 4;
use Syntax::Highlight::Perl::Improved ':BASIC';  # ':BASIC' or ':FULL' - FULL doesn't seem to do much
use Time::HiRes qw ( time );
use Win32::Process; # for calling Exuberant ctags.exe
use JSON::MaybeXS qw(encode_json);
use Text::MultiMarkdown; # for .md files
use Path::Tiny qw(path);
use Pod::Simple::HTML;
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;
use win_wide_filepaths;
use win_user32_local;
use docx2txt;
use ext; # for ext.pm#IsTextExtensionNoPeriod() etc.
use html2gloss;
use cobol_keywords;

Encode::Guess->add_suspects(qw/iso-8859-1/);

$|  = 1;

# Some ASCII values, used in AddInternalLinksToPerlLine().
my $ORD_a = ord('a');
my $ORD_z = ord('z');
my $ORD_A = ord('A');
my $ORD_Z = ord('Z');
my $ORD_0 = ord('0');
my $ORD_9 = ord('9');

# Circled letters, used in tables of contents.
my $C_icon = '<span class="circle_green">C</span>'; 	# Class
my $S_icon = '<span class="circle_green">S</span>';		# Struct
my $M_icon = '<span class="circle_green">M</span>';		# Module
my $T_icon = '<span class="circle_blue">T</span>';		# Type
my $D_icon = '<span class="circle_blue">D</span>';		# Data
my $m_icon = '<span class="circle_red">m</span>';		# method
my $f_icon = '<span class="circle_red">f</span>';		# function
my $s_icon = '<span class="circle_red">s</span>';		# subroutine

LoadCobolKeywords();

my $PAGENAME = '';
my $SHORTNAME = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

my $IMAGES_DIR = FullDirectoryPath('IMAGES_DIR');
#my $COMMON_IMAGES_DIR = CVal('COMMON_IMAGES_DIR');
my $UseAppForLocalEditing = CVal('USE_APP_FOR_EDITING');
my $UseAppForRemoteEditing = CVal('USE_APP_FOR_REMOTE_EDITING');
my $AllowLocalEditing = CVal('ALLOW_LOCAL_EDITING');
my $AllowRemoteEditing = CVal('ALLOW_REMOTE_EDITING');

# Just a whimsy - for contents.txt files that start with CONTENTS, try to make it look
# like an old-fashioned "special" table of contents. Initialized here.
InitSpecialIndexFileHandling();

my $kLOGMESSAGES = 0;			# 1 == Log Output() messages
my $kDISPLAYMESSAGES = 0;		# 1 == print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print.
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);

my $GLOSSARYFILENAME = lc(CVal('GLOSSARYFILENAME'));

InitPerlSyntaxHighlighter();
my $LogDir = FullDirectoryPath('LogDir');
InitCtags($LogDir . 'temp/tempctags');

Output("Starting $SHORTNAME on port $port_listen\n\n");

# This service has no default action. For file display either 'href=path'
# or the more RESTful '.../file/path' can be used. See eg intramine_search.js#viewerOpenAnchor()
# (a call to that is inserted by elasticsearcher.pm#FormatHitResults() among others).
my %RequestAction;
$RequestAction{'href'} = \&FullFile; 					# Open file, href = anything
$RequestAction{'/file/'} = \&FullFile; 					# RESTful alternative, /file/is followed by file path in $obj
$RequestAction{'req|loadfile'} = \&LoadTheFile; 		# req=loadfile
$RequestAction{'req|openDirectory'} = \&OpenDirectory; 		# req=openDirectory
# The following two callbacks are needed if any css/js files
# are passed to GetStandardPageLoader() in the first argument. Not needed here.
$RequestAction{'req|css'} = \&GetRequestedFile; 		# req=css  see swarmserver.pm#GetRequestedFile()
$RequestAction{'req|js'} = \&GetRequestedFile; 			# req=js
# Testing
$RequestAction{'/test/'} = \&SelfTest;					# Ask this server to test itself.
# Not needed, done in swarmserver: $RequestAction{'req|id'} = \&Identify; # req=id

MainLoop(\%RequestAction);

################### subs

# A browser view of a file. Text, source (226 extensions currently), PDF, HTML, Word.
# Most views are created using CodeMirror.
# pl, pm, pod, txt, log, bat, cgi, and t extensions have "custom" views generated below, rather
# than using CodeMirror.
# A serious attempt has been made to give CodeMirror and custom views the same capabilities,
# even though the two approaches differ greatly. The difference is due mainly to the use by
# CodeMirror of "overlays" for anything custom - so for example, a link or highlight in a
# CodeMirror view needs an overlay marker to put the link or highlight "on top" of the text.
# See eg https://codemirror.net/doc/manual.html#markText.
# In the custom views, the link is inserted directly into the displayed HTML.
# Because creating overlay markers for all links in a large file is moderately expensive,
# the markers are created on demand, when new lines are scrolled into view.
# The real work is done by GetContentBasedOnExtension() below.
# 2020-02-28 15_55_57-reverse_filepaths.pm.png
sub FullFile {
	my ($obj, $formH, $peeraddress) = @_;
	my $theBody = FullFileTemplate();
	my $t1 = time;
	my $fileServerPort = $port_listen;
	my $usingRESTfulApproach = 0;
	
	$formH->{'FULLPATH'} = '';
	# Accept argument based 'href=filepath' in $formH or more RESTful /file/path in $obj.
	if (!defined($formH->{'href'}))
		{
		$usingRESTfulApproach = 1;
		if ($obj =~ m!$SHORTNAME/file/([^\?]+)!)
			{
			my $path = $1;
			$path =~ s!/$!!;
			$formH->{'FULLPATH'} = $path;
			}
		}
	
	if (defined($formH->{'href'}))
		{
		$formH->{'FULLPATH'} = $formH->{'href'};
		}
		
	my $filePath = $formH->{'FULLPATH'};
	
	# Revision (temporarily at least), return '' if file does not exist. This leads to an ugly
	# 404 generated by the browser, but it's all I've got at the moment. The problem is with
	# JS-generated paths such as
	# C:/perlprogs/mine/test/mode/clike/clike.js
	# which is a blend of eg C:\perlprogs\mine\test\googlesuggest.cpp (the main file)
	# and mode/clike/clike.js (a CodeMirror subfolder). Since the JS-generated path looks like
	# and could in fact be a real path, we have to reject it if the file is not found.
	# The rub there is that if C:/perlprogs/mine/test/mode/clike/clike.js does in fact
	# exist then the load is toast, the wrong clike.js will be loaded. This problem happens
	# only for RESTful URLs, arg-based is fine.
	if ($usingRESTfulApproach && FileOrDirExistsWide($filePath) != 1)
		{
		# TEST ONLY codathon
		print("FullFile REJECTED |$filePath|\n");
		return('');
		}
		
	# Early return if file does not exist and it's not a bogus request from the browser.
#	if (FileOrDirExistsWide($filePath) != 1)
#		{
#		# For RESTful (eg /file/path/goodfile.txt) requests, browser often asks for css and js using path
#		# /file/path/goodfile.txt/this/that/afile.css. In this case, we should immediately return '', signalling
#		# to the caller (typically swarmserver.pm#HandleRequestAction()) that it was a bad request
#		# and caller should  keep trying (eg call swarmserver.pm#GetCssResult()).
#		# Otherwise, if "$preFileName" does not exist on disk, we assume the $filePath really is bad
#		# and return a nice result page with nav bar etc saying NOT RETRIEVED.
#		print("Considering \$filePath |$filePath|\n");
#		
#		# Sometimes we need to strip off more than one part of the path to reveal the original
#		# path, eg .../test/googlesuggest.cpp/addon/dialog/dialog.css
#		my $filePathCopy = $filePath;
#		my $fnPosition = rindex($filePathCopy, '/');
#		
#		while ($fnPosition > 3)
#			{
#			$filePathCopy = substr($filePathCopy, 0, $fnPosition);
#			if ($filePathCopy =~ m!\.\w+$!)
#				{
#				if (FileOrDirExistsWide($filePathCopy) == 1)
#					{
#					print("BOGUS CALL, returning ''.\n");
#					return('');
#					}
#				else
#					{
#					last; # Check once only if an extension is seen.
#					}
#				}
#			$fnPosition = rindex($filePathCopy, '/');
#			}
#		}
	
	my $title = $filePath . ' NOT RETRIEVED!';
	my $serverAddr = ServerAddress();

	my $clientIsRemote = 0;
	# If client is on the server then peeraddress can be either 127.0.0.1 or $serverAddr:
	# if client is NOT on the server then peeraddress is not 127.0.0.1 and differs from $serverAddr.
	if ($peeraddress ne '127.0.0.1' && $peeraddress ne $serverAddr)	#if ($peeraddress ne $serverAddr)
	#if ($peeraddress ne '127.0.0.1')
		{
		$clientIsRemote = 1;
		}
	
	my $allowEditing = (($clientIsRemote && $AllowRemoteEditing) || (!$clientIsRemote && $AllowLocalEditing));
	my $useAppForEditing = 0;
	if ($allowEditing)
		{
		$useAppForEditing = (($clientIsRemote && $UseAppForRemoteEditing) || (!$clientIsRemote && $UseAppForLocalEditing));
		}

	# Editing can be done with IntraMine's Editor, or with your preferred text editor.
	# See intramine_config.txt "ALLOW_LOCAL_EDITING" et seq for some notes on setting up
	# local editing (on the IntraMine box) and remote editing. You can use IntraMine or your
	# preferred app locally or remotely, or disable editing for either.
	my $amRemoteValue = $clientIsRemote ? 'true' : 'false';
	my $tfAllowEditing = ($allowEditing) ? 'true' : 'false';
	my $tfUseAppForEditing = ($useAppForEditing) ? 'true' : 'false';
	my $host = $serverAddr;
	my $port = $port_listen;
	my $fileContents = '<p>Read error!</p>';
	my $meta = "";
	my $customCSS = '';
	my $textTableCSS = '';
	# For cmTextHolderName = '_CMTEXTHOLDERNAME_'; -- can also  be 'scrollTextRightOfContents'
	my $textHolderName = 'scrollText';
	my $usingCM = 'true'; # for _USING_CM_ etc (using CodeMirror)

	my $ctrlSPath = $filePath;
	
	my $topNav = TopNav($PAGENAME);
	$theBody =~ s!_TOPNAV_!$topNav!;
	
	
	my $exists = FileOrDirExistsWide($filePath);
	
	if ($exists == 1)
		{
		$title = $filePath;
		
		$ctrlSPath = encode_utf8($ctrlSPath);
		$ctrlSPath =~ s!%!%25!g;
		$ctrlSPath =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
		
		# Categories: see GetContentBasedOnExtension() below. Here we handle HTML.
		# 1.1
		# If a local HTML file has been requested, skip the TopNav() etc and just return the page as-is.
		# DEFAULTDIR is needed for serving up css and js files associated with the page, when url for
		# the resource starts with "./".
		# This is the "view" for HTML: "edit" shows the raw HTML as text.
		if ($filePath =~ m!\.html?$!i)
			{
			GetHTML($formH, $peeraddress, \$fileContents);
			# $meta  not needed.
			my $dir = lc(DirectoryFromPathTS($filePath));
			$formH->{'DEFAULTDIR'} = $dir;
			return($fileContents);
			
			}
		else # all other categories of extension
			{
			GetContentBasedOnExtension($formH, $peeraddress, $filePath, 
			$clientIsRemote, $allowEditing, \$fileContents,
			\$usingCM, \$meta, \$textTableCSS, \$customCSS,
			\$textHolderName);
			}
		}
	else
		{
		# Fail, use text JS and CSS for the 404 display.
		$usingCM = 'false';
		$customCSS = '<link rel="stylesheet" type="text/css" href="non_cm_text.css" />';
		}
		
	# Remove scrollAdjustedHeight if it's an image.
	# And take out the toggle button.
	if ($filePath =~ m!\.(png|gif|jpe?g|ico|webp)$!i)
		{
		$theBody =~ s! id='scrollAdjustedHeight'!!;
		$theBody =~ s!_TOGGLEPOSACTION_!!;
		}

	# Insert the HTML to load various JavaScript and CSS files as needed. Plus the "meta" line.
	$theBody =~ s!_META_CHARSET_!$meta!;
	$theBody =~ s!_CSS_!$customCSS!;
	$theBody =~ s!_TEXTTABLECSS_!$textTableCSS!;	
	my $customJS = ($usingCM eq 'true') ? CodeMirrorJS() : NonCodeMirrorJS();
	# Add lolight JS for .txt files only.
	if ($filePath =~ m!\.txt$!)
		{
		$customJS .= "\n" . '<script src="lolight-1.4.0.min.js"></script>';
		}
	$theBody =~ s!_JAVASCRIPT_!$customJS!;
	
	# Full path is unhelpful in the <title>, trim down to just file name.
	my $fileName = FileNameFromPath($title);
	$fileName = &HTML::Entities::encode($fileName);
	$theBody =~ s!_TITLE_!$fileName!;
	
	# Make a copy of title, just for console display.
	my $consoleDisplayedTitle = $title;
	
	# Flip the slashes for file path in _TITLEHEADER_ at top of the page, for easier
	# copy/paste into notepad++ etc.
	$title =~ s!/!\\!g;
	$title = &HTML::Entities::encode($title);
	
	# Grab mod date and file size.
	my $modDate = GetFileModTimeWide($filePath);
	my $size = GetFileSizeWide($filePath);
	my $sizeDateStr =  DateSizeString($modDate, $size);
	
	# Fill in the placeholders in the HTML template for title etc. And give values to
	# JS variables. See FullFileTemplate() just below.
	$theBody =~ s!_TITLEHEADER_!$title!;
	
	$theBody =~ s!_DATEANDSIZE_!$sizeDateStr!;

	# Use $ctrlSPath for $filePath beyond this point.
	# Why? It works. Otherwise Unicode is messed up.
	$filePath = $ctrlSPath;


	
	$theBody =~ s!_PATH_!$filePath!g;
	$theBody =~ s!_ENCODEDPATH_!$ctrlSPath!g;
	
	$theBody =~ s!_USING_CM_!$usingCM!;
	$theBody =~ s!_CMTEXTHOLDERNAME_!$textHolderName!g;
	my $findTip = "(Unshift for lower case)";
	$theBody =~ s!_MESSAGE__!$findTip!;
	
	#####$theBody =~ s!_THEHOST_!$host!g;
	$theBody =~ s!_THEPORT_!$port!g;
	$theBody =~ s!_PEERADDRESS_!$peeraddress!g;
	#####$theBody =~ s!_THEMAINPORT_!$server_port!;
	$theBody =~ s!_CLIENT_IP_ADDRESS_!$peeraddress!;
	#####$theBody =~ s!_SHORTSERVERNAME_!$SHORTNAME!;
	my $viewerShortName = CVal('VIEWERSHORTNAME');
	my $openerShortName = CVal('OPENERSHORTNAME');
	my $editorShortName = CVal('EDITORSHORTNAME');
	my $linkerShortName = CVal('LINKERSHORTNAME');
	my $filesShortName = CVal('FILESSHORTNAME');
	$theBody =~ s!_VIEWERSHORTNAME_!$viewerShortName!;
	$theBody =~ s!_OPENERSHORTNAME_!$openerShortName!;
	$theBody =~ s!_EDITORSHORTNAME_!$editorShortName!;
	$theBody =~ s!_LINKERSHORTNAME_!$linkerShortName!;
	$theBody =~ s!_FILESSHORTNAME_!$filesShortName!;
	#$theBody =~ s!_FILESERVERPORT_!$fileServerPort!g;
	$theBody =~ s!_WEAREREMOTE_!$amRemoteValue!;
	$theBody =~ s!_ALLOW_EDITING_!$tfAllowEditing!;
	$theBody =~ s!_USE_APP_FOR_EDITING_!$tfUseAppForEditing!;
	my $dtime = DoubleClickTime();
	$theBody =~ s!_DOUBLECLICKTIME_!$dtime!;

	
	# Put in an "Edit" button for files that can be edited (if editing is allowed).
	# "Edit" can invoke IntraMine's Editor or your preferred editor.
	my $editAction = EditButton($host, $filePath, $clientIsRemote, $allowEditing);
	$theBody =~ s!_EDITACTION_!$editAction!;
	
	# Experimental, trying to add Search/Find.
	my $search = "<input id=\"search-button\" class=\"submit-button\" type=\"submit\" value=\"Find\" />";
	$theBody =~ s!_SEARCH_!$search!;
	
	# Detect any searchItems passed along for hilighting. If there are any, add a
	# "Hide/Show Initial Hits" button at top of page.
	my $searchItems = defined($formH->{'searchItems'}) ? $formH->{'searchItems'} : '';
	my ($highlightItems, $toggleHitsButton) = InitialHighlightItems($formH, $usingCM, $searchItems);
	$theBody =~ s!_HIGHLIGHTITEMS_!$highlightItems!;
	$theBody =~ s!_INITIALHITSACTION_!$toggleHitsButton!;
	my $togglePositionButton = '';
	# Mardown Toggle won't work because there are no line numbers.
	if ($filePath !~ m!\.md$!i)
		{
		$togglePositionButton = PositionToggle();
		}
	$theBody =~ s!_TOGGLEPOSACTION_!$togglePositionButton!;

	my $inlineHoverButton = InlineHoverButton($filePath);
	$theBody =~ s!_HOVERINLINE_!$inlineHoverButton!;
	
	# Hilight class for table of contents selected element - see also non_cm_test.css
	# and cm_viewer.css.
	$theBody =~ s!_SELECTEDTOCID_!tocitup!; 
	
	# Put in main IP, main port, our short name for JavaScript.
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()
	
	# Keep this last, else a casual mention of _TITLE_ etc in the file contents
	# could get replaced by one of the above substitutions.
	$theBody =~ s!_FILECONTENTS_!$fileContents!;
	
	my $elapsed = time - $t1;
	my $ruffElapsed = substr($elapsed, 0, 6);
	#Output("Full File load time for $consoleDisplayedTitle: $ruffElapsed seconds\n");
	
	# TEST ONLY display load time.
	#print("Full File load time for $consoleDisplayedTitle: $ruffElapsed seconds\n");

	return $theBody;
	}

# HTML "skeleton" for the view. Placeholders (all caps with underscores) are filled in
# above in FullFile().
sub FullFileTemplate {
	my $theBody = <<'FINIS';
<!doctype html>
<html lang="en">
<head>
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="apple-touch-fullscreen" content="yes" />
<meta name="google" content="notranslate">
_META_CHARSET_
<!-- <meta http-equiv="content-type" content="text/plain; charset=utf-8"> -->
<title>_TITLE_</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="forms.css" />
_CSS_
_TEXTTABLECSS_
<link rel="stylesheet" type="text/css" href="tooltip.css" />
<link rel="stylesheet" type="text/css" href="dragTOC.css" />
</head>
<body>
<!-- added for touch scrolling, an indicator -->
<div id="indicator"></div> <!-- iPad -->
<div id="indicatorPC"></div>
_TOPNAV_
<div id="title-block">
<span id="viewEditTitle">_TITLEHEADER_</span><br /><span id="viewEditDateSize">_DATEANDSIZE_</span>
</div>
<div id="button-block">
_EDITACTION_ _INITIALHITSACTION_ _TOGGLEPOSACTION_ _SEARCH_ _HOVERINLINE_<span id="editor_error">&nbsp;</span> <span id='small-tip'>_MESSAGE__</span>
</div>
<hr id="rule_above_editor" />
<div id='scrollAdjustedHeight'>
_FILECONTENTS_
</div>
<script>
let weAreRemote = _WEAREREMOTE_;
let allowEditing = _ALLOW_EDITING_;
let useAppForEditing = _USE_APP_FOR_EDITING_;
let thePath = '_PATH_';
let theEncodedPath = '_ENCODEDPATH_';
let usingCM = _USING_CM_;
let cmTextHolderName = '_CMTEXTHOLDERNAME_';
let specialTextHolderName = 'specialScrollTextRightOfContents';
let clientIPAddress = '_CLIENT_IP_ADDRESS_'; 	// ip address of client (dup, for Editing only)
let ourServerPort = '_THEPORT_';
let viewerShortName = '_VIEWERSHORTNAME_';
let openerShortName = '_OPENERSHORTNAME_';
let editorShortName = '_EDITORSHORTNAME_';
let linkerShortName = '_LINKERSHORTNAME_';
let filesShortName = '_FILESSHORTNAME_';
let peeraddress = '_PEERADDRESS_';	// ip address of client
let errorID = "editor_error";
let highlightItems = [_HIGHLIGHTITEMS_];
let b64ToggleImage = '';
let selectedTocId = '_SELECTEDTOCID_';
let doubleClickTime = _DOUBLECLICKTIME_;
let weAreEditing = false; // Don't adjust user selection if editing - we are not editing here.
</script>
<script>
	// Call fn when ready.
	function ready(fn) {
	  if (document.readyState != 'loading'){
	    fn();
	  } else {
	    document.addEventListener('DOMContentLoaded', fn);
	  }
	}

	function getRandomInt(min, max) {
  		return Math.floor(Math.random() * (max - min + 1) + min);
		}	
</script>
<script src="debounce.js"></script>
<script src="tooltip.js"></script>
_JAVASCRIPT_
<script>
window.addEventListener('wsinit', function (e) { wsSendMessage('activity ' + shortServerName + ' ' + ourSSListeningPort); }, false);
</script>
</body></html>
FINIS

	return($theBody);
	}

# Fill in contents, meta line, and css file names based on extension at end of $filepath.
# Categories:
# 1. not text: PDF, docx, html (for viewing purposes), images.
# 2. pure custom with Table Of Contents (TOC): pl, pm, pod, txt, log, bat, cgi, y.
# 2.1 custom, no TOC: md (Markdown).
# 3.1 CodeMirror (CM) with TOC, no ctag support: go.
# 3.2 CM with TOC, ctag support: cpp, js, etc.
# 4. CM, no TOC: textile, out, other uncommon formats not supported by ctags.
# Note HTML is done above (Category 1.1).
sub GetContentBasedOnExtension {
	my ($formH, $peeraddress, $filePath, 
		$clientIsRemote, $allowEditing, $fileContents_R,
		$usingCM_R, $meta_R, $textTableCSS_R, $customCSS_R,
		$textHolderName_R) = @_;

	# CSS varies: CodeMirror, Markdown, (other) non-CodeMirror.
	# CodeMirror CSS:
	my $cssForCM = 
'<link rel="stylesheet" type="text/css" href="lib/codemirror.css" />' . "\n" .
'<link rel="stylesheet" type="text/css" href="addon/dialog/dialog.css" />' . "\n" .
'<link rel="stylesheet" type="text/css" href="addon/search/matchesonscrollbar.css" />' . "\n" .
'<link rel="stylesheet" type="text/css" media="screen" href="addon/search/cm_small_tip.css" />' . "\n" .
'<link rel="stylesheet" type="text/css" href="cm_viewer.css" />' . "\n";
	# Markdown CSS:
	my $cssForMD = '<link rel="stylesheet" type="text/css" href="cm_md.css" />';
	# Non CodeMirror CSS:
	my $cssForNonCm = '<link rel="stylesheet" type="text/css" href="non_cm_text.css" />';
	# For $textTableCSS variations, some table formatting.
	my $cssForNonCmTables = '<link rel="stylesheet" type="text/css" href="non_cm_tables.css" />';
	my $cssForPod = '<link rel="stylesheet" type="text/css" href="pod.css" />';


	# 1.2 Images: entire "contents" of the page is just an img link.
	if ($filePath =~ m!\.(png|gif|jpe?g|ico|webp)$!i)
		{
		# Temp, using $port_listen instead of $server_port to open images.
		# I'm working on it. Actually, no, I'm just leaving it.
		GetImageLink($formH, $peeraddress, $port_listen, $fileContents_R);
		$$usingCM_R = 'false';
		# $metaR is not needed.
		}
	# 1.3 PDF
	elsif ($filePath =~ m!\.pdf$!i)
		{
		GetPDF($formH, $peeraddress, $fileContents_R);
		$$usingCM_R = 'false';
		$$meta_R = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
		}
	elsif ($filePath =~ m!\.docx$!i) # old ".doc" is not supported
		{
		GetWordAsText($formH, $peeraddress, $fileContents_R);
		$$usingCM_R = 'false';
		$$meta_R = '<meta http-equiv="content-type" content="text/html; charset=windows-1252">';
		$$textTableCSS_R = $cssForNonCmTables;
		$$customCSS_R = $cssForNonCm;
		}
	# 2. pure custom with TOC: pl, pm, pod, txt, log, bat, cgi, t.
	# TEST ONLY codathon temp out
	elsif ($filePath =~ m!\.(p[lm]|cgi|t)$!i)
		{
		GetPrettyPerlFileContents($formH, $peeraddress, $clientIsRemote, $allowEditing, $fileContents_R);
		$$usingCM_R = 'false';
		$$textHolderName_R = 'scrollTextRightOfContents';
		$$meta_R = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
		$$customCSS_R = $cssForNonCm;
		$$textTableCSS_R = $cssForNonCmTables;
		}
	elsif ($filePath =~ m!\.pod$!i)
		{
		GetPrettyPod($formH, $peeraddress, $clientIsRemote, $allowEditing, $fileContents_R);
		$$usingCM_R = 'false';
		$$textHolderName_R = 'scrollTextRightOfContents';
		$$meta_R = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
		$$customCSS_R = $cssForNonCm . "\n" . $cssForPod;
		$$textTableCSS_R = $cssForNonCmTables;
		}
	elsif ($filePath =~ m!\.(txt|log|bat)$!i)
		{
		# Glossary files get a special table of contents, and not much else.
		if ($filePath =~ m![\\/]$GLOSSARYFILENAME$!i || $filePath =~ m![\\/]glossary.txt$!i)
			{
			GetPrettyGlossaryFile($formH, $peeraddress, $clientIsRemote, $allowEditing, $fileContents_R, undef);
			}
		else
			{
			# By default this runs the text through a Gloss processor.
			# So all your .txt files are belong to Gloss.
			GetPrettyTextContents($formH, $peeraddress, $clientIsRemote, $allowEditing, $fileContents_R, undef);
			}
		$$usingCM_R = 'false';
		$$textHolderName_R = 'scrollTextRightOfContents';
		$$meta_R = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
		# Code block syntax highlighting with lolight, only for .txt files:
		if ($filePath =~ m!\.txt|$!)
			{
			$cssForNonCm .= "\n" . '<link rel="stylesheet" href="lolight_custom.css" />';
			}
		$$customCSS_R = $cssForNonCm;
		$$textTableCSS_R = $cssForNonCmTables;		
		}
	# 2.1 custom, no TOC: md (Markdown)
	elsif ($filePath =~ m!\.md$!i)
		{
		GetPrettyMD($formH, $peeraddress, $fileContents_R);
		$$usingCM_R = 'false';
		$$textHolderName_R = 'scrollText';
		$$meta_R = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
		$$customCSS_R = $cssForMD;
		$$textTableCSS_R = $cssForNonCmTables;
		}
	# 3.1 go: CodeMirror for the main view with a custom Table of Contents
	elsif ($filePath =~ m!\.go$!i)
		{
		$$textHolderName_R = 'scrollTextRightOfContents';
		$$meta_R = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
		$$customCSS_R = $cssForCM;
		my $textContents = GetHtmlEncodedTextFile($filePath);
		my $toc = '';
		if ($textContents ne '')
			{
			GetGoTOC(\$textContents, \$toc);
			}
		$$fileContents_R = "<div id='scrollContentsList'>$toc</div>" . "<div id='scrollTextRightOfContents'></div>";
		}
	# 3.1 cont'd Fortran: CM for main view, custom TOC
	elsif ($filePath =~ m!\.(f|f77|f90|f95|f03|for)$!i)
		{
		$$textHolderName_R = 'scrollTextRightOfContents';
		$$meta_R = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
		$$customCSS_R = $cssForCM;
		my $textContents = GetHtmlEncodedTextFile($filePath);
		my $toc = '';
		if ($textContents ne '')
			{
			GetFortranTOC(\$textContents, \$toc);
			}
		$$fileContents_R = "<div id='scrollContentsList'>$toc</div>" . "<div id='scrollTextRightOfContents'></div>";
		}
	# 3.1 cont'd, COBOL: CM for main view, custom TOC
	elsif ($filePath =~ m!\.(cob|cpy|cbl)$!i)
		{
		$$textHolderName_R = 'scrollTextRightOfContents';
		$$meta_R = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
		$$customCSS_R = $cssForCM;
		my $textContents = GetHtmlEncodedTextFile($filePath);
		my $toc = '';
		if ($textContents ne '')
			{
			GetCOBOLTOC(\$textContents, \$toc);
			}
		$$fileContents_R = "<div id='scrollContentsList'>$toc</div>" . "<div id='scrollTextRightOfContents'></div>";
		}

	# 3.1 cont'd, Visual Basic: CM for main view, custom TOC
	# NOTE at present only .vb and .vbs are supported.
	elsif ($filePath =~ m!\.(bas|cls|ctl|frm|vbs|vba|vb)$!i)
		{
		$$textHolderName_R = 'scrollTextRightOfContents';
		$$meta_R = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
		$$customCSS_R = $cssForCM;
		my $textContents = GetHtmlEncodedTextFile($filePath);
		my $toc = '';
		if ($textContents ne '')
			{
			GetVBTOC(\$textContents, \$toc);
			}
		$$fileContents_R = "<div id='scrollContentsList'>$toc</div>" . "<div id='scrollTextRightOfContents'></div>";
		}
	# 3.2 CM with TOC, ctag support: cpp, js, etc, and now including .css
	elsif (IsSupportedByCTags($filePath))
		{
		$$textHolderName_R = 'scrollTextRightOfContents';
		$$meta_R = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
		$$customCSS_R = $cssForCM;
		my $toc = '';
		if ($filePath =~ m!\.css$!i)
			{
			# CSS is special, can have multiple entries per line.
			GetCssCTagsTOCForFile($filePath, \$toc);
			}
		else
			{
			GetCTagsTOCForFile($filePath, \$toc);
			}
		
		$$fileContents_R = "<div id='scrollContentsList'>$toc</div>" . "<div id='scrollTextRightOfContents'></div>";
		}
	# 4. CM, no TOC: textile, out, other uncommon formats not supported by ctags.
	else
		{
		$$meta_R = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
		$$customCSS_R = $cssForCM;
		$$fileContents_R = "<div id='scrollText'></div>";
		}
	}

# Content for Edit button at top of View. Images don't have an Edit button.
# Word and pdf have an Edit button only if client is on the IntraMine server (!$clientIsRemote).
sub EditButton {
	my ($host, $filePath, $clientIsRemote, $allowEditing) = @_;
	my $result = '';
	
	# No Edit button if it's an image.
	my $canEdit = ($filePath !~ m!\.(png|gif|jpe?g|ico|webp)$!i);
	if (!$allowEditing)
		{
		$canEdit = 0;
		}
	# No remote Edit for docx|pdf
	if ($canEdit)
		{
		if ($clientIsRemote && $filePath =~ m!\.(docx|pdf)$!i)
			{
			$canEdit = 0;
			}
		}

	# Edit button, text files will open with IntraMine's Editor or your preferred app,
	# the final decision being made in viewerlinks.js#editOpen().
	if (!$canEdit)
		{
		; # leave action empty
		}
	else
		{
		$result = <<'FINIS';
<a href='_FILEPATH_' onclick='editOpen(this.href); return false;'><input class="submit-button" type="submit" value="Edit" /></a>
FINIS
#<a href='_FILEPATH_' onclick='editWithPreferredApp(this.href); return false;'><img src='edit_55_22.png'></a>

		# TEST ONLY encode_utf8 out
		my $encFilePath = $filePath;
		#my $encFilePath = encode_utf8($filePath);
		$encFilePath =~ s!\\!/!g;
		$encFilePath =~ s!^file\:///!!;
		$encFilePath =~ s!%!%25!g;
		$encFilePath =~ s!\+!\%2B!g;
		# prob not needed $encFilePath = &HTML::Entities::encode($encFilePath);
		$result =~ s!_FILEPATH_!$encFilePath!;
		}
		
	return($result);
	}

# If we arrived at this View from Search results, get highlight information for inserting
# into the returned page: see _HIGHLIGHTITEMS_ in FullFileTemplate().
# For non-CodeMirror files, just poke the individual search words into an array.
# For CodeMirror, build a list of all the hits in the text of the file,
# array of "[line, charStart, charEnd]". Only the first 50 hits are done for CodeMirror.
# For non-CodeMirror files, the price of marking all occurrences is we must avoid
# marking one or two-letter words, otherwise things stall out in large files.
sub InitialHighlightItems {
	my ($formH, $usingCM, $searchItems) = @_;
	my $highlightItems = '';
	
	if ($searchItems ne '')
		{
		my $forExactPhrase = ($searchItems =~ m!^\"!);
		# Fix up special characters such as ' __D_ '.
		DecodeSpecialNonWordCharacters(\$searchItems);
		$searchItems = lc($searchItems);
		$searchItems =~ s!\"!!g;
		my @items = split(/ +/, $searchItems);
		
		if ($usingCM eq 'true')
			{
			if ($forExactPhrase)
				{
				@items = ();
				push @items, $searchItems;
				}
			GetCodeMirrorSearchHitPositions($formH, \@items, \$highlightItems);
			}
		else
			{
			if ($forExactPhrase)
				{
				if (length($searchItems) > 2)
					{
					$highlightItems = "\"$searchItems\"";
					}
				}
			else
				{
				my $numItems = @items;
				my $numSoFar = 0;
				for (my $i = 0; $i < $numItems; ++$i)
					{
					if (length($items[$i]) > 2)
						{
						if ($numSoFar == 0)
							{
							$highlightItems = "\"$items[$i]\"";
							}
						else
							{
							$highlightItems .= ",\"$items[$i]\"";
							}
						++$numSoFar;
						}
					}
				}
			}
		}
	
	my $toggleHitsButton = '';
	if ($highlightItems ne '')
		{
		$toggleHitsButton = '<input onclick="toggleInitialSearchHits();" id="sihits" class="submit-button" type="submit" value="Hide Initial Hits" />';
		}
	
	return($highlightItems, $toggleHitsButton);
	}

sub DecodeSpecialNonWordCharacters {
	my ($txtR) = @_;
	
	$$txtR =~ s! *__D_ *!\.!g;
	$$txtR =~ s!__DS_([A-Za-z])!\$$1!g;
	$$txtR =~ s!__L_([A-Za-z])!\~$1!g;
	$$txtR =~ s!__PC_([A-Za-z])!\%$1!g;
	$$txtR =~ s!__AT_([A-Za-z])!\@$1!g;
	}

sub PositionToggle {
	my $result = '<input onclick="toggle();" id="togglehits" class="submit-button" type="submit" value="Toggle" />';
	return($result);
	}

sub InlineHoverButton {
	my ($filePath) = @_;
	my $result = '';
	if ($filePath !~ m!\.txt$!i)
		{
		return($result);
		}
	$result = '<input onclick="toggleImagesButton();" id="inlineImages" class="submit-button" type="submit" value="Inline Images" />';

	return($result);
	}

# CodeMirror JavaScript and non-CodeMirror JS are rather different, especially in the way that
# such things as links and highlights are handled. For non-CodeMirror, links and highlights
# are put right in the HTML, whereas CodeMirror links and highlights are handled with
# overlay markers (for an overview of that, see https://codemirror.net/doc/manual.html#markText).
sub CodeMirrorJS {
	my $jsFiles = <<'FINIS';
<script src="lib/codemirror.js" ></script>
<script src="addon/mode/loadmode.js"></script>
<script src="mode/meta.js"></script>
<script src="addon/dialog/dialog.js"></script>
<script src="addon/search/search.js"></script>
<script src="addon/scroll/annotatescrollbar.js"></script>
<script src="addon/search/matchesonscrollbar.js"></script>
<script src="addon/search/searchcursor.js"></script>
<script src="addon/search/match-highlighter.js"></script>
<script src="addon/search/jump-to-line.js"></script>

<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
<script src="isW.js" ></script>
<script src="cmViewerStart.js" ></script>
<script src="viewerLinks.js" ></script>
<script src="cmAutoLinks.js" ></script>
<script src="cmTocAnchors.js" ></script>
<script src="cmViewerMobile.js" ></script>
<script src="showHideTOC.js" ></script>
<script src="cmShowSearchItems.js" ></script>
<script src="cmToggle.js" ></script>
<script src="cmScrollTOC.js" ></script>
<script src="dragTOC.js" ></script>
<script src="viewer_auto_refresh.js" ></script>
<script src="cmHandlers.js" ></script>
FINIS

	return($jsFiles);
	}

# JavaScript for non-CodeMirror "custom" views (text, Perl and a few others).
sub NonCodeMirrorJS {
	my $jsFiles = <<'FINIS';
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
<script src="isW.js" ></script>
<script src="mark.min.js" ></script>
<script src="wordAtInsertionPt.js" ></script>
<script src="LightRange.min.js" ></script>
<script src="commonEnglishWords.js" ></script>
<script src="viewerStart.js" ></script>
<script src="autoLinks.js" ></script>
<script src="showHideTOC.js" ></script>
<script src="viewerLinks.js" ></script>
<script src="indicator.js" ></script>
<script src="toggle.js" ></script>
<script src="scrollTOC.js" ></script>
<script src="viewer_auto_refresh.js" ></script>
<script src="dragTOC.js" ></script>
<script src="viewer_hover_inline_images.js" ></script>
<script>
hideSpinner();
</script>
FINIS

	return($jsFiles);
	}

# "req=loadfile" handling. For CodeMirror views, the text is loaded by JavaScript after the
# page starts up, see cmViewerStart.js#loadFileIntoCodeMirror().
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

# Open a directory link using Windows File Explorer.
sub OpenDirectory {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = 'OK';
	my $dirPath = defined($formH->{'dir'})? $formH->{'dir'}: '';
	if ($dirPath eq '')
		{
		$result = 'ERROR, no directory supplied!';
		}
	else
		{
		$dirPath =~ s!^file\:///!!g;
		
		# DAAAMM this is ugly.
		# https://www.perlmonks.org/?node_id=1162804
		$dirPath = Encode::encode("CP1252", $dirPath);
		
		system('start', '', $dirPath);
		}
	
	return($result);
	}

# "req=loadfile" handling. For CodeMirror views, the text is loaded by JavaScript after the
# page starts up, see cmViewerStart.js#loadFileIntoCodeMirror().
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
		return(GetHtmlEncodedTextFileWide($filePath));
		}
	}


# Straight HTML. Note resulting page has no TopNav.
sub GetHTML {
	my ($formH, $peeraddress, $contentsR) = @_;
	my $filePath = $formH->{'FULLPATH'};
	
	$$contentsR = "";
	my $sourceFileH = GetExistingReadFileHandleWide($filePath);
	
	if (!defined($sourceFileH))
		{
		my $exists = FileOrDirExistsWide($filePath);
		if ($exists == 1)
		#if (-f $filePath)
			{
			$$contentsR .= "Error, could not open $filePath.";
			}
		else
			{
			$$contentsR .= "Error, $filePath does not exist.";
			}
		return;
		}
	
	my $inStr = '';
	my $line = '';
	my @lines;
	while ($line = <$sourceFileH>)
		{
		chomp $line;
		push @lines, $line;
		}
	close $sourceFileH;
	
	$$contentsR .= join("\n", @lines);
	}

sub GetImageLink {
	my ($formH, $peeraddress, $port, $contentsR) = @_;
	my $fileLocation = $formH->{'FULLPATH'};
	my $serverAddr = ServerAddress();
	
	$fileLocation =~ s!%!%25!g;
	$fileLocation = &HTML::Entities::encode($fileLocation);
	
	my $imagePath = "http://$serverAddr:$port/$fileLocation";
	$$contentsR = "<img src='$imagePath'>";
	}

# PDF: requires having swarmserver.pm#Respond() add a couple of headers to response.
sub GetPDF {
	my ($formH, $peeraddress, $contentsR) = @_;
	my $fileLocation = $formH->{'FULLPATH'};
	$$contentsR = GetBinFile($fileLocation);
	
	# Add two extra headers to force PDF to open in browser.
	# Microsoft Edge is fine, tho it doesn't show <title>. Chrome just plain won't do it directly, probably
	# another wonderful "you don't have a clue what you're doing, let us protect you" issue.
	# Chrome works if install "PDF Viewer" extension (no need to disable Chrome's builtin PDF plugin
	# at chrome://plugins).
	my $extraHeadersA = $formH->{'EXTRAHEADERSA'};
	push @$extraHeadersA, "Content-Type: application/pdf";
	my $fileName = FileNameFromPath($fileLocation);
	push @$extraHeadersA, "Content-Disposition: inline; filename=\"$fileName\"";
	}

# Pull plain text with almost no formatting out of a Word docx file.
sub GetWordAsText {
	my ($formH, $peeraddress, $contentsR) = @_;
	my $fileLocation = $formH->{'FULLPATH'};
	
	my $docxReader = docx2txt->new();
	$docxReader->ShowHyperlinks();
	$docxReader->ShowListNumbering();
	
	my $contents = $docxReader->Contents($fileLocation);
	
	$$contentsR = "";
	$$contentsR .= "<div id='scrollText'><table><tbody>" . $contents . '</tbody></table></div>';
	}

sub UniqueTocID {
	my ($id, $idExists_H) = @_;

	my $idBump = 2;
	my $idBase = $id;
	while ($id eq '' || defined($idExists_H->{$id}))
		{
		$id = $idBase . $idBump;
		++$idBump;
		}
	$idExists_H->{$id} = 1;

	return($id);
	}

# Table Of Contents (TOC) on the left, highlighted Perl on the right.
# Syntax::Highlight::Perl::Improved does the formatting.
# Autolinks are added for source and text files, web addresses, and images.
# "use Package::Module;" is given a local link and a link to metacpan,
sub GetPrettyPerlFileContents {
	my ($formH, $peeraddress, $clientIsRemote, $allowEditing, $contentsR) = @_;
	my $filePath = $formH->{'FULLPATH'};
	my $dir = lc(DirectoryFromPathTS($filePath));
	my $serverAddr = ServerAddress();
	$$contentsR = "";
	
	my $octets;
	if (!LoadPerlFileContents($filePath, $contentsR, \$octets))
		{
		return;
		}
	
	my @lines = split(/\n/, $octets);
	
	# Put in line numbers etc.
	my @jumpList;
	my @subNames;
	my @sectionList;
	my @sectionNames;
	my $lineNum = 1;
	my %sectionIdExists; # used to avoid duplicated anchor id's for sections.
	
	for (my $i = 0; $i < @lines; ++$i)
		{
		# Turn 'use Package::Module;' into a link to metacpan. One wrinkle, if it's a local-only module
		# then link directly to the module. (This relies on user having indexed the module while
		# setting up full text search, but I can't think of a better way.)
#		if ($lines[$i] =~ m!(use|import)\s*</span>!)
#			{
#			AddModuleLinkToPerl(\${lines[$i]}, $dir, $serverAddr, $server_port, $clientIsRemote, $allowEditing);
#			}
		
		# Put subs etc in TOC, with links.
		# Links for subs are moved up to the first comment that goes with the sub.
		# <span class='line_number'>204</span>&nbsp;<span class='Keyword'>sub</span> <span class='Subroutine'>
		if ($lines[$i] =~ m!^\<span\s+class=\'Keyword\'\>\s*sub\s*\<\/span\>\s*\<span\s+class=\'Subroutine\'\>(\w+)\<\/span\>!)
			{
			# Use $subName as the $id
			my $subName = $1;
			my $id = $subName;
			$sectionIdExists{$id} = 1;
			my $contentsClass = 'h2';
			my $jlStart = "<li class='$contentsClass' im-text-ln='$lineNum'><a href='#$id'>";
			my $jlEnd = "</a></li>";
			my $destAnchorStart = "<span id='$id'>";
			my $destAnchorEnd = "</span>";
			my $displayedSubName = $subName;
			push @jumpList, $jlStart . $s_icon . $displayedSubName . '()' . $jlEnd;
			push @subNames, $subName;
			my $anki = $i;
			# Look for highest comment above sub.
			if ( $i > 0 && ($lines[$i-1] =~ m!^<tr id='R\d+'><td[^>]+></td><td><span\s+class='Comment_Normal'>!) )
				{
				$anki = $i - 1;
				my $testi = $i - 2;
				while ($testi > 0 && $lines[$testi] =~ m!^<tr id='R\d+'><td[^>]+></td><td><span\s+class='Comment_Normal'>!)
					{
					$anki = $testi;
					--$testi;
					}
				}
			if ($anki == $i)
				{
				$lines[$i] =~ s!$subName!$destAnchorStart$subName$destAnchorEnd!;
				}
			else
				{
				$lines[$anki] =~ s!\#!$destAnchorStart\#$destAnchorEnd!;
				}
			}
		# "Sub-modules" - top level { ## Description \n code...}
		elsif ($lines[$i] =~ m!\<span\s+class=\'Symbol\'\>\{\<\/span>\s*\<span\s+class=\'Comment_Normal\'\>##+\s+(.+?)\<\/span\>!)
			{
			# Use section_name_with_underscores_instead_of_spaces as the $id, unless it's a duplicate.
			# Eg intramine_main_3.pl#Drive_list
			my $sectionName = $1;
			my $id = $sectionName;
			$id =~ s!\s+!_!g;
			if (defined($sectionIdExists{$id}))
				{
				my $anchorNumber = @sectionList;
				$id = "hdr_$anchorNumber";
				}
			$sectionIdExists{$id} = 1;
			my $contentsClass = 'h2';
			my $jlStart = "<li class='$contentsClass' im-text-ln='$lineNum'><a href='#$id'><strong>";
			my $jlEnd = "</strong></a></li>";
			my $destAnchorStart = "<span id='$id'>";
			my $destAnchorEnd = "</span>";
			push @sectionList, $jlStart . $S_icon . $sectionName . $jlEnd;
			push @sectionNames, $sectionName;
			$lines[$i] =~ s!$sectionName!$destAnchorStart$sectionName$destAnchorEnd!;			
			}
		# mini MultiMarkdown:
		$lines[$i] =~ s!(^|[ #/])(TODO)!$1<span class='notabene'>$2</span>!;
		$lines[$i] =~ s!(REMINDER|NOTE)!<span class='notabene'>$1</span>!;
		
###		AddFileLinksToPerl(\${lines[$i]}, $dir, $serverAddr, $server_port, $clientIsRemote, $allowEditing);
		my $rowID = 'R' . $lineNum;
		$lines[$i] = "<tr id='$rowID'><td n='$lineNum'></td><td>" . $lines[$i] . '</td></tr>';
		++$lineNum;
		}
	
	# Add internal links to Perl files.
	# Put in links that reference Table Of Contents entries within the current document.
	for (my $i = 0; $i < @lines; ++$i)
		{
		AddInternalLinksToPerlLine(\${lines[$i]}, \%sectionIdExists);
		}

	if (defined($lines[0]))
		{
		$lines[0] = "<span id='top-of-document'></span>" . $lines[0];
		}
	my @idx = sort { $subNames[$a] cmp $subNames[$b] } 0 .. $#subNames;
	@jumpList = @jumpList[@idx];
	@idx = sort { $sectionNames[$a] cmp $sectionNames[$b] } 0 .. $#sectionNames;
	@sectionList = @sectionList[@idx];
	my $numSectionEntries = @sectionList;
	my $sectionBreak = ($numSectionEntries > 0) ? '<br>': '';
	$$contentsR .= "<div id='scrollContentsList'>" . "<ul>\n<li class='h2' im-text-ln='1'><a href='#top-of-document'>TOP</a></li>\n" . join("\n", @sectionList) . $sectionBreak . join("\n", @jumpList) . '</ul></div>' . "\n";
	$$contentsR .= "<div id='scrollTextRightOfContents'><table><tbody>" . join("\n", @lines) . '</tbody></table></div>';
	
	$$contentsR = encode_utf8($$contentsR);
	}

# Markdown.
sub GetPrettyMD {
	my ($formH, $peeraddress, $contentsR) = @_;
	my $filePath = $formH->{'FULLPATH'};
	my $dir = lc(DirectoryFromPathTS($filePath));
	my $serverAddr = ServerAddress();
	$$contentsR = ""; #"<hr />";
	
	my $octets;
	if (!LoadTextFileContents($filePath, $contentsR, \$octets))
		{
		return;
		}

	my $m = Text::MultiMarkdown->new(
	    empty_element_suffix => '>',
	    tab_width => 4,
	    use_wikilinks => 0,
		);
	my $html = $m->markdown( $octets );

	# Regex to add raw=true has been moved to autoLinks.jsrequestLinkMarkupWithPortForMarkdown().
	##$html = FixGithubLinks($html);
	
	$$contentsR = "<div id='scrollText'>" . $html . "</div>";
	
	$$contentsR = encode_utf8($$contentsR);
	}

# Add raw=true to github links.
sub FixGithubLinks {
	my ($src) = @_;

	my @lines = split(/\n/, $src);
	for (my $i = 0; $i < @lines; ++$i)
		{
		# Add ?raw=true to github img src.
		if (index($lines[$i], "?raw=true") < 0)
			{
			$lines[$i] =~ s!https://github.com/([^'"]+)(['"])!https://github.com/$1?raw=true$2!g;
			}
		}

	my $result = join("\n", @lines);

	return($result);
	}

# Call LoadPodFileContents() to get an HTML version using Pod::Simple::HTML,
# then use html2gloss.pm to convert that to Gloss.
# Finally, pass that through GetPrettyTextFileContents() to convert the
# Gloss text to HTML for display. Whew.
sub GetPrettyPod {
	my ($formH, $peeraddress, $clientIsRemote, $allowEditing, $contentsR) = @_;
	my $filePath = $formH->{'FULLPATH'};
	my $dir = lc(DirectoryFromPathTS($filePath));
	my $serverAddr = ServerAddress();
	$$contentsR = "";

	my $octets;
	if (!LoadPodFileContents($filePath, \$octets))
		{
		return;
		}

	# Convert HTML tags and text to Gloss equivalents. See html2gloss.pm
	my $p = html2gloss->new();
	my $contentsInrawGloss;
	$p->htmlToGloss(\$octets, \$contentsInrawGloss);

	
	# TEST ONLY
	# Dump what we have so far.
	#WriteTextFileWide("C:/perlprogs/IntraMine/test/test_pod_4_gloss.txt", $contentsInrawGloss);


	# Convert to Gloss HTML display with GetPrettyTextContents().
	GetPrettyTextContents($formH, $peeraddress, $clientIsRemote, $allowEditing, $contentsR, \$contentsInrawGloss);
	}

# An attempt at a pleasing and useful view of text files.
# This is the main implementation of Gloss, IntraMine's markdown variant
# optimized for intranet use.
# All text (.txt) files are run through Gloss processing, see Gloss.txt for details. There are
# autolinks and hover images and headings and tables and lists and all that.
# A Table of Contents down the left side lists headings.
# Alas, handling POD files introduces a light fog of special cases.
sub GetPrettyTextContents {
	my ($formH, $peeraddress, $clientIsRemote, $allowEditing, $contentsR, $sourceR) = @_;
	my $serverAddr = ServerAddress();
	
	my $filePath = $formH->{'FULLPATH'};
	my $dir = lc(DirectoryFromPathTS($filePath));
	$$contentsR = ""; # "<hr />";
	
	my $doingPOD = 0;
	my $inPre = 0; # POD only, are we in a <pre> element?
	my $octets;

	# GetPrettyPod calls this sub with loaded source.
	# Pod sends a lot of placeholders such as _A_, _POLB_, _ALB_ etc
	# that are removed or replaced below if $doingPOD is set
	# - see html2gloss.pm for details on why they are needed.
	if (defined($sourceR))
		{
		$doingPOD = 1;

		$octets = $$sourceR;
		}
	else
		{
		if (!LoadTextFileContents($filePath, $contentsR, \$octets))
			{
			return;
			}
		}
	
	# Preserve consecutive blank lines at bottom.
	$octets .= "\nx";
	my @lines = split(/\n/, $octets);
	pop @lines;
	 
	my @jumpList;
	my $lineNum = 1;
	my %sectionIdExists; # used to avoid duplicated anchor id's for sections.
	my $orderedListNum = 0;
	my $secondOrderListNum = 0;
	my $unorderedListDepth = 0; # 0 1 2 for no list, top level, second level.
	my $justDidHeadingOrHr = 0;
	# Rev May 14 2021, track whether within TABLE, and skip lists, hr, and heading if so.
	# We are in a table from seeing a line that starts with TABLE|[_ \t:.-]? until a line with no tabs.
	my $inATable = 0;
	my $inACodeBlock = 0; 	# Set if see CODE on a line by itself,
							# continue until ENDCODE on a line by itself.
	my $numLines = @lines;
	
	# Gloss, aka minimal Markdown.
	for (my $i = 0; $i < $numLines; ++$i)
		{
		# See if we're entering or leaving a code block.
		# A code block starts with 'CODE' on a line by itself,
		# and ends with 'ENDCODE' on a line by itself.
		# CODE/ENDCODE is replaced by '_STARTCB_FL_',
		# and intervening lines have '_STARTCB_' added
		# at the beginning. Later, viewerStart.js#finishStartup()
		# will delete the markers and wrap lines in <pre> elements,
		# and lolight will style them when the page is ready.
		if (!$doingPOD && !$inATable)
			{
			if ($lines[$i] eq 'CODE')
				{
				$lines[$i] = '_STARTCB_FL_';
				$inACodeBlock = 1;
				}
			elsif ($lines[$i] eq 'ENDCODE')
				{
				$lines[$i] = '_STARTCB_FL_';
				$inACodeBlock = 0;
				}
			}
		
		# Highlight code blocks. Actual highlighting is done by
		# viewerStart.js#finishStartup().
		if ($inACodeBlock)
			{
			if ($lines[$i] ne '_STARTCB_FL_')
				{
				$lines[$i] = '_STARTCB_' . $lines[$i];
				}
			}
		
		# Rmove _INDT_ for all lines, and count how many. These only come from .pod files.
		my $indentClass = '';
		if ($doingPOD && (my $indentPos = index($lines[$i], '_INDT_')) >= 0)
			{
			my $indentLevel = 0;
			while ($indentPos >= 0)
				{
				++$indentLevel;
				$lines[$i] = substr($lines[$i], 0, $indentPos) . substr($lines[$i], $indentPos + 6);
				$indentPos = index($lines[$i], '_INDT_');
				}
			if ($indentLevel == 1)
				{
				$indentClass = 'onePodIndent';
				}
			elsif ($indentLevel == 2)
				{
				$indentClass = 'twoPodIndents';
				}
			elsif ($indentLevel == 3)
				{
				$indentClass = 'threePodIndents';
				}
			elsif ($indentLevel >= 4)
				{
				$indentClass = 'fourPodIndents';
				}
			}

		AddEmphasis(\$lines[$i], $doingPOD);

		# After fooling AddEmphasis() with a one or more of _NBS_ placeholder in place of
		# any trailing space, we can put the space back. Pod only.
		if ($doingPOD)
			{
			$lines[$i] =~ s!_NBS_! !g;
			}

		if ($lines[$i] =~ m!^TABLE($|[_ \t:.-])!)
			{
			$inATable = 1;
			}
		elsif ($inATable && $lines[$i] !~ m!\t!)
			{
			$inATable = 0;
			}

		if (!$inATable)
			{
			# Special <pre> starts and ends _SPRE_ _EPRE_ from html2gloss.pm for POD files.
			# These are just horizontal rules, marking the start and end of <pre> sections.
			my $didPodPreRule = 0;
			if ($doingPOD && $lines[$i] =~ m!^\s*(_[SE]PR_)\s*$!)
				{
				my $preSignal = $1;
				if (index($preSignal, 'S') > 0)
					{
					$inPre = 1;
					}
				else
					{
					$inPre = 0;
					}
				PreRule(\$lines[$i], $lineNum, $indentClass);
				$didPodPreRule = 1;
				}
			else
				{
				# Convert unordered (bullet) and numbered lists to final form.
				# Skip if a heading underline follows.
				if ($i == $numLines - 1 || $lines[$i + 1] !~ m!^[=~-][=~-][=~-][=~-][=~-]+$!)
					{
					UnorderedList(\$lines[$i], \$unorderedListDepth, $indentClass, $doingPOD);
					OrderedList(\$lines[$i], \$orderedListNum, \$secondOrderListNum, $indentClass);
					}
				}
			
			if ($doingPOD)
				{
				# Translate __A__ (an asterisk standin from POD) to *. We've waited until
				# here because '*' is important in AddEmphasis() and UnorderedList().
				$lines[$i] =~ s!__A__!\*!g;

				# And remove _POLB_ (Pod Ordered List Blocker), that was blocking the interpretation
				# of a line starting with a number as being a Gloss ordered list item.
				$lines[$i] =~ s!_POLB_!!g;
				}
			
			if (!$didPodPreRule)
				{
				# Hashed heading eg ## Heading.
				if ($lines[$i] =~ m!^#+\s+!)
					{
					Heading(\$lines[$i], undef, undef, \@jumpList, $i, \%sectionIdExists);
					$justDidHeadingOrHr = 1;
					}
				# Underlines -> hr or heading. Heading requires altering line before underline.
				elsif ($i > 0 && $lines[$i] =~ m!^[=~-][=~-]([=~-]+)$!)
					{
					my $underline = $1;
					if (length($underline) <= 2) # ie three or four total
						{
						HorizontalRule(\$lines[$i], $lineNum, $indentClass);
						}
					elsif ($justDidHeadingOrHr == 0) # a heading - put in anchor and add to jump list too
						{
						Heading(\$lines[$i], \$lines[$i-1], $underline, \@jumpList, $i, \%sectionIdExists);
						}
					else # treat like any ordinary line
						{
						my $rowID = 'R' . $lineNum;
						$lines[$i] = "<tr id='$rowID'><td n='$lineNum'></td><td>" . $lines[$i] . '</td></tr>';
						}
					$justDidHeadingOrHr = 1;
					}
				# Anchors, gotta put them in all the way down so links to them work.
				elsif (index($lines[$i], '_ALB_') >= 0)
					{
					Anchor(\$lines[$i]);
					my $rowID = 'R' . $lineNum;
					my $classAttr = ClassAttribute('', $indentClass);
					$lines[$i] = "<tr id='$rowID'><td n='$lineNum'></td><td$classAttr>" . $lines[$i] . '</td></tr>';
					$justDidHeadingOrHr = 0;
					}
				else # treat like any ordinary line
					{
					my $rowID = 'R' . $lineNum;
					my $classAttr = ClassAttribute('', $indentClass);
					$lines[$i] = "<tr id='$rowID'><td n='$lineNum'></td><td$classAttr>" . $lines[$i] . '</td></tr>';
					$justDidHeadingOrHr = 0;
					}
				}
			}
		else # In a table, nothing special done yet - see just below, PutTablesInText().
			{
			# Put contents in table, separate cells for line number and line proper
			my $rowID = 'R' . $lineNum;
			$lines[$i] = "<tr id='$rowID'><td n='$lineNum'></td><td>" . $lines[$i] . '</td></tr>';
			$justDidHeadingOrHr = 0;
			}

		# Add background color to <pre> lines.
		if ($inPre && $inPre++ > 1)
			{
			$lines[$i] =~ s!^<tr !<tr class='pre_line' !;
			}
		++$lineNum;
		}
	
	# Tables.
	PutTablesInText(\@lines);
	
	# Put in internal links that reference headers within the current document.
	for (my $i = 0; $i < @lines; ++$i)
		{
		AddInternalLinksToLine(\${lines[$i]}, \%sectionIdExists);
		}
	
	# Assemble the table of contents and text.
	# Special treatment (optional) for an contents.txt file with "contents" as the first line;
	# Style it up somewhat to more resemble a proper (old-fashioned) Table Of Contents.
	if (IsSpecialIndexFile($filePath, \@lines))
		{
		MakeSpecialIndexFileLookSpecial(\@lines);
		my $specialImageBackgroundImage =  CVal('SPECIAL_INDEX_BACKGROUND');
		$$contentsR .= "<div id='specialScrollTextRightOfContents' style='background-image: url(\"$specialImageBackgroundImage\");'><div id='special-index-wrapper'><table><tbody>" . join("\n", @lines) . '</tbody></table></div></div>';
		#$$contentsR .= "<div id='specialScrollTextRightOfContents'><div id='special-index-wrapper'><table><tbody>" . join("\n", @lines) . '</tbody></table></div></div>';
		}
	else
		{
		if (defined($lines[0]))
			{
			$lines[0] = "<span id='top-of-document'></span>" . $lines[0];
			}
		unshift @jumpList, "<ul>";
		unshift @jumpList, "<li class='h2' im-text-ln='1'><a href='#top-of-document'>TOP</a></li>";
		$$contentsR .= "<div id='scrollContentsList'>" . join("\n", @jumpList) . '</ul></div>';
		my $bottomShim = "<p id='bottomShim'></p>";
		$$contentsR .= "<div id='scrollTextRightOfContents'><table><tbody>" . join("\n", @lines) . "</tbody></table>$bottomShim</div>";
		}
	
	if (!defined($sourceR))
		{
		$$contentsR = encode_utf8($$contentsR);
		}
	}

# A basic view of an IntraMine glossary file, with an alphabetical table of contents.
sub GetPrettyGlossaryFile {
	my ($formH, $peeraddress, $clientIsRemote, $allowEditing, $contentsR, $sourceR) = @_;
	my $serverAddr = ServerAddress();
	
	my $filePath = $formH->{'FULLPATH'};
	my $dir = lc(DirectoryFromPathTS($filePath));
	$$contentsR = ""; # "<hr />";

	my $octets;
	if (!LoadTextFileContents($filePath, $contentsR, \$octets))
		{
		return;
		}

	
	my @lines = split(/\n/, $octets);

	my $indentClass = '';
	my @jumpList;
	my $lineNum = 1;
	my %sectionIdExists; # used to avoid duplicated anchor id's for sections.
	my $numLines = @lines;
	
	# Gloss, aka minimal Markdown.
	for (my $i = 0; $i < $numLines; ++$i)
		{
		if ($lines[$i] =~ m!^([^:]+)\:!)
			{
			my $term = $1;
			my $anchorText = lc(AnchorForGlossaryTerm($term));
			my $contentsClass = 'h2';
			my $jlStart = "<li class='$contentsClass' im-text-ln='$lineNum'><a href='#$anchorText'>";
			my $jlEnd = "</a></li>";
			push @jumpList, $jlStart . $term . $jlEnd;
			}

		my $rowID = 'R' . $lineNum;
			my $classAttr = ClassAttribute('', $indentClass);
			$lines[$i] = "<tr id='$rowID'><td n='$lineNum'></td><td$classAttr>" . $lines[$i] . '</td></tr>';
		
		++$lineNum;
		}

	for (my $i = 0; $i < @lines; ++$i)
		{
		AddGlossaryAnchor(\${lines[$i]});
		}

	if (defined($lines[0]))
		{
		$lines[0] = "<span id='top-of-document'></span>" . $lines[0];
		}
	unshift @jumpList, "<ul>";
	@jumpList = sort TocSort @jumpList;
	unshift @jumpList, "<li class='h2' im-text-ln='1'><a href='#top-of-document'>TOP</a></li>";
	$$contentsR .= "<div id='scrollContentsList'>" . join("\n", @jumpList) . '</ul></div>';
	my $bottomShim = "<p id='bottomShim'></p>";
	$$contentsR .= "<div id='scrollTextRightOfContents'><table><tbody>" . join("\n", @lines) . "</tbody></table>$bottomShim</div>";

	$$contentsR = encode_utf8($$contentsR);
	}

sub AnchorForGlossaryTerm {
	my ($term) = @_;
	
	$term =~ s!&nbsp;!_!g;
	$term =~ s!['"]!!g;
	$term =~ s!\&#\d+;!!g; # eg &#9755;
	$term =~ s!\s!_!g;
	$term =~ s!\-!_!g;
	
	return($term);
	}

# For glossary.txt only, add anchors for defined terms.
sub AddGlossaryAnchor {
	my ($txtR) = @_;
	
	# Init variables with "Glossary loading" scope.
	my $line = $$txtR;
	my $len = length($line);
	
	# Typical line start for defined term:
	# <tr><td n='21'></td><td>Strawberry Perl: 
	if ($line =~ m!^(.+?<td>\s*)([^:]+)\:(.*)$!)
		{
		my $pre = $1;
		my $post = $3;
		my $term = $2;
		my $originalText = $term;
		$term = lc($term);
		$term =~ s!\*!!g;
		my $anchorText = AnchorForGlossaryTerm($term);
		my $rep = "<h2 id=\"$anchorText\"><strong>$originalText</strong>:</h2>";
#		my $rep = "<a id=\"$anchorText\"><strong>$originalText</strong>:</a>";
		$$txtR = $pre . $rep . $post;
		}
	}

# Sort @jumpList (above) based on anchor text. Typical @jumpList entry:
# <li class="h2" im-text-ln="41"><a href="#map_network_drive">Map network drive</a></li>
sub TocSort {
	my $result = -1;
	
	if ($a =~ m!\#([^\>]+)\>!)
		{
		my $aStr = $1;
		if ($b =~ m!\#([^\>]+)\>!)
			{
			my $bStr = $1;
			$result = $aStr cmp $bStr;;
			}
		}

	return($result);
}

# Cook up a class= entry.
# Any one specific class, or indent level class, or ''.
# Leading space is tacked in to make final assembly easier.
sub ClassAttribute {
	my ($specificClass, $indentClass) = @_;
	my $result = '';
	
	if ($specificClass eq '' && $indentClass eq '')
		{
		return($result);
		}
	
	if ($specificClass ne '')
		{
		$result = ' class=';
		my $classes = $specificClass;
		if ($indentClass ne '')
			{
			$classes .= " $indentClass";
			}
		$result .= "'$classes'";
		}
	else # we have in indent level, no specific class
		{
		$result = " class='$indentClass'";
		}
	
	return($result);
	}

# sub IndentClass {
# 	my ($indentLevel) = @_;
# 	my $result = '';

# 	if ($indentLevel > 0)
# 		{
# 		if ($indentLevel == 1)
# 			{
# 			$result = 'onePodIndent';
# 			}
# 		else
# 			{
# 			$result = 'twoPodIndents';
# 			}
# 		}
	
# 	return($result);
# 	}

sub AddEmphasis {
	my ($lineR, $doingPOD) = @_;

	$$lineR =~ s!\&!\&amp;!g;
	$$lineR =~ s!\<!&#60;!g;
	$$lineR =~ s!\&#62;!&gt;!g;
	
	# *!*code*!* **bold** *italic*  (NOTE __bold__  _italic_ not done, they mess up file paths).
	
	$$lineR =~ s!\*\!\*(.*?)\*\!\*!<code>$1</code>!g;
	# For italic and bold, avoid a space or tab as the last character,
	# to prevent bolding "*this, but *this doesn't always" etc.
	$$lineR =~ s!\*\*(.*?[^\s])\*\*!<strong>$1</strong>!g;
	$$lineR =~ s!\*(.*?[^\s])\*!<em>$1</em>!g;
	
	# Somewhat experimental, loosen requirements to just *.+?\S* and **.+?\S**
	#$$lineR =~ s!\*\*(.+?\S)\*\*!<strong>$1</strong>!g;
	#$$lineR =~ s!\*(.+?\S)\*!<em>$1</em>!g;
	## Older more restrictive approach
	#$$lineR =~ s!\*\*([a-zA-Z0-9_. \t',-]+[a-zA-Z0-9_.'-])\*\*!<strong>$1</strong>!g;
	#$$lineR =~ s!\*([a-zA-Z0-9_. \t'",-]+[a-zA-Z0-9_.'"-])\*!<em>$1</em>!g;

	# Some "markdown": make TODO etc prominent.
	# CSS for .textSymbol has font-family: "Segoe UI Symbol", that font has better looking
	# symbols than most others on a std Windows box.
	# Beetle (lady bug): &#128030;
	# Bug: &#128029;
	# Bug (ugly): &#128027;
	# Ant: &#128028;
	# Note: &#9834;
	# Reminder (a bit of string): &#127895;
	# Check mark: &#10003;
	# Heavy check mark: &#10004;
	# Ballot box with check: &#9745;
	# Wrench: &#128295;
	# OK hand sign: &#128076;
	# Hand pointing right: &#9755;
	# Light bulb: &#128161;
	# Smiling face: &#128578;
	# PEBKAC, ID10T: &#128261;
	
	if (!$doingPOD)
		{
		$$lineR =~ s!(TODO)!<span class='notabene'>\&#127895;$1</span>!;		
		$$lineR =~ s!(REMINDERS?)!<span class='notabene'>\&#127895;$1</span>!;
		$$lineR =~ s!(NOTE)(\W)!<span class='notabene'>$1</span>$2!;
		$$lineR =~ s!(BUGS?)!<span class='textSymbol' style='color: Crimson;'>\&#128029;</span><span class='notabene'>$1</span>!;
		$$lineR =~ s!^\=\>!<span class='textSymbol' style='color: Green;'>\&#9755;</span>!; 			# White is \&#9758; but it's hard to see.
		$$lineR =~ s!^( )+\=\>!$1<span class='textSymbol' style='color: Green;'>\&#9755;</span>!;
		$$lineR =~ s!(IDEA\!)!<span class='textSymbol' style='color: Gold;'>\&#128161;</span>$1!;
		$$lineR =~ s!(FIXED|DONE)!<span class='textSymbolSmall' style='color: Green;'>\&#9745;</span>$1!;
		$$lineR =~ s!(WTF)!<span class='textSymbol' style='color: Chocolate;'>\&#128169;</span>$1!;
		$$lineR =~ s!\:\)!<span class='textSymbol' style='color: DarkGreen;'>\&#128578;</span>!; # or \&#9786;
		# No good, messes up glossary popups: $$lineR =~ s!FLASH!<span class='smallCaps'>FLASH</span>!g;
		}
	}

# Bulleted lists start with space? hyphen hyphen* space? then not-a-hyphen, and then anything goes.
# - two levels are supported
#- an unordered list item begins flush left with a '-', '+', or '*'.
# - optionally you can put one or more spaces at the beginning of the line.
#   -- if you put two or more of '-', '+', or '*', eg '--' or '+++', you'll get a second-level entry.
# To make it prettier in the original text, you can insert spaces at the beginning of the line.
#   A top-level or second-level item can continue in following paragraphs.
# To have the following paragraphs count as part of an item, begin each with one or more tabs or spaces.
# The leading spaces or tabs will be suppressed in the HTML display.
#     ---++** Another second-level item, with excessive spaces.
sub UnorderedList {
	my ($lineR, $unorderedListDepthR, $indentClass, $doingPOD) = @_;
	
	if ($$lineR =~ m!^\s*([-+*][-+*]*)\s+([^-].+)$!)
		{
		my $listSignal = $1;
		# One 'hyphen' is first level, two 'hyphens' is second level.
		if (length($listSignal) == 1)
			{
			$$unorderedListDepthR = 1;
			my $classAttr = ClassAttribute('outdent-unordered', $indentClass);
			$$lineR = "<p$classAttr>" . '&nbsp;&bull; ' . $2 . '</p>'; # &#9830;(diamond) or &bull;
			#$$lineR = '<p class="outdent-unordered">' . '&nbsp;&bull; ' . $2 . '</p>'; # &#9830;(diamond) or &bull;
			}
		else
			{
			$$unorderedListDepthR = 2;
			my $classAttr = ClassAttribute('outdent-unordered-sub', $indentClass);
			$$lineR = "<p$classAttr>" . '&#9702; ' . $2 . '</p>'; # &#9702; circle, &#9830;(diamond) or &bull;
			#$$lineR = '<p class="outdent-unordered-sub">' . '&#9702; ' . $2 . '</p>'; # &#9702; circle, &#9830;(diamond) or &bull;
			}
		}
	elsif ($$unorderedListDepthR > 0 && $$lineR =~ m!^\s+!)
		{
		if ($doingPOD)
			{
			$$lineR =~ s!^ !!; # That's a space
			}
		else
			{
			$$lineR =~ s!^ +!!; # That's a space(s)
			}
		if ($$unorderedListDepthR == 1)
			{
			my $classAttr = ClassAttribute('outdent-unordered-continued', $indentClass);
			$$lineR = "<p$classAttr>" . $$lineR . '</p>';
#			$$lineR = '<p class="outdent-unordered-continued">' . $$lineR . '</p>';
			}
		else
			{
			my $classAttr = ClassAttribute('outdent-unordered-sub-continued', $indentClass);
			$$lineR = "<p$classAttr>" . $$lineR . '</p>';
#			$$lineR = "<p class="outdent-unordered-sub-continued">" . $$lineR . '</p>';
			}
		}
	else
		{
		$$unorderedListDepthR = 0;
		}
	}

# Ordered lists: eg 4. or 4.2 preceded by optional whitespace and followed by at least one space.
# Ordered lists are auto-numbered, provided the following guidelines are followed:
# 1. Two levels, major (2.) and minor (2.4) are supported
# 2. If the first entry in a list starts with a number, that number is used as the
#    starting number for the list.
# 3. '#' can be used as a placeholder, but it's not recommended because if you want to refer
#    to a numbered entry you have to know the number ("see #.# above" can't be filled in for you
#    without AI-level intelligence). In practice, careful numbering by hand is more useful.
# 4. If you use two levels, there should be a single level entry starting off each top-level
#    item, such as the "1." "2." "3." entries in 1., 1.1, 1.2, 2., 2.1, 3., 3.1.
# An item can have more than one paragraph. To signal that a paragraph belongs to a list item,
# begin the paragraph with one or more spaces or tabs. The leading spaces or tabs will be
# suppressed in the resulting HTML.
# Naming: "ol-1-2-c" = ordered list - one digit top level - two digits second - continuation
#  paragraph.
# "ol-2" = ordered list - two digits top level, no second level, first paragraph.
#
# Ordered lists from Pod files start with
# '_OLN_. ' or '_OLN_._OLN_ ' for main or sub items, and numbering starts at 1.
sub OrderedList {
	my ($lineR, $listNumberR, $subListNumberR, $indentClass) = @_;
	
	# A major list item, eg "3.":
	if ($$lineR =~ m!^\s*(\d+|\#)\. +(.+?)$! || $$lineR =~ m!^\s*(_OLN_)\. +(.+?)$!)
		{
		my $suggestedNum = $1;
		my $trailer = $2;
		if ($suggestedNum eq '#' || $suggestedNum eq '_OLN_')
			{
			$suggestedNum = 0;
			}
		if ($$listNumberR == 0 && $suggestedNum > 0)
			{
			$$listNumberR = $suggestedNum;
			}
		else
			{
			++$$listNumberR;
			}
		
		$$subListNumberR = 0;
		my $class = (length($suggestedNum) > 1) ? "ol-2": "ol-1";
		my $classAttr = ClassAttribute($class, $indentClass);
		$$lineR = "<p$classAttr>" . "$$listNumberR. $trailer" . '</p>';
		}
	# A minor entry, eg "3.1":
	elsif ($$lineR =~ m!^\s*(\d+|\#)\.(\d+|\#) +(.+?)$! || $$lineR =~ m!^\s*(_OLN_)\.(_OLN_) +(.+?)$!)
		{
		my $suggestedNum = $1;			# not used
		my $secondSuggestedNum = $2;	# not used
		my $trailer = $3;
		
		++$$subListNumberR;
		if ($$listNumberR <= 0)
			{
			$$listNumberR = 1;
			}
		if (length($$listNumberR) > 1)
			{
			my $class = (length($$subListNumberR) > 1) ? "ol-2-2": "ol-2-1";
			my $classAttr = ClassAttribute($class, $indentClass);
			$$lineR = "<p$classAttr>" . "$$listNumberR.$$subListNumberR $trailer" . '</p>';
			}
		else
			{
			my $class = (length($$subListNumberR) > 1) ? "ol-1-2": "ol-1-1";
			my $classAttr = ClassAttribute($class, $indentClass);
			$$lineR = "<p$classAttr>" . "$$listNumberR.$$subListNumberR $trailer" . '</p>';
			}
		}
	# Line continues an item if we're in one and it starts with one or more tabs or spaces.
	elsif ($$listNumberR > 0 && $$lineR =~ m!^\s+!)
		{
		$$lineR =~ s!^\s+!!;
		if ($$subListNumberR > 0)
			{
			if (length($$listNumberR) > 1)
				{
				my $class = (length($$subListNumberR) > 1) ? "ol-2-2-c": "ol-2-1-c";
				my $classAttr = ClassAttribute($class, $indentClass);
				$$lineR = "<p$classAttr>" . $$lineR . '</p>';
				}
			else
				{
				my $class = (length($$subListNumberR) > 1) ? "ol-1-2-c": "ol-1-1-c";
				my $classAttr = ClassAttribute($class, $indentClass);
				$$lineR = "<p$classAttr>" . $$lineR . '</p>';
				}
			}
		else
			{
			my $class = (length($$listNumberR) > 1) ? "ol-2-c": "ol-1-c";
			my $classAttr = ClassAttribute($class, $indentClass);
			$$lineR = "<p$classAttr>" . $$lineR . '</p>';
			}
		}
	else
		{
		# A blank line or line that doesn't start with a space or tab restarts the auto numbering.
		if ($$lineR =~ m!^\s*$! || $$lineR !~ m!^\s!)
			{
			$$listNumberR = 0;
			$$subListNumberR = 0;
			}
		}	
	}

sub HorizontalRule {
	my ($lineR, $lineNum, $indentClass) = @_;
	
	# <hr> equivalent for three or four === or --- or ~~~
	# If it's === or ====, use a slightly thicker rule.
	my $imageName = ($$lineR =~ m!^\=\=\=\=?!) ? 'mediumrule4.png': 'slimrule4.png';
	my $height = ($imageName eq 'mediumrule4.png') ? 6: 3;
	my $rowID = 'R' . $lineNum;
	my $classAttr = ClassAttribute('vam', $indentClass);
	$$lineR = "<tr id='$rowID'><td n='$lineNum'></td><td$classAttr><img style='display: block;' src='$imageName' width='98%' height='$height' /></td></tr>";
	}

# Convert a <pre> marker line to an image.
sub PreRule {
	my ($lineR, $lineNum, $indentClass) = @_;
	my $imageName = 'slimrule4.png'; # 'slimrule4.png'; 'mediumrule4.png'
	my $height = 3; # 3; 6;
	my $spacer = (index($$lineR, ' ') == 0) ? ' ': '';
	my $pClass = ($spacer eq '') ? "class='ruleHeightPara'": " class='outdent-unordered ruleHeightPara'";
	my $classAttr = " class='vam'";
	my $rowID = 'R' . $lineNum;

	$$lineR = "<tr id='$rowID'><td n='$lineNum'></td><td$classAttr><img style='display: block;' src='$imageName' width='98%' height='$height' /></td></tr>";

#	$$lineR = "$spacer<img class='vam' style='display: block;' src='$imageName' width='98%' height='$height' />";
#	$$lineR = "<p$pClass>$spacer<img class='vam' style='display: block;' src='$imageName' width='98%' height='$height' /></p>";

	}

# Heading(\$lines[$i], \$lines[$i-1], $underline, \@jumpList, $i, \%sectionIdExists);
# Note if doing underlined header then line before will have td etc, but
# if doing # header then the line we're on will be plain text.
# Note line counts as # header only if the #'s are followed by at least one space.
sub Heading {
	my ($lineR, $lineBeforeR, $underline, $jumpListA, $i, $sectionIdExistsH) = @_;

	# Use text of header for anchor id if possible.
	my $isHashedHeader = 0; #  ### header vs underlined header
	my $beforeHeader = '';
	my $headerProper = '';
	my $afterHeader = '';
	my $headerLevel = 0;
	# ### style heading, heading is on $lineR.
	if ($$lineR =~ m!^(#.+)$!)
		{
		$isHashedHeader = 1;
		$beforeHeader = '';
		my $rawHeader = $1;
		$afterHeader = '';
		$rawHeader =~ m!^(#+)!;
		my $hashes = $1;
		$headerLevel = length($hashes);
		if ($i <= 1) # right at the top of the document, assume it's a document title <h1>
			{
			$headerLevel = 1;
			}
		$rawHeader =~ s!^#+\s+!!;
		$headerProper = $rawHeader;
		}
	# Underlined heading, heading is on $lineBeforeR.
	elsif ($$lineBeforeR =~ m!^(<tr id='R\d+'><td[^>]+></td><td>)(.*?)(</td></tr>)$!)
		{
		$beforeHeader = $1;
		$headerProper = $2;
		$afterHeader = $3;
		if (substr($underline,0,1) eq '=')
			{
			$headerLevel = 2;
			}
		elsif (substr($underline,0,1) eq '-')
			{
			$headerLevel = 3;
			}
		elsif (substr($underline,0,1) eq '~')
			{
			$headerLevel = 4;
			}
		if ($i == 1) # right at the top of the document, assume it's a document title <h1>
			{
			$headerLevel = 1;
			}
		}

	# Mark up as an ordinary line and return if no header pattern matched.
	if (!defined($headerProper) || $headerProper eq '')
		{
		++$i; # Convert to 1-based line number.
		my $rowID = 'R' . $i;
		$$lineR = "<tr id='$rowID'><td n='$i'></td><td>" . $$lineR . '</td></tr>';
		return;
		}
	
	my ($jumperHeader, $id) = GetJumperHeaderAndId($headerProper, $jumpListA, $sectionIdExistsH);

	my $contentsClass = 'h' . $headerLevel;
	
	# For ### hash headers we link to $i+1, for underlined link to $i.
	# im-text-ln is short for IntraMine text line.
	# Note $i is 0-based, but im-text-ln is 1-based, so $i refers to line $i-1.
	if ($isHashedHeader)
		{
		++$i; # $i is now a 1-based line number.
		my $rowID = 'R' . $i;
		$$lineR = "<tr id='$rowID'><td n='$i'></td><td>" . "<$contentsClass id=\"$id\">$headerProper</$contentsClass>" . '</td></tr>';
		}
	else
		{
		# Turn the underline into a tiny blank row, make line before look like a header
		$$lineR = "<tr class='shrunkrow'><td></td><td></td></tr>";
		$$lineBeforeR = "$beforeHeader<$contentsClass id=\"$id\">$headerProper</$contentsClass>$afterHeader";
		# Back out any "outdent" wrapper that might have been added, for better alignment.
		if ($jumperHeader =~ m!^<p!)
			{
			$jumperHeader =~ s!^<p[^>]*>!!;
			$jumperHeader =~ s!</p>$!!;
			}
		}
	
	my $jlStart = "<li class='$contentsClass' im-text-ln='$i'><a href='#$id'>";
	my $jlEnd = "</a></li>";
	push @$jumpListA, $jlStart . $jumperHeader . $jlEnd;
	}

# $jumperHeader is $headerProper (orginal header text) with HTML etc removed.
# $id also has unicode etc removed, and is forced to be unique.
sub GetJumperHeaderAndId {
	my ($headerProper, $jumpListA, $sectionIdExistsH) = @_;

	my $id = $headerProper;
	# Remove leading white from header, it looks better.
	$headerProper =~ s!^\s+!!;
	$headerProper =~ s!^&nbsp;!!g;
	# A minor nuisance, we have span, strong, em wrapped around some or all of the header, get rid of that in the id.
	# And thanks to links just being added, also remove <a ...> and </a> and <img ...>.
	# Rev, remove from both TOC entry and id.
	$id =~ s!<[^>]+>!!g;
	$id =~ s!^\s+!!;
	$id =~ s!\s+$!!;
	$id =~ s!\t+! !g;
	my $jumperHeader = $id;				
	$id =~ s!\s+!_!g;
	# File links can have &nbsp; Strip any leading ones, and convert the rest to _.
	$id =~ s!^&nbsp;!!;
	$id =~ s!&nbsp;!_!g;
	$id =~ s!_+$!!;
	# Quotes don't help either.
	$id =~ s!['"]!!g;
	# Remove unicode symbols from $id, especially the ones inserted by markdown above, to make
	# it easier to type the headers in links. Eg 'server swarm.txt#TODO_List' for header '&#127895;TODO List'.
	$id =~ s!\&#\d+;!!g; # eg &#9755;

	if ($id eq '' || defined($sectionIdExistsH->{$id}))
		{
		my $anchorNumber = @$jumpListA;
		$id = "hdr_$anchorNumber";
		}
	$sectionIdExistsH->{$id} = 1;

	return($jumperHeader, $id);
	}

# Heading(\$lines[$i], \$lines[$i-1], $underline, \@jumpList, $i, \%sectionIdExists);
sub xHeading {
	my ($lineR, $lineBeforeR, $underline, $jumpListA, $i, $sectionIdExistsH) = @_;
		
	# Use text of header for anchor id if possible.
	$$lineBeforeR =~ m!^(<tr id='R\d+'><td[^>]+></td><td>)(.*?)(</td></tr>)$!;
	my $beforeHeader = $1;
	my $headerProper = $2;
	my $afterHeader = $3;

	# No heading if the line before has no text.
	if (!defined($headerProper) || $headerProper eq '')
		{
		return;
		}
	
	my $id = $headerProper;
	# Remove leading white from header, it looks better.
	$headerProper =~ s!^\s+!!;
	$headerProper =~ s!^&nbsp;!!g;
	# A minor nuisance, we have span, strong, em wrapped around some or all of the header, get rid of that in the id.
	# And thanks to links just being added, also remove <a ...> and </a> and <img ...>.
	# Rev, remove from both TOC entry and id.
	$id =~ s!<[^>]+>!!g;
	$id =~ s!^\s+!!;
	$id =~ s!\s+$!!;
	$id =~ s!\t+! !g;
	my $jumperHeader = $id;				
	$id =~ s!\s+!_!g;
	# File links can have &nbsp; Strip any leading ones, and convert the rest to _.
	$id =~ s!^&nbsp;!!;
	$id =~ s!&nbsp;!_!g;
	$id =~ s!_+$!!;
	# Quotes don't help either.
	$id =~ s!['"]!!g;
	# Remove unicode symbols from $id, especially the ones inserted by markdown above, to make
	# it easier to type the headers in links. Eg 'server swarm.txt#TODO_List' for header '&#127895;TODO List'.
	$id =~ s!\&#\d+;!!g; # eg &#9755;
	
	if ($id eq '' || defined($sectionIdExistsH->{$id}))
		{
		my $anchorNumber = @$jumpListA;
		$id = "hdr_$anchorNumber";
		}
	$sectionIdExistsH->{$id} = 1;
	
	my $contentsClass = 'h2';
	if (substr($underline,0,1) eq '-')
		{
		$contentsClass = 'h3';
		}
	elsif (substr($underline,0,1) eq '~')
		{
		$contentsClass = 'h4';
		}
	if ($i == 1) # right at the top of the document, assume it's a document title <h1>
		{
		$contentsClass = 'h1';
		}
	
	# im-text-ln='$i' rather than $lineNum=$i+1, because we're on the
	# underline here and want to record the heading line number on the line before.
	my $jlStart = "<li class='$contentsClass' im-text-ln='$i'><a href='#$id'>";
	my $jlEnd = "</a></li>";

	# Turn the underline into a tiny blank row, make line before look like a header
	$$lineR = "<tr class='shrunkrow'><td></td><td></td></tr>";
	$$lineBeforeR = "$beforeHeader<$contentsClass id=\"$id\">$headerProper</$contentsClass>$afterHeader";
	# Back out any "outdent" wrapper that might have been added, for better alignment.
	if ($jumperHeader =~ m!^<p!)
		{
		$jumperHeader =~ s!^<p[^>]*>!!;
		$jumperHeader =~ s!</p>$!!;
		}
	push @$jumpListA, $jlStart . $jumperHeader . $jlEnd;
	}

# Turn anchor eg
# _ALB_C<code> -- code text    _ARB__ALP_id=C%3Ccode%3E_--_code_text_ARP_
# into a real anchor <a id='C%3Ccode%3E_--_code_text'>C<code> -- code text    </a>
# Anchor requires all four of _ALB_ _ARB_ _ALP_ _ARP_
# and also the 'id=' just after _ALP_.
# This is mainly for POD files, but you can your own to a .txt
# file, eg _ALB_Text for anchor_ARB__ALP_id=uniqueid_ARP_
#  - just be aware there is no checking that the id
# is unique.
sub Anchor {
	my ($lineR) = @_;

	my $anchorStartPosition = 0;
	while (($anchorStartPosition = index($$lineR, '_ALB_')) >= 0)
		{
		my $leftIdx = $anchorStartPosition;
		# Extract text.
		my $startRepPosition = $leftIdx;
		$leftIdx += length('_ALB_');
		my $rightIdx = index($$lineR, '_ARB_');
		if ($rightIdx < 0)
			{
			return;
			}
		my $displayedText = substr($$lineR, $leftIdx, $rightIdx - $leftIdx);

		# Extract id.
		$leftIdx = index($$lineR, '_ALP_');
		if ($leftIdx < 0)
			{
			return;
			}
		$leftIdx += length('_ALP_');
		my $idIndex = index($$lineR, 'id=', $leftIdx);
		if ($idIndex != $leftIdx) # No 'id=', no link. Abort the whole process here.
			{
			return;
			}
		$leftIdx += 3; # Skip 'id='
		$rightIdx = index($$lineR, '_ARP_');
		if ($rightIdx < 0)
			{
			return;
			}
		my $endRepPosition = $rightIdx + length('_ARP_');
		my $id = substr($$lineR, $leftIdx, $rightIdx - $leftIdx);

		my $anchor = "<a id='$id'>$displayedText</a>";

		$$lineR = substr($$lineR, 0, $startRepPosition) . $anchor . substr($$lineR, $endRepPosition);
		}
	}

# Where a line begins with TABLE, convert lines following TABLE that contain tab(s) into an HTML table.
# We have already put in line numbers and <tr> with <td> for the line numbers and contents proper, see just above.
# A table begins with TABLE followed by optional text, provided the first character in the optional text
# is one of space tab underscore colon period hyphen. The following line must also
# contain at least one tab. The table continues for all following lines containing at least one tab.
## Cells are separated by one or more tabs. Anything else, even a space, counts as cell content. ##
# The opening TABLE is suppressed. Text after TABLE is used as the caption.
# If TABLE is the only text on the line, the line is made shorter in height.
# Now, the whole body of a document is in a single table with
# each row having cells for line number and actual content. For a TABLE, the
# body table is ended with </table>, our special TABLE is put in, and then a regular
# body table is started up again with <table> afterwards. The overall <table> and </table>
# wrappers for the body are done at the end of GetPrettyTextContents().
# For the TABLE line: end previous (body) table, start new table, remove TABLE from line and also line number
# if there is no text following TABLE, and give the row class='shrunkrow' (in the table being ended).
# But if TABLE is followed by text on the same line, display the line, including the line number.
# Any following text becomes the table caption (TABLE is always removed from the text).
# Subsequent lines: first table row is <th> except for the line number which is <td>. Every table
# row starts with a line number, so there is one extra column in each row for that.
# At table end, tack on </table><table> to revert back to the regular document body table.
# In content rows, if there are too many cells then the rightmost will be combined into one
# And if there are too few, colspan will extend the last cell.
# To "skip" a column, put an unobtrusive character such as space or period for its content (it will be centered up)
# Any character that's not a tab counts as content for a cell.
# If a cell starts with <\d+> it's treated as a colspan request. The last cell doesn't need a
# <N> to span the remaining columns.
# If a cell starts with <L> or <R> or <C>, text in the cell is aligned left or right or center.
# Colspan and alignment can be combined, eg <C3>.
# See Gloss.txt for examples.
sub PutTablesInText {
	my ($lines_A) = @_;
	my $numLines = @$lines_A;
	my %alignmentString;
	$alignmentString{'L'} = " class='left_cell'";
	$alignmentString{'R'} = " class='right_cell'";
	$alignmentString{'C'} = " class='centered_cell'";
	
	for (my $i = 0; $i <$numLines; ++$i)
		{
		if ( $lines_A->[$i] =~ m!^<tr id='R\d+'><td[^>]+></td><td>TABLE(</td>|[_ \t:.-])! 
		  && $i <$numLines-1 && $lines_A->[$i+1] =~ m!\t! )
			{
			my $numColumns = 0;
			my $tableStartIdx = $i;
			my $idx = $i + 1;
			my $startIdx = $idx;
			
			# Preliminary pass, determine the maximum number of columns. Rather than check all the
			# rows, assume a full set of columns will be found on the first or second row, and
			# no colspans. Ok, four rows. Otherwise madness reigns.
			my @cellMaximumChars;
			
			GetMaxColumns($idx, $numLines, $lines_A, \$numColumns, \@cellMaximumChars);
						
			# Start the table, with optional title.
			StartNewTable($lines_A, $tableStartIdx, \@cellMaximumChars, $numColumns);

			# Main pass, make the table rows.
			$idx = $startIdx;
			$idx = DoTableRows($idx, $numLines, $lines_A, $numColumns, \%alignmentString);;

			# Stop/start table on the last line matched.
			# No start of new table if we're at the bottom.
			if ($idx == $numLines)
				{
				$lines_A->[$idx-1] = $lines_A->[$idx-1] . '</tbody></table>';
				}
			else
				{
				$lines_A->[$idx-1] = $lines_A->[$idx-1] . '</tbody></table><table><tbody>';
				}
			} # if TABLE
		} # for (my $i = 0; $i <$numLines; ++$i)
	}

# Check first few rows, determine maximum number of columns and length of each cell.
sub GetMaxColumns {
	my ($idx, $numLines, $lines_A, $numColumnsR, $cellMaximumChars_A) = @_;
	
	my $rowsChecked = 0;
	while ($idx < $numLines && $lines_A->[$idx] =~ m!\t! && ++$rowsChecked <= 4)
		{
		$lines_A->[$idx] =~ m!^<tr id='R\d+'><td\s+n\=['"](\d+)['"]></td><td>(.+?)</td></tr>!;
		my $content = $2;
		my @contentFields = split(/\t+/, $content);
		my $currentNumColumns = @contentFields;
		if ($$numColumnsR < $currentNumColumns)
			{
			$$numColumnsR = $currentNumColumns;
			}
		for (my $j = 0; $j < $currentNumColumns; ++$j)
			{
			if ( !defined($cellMaximumChars_A->[$j])
				|| length($cellMaximumChars_A->[$j]) < length($contentFields[$j]) )
				{
				$cellMaximumChars_A->[$j] = length($contentFields[$j]);
				}
			}
		
		++$idx;				
		}
	}

sub StartNewTable {
	my ($lines_A, $tableStartIdx, $cellMaximumChars_A, $numColumns) = @_;

	if ($lines_A->[$tableStartIdx] =~ m!TABLE[_ \t:.-]\S!)
		{
		# Use supplied text after TABLE as table "caption".
		if ($lines_A->[$tableStartIdx] =~ m!^(<tr id='R\d+'><td[^>]+></td><td>)TABLE[_ \t:.-](.+?)(</td></tr>)!)
			{
			# Arg, caption can be no wider than the table, disregarding the caption. ?!?!?
			# So we'll just use text above the table if the caption is too long.
			#$lines_A->[$i] = "$1$3</table><table class='bordered'><caption>$2</caption>";
			my $pre = $1;
			my $caption = $2;
			my $post = $3;
			# If the caption will be roughly no wider than the resulting table,
			# use a caption. But if the caption will be smaller than the table,
			# just use slightly indented text. An empty line has
			# about 36 characters, the rest is the caption. Less 6 for "TABLE ".
			# A table row will be as wide as needed for the widest cell in each column,
			# and count the width of one character between columns.
			my $captionChars = length($caption);
			my $longestLineChars = 0;
			for (my $j = 0; $j < @$cellMaximumChars_A; ++$j)
				{
				$longestLineChars += $cellMaximumChars_A->[$j];
				}
			$longestLineChars += $numColumns - 1;
			if ($captionChars < $longestLineChars)
				{
				$lines_A->[$tableStartIdx] = "$pre$post</tbody></table><table class='bordered'><caption>$caption</caption><thead>";
				}
			else
				{
				$lines_A->[$tableStartIdx] = "$pre&nbsp; &nbsp;&nbsp; &nbsp;&nbsp;<span class='fakeCaption'>$caption</span>$post</tbody></table><table class='bordered'><thead>";
				}
			}
		else
			{
			# Probably a maintenance failure. Struggle on.
			$lines_A->[$tableStartIdx] = "<tr class='shrunkrow'><td></td><td></td></tr></tbody></table><table class='bordered'><thead>";
			}
		}
	else # no caption
		{
		$lines_A->[$tableStartIdx] = "<tr class='shrunkrow'><td></td><td></td></tr></tbody></table><table class='bordered'><thead>";
		}			
	}

sub DoTableRows {
	my ($idx, $numLines, $lines_A, $numColumns, $alignmentString_H) = @_;

	my $isFirstTableContentLine = 2; # Allow up to two headers rows up top.
	while ($idx < $numLines && $lines_A->[$idx] =~ m!\t!)
		{
		# Grab line number and content.
		$lines_A->[$idx] =~ m!^<tr id='R\d+'><td\s+n\=['"](\d+)['"]></td><td>(.+?)</td></tr>!;
		my $lineNum = $1;
		my $content = $2;
		
		# Break content into cells. Separator is one or more tabs.
		my @contentFields = split(/\t+/, $content);
		my $currentNumColumns = @contentFields;
		
		# Determine the colspan of each field. If the field starts with <[LRC]?N> where N
		# is an integer, use that as the colspan. If we're at the last field
		# and don't have enough columns yet, add them to the last field.
		my $numColumnsIncludingSpans = 0;
		my @colSpanForFields;
		my @alignmentForFields;
		my $lastUsableFieldIndex = -1;
		
		for (my $j = 0; $j < $currentNumColumns; ++$j)
			{
			my $requestedColSpan = 0;
			my $alignment = '';
			# Look for <[LRC]\d+> at start of cell text. Eg <R>, <C3>, <4>.
			if ($contentFields[$j] =~ m!^(\&#60;|\&lt\;|\<)([LRClrc]?\d+|[LRClrc])(\&#62;|\&gt\;|\>)!)
				{
				my $alignSpan = $2;
				if ($alignSpan =~ m!(\d+)!)
					{
					$requestedColSpan = $1;
					if ($requestedColSpan <= 1)
						{
						$requestedColSpan = 0;
						}
					}
				if ($alignSpan =~ m!([LRClrc])!)
					{
					$alignment = uc($1);
					}
				}
			push @colSpanForFields, $requestedColSpan;
			push @alignmentForFields, $alignment;
			$numColumnsIncludingSpans += ($requestedColSpan > 0) ? $requestedColSpan: 1;
			
			# Ignore <N> if max columns has been hit. Note when it happens.
			if ($numColumnsIncludingSpans >= $numColumns)
				{
				$lastUsableFieldIndex = $j unless ($lastUsableFieldIndex >= 0);
				$colSpanForFields[$j] = 0;
				}
			
			if ($j == $currentNumColumns - 1) # last entry
				{
				if ($lastUsableFieldIndex < 0)
					{
					$lastUsableFieldIndex = $currentNumColumns - 1;
					}
				
				if ($numColumnsIncludingSpans < $numColumns)
					{
					$colSpanForFields[$j] = $numColumns - $numColumnsIncludingSpans + 1;
					}
				# Note $numColumnsIncludingSpans > $numColumns shouldn't happen
				}
			
			# Remove the colspan hint <N> from field.
			$contentFields[$j] =~ s!^(\&#60;|\&lt\;|\<)([LRClrc]?\d+|[LRClrc])(\&#62;|\&gt\;|\>)!!;
			}

		my $cellName = ($isFirstTableContentLine) ? 'th' : 'td';
		my $newLine;

		# A line with nothing but spaces for content will be shrunk vertically.
		if ($content =~ m!^\s+$!)
			{
			$newLine = "<tr class='reallyshrunkrow'><td></td>";
			$newLine .= "<td></td>"x$numColumns;
			$newLine .= "</tr>";
			}
		else
			{
			# Leftmost cell is for line number.
			my $rowID = 'R' . $lineNum;
			$newLine = "<tr id='$rowID'><$cellName n='$lineNum'></$cellName>";
			for (my $j = 0; $j <= $lastUsableFieldIndex; ++$j)
				{
				# A single non-word char such as a space or period is taken as a signal for
				# an empty cell. Just centre it up, which makes it less obtrusive.
				if ($contentFields[$j] =~ m!^\W$!)
					{
					$newLine = $newLine . "<$cellName class='centered_cell'>$contentFields[$j]</$cellName>";
					}
				else
					{
					# Leading spaces are typically for numeric alignment and should be preserved.
					# We'll adjust for up to six spaces at the start of cell contents, replacing every
					# second space with a non-breaking space, starting with the first space.
					if (index($contentFields[$j], ' ') == 0)
						{
						$contentFields[$j] =~ s!^     !&nbsp; &nbsp; &nbsp;!; 	# five spaces there
						$contentFields[$j] =~ s!^   !&nbsp; &nbsp;!;			# three spaces
						$contentFields[$j] =~ s!^ !&nbsp;!;						# one space
						}
						
					my $colspanStr = '';
					if (defined($colSpanForFields[$j]) && $colSpanForFields[$j] > 1)
						{
						$colspanStr = " colspan='$colSpanForFields[$j]'";
						}

					my $alignStr = '';
					if (defined($alignmentForFields[$j]) && $alignmentForFields[$j] ne '')
						{
						$alignStr = $alignmentString_H->{$alignmentForFields[$j]};
						}
						
					# Center up multi-column text by default.
					if ($colspanStr ne '' && $alignmentForFields[$j] eq '')
						{
						$alignStr = $alignmentString_H->{'C'};
						}

					$newLine = $newLine . "<$cellName$colspanStr$alignStr>$contentFields[$j]</$cellName>";
					}
				}
			}
		$newLine = $newLine . '</tr>';
		
		$lines_A->[$idx] = $newLine;
		
		# To allow for grouping headers above the headers proper, don't cancel
		# $isFirstTableContentLine until a full set of column entries is seen, or we've
		# seen two rows (there have to be limits).
		if ($isFirstTableContentLine > 0)
			{
			--$isFirstTableContentLine;
			
			if ($currentNumColumns == $numColumns && $isFirstTableContentLine > 0)
				{
				$isFirstTableContentLine = 0;
				}
			
			# Terminate thead and start tbody at end of header row(s).
			if ($isFirstTableContentLine == 0)
				{
				$lines_A->[$idx] .= '</thead><tbody>';
				}
			}
			
		++$idx;
		}
		
	return($idx);
	}

# Get text file as a big string. Returns 1 if successful, 0 on failure.
sub LoadTextFileContents {
	my ($filePath, $contentsR, $octetsR) = @_;
	
	$$octetsR = ReadTextFileWide($filePath);
	if (!defined($$octetsR))
		{
		$$contentsR .= "Error, could not open $filePath.";
		return(0);
		}
	my $decoder = Encode::Guess->guess($$octetsR);
	
	my $eightyeightFired = 0;
	if (ref($decoder))
		{
		my $decoderName = $decoder->name();
		if ($decoderName =~ m!iso-8859-\d+!)
			{
			$$octetsR = $decoder->decode($$octetsR);
			$eightyeightFired = 1;
			}
		}
	
	if (!$eightyeightFired)
		{
		$$octetsR = decode_utf8($$octetsR);
		}
	
	return(1);
	}

sub LoadPerlFileContents {
	my ($filePath, $contentsR, $octetsR) = @_;
	
	$$octetsR = ReadTextFileWide($filePath);
	if (!defined($$octetsR))
		{
		$$contentsR .= "Error, could not open $filePath.";
		return(0);
		}
	my $decoder = Encode::Guess->guess($$octetsR);
	
	my $eightyeightFired = 0;
	if (ref($decoder))
		{
		my $decoderName = $decoder->name();
		if ($decoderName =~ m!iso-8859-\d+!)
			{
			$$octetsR = $decoder->decode($$octetsR);
			$eightyeightFired = 1;
			}
		}
		
	# TEST ONLY codathon
#	print("Perl highlighting...");
#	my $t1 = time;
	my $formatter = GetPerlHighlighter();
	$$octetsR = $formatter->format_string($$octetsR);
#	my $elapsed = time - $t1;
#	my $ruffElapsed = substr($elapsed, 0, 6);
#	print(" $ruffElapsed seconds\n");

	if (!$eightyeightFired)
		{
		$$octetsR = decode_utf8($$octetsR);
		}
		
	return(1);
	}

# Called by GetPrettyPOD().
# Load the file, then convert to HTML using Pod::Simple::HTML.
sub LoadPodFileContents {
	my ($filePath, $octetsR) = @_;

	my $contents = ReadTextFileDecodedWide($filePath, 1);

	# Stick in =pod if first line is =heading NAME
	if ($contents =~ m!^\=head1 NAME!)
		{
		$contents = "=pod\n\n" . $contents;
		}

    # Some repair is needed before parsing it seems.
	# Comments 
    # Specifically, two consecutive headings can mess things up.
    # Headings start with ^=headN where N is a digit.
    my @lines = split(/\n/, $contents);
	my $numLines =  @lines;
    my $consecutiveHeadingCount = 0;
    my @fixedLines;

    for (my $i = 1; $i < $numLines; ++$i)
        {
        if (index($lines[$i], "=head") == 0
          && $lines[$i] =~ m!^\=head\d!)
            {
            ++$consecutiveHeadingCount;
            if ($consecutiveHeadingCount == 2)
                {
                --$consecutiveHeadingCount;
                push @fixedLines, '';
                push @fixedLines, $lines[$i];
                }
            else
                {
                push @fixedLines, $lines[$i];
                }
            }
        else
            {
            $consecutiveHeadingCount = 0;
            push @fixedLines, $lines[$i];
            }
        }

    $contents = join("\n", @fixedLines);

	my $p = Pod::Simple::HTML->new;

	$p->no_whining(1);
	$p->parse_characters(1);
	#$p->html_h_level(2);
	my $html;
	$p->output_string(\$html);
	$p->parse_string_document($contents);

	# Strip off the top and bottom, we just want  after "<!-- start doc -->"
	# down to before "<!-- end doc -->"
	my $startDoc = "<!-- start doc -->";
	my $idx = index($html, "<!-- start doc -->");
	if ($idx > 0)
		{
		my $skipStartLength = length($startDoc);
		$html = substr($html, $idx + $skipStartLength);
		}
	$idx = index($html, "<!-- end doc -->");
	if ($idx > 0)
		{
		$html = substr($html, 0, $idx);
		}

	# Strip any '___top' anchor, not needed.
	my $topAnchor = "<a name='___top' class='dummyTopAnchor' ></a>";
	$idx = index($html, $topAnchor);
	if ($idx >= 0)
		{
		my $skipLength = length($topAnchor);
		$html = substr($html, $idx + $skipLength);
		}

	# And strip comments, easier to do it here than in html2gloss.pm
	$html =~ s!<\!--.*?-->!!gs;

	# TEST ONLY
	# Write out what we have so far.
	#WriteTextFileWide("C:/perlprogs/IntraMine/test/test_pod_4_html.txt", $html);

	$$octetsR = $html;

	return(1);
	}

{ ##### Special handling for contents.txt table of CONTENTS files
my $IndexGetsSpecialTreatment;
my $SpecialIndexFileName;
my $ContentTriggerWord;
my $SpecialIndexFont;
my $SpecialIndexFlourishImage;
my $FlourishImageHeight;

sub InitSpecialIndexFileHandling {
	$IndexGetsSpecialTreatment = CVal('INDEX_GETS_SPECIAL_TREATMENT');
	$SpecialIndexFileName = CVal('SPECIAL_INDEX_NAME');
	$ContentTriggerWord = CVal('SPECIAL_INDEX_EARLY_TEXT_MUST_CONTAIN');
	$SpecialIndexFont = CVal('SPECIAL_INDEX_FONT');
	$SpecialIndexFlourishImage = CVal('SPECIAL_INDEX_FLOURISH');
	$FlourishImageHeight = CVal('SPECIAL_INDEX_FLOURISH_HEIGHT');
	}

sub IsSpecialIndexFile {
	my ($filePath, $lines_A) = @_;
	my $result = 0;
	
	if ($IndexGetsSpecialTreatment)
		{
		if ($filePath =~ m!$SpecialIndexFileName$!i)
			{
			my $numLines = @$lines_A;
			if ($numLines && $lines_A->[0] =~ m!$ContentTriggerWord!i
				&& $numLines <= 100 )
				{
				$result = 1;
				}
			}
		}
	
	return($result);
	}
	
sub MakeSpecialIndexFileLookSpecial {
	my ($lines_A) = @_;
	
	my $numLines = @$lines_A;
	if ($numLines)
		{
		my $flourishImageLink = GetFlourishImageLink();
		$lines_A->[0] =~ s!(<td>)(.*?$ContentTriggerWord.*?)(</td>)!<th align='center'><span id='toc-line'>$2</span>$flourishImageLink</th>!i;
		}
	}

sub GetFlourishImageLink {
	my $result = '';
	if (FileOrDirExistsWide($IMAGES_DIR . $SpecialIndexFlourishImage) == 1)
		{
		my $imagePath = $IMAGES_DIR . $SpecialIndexFlourishImage;
		$result = "<img id='flourish-image' src='$SpecialIndexFlourishImage' width='100%' height='$FlourishImageHeight'>";
		}
	
	return($result);
	}
} ##### Special handling for contents.txt table of CONTENTS files

# Table of contents for a .go file. Structs and functions.
sub GetGoTOC {
	my ($txtR, $tocR) = @_;
	my @lines = split(/\n/, $$txtR);
	my @classList;
	my @classNames;
	my @methodList;
	my @methodNames;
	my %idExists; # used to avoid duplicated anchor id's.

	my $numLines = @lines;
	my $lineNum = 1;
	for (my $i = 0; $i < $numLines; ++$i)
		{
		# Put structs in jumplist.
		# type parser struct {
		if ($lines[$i] =~ m!^\s*type\s*(\w+)\s*struct! )
			{
			my $className = $1;
			my $contentsClass = 'h2';
			my $id = $className;
			$id =~ s!\s+!_!g;
			$id = UniqueTocID($id, \%idExists);
			my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			my $jlEnd = "</a></li>";
			push @classList, $jlStart . $S_icon . $className . $jlEnd;
			push @classNames, $className;
			}
		# and functions:
		# func (p *parser) init(
		# func trace(
		elsif ( $lines[$i] =~ m!^\s*func\s+\([^)]+\)\s*(\w+)\s*\(!
			||  $lines[$i] =~ m!^\s*func\s+(\w+)\s*\(! )
			{
			my $rawName = $1;
			# Avoid keywords
			if ($rawName !~ m!^(if|do|for|while|else|elsif|switch)$!)
				{
				my $methodName = $rawName;
				my $contentsClass = 'h2';
				my $id = $methodName;
				$id =~ s!\s+!_!g;
				$id = UniqueTocID($id, \%idExists);
				my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
				my $jlEnd = "</a></li>";
				push @methodList, $jlStart . $f_icon . $methodName . '()' . $jlEnd;
				push @methodNames, $methodName;
				}
			}
		
		++$lineNum;
		}
	
	my @idx = sort { $classNames[$a] cmp $classNames[$b] } 0 .. $#classNames;
	@classList = @classList[@idx];
	@idx = sort { $methodNames[$a] cmp $methodNames[$b] } 0 .. $#methodNames;
	@methodList = @methodList[@idx];
	my $numClassListEntries = @classList;
	my $classBreak = ($numClassListEntries > 0) ? '<br>': '';
	$$tocR = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n" . join("\n", @classList) . $classBreak . join("\n", @methodList) . "</ul>\n";
	}

# Table of contents for a Fortan file. Types, and procedures (subroutines and functions).
sub GetFortranTOC {
	my ($txtR, $tocR) = @_;
	my @lines = split(/\n/, $$txtR);
	my @classList;
	my @classNames;
	my @methodList;
	my @methodNames;
	my %idExists; # used to avoid duplicated anchor id's.
	
	my $numLines = @lines;
	my $lineNum = 1;
	for (my $i = 0; $i < $numLines; ++$i)
		{
		if ( $lines[$i] =~ m!^[^\!]*?type\s+(\w+)!i
		  || $lines[$i] =~ m!^[^\!]*?type\s*,[^\:]+\:\:\s+(\w+)!i)
			{
			if ($lines[$i] !~ m!end\s+type!)
				{
				$lines[$i] =~ m!type\s+(\w+)!i;
				my $className = $1; # Really should be $typeName, sorry
				my $contentsClass = 'h2';
				my $id = $className;
				$id =~ s!\s+!_!g;
				$id = UniqueTocID($id, \%idExists);
				my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
				my $jlEnd = "</a></li>";
				push @classList, $jlStart . $T_icon . $className . $jlEnd;
				push @classNames, $className;
				}
			}
		elsif ($lines[$i] =~ m!^[^\!]*?(function|subroutine)\s+(\w+)!i)
			{
			if ($lines[$i] !~ m!end\s+(function|subroutine)!)
				{
				$lines[$i] =~ m!(function|subroutine)\s+(\w+)!;
				my $callType = lc($1);
				my $methodName = $2; # Really should be $procedureName, sorry
				my $contentsClass = 'h2';
				my $id = $methodName;
				$id =~ s!\s+!_!g;
				$id = UniqueTocID($id, \%idExists);
				my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
				my $jlEnd = "</a></li>";
				my $icon = ($callType eq 'function') ? $f_icon : $s_icon;
				push @methodList, $jlStart . $icon . $methodName . '()' . $jlEnd;
				push @methodNames, $methodName;
				}
			}
		++$lineNum;
		}
		
	my @idx = sort { $classNames[$a] cmp $classNames[$b] } 0 .. $#classNames;
	@classList = @classList[@idx];
	@idx = sort { $methodNames[$a] cmp $methodNames[$b] } 0 .. $#methodNames;
	@methodList = @methodList[@idx];
	my $numClassListEntries = @classList;
	my $classBreak = ($numClassListEntries > 0) ? '<br>': '';
	$$tocR = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n" . join("\n", @classList) . $classBreak . join("\n", @methodList) . "</ul>\n";
	}

# COBOL table of contents entries. Divisions, sections, procedures, records, file descriptors.
sub GetCOBOLTOC {
	my ($txtR, $tocR) = @_;
	$$tocR = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n";
	my @lines = split(/\n/, $$txtR);
	my $numLines = @lines;
	my $numCalls = 0;
	my %idExists; # used to avoid duplicated anchor id's.

	for (my $i = 0; $i < $numLines; ++$i)
		{
		if ($lines[$i] =~ m!^(\d{6}.)?\s*identification\s+division!i)
			{
			++$numCalls;

			# Look ahead a bit to see if we're dealing with Object Oriented COBOL
			my $isOOCOBOL = 0;
			my $lookAheadLimit = $i + 10;
			if ($lookAheadLimit > $numLines)
				{
				$lookAheadLimit = $numLines;
				}
			for (my $j = $i + 1; $j < $lookAheadLimit; ++$j)
				{
				if ($lines[$j] =~ m!^(\d{6}.)?\s*class-id[.\s]*([a-zA-Z0-9-]+)!i)
					{
					$isOOCOBOL = 1;
					$i = $j;
					last;
					}
				}

			if ($isOOCOBOL)
				{
				$i = getOneOOCOBOLTOC(\@lines, $numLines, $i, $numCalls, \%idExists, $tocR);
				}
			else
				{
				$i = GetOneProgramCOBOLTOC(\@lines, $numLines, $i, $numCalls, \%idExists, $tocR);
				}
			}
		else # not id, look for class-id only
			{
			if ($lines[$i] =~ m!^(\d{6}.)?\s*class-id[.\s]*([a-zA-Z0-9-]+)!i)
				{
				$i = getOneOOCOBOLTOC(\@lines, $numLines, $i, $numCalls, \%idExists, $tocR);
				}
			}
		}

	$$tocR .= "</ul>\n";
	}

sub GetOneProgramCOBOLTOC {
	my ($lines_A, $numLines, $i, $numCalls, $idExists_H, $tocR) = @_;
	my $identificationCounter = 0;
	if ($lines_A->[$i] !~ m!^(\d{6}.)?\s*identification\s+division!i)
		{
		return($numLines);
		}

	my @classList;
	my @classNames;
	my @methodList;
	my @methodNames;

	my %sortLetterForDivision;
	$sortLetterForDivision{'IDENTIFICATION'} = 'A ';
	$sortLetterForDivision{'ENVIRONMENT'} = 'B ';
	$sortLetterForDivision{'DATA'} = 'C ';
	$sortLetterForDivision{'PROCEDURE'} = 'D ';
	
	my $divisionName = '';
	my $divisionNameUC = ''; 	# Uppercase division name
	#my $sectionName = '';
	my $sectionNameUC = '';
	my $inDeclaratives = 0; 	# DECLARATIVES in PROCEDURE division, skip
	my %varNames; 				# Remember variable names from WORKING-STORAGE etc
	my %topLevelVars;			# Variables displayed in the TOC under DATA
	my $topLevelIndentLength = -1; # Pick up only record names with the least indent, based on first seen.
	for (; $i < $numLines; ++$i)
		{
		my $lineNum = $i + 1;
		# DIVISION
		if ($lines_A->[$i] =~ m!^(\d{6}.)?\s*([a-zA-Z0-9-]+)\s+division!i)
			{
			my $className = defined($2) ? $2 : $1; # Really should be $divisionName, sorry
			$divisionName = $className;
			$divisionNameUC = uc($divisionName);

			# Move on to next subprogram if we see a second IDENTIFICATION DIVISION
			if ($divisionNameUC eq 'IDENTIFICATION')
				{
				++$identificationCounter;
				if ($identificationCounter >= 2)
					{
					last;
					}
				}
			my $contentsClass = 'h2';
			my $id = $className;
			$id =~ s!\s+!_!g;
			$id = UniqueTocID($id, $idExists_H);
			my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			my $jlEnd = "</a></li>";
			push @classList, $jlStart . $divisionNameUC . $jlEnd;
			my $sortLetter = defined($sortLetterForDivision{$divisionNameUC}) ? $sortLetterForDivision{$divisionNameUC}: 'Z';
			push @classNames, $sortLetter . uc($className);
			}
		# PROGRAM-ID in IDENTIFICATION division
		elsif ($lines_A->[$i] =~ m!^(\d{6}.)?\s*program-id\.?\s+([a-zA-Z0-9-]+)!i)
			{
			my $programID = defined($2) ? $2 : $1;
			# Use "PROGRAM-ID $programID" as a section name under current division (identification)
			my $className = $divisionNameUC . ' ' . "PROGRAM-ID " . $programID;
			my $contentsClass = 'h3';
			my $id = $className;
			$id =~ s!\s+!_!g;
			$id = UniqueTocID($id, $idExists_H);
			my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			my $jlEnd = "</a></li>";
			push @classList, $jlStart . "PROGRAM-ID " . $programID . $jlEnd;
			#push @classList, $jlStart . $className . $jlEnd;
			my $sortLetter = defined($sortLetterForDivision{$divisionNameUC}) ? $sortLetterForDivision{$divisionNameUC}: 'Z';
			push @classNames, $sortLetter . uc($className);
			}
		# SECTION
		elsif ($divisionNameUC ne 'PROCEDURE' && $lines_A->[$i] =~ m!^(\d{6}.)?\s*([a-zA-Z0-9-]+)\s+section!i)
			{
			my $sectionName = defined($2) ? $2 : $1;
			$sectionNameUC = uc($sectionName);
			# Use division-section as the name.
			my $className = $divisionNameUC . ' ' . $sectionName;
			my $contentsClass = 'h3';
			my $id = $className;
			$id =~ s!\s+!_!g;
			$id = UniqueTocID($id, $idExists_H);
			my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			my $jlEnd = "</a></li>";
			push @classList, $jlStart . $S_icon . $sectionName . $jlEnd;
			#push @classList, $jlStart . $className . $jlEnd;
			my $sortLetter = defined($sortLetterForDivision{$divisionNameUC}) ? $sortLetterForDivision{$divisionNameUC}: 'Z';
			push @classNames, $sortLetter .uc($className);
			}
		# DATA variables and records (top level only)
		elsif ( $divisionNameUC eq 'DATA'
			 && $lines_A->[$i] =~ m!^(\d{6}.)?\s*([a-zA-Z0-9-]+)\s+([a-zA-Z0-9-]+)!)
			{
			my $varName = defined($3) ? $3 : $2;
			my $prefix = defined($3) ? $2 : $1; # Eg "01" or "FD"
			if (!defined($2)) # Shouldn't happen with compilable code
				{
				$varName = $1;
				$prefix = '';
				}
			$varNames{$varName} += 1;

			if ($prefix !~ m!^\d+$! && $prefix !~ m!^[a-zA-Z][a-zA-Z]$!)
				{
				++$lineNum; # This is why I don't like doing "next;"
				next;
				}

			# Pick up top level vars. This is mainly done by matching the indentation
			# level of the first variable seen in all subsequent matches (except 01 vars).
			$lines_A->[$i] =~ m!^((\d{6}.)?\s*)!;
			my $indent = $1;
			my $indentLength = length($indent);
			if ($topLevelIndentLength < 0)
				{
				$topLevelIndentLength = $indentLength;
				}
			if ($topLevelIndentLength >= 0)
				{
				if ($indentLength == $topLevelIndentLength ||
					$prefix eq "01" || $prefix eq "1" || $prefix eq "77")
					{
					my $className = $divisionNameUC . ' ' . $sectionNameUC . ' ' . $varName;
					my $contentsClass = 'h4';
					my $id = $className;
					$id =~ s!\s+!_!g;
					$id = UniqueTocID($id, $idExists_H);
					my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
					my $jlEnd = "</a></li>";
					push @classList, $jlStart . $D_icon . $varName . $jlEnd;
					#push @classList, $jlStart . $className . $jlEnd;
					my $sortLetter = defined($sortLetterForDivision{$divisionNameUC}) ? $sortLetterForDivision{$divisionNameUC}: 'Z';
					push @classNames, $sortLetter . uc($className);
					}
				}
			}
		# Procedures
		elsif ($divisionNameUC eq 'PROCEDURE') # procedure division, procedure
			{
			if ($lines_A->[$i] =~ m!DECLARATIVES!i)
				{
				if ($lines_A->[$i] =~ m!END\s+DECLARATIVES!i)
					{
					$inDeclaratives = 0;
					}
				else
					{
					$inDeclaratives = 1;
					}
				}
			
			if ( !$inDeclaratives
			  && ( $lines_A->[$i] =~ m!^(\d{6}.)?\s*([a-zA-Z0-9-]+)\.?\s*$!
			    || $lines_A->[$i] =~ m!^(\d{6}.)?\s*([a-zA-Z0-9-]+)\s+SECTION!i))
				{
				my $methodName = defined($2) ? $2 : $1;
				if (!isCobolKeyWord($methodName) && !defined($varNames{$methodName}))
					{
					my $contentsClass = 'h3';
					my $id = $methodName;
					$id =~ s!\s+!_!g;
					$id = UniqueTocID($id, $idExists_H);
					my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
					my $jlEnd = "</a></li>";
					push @methodList, $jlStart . $f_icon . $methodName . '()' . $jlEnd;
					push @methodNames, uc($methodName);
					}
				}
			}
		
		++$lineNum;
		}

	my @idx = sort { $classNames[$a] cmp $classNames[$b] } 0 .. $#classNames;
	@classList = @classList[@idx];
	@idx = sort { $methodNames[$a] cmp $methodNames[$b] } 0 .. $#methodNames;
	@methodList = @methodList[@idx];
	my $numClassListEntries = @classList;
	my $programBreak = ($numCalls > 1) ? '<br>': '';
	#my $classBreak = ($numClassListEntries > 0) ? '<br>': '';
	$$tocR .= $programBreak . join("\n", @classList) . join("\n", @methodList);
	
	if ($i > 0)
		{
		--$i; # Step back a line, for loop in caller will step ahead one.
		}
	
	return($i);
	}

# Table of Contents for a COBOL class (Object Oriented COBOL).
# Because I decided to do a COBOL TOC, so might as well finish the job.
sub getOneOOCOBOLTOC {
	my ($lines_A, $numLines, $i, $numCalls, $idExists_H, $tocR) = @_;
	my $ooClassName = '';

	my @classList;
	my @classNames;
	my @methodList;
	my @methodNames;

	my %sortLetterForDivision;
	$sortLetterForDivision{'IDENTIFICATION'} = 'A ';
	$sortLetterForDivision{'ENVIRONMENT'} = 'B ';
	$sortLetterForDivision{'DATA'} = 'C ';
	$sortLetterForDivision{'PROCEDURE'} = 'D ';
	
	my $divisionName = '';
	my $divisionNameUC = ''; 	# Uppercase division name
	#my $sectionName = '';
	my $sectionNameUC = '';
	my $inDeclaratives = 0; 	# DECLARATIVES in PROCEDURE division, skip
	my %varNames; 				# Remember variable names from WORKING-STORAGE etc
	my %topLevelVars;			# Variables displayed in the TOC under DATA
	my $topLevelIndentLength = -1; # Pick up only record names with the least indent, based on first seen.
	my $inObject = 0;

	if ($lines_A->[$i] =~ m!^(\d{6}.)?\s*CLASS-ID[.\s]*([a-zA-Z0-9-]+)!i)
		{
		$ooClassName = defined($2) ? $2 : $1;
		++$i;

		my $lineNum = $i;
		my $className = $ooClassName;
		my $contentsClass = 'h2';
		my $id = $className;
		$id =~ s!\s+!_!g;
		$id = UniqueTocID($id, $idExists_H);
		my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
		my $jlEnd = "</a></li>";
		push @classList, $jlStart . $C_icon . $ooClassName . $jlEnd;
		push @classNames, $sortLetterForDivision{'IDENTIFICATION'} . uc($className);
		}
	else # No class, no TOC. Maintenance error probably.
		{
		return($numLines);
		}

	for (; $i < $numLines; ++$i)
		{
		my $lineNum = $i + 1;

		# Methods: pick up the name and skip to END.
		if ($lines_A->[$i] =~ m!^(\d{6}.)?\s*METHOD-ID\.?\s+([a-zA-Z0-9-]+)!i)
			{
			my $methodName = defined($2) ? $2 : $1;
			my $contentsClass = 'h3';
			my $id = $methodName;
			$id =~ s!\s+!_!g;
			$id = UniqueTocID($id, $idExists_H);
			my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			my $jlEnd = "</a></li>";
			if ($methodName =~ m!^new$!i)
				{
				push @methodList, $jlStart . $m_icon . "<strong>" . $methodName . "</strong>" . '()' . $jlEnd;
				}
			else
				{
				push @methodList, $jlStart . $m_icon. $methodName . '()' . $jlEnd;
				}
			push @methodNames, uc($methodName);

			# Skip to END METHOD.
			++$i;
			while ($i < $numLines
				&& $lines_A->[$i] !~ m!^(\d{6}.)?\s*END\s+METHOD!i)
				{
				++$i;
				}
			}
		# Drop out if we see "END CLASS".
		elsif ($lines_A->[$i] =~ m!^(\d{6}.)?\s*END\s+CLASS!i)
			{
			last;
			}

		# Are we in an OBJECT?
		elsif ($lines_A->[$i] =~ m!^(\d{6}.)?\s*OBJECT[^-]*!i)
			{
			$inObject = 1;
			}
		elsif ($lines_A->[$i] =~ m!^(\d{6}.)?\s*END\s+OBJECT!i)
			{
			$inObject = 0;
			#last;
			}
		# Pick up top level vars, just 01 and 77.
		elsif ($lines_A->[$i] =~ m!^(\d{6}.)?\s*([a-zA-Z0-9-]+)\s+([a-zA-Z0-9-]+)!)
			{
			my $varName = defined($3) ? $3 : $2;
			my $prefix = defined($3) ? $2 : $1; # Eg "01" or "FD"
			if (!defined($2)) # Shouldn't happen with compilable code
				{
				$varName = $1;
				$prefix = '';
				}
			$varNames{$varName} += 1;

			if ($prefix !~ m!^\d+$! && $prefix !~ m!^[a-zA-Z][a-zA-Z]$!)
				{
				++$lineNum; # This is why I don't like doing "next;"
				next;
				}

			if ($prefix eq "01" || $prefix eq "1" || $prefix eq "77"
				|| $prefix =~ m!^[a-zA-Z][a-zA-Z]$!)
				{
				my $className = $ooClassName . ' ' . $varName;
				my $contentsClass = 'h3';
				my $id = $className;
				$id =~ s!\s+!_!g;
				$id = UniqueTocID($id, $idExists_H);
				my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
				my $jlEnd = "</a></li>";
				push @classList, $jlStart . $D_icon. $varName . $jlEnd;
				push @classNames, uc($className);
				}
			}
		++$lineNum;
		}

	my @idx = sort { $classNames[$a] cmp $classNames[$b] } 0 .. $#classNames;
	@classList = @classList[@idx];
	@idx = sort { $methodNames[$a] cmp $methodNames[$b] } 0 .. $#methodNames;
	@methodList = @methodList[@idx];
	my $numClassListEntries = @classList;
	my $programBreak = ($numCalls > 1) ? '<br>': '';
	my $classBreak = ($numClassListEntries > 0) ? '<br>': '';
	$$tocR .= $programBreak . join("\n", @classList) . $classBreak . join("\n", @methodList);

	# We don't need to step back a line.
	return($i);
	}

# Table of contents for a Visual Basic file.
sub GetVBTOC {
	my ($txtR, $tocR) = @_;
	my @lines = split(/\n/, $$txtR);
	my @moduleList;
	my @moduleNames;
	my @classList;
	my @classNames;
	my @methodList;
	my @methodNames;
	my %idExists; # used to avoid duplicated anchor id's.
	
	# Tag hierarchy.
	my $currentModule = '';
	my $currentClass = '';
	my $currentStructure = '';

	my $numLines = @lines;
	my $lineNum = 1;
	my $quotePos = -1;
	for (my $i = 0; $i < $numLines; ++$i)
		{
		# Crudely remove comments (not perfect, but good enough for us
		# since we are looking for top level defining instances).
		$quotePos = index($lines[$i], "'");
		if ($quotePos >= 0)
			{
			$lines[$i] = substr($lines[$i], 0, $quotePos);
			}
		# Look for tag on line where defined.
		if ($lines[$i] =~ m!^(.*?)(module|sub|function|structure|class)\s+(\w+)!i)
			{
			my $tagType = lc($2);
			my $tagName = $3;
			
			if ($tagType eq 'module')
				{
				$currentModule = $tagName . '.';
				PushVBTag(\@moduleList, \@moduleNames, \%idExists,
						  $lineNum, $tagName, 'h2', $M_icon);
				}
			elsif ($tagType eq 'class')
				{
				$currentClass = $tagName . '.';
				PushVBTag(\@classList, \@classNames, \%idExists,
						  $lineNum, $tagName, 'h2', $C_icon);
				}
			elsif ($tagType eq 'structure')
				{
				$currentStructure = $tagName . '.';
				PushVBTag(\@classList, \@classNames, \%idExists,
						  $lineNum, $tagName, 'h2', $S_icon);
				}
			elsif ($tagType eq 'sub' || $tagType eq 'function')
				{
				my $owner = $currentClass . $currentStructure;
				# Strip final '.' if any.
				my $lastDotPos = rindex($owner, ".");
				if ($lastDotPos > 0)
					{
					$owner = substr($owner, 0, $lastDotPos);
					}
				
				if ($owner ne '')
					{
					PushVBTag(\@classList, \@classNames, \%idExists,
						  $lineNum, $owner . '#' . $tagName, 'h3', $m_icon);
					}
				else
					{
					PushVBTag(\@methodList, \@methodNames, \%idExists,
						  $lineNum, $tagName, 'h2', $f_icon);
					}
				}
			}
		# Look for end tag.
		elsif ($lines[$i] =~ m!^(.*?)end\s+(\w+)!i)
			{
			my $tagType = lc($2);

			if ($tagType eq 'module')
				{
				$currentModule = '';
				}
			elsif ($tagType eq 'class')
				{
				$currentClass = '';
				}
			elsif ($tagType eq 'structure')
				{
				$currentStructure = '';
				}
			
			}
		++$lineNum;
		}
	
	my @idx = sort { $classNames[$a] cmp $classNames[$b] } 0 .. $#classNames;
	@classList = @classList[@idx];
	@idx = sort { $methodNames[$a] cmp $methodNames[$b] } 0 .. $#methodNames;
	@methodList = @methodList[@idx];
	@idx = sort { $moduleNames[$a] cmp $moduleNames[$b] } 0 .. $#moduleNames;
	@moduleList = @moduleList[@idx];
	
	my $numModuleEntries = @moduleList;
	my $moduleBreak = ($numModuleEntries > 0) ? '<br>': '';
	my $numClassListEntries = @classList;
	my $classBreak = ($numClassListEntries > 0) ? '<br>': '';

	# Trim down sub and function entries in @classList, remove owners.
	for (my $i = 0; $i < $numClassListEntries; ++$i)
		{
		if (index($classList[$i], '#') > 0)
			{
			$classList[$i] =~ s!\w+\.!!g;
			$classList[$i] =~ s!\w+\#!!g;
			}
		}
	
	$$tocR = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n" . join("\n", @moduleList) . $moduleBreak . join("\n", @classList) . $classBreak . join("\n", @methodList) . "</ul>\n";
	}

sub PushVBTag {
	my ($listA, $namesA, $idExistsH, $lineNum, $tagName, $contentsClass, $icon) = @_;

	my $id = $tagName;
	$id =~ s!\s+!_!g;
	$id = UniqueTocID($id, $idExistsH);
	my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
	my $jlEnd = "</a></li>";
	push @$listA, $jlStart . $icon . $tagName . $jlEnd;
	push @$namesA, $tagName;
	}

# Use ctags to generate a Table Of Contents (TOC) for a source file. Ctags are written to
# a temp file and then read back in, a bit clumsy but it works.
sub GetCTagsTOCForFile {
	my ($filePath, $tocR) = @_;
	my $dir = lc(DirectoryFromPathTS($filePath));
	my $fileName = FileNameFromPath($filePath);

	# First, get ctags for the file
	my $errorMsg = '';
	my ($ctagsFilePath, $tempFilePath) = MakeCtagsForFile($dir, $fileName, \$errorMsg);
	if ($ctagsFilePath eq '' || length($errorMsg) > 0)
		{
		$$tocR = "<strong>$errorMsg</strong>\n";
		return;
		}
	my %classEntryForLine;
	my %structEntryForLine;
	my %methodEntryForLine;
	my %functionEntryForLine;
	my $itemCount = LoadCtags($filePath, $ctagsFilePath,
						\%classEntryForLine,
						\%structEntryForLine, \%methodEntryForLine,
						\%functionEntryForLine, \$errorMsg);
	if ($errorMsg ne '')
		{
		$$tocR = "<strong>$errorMsg</strong>\n";
		return;
		}
	
	my @classList;
	my @classNames;
	my @structList;
	my @structNames;
	my @methodList;
	my @methodNames;
	my @functionList;
	my @functionNames;
	my %idExists; # used to avoid duplicated anchor id's.
	my $jlEnd = "</a></li>";
	
	foreach my $lineNum (sort {$a <=> $b} keys %structEntryForLine)
		{
		my $className = $structEntryForLine{$lineNum};
		my $contentsClass = 'h2';
		my $id = $className;
		$id =~ s!\s+!_!g;
		$id = UniqueTocID($id, \%idExists);
		my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
		push @structList, $jlStart . $S_icon . $className . $jlEnd;
		push @structNames, $className;
		}

	# LineNumComp() strips any initial 'a' from line numbers
	# before sorting numerically.
	foreach my $lineNum (sort { LineNumComp($a, $b) } keys %classEntryForLine)
	# foreach my $lineNum (sort {$a <=> $b} keys %classEntryForLine)
		{
		my $className = $classEntryForLine{$lineNum};
		my $contentsClass = (index($className, ':') > 0) ? 'h3' : 'h2';
		# And also h3 if entry contains '#' indicating a method (eg Java).
		if (index($className, '#') > 0)
			{
			$contentsClass = 'h3';
			}
		my $id = $className;
		$id =~ s!\s+!_!g;
		$id = UniqueTocID($id, \%idExists);
		
		# As a special case, if $lineNum starts with a letter then the
		# entry is shown "disabled" (gray) and there is no functioning link.
		# (Needed eg for Julia, see LoadJuliaTags()).
		my $jlStart;
		if ($lineNum =~ m!^[a-zA-Z]!)
			{
			$jlStart = "<li class='h2Disabled'><a>";
			#$jlStart = "<li class='h2Disabled'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			}
		else
			{
			$jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			}
		push @classList, $jlStart . $C_icon . $className . $jlEnd;
		push @classNames, $className;
		}
		
	foreach my $lineNum (sort {$a <=> $b} keys %methodEntryForLine)
		{
		my $methodName = $methodEntryForLine{$lineNum};
		my $contentsClass = 'h2';
		my $id = $methodName;
		$id =~ s!\s+!_!g;
		$id = UniqueTocID($id, \%idExists);
		my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
		push @methodList, $jlStart . $m_icon . $methodName . '()' . $jlEnd;
		push @methodNames, $methodName;
		}

	foreach my $lineNum (sort {$a <=> $b} keys %functionEntryForLine)
		{
		my $methodName = $functionEntryForLine{$lineNum};
		my $contentsClass = 'h2';
		my $id = $methodName;
		$id =~ s!\s+!_!g;
		$id = UniqueTocID($id, \%idExists);
		my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
		push @functionList, $jlStart . $f_icon . $methodName . '()' . $jlEnd;
		push @functionNames, $methodName;
		}

	my $numStructs = @structList;
	my $numClasses = @classList;
	my $numMethods = @methodList;
	my $numFunctions = @functionList;
	my @idx;
	
	if ($numStructs)
		{
		@idx = sort { $structNames[$a] cmp $structNames[$b] } 0 .. $#structNames;
		@structList = @structList[@idx];
		}
	if ($numClasses)
		{
		@idx = sort { $classNames[$a] cmp $classNames[$b] } 0 .. $#classNames;
		@classList = @classList[@idx];
		}
	if ($numMethods)
		{
		@idx = sort { $methodNames[$a] cmp $methodNames[$b] } 0 .. $#methodNames;
		@methodList = @methodList[@idx];
		}
	if ($numFunctions)
		{
		@idx = sort { $functionNames[$a] cmp $functionNames[$b] } 0 .. $#functionNames;
		@functionList = @functionList[@idx];
		}
	
	my $numClassListEntries = @classList;
	my $typeBreak = ($numClassListEntries > 0) ? '<br>': '';
	$$tocR = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n";
	if ($numStructs)
		{
		my $structString = join("\n", @structList);
		$$tocR .= $structString;
		}
	if ($numClasses)
		{
		# If the classList contains method/interface'::' tags, remove those
		# to make the TOC narrower. Also remove method/interface tags
		# if entry contains '#' indicating a method name.
		for (my $i = 0; $i < @classList; ++$i)
			{
			if (index($classList[$i], ':') > 0)
				{
				$classList[$i] =~ s!\w+\:\:!!g;
				# Fix the icon
				$classList[$i] =~ s!$C_icon!$m_icon!;
				}
			
			if (index($classList[$i], '#') > 0)
				{
				$classList[$i] =~ s!\w+\.!!g;
				$classList[$i] =~ s!\w+\#!!g;
				# Fix the icon
				$classList[$i] =~ s!$C_icon!$m_icon!;
				}
			}
		my $classString = join("\n", @classList);
		if ($numStructs)
			{
			$classString = $typeBreak . $classString;
			}
		$$tocR .= $classString;
		}
	if ($numMethods)
		{
		my $methodString = join("\n", @methodList);
		if ($numStructs || $numClasses)
			{
			$methodString = $typeBreak . $methodString;
			}
		$$tocR .= $methodString;
		}
	if ($numFunctions)
		{
		my $functionString = join("\n", @functionList);
		if ($numStructs || $numClasses || $numMethods)
			{
			$functionString = $typeBreak . $functionString;
			}
		$$tocR .= $functionString;
		}
	
	#$$tocR = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n" .
	#			join("\n", @classList) . $classBreak . join("\n", @methodList) . "</ul>\n";

	# Get rid of the one or two temp files made while getting ctags.
	unlink($ctagsFilePath);
	if ($tempFilePath ne '')
		{
		unlink($tempFilePath);
		}
	}

# Sort line numbers, first stripping any initial 'a'.
sub LineNumComp {
	my ($numA, $numB) = @_;
	if (index($numA, 'a') == 0)
		{
		$numA = substr($numA, 1);
		}
	if (index($numB, 'a') == 0)
		{
		$numB = substr($numB, 1);
		}
	
	return($numA <=> $numB);
	}

# Ctags handling, for CSS files. There can be multiple entries per line, and tag can be
# somewhat modified for use as an anchor.
sub GetCssCTagsTOCForFile {
	my ($filePath, $tocR) = @_;
	my $dir = lc(DirectoryFromPathTS($filePath));
	my $fileName = FileNameFromPath($filePath);
	my $contentsClass = 'h2';

	# First, get ctags for the file
	my $errorMsg = '';
	my ($ctagsFilePath, $tempFilePath) = MakeCtagsForFile($dir, $fileName, \$errorMsg);
	if ($ctagsFilePath eq '' || length($errorMsg) > 0)
		{
		$$tocR = "<strong>$errorMsg</strong>\n";
		return;
		}
	my %tagEntryForLine;
	my %tagDisplayedNameForLine;
	$fileName = lc($fileName);
	my $itemCount = LoadCssCtags($ctagsFilePath, $fileName,
								\%tagEntryForLine,
								\%tagDisplayedNameForLine,
								\$errorMsg);
	if ($errorMsg ne '')
		{
		$$tocR = "<strong>$errorMsg</strong>\n";
		return;
		}
	
	my @anchorList;
	my @displayedTagNames;
	my %idExists; # used to avoid duplicated anchor id's.
	my $jlEnd = "</a></li>";
	foreach my $lineNum (keys %tagEntryForLine)
		{
		my $tag = $tagEntryForLine{$lineNum};
		my $displayedTag = $tagDisplayedNameForLine{$lineNum};
		if (index($tag, "|") > 0) # multiple entries for line
			{
			my @tags = split(/\|/, $tag);
			my @displayedtags = split(/\|/, $displayedTag);
			for (my $j = 0; $j < @tags; ++$j)
				{
				$tag = $tags[$j];
				$displayedTag = $displayedtags[$j];
				my $id = $tag;
				if (!defined($idExists{$id}))
					{
					my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
					my $jlEnd = "</a></li>";
					push @anchorList, $jlStart . $displayedTag . $jlEnd;
					push @displayedTagNames, $displayedTag;
					}
				$idExists{$id} = 1;
				}
			}
		else # single entry for line
			{
			my $id = $tag;
			if (!defined($idExists{$id}))
				{
				my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
				my $jlEnd = "</a></li>";
				push @anchorList, $jlStart . $displayedTag . $jlEnd;
				push @displayedTagNames, $displayedTag;
				}
			$idExists{$id} = 1;
			}
		}
	
	my @idx = sort { $displayedTagNames[$a] cmp $displayedTagNames[$b] } 0 .. $#displayedTagNames;
	@anchorList = @anchorList[@idx];
	$$tocR = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n" .
				join("\n", @anchorList) . "</ul>\n";

	# Get rid of the one or two temp files made while getting ctags.
	unlink($ctagsFilePath);
	if ($tempFilePath ne '')
		{
		unlink($tempFilePath);
		}
	}

# Get array contents for "let highlightItems = [_HIGHLIGHTITEMS_];" in FullFile().
# Mark only the first few hits. For now, 50.
sub GetCodeMirrorSearchHitPositions {
	my ($formH, $hitsA, $hitArrayContentsR) = @_;
	my $filePath = $formH->{'FULLPATH'};
	$$hitArrayContentsR = "";
	
	my $maximumHitsToMark = 50;
	
	my $octets;
	my $dummyContents;
	if (!LoadTextFileContents($filePath, \$dummyContents, \$octets))
		{
		return;
		}

	my @hits = @$hitsA;
	my @hitLengths;
	for (my $i = 0; $i < @hits; ++$i)
		{
		push @hitLengths, length($hits[$i]);
		}
	my $numHitItems = @hits;
	my @lines = split(/\n/, $octets);
	my $currPos = -1;
	my @hitArray; # array of "[line, charStart, charEnd]"
	
	my $numHitsSoFar = 0;
	for (my $i = 0; $i < @lines; ++$i)
		{
		$lines[$i] = lc($lines[$i]);
		for(my $j = 0; $j < $numHitItems; ++$j)
			{
			$currPos = 0;
			while (($currPos = index($lines[$i], $hits[$j], $currPos)) >= 0)
				{
				my $endPos = $currPos + $hitLengths[$j];
				push @hitArray, "[$i, $currPos, $endPos]";
				$currPos = $endPos;
				++$numHitsSoFar;
				}
			}
		last if ($numHitsSoFar >= $maximumHitsToMark);
		}
	
	$$hitArrayContentsR = join(',', @hitArray);
	}

{ ##### Perl Syntax Highlight
my $formatter;
my %StartFormats;
my %EndFormats;

sub InitPerlSyntaxHighlighter {
	$formatter = Syntax::Highlight::Perl::Improved->new();
	
	$StartFormats{'Comment_Normal'} = "<span class='Comment_Normal'>";
	$StartFormats{'Comment_POD'} = "<span class='Comment_POD'>";
	$StartFormats{'Directive'} = "<span class='Directive'>";
	$StartFormats{'Label'} = "<span class='Label'>";
	$StartFormats{'Quote'} = "<span class='Quote'>";
	$StartFormats{'String'} = "<span class='String'>";
	$StartFormats{'Subroutine'} = "<span class='Subroutine'>";
	$StartFormats{'Variable_Scalar'} = "<span class='Variable_Scalar'>";
	$StartFormats{'Variable_Array'} = "<span class='Variable_Array'>";
	$StartFormats{'Variable_Hash'} = "<span class='Variable_Hash'>";
	$StartFormats{'Variable_Typeglob'} = "<span class='Variable_Typeglob'>";
	#$StartFormats{'Whitespace'} = "<span class='Whitespace'>";
	$StartFormats{'Character'} = "<span class='Character'>";
	$StartFormats{'Keyword'} = "<span class='Keyword'>";
	$StartFormats{'Builtin_Function'} = "<span class='Builtin_Function'>";
	$StartFormats{'Builtin_Operator'} = "<span class='Builtin_Operator'>";
	$StartFormats{'Operator'} = "<span class='Operator'>";
	$StartFormats{'Bareword'} = "<span class='Bareword'>";
	$StartFormats{'Package'} = "<span class='Package'>";
	$StartFormats{'Number'} = "<span class='Number'>";
	$StartFormats{'Symbol'} = "<span class='Symbol'>";
	$StartFormats{'CodeTerm'} = "<span class='CodeTerm'>";
	$StartFormats{'DATA'} = "<span class='DATA'>";
	
	$EndFormats{'Comment_Normal'} = "</span>";
	$EndFormats{'Comment_POD'} = "</span>";
	$EndFormats{'Directive'} = "</span>";
	$EndFormats{'Label'} = "</span>";
	$EndFormats{'Quote'} = "</span>";
	$EndFormats{'String'} = "</span>";
	$EndFormats{'Subroutine'} = "</span>";
	$EndFormats{'Variable_Scalar'} = "</span>";
	$EndFormats{'Variable_Array'} = "</span>";
	$EndFormats{'Variable_Hash'} = "</span>";
	$EndFormats{'Variable_Typeglob'} = "</span>";
	#$EndFormats{'Whitespace'} = "</span>";
	$EndFormats{'Character'} = "</span>";
	$EndFormats{'Keyword'} = "</span>";
	$EndFormats{'Builtin_Function'} = "</span>";
	$EndFormats{'Builtin_Operator'} = "</span>";
	$EndFormats{'Operator'} = "</span>";
	$EndFormats{'Bareword'} = "</span>";
	$EndFormats{'Package'} = "</span>";
	$EndFormats{'Number'} = "</span>";
	$EndFormats{'Symbol'} = "</span>";
	$EndFormats{'CodeTerm'} = "</span>";
	$EndFormats{'DATA'} = "</span>";
	
	$formatter->set_start_format(\%StartFormats);
	$formatter->set_end_format(\%EndFormats);
	
	my $subH = $formatter->substitutions();
	$subH->{'<'} = '&lt;';
	$subH->{'>'} = '&gt;';
	$subH->{'&'} = '&amp;';
	#$subH->{"\t"} = '&nbsp;&nbsp;&nbsp;&nbsp;';
	#$subH->{"    "} = '&nbsp;&nbsp;&nbsp;&nbsp;';
	}

sub GetPerlHighlighter {
	# Some files such as filehandle.pm kill the Perl formatter,
	# and it starts spitting out unhighlighted text.
	# A reset seems to cure that.
	$formatter->reset();
	return($formatter);
	}

} ##### Perl Syntax Highlight

{ ##### Exuberant Ctags Support
# Ctags is used to generate a list of tags and their locations in
# a source file, which in turn is used to generate a table of contents.

my $CtagsOutputFilePathBase;
my $CtagsOutputFilePath;
my $CTAGS_DIR;
my $CTAGS_EXE;
my %SupportedExtension; # eg $SupportedExtension{'cpp'} = 'C++';

sub InitCtags {
	my ($firstPartOfPath) = @_;
	my $port = $port_listen;
	$CtagsOutputFilePathBase = $firstPartOfPath . '_' . $port;
	$CTAGS_DIR = CVal('CTAGS_DIR');
	$CTAGS_DIR =~ s!\\!/!g;
	$CTAGS_DIR =~ s!/$!!g;
	$CTAGS_EXE = $CTAGS_DIR . '/ctags.exe';
	if (!(-f $CTAGS_EXE))
		{
		die("intramine_viewer.pl InitCtags error, terminating, could not find exuberant ctags.exe in |$CTAGS_DIR|! Did you set CTAGS_DIR in /data/intramine_config.txt?");
		}
	GetCTagSupportedTypes();
	}

# eg $SupportedExtension{'cpp'} = 'C++';
sub GetCTagSupportedTypes {
	my $theTypes = <<'FINIS';
Ada      *.adb *.ads *.Ada *.ada
Ant      *.ant
Asciidoc *.asc *.adoc *.asciidoc *.asc *.adoc *.asciidoc
Asm  *.A51 *.29k *.29K *.68k *.68K *.86k *.86K *.88k *.88K *.68s *.68S *.86s *.86S *.88s *.88S *.68x *.68X *.86x *.86X *.88x *.88X *.x86 *.x68 *.x88 *.X86 *.X68 *.X88 *.asm *.ASM
Asp      *.asp *.asa
Autoconf *.ac
AutoIt   *.au3 *.AU3 *.aU3 *.Au3
Automake *.am
Awk      *.awk *.gawk *.mawk
Basic    *.bas *.bi *.bb *.pb
BETA     *.bet
Clojure  *.clj *.cljs *.cljc
CMake    *.cmake
C        *.c
C++      *.c++ *.cc *.cp *.cpp *.cxx *.h *.h++ *.hh *.hp *.hpp *.hxx *.inl
CSS      *.css
C#       *.cs
Ctags    *.ctags
Cobol    *.cbl *.cob *.CBL *.COB
CUDA     *.cu *.cuh
D        *.d *.di
Diff     *.diff *.patch
DTD      *.dtd *.mod
DTS      *.dts *.dtsi
DosBatch *.bat *.cmd
Eiffel   *.e
Elm      *.elm
Erlang   *.erl *.ERL *.hrl *.HRL
Falcon   *.fal *.ftd
Flex     *.as *.mxml
Fortran  *.f *.for *.ftn *.f77 *.f90 *.f95 *.f03 *.f08 *.f15
Fypp     *.fy
Gdbinit  .gdbinit *.gdb
Go       *.go
Haskell       *.hs
HTML     *.htm *.html
Iniconf  *.ini *.conf
ITcl     *.itcl
Java     *.java
JavaProperties *.properties
JavaScript *.js *.jsx
JSON     *.json
Julia     *.jl
LdScript *.lds *.scr *.ld
Lisp     *.cl *.clisp *.el *.l *.lisp *.lsp
Lua      *.lua
M4       *.m4 *.spt
Man      *.1 *.2 *.3 *.4 *.5 *.6 *.7 *.8 *.9 *.3pm *.3stap *.7stap
Make     *.mak *.mk
Markdown *.md *.markdown
MatLab   *.m
Myrddin  *.myr
ObjectiveC *.mm *.m *.h
OCaml    *.ml *.mli *.aug
Pascal   *.p *.pas
Perl     *.pl *.pm *.ph *.plx *.perl
Perl6    *.p6 *.pm6 *.pm *.pl6
PHP      *.php *.php3 *.php4 *.php5 *.php7 *.phtml
Pod      *.pod
Protobuf *.proto
PuppetManifest *.pp
Python   *.py *.pyx *.pxd *.pxi *.scons *.wsgi
QemuHX   *.hx
R        *.r *.R *.s *.q
REXX     *.cmd *.rexx *.rx
Robot    *.robot
RpmSpec  *.spec
ReStructuredText *.rest *.reST *.rst
Ruby     *.rb *.ruby
Rust     *.rs
Scheme   *.SCM *.SM *.sch *.scheme *.scm *.sm
Sh       *.sh *.SH *.bsh *.bash *.ksh *.zsh *.ash
SLang    *.sl
SML      *.sml *.sig
SQL      *.sql
SystemdUnit *.unit *.service *.socket *.device *.mount *.automount *.swap *.target *.path *.timer *.snapshot *.scope *.slice *.time
Tcl      *.tcl *.tk *.wish *.exp
Tex      *.tex
TTCN     *.ttcn *.ttcn3
TypeScript  *.ts
Vera     *.vr *.vri *.vrh
Verilog  *.v
SystemVerilog *.sv *.svh *.svi
VHDL     *.vhdl *.vhd
Vim      *.vim *.vba
WindRes  *.rc
YACC     *.y
YumRepo  *.repo
Zephir   *.zep
DBusIntrospect *.xml
Glade    *.glade
Maven2   pom.xml *.pom *.xml
PlistXML *.plist
RelaxNG  *.rng
SVG      *.svg
XSLT     *.xsl *.xslt
Yaml     *.yml
FINIS

	my @typeLines = split(/\n/, $theTypes);
	my $numTypes = @typeLines;
	for (my $i = 0; $i < $numTypes; ++$i)
		{
		my @typeExt = split(/ +/, $typeLines[$i]);
		my $lang = $typeExt[0];
		my $numEntries = @typeExt;
		for (my $j = 1; $j < $numEntries; ++$j)
			{
			my $ext = lc($typeExt[$j]);
			$ext =~ s!^\*\.!!;
			$SupportedExtension{$ext} = $lang;
			}
		}
	}

sub IsSupportedByCTags {
	my ($filePath) = @_;
	my $result = 0;
	if ($filePath =~ m!\.(\w+)$!)
		{
		my $fileExt = lc($1);
		if (defined($SupportedExtension{$fileExt}))
			{
			$result = 1;
			}
		}
	
	return($result);
	}

# Call Universal Ctags to generate ctags for $dir . $fileName, to a temp file that only
# one instance of this server uses. Wait until done, then return path to the ctags temp file.
# LIMITATION this does not work as quickly as it could if $fileName or $dir contain "unicode" characters,
# since an entire temp copy of the file is made, with a plain ascii name. A better workaround would be
# to use Win32::API to import CreateProcessW, but I'm just not up to it today. Sorry.
sub MakeCtagsForFile {
	my ($dir, $fileName, $errorMsgR) = @_;
	my $result = '';
	my $tempFilePath = '';
	my $tempDir = '';
	my $proc;
	
	# Trouble with "wide" file names. Towards a workaround, copy the file being processed to
	# something temp with a "narrow" name.
	my $haveWideName = ($fileName =~ m![\x80-\xFF]!) || ($dir =~ m![\x80-\xFF]!);
	
	if ($haveWideName)
		{
		my $ext = '';
		if ($fileName =~ m!\.(\w+)$!)
			{
			$ext = $1;
			}
		my $randomInteger = random_int_between(1001, 60000);
		$tempFilePath = 'temp_code_copy_' . $port_listen . time . $randomInteger . ".$ext";
		$tempDir = $LogDir . 'temp/';
		#print("Copying |$dir$fileName| to |$tempDir$tempFilePath|\n");
		if (CopyFileWide($dir . $fileName, $tempDir . $tempFilePath, 0))
			{
			#print("Making ctags\n");
			my $randomInteger2 = random_int_between(1001, 60000);
			$CtagsOutputFilePath = $CtagsOutputFilePathBase . time . $randomInteger2 . '.txt';
			my $didit = Win32::Process::Create($proc, $CTAGS_EXE, " -n -u -f \"$CtagsOutputFilePath\" \"$tempFilePath\"", 0, 0, $tempDir);
			if (!$didit)
				{
				my $status = Win32::FormatMessage( Win32::GetLastError() );
				$$errorMsgR = "MakeCtagsForFile Error |$status|, could not run $CTAGS_EXE!";
				return($result);
				}
			$proc->Wait(INFINITE);
			$result = $CtagsOutputFilePath;
			#unlink($tempFilePath); too soon, sometimes - for unlink see GetCTagsTOCForFile();
			}
		}
	else
		{
		my $randomInteger = random_int_between(1001, 60000);
		$CtagsOutputFilePath = $CtagsOutputFilePathBase . time . $randomInteger . '.txt';
		my $didit = Win32::Process::Create($proc, $CTAGS_EXE, " -n -u -f \"$CtagsOutputFilePath\" \"$fileName\"", 0, 0, $dir);
		if (!$didit)
			{
			my $status = Win32::FormatMessage( Win32::GetLastError() );
			$$errorMsgR = "MakeCtagsForFile Error |$status|, could not run $CTAGS_EXE!";
			return($result);
			}
		$proc->Wait(INFINITE);
		$result = $CtagsOutputFilePath;
		}
	
	return($result, $tempDir . $tempFilePath);
	}

#http://ctags.sourceforge.net/FORMAT
#PropertyGetterSetter	qqmljsast_p.h	682;"	c	namespace:QQmlJS::AST
#PropertyGetterSetter	qqmljsast_p.h	696;"	f	class:QQmlJS::AST::PropertyGetterSetter
#tagname}<Tab>{tagfile}<Tab>{tagaddress
#tagname tab sourcefile tab \d+ not-tab tab c or f tab not-colon to the end for 'f' is the owning class, ignore trailer if 'c'
# - technically that not-tab is ;"
# - there can be other "kinds" besides c or f, ignore them
# - mind you, need to check struct, and <template> files
# That incoherent preamble was brought to you by caffeine.
# Ahem: go through a ctags file and pick out entries that declare classes and methods. Poke
# those into hashes, indexed by line number.
# (In progress, individual language are being addressed in order to
# generate more accurate tables of contents.)
sub LoadCtags {
	my ($filePath, $ctagsFilePath, $classEntryForLineH, $structEntryForLineH, $methodEntryForLineH, $functionEntryForLineH, $errorMsgR) = @_;
	my $itemCount = 0;
	$$errorMsgR = '';

	if (!(-f $ctagsFilePath))
		{
		$$errorMsgR .= "$ctagsFilePath does not exist.";
		return($itemCount);
		}
	my $octets = read_file($ctagsFilePath);
	if (!defined($octets))
		{
		$$errorMsgR .= "Error, could not open $ctagsFilePath.";
		return($itemCount);
		}
	
	#my $topScopeFunctionName = '';
	my @lines = split(/\n/, $octets);
	my $numLines = @lines;
	
	# Per-language regex's to extract tags:
	if ($filePath =~ m!\.ts$!i)
		{
		$itemCount = LoadTypeScriptTags(\@lines, $classEntryForLineH, $structEntryForLineH, $methodEntryForLineH, $functionEntryForLineH);
		}
	elsif ($filePath =~ m!\.java$!i)
		{
		$itemCount = LoadJavaTags(\@lines, $classEntryForLineH, $structEntryForLineH, $methodEntryForLineH, $functionEntryForLineH);
		}
	elsif ($filePath =~ m!\.rs$!i)
		{
		$itemCount = LoadRustTags(\@lines, $classEntryForLineH, $structEntryForLineH, $methodEntryForLineH, $functionEntryForLineH);
		}
	elsif ($filePath =~ m!\.(rb|ruby)$!i)
		{
		$itemCount = LoadRubyTags(\@lines, $classEntryForLineH, $structEntryForLineH, $methodEntryForLineH, $functionEntryForLineH);
		}
	elsif ($filePath =~ m!\.cs$!i)
		{
		$itemCount = LoadCSharpTags(\@lines, $classEntryForLineH, $structEntryForLineH, $methodEntryForLineH, $functionEntryForLineH);
		}
	elsif ($filePath =~ m!\.jl$!i)
		{
		$itemCount = LoadJuliaTags(\@lines, $classEntryForLineH, $structEntryForLineH, $methodEntryForLineH, $functionEntryForLineH);
		}
	else # Default class/struct/function handling
		{
		for (my $i = 0; $i < $numLines; ++$i)
			{
			# selectUrl\tqfiledialog.cpp\t1085;"\tf\tclass:QFileDialog\ttyperef:typename:void
			if ($lines[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([csf])\t[^:]+:([^\t]+)\t[^\t]+$!)
				{
				my $tagname = $1;
				my $lineNumber = $2;
				my $kind = $3;
				my $owner = $4;
				if ($kind eq 'c')
					{
					$classEntryForLineH->{"$lineNumber"} = $tagname;
					++$itemCount;
					}
				elsif ($kind eq 's')
					{
					$structEntryForLineH->{"$lineNumber"} = $tagname;
					++$itemCount;
					}
				elsif ($kind eq 'f')
					{
					$methodEntryForLineH->{"$lineNumber"} = $owner . '::' . $tagname;
					# Experiment, put methods in the $classEntryForLineH hash, to group
					# methods under the owning class/interface. This doesn't work
					# for C++, there is typically no owning class entry in the .cpp file.
					#$classEntryForLineH->{"$lineNumber"} = $owner . '::' . $tagname;
					++$itemCount;
					}
				# else $kind eq 'e' for enum etc - ignore
				}
			# qt_tildeExpansion\tqfiledialog.cpp\t1100;"\tf\ttyperef:typename:Q_AUTOTEST_EXPORT QString
			elsif ($lines[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([csf])!) # no class or namespace specifier
				{
				my $tagname = $1;
				my $lineNumber = $2;
				my $kind = $3;
				if ($kind eq 'c')
					{
					$classEntryForLineH->{"$lineNumber"} = $tagname;
					++$itemCount;
					}
				elsif ($kind eq 's')
					{
					$structEntryForLineH->{"$lineNumber"} = $tagname;
					++$itemCount;
					}
				elsif ($kind eq 'f')
					{
					# A small nuisance, don't list nested functions (eg in JavaScript) separately.
					# A regular entry ends in 'f', a nested entry is followed by 'function:'.
					if ($lines[$i] !~ m!\t+f\t+function\:!)
						{
						#$topScopeFunctionName = $tagname;
						$methodEntryForLineH->{"$lineNumber"} = $tagname;
						}
					# This is out mainly because the ctags parser returns nested functions before
					# the enclosing function, and seems to miss some nested functions too.
	#				else
	#					{
	#					$methodEntryForLineH->{"$lineNumber"} = "$topScopeFunctionName.$tagname";
	#					$methodNameForLineH->{"$lineNumber"} = $tagname;
	#					# TEST ONLY codathon
	#					print("N: |$lines[$i]|\n");
	#					}
						
					++$itemCount;
					}
				# else $kind eq 'e' for enum etc - ignore
				}
			}
		}
	
	return($itemCount);
	}

# Get tag hashes of class/interface/method/function entries from lines in a TypeScript
# file. Note struct is ignored.
# Return count of all tags.
sub LoadTypeScriptTags {
	my ($linesA, $classEntryForLineH, $structEntryForLineH, 
		$methodEntryForLineH, $functionEntryForLineH) = @_;
	my $itemCount = 0;
	my $numLines = @{$linesA};
	
	for (my $i = 0; $i < $numLines; ++$i)
		{
		# Eg (function, function, class, method, interface):
		# isDeclarationFileInJSOnlyNonConfiguredProject	session.ts	23;"	f	namespace:ts.server
		# formatMessage	session.ts	130;"	f	namespace:ts.server
		# MultistepOperation	session.ts	166;"	c	namespace:ts.server
		# immediate	session.ts	188;"	m	class:ts.server.MultistepOperation
		# PendingErrorCheck	session.ts	113;"	i	namespace:ts.server
		if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cfmi])\t([^\t]+)$!
			|| $linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cfmi])$!)
		#if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cfmi])\t([^\t]+)$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			my $owner = defined($4)? $4: '';

			if ($kind eq 'c' || $kind eq 'i')
				{
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'm')
				{
				my $class = $owner;
				my $lastPeriodPos = rindex($class, '.');
				if ($lastPeriodPos >= 0)
					{
					$class = substr($class, $lastPeriodPos + 1);
					}
				my $lastColonPos = rindex($class, ':');
				if ($lastColonPos >= 0)
					{
					$class = substr($class, $lastColonPos + 1);
					}
				# Revision, put methods in the $classEntryForLineH hash, to group
				# methods under the owning class/interface.
				#$methodEntryForLineH->{"$lineNumber"} = $class . '::' . $tagname;
				$classEntryForLineH->{"$lineNumber"} = $class . '::' . $tagname;
				}
			elsif ($kind eq 'f')
				{
				$functionEntryForLineH->{"$lineNumber"} = $tagname;
				}
			++$itemCount;
			}
		}
	
	return($itemCount);
	}

# Get tag hashes of class/interface/method entries for a Java file.
# Return count of all tags.
sub LoadJavaTags {
	my ($linesA, $classEntryForLineH, $structEntryForLineH, 
		$methodEntryForLineH, $functionEntryForLineH) = @_;
	my $itemCount = 0;
	my $numLines = @{$linesA};
	
	for (my $i = 0; $i < $numLines; ++$i)
		{
		# Trailing scope.
		# ResponseContext	Transport.java	154;"	c	interface:Transport
		# getNetworkMessageSize	Header.java	40;"	m	class:Header
		# Connection	Transport.java	92;"	i	interface:Transport
		# getNode	Transport.java	96;"	m	interface:Transport.Connection
		if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cmi])\t([^\t]+)$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			my $owner = $4;
			
			# Strip "interface" or "class" from start of $owner.
			my $colonPos = index($owner, ':');
			if ($colonPos > 0)
				{
				$owner = substr($owner, $colonPos + 1);
				}

			if ($kind eq 'c' || $kind eq 'i')
				{
				if ($owner ne '')
					{
					$tagname = $owner . '.' . $tagname;
					}
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'm')
				{
				# Put in $class hash, prepend $owner so methods will sort with
				# owner.
				# NOTE using '#' as separator between $owner and $tagname.
				if ($owner ne '')
					{
					$tagname = $owner . '#' . $tagname;
					}
				
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		# No trailing scope.
		# Header	Header.java	20;"	c
		# Transport	Transport.java	35;"	i
		# (I suspect all methods have a trailing scope.)
		elsif ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cfmi])$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			
			if ($kind eq 'c' || $kind eq 'i')
				{
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'm')
				{
				$methodEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		++$itemCount;
		}
	
	return($itemCount);
	}

# Do P method, f function, i interface, s struct.
# Return count of all tags.
sub LoadRustTags {
	my ($linesA, $classEntryForLineH, $structEntryForLineH, 
		$methodEntryForLineH, $functionEntryForLineH) = @_;
	my $itemCount = 0;
	my $numLines = @{$linesA};
	
	for (my $i = 0; $i < $numLines; ++$i)
		{
		#Tag examples
		# Plugin	plugin.rs	21;"	i
		# name	plugin.rs	23;"	P	interface:Plugin
		# Builder	plugin.rs	136;"	s
		# get_menu_ids	tray.rs	23;"	f
		# Trailing scope.
		if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([iPsf])\t([^\t]+)$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			my $owner = $4;
			
			# Strip "interface" or "class" from start of $owner.
			my $colonPos = index($owner, ':');
			if ($colonPos > 0)
				{
				$owner = substr($owner, $colonPos + 1);
				}

			if ($kind eq 's' || $kind eq 'i')
				{
				if ($owner ne '')
					{
					$tagname = $owner . '.' . $tagname;
					}
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'P' || $kind eq 'f')
				{
				# Put in $class hash, prepend $owner so methods will sort with
				# owner.
				# NOTE using '#' as separator between $owner and $tagname.
				if ($owner ne '')
					{
					$tagname = $owner . '#' . $tagname;
					}
				
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		# No trailing scope.
		elsif ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([iPsf])$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			
			if ($kind eq 's' || $kind eq 'i')
				{
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'P' || $kind eq 'f')
				{
				$methodEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		++$itemCount;
		}
	
	return($itemCount);
	}

# Do S singletonMethod, c class, f method, m module. Note ctags doesn't always give
# an owning class or object for a singleton, so those are listed
# as unowned methods at the bottom of the TOC.
# Return count of all tags.
sub LoadRubyTags {
	my ($linesA, $classEntryForLineH, $structEntryForLineH, 
		$methodEntryForLineH, $functionEntryForLineH) = @_;
	my $itemCount = 0;
	my $numLines = @{$linesA};
	
	for (my $i = 0; $i < $numLines; ++$i)
		{
		# Tag examples:
		# wheels	vehicle.rb	16;"	S
		# Floor	floor.rb	2;"	c	module:RubyWarrior
		# initialize	floor.rb	6;"	f	class:RubyWarrior.Floor
		if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([fcSm])\t([^\t]+)$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			my $owner = $4;
			
			# Strip "module" or "class" from start of $owner.
			my $colonPos = index($owner, ':');
			if ($colonPos > 0)
				{
				$owner = substr($owner, $colonPos + 1);
				}

			if ($kind eq 'c' || $kind eq 'S')
				{
				if ($owner ne '')
					{
					# For S, separate $owner and $tagname with '#'
					if ($kind eq 'S')
						{
						$tagname = $owner . '#' . $tagname;
						}
					else
						{
						$tagname = $owner . '.' . $tagname;
						}
					}
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'm')
				{
				if ($owner ne '')
					{
					$tagname = $owner . '.' . $tagname;
					}
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'f')
				{
				# Put in $class hash, prepend $owner so methods will sort with
				# owner.
				# NOTE using '#' as separator between $owner and $tagname.
				if ($owner ne '')
					{
					$tagname = $owner . '#' . $tagname;
					}
				
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		# No trailing scope. (Orphan S singletons show up here.)
		elsif ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([fcSm])$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			
			if ($kind eq 'c')
				{
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'm')
				{
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'f' || $kind eq 'S')
				{
				$methodEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		++$itemCount;
		}
		
	return($itemCount);
	}

# Get tag hashes of c class, m method, p property, s struct, i interface entries for a C# file.
# Return count of all tags.
sub LoadCSharpTags {
	my ($linesA, $classEntryForLineH, $structEntryForLineH, 
		$methodEntryForLineH, $functionEntryForLineH) = @_;
	my $itemCount = 0;
	my $numLines = @{$linesA};
	
	for (my $i = 0; $i < $numLines; ++$i)
		{
		# Trailing scope. C# entries sometimes have a trailing "\tfile:".
		if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cmpsi])\t([^\t]+)((\t\w+\:)?)$!)
		#if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cmpsi])\t([^\t]+)$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			my $owner = $4;
			
			# Strip "interface:" or "class:" from start of $owner.
			my $colonPos = index($owner, ':');
			if ($colonPos > 0)
				{
				$owner = substr($owner, $colonPos + 1);
				}

			if ($kind eq 'c' || $kind eq 'i' || $kind eq 's')
				{
				if ($owner ne '')
					{
					$tagname = $owner . '.' . $tagname;
					}
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'm' || $kind eq 'p')
				{
				# Put in $class hash, prepend $owner so methods will sort with
				# owner.
				# NOTE using '#' as separator between $owner and $tagname.
				if ($owner ne '')
					{
					$tagname = $owner . '#' . $tagname;
					}
				
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		# No trailing scope.
		# Header	Header.java	20;"	c
		# Transport	Transport.java	35;"	i
		# (I suspect all methods have a trailing scope.)
		elsif ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cmpsi])$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			
			if ($kind eq 'c' || $kind eq 'i' || $kind eq 's')
				{
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'm' || $kind eq 'p')
				{
				$methodEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		++$itemCount;
		}
	
	return($itemCount);
	}

# Get tag hashes of n module s struct f function entries for a Julia file.
# Some functions can belong to modules such as Base that are not present
# in the file - dummy entries are inserted for Base etc if needed.
# Note a '!' can be part of a function name.
# Return count of all tags.
sub LoadJuliaTags {
	my ($linesA, $classEntryForLineH, $structEntryForLineH, 
		$methodEntryForLineH, $functionEntryForLineH) = @_;
	my $itemCount = 0;
	my $numLines = @{$linesA};
	
	my $module = ''; # The module name for the file.
	
	for (my $i = 0; $i < $numLines; ++$i)
		{
		if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([nsf])\t([^\t]+)((\t\w+\:)?)$!)
			{
			my $tagname = $1; 		# NOTE may include '!'
			my $lineNumber = $2;
			my $kind = $3;
			my $owner = $4;
			
			# Strip "module:" from start of $owner.
			my $colonPos = index($owner, ':');
			if ($colonPos > 0)
				{
				$owner = substr($owner, $colonPos + 1);
				}

			if ($kind eq 'n')
				{
				if ($owner ne '')
					{
					$tagname = $owner . '.' . $tagname;
					}
				$classEntryForLineH->{"$lineNumber"} = $tagname;				
				}
			elsif ($kind eq 's')
				{
				if ($owner ne '')
					{
					$tagname = $owner . '.' . $tagname;
					}
				$structEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'f')
				{
				$classEntryForLineH->{"$lineNumber"} = $owner . '#' . $tagname;
				}
			}
		elsif ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([nsf])$!)
			{
			my $tagname = $1; 		# NOTE may include '!'
			my $lineNumber = $2;
			my $kind = $3;
			
			if ($kind eq 'n')
				{
				$module = $tagname;
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 's')
				{
				# No owner: use $module if there is one.
				my $owner = ($module ne '') ? "$module." : '';
				$structEntryForLineH->{"$lineNumber"} = $tagname . $owner;
				}
			elsif ($kind eq 'f')
				{
				# No owner: use $module if there is one.
				my $owner = ($module ne '') ? "$module#" : '';
				$classEntryForLineH->{"$lineNumber"} = $owner . $tagname;
				}
			}
		++$itemCount;
		}
		
	# In Julia a function can be defined for a module that is not itself
	# defined in the current file. If a module is not defined, poke in
	# an entry for it so that functions can be grouped under it - but
	# the missing module itself will be disabled in the table of contents.
	my %missingModules;
	foreach my $lineNum (keys %{$classEntryForLineH})
		{
		my $value = $classEntryForLineH->{$lineNum};
		my $octoPos = index($value, '#');
		if ($octoPos > 0)
			{
			my $ownerName = substr($value, 0, $octoPos);
			if (!defined($missingModules{$ownerName}) && $ownerName ne $module)
				{
				$missingModules{$ownerName} = 'a' . $lineNum;
				}
			}
		}
	
	foreach my $missingModule (keys %missingModules)
		{
		my $lineNum = $missingModules{$missingModule};
		$classEntryForLineH->{"$lineNum"} = $missingModule;
		}
	
	return($itemCount);
	}

# CSS tags are a mess from the perspective of using them as anchors: there can be several
# defined on one line, characters such as space hash '>' and comma are used. The approach here
# is to replace a run of all but comma with underscores for the actual anchor, trimming off any initial
# period or hash. If there are several tags separated by commas, separate entries are made for
# each (all with the same line number).
# Examples of 	original tab 		vs 				tagEntry for lineNumber:
# 				.form-container h2					form_container_h2
# 				.todo-task > .task-header			todo_task_task-header
#				.first, .second						first|second
sub LoadCssCtags {
	my ($ctagsFilePath, $lcCssFileName, $tagEntryForLineH, $tagDisplayedNameForLineH, $errorMsgR) = @_;
	my $itemCount = 0;
	$$errorMsgR = '';

	if (!(-f $ctagsFilePath))
		{
		$$errorMsgR .= "$ctagsFilePath does not exist.";
		return($itemCount);
		}
	my $octets = read_file($ctagsFilePath);
	if (!defined($octets))
		{
		$$errorMsgR .= "Error, could not open $ctagsFilePath.";
		return($itemCount);
		}
	
	my @lines = split(/\n/, $octets);
	my $numLines = @lines;
	
	for (my $i = 0; $i < $numLines; ++$i)
		{
		if ($lines[$i] =~ m!^(.+?)\s+$lcCssFileName\s+(\d+);!)
			{
			my $displayedTagname = $1;
			my $lineNumber = $2;
			
			if (index($displayedTagname, ",") > 0) # multiple tags, separate entries for linenum by '|'
				{
				my @tags = split(/,\s*/, $displayedTagname);
				for (my $j = 0; $j < @tags; ++$j)
					{
					$displayedTagname = $tags[$j];
					my $tagname = $displayedTagname;
					$tagname =~ s!^[^A-Za-z0-9_]+!!;
					$tagname =~ s![^A-Za-z0-9_]+!_!g;
					if (defined($tagEntryForLineH->{"$lineNumber"}))
						{
						$tagEntryForLineH->{"$lineNumber"} .= "|$tagname";
						$tagDisplayedNameForLineH->{"$lineNumber"} .= "|$displayedTagname";
						}
					else
						{
						$tagEntryForLineH->{"$lineNumber"} = $tagname;
						$tagDisplayedNameForLineH->{"$lineNumber"} = $displayedTagname;
						}
					}
				}
			else # single tag, but can be multiple entries for the same line number
				{
				my $tagname = $displayedTagname;
				$tagname =~ s!^[^A-Za-z0-9_]+!!;
				$tagname =~ s![^A-Za-z0-9_]+!_!g;
				
				if (defined($tagEntryForLineH->{"$lineNumber"}))
					{
					$tagEntryForLineH->{"$lineNumber"} .= "|$tagname";
					$tagDisplayedNameForLineH->{"$lineNumber"} .= "|$displayedTagname";
					}
				else
					{
					$tagEntryForLineH->{"$lineNumber"} = $tagname;
					$tagDisplayedNameForLineH->{"$lineNumber"} = $displayedTagname;
					}
				}
			}
		}
	}
} ##### Exuberant Ctags Support


{ ##### Internal Links
my $line;
my $len;
	
# These replacements are more easily done in reverse order to avoid throwing off the start/end.
my @repStr;			# new link, eg <a href="#Header_within_doc">#Header within doc</a>
my @repLen;			# length of substr to replace in line, eg length('#Header within doc')
my @repStartPos;	# where header being replaced starts, eg zero-based positon of '#' in '#Header within doc'

# AddInternalLinksToLine
# Turn mention of a header within a txt file into a link.
# Called only for .txt files, see GetPrettyTextContents() above.
# Header mentions must be enclosed in "", and can be either the
# actual text of the header or the boiled-down anchor (spaces -> underscores etc) eg:
# "Header name" "Header_name".
# A previous pass through the text has made note of headers, so we just need to check
# quoted text against a hash of headers to see if one is mentioned. After "boiling down"
# the header mention first, as mentioned.
# Skip existing links to anchors in other files. This check is needed only
# after a potential header has been found.
# Any found mention of a header, such as "Header within doc", is turned into a link
# <a href="#Header_within_doc">Header within doc</a>.
sub AddInternalLinksToLine {
	my ($txtR, $sectionIdExistsH) = @_;
	
	# Skip any line that does have a header element <h1> <h2> etc or doesn't have a header delimiter.
	if (index($$txtR, '><h') > 0 || index($$txtR, '"') < 0)
		{
		return;
		}
	
	# Init variables with "Internal Links" scope.
	$line = $$txtR;
	$len = length($line);
	@repStr = ();		# new link, eg <a href="#Header_within_doc">#Header within doc</a>
	@repLen = ();		# length of substr to replace in line, eg length('#Header within doc')
	@repStartPos = ();	# where header being replaced starts, eg zero-based positon of '#' in '#Header within doc'
	
	EvaluateInternalLinkCandidates($sectionIdExistsH);

	# Do all reps in reverse order at end.
	my $numReps = @repStr;
	if ($numReps)
		{
		for (my $i = $numReps - 1; $i >= 0; --$i)
			{
			# substr($line, $pos, $srcLen, $repString);
			substr($line, $repStartPos[$i], $repLen[$i], $repStr[$i]);
			}
		$$txtR = $line;
		}
	}
	
sub EvaluateInternalLinkCandidates {
	my ($sectionIdExistsH) = @_;
	
	# Find first pair of double quotes, if any.
	# Get things started by spotting the first ". At least one is guaranteed above.
	my $currentMatchStartPos = index($line, '"');
	
	# Find the next double quote, or we are done.
	my $currentMatchEndPos = -1;
	if ($line =~ m!^.{$currentMatchStartPos}..*?(["])!)
		{
		$currentMatchEndPos = $-[1];
		}
	else
		{
		return;
		}
	
	# Loop over all potential matches on the line.
	while ($currentMatchStartPos > 0)
		{
		# Look at the current quoted text.
		$line =~ m!^.{$currentMatchStartPos}.([^"]+)!;
		my $potentialID = $1;
		# Convert raw text into a header anchor. (Aka "boiling down")
		# (Note stripping HTML elements will also strip trailing </td></td> if we're at end of line.)
		$potentialID =~ s!<[^>]+>!!g;
		# File links can have &nbsp;
		$potentialID =~ s!&nbsp;!_!g;
		# Quotes don't help either.
		$potentialID =~ s!['"]!!g;
		# Convert spaces to underscores too.
		$potentialID =~ s! !_!g;
		# Remove unicode symbols from $id, especially the ones inserted by markdown above, to make
		# it easier to type the headers in links. Eg 'server swarm.txt#TODO_List' for header '&#127895;TODO List'.
		$potentialID =~ s!\&#\d+;!!g; # eg &#9755;
		
		# Have we matched a known header with our (potential) ID?
		my $haveGoodMatch = 0;
		if (defined($sectionIdExistsH->{$potentialID}))
			{
			# No match if '#' was inside a pre-existing file anchor.
			if (!InsideExistingAnchor('"', $currentMatchEndPos))
				{
				$haveGoodMatch = 1;
				my $repStartPosition = $currentMatchStartPos;
				my $repLength = $currentMatchEndPos - $currentMatchStartPos + 1;

				# <a href="#Header_within_doc">Header within doc</a>
				# At this point, $repString is just the anchor $potentialID.
				my $srcHeader = substr($line, $repStartPosition, $repLength);
				my $replacementAnchor = "<a href=\"#$potentialID\">$srcHeader</a>";
				push @repStr, $replacementAnchor;
				push @repLen, $repLength;
				push @repStartPos, $repStartPosition;
				}
			}
		
		# On to the next match, if any. For a good match, skip past the current matching text.
		# For a bad match, just skip past the current starting quote.
		$currentMatchStartPos = ($haveGoodMatch) ? $currentMatchEndPos + 1 : $currentMatchStartPos + 1;
		$currentMatchEndPos = -1;
		if ($currentMatchStartPos < $len - 2
		  && $line =~ m!^.{$currentMatchStartPos}.*?(["])!)
			{
			$currentMatchStartPos = $-[1];
			if ($currentMatchStartPos < $len - 2
			  && $line =~ m!^.{$currentMatchStartPos}..*?(["])!)
				{
				$currentMatchEndPos = $-[1];
				}
			}
			
		if ($currentMatchEndPos < 0)
			{
			$currentMatchStartPos = -1;
			}
		} # while ($currentMatchStartPos > 0)
	}

sub InsideExistingAnchor {
	my ($delimiter, $currentPos) = @_;
	my $insideExistingAnchor = 0;
	
	# Is there an anchor on the line, when delimiter is '#'?
	if ($delimiter eq '#' && index($line, '<a') > 0)
		{
		# Does the anchor enclose the header mention?
		#<a href="http://192.168.0.3:43129/?href=c:/perlprogs/mine/notes/server swarm.txt#Set_HTML" target="_blank">server swarm.txt#Set_HTML</a>
		# Look ahead for either '<a ' or '</a>, and if '</a>' is seen first
		# then it's inside an anchor.
		# If it's in the href, it will be preceded immediately by a port number.
		# If it's displayed as the anchor content, it will be preceded immediately
		# by a file extension.
		my $nextAnchorStartPos = index($line, '<a ', $currentPos);
		my $nextAnchorEndPos = index($line, '</a>', $currentPos);
		if ($nextAnchorEndPos >= 0 &&
			($nextAnchorStartPos < 0 || $nextAnchorEndPos < $nextAnchorStartPos ))
			{
			$insideExistingAnchor = 1;
			}
		}
	
	return($insideExistingAnchor);
	}
} ##### Internal Links

# Much as AddInternalLinksToLine() just above, but only single words
# are examined for a match against a TOC entry, and word must be followed immediately by '('
# (possibly with intervening span markup),
# which limits links to sub() mentions, in code or comments.
# Or preceded by '&', meaning a subrouting reference.
# OUTSIDE of a comment, a sub call looks like:
#		<span class="Subroutine">MakeDirectoriesForFile</span>\s*<span class="Symbol">(</span>....
# INSIDE of a comment, it's just
# 		MakeDirectoriesForFile(....
sub AddInternalLinksToPerlLine {
	my ($txtR, $sectionIdExistsH) = @_;
	
	# Skip any line that does have a '(' or '&amp;' or is a sub definition.
	if ((index($$txtR, '(') < 0 && index($$txtR, '&amp;') < 0) || index($$txtR, 'sub<') > 0)
		{
		return;
		}
	
	my $line = $$txtR;
	
	# These replacements are more easily done in reverse order to avoid throwing off the start/end.
	my @repStr;			# new link, eg <a href="#GetBinFile">GetBinFile</a>(...)
	my @repLen;			# length of substr to replace in line, eg length('GetBinFile')
	my @repStartPos;	# where header being replaced starts, eg zero-based positon of 'B' in 'GetBinFile'

	my $currentMatchEndPos = 0;
	while ( ($currentMatchEndPos = index($line, '(', $currentMatchEndPos)) > 0 )
		{
		my $haveGoodMatch = 0;
		# Find end and start of any word before '('. Skip over span stuff if it's code, not comment.
		my $wordEndPos = $currentMatchEndPos;
		if (substr($line, $wordEndPos - 1, 1) eq '>')
			{
			$wordEndPos = rindex($line, '<', $wordEndPos);
			$wordEndPos = rindex($line, '>', $wordEndPos) unless $wordEndPos < 0;
			$wordEndPos = rindex($line, '<', $wordEndPos) unless $wordEndPos < 0;
			}
		#else assume subroutine name is immediately before the '('.
		# If no word end, keep going.
		if ($wordEndPos < 0)
			{
			++$currentMatchEndPos;
			next;
			}
		
		my $wordStartPos = rindex($line, ' ', $wordEndPos);
		my $rightAnglePos = rindex($line, '>', $wordEndPos);
		if ($rightAnglePos > 0 && ($wordStartPos < 0 || $rightAnglePos > $wordStartPos))
			{
			$wordStartPos = $rightAnglePos;
			}
		my $hashPos = rindex($line, '#', $wordEndPos);
		if ($hashPos > 0 && ($wordStartPos < 0 || $hashPos > $wordStartPos))
			{
			$wordStartPos = $hashPos;
			}
		++$wordStartPos; # Skip the space or > or #.
				
		my $potentialID = substr($line, $wordStartPos, $wordEndPos - $wordStartPos);
		# Have we matched a known header with our (potential) ID?
		if (defined($sectionIdExistsH->{$potentialID}))
			{
			$haveGoodMatch = 1;
			my $charBeforeMatch = substr($line, $wordStartPos-1, 1);
			if ($charBeforeMatch eq '#')
				{
				my $insideExistingAnchor = 0;
				# Is there an anchor on the line?
				if (index($line, '<a') > 0)
					{
					# Does the anchor enclose the header mention? That's a hard one.
					#<a href="http://192.168.0.3:43129/?href=c:/perlprogs/mine/notes/server swarm.txt#Set_HTML" target="_blank">server swarm.txt#Set_HTML</a>
					# If it's in the href, it will be preceded immediately by a port number.
					# If it's displayed as the anchor content, it will be preceded immediately
					# by a file extension.
					# REVISION if followed by single or double quote, but there isn't a
					# matching single or double quote before the #, skip it.
					#$posSep = index($line, '.', $prevPos);
					my $currentPos = $wordEndPos;
					my $nextAnchorStartPos = index($line, '<a ', $currentPos);
					my $nextAnchorEndPos = index($line, '</a>', $currentPos);
					if ($nextAnchorEndPos >= 0 &&
						($nextAnchorStartPos < 0 || $nextAnchorEndPos <$nextAnchorStartPos ))
						{
						$insideExistingAnchor = 1;
						}
					}
				
				if ($insideExistingAnchor)
					{
					$haveGoodMatch = 0;
					}
				else
					{
					# Skip if we see \w# before the word, likely meaning that a file name precedes
					# the word and it's really a link to another file.
					if ($wordStartPos > 2)
						{
						my $charBefore = substr($line, $wordStartPos - 2, 1);
						my $ordCB = ord($charBefore);
						my $isExtensionChar = (($ordCB >= $ORD_a && $ordCB <= $ORD_z) || ($ordCB >= $ORD_A && $ordCB <= $ORD_Z) || ($ordCB >= $ORD_0 && $ordCB <= $ORD_9));
						if ($isExtensionChar)
							{
							$haveGoodMatch = 0;
							}
						}
					}
				}
			
			if ($haveGoodMatch)
				{
				# <a href="#potentialID">potentialID</a>
				push @repStr, "<a href=\"#$potentialID\">$potentialID</a>";
				push @repStartPos, $wordStartPos;
				push @repLen, $wordEndPos - $wordStartPos;
				}
			}
		
		++$currentMatchEndPos;
		} # while ($currentMatchEndPos = (index($line, '(', $currentMatchEndPos)) > 0)
		
	# Also look for \&Subname. In practice, &Subname should do.
	# (Note & is &amp; in the HTML.)
	my $currentMatchStartPos = 0;
	while ( ($currentMatchStartPos = index($line, '&amp;', $currentMatchStartPos)) > 0 )
		{
		# If chars following the '&' form a word, look it up in TOC entries.
		my $wordStartPos = $currentMatchStartPos + 5;
		my $wordEndPos = $wordStartPos;
		my $nextChar = substr($line, $wordEndPos, 1);
		my $ordNC = ord($nextChar);
		while (($ordNC >= $ORD_a && $ordNC <= $ORD_z) || ($ordNC >= $ORD_A && $ordNC <= $ORD_Z) || ($ordNC >= $ORD_0 && $ordNC <= $ORD_9))
			{
			++$wordEndPos;
			$nextChar = substr($line, $wordEndPos, 1);
			$ordNC = ord($nextChar);
			}
		if ($wordEndPos > $wordStartPos)
			{
			my $potentialID = substr($line, $wordStartPos, $wordEndPos - $wordStartPos);
			if (defined($sectionIdExistsH->{$potentialID}))
				{
				push @repStr, "<a href=\"#$potentialID\">$potentialID</a>";
				push @repStartPos, $wordStartPos;
				push @repLen, $wordEndPos - $wordStartPos;
				}
			$currentMatchStartPos += ($wordEndPos - $wordStartPos);
			}
		else
			{
			$currentMatchStartPos += 5;
			}
		}

	# Do all reps in reverse order at end.
	my $numReps = @repStr;
	if ($numReps)
		{
		for (my $i = $numReps - 1; $i >= 0; --$i)
			{
			# substr($line, $pos, $srcLen, $repString);
			substr($line, $repStartPos[$i], $repLen[$i], $repStr[$i]);
			}
		$$txtR = $line;
		}
	}
