# intramine_viewer.pl: use CodeMirror to display most code files,
# with custom display (code below) for txt, Perl, and pod.
# Pdf and docx also have basic viewers.
# All code and text files have autolinks, and image hovers, and glossary popups.
# Text files (.txt) are given the full Gloss (like Markdown) treatment with
# headings, lists, tables, autolinks, image hovers, special characters,
# horizontal rules and a table of contents on the left.
# Files with tables of contents: txt, pl, pm, pod, C(++), js, css, go,
# and many others supported by ctags such as PHP, Ruby - see libs/toc_local.pm and ex_ctags.pm.
# This is not a "top" server, meaning it doesn't have an entry in IntraMine's top navigation bar.
# Typically it's called by click on a link in Search page results, the Files page lists,
# or a link in a view provided by this Viewer or the Editor service.
#
# See also Documentation/Viewer.html.
#

# perl C:\perlprogs\IntraMine\intramine_viewer.pl

use strict;
use warnings;
use utf8;
use FileHandle;
use Encode;
use Encode::Guess;
use HTML::Entities;
#use URI::Escape;
use URI::Escape qw(uri_unescape);
use Text::Tabs;
$tabstop = 4;
#use Syntax::Highlight::Perl::Improved ':BASIC'; # ':BASIC' or ':FULL' - FULL doesn't seem to do much
use Time::HiRes qw ( time );
use Win32::Process 'STILL_ACTIVE';    # for calling Universal ctags.exe etc
use JSON::MaybeXS qw(encode_json);
use Text::MultiMarkdown;              # for .md files
use Win32;
use Time::HiRes qw(usleep);
use Path::Tiny  qw(path);
use Pod::Simple::HTML;
use Cwd qw();
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;
use win_wide_filepaths;
use win_user32_local;
use docx2txt;
use ext;                              # for ext.pm#IsTextExtensionNoPeriod() etc.
use html2gloss;
use toc_local;
use gloss;                            # Just for footnotes

Encode::Guess->add_suspects(qw/iso-8859-1/);

binmode(STDOUT, ":encoding(UTF-8)");
Win32::SetConsoleCP(65001);

$| = 1;

# Some ASCII values, used in AddInternalLinksToPerlLine(). Obsolete..
my $ORD_a = ord('a');
my $ORD_z = ord('z');
my $ORD_A = ord('A');
my $ORD_Z = ord('Z');
my $ORD_0 = ord('0');
my $ORD_9 = ord('9');

# Circled letters, used in tables of contents.
my $C_icon = '<span class="circle_green">C</span>';    # Class
my $S_icon = '<span class="circle_green">S</span>';    # Struct
my $M_icon = '<span class="circle_green">M</span>';    # Module
my $T_icon = '<span class="circle_blue">T</span>';     # Type
my $D_icon = '<span class="circle_blue">D</span>';     # Data
my $m_icon = '<span class="circle_red">m</span>';      # method
my $f_icon = '<span class="circle_red">f</span>';      # function
my $s_icon = '<span class="circle_red">s</span>';      # subroutine

my %VideMimeTypeForExtension;
$VideMimeTypeForExtension{'mp4'}  = 'video/mp4';
$VideMimeTypeForExtension{'m4v'}  = 'video/MP4V-ES';
$VideMimeTypeForExtension{'webm'} = 'video/webm';
$VideMimeTypeForExtension{'3gp'}  = 'video/3gpp';
$VideMimeTypeForExtension{'mkv'}  = 'video/x-matroska';
$VideMimeTypeForExtension{'avi'}  = 'video/x-msvideo';
$VideMimeTypeForExtension{'mpeg'} = 'video/mpeg';
$VideMimeTypeForExtension{'ogv'}  = 'video/ogg';
$VideMimeTypeForExtension{'ts'}   = 'video/mp2t';
$VideMimeTypeForExtension{'3g2'}  = 'video/3gpp2';
$VideMimeTypeForExtension{'ogg'}  = 'application/ogg';

#LoadCobolKeywords();

my $PAGENAME    = '';
my $SHORTNAME   = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

my $CSS_DIR                = FullDirectoryPath('CSS_DIR');
my $JS_DIR                 = FullDirectoryPath('JS_DIR');
my $IMAGES_DIR             = FullDirectoryPath('IMAGES_DIR');
my $COMMON_IMAGES_DIR      = CVal('COMMON_IMAGES_DIR');
my $UseAppForLocalEditing  = CVal('USE_APP_FOR_EDITING');
my $UseAppForRemoteEditing = CVal('USE_APP_FOR_REMOTE_EDITING');
my $AllowLocalEditing      = CVal('ALLOW_LOCAL_EDITING');
my $AllowRemoteEditing     = CVal('ALLOW_REMOTE_EDITING');

# Just a whimsy - for contents.txt files that start with CONTENTS, try to make it look
# like an old-fashioned "special" table of contents. Initialized here.
InitSpecialIndexFileHandling();

my $kLOGMESSAGES     = 0;    # 1 == Log Output() messages
my $kDISPLAYMESSAGES = 0;    # 1 == print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print.
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);

my $GLOSSARYFILENAME = lc(CVal('GLOSSARYFILENAME'));

# For ATX-style headings that start with a '#', optionally require blank line before
# (which is the default).
my $HashHeadingRequireBlankBefore = CVal("HASH_HEADING_NEEDS_BLANK_BEFORE");

#InitPerlSyntaxHighlighter();
my $LogDir    = FullDirectoryPath('LogDir');
my $ctags_dir = CVal('CTAGS_DIR');
InitTocLocal($LogDir . 'temp/tempctags',
	$port_listen, $LogDir, $ctags_dir, $HashHeadingRequireBlankBefore);
#InitCtags($LogDir . 'temp/tempctags');

Output("Starting $SHORTNAME on port $port_listen\n\n");

#my %ThemeIsDark; # $ThemeIsDark{'theme'} = 1 if bkg is dark, 0 if light.
InitThemeIsDark();

# This service has no default action. For file display either 'href=path'
# or the more RESTful '.../file/path' can be used. See eg intramine_search.js#viewerOpenAnchor()
# (a call to that is inserted by elasticsearcher.pm#FormatHitResults() among others).
my %RequestAction;
$RequestAction{'href'}   = \&FullFile; # Open file, href = anything
$RequestAction{'/file/'} = \&FullFile; # RESTful alternative, /file/is followed by file path in $obj
$RequestAction{'req|loadfile'}      = \&LoadTheFile;      # req=loadfile
$RequestAction{'req|openDirectory'} = \&OpenDirectory;    # req=openDirectory
# The following two callbacks are needed if any css/js files
# are passed to GetStandardPageLoader() in the first argument. Not needed here.
$RequestAction{'req|css'} = \&GetRequestedFile;    # req=css  see swarmserver.pm#GetRequestedFile()
$RequestAction{'req|js'}  = \&GetRequestedFile;    # req=js
$RequestAction{'req|timestamp'} = \&GetTimeStamp;    # req=timestamp
# Testing
$RequestAction{'/test/'} = \&SelfTest;               # Ask this server to test itself.
# Not needed, done in swarmserver: $RequestAction{'req|id'} = \&Identify; # req=id

# For calling the Linker to supply FLASH links etc. See AddFlashLinksToFootnote below.
my %LinkerArguments;
$LinkerArguments{'FIRST_LINE_NUM'} = "1";
$LinkerArguments{'LAST_LINE_NUM'}  = "1";
$LinkerArguments{'SHOULD_INLINE'}  = "1";


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
	my $theBody              = FullFileTemplate();
	my $t1                   = time;
	my $fileServerPort       = $port_listen;
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
		print("Could not find |$filePath|!\n");
		return ('');
		}

	my $title      = $filePath . ' NOT RETRIEVED!';
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

	# Editing can be done with IntraMine's Editor, or with your preferred text editor.
	# See intramine_config.txt "ALLOW_LOCAL_EDITING" et seq for some notes on setting up
	# local editing (on the IntraMine box) and remote editing. You can use IntraMine or your
	# preferred app locally or remotely, or disable editing for either.
	my $amRemoteValue      = $clientIsRemote     ? 'true' : 'false';
	my $tfAllowEditing     = ($allowEditing)     ? 'true' : 'false';
	my $tfUseAppForEditing = ($useAppForEditing) ? 'true' : 'false';
	my $host               = $serverAddr;
	my $port               = $port_listen;
	my $fileContents       = '<p>Read error!</p>';
	my $meta               = "";
	my $customCSS          = '';
	my $textTableCSS       = '';
	# For cmTextHolderName = '_CMTEXTHOLDERNAME_'; -- can also  be 'scrollTextRightOfContents'
	my $textHolderName = 'scrollText';
	my $usingCM        = 'true';         # for _USING_CM_ etc (using CodeMirror)

	my $encPath = $filePath;
	$encPath = &HTML::Entities::encode($encPath);

	# Trying to phase out $ctrlSPath.
	my $ctrlSPath = $filePath;

	$LinkerArguments{'REMOTE_VALUE'}     = $clientIsRemote;
	$LinkerArguments{'ALLOW_EDIT_VALUE'} = $tfAllowEditing;
	$LinkerArguments{'USE_APP_VALUE'}    = $useAppForEditing;
	$LinkerArguments{'PEER_ADDRESS'}     = $peeraddress;
	$LinkerArguments{'THE_PATH'}         = uri_escape_utf8($filePath);


	my $topNav = TopNav($PAGENAME);
	$theBody =~ s!_TOPNAV_!$topNav!;

	my $exists = FileOrDirExistsWide($filePath);
	if ($exists == 1)
		{
		$title = $filePath;

		$ctrlSPath = encode_utf8($ctrlSPath);
		$ctrlSPath =~ s!%!%25!g;
		$ctrlSPath =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

		# Set the selected CodeMirror theme.
		my $theme = CVal('THEME');
		if ($theme eq '')
			{
			$theme = 'default';
			}
		$theBody =~ s!_THEME_!$theme!;

		my $themeIsDarkVal = 'false';
		if (ThemeHasDarkBackground($theme))
			{
			$themeIsDarkVal = 'true';
			}
		$theBody =~ s!_THEME_IS_DARK!$themeIsDarkVal!;

		# Added Feb 2024, if it's a video throw it up in a new browser tab.
		if (EndsWithVideoExtension($filePath))
			{
			ShowVideo($obj, $formH, $peeraddress, $clientIsRemote);
			return ("1");
			}

		# Clear out the  array for JavaScript holding git diff changed lines.
		InitDiffChangedLinesForJS();

		# Categories: see GetContentBasedOnExtension() below. Here we handle HTML.
		# 1.1
		# If a local HTML file has been requested, skip the TopNav() etc and just return page as-is.
		# DEFAULTDIR is needed for serving up css and js files associated with page, when url for
		# the resource starts with "./".
		# This is the "view" for HTML: "edit" shows the raw HTML as text.
		if ($filePath =~ m!\.html?$!i)
			{
			GetHTML($formH, $peeraddress, \$fileContents);
			# $meta  not needed.
			my $dir = lc(DirectoryFromPathTS($filePath));
			$formH->{'DEFAULTDIR'} = $dir;
			return ($fileContents);

			}
		else    # all other categories of extension
			{
			GetContentBasedOnExtension(
				$formH,         $peeraddress,   $filePath,        $clientIsRemote,
				$allowEditing,  \$fileContents, \$usingCM,        \$meta,
				\$textTableCSS, \$customCSS,    \$textHolderName, $theme
			);
			}
		}
	else
		{
		# Fail, use text JS and CSS for the 404 display.
		$usingCM   = 'false';
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

	# User custom JS, for .txt and Markdown files.
	if ($filePath =~ m!\.(txt|log|bat)$!i)
		{
		$customJS .= OptionalCustomJSforGloss();
		# Set any diff changed array for.txt
		my $diffLineString = JsDiffChangedLinesEntry();
		if ($diffLineString ne "")
			{
			$theBody =~
s!_CHANGEDARRAY_!<script>const textDiffChangedLines = \[$diffLineString\];\n</script>!;
			}
		else
			{
			$theBody =~ s!_CHANGEDARRAY_!<script>const textDiffChangedLines = \[\];\n</script>!;
			}
		}
	elsif ($filePath =~ m!\.(md|mkd|markdown)$!i)
		{
		$customJS .= OptionalCustomJSforMarkdown();
		$theBody =~ s!_CHANGEDARRAY_!<script>const textDiffChangedLines = \[\];\n</script>!;
		}
	else
		{
		$theBody =~ s!_CHANGEDARRAY_!<script>const textDiffChangedLines = \[\];\n</script>!;
		}

	# OUT, no longer needed, restart_editor_viewer.js is used for all views.
	# Replace restart.js with restart_editor_viewer.js for .txt files.
	# <script src="restart.js"></script>
	# This is needed because txt files in the Viewer lock up
	# after doing window.location.reload();
	# and I can't figure out why - refresh by viewer_auto_refresh.js
	# also does a reload, for example, and there it works.
	# if ($filePath =~ m!\.(txt|log|bat)$!i)
	# 	{
	# 	$customJS =~ s!restart\.js!restart_text_view.js!;
	# 	}

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
	my $modDate     = GetFileModTimeWide($filePath);
	my $size        = GetFileSizeWide($filePath);
	my $sizeDateStr = DateSizeString($modDate, $size);

	# Fill in the placeholders in the HTML template for title etc. And give values to
	# JS variables. See FullFileTemplate() just below.
	#$theBody =~ s!_TITLEHEADER_!$title!;
	my $titleDisplay = TitleDisplay($title, $fileName);
	$theBody =~ s!_TITLEHEADER_!$titleDisplay!;

	$theBody =~ s!_DATEANDSIZE_!$sizeDateStr!;

	# Use $ctrlSPath for $filePath beyond this point.
	# Why? It works. Otherwise Unicode is messed up.
	$filePath = $encPath;

	# Trying to phase out $ctrlSPath. Not going well, back to using it.
	#$filePath = $ctrlSPath;

	$theBody =~ s!_PATH_!$ctrlSPath!g;
	$theBody =~ s!_ENCODEDPATH_!$ctrlSPath!g;

	$theBody =~ s!_FILE_MOD_DATE!$modDate!;

	$theBody =~ s!_USING_CM_!$usingCM!;
	$theBody =~ s!_CMTEXTHOLDERNAME_!$textHolderName!g;

	my $findTip = '';    #"(Unshift for lower case)"; I have forgotten why I did that
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
	my $filesShortName  = CVal('FILESSHORTNAME');
	my $videoShortName  = CVal('VIDEOSHORTNAME');
	$theBody =~ s!_VIEWERSHORTNAME_!$viewerShortName!;
	$theBody =~ s!_OPENERSHORTNAME_!$openerShortName!;
	$theBody =~ s!_EDITORSHORTNAME_!$editorShortName!;
	$theBody =~ s!_LINKERSHORTNAME_!$linkerShortName!;
	$theBody =~ s!_FILESSHORTNAME_!$filesShortName!;
	$theBody =~ s!_VIDEOSHORTNAME_!$videoShortName!;
	#$theBody =~ s!_FILESERVERPORT_!$fileServerPort!g;
	$theBody =~ s!_WEAREREMOTE_!$amRemoteValue!;
	$theBody =~ s!_ALLOW_EDITING_!$tfAllowEditing!;
	$theBody =~ s!_USE_APP_FOR_EDITING_!$tfUseAppForEditing!;
	my $dtime = DoubleClickTime();
	$theBody =~ s!_DOUBLECLICKTIME_!$dtime!;

	# Display popup for the specifics of git diff HEAD at line where the gutter is clicked.
	#$theBody =~ s!_DIFF_SPECIFICS_POPUP_!!;
	my $diffSpecificsPopup = DiffSpecificsPopup();
	$theBody =~ s!_DIFF_SPECIFICS_POPUP_!$diffSpecificsPopup!;


	# Put in an "Edit" button for files that can be edited (if editing is allowed).
	# "Edit" can invoke IntraMine's Editor or your preferred editor.
	my $editAction = EditButton($host, $filePath, $clientIsRemote, $allowEditing);
	$theBody =~ s!_EDITACTION_!$editAction!;

	# Add Search/Find.
	my $search =
		"<input id=\"search-button\" class=\"submit-button\" type=\"submit\" value=\"Find\" />";
	#$theBody =~ s!_SEARCH_!$search!;
	# Rev, Find isn't that useful and the browser has a built-in Find.
	$theBody =~ s!_SEARCH_!!;

	# Detect any searchItems passed along for hilighting. If there are any, add a
	# "Hide/Show Initial Hits" button at top of page.
	my $searchItems = defined($formH->{'searchItems'}) ? $formH->{'searchItems'} : '';
	my ($highlightItems, $toggleHitsButton) = InitialHighlightItems($formH, $usingCM, $searchItems);
	$theBody =~ s!_HIGHLIGHTITEMS_!$highlightItems!;
	$theBody =~ s!_INITIALHITSACTION_!$toggleHitsButton!;
	my $togglePositionButton = '';
	# Markdown Toggle won't work because there are no line numbers.
	if ($filePath !~ m!\.(md|mkd|markdown)$!i)
		{
		$togglePositionButton = PositionToggle();
		}
	$theBody =~ s!_TOGGLEPOSACTION_!$togglePositionButton!;

	my $inlineHoverButton = InlineHoverButton($filePath);
	$theBody =~ s!_HOVERINLINE_!$inlineHoverButton!;

	# Hilight class for table of contents selected element - see also non_cm_test.css
	# and cm_viewer.css.
	$theBody =~ s!_SELECTEDTOCID_!tocitup!;

	# .txt files, put in mono or proportional font, '' otherwise.
	# ___TEXT___FONT___
	# my $textFontCssFile = '';
	# if ($fileName =~ m!\.(txt|log|bat)$!i)
	# 	{
	# 	my $useProportional = 1;
	# 	if ($useProportional)
	# 		{
	# 		$textFontCssFile = '<link rel="stylesheet" type="text/css" href="txt_font_prop.css" />';
	# 		}
	# 	else
	# 		{
	# 		$textFontCssFile = '<link rel="stylesheet" type="text/css" href="txt_font_mono.css" />';
	# 		}
	# 	}
	# # else leave empty
	# $theBody =~ s!___TEXT___FONT___!$textFontCssFile!;

	# Put in main IP, main port, our short name for JavaScript.
	PutPortsAndShortnameAtEndOfBody(\$theBody);   # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()

	# Keep this last, else a casual mention of _TITLE_ etc in the file contents
	# could get replaced by one of the above substitutions.
	$theBody =~ s!_FILECONTENTS_!$fileContents!;

	my $elapsed     = time - $t1;
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
<link rel="stylesheet" type="text/css" href="hide_contents.css" />
<link rel="stylesheet" type="text/css" href="showDiffDetails.css" />
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
_DIFF_SPECIFICS_POPUP_
<script>
let weAreRemote = _WEAREREMOTE_;
let allowEditing = _ALLOW_EDITING_;
let useAppForEditing = _USE_APP_FOR_EDITING_;
let thePath = '_PATH_';
let theEncodedPath = '_ENCODEDPATH_';
let fileModTime = '_FILE_MOD_DATE';
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
let videoShortName = '_VIDEOSHORTNAME_';
let peeraddress = '_PEERADDRESS_';	// ip address of client
let errorID = "editor_error";
let highlightItems = [_HIGHLIGHTITEMS_];
let b64ToggleImage = '';
let selectedTocId = '_SELECTEDTOCID_';
let doubleClickTime = _DOUBLECLICKTIME_;
let selectedTheme = '_THEME_';
let themeIsDark = _THEME_IS_DARK;
let weAreEditing = false; // Don't adjust user selection if editing - we are not editing here.

let arrowHeight = 18;
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
<script src="showDiffDetails.js"></script>
_JAVASCRIPT_
<script>
window.addEventListener('wsinit', function (e) { wsSendMessage('activity ' + shortServerName + ' ' + ourSSListeningPort); }, false);
</script>
_CHANGEDARRAY_
</body></html>
FINIS

	return ($theBody);
}

sub TitleDisplay {
	my ($filePath, $fileName) = @_;
	$filePath =~ s!\\!/!g;
	my $currentPath = Win32::GetLongPathName($filePath);
	if (!defined($currentPath) || $currentPath eq '')
		{
		$currentPath = $filePath;
		}

	$filePath = $currentPath;
	$filePath    =~ s!/!\\!g;
	$currentPath =~ s!\\!/!g;
	$currentPath =~ s!//!/!g;
	my $directoryAnchorList = "";

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
"<span id=\"viewEditTitle\" class=\"slightShadow\" onmouseover=\"showhint(`$directoryAnchorList`, this, event, '600px', false);\" >$filePath</span>";

	return ($result);
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
	my (
		$formH,          $peeraddress,    $filePath,         $clientIsRemote,
		$allowEditing,   $fileContents_R, $usingCM_R,        $meta_R,
		$textTableCSS_R, $customCSS_R,    $textHolderName_R, $theme
	) = @_;

	# CSS varies: CodeMirror, Markdown, (other) non-CodeMirror.
	# CodeMirror CSS:
	my $cssForCM =
		  '<link rel="stylesheet" type="text/css" href="lib/codemirror.css" />' . "\n"
		. '<link rel="stylesheet" type="text/css" href="addon/dialog/dialog.css" />' . "\n"
		. '<link rel="stylesheet" type="text/css" href="addon/search/matchesonscrollbar.css" />'
		. "\n"
		. '<link rel="stylesheet" type="text/css" media="screen" href="addon/search/cm_small_tip.css" />'
		. "\n"
		. '<link rel="stylesheet" type="text/css" href="cm_viewer.css" />' . "\n";
	$cssForCM .= CodeMirrorThemeCSS();

	# Determine non-CM CSS theme file. Add it in for non-CodeMirror displays.
	my $nonCmThemeCssFile = NonCodeMirrorThemeCSS($theme, $filePath);

	# For some displays eg txt, @@@ signals a section break "flourish" image.
	# Set it here for all, just in case it's needed.
	SetFlourishLinkBasedOnTheme($theme);

	# Markdown CSS:
	my $cssForMD = '<link rel="stylesheet" type="text/css" href="cm_md.css" />';
	#$cssForMD .= $nonCmThemeCssFile;
	# Non CodeMirror CSS:
	my $cssForNonCm = '<link rel="stylesheet" type="text/css" href="non_cm_text.css" />';
	#$cssForNonCm .= $nonCmThemeCssFile;
	# For $textTableCSS variations, some table formatting.
	my $cssForNonCmTables = '<link rel="stylesheet" type="text/css" href="non_cm_tables.css" />';
	#$cssForNonCmTables .= $nonCmThemeCssFile;
	my $cssForPod = '<link rel="stylesheet" type="text/css" href="pod.css" />';
	#$cssForPod .= $nonCmThemeCssFile;


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
		$$meta_R    = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
		}
	elsif ($filePath =~ m!\.docx$!i)    # old ".doc" is not supported
		{
		GetWordAsText($formH, $peeraddress, $fileContents_R);
		$$usingCM_R = 'false';
		$$meta_R    = '<meta http-equiv="content-type" content="text/html; charset=windows-1252">';
		$$textTableCSS_R = $cssForNonCmTables . $nonCmThemeCssFile;
		$$customCSS_R    = $cssForNonCm;
		}
	# 2. pure custom with TOC: pl, pm, pod, txt, log, bat, cgi, t.
	# OUT, switching to CodeMirror for Perl display.
	# elsif ($filePath =~ m!\.(p[lm]|cgi|t)$!i)
	# 	{
	# 	GetPrettyPerlFileContents($formH, $peeraddress, $clientIsRemote, $allowEditing,
	# 		$fileContents_R);
	# 	$$usingCM_R        = 'false';
	# 	$$textHolderName_R = 'scrollTextRightOfContents';
	# 	$$meta_R           = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
	# 	$$customCSS_R      = $cssForNonCm;
	# 	$$textTableCSS_R   = $cssForNonCmTables;
	# 	$$textTableCSS_R   = $cssForNonCmTables . $nonCmThemeCssFile;
	# 	}
	elsif ($filePath =~ m!\.pod$!i)
		{
		GetPrettyPod($formH, $peeraddress, $clientIsRemote, $allowEditing, $fileContents_R);
		$$usingCM_R        = 'false';
		$$textHolderName_R = 'scrollTextRightOfContents';
		$$meta_R           = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
		$$customCSS_R      = $cssForNonCm . "\n" . $cssForPod;
		$$textTableCSS_R   = $cssForNonCmTables . $nonCmThemeCssFile;
		}
	elsif ($filePath =~ m!\.(txt|log|bat)$!i)
		{
		# By default this runs the text through a Gloss processor.
		# So all your .txt files are belong to Gloss.
		GetPrettyTextContents($formH, $peeraddress, $clientIsRemote, $allowEditing,
			$fileContents_R, undef);

		$$usingCM_R        = 'false';
		$$textHolderName_R = 'scrollTextRightOfContents';
		$$meta_R           = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
		# Code block syntax highlighting with lolight,
		# and optional custom CSS, only for .txt files:
		if ($filePath =~ m!\.txt|$!)
			{
			$cssForNonCm .= "\n" . '<link rel="stylesheet" href="lolight_custom.css" />';
			$cssForNonCm .= OptionalCustomCSSforGloss();
			}
		$$customCSS_R    = $cssForNonCm;
		$$textTableCSS_R = $cssForNonCmTables . $nonCmThemeCssFile;
		}
	# 2.1 custom, no TOC: md (Markdown)
	elsif ($filePath =~ m!\.(md|mkd|markdown)$!i)
		{
		GetPrettyMD($formH, $peeraddress, $fileContents_R);
		$$usingCM_R = 'false';
		# IAdd a TOC
		$$textHolderName_R = 'scrollTextRightOfContents';
		$$meta_R           = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
		$cssForNonCm .= OptionalCustomCSSforMarkdown();
		$$customCSS_R    = $cssForMD . "\n" . $cssForNonCm;
		$$textTableCSS_R = $cssForNonCmTables . $nonCmThemeCssFile;
		}
	else
		{
		my $toc = '';
		GetCMToc($filePath, \$toc);
		if ($toc ne '')
			{
			# OUT
			#$toc               = decode_utf8($toc);
			$$textHolderName_R = 'scrollTextRightOfContents';
			$$meta_R      = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
			$$customCSS_R = $cssForCM . $nonCmThemeCssFile;
			$$fileContents_R = "<div id='scrollContentsList'>$toc</div>"
				. "<div id='scrollTextRightOfContents'></div>";
			}
		else
			{
			$$meta_R      = '<meta http-equiv="content-type" content="text/html; charset=utf-8">';
			$$customCSS_R = $cssForCM . $nonCmThemeCssFile;
			$$fileContents_R = "<div id='scrollText'></div>";
			}
		}
}

sub OptionalCustomCSSforGloss {
	my $result         = '';
	my $customFilePath = $CSS_DIR . 'im_gloss.css';
	if (FileOrDirExistsWide($customFilePath))
		{
		$result = "\n" . '<link rel="stylesheet" type="text/css" href="im_gloss.css" />' . "\n";
		}

	return ($result);
}

sub OptionalCustomJSforGloss {
	my $result         = '';
	my $customFilePath = $JS_DIR . 'im_gloss.js';
	if (FileOrDirExistsWide($customFilePath))
		{
		$result = "\n" . '<script src="im_gloss.js"></script>' . "\n";
		}

	return ($result);
}

sub OptionalCustomCSSforMarkdown {
	my $result         = '';
	my $customFilePath = $CSS_DIR . 'im_markdown.css';
	if (FileOrDirExistsWide($customFilePath))
		{
		$result = "\n" . '<link rel="stylesheet" type="text/css" href="im_markdown.css" />' . "\n";
		}

	return ($result);
}

sub OptionalCustomJSforMarkdown {
	my $result         = '';
	my $customFilePath = $JS_DIR . 'im_markdown.js';
	if (FileOrDirExistsWide($customFilePath))
		{
		$result = "\n" . '<script src="im_markdown.js"></script>' . "\n";
		}

	return ($result);
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
		;    # leave action empty
		}
	else
		{
		$result = <<'FINIS';
<a href='' onclick='editOpen("_FILEPATH_"); return false;'><input class="submit-button" type="submit" value="Edit" /></a>
FINIS

		my $encFilePath = $filePath;

		# Leave out my $encFilePath = encode_utf8($filePath);
		$encFilePath =~ s!\\!/!g;
		$encFilePath =~ s!^file\:///!!;
		# Leave out prob not needed $encFilePath = &HTML::Entities::encode($encFilePath);
		$result =~ s!_FILEPATH_!$encFilePath!;
		}

	return ($result);
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

	# Fix quotes.
	$searchItems =~ s!%22!"!g;
	# And spaces
	$searchItems =~ s!%20! !g;
	# And apostrophes.
	$searchItems =~ s!___APOSS___!'!g;    # See elasticsearcher.pm#FormatHitResults()

	if ($searchItems ne '')
		{
		my $forExactPhrase = ($searchItems =~ m!^\"!);
		# Fix up special characters such as ' __D_ '.
		DecodeSpecialNonWordCharacters(\$searchItems);
		$searchItems = lc($searchItems);
		$searchItems =~ s!\"!!g;
		my @items = split(/ +/, $searchItems);

		for (my $i = 0 ; $i < @items ; ++$i)
			{
			$items[$i] = encode_utf8($items[$i]);
			$items[$i] =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
			}

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
				if (length($searchItems) > 3)    # was 2
					{
					$highlightItems = "\"$searchItems\"";
					}
				}
			else
				{
				my $numItems = @items;
				my $numSoFar = 0;
				for (my $i = 0 ; $i < $numItems ; ++$i)
					{
					if (length($items[$i]) > 3)    # was 2
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
		$toggleHitsButton =
'<input onclick="toggleInitialSearchHits();" id="sihits" class="submit-button" type="submit" value="Hide Initial Hits" />';
		}

	return ($highlightItems, $toggleHitsButton);
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
	my $result =
'<input onclick="toggle();" id="togglehits" class="submit-button" type="submit" value="Toggle" />';
	return ($result);
}

sub InlineHoverButton {
	my ($filePath) = @_;
	my $result = '';
	if ($filePath !~ m!\.txt$!i)
		{
		return ($result);
		}
	$result =
'<input onclick="toggleImagesButton();" id="inlineImages" class="submit-button" type="submit" value="Inline Images" />';

	return ($result);
}

sub NonCodeMirrorThemeCSS {
	my ($themeName, $filePath) = @_;
	# If css file doesn't exist, return '';
	# Location is .../IntraMine/css_for_web_server/viewer_themes/$themeName.css
	my $cssPath = BaseDirectory() . 'css_for_web_server/viewer_themes/' . $themeName . '_IM.css';
	if (FileOrDirExistsWide($cssPath) != 1)
		{
		# TEST ONLY
		#print("ERROR could not find |$cssPath|\n");
		return ('');
		}

	my $imCssResult = "\n"
		. '<link rel="stylesheet" type="text/css"  href="/viewer_themes/'
		. $themeName
		. '_IM.css">' . "\n";

	# Perl left in here, but not used - CodeMirror is being used instead.
	my $perlCssResult = '';
	if ($filePath =~ m!\.(p[lm]|cgi|t)$!i)
		{
		my $perlCssPath =
			BaseDirectory() . 'css_for_web_server/viewer_themes/' . $themeName . '_Pl.css';
		if (FileOrDirExistsWide($perlCssPath) == 1)
			{
			$perlCssResult = "\n"
				. '<link rel="stylesheet" type="text/css"  href="/viewer_themes/'
				. $themeName
				. '_Pl.css">' . "\n";
			}
		}

	return ($imCssResult . $perlCssResult);
}

sub CodeMirrorThemeCSS {
	my $cssFiles = <<'FINIS';
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
FINIS

	return ($cssFiles);
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
<script src="addon/edit/matchbrackets.js"></script>

<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="restart_editor_viewer.js"></script>
<script src="topnav.js"></script>
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
<script src="indicator.js" ></script>
<script src="cmToggle.js" ></script>
<script src="cmScrollTOC.js" ></script>
<script src="dragTOC.js" ></script>
<script src="go2def.js" ></script>
<script src="viewer_auto_refresh.js" ></script>
<script src="cmHandlers.js" ></script>
FINIS

	return ($jsFiles);
}

# JavaScript for non-CodeMirror "custom" views (text, and a few others).
sub NonCodeMirrorJS {
	my $jsFiles = <<'FINIS';
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="restart_editor_viewer.js"></script>
<script src="topnav.js"></script>
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
<script src="go2def.js" ></script>
<script src="viewer_hover_inline_images.js" ></script>
<script>
hideSpinner();
</script>
FINIS

	return ($jsFiles);
}

# "req=loadfile" handling. For CodeMirror views, the text is loaded by JavaScript after the
# page starts up, see cmViewerStart.js#loadFileIntoCodeMirror().
sub LoadTheFile {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = '';

	my $filepath = defined($formH->{'file'}) ? $formH->{'file'} : '';
	if ($filepath ne '')
		{
		$filepath = &HTML::Entities::decode($filepath);

		$result = uri_escape_utf8(ReadTextFileDecodedWide($filepath));

		if ($result eq '' && FileOrDirExistsWide($filepath) == 1)
			{
			$result = '___THIS_IS_ACTUALLY_AN_EMPTY_FILE___';
			}
		}

	return ($result);
}

# Open a directory link using Windows File Explorer.
sub OpenDirectory {
	my ($obj, $formH, $peeraddress) = @_;
	my $result  = 'OK';
	my $dirPath = defined($formH->{'dir'}) ? $formH->{'dir'} : '';
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

	return ($result);
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
	my $line  = '';
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
	my $serverAddr   = ServerAddress();

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
	# Microsoft Edge is fine, tho it doesn't show <title>. Chrome just plain won't do it directly,
	# probably another "you don't have a clue what you're doing, let us protect you" issue.
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

# Obsolete, CodeMirror is being used now for Perl display.
# Table Of Contents (TOC) on the left, highlighted Perl on the right.
# Syntax::Highlight::Perl::Improved does the formatting.
# Autolinks are added for source and text files, web addresses, and images.
# "use Package::Module;" is given a local link and a link to metacpan.
# sub GetPrettyPerlFileContents {
# 	my ($formH, $peeraddress, $clientIsRemote, $allowEditing, $contentsR) = @_;
# 	my $filePath   = $formH->{'FULLPATH'};
# 	my $dir        = lc(DirectoryFromPathTS($filePath));
# 	my $serverAddr = ServerAddress();
# 	$$contentsR = "";

# 	my $octets;
# 	if (!LoadPerlFileContents($filePath, $contentsR, \$octets))
# 		{
# 		return;
# 		}

# 	my @lines = split(/\n/, $octets);

# 	# Put in line numbers etc.
# 	my @jumpList;
# 	my @subNames;
# 	my @sectionList;
# 	my @sectionNames;
# 	my $lineNum = 1;
# 	my %sectionIdExists;    # used to avoid duplicated anchor id's for sections.
# 	my $braceDepth = 0;     # Valid depth >= 1, 0 means not inside any {}

# 	for (my $i = 0 ; $i < @lines ; ++$i)
# 		{
# 		# Put subs etc in TOC, with links.
# 		# Links for subs are moved up to the first comment that goes with the sub.
# 		# <span class='line_number'>204</span>&nbsp;<span class='Keyword'>sub</span> <span class='Subroutine'>
# 		# And also <span class='String'>sub Subname {</span>, since the parser breaks
# 		# if it encounters '//' sometimes.
# 		# TODO support "method" and "my method"? (Requires new parser I suspect.)
# 		if ($lines[$i] =~
# m!^\<span\s+class=['"]Keyword['"]\>\s*sub\s*\<\/span\>\s*\<span\s+class=['"]Subroutine['"]\>(\w+)\<\/span\>!
# 			|| $lines[$i] =~ m!^<span\s+class=['"]String['"]>\s*sub\s+(\w+)!)
# 			{
# 			# Use $subName as the $id
# 			my $subName = $1;
# 			my $id      = $subName;
# 			$sectionIdExists{$id} = 1;
# 			my $contentsClass = 'h2';
# 			my $jlStart       = "<li class='$contentsClass' im-text-ln='$lineNum'><a href='#$id'>";
# 			my $jlEnd         = "</a></li>";
# 			my $destAnchorStart  = "<span id='$id'>";
# 			my $destAnchorEnd    = "</span>";
# 			my $displayedSubName = $subName;
# 			push @jumpList, $jlStart . $s_icon . $displayedSubName . '()' . $jlEnd;
# 			push @subNames, $subName;
# 			my $anki = $i;
# 			# Look for highest comment above sub.
# 			if (
# 				$i > 0
# 				&& ($lines[$i - 1] =~
# 					m!^<tr id='R\d+'><td[^>]+></td><td><span\s+class='Comment_Normal'>!)
# 				)
# 				{
# 				$anki = $i - 1;
# 				my $testi = $i - 2;
# 				while ($testi > 0
# 					&& $lines[$testi] =~
# 					m!^<tr id='R\d+'><td[^>]+></td><td><span\s+class='Comment_Normal'>!)
# 					{
# 					$anki = $testi;
# 					--$testi;
# 					}
# 				}
# 			if ($anki == $i)
# 				{
# 				$lines[$i] =~ s!$subName!$destAnchorStart$subName$destAnchorEnd!;
# 				}
# 			else
# 				{
# 				$lines[$anki] =~ s!\#!$destAnchorStart\#$destAnchorEnd!;
# 				}
# 			}
# 		# "Sub-modules" - top level { ## Description \n code...}
# 		elsif ($lines[$i] =~
# m!\<span\s+class=\'Symbol\'\>\{\<\/span>\s*\<span\s+class=\'Comment_Normal\'\>##+\s+(.+?)\<\/span\>!
# 			)
# 			{
# 			# Use section_name_with_underscores_instead_of_spaces as the $id, unless it's a duplicate.
# 			# Eg intramine_main_3.pl#Drive_list
# 			my $sectionName = $1;
# 			my $id          = $sectionName;
# 			$id =~ s!\s+!_!g;
# 			if (defined($sectionIdExists{$id}))
# 				{
# 				my $anchorNumber = @sectionList;
# 				$id = "hdr_$anchorNumber";
# 				}
# 			$sectionIdExists{$id} = 1;
# 			my $contentsClass = 'h2';
# 			my $jlStart =
# 				"<li class='$contentsClass' im-text-ln='$lineNum'><a href='#$id'><strong>";
# 			my $jlEnd           = "</strong></a></li>";
# 			my $destAnchorStart = "<span id='$id'>";
# 			my $destAnchorEnd   = "</span>";
# 			push @sectionList,  $jlStart . $S_icon . $sectionName . $jlEnd;
# 			push @sectionNames, $sectionName;
# 			$lines[$i] =~ s!$sectionName!$destAnchorStart$sectionName$destAnchorEnd!;
# 			}

# 		# Curly brace tracking
# 		while ($lines[$i] =~ m!<span class=['"]Symbol['"]>([{}])</span>!)
# 			{
# 			my $brace      = $1;
# 			my $braceClass = '';
# 			if ($brace eq '{')
# 				{
# 				++$braceDepth;
# 				$braceClass = 'b-' . $braceDepth;
# 				}
# 			else    # '}'
# 				{
# 				$braceClass = 'b-' . $braceDepth;
# 				--$braceDepth;
# 				}

# 			$lines[$i] =~
# s!<span class=['"]Symbol['"]>[{}]</span>!<span class='Symbol $braceClass'>$brace</span>!;
# 			}
# 		# mini MultiMarkdown:
# 		$lines[$i] =~ s!(^|[ #/])(TODO)!$1<span class='notabene'>$2</span>!;
# 		$lines[$i] =~ s!(REMINDER|NOTE)!<span class='notabene'>$1</span>!;

# 		my $rowID = 'R' . $lineNum;
# 		$lines[$i] = "<tr id='$rowID'><td n='$lineNum'></td><td>" . $lines[$i] . '</td></tr>';
# 		++$lineNum;
# 		}

# 	# Add internal links to Perl files.
# 	# Put in links that reference Table Of Contents entries within the current document.
# 	for (my $i = 0 ; $i < @lines ; ++$i)
# 		{
# 		AddInternalLinksToPerlLine(\${lines [$i]}, \%sectionIdExists);
# 		}

# 	my $topSpan = '';
# 	if (defined($lines[0]))
# 		{
# 		$topSpan = "<span id='top-of-document'></span>";
# 		}
# 	my @idx = sort {$subNames[$a] cmp $subNames[$b]} 0 .. $#subNames;
# 	@jumpList    = @jumpList[@idx];
# 	@idx         = sort {$sectionNames[$a] cmp $sectionNames[$b]} 0 .. $#sectionNames;
# 	@sectionList = @sectionList[@idx];
# 	my $numSectionEntries = @sectionList;
# 	my $sectionBreak      = ($numSectionEntries > 0) ? '<br>' : '';
# 	$$contentsR .=
# 		  "<div id='scrollContentsList'>"
# 		. "<ul>\n<li class='h2' im-text-ln='1'><a href='#top-of-document'>TOP</a></li>\n"
# 		. join("\n", @sectionList)
# 		. $sectionBreak
# 		. join("\n", @jumpList)
# 		. '</ul></div>' . "\n";
# 	$$contentsR .=
# 		  "<div id='scrollTextRightOfContents'>$topSpan<table><tbody>"
# 		. join("\n", @lines)
# 		. '</tbody></table></div>';

# 	$$contentsR = encode_utf8($$contentsR);
# }

# Markdown.
sub GetPrettyMD {
	my ($formH, $peeraddress, $contentsR) = @_;
	my $filePath   = $formH->{'FULLPATH'};
	my $dir        = lc(DirectoryFromPathTS($filePath));
	my $serverAddr = ServerAddress();
	$$contentsR = "";    #"<hr />";

	# TEST ONLY
	#my $t1 = time;

	my $octets;
	if (!LoadTextFileContents($filePath, $contentsR, \$octets))
		{
		return;
		}

	# Turn GitHub-sourced images of the form
	# ![..](...)
	# into
	# ![..](...?raw=true).
	my @lines = split(/\n/, $octets);
	for (my $i = 0 ; $i < @lines ; ++$i)
		{
		if ($lines[$i] =~ m!\!\[[^\]]+]\([^)]+\)!)
			{
			$lines[$i] =~ s!(\!\[[^\]]+]\([^)]+)\)!$1\?raw\=true\)!;
			}
		}
	$octets = join("\n", @lines);

	my $m = Text::MultiMarkdown->new(
		empty_element_suffix => '>',
		tab_width            => 4,
		use_wikilinks        => 0,
	);
	my $html = $m->markdown($octets);

	my $toc = '';
	GetTOCFromMarkdownHTML(\$html, \$toc);

	$$contentsR .= "<div id='scrollContentsList'>" . $toc . "</div>";

	my $bottomShim = "<p id='bottomShim'></p>";
	$$contentsR .= "<div id='scrollTextRightOfContents'>" . $html . "$bottomShim</div>";

	$$contentsR = encode_utf8($$contentsR);

	# TEST ONLY
	# my $elapsed = time - $t1;
	# my $ruffElapsed = substr($elapsed, 0, 6);
	# Monitor("Load time for $filePath: $ruffElapsed seconds");
	# Result: worst case 0.6 seconds per 1,000 lines, acceptable.
	# Call it 2,000 lines per second.
}

# An experiment, abandoned.
sub xMakeCmarksForFile {
	my ($filePath, $dir) = @_;
	my $cmark_dir    = FullDirectoryPath('CMARK_DIR');
	my $cmarkEXE     = $cmark_dir . 'cmark.exe';
	my $tempFilePath = '';
	my $tempDir      = '';
	#my $proc;
	my $outputFileBase = $LogDir . 'temp/cmark';
	my $randomInteger  = random_int_between(1001, 60000);
	my $outputFilePath = $outputFileBase . $port_listen . time . $randomInteger . '.html';
	my $file           = "output.txt";
	my $didit;

	# Run a .bat filel to call Pandoc.
	$didit = RunPandocViaBat($filePath, $outputFilePath);

	# Run a .bat file to call cmark. OUT, doesn't do tables or headers
	### $didit = RunCmarkViaBat($filePath, $outputFilePath);

	if (!$didit)
		{
		my $status = Win32::FormatMessage(Win32::GetLastError());
		Monitor("MakeCtagsForFile Error |$status|, could not run $cmarkEXE!");
		return ('');
		}

	return ($outputFilePath);

	# Can't get STDIN redirected, giving up on this approach.
	# {
	# open my $oldin, '<&', \*STDIN or (return(ErrorOnRedirect('OLDIN', $filePath, $1)));
	# open my $oldout, '>&', \*STDOUT or (return(ErrorOnRedirect('OLDOUT', $filePath, $1)));
	# close STDIN;
	# open(STDIN, '<', '$filePath') or (return(ErrorOnRedirect('IN', $filePath, $1)));
	# close STDOUT;
	# open(STDOUT, '>', '$outputFilePath') or (return(ErrorOnRedirect('OUT', $filePath, $1)));

	# $didit =  Win32::Process::Create($proc, $cmarkEXE, " -t html", 0, 0, $dir);

	# # Is '&' right? Try leaving out: no difference.
	# close STDIN;
	# open STDIN, '<&', $oldin or (return(ErrorOnRedirect('RESTOREIN', $filePath, $1)));
	# close $oldin;
	# close STDOUT;
	# open STDOUT, '<&', $oldout or (return(ErrorOnRedirect('RESTOREOUT', $filePath, $1)));
	# close $oldout;
	# }

	# if (!$didit)
	# 	{
	# 	my $status = Win32::FormatMessage( Win32::GetLastError() );
	# 	Monitor("MakeCtagsForFile Error |$status|, could not run $cmarkEXE!");
	# 	return('');
	# 	}

	# while (defined($proc))
	# 	{
	# 	usleep(100000); # 0.1 seconds
	# 	}

	# return($outputFilePath);
}

sub ErrorOnRedirect {
	my ($action, $path, $err) = @_;
	Monitor("Error $action $path: |$err|");
	return ('');
}

sub RunPandocViaBat {
	my ($filePath, $outputFilePath) = @_;
	my $outputFileBase = $LogDir . 'temp/cmark';
	my $randomInteger  = random_int_between(1001, 60000);
	my $batPath = $outputFileBase . 'tempbat' . $port_listen . '_' . time . $randomInteger . '.bat';
	my $cmark_dir = FullDirectoryPath('CMARK_DIR');
	my $pandocEXE = "P:/temp/pandoc-3.7.0.1-windows-x86_64/pandoc-3.7.0.1/pandoc.exe";

	MakeDirectoriesForFile($batPath);

	my $outFileH = FileHandle->new("> $batPath")
		or return (BatError("FILE ERROR could not make |$batPath|!"));
	### TEMP PUT binmode($outFileH, ":utf8");
	### TEMP OUT print $outFileH "chcp 65001\n";
	print $outFileH '@echo off' . "\n";
	print $outFileH "\"$pandocEXE\" -f markdown_mmd -t html5 <\"$filePath\" >\"$outputFilePath\"\n";
	print $outFileH 'exit /b' . "\n";

	# Self-destruct.
	# TEMP OUT print $outFileH "del \"%~f0\"\n";
	close($outFileH);

	# Run the bat.
	my $proc;
	my $status = 'OK';

	Win32::Process::Create($proc, $ENV{COMSPEC}, "/c $batPath", 0, 0, ".")
		|| ($status = 'bad');
	if ($status ne 'OK')
		{
		return (0);
		}

	# TEST ONLY
	print("Create status OK.\n");

	my $breaker = 0;
	while (defined($proc) && ++$breaker <= 50)
		{
		usleep(100000);    # 0.1 seconds
						   # TEST ONLY
		Monitor("breaker $breaker");
		}

	### TEMP OUT unlink($batPath); DO NOT CALL if there's a del above

	return (1);
}

sub RunCmarkViaBat {
	my ($filePath, $outputFilePath) = @_;
	my $outputFileBase = $LogDir . 'temp/cmark';
	my $randomInteger  = random_int_between(1001, 60000);
	my $batPath = $outputFileBase . 'tempbat' . $port_listen . '_' . time . $randomInteger . '.bat';
	my $cmark_dir = FullDirectoryPath('CMARK_DIR');
	my $cmarkEXE  = $cmark_dir . 'cmark.exe';

	MakeDirectoriesForFile($batPath);

	my $outFileH = FileHandle->new("> $batPath")
		or return (BatError("FILE ERROR could not make |$batPath|!"));
	### TEMP OUT binmode($outFileH, ":utf8");
	### TEMP OUT print $outFileH "chcp 65001\n";
	print $outFileH '@echo off' . "\n";
	print $outFileH "\"$cmarkEXE\" <\"$filePath\" >\"$outputFilePath\"\n";
	print $outFileH 'exit /b' . "\n";

	# Self-destruct.
	# TEMP OUT print $outFileH "del \"%~f0\"\n";
	close($outFileH);

	# Run the bat.
	my $proc;
	my $status = 'OK';

	Win32::Process::Create($proc, $ENV{COMSPEC}, "/c $batPath", 0, 0, ".")
		|| ($status = 'bad');
	if ($status ne 'OK')
		{
		return (0);
		}

	# TEST ONLY
	print("Create status OK.\n");

	my $breaker = 0;
	while (defined($proc) && ++$breaker <= 10)
		{
		usleep(100000);    # 0.1 seconds
		}

	### TEMP OUT unlink($batPath); DO NOT CALL if there's a del above

	return (1);
}

sub BatError {
	my ($msg) = @_;
	Monitor($msg);
	return (0);
}

sub GetTOCFromMarkdownHTML {
	my ($htmlR, $tocR) = @_;
	$$tocR = "<ul>\n";
	my $text     = $$htmlR;
	my @lines    = split(/\n/, $text);
	my $numLines = @lines;
	my @tocEntries;

	# Looking for lines like
	# <h2 id="intraminesservices">IntraMine's services</h2>
	my $lineNum = 1;
	for (my $i = 0 ; $i < $numLines ; ++$i)
		{
		if ($lines[$i] =~ m!^<h(\d)\s+id="([^"]+)">([^<]+)<!)
			{
			my $headerLevel   = $1;
			my $id            = $2;
			my $headerText    = $3;
			my $contentsClass = 'h' . $headerLevel;
			my $jumper =
"<li class='$contentsClass'><a onclick=\"mdJump('$id', '$lineNum');\">$headerText</a></li>";
			push @tocEntries, $jumper;
			}
		++$lineNum;
		}

	$$tocR .= join("\n", @tocEntries);
	$$tocR .= "</ul>\n";
}

# NOT FINISHED, doesn't handle lists (among other things probably).
sub AddLineNumbersToMarkdown {
	my ($htmlR) = @_;
	my $text = $$htmlR;

	# Split into lines.
	my @lines = split(/\n/, $text);
	# Add table rows, except within an existing table.
	my $lineNum     = 1;
	my $numLines    = @lines;
	my $inATable    = 0;        # Avoid putting tables in tables.
	my $inMainTable = 0;
	for (my $i = 0 ; $i < $numLines ; ++$i)
		{
		if (index($lines[$i], '<table>') == 0)
			{
			$inATable = 1;
			if ($inMainTable)
				{
				$lines[$i] = '</table>' . $lines[$i];
				$inMainTable = 0;
				}
			}
		elsif (index($lines[$i], '</table>') == 0)
			{
			$lines[$i]   = $lines[$i] . '<table>';
			$inATable    = 0;
			$inMainTable = 1;
			}
		elsif ($inATable)
			{
			;    # Experiment, try doing nothing
			}
		else
			{
			if (!$inMainTable)
				{
				$lines[$i] = '<table>' . $lines[$i];
				$inMainTable = 1;
				}
			my $rowID = 'R' . $lineNum;
			$lines[$i] = "<tr id='$rowID'><td n='$lineNum'></td><td>" . $lines[$i] . '</td></tr>';
			}

		++$lineNum;
		}

	$$htmlR = join("\n", @lines);
}

# Call LoadPodFileContents() to get an HTML version using Pod::Simple::HTML,
# then use html2gloss.pm to convert that to Gloss.
# Finally, pass that through GetPrettyTextFileContents() to convert the
# Gloss text to HTML for display. Whew.
sub GetPrettyPod {
	my ($formH, $peeraddress, $clientIsRemote, $allowEditing, $contentsR) = @_;
	my $filePath   = $formH->{'FULLPATH'};
	my $dir        = lc(DirectoryFromPathTS($filePath));
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
	GetPrettyTextContents($formH, $peeraddress, $clientIsRemote, $allowEditing, $contentsR,
		\$contentsInrawGloss);
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
	my $dir      = lc(DirectoryFromPathTS($filePath));
	$$contentsR = "";    # "<hr />";

	# glossary files get a table of contents listing glossary terms,
	# in alphabetical order.
	my $isGlossaryFile = 0;
	if ($filePath =~ m![\\/]$GLOSSARYFILENAME$!i || $filePath =~ m![\\/]glossary.txt$!i)
		{
		$isGlossaryFile = 1;
		}

	my $doingPOD = 0;
	my $inPre    = 0;    # POD only, are we in a <pre> element?
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

	# Pull raw (inline) HTML and footnotes.
	$octets = ReplaceHTMLAndFootnoteswithKeys($octets);

	# Preserve consecutive blank lines at bottom.
	$octets .= "\nx";
	my @lines = split(/\n/, $octets);
	pop @lines;

	my @jumpList;
	my $lineNum = 1;
	my %sectionIdExists;           # used to avoid duplicated anchor id's for sections.
	my $orderedListNum     = 0;
	my $secondOrderListNum = 0;
	my $unorderedListDepth = 0;    # 0 1 2 for no list, top level, second level.
	my $justDidHeadingOrHr = 0;
	# Rev May 14 2021, track whether within TABLE, and skip lists, hr, and heading if so.
	# We are in a table from a line that starts with TABLE|[_ \t:.-]? until a line with no tabs.
	my $inATable     = 0;
	my $inACodeBlock = 0;        # Set if see CODE on a line by itself,
								 # continue until ENDCODE on a line by itself.
	my $numLines     = @lines;

	# Well I've put myself in a pickle by supporting ^#+ to signal headings.
	# IntraMine's own intramine_config.txt starts lines with # to indicate comments.
	# There is no great fix for that. But we check the first 20 lines here, and
	# if enough start with # then turn off octothorpe headings. Also turn off if
	# we same the same number of hashes on two consecutive lines. Later, we require
	# a blank line before a heading and a space between '#' and the heading text.
	my $allowOctothorpeHeadings = 1;    # Whether to do ## Markdown headings
	my $numOctos                = 0;    # Too many means probably not headings
	my $lineIsBlank             = 1;
	my $lineBeforeIsBlank       = 1;    # Initally there is no line before, so it's kinda blank:)
	my $linesToCheck            = 20;
	my $hasSameHashesInARow     = 0;    # Consecutive # or ## etc means not headings
	my $previousHashesCount     = 0;
	if ($linesToCheck > $numLines)
		{
		$linesToCheck = $numLines;
		}
	if ($linesToCheck)
		{
		for (my $i = 0 ; $i < $linesToCheck ; ++$i)
			{
			if (index($lines[$i], '#') == 0)
				{
				++$numOctos;
				$lines[$i] =~ m!^(#+)!;
				my $startHashes        = $1;
				my $currentHashesCount = length($startHashes);
				if ($currentHashesCount == $previousHashesCount)
					{
					$hasSameHashesInARow = 1;
					}
				$previousHashesCount = $currentHashesCount;
				}
			else
				{
				$previousHashesCount = 0;
				}
			}
		my $headingRatio = $numOctos / ($linesToCheck + 0.0);
		# .25 is admittedly somewhat arbitrary and untested.
		if ($headingRatio > .25 || $hasSameHashesInARow)
			{
			$allowOctothorpeHeadings = 0;
			}
		}

	# Gloss, aka minimal Markdown.
	my $inlineIndex = 1;    # Key numbers start at 1.

	for (my $i = 0 ; $i < $numLines ; ++$i)
		{
		# Turn GitHub-sourced images of the form
		# ![..](...)
		# into
		# ![..](...?raw=true). They don't display,
		# but at least the link works.
		if ($lines[$i] =~ m!\!\[[^\]]+]\([^)]+\)!)
			{
			$lines[$i] =~ s!(\!\[[^\]]+]\([^)]+)\)!$1\?raw\=true\)!;
			}

		# Skip raw HTML markers, adjust line count.
		# __HH__ . $index . '_L_' . $lineCount
		if (index($lines[$i], '__HH__') == 0)
			{
			my $lpos = -1;
			if (($lpos = index($lines[$i], '_L_')) > 0)
				{
				# Require $index to be in strict sequence. This
				# reduces errors caused by user entering a line
				# that mimics an __HH__ line used for inline HTML
				# removal and subsequent replacement.
				my $fullKey = substr($lines[$i], 0, $lpos);
				my $index   = substr($fullKey,   6);    # 6 == length('__HH__')
				if (   $index =~ m!^\d+$!
					&& $index == $inlineIndex
					&& InlineHTMLKeyIsDefined($fullKey))
					{
					++$inlineIndex;
					my $lineCount = substr($lines[$i], $lpos + 3);
					$lineNum += $lineCount;
					next;
					}
				}
			}

		# Blank out footnote markers and adjust line count
		if (index($lines[$i], '__FN__') == 0)
			{
			my $lpos = -1;
			my $rpos = -1;
			if (   ($lpos = index($lines[$i], '_L_')) > 0
				&& ($rpos = index($lines[$i], '_IND_')) > $lpos
				&& FootNoteIsDefined($lines[$i]))
				{
				$lpos += 3;
				my $lineCount = substr($lines[$i], $lpos, $rpos - $lpos);
				$lineNum += $lineCount;
				$lines[$i] = '';
				next;
				}
			}

		$lineBeforeIsBlank = $lineIsBlank;
		if ($lines[$i] eq '')
			{
			$lineIsBlank = 1;
			}
		else
			{
			$lineIsBlank = 0;
			}

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
				if ($lines[$i] eq '')
					{
					$lines[$i] = '_STARTCB_ ' . $lines[$i];
					}
				else
					{
					$lines[$i] = '_STARTCB_' . $lines[$i];
					}
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
				# Hashed heading eg ## Heading. Require blank line before # heading
				# (or first line).
				if (   $allowOctothorpeHeadings
					&& $lines[$i] =~ m!^#+\s+!
					&& ($lineBeforeIsBlank || !$HashHeadingRequireBlankBefore))
					{
					Heading(\$lines[$i], undef, undef, \@jumpList, $i, \%sectionIdExists);
					$justDidHeadingOrHr = 1;
					}
				# Underlines -> hr or heading. Heading requires altering line before underline.
				elsif ($i > 0 && $lines[$i] =~ m!^[=~-][=~-]([=~-]+)$!)
					{
					my $underline = $1;
					if (length($underline) <= 2)    # ie three or four total
						{
						HorizontalRule(\$lines[$i], $lineNum, $indentClass);
						}
					elsif ($justDidHeadingOrHr ==
						0)    # a heading - put in anchor and add to jump list too
						{
						Heading(\$lines[$i], \$lines[$i - 1],
							$underline, \@jumpList, $i, \%sectionIdExists);
						}
					else      # treat like any ordinary line
						{
						my $rowID = 'R' . $lineNum;
						$lines[$i] =
							  "<tr id='$rowID'><td n='$lineNum'></td><td>"
							. $lines[$i]
							. '</td></tr>';
						}
					$justDidHeadingOrHr = 1;
					}
				# Anchors, gotta put them in all the way down so links to them work.
				elsif (index($lines[$i], '_ALB_') >= 0)
					{
					Anchor(\$lines[$i]);
					my $rowID     = 'R' . $lineNum;
					my $classAttr = ClassAttribute('', $indentClass);
					$lines[$i] =
						  "<tr id='$rowID'><td n='$lineNum'></td><td$classAttr>"
						. $lines[$i]
						. '</td></tr>';
					$justDidHeadingOrHr = 0;
					}
				else    # Pick up glossary TOC entries, treat like any ordinary line
					{
					if ($isGlossaryFile)
						{
						if ($lines[$i] =~ m!^\s*(.+?[^\\]):!)
							#if ($lines[$i] =~ m!^([^:]+)\:!)
							{
							my $term          = $1;
							my $anchorText    = lc(AnchorForGlossaryTerm($term));
							my $contentsClass = 'h2';
							my $jlStart =
"<li class='$contentsClass' im-text-ln='$lineNum'><a href='#$anchorText'>";
							my $jlEnd = "</a></li>";
							push @jumpList, $jlStart . $term . $jlEnd;
							}
						# For display, remove '\' from '\:'.
						# ARG too soon! See AddGlossaryAnchor().
						#$lines[$i] =~ s!\\:!:!g;
						}

					my $rowID     = 'R' . $lineNum;
					my $classAttr = ClassAttribute('', $indentClass);
					$lines[$i] =
						  "<tr id='$rowID'><td n='$lineNum'></td><td$classAttr>"
						. $lines[$i]
						. '</td></tr>';
					$justDidHeadingOrHr = 0;
					}
				}
			}
		else    # In a table, nothing special done yet - see just below, PutTablesInText().
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

	# Gutter diff marks,
	#my $numLines         = @lines;
	my @changedLines     = (0) x ($numLines + 1);
	my @lineTypes        = (0) x ($numLines + 1);
	my $haveChangedLines = GetChangedLinesArray($filePath, \@changedLines, \@lineTypes);
	my $diffMouseHandlers =
"onclick='diffMarkerClicked(event)' onmouseover='overDiffMarker(event)' onmouseout='outOfDiffMarker(event)'";

	if (!$isGlossaryFile)
		{
		# Put in internal links that reference headers within the current document.

		#PutChangedArrayInPageSource();

		for (my $i = 0 ; $i < @lines ; ++$i)
			{
			AddInternalLinksToLine(\${lines [$i]}, \%sectionIdExists);

			if ($haveChangedLines)
				{
				my $lineNumber = $i + 1;
				# Put git diff HEAD change markers in the line numbers.
				if ($changedLines[$lineNumber] != 0)
					{
					my $spacer = '';
					if ($lineNumber < 10)
						{
						$spacer = '   ';
						}
					elsif ($lineNumber < 100)
						{
						$spacer = '  ';
						}
					elsif ($lineNumber < 1000)
						{
						$spacer = ' ';
						}
					my $lineType = $lineTypes[$lineNumber];
					if ($lineType eq 'N')    # New/changed
						{
						$lines[$i] =~
							s!<td\s+n=['"](\d+)['"]!<td n='$1$spacer|' $diffMouseHandlers!;
						}
					elsif ($lineType eq 'D')    # Deleted
						{
						$lines[$i] =~
							s!<td\s+n=['"](\d+)['"]!<td n='$1$spacer▸' $diffMouseHandlers!;
						}
					}
				}
			}
		}
	else    # a glossary file, add anchors (well id's actually).
		{
		for (my $i = 0 ; $i < @lines ; ++$i)
			{
			AddGlossaryAnchor(\${lines [$i]});

			if ($haveChangedLines)
				{
				my $lineNumber = $i + 1;
				# Put git diff HEAD change markers in the line numbers.
				if ($changedLines[$lineNumber] != 0)
					{
					my $spacer = '';
					if ($lineNumber < 10)
						{
						$spacer = '   ';
						}
					elsif ($lineNumber < 100)
						{
						$spacer = '  ';
						}
					elsif ($lineNumber < 1000)
						{
						$spacer = ' ';
						}
					my $lineType = $lineTypes[$lineNumber];
					if ($lineType eq 'N')    # New/changed
						{
						$lines[$i] =~
							s!<td\s+n=['"](\d+)['"]!<td n='$1$spacer|' $diffMouseHandlers!;
						}
					elsif ($lineType eq 'D')    # Deleted
						{
						$lines[$i] =~
							s!<td\s+n=['"](\d+)['"]!<td n='$1$spacer▸' $diffMouseHandlers!;
						}
					}
				}
			}
		}

	# Assemble the table of contents and text.
	# Special treatment (optional) for an contents.txt file with "contents" as the first line;
	# Style it up somewhat to more resemble a proper (old-fashioned) Table Of Contents.
	if (IsSpecialIndexFile($filePath, \@lines))
		{
		MakeSpecialIndexFileLookSpecial(\@lines);
		my $specialImageBackgroundImage = CVal('SPECIAL_INDEX_BACKGROUND');
		$$contentsR .=
"<div id='specialScrollTextRightOfContents' style='background-image: url(\"$specialImageBackgroundImage\");'><div id='special-index-wrapper'><table><tbody>"
			. join("\n", @lines)
			. '</tbody></table></div></div>';
		}
	else
		{
		# As a special exception, glossary TOC entries are sorted alphabetically
		# rather than in order of occurrence.
		if ($isGlossaryFile)
			{
			@jumpList = sort TocSort @jumpList;
			}

		unshift @jumpList, "<li class='h2' im-text-ln='1'><a href='#top-of-document'>TOP</a></li>";
		unshift @jumpList, "<ul>";
		$$contentsR .= "<div id='scrollContentsList'>" . join("\n", @jumpList) . '</ul></div>';
		my $bottomShim = "<p id='bottomShim'></p>";

		# Replace raw HTML placeholders with original HTML. Add footnotes.
		ReplaceKeysWithHTMLAndFootnotes(\@lines, $numLines, $filePath);

		my $topSpan = '';
		if (defined($lines[0]))
			{
			$topSpan = "<span id='top-of-document'></span>";
			}

		$$contentsR .=
			  "<div id='scrollTextRightOfContents'>$topSpan<table class='imt'><tbody>"
			. join("\n", @lines)
			. "</tbody></table>$bottomShim</div>";
		}

	if (!defined($sourceR))
		{
		$$contentsR = encode_utf8($$contentsR);
		}
}

{ ##### git diff HEAD changed lines for .txt Views, array for JavaScript
my @DiffChangedLinesForJS;

sub InitDiffChangedLinesForJS {
	@DiffChangedLinesForJS = ();
}

sub JsDiffChangedLinesEntry {
	my $result     = "";
	my $numEntries = @DiffChangedLinesForJS;
	if ($numEntries)
		{
		for (my $i = 0 ; $i < $numEntries ; ++$i)
			{
			$DiffChangedLinesForJS[$i] = "'$DiffChangedLinesForJS[$i]'";
			}
		$result = join(",", @DiffChangedLinesForJS);
		}

	return ($result);
}

sub GetChangedLinesArray {
	my ($path, $changedLinesA, $lineTypesA) = @_;
	my $haveChanges = 0;
	$path =~ s!\\!/!g;
	# This is important, git relative path is cAsE sEnsITiVe (true).
	my $properPath = Win32::GetLongPathName($path);
	if (defined($properPath) && $properPath ne '')
		{
		$path = $properPath;
		}
	$path =~ s!\\!/!g;
	my $gitDir = GetGitDirectoryFromPath($path);
	if ($gitDir eq "")
		{
		return;
		}

	my $relativePath = substr($path, length($gitDir) + 1);
	chdir($gitDir);
	my $gitCmd = "git diff HEAD -- \"$relativePath\" 2>NUL";

	# Call git for a list of differences between current saved version
	# and last committed version. Note git might not even be installed.
	my $diffs = `$gitCmd`;

	my $shortDiff = "";
	if ($diffs ne '')
		{
		$shortDiff = substr($diffs, 0, 30);
		}

	# print("\$gitDir: |$gitDir|\n");
	# print("\$relativePath: |$relativePath|\n");
	# print("Diffs for $path: |$shortDiff|\n");
	# my $currentDir = Cwd::cwd();
	# print "Current wd: |$currentDir|\n";

	if ($diffs ne '')
		{
		my @changedLineNumbers;
		my @lineTypes;
		GetLineNumbersForChangedLines($diffs, \@changedLineNumbers, \@lineTypes);
		my $numLineNumbers = @changedLineNumbers;
		if ($numLineNumbers)
			{
			# Fill @DiffChangedLinesForJS with zeroes.
			@DiffChangedLinesForJS = @$changedLinesA;

			$haveChanges = 1;
			for (my $i = 0 ; $i < $numLineNumbers ; ++$i)
				{
				my $testNum = $changedLineNumbers[$i];
				$changedLinesA->[$testNum]       = $changedLineNumbers[$i];
				$lineTypesA->[$testNum]          = $lineTypes[$i];
				$DiffChangedLinesForJS[$testNum] = $lineTypes[$i] . $changedLineNumbers[$i];
				}
			}
		}

	return ($haveChanges);
}
}    ##### git diff HEAD changed lines for .txt Views, array for JavaScript

sub GetGitDirectoryFromPath {
	my ($filePath) = @_;
	my $copyPath   = $filePath;
	my $result     = '';
	$copyPath =~ s!\\!/!g;
	my $slashPos = rindex($filePath, "/");
	while ($slashPos > 0)
		{
		my $testDir = substr($filePath, 0, $slashPos + 1) . '.git';
		if (FileOrDirExistsWide($testDir) == 2)
			{
			$result = substr($filePath, 0, $slashPos);
			last;
			}
		$slashPos = rindex($filePath, "/", $slashPos - 1);
		}

	return ($result);
}

# An extra character is added to the start of the line number:
# N: new/changed
# D: deleted
# C: context
sub GetLineNumbersForChangedLines {
	my ($diffs, $changedLineNumsArr, $lineTypesArr) = @_;
	my @lines               = split(/\n/, $diffs);
	my $atatLineStart       = -1;
	my $plusSeen            = 0;
	my $negSeen             = 0;
	my $negLine             = 0;
	my $consecutiveNegCount = 0;
	my $numLines            = @lines;
	my $line                = '';

	for (my $i = 0 ; $i < $numLines ; ++$i)
		{
		my $line = $lines[$i];
		# Eg @@ -27,7 +27,7 @@...
		# or @@ -665,8 +668,15
		if (index($line, '@@') == 0 && $line =~ m!^@@\s+\-\d+,\d+\s+\+(\d+),(\d+)!)
			{
			# Push any neg line if saw neg but no positive.
			if ($negSeen && !$plusSeen)
				{
				push @$changedLineNumsArr, $negLine;
				push @$lineTypesArr,       'D';
				}
			$plusSeen      = 0;
			$negSeen       = 0;
			$negLine       = 0;
			$atatLineStart = $1 - 1;
			}
		elsif ($atatLineStart > 0)
			{
			++$atatLineStart;
			if (index($line, '+') == 0)
				{
				if ($consecutiveNegCount)
					{
					$atatLineStart -= $consecutiveNegCount;
					}
				$plusSeen = 1;
				push @$changedLineNumsArr, $atatLineStart;
				push @$lineTypesArr,       'N';
				$consecutiveNegCount = 0;
				}
			elsif (index($line, '-') == 0)
				{
				++$consecutiveNegCount;
				$negSeen = 1;
				$negLine = $atatLineStart;
				#--$atatLineStart;
				}
			else    # "Context" line, no + or - at start
				{
				if ($consecutiveNegCount)
					{
					$atatLineStart -= $consecutiveNegCount;
					}
				push @$changedLineNumsArr, $atatLineStart;
				push @$lineTypesArr,       'C';
				$consecutiveNegCount = 0;
				}
			}
		}

	if ($negSeen && !$plusSeen)
		{
		push @$changedLineNumsArr, $negLine;
		push @$lineTypesArr,       'D';
		}


	#print("Changed:\n");
	#print("@$changedLineNumsArr\n");
}

sub xGetLineNumbersForChangedLines {
	my ($diffs, $changedLineNumsArr, $lineTypesArr) = @_;
	my @lines         = split(/\n/, $diffs);
	my $atatLineStart = -1;
	my $atatCount     = -1;
	my $plusSeen      = 0;
	my $negSeen       = 0;
	my $negLine       = 0;
	my $numLines      = @lines;
	my $line          = '';

	for (my $i = 0 ; $i < $numLines ; ++$i)
		{
		my $line = $lines[$i];
		# Eg @@ -27,7 +27,7 @@...
		# or @@ -665,8 +668,15
		if (index($line, '@@') == 0 && $line =~ m!^@@\s+\-\d+,\d+\s+\+(\d+),(\d+)!)
			{
			# Push any neg line if saw neg but no positive.
			if ($negSeen && !$plusSeen)
				{
				push @$changedLineNumsArr, -$negLine;
				}
			$plusSeen      = 0;
			$negSeen       = 0;
			$negLine       = 0;
			$atatLineStart = $1 - 1;
			$atatCount     = $2;
			#print("START LINE $atatLineStart, COUNT $atatCount\n");
			}
		elsif ($atatLineStart > 0)
			{
			#print("$line\n");
			++$atatLineStart;
			if (index($line, '+') == 0)
				{
				$plusSeen = 1;
				push @$changedLineNumsArr, $atatLineStart;
				}
			elsif (index($line, '-') == 0)
				{
				$negSeen = 1;
				$negLine = $atatLineStart;
				--$atatLineStart;
				}
			else    # "Context" line
				{

				}
			}
		}

	if ($negSeen && !$plusSeen)
		{
		push @$changedLineNumsArr, -$negLine;
		}


	#print("Changed:\n");
	#print("@$changedLineNumsArr\n");
}

{ ##### HTML hash and footnotes
# Text (Gloss) only, id inline HTML blocks and replace with fairly unique keys.
# Based on Text::MultiMarkdown's _HashHTMLBlocks();
my %g_html_blocks;
my %footnotes;
my %popupFootnotes;
my %newIdForOld;
my %referenceSeen;    # defined if a reference id has already been seen

sub ReplaceHTMLAndFootnoteswithKeys {
	my ($text) = @_;
	my $textLen = length($text);

	%g_html_blocks  = ();
	%footnotes      = ();
	%popupFootnotes = ();
	%newIdForOld    = ();
	%referenceSeen  = ();
	my $block_tags_a =
qr/p|div|h[1-6]|blockquote|pre|table|dl|ol|ul|script|noscript|form|fieldset|iframe|math|ins|del/;
	my $htmlStart = qr/!/;    # Inline HTML must start with a !
	my $index     = 1;

	# Look for nested blocks, e.g.:
	# 	!<div>
	# 		<div>
	# 		tags for inner block must be indented.
	# 		</div>
	# 	</div>
	#
	# See "Gloss.html#Inline HTML" for details.
	$text =~ s{
				^						# start of line  (with /m)
				$htmlStart				# inline HTML marker start char
				(						# save in $1
					<($block_tags_a)	# start tag = $2
					\b					# word break
					(.*\n)*?			# any number of lines, minimally matching
					</\2>				# the matching end tag
					[ \t]*				# trailing spaces/tabs
					(?=\n+|\Z)			# followed by a newline or end of document
				)
			}{
				my $key = '__HH__' . $index++;
				$g_html_blocks{$key} = $1;
				my $nr_of_lines = $1 =~ tr/\n//;
				++$nr_of_lines; # num lines == num newlines + 1
				# Return key with number of lines in original appended
				# so we can adjust Viewer line count to match Editor.
				$key . '_L_' . $nr_of_lines;
			}egmx;

	# Pick up footnote text, put in link to where footnote will be mentioned.
	$index = 1;
	$text =~ s{
				^						# start of line  (with /m)
				(						# save in $1
				\[\^					# standard [^ starting a footnote
				(\w+)					# footnote id, $2
				]:						# close id plus colon
				.*?\n					# Remainder of first line
				(^.+?(\n|$))* 			# following lines, must not be empty
				)
	}{
		my $note = $1;
		my $idProper = $2;
		my $nr_of_lines = $note =~ tr/\n//;
		++$nr_of_lines;
		my $key = '__FN__' . $idProper . '_L_' . $nr_of_lines . '_IND_' . $index++;
		
		my $backLink = "<a href=\"#fnref_BACKREF_\" onclick=\"scrollBackToFootnoteRef(this); return(false);\"" . " class=\"footnote-backref\">↩</a>";
		chomp($note);
		$footnotes{$key} = "<div id='fn$idProper'>" . $note . ' ' . $backLink . "</div>";
		$popupFootnotes{'__FNP__' . $idProper} = $note;
		$key;
	}egmx;

	return ($text);
}

# Text (Gloss) only, replace HTML keys with orginal inline HTML.
# Everything in Gloss is in a <table> EXCEPT the inline HTML,
# so that's why we end a table and start a new table. Mostly.
# Footnote keys are not in the text, for them we notice a
# footnote reference such as [^27] and look for key fn27;
sub ReplaceKeysWithHTMLAndFootnotes {
	my ($linesA, $numLines, $filePath) = @_;
	my $previousLineForChunk = -1;
	my $footIndex            = 1;
	my $newIndex             = 1;

	for (my $i = 0 ; $i < $numLines ; ++$i)
		{
		# Inline HTML.
		my $key = '';
		if (index($linesA->[$i], '__HH__') == 0)
			{
			my $lpos = -1;
			if (($lpos = index($linesA->[$i], '_L_')) > 0)
				{
				$key = substr($linesA->[$i], 0, $lpos);
				}
			}

		if (defined($g_html_blocks{$key}))
			{
			my $putEndTable   = 1;
			my $putStartTable = 1;

			# Check for a preceding chunk.
			if ($i == $previousLineForChunk + 1)
				{
				$putEndTable = 0;
				}

			# Check for a following chunk.
			if (   $i < $numLines - 1
				&& index($linesA->[$i + 1], '__HH__') == 0
				&& index($linesA->[$i + 1], '_L_') > 0)
				{
				$putStartTable = 0;
				}

			if ($putEndTable && $putStartTable)
				{
				$linesA->[$i] =
					  "</table><div class='rawHTML'>"
					. $g_html_blocks{$key}
					. "</div><table class='imt'>";
				}
			elsif (!$putEndTable && !$putStartTable)
				{
				$linesA->[$i] = "<div class='rawHTML'>" . $g_html_blocks{$key} . "</div>";
				}
			elsif (!$putEndTable)
				{
				$linesA->[$i] =
					"<div class='rawHTML'>" . $g_html_blocks{$key} . "</div><table class='imt'>";
				}
			elsif (!$putStartTable)    # possibly redundant:)
				{
				$linesA->[$i] = "</table><div class='rawHTML'>" . $g_html_blocks{$key} . "</div>";
				}

			$previousLineForChunk = $i;
			}

		# Footnote references. Skip refs with no actual corresponding footnote.
		if (index($linesA->[$i], '[^') >= 0)    # footnote ref if it's [^stuff]no colon
			{
			$linesA->[$i] =~ s{
				(\[\^(\w+)](?=[^:]|$))
				}{
					if (defined($popupFootnotes{'__FNP__' . $2}))
						{
						if (!defined($referenceSeen{$2}))
							{
							$referenceSeen{$2} = 1;
							$newIndex = $footIndex++;
							$newIdForOld{$2} = $newIndex;
							}
						else
							{
							$referenceSeen{$2} += 1;
							$newIndex = $newIdForOld{$2};
							}
						my $noteId = 'fn' . $newIndex;
						my $refLineNumber = LineNumberFromRowText($linesA->[$i]);
						my $matchStartPos = $-[0];
						my $isFootnote = 1;
						if ($matchStartPos > 0)
							{
							my $beforeChar = substr($linesA->[$i], $matchStartPos - 1, 1);
							if ($beforeChar eq ' ' || $beforeChar eq "\t")
								{
								$isFootnote = 0; # Counts as a citation, no <sup>
								}
							}
						my $supStart = ($isFootnote) ? "<sup class='footenoteref'>": '';
						my $supEnd = ($isFootnote) ? "</sup>": '';
						my $refID = 'fnref' . $newIndex . '_' . $referenceSeen{$2};
						"$supStart<a href='#fn$newIndex' onclick=\"scrollToFootnote('$noteId', '$refLineNumber')\"  id='$refID'" . GlossedPopupForFootnote($2, $newIndex, $filePath) . ">\[$newIndex]</a>$supEnd";
						}
					else
						{
						$1;
						}
				}egx;
			}
		}

	# Restore footnotes at bottom. They have been removed from the text where defined.
	# Unreferenced footnotes/citations are not included in the output.
	my $numFootnotes = keys %footnotes;
	if ($numFootnotes)
		{
		push(@{$linesA}, "\n");
		push(@{$linesA}, "</table>");
		push(@{$linesA}, "<hr>");
		push(@{$linesA}, "<div class='allfootnotes'>\n");
		foreach my $key (sort {FootnoteIndexComp($a, $b)} keys %footnotes)
			{
			my $isReferenced = 0;
			if ($key =~ m!__FN__(\w+?)_L_!)
				{
				my $idProper = $1;
				if (defined($newIdForOld{$idProper}))
					{
					$isReferenced = 1;
					}
				}

			if ($isReferenced)
				{
				my $footnote = $footnotes{$key};
				$footnote = GlossedFootnote($footnote, $filePath);
				push(@{$linesA}, $footnote);
				}
			}
		push(@{$linesA}, "\n</div>\n<table class='imt'>");
		}

	%g_html_blocks  = ();
	%footnotes      = ();
	%popupFootnotes = ();
	%newIdForOld    = ();
	%referenceSeen  = ();
}

sub ReplaceKeysWithHTMLInsideFootnotes {
	my ($linesA, $numLines) = @_;
	my $previousLineForChunk = -1;

	for (my $i = 0 ; $i < $numLines ; ++$i)
		{
		# Inline HTML.
		my $key  = '';
		my $hpos = -1;
		if (($hpos = index($linesA->[$i], '__HH__')) >= 0)
			{
			my $lpos = -1;
			if (($lpos = index($linesA->[$i], '_L_')) > $hpos)
				{
				$key = substr($linesA->[$i], $hpos, $lpos - $hpos);
				}
			}

		if (defined($g_html_blocks{$key}))
			{
			my $putEndTable   = 1;
			my $putStartTable = 1;

			# Check for a preceding chunk.
			if ($i == $previousLineForChunk + 1)
				{
				$putEndTable = 0;
				}

			# Check for a following chunk.
			if (   $i < $numLines - 1
				&& index($linesA->[$i + 1], '__HH__') >= 0
				&& index($linesA->[$i + 1], '_L_') > 0)
				{
				$putStartTable = 0;
				}

			# Pull out any trailing back reference anchor
			my $backRef = '';
			if ($linesA->[$i] =~ m!(\s*<a\s+href="#fnref[^"]+"\s+onclick.+?</a>)!)
				{
				$backRef = $1;
				}
			if ($putEndTable && $putStartTable)
				{
				$linesA->[$i] =
					  "</table><div class='rawHTML'>"
					. $g_html_blocks{$key}
					. $backRef
					. "</div><table class='imt'>";
				}
			elsif (!$putEndTable && !$putStartTable)
				{
				$linesA->[$i] =
					"<div class='rawHTML'>" . $g_html_blocks{$key} . $backRef . "</div>";
				}
			elsif (!$putEndTable)
				{
				$linesA->[$i] =
					  "<div class='rawHTML'>"
					. $g_html_blocks{$key}
					. $backRef
					. "</div><table class='imt'>";
				}
			elsif (!$putStartTable)    # possibly redundant:)
				{
				$linesA->[$i] =
					"</table><div class='rawHTML'>" . $g_html_blocks{$key} . $backRef . "</div>";
				}

			$previousLineForChunk = $i;
			}
		}
}

# Used to skip user-entered instances of __HH__... at a line start.
sub InlineHTMLKeyIsDefined {
	my ($key) = @_;
	my $result = defined($g_html_blocks{$key}) ? 1 : 0;
	return ($result);
}

sub FootNoteIsDefined {
	my ($key) = @_;
	my $result = defined($footnotes{$key}) ? 1 : 0;
	return ($result);
}

sub GlossedFootnote {
	my ($footnote, $filePath) = @_;
	my @footnoteLines = split(/\n/, $footnote);
	my $oldIndex      = '';
	my $newIndex      = '';

	# Find new index for footnote. Footnotes are renumbered to
	# be in sequence, according to sequence of footnote references
	# in the body text.
	if ($footnoteLines[0] =~ m!id=\'fn(\w+)!)
		{
		$oldIndex = $1;
		if (defined($newIdForOld{$oldIndex}))
			{
			$newIndex = $newIdForOld{$oldIndex};
			}
		else
			{
			$newIndex = $oldIndex;
			}
		}

	$footnoteLines[0] =~
		s!^<div\s+id=(['"])fn(\w+)['"]>\[\^(\w+)]:!<div id=$1fn$newIndex$1>\*\*$newIndex\*\*\.!;

	# Fix the back ref too, on the last line. Look for #fnref_BACKREF_
	my $lastLine = @footnoteLines;
	--$lastLine;
	if ($lastLine >= 0)
		{
		my $refID = '#fnref' . $newIndex . '_' . '1';
		$footnoteLines[$lastLine] =~ s!#fnref_BACKREF_!$refID!;
		}

	$footnote = join("\n", @footnoteLines);
	my $glossedFootnote;
	my $serverAddr    = ServerAddress();
	my $theServerPort = $port_listen;      # Not $server_port;
	my $contextDir    = lc($filePath);
	$contextDir = DirectoryFromPathTS($contextDir);

	Gloss(
		$footnote, $serverAddr, $theServerPort,     \$glossedFootnote,
		0,         $IMAGES_DIR, $COMMON_IMAGES_DIR, $contextDir,
		undef,     undef
	);

	#my $foot = $glossedFootnote;

	# Ask Linker for additional (FLASH) links.
	AddFlashLinksToFootnote(\$glossedFootnote, $contextDir);

	# TO DO avoid re-splitting the footnote.
	# Rep inline HTML keys with HTML, preserving the back reference.
	@footnoteLines = split(/\n/, $glossedFootnote);
	my $numLines = @footnoteLines;
	ReplaceKeysWithHTMLInsideFootnotes(\@footnoteLines, $numLines);
	my $foot = join("\n", @footnoteLines);

	# Spurious LF's, stomp them with malice.
	$foot =~ s!\%0A!!gm;

	$foot =~ s!&quot;!"!gm;
	$foot =~ s!&#60;!<!gm;

	return ($foot);
}

sub GlossedPopupForFootnote {
	my ($idProper, $newIndex, $filePath) = @_;
	my $gloss = '';

	my $key = '__FNP__' . $idProper;
	if (defined($popupFootnotes{$key}))
		{
		my $footnote = $popupFootnotes{$key};
		$footnote =~ s!^\[\^(\w+)]:!\*\*$newIndex\*\*\.!;
		my $glossedFootnote;
		my $serverAddr    = ServerAddress();
		my $theServerPort = $port_listen;
		my $contextDir    = lc($filePath);
		$contextDir = DirectoryFromPathTS($contextDir);

		Gloss(
			$footnote, $serverAddr, $theServerPort,     \$glossedFootnote,
			0,         $IMAGES_DIR, $COMMON_IMAGES_DIR, $contextDir,
			undef,     undef
		);

		# Ask Linker for additional (FLASH) links.
		AddFlashLinksToFootnote(\$glossedFootnote, $contextDir);

		# TO DO avoid splitting the footnote.
		# Rep inline HTML keys with HTML, preserving the back reference.
		my @footnoteLines = split(/\n/, $glossedFootnote);
		my $numLines      = @footnoteLines;
		ReplaceKeysWithHTMLInsideFootnotes(\@footnoteLines, $numLines);
		# Pad out the footnote vertically if it's tiny, to allow easier mousing over (sic).
		if ($numLines < 3)
			{
			push @footnoteLines, "<p></p>";
			unshift @footnoteLines, "<p></p>";
			}

		my $foot = join("\n", @footnoteLines);

		$foot  = uri_escape_utf8("<div class='footDiv'>" . $foot . "</div>");
		$gloss = " onmouseover=\"showhint('$foot', this, event, '600px', false, true);\"";
		}

	return ($gloss);
}

# Key: my $key = '__FN__' . $2 . '_L_' . $nr_of_lines . '_IND_' . $index++;
# Compare NEW index values to order by new index.
sub FootnoteIndexComp {
	my ($keyA, $keyB) = @_;
	my $indexA = -1;
	my $indexB = -1;
	my $pos    = -1;
	my $rpos   = -1;

	if (   ($pos = index($keyA, '__FN__')) == 0
		&& ($rpos = index($keyA, '_L_')) > 0)
		{
		my $oldIndex = substr($keyA, $pos + 6, $rpos - $pos - 6);
		if (defined($newIdForOld{$oldIndex}))
			{
			$indexA = $newIdForOld{$oldIndex};
			}
		}

	if (   ($pos = index($keyB, '__FN__')) == 0
		&& ($rpos = index($keyB, '_L_')) > 0)
		{
		my $oldIndex = substr($keyB, $pos + 6, $rpos - $pos - 6);
		if (defined($newIdForOld{$oldIndex}))
			{
			$indexB = $newIdForOld{$oldIndex};
			}
		}

	return ($indexA <=> $indexB);
}

sub AddFlashLinksToFootnote {
	my ($contentsR, $contextDir) = @_;

	my $linkerShortName = CVal('LINKERSHORTNAME');
	my $linkerPort      = FetchPort($linkerShortName);

	if (index($linkerPort, "***ERROR") == 0)
		{
		# Linker is not reachable.
		return;
		}

	$LinkerArguments{'VISIBLE_TEXT'} = uri_escape_utf8($$contentsR);

	my $result = RequestLinkMarkupWithPort($linkerPort, \%LinkerArguments);
	$result = decode_utf8(uri_unescape($result));
	#$result = uri_unescape_utf8($result); - sub does not exist!?

	if (index($result, '***ERROR') != 0 && $result ne '')
		{
		$$contentsR = $result;
		}
}

}    ##### HTML hash and footnotes

sub LineNumberFromRowText {
	my ($text) = @_;
	my $lineNumber = 0;

	if ($text =~ m!<td n=['"](\d+)['"]>!)
		{
		$lineNumber = $1;
		}
	return ($lineNumber);
}

sub AnchorForGlossaryTerm {
	my ($term) = @_;

	$term =~ s!&nbsp;!_!g;
	$term =~ s!['"]!!g;
	$term =~ s!\&#\d+;!!g;    # eg &#9755;
	$term =~ s!\s!_!g;
	$term =~ s!\-!_!g;

	return ($term);
}

# For glossary.txt only, add anchors for defined terms.
sub AddGlossaryAnchor {
	my ($txtR) = @_;

	# Init variables with "Glossary loading" scope.
	my $line = $$txtR;
	my $len  = length($line);

	# Typical line start for defined term:
	# <tr><td n='21'></td><td>Strawberry Perl:
	if ($line =~ m!^(.+?<td>\s*)(.+?[^\\]):(.*)$!)
		#if ($line =~ m!^(.+?<td>\s*)([^:]+)\:(.*)$!)
		{
		my $pre          = $1;
		my $post         = $3;
		my $term         = $2;
		my $originalText = $term;
		$term = lc($term);
		$term =~ s!\*!!g;

		my $anchorText = AnchorForGlossaryTerm($term);
		my $rep        = "<h2 id=\"$anchorText\"><strong>$originalText</strong>:</h2>";
		#		my $rep = "<a id=\"$anchorText\"><strong>$originalText</strong>:</a>";
		# Sometimes an escaped colon sneaks into the first paragraph, delete the \.
		$post =~ s!\\:!:!g;

		$$txtR = $pre . $rep . $post;
		}
	# While we're passing by, remove the '\' from '\:'.
	elsif (index($line, "\:") >= 0)
		{
		$$txtR =~ s!\\:!:!g;
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
			$result = $aStr cmp $bStr;
			}
		}

	return ($result);
}

# Cook up a class= entry.
# Any one specific class, or indent level class, or ''.
# Leading space is tacked in to make final assembly easier.
sub ClassAttribute {
	my ($specificClass, $indentClass) = @_;
	my $result = '';

	if ($specificClass eq '' && $indentClass eq '')
		{
		return ($result);
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
	else    # we have in indent level, no specific class
		{
		$result = " class='$indentClass'";
		}

	return ($result);
}

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
		$$lineR =~
s!(BUGS?)!<span class='textSymbol' style='color: Crimson;'>\&#128029;</span><span class='notabene'>$1</span>!;
		$$lineR =~ s!^\=\>!<span class='textSymbol' style='color: Green;'>\&#9755;</span>!
			;    # White is \&#9758; but it's hard to see.
		$$lineR =~ s!^( )+\=\>!$1<span class='textSymbol' style='color: Green;'>\&#9755;</span>!;
		$$lineR =~ s!(IDEA\!)!<span class='textSymbol' style='color: Gold;'>\&#128161;</span>$1!;
		$$lineR =~
			s!(FIXED|DONE)!<span class='textSymbolSmall' style='color: Green;'>\&#9745;</span>$1!;
		$$lineR =~ s!(WTF)!<span class='textSymbol' style='color: Chocolate;'>\&#128169;</span>$1!;
		$$lineR =~
s!\:\)!<span class='textSymbol' style='color: lightgreen; background-color: #808080;'>\&#128578;</span>!g
			;    # or \&#9786;
				 # Three or more @'s on a line by themselves produce a "flourish" section break.
		if ($$lineR =~ m!^@@@@*$!)
			{
			my $sectionImage = FlourishLink();
			$$lineR =~ s!@@@@*!$sectionImage!;
			}
		# Messes up glossary popups: $$lineR =~ s!FLASH!<span class='smallCaps'>FLASH</span>!g;
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
			$$lineR = "<p$classAttr>" . '&nbsp;&bull; ' . $2 . '</p>';  # &#9830;(diamond) or &bull;
			 #$$lineR = '<p class="outdent-unordered">' . '&nbsp;&bull; ' . $2 . '</p>'; # &#9830;(diamond) or &bull;
			}
		else
			{
			$$unorderedListDepthR = 2;
			my $classAttr = ClassAttribute('outdent-unordered-sub', $indentClass);
			$$lineR =
				  "<p$classAttr>"
				. '&#9702; '
				. $2
				. '</p>';    # &#9702; circle, &#9830;(diamond) or &bull;
			 #$$lineR = '<p class="outdent-unordered-sub">' . '&#9702; ' . $2 . '</p>'; # &#9702; circle, &#9830;(diamond) or &bull;
			}
		}
	elsif ($$unorderedListDepthR > 0 && $$lineR =~ m!^\s+!)
		{
		if ($doingPOD)
			{
			$$lineR =~ s!^ !!;    # That's a space
			}
		else
			{
			$$lineR =~ s!^ +!!;    # That's a space(s)
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
		my $trailer      = $2;
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
		my $class     = (length($suggestedNum) > 1) ? "ol-2" : "ol-1";
		my $classAttr = ClassAttribute($class, $indentClass);
		$$lineR = "<p$classAttr>" . "$$listNumberR. $trailer" . '</p>';
		}
	# A minor entry, eg "3.1":
	elsif ($$lineR =~ m!^\s*(\d+|\#)\.(\d+|\#) +(.+?)$!
		|| $$lineR =~ m!^\s*(_OLN_)\.(_OLN_) +(.+?)$!)
		{
		my $suggestedNum       = $1;    # not used
		my $secondSuggestedNum = $2;    # not used
		my $trailer            = $3;

		++$$subListNumberR;
		if ($$listNumberR <= 0)
			{
			$$listNumberR = 1;
			}
		if (length($$listNumberR) > 1)
			{
			my $class     = (length($$subListNumberR) > 1) ? "ol-2-2" : "ol-2-1";
			my $classAttr = ClassAttribute($class, $indentClass);
			$$lineR = "<p$classAttr>" . "$$listNumberR.$$subListNumberR $trailer" . '</p>';
			}
		else
			{
			my $class     = (length($$subListNumberR) > 1) ? "ol-1-2" : "ol-1-1";
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
				my $class     = (length($$subListNumberR) > 1) ? "ol-2-2-c" : "ol-2-1-c";
				my $classAttr = ClassAttribute($class, $indentClass);
				$$lineR = "<p$classAttr>" . $$lineR . '</p>';
				}
			else
				{
				my $class     = (length($$subListNumberR) > 1) ? "ol-1-2-c" : "ol-1-1-c";
				my $classAttr = ClassAttribute($class, $indentClass);
				$$lineR = "<p$classAttr>" . $$lineR . '</p>';
				}
			}
		else
			{
			my $class     = (length($$listNumberR) > 1) ? "ol-2-c" : "ol-1-c";
			my $classAttr = ClassAttribute($class, $indentClass);
			$$lineR = "<p$classAttr>" . $$lineR . '</p>';
			}
		}
	else
		{
		# A blank line or line that doesn't start with a space or tab restarts the auto numbering.
		if ($$lineR =~ m!^\s*$! || $$lineR !~ m!^\s!)
			{
			$$listNumberR    = 0;
			$$subListNumberR = 0;
			}
		}
}

sub HorizontalRule {
	my ($lineR, $lineNum, $indentClass) = @_;

	# <hr> equivalent for three or four === or --- or ~~~
	# If it's === or ====, use a slightly thicker rule.
	my $imageName = ($$lineR =~ m!^\=\=\=\=?!)        ? 'mediumrule4.png' : 'slimrule4.png';
	my $height    = ($imageName eq 'mediumrule4.png') ? 6                 : 3;
	my $rowID     = 'R' . $lineNum;
	my $classAttr = ClassAttribute('vam', $indentClass);
	$$lineR =
"<tr id='$rowID'><td n='$lineNum'></td><td$classAttr><img style='display: block;' src='$imageName' width='98%' height='$height' /></td></tr>";
}

# Convert a <pre> marker line to an image.
sub PreRule {
	my ($lineR, $lineNum, $indentClass) = @_;
	my $imageName = 'slimrule4.png';                         # 'slimrule4.png'; 'mediumrule4.png'
	my $height    = 3;                                       # 3; 6;
	my $spacer    = (index($$lineR, ' ') == 0) ? ' ' : '';
	my $pClass =
		($spacer eq '') ? "class='ruleHeightPara'" : " class='outdent-unordered ruleHeightPara'";
	my $classAttr = " class='vam'";
	my $rowID     = 'R' . $lineNum;

	$$lineR =
"<tr id='$rowID'><td n='$lineNum'></td><td$classAttr><img style='display: block;' src='$imageName' width='98%' height='$height' /></td></tr>";
}

# Heading(\$lines[$i], \$lines[$i-1], $underline, \@jumpList, $i, \%sectionIdExists);
# Note if doing underlined header then line before will have td etc, but
# if doing # header then the line we're on will be plain text.
# Note line counts as # header only if the #'s are followed by at least one space.
# Added Feb 2024, require blank line before # header, except at doc start (see above).
sub Heading {
	my ($lineR, $lineBeforeR, $underline, $jumpListA, $i, $sectionIdExistsH) = @_;

	# Use text of header for anchor id if possible.
	my $isHashedHeader = 0;    #  ### header vs underlined header
	my $beforeHeader   = '';
	my $headerProper   = '';
	my $afterHeader    = '';
	my $headerLevel    = 0;
	# ### style heading, heading is on $lineR.
	if ($$lineR =~ m!^(#.+)$!)
		{
		$isHashedHeader = 1;
		$beforeHeader   = '';
		my $rawHeader = $1;
		$afterHeader = '';
		$rawHeader =~ m!^(#+)!;
		my $hashes = $1;
		$headerLevel = length($hashes);
		if ($i <= 1)    # right at the top of the document, assume it's a document title <h1>
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
		$afterHeader  = $3;
		if (substr($underline, 0, 1) eq '=')
			{
			$headerLevel = 2;
			}
		elsif (substr($underline, 0, 1) eq '-')
			{
			$headerLevel = 3;
			}
		elsif (substr($underline, 0, 1) eq '~')
			{
			$headerLevel = 4;
			}
		if ($i == 1)    # right at the top of the document, assume it's a document title <h1>
			{
			$headerLevel = 1;
			}
		}

	# Mark up as an ordinary line and return if no header pattern matched.
	if (!defined($headerProper) || $headerProper eq '')
		{
		++$i;           # Convert to 1-based line number.
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
		++$i;    # $i is now a 1-based line number.
		my $rowID = 'R' . $i;
		$$lineR =
			  "<tr id='$rowID'><td n='$i'></td><td>"
			. "<$contentsClass id=\"$id\">$headerProper</$contentsClass>"
			. '</td></tr>';
		}
	else
		{
		# Turn the underline into a tiny blank row, make line before look like a header
		$$lineR = "<tr class='shrunkrow'><td></td><td></td></tr>";
		$$lineBeforeR =
			"$beforeHeader<$contentsClass id=\"$id\">$headerProper</$contentsClass>$afterHeader";
		# Back out any "outdent" wrapper that might have been added, for better alignment.
		if ($jumperHeader =~ m!^<p!)
			{
			$jumperHeader =~ s!^<p[^>]*>!!;
			$jumperHeader =~ s!</p>$!!;
			}
		}

	my $jlStart = "<li class='$contentsClass' im-text-ln='$i'><a href='#$id'>";
	my $jlEnd   = "</a></li>";
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
	# A minor nuisance, we have span, strong, em wrapped around some or all of the header,
	# get rid of that in the id.
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
	# it easier to type the headers in links.
	# Eg 'server swarm.txt#TODO_List' for header '&#127895;TODO List'.
	$id =~ s!\&#\d+;!!g;    # eg &#9755;

	if ($id eq '' || defined($sectionIdExistsH->{$id}))
		{
		my $anchorNumber = @$jumpListA;
		$id = "hdr_$anchorNumber";
		}
	$sectionIdExistsH->{$id} = 1;

	return ($jumperHeader, $id);
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
		if ($idIndex != $leftIdx)    # No 'id=', no link. Abort the whole process here.
			{
			return;
			}
		$leftIdx += 3;               # Skip 'id='
		$rightIdx = index($$lineR, '_ARP_');
		if ($rightIdx < 0)
			{
			return;
			}
		my $endRepPosition = $rightIdx + length('_ARP_');
		my $id             = substr($$lineR, $leftIdx, $rightIdx - $leftIdx);

		my $anchor = "<a id='$id'>$displayedText</a>";

		$$lineR =
			substr($$lineR, 0, $startRepPosition) . $anchor . substr($$lineR, $endRepPosition);
		}
}

# Where a line begins with TABLE, convert lines following TABLE that contain tab(s) into an
# HTML table. We have already put in line numbers and <tr> with <td> for the line numbers and
# contents proper, see just above.
# A table begins with TABLE followed by optional text, provided the first character in the optional
# text is one of space tab underscore colon period hyphen. The following line must also
# contain at least one tab. The table continues for all following lines containing at least one tab.
## Cells are separated by one or more tabs. Anything else, even a space, counts as cell content. ##
# The opening TABLE is suppressed. Text after TABLE is used as the caption.
# If TABLE is the only text on the line, the line is made shorter in height.
# Now, the whole body of a document is in a single table with
# each row having cells for line number and actual content. For a TABLE, the
# body table is ended with </table>, our special TABLE is put in, and then a regular
# body table is started up again with <table> afterwards. The overall <table> and </table>
# wrappers for the body are done at the end of GetPrettyTextContents().
# For the TABLE line: end previous (body) table, start new table, remove TABLE from line and also
# line number if there is no text following TABLE, and give the row class='shrunkrow'
# (in the table being ended).
# But if TABLE is followed by text on the same line, display the line, including the line number.
# Any following text becomes the table caption (TABLE is always removed from the text).
# Subsequent lines: first table row is <th> except for the line number which is <td>. Every table
# row starts with a line number, so there is one extra column in each row for that.
# At table end, tack on </table><table> to revert back to the regular document body table.
# In content rows, if there are too many cells then the rightmost will be combined into one
# And if there are too few, colspan will extend the last cell.
# To "skip" a column, put an unobtrusive character such as space or period for its content
# (it will be centered up).
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

	for (my $i = 0 ; $i < $numLines ; ++$i)
		{
		if (   $lines_A->[$i] =~ m!^<tr id='R\d+'><td[^>]+></td><td>TABLE(</td>|[_ \t:.-])!
			&& $i < $numLines - 1
			&& $lines_A->[$i + 1] =~ m!\t!)
			{
			my $numColumns    = 0;
			my $tableStartIdx = $i;
			my $idx           = $i + 1;
			my $startIdx      = $idx;

			# Preliminary pass, determine the maximum number of columns. Rather than check all the
			# rows, assume a full set of columns will be found on the first or second row, and
			# no colspans. Ok, four rows. Otherwise madness reigns.
			my @cellMaximumChars;

			GetMaxColumns($idx, $numLines, $lines_A, \$numColumns, \@cellMaximumChars);

			# Start the table, with optional title.
			StartNewTable($lines_A, $tableStartIdx, \@cellMaximumChars, $numColumns);

			# Main pass, make the table rows.
			$idx = $startIdx;
			$idx = DoTableRows($idx, $numLines, $lines_A, $numColumns, \%alignmentString);

			# Stop/start table on the last line matched.
			# No start of new table if we're at the bottom.
			if ($idx == $numLines)
				{
				$lines_A->[$idx - 1] = $lines_A->[$idx - 1] . '</tbody></table>';
				}
			else
				{
				$lines_A->[$idx - 1] =
					$lines_A->[$idx - 1] . '</tbody></table><table class=\'imt\'><tbody>';
				}
			}    # if TABLE
		}    # for (my $i = 0; $i <$numLines; ++$i)
}

# Check first few rows, determine maximum number of columns and length of each cell.
sub GetMaxColumns {
	my ($idx, $numLines, $lines_A, $numColumnsR, $cellMaximumChars_A) = @_;

	my $rowsChecked = 0;
	while ($idx < $numLines && $lines_A->[$idx] =~ m!\t! && ++$rowsChecked <= 4)
		{
		$lines_A->[$idx] =~ m!^<tr id='R\d+'><td\s+n\=['"](\d+)['"]></td><td>(.+?)</td></tr>!;
		my $content           = $2;
		my @contentFields     = split(/\t+/, $content);
		my $currentNumColumns = @contentFields;
		if ($$numColumnsR < $currentNumColumns)
			{
			$$numColumnsR = $currentNumColumns;
			}
		for (my $j = 0 ; $j < $currentNumColumns ; ++$j)
			{
			if (  !defined($cellMaximumChars_A->[$j])
				|| length($cellMaximumChars_A->[$j]) < length($contentFields[$j]))
				{
				$cellMaximumChars_A->[$j] = length($contentFields[$j]);
				}
			}

		++$idx;
		}
}

sub StartNewTable {
	my ($lines_A, $tableStartIdx, $cellMaximumChars_A, $numColumns) = @_;

	if ($lines_A->[$tableStartIdx] =~ m!TABLE[_ \t:.-]+\S!)
		{
		# Use supplied text after TABLE as table "caption".
		if ($lines_A->[$tableStartIdx] =~
			m!^(<tr id='R\d+'><td[^>]+></td><td>)TABLE[_ \t:.-]+(.+?)(</td></tr>)!)
			{
			# Arg, caption can be no wider than the table, disregarding the caption. ?!?!?
			# So we'll just use text above the table if the caption is too long.
			#$lines_A->[$i] = "$1$3</table><table class='bordered'><caption>$2</caption>";
			my $pre     = $1;
			my $caption = $2;
			my $post    = $3;

			# If the caption will be roughly no wider than the resulting table,
			# use a caption. But if the caption will be smaller than the table,
			# just use slightly indented text. An empty line has
			# about 36 characters, the rest is the caption. Less 6 for "TABLE ".
			# A table row will be as wide as needed for the widest cell in each column,
			# and count the width of one character between columns.
			my $captionChars     = length($caption);
			my $longestLineChars = 0;
			for (my $j = 0 ; $j < @$cellMaximumChars_A ; ++$j)
				{
				$longestLineChars += $cellMaximumChars_A->[$j];
				}
			$longestLineChars += $numColumns - 1;
			if ($captionChars < $longestLineChars)
				{
				$lines_A->[$tableStartIdx] =
"$pre$post</tbody></table><table class='bordered imt'><caption>$caption</caption><thead>";
				}
			else
				{
				$lines_A->[$tableStartIdx] =
"$pre&nbsp; &nbsp;&nbsp; &nbsp;&nbsp;<span class='fakeCaption'>$caption</span>$post</tbody></table><table class='bordered imt'><thead>";
				}
			}
		else
			{
			# Probably a maintenance failure. Struggle on.
			$lines_A->[$tableStartIdx] =
"<tr class='shrunkrow'><td></td><td></td></tr></tbody></table><table class='bordered imt'><thead>";
			}
		}
	else    # no caption
		{
		$lines_A->[$tableStartIdx] =
"<tr class='shrunkrow'><td></td><td></td></tr></tbody></table><table class='bordered imt'><thead>";
		}
}

sub DoTableRows {
	my ($idx, $numLines, $lines_A, $numColumns, $alignmentString_H) = @_;

	my $isFirstTableContentLine = 2;    # Allow up to two headers rows up top.
	while ($idx < $numLines && $lines_A->[$idx] =~ m!\t!)
		{
		# Grab line number and content.
		$lines_A->[$idx] =~ m!^<tr id='R\d+'><td\s+n\=['"](\d+)['"]></td><td>(.+?)</td></tr>!;
		my $lineNum = $1;
		my $content = $2;

		# Break content into cells. Separator is one or more tabs.
		my @contentFields     = split(/\t+/, $content);
		my $currentNumColumns = @contentFields;

		# Determine the colspan of each field. If the field starts with <[LRC]?N> where N
		# is an integer, use that as the colspan. If we're at the last field
		# and don't have enough columns yet, add them to the last field.
		my $numColumnsIncludingSpans = 0;
		my @colSpanForFields;
		my @alignmentForFields;
		my $lastUsableFieldIndex = -1;

		for (my $j = 0 ; $j < $currentNumColumns ; ++$j)
			{
			my $requestedColSpan = 0;
			my $alignment        = '';
			# Look for <[LRC]\d+> at start of cell text. Eg <R>, <C3>, <4>.
			if ($contentFields[$j] =~
				m!^(\&#60;|\&lt\;|\<)([LRClrc]?\d+|[LRClrc])(\&#62;|\&gt\;|\>)!)
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
			push @colSpanForFields,   $requestedColSpan;
			push @alignmentForFields, $alignment;
			$numColumnsIncludingSpans += ($requestedColSpan > 0) ? $requestedColSpan : 1;

			# Ignore <N> if max columns has been hit. Note when it happens.
			if ($numColumnsIncludingSpans >= $numColumns)
				{
				$lastUsableFieldIndex = $j unless ($lastUsableFieldIndex >= 0);
				$colSpanForFields[$j] = 0;
				}

			if ($j == $currentNumColumns - 1)    # last entry
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
			$newLine .= "<td></td>" x $numColumns;
			$newLine .= "</tr>";
			}
		else
			{
			# Leftmost cell is for line number.
			my $rowID = 'R' . $lineNum;
			$newLine = "<tr id='$rowID'><$cellName n='$lineNum'></$cellName>";
			for (my $j = 0 ; $j <= $lastUsableFieldIndex ; ++$j)
				{
				# A single non-word char such as a space or period is taken as a signal for
				# an empty cell. Just centre it up, which makes it less obtrusive.
				if ($contentFields[$j] =~ m!^\W$!)
					{
					$newLine = $newLine
						. "<$cellName class='centered_cell'>$contentFields[$j]</$cellName>";
					}
				else
					{
					# Leading spaces are typically for numeric alignment and should be preserved.
					# We'll adjust for up to six spaces at the start of cell contents, replacing
					# every second space with a non-breaking space, starting with the first space.
					if (index($contentFields[$j], ' ') == 0)
						{
						$contentFields[$j] =~ s!^     !&nbsp; &nbsp; &nbsp;!;    # five spaces there
						$contentFields[$j] =~ s!^   !&nbsp; &nbsp;!;             # three spaces
						$contentFields[$j] =~ s!^ !&nbsp;!;                      # one space
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

					$newLine =
						$newLine . "<$cellName$colspanStr$alignStr>$contentFields[$j]</$cellName>";
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

	return ($idx);
}

# Obsolete, CodeMirror is being used instead for Perl files.
# sub LoadPerlFileContents {
# 	my ($filePath, $contentsR, $octetsR) = @_;

# 	$$octetsR = ReadTextFileWide($filePath);
# 	if (!defined($$octetsR))
# 		{
# 		$$contentsR .= "Error, could not open $filePath.";
# 		return (0);
# 		}
# 	my $decoder = Encode::Guess->guess($$octetsR);

# 	my $eightyeightFired = 0;
# 	if (ref($decoder))
# 		{
# 		my $decoderName = $decoder->name();
# 		if ($decoderName =~ m!iso-8859-\d+!)
# 			{
# 			$$octetsR         = $decoder->decode($$octetsR);
# 			$eightyeightFired = 1;
# 			}
# 		}

# 	# TEST ONLY track Perl load time
# 	#	print("Perl highlighting...");
# 	#	my $t1 = time;
# 	my $formatter = GetPerlHighlighter();
# 	$$octetsR = $formatter->format_string($$octetsR);
# 	#	my $elapsed = time - $t1;
# 	#	my $ruffElapsed = substr($elapsed, 0, 6);
# 	#	print(" $ruffElapsed seconds\n");

# 	if (!$eightyeightFired)
# 		{
# 		$$octetsR = decode_utf8($$octetsR);
# 		}

# 	return (1);
# }

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
	my @lines                   = split(/\n/, $contents);
	my $numLines                = @lines;
	my $consecutiveHeadingCount = 0;
	my @fixedLines;

	for (my $i = 1 ; $i < $numLines ; ++$i)
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
	my $idx      = index($html, "<!-- start doc -->");
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

	return (1);
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
	$SpecialIndexFileName      = CVal('SPECIAL_INDEX_NAME');
	$ContentTriggerWord        = CVal('SPECIAL_INDEX_EARLY_TEXT_MUST_CONTAIN');
	$SpecialIndexFont          = CVal('SPECIAL_INDEX_FONT');
	$SpecialIndexFlourishImage = CVal('SPECIAL_INDEX_FLOURISH');
	$FlourishImageHeight       = CVal('SPECIAL_INDEX_FLOURISH_HEIGHT');
}

sub IsSpecialIndexFile {
	my ($filePath, $lines_A) = @_;
	my $result = 0;

	if ($IndexGetsSpecialTreatment)
		{
		if ($filePath =~ m!$SpecialIndexFileName$!i)
			{
			my $numLines = @$lines_A;
			if (   $numLines
				&& $lines_A->[0] =~ m!$ContentTriggerWord!i
				&& $numLines <= 100)
				{
				$result = 1;
				}
			}
		}

	return ($result);
}

sub MakeSpecialIndexFileLookSpecial {
	my ($lines_A) = @_;

	my $numLines = @$lines_A;
	if ($numLines)
		{
		my $flourishImageLink = GetFlourishImageLink();
		$lines_A->[0] =~
s!(<td>)(.*?$ContentTriggerWord.*?)(</td>)!<th align='center'><span id='toc-line'>$2</span><br/>$flourishImageLink</th>!i;
		}
}

sub GetFlourishImageLink {
	my $result = '';
	if (FileOrDirExistsWide($IMAGES_DIR . $SpecialIndexFlourishImage) == 1)
		{
		my $imagePath = $IMAGES_DIR . $SpecialIndexFlourishImage;
		$result = "<img id='flourish-image' src='$SpecialIndexFlourishImage' width='100%'>";
		}

	return ($result);
}
}    ##### Special handling for contents.txt table of CONTENTS files

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
	for (my $i = 0 ; $i < @hits ; ++$i)
		{
		push @hitLengths, length($hits[$i]);
		}
	my $numHitItems = @hits;
	my @lines       = split(/\n/, $octets);
	my $currPos     = -1;
	my @hitArray;    # array of "[line, charStart, charEnd]"

	my $numHitsSoFar = 0;
	for (my $i = 0 ; $i < @lines ; ++$i)
		{
		$lines[$i] = lc($lines[$i]);
		for (my $j = 0 ; $j < $numHitItems ; ++$j)
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

{ ##### Theme dark vs light
my %ThemeIsDark;    # $ThemeIsDark{'theme'} = 1 if bkg is dark, 0 if light.
my $flourishLink;

sub SetFlourishLinkBasedOnTheme {
	my ($theme) = @_;
	#my $imageDir = $IMAGES_DIR;
	my $specialIndexFlourishImage = CVal('SPECIAL_INDEX_FLOURISH');

	my $flourishImageName;
	if (ThemeHasDarkBackground($theme))
		{
		#$flourishImageName = 'flourish2_white.png';
		# Take the base name and tack on '_white'.
		$flourishImageName = $specialIndexFlourishImage;
		if ($flourishImageName =~ m!^(.+?)\.(\w+)$!)
			{
			my $baseName  = $1;
			my $extension = $2;
			$flourishImageName = $baseName . '_white.' . $extension;
			}
		}
	else
		{
		$flourishImageName = $specialIndexFlourishImage;
		if ($flourishImageName =~ m!^(.+?)\.(\w+)$!)
			{
			my $baseName  = $1;
			my $extension = $2;
			$flourishImageName = $baseName . '_black.' . $extension;
			}
		}

	$flourishLink = "<img src='$flourishImageName' width='100%'";
}

# Call SetFlourishLinkBasedOnTheme() before calling this.
sub FlourishLink {
	return ($flourishLink);
}


sub ThemeHasDarkBackground {
	my ($theme) = @_;
	my $result = defined($ThemeIsDark{$theme}) ? $ThemeIsDark{$theme} : 0;
	return ($result);
}

sub InitThemeIsDark {
	$ThemeIsDark{'3024-day'}                = 0;
	$ThemeIsDark{'3024-night'}              = 1;
	$ThemeIsDark{'abbott'}                  = 1;
	$ThemeIsDark{'abcdef'}                  = 1;
	$ThemeIsDark{'ambiance'}                = 0;
	$ThemeIsDark{'ayu-dark'}                = 1;
	$ThemeIsDark{'ayu-mirage'}              = 1;
	$ThemeIsDark{'base16-dark'}             = 1;
	$ThemeIsDark{'base16-light'}            = 0;
	$ThemeIsDark{'bespin'}                  = 1;
	$ThemeIsDark{'blackboard'}              = 1;
	$ThemeIsDark{'cobalt'}                  = 1;
	$ThemeIsDark{'colorforth'}              = 1;
	$ThemeIsDark{'darcula'}                 = 1;
	$ThemeIsDark{'dracula'}                 = 1;
	$ThemeIsDark{'duotone-dark'}            = 1;
	$ThemeIsDark{'duotone-light'}           = 0;
	$ThemeIsDark{'eclipse'}                 = 0;
	$ThemeIsDark{'elegant'}                 = 0;
	$ThemeIsDark{'erlang-dark'}             = 1;
	$ThemeIsDark{'gruvbox-dark'}            = 1;
	$ThemeIsDark{'hopscotch'}               = 1;
	$ThemeIsDark{'icecoder'}                = 1;
	$ThemeIsDark{'idea'}                    = 0;
	$ThemeIsDark{'isotope'}                 = 1;
	$ThemeIsDark{'juejin'}                  = 0;
	$ThemeIsDark{'lesser-dark'}             = 1;
	$ThemeIsDark{'liquibyte'}               = 1;
	$ThemeIsDark{'lucario'}                 = 1;
	$ThemeIsDark{'material'}                = 1;
	$ThemeIsDark{'material-darker'}         = 1;
	$ThemeIsDark{'material-ocean'}          = 1;
	$ThemeIsDark{'material-palenight'}      = 1;
	$ThemeIsDark{'mbo'}                     = 1;
	$ThemeIsDark{'mdn-like'}                = 0;
	$ThemeIsDark{'midnight'}                = 1;
	$ThemeIsDark{'monokai'}                 = 1;
	$ThemeIsDark{'moxer'}                   = 1;
	$ThemeIsDark{'neat'}                    = 0;
	$ThemeIsDark{'neo'}                     = 0;
	$ThemeIsDark{'night'}                   = 1;
	$ThemeIsDark{'nord'}                    = 1;
	$ThemeIsDark{'oceanic-next'}            = 1;
	$ThemeIsDark{'panda-syntax'}            = 1;
	$ThemeIsDark{'paraiso-dark'}            = 1;
	$ThemeIsDark{'paraiso-light'}           = 0;
	$ThemeIsDark{'pastel-on-dark'}          = 1;
	$ThemeIsDark{'railscasts'}              = 1;
	$ThemeIsDark{'rubyblue'}                = 1;
	$ThemeIsDark{'seti'}                    = 1;
	$ThemeIsDark{'shadowfox'}               = 1;
	$ThemeIsDark{'solarized'}               = 1;
	$ThemeIsDark{'ssms'}                    = 0;
	$ThemeIsDark{'the-matrix'}              = 1;
	$ThemeIsDark{'tomorrow-night-bright'}   = 1;
	$ThemeIsDark{'tomorrow-night-eighties'} = 1;
	$ThemeIsDark{'twilight'}                = 1;
	$ThemeIsDark{'vibrant-ink'}             = 1;
	$ThemeIsDark{'xq-dark'}                 = 1;
	$ThemeIsDark{'xq-light'}                = 0;
	$ThemeIsDark{'yeti'}                    = 0;
	$ThemeIsDark{'yonce'}                   = 1;
	$ThemeIsDark{'zenburn'}                 = 1;
}
}    ##### Theme dark vs light

# Obsolete, CodeMirror is being used instead for Perl files.
# { ##### Perl Syntax Highlight
# my $formatter;
# my %StartFormats;
# my %EndFormats;

# sub InitPerlSyntaxHighlighter {
# 	$formatter = Syntax::Highlight::Perl::Improved->new();

# 	$StartFormats{'Comment_Normal'}    = "<span class='Comment_Normal'>";
# 	$StartFormats{'Comment_POD'}       = "<span class='Comment_POD'>";
# 	$StartFormats{'Directive'}         = "<span class='Directive'>";
# 	$StartFormats{'Label'}             = "<span class='Label'>";
# 	$StartFormats{'Quote'}             = "<span class='Quote'>";
# 	$StartFormats{'String'}            = "<span class='String'>";
# 	$StartFormats{'Subroutine'}        = "<span class='Subroutine'>";
# 	$StartFormats{'Variable_Scalar'}   = "<span class='Variable_Scalar'>";
# 	$StartFormats{'Variable_Array'}    = "<span class='Variable_Array'>";
# 	$StartFormats{'Variable_Hash'}     = "<span class='Variable_Hash'>";
# 	$StartFormats{'Variable_Typeglob'} = "<span class='Variable_Typeglob'>";
# 	#$StartFormats{'Whitespace'} = "<span class='Whitespace'>";
# 	$StartFormats{'Character'}        = "<span class='Character'>";
# 	$StartFormats{'Keyword'}          = "<span class='Keyword'>";
# 	$StartFormats{'Builtin_Function'} = "<span class='Builtin_Function'>";
# 	$StartFormats{'Builtin_Operator'} = "<span class='Builtin_Operator'>";
# 	$StartFormats{'Operator'}         = "<span class='Operator'>";
# 	$StartFormats{'Bareword'}         = "<span class='Bareword'>";
# 	$StartFormats{'Package'}          = "<span class='Package'>";
# 	$StartFormats{'Number'}           = "<span class='Number'>";
# 	$StartFormats{'Symbol'}           = "<span class='Symbol'>";
# 	$StartFormats{'CodeTerm'}         = "<span class='CodeTerm'>";
# 	$StartFormats{'DATA'}             = "<span class='DATA'>";

# 	$EndFormats{'Comment_Normal'}    = "</span>";
# 	$EndFormats{'Comment_POD'}       = "</span>";
# 	$EndFormats{'Directive'}         = "</span>";
# 	$EndFormats{'Label'}             = "</span>";
# 	$EndFormats{'Quote'}             = "</span>";
# 	$EndFormats{'String'}            = "</span>";
# 	$EndFormats{'Subroutine'}        = "</span>";
# 	$EndFormats{'Variable_Scalar'}   = "</span>";
# 	$EndFormats{'Variable_Array'}    = "</span>";
# 	$EndFormats{'Variable_Hash'}     = "</span>";
# 	$EndFormats{'Variable_Typeglob'} = "</span>";
# 	#$EndFormats{'Whitespace'} = "</span>";
# 	$EndFormats{'Character'}        = "</span>";
# 	$EndFormats{'Keyword'}          = "</span>";
# 	$EndFormats{'Builtin_Function'} = "</span>";
# 	$EndFormats{'Builtin_Operator'} = "</span>";
# 	$EndFormats{'Operator'}         = "</span>";
# 	$EndFormats{'Bareword'}         = "</span>";
# 	$EndFormats{'Package'}          = "</span>";
# 	$EndFormats{'Number'}           = "</span>";
# 	$EndFormats{'Symbol'}           = "</span>";
# 	$EndFormats{'CodeTerm'}         = "</span>";
# 	$EndFormats{'DATA'}             = "</span>";

# 	$formatter->set_start_format(\%StartFormats);
# 	$formatter->set_end_format(\%EndFormats);

# 	my $subH = $formatter->substitutions();
# 	$subH->{'<'} = '&lt;';
# 	$subH->{'>'} = '&gt;';
# 	$subH->{'&'} = '&amp;';
# 	#$subH->{"\t"} = '&nbsp;&nbsp;&nbsp;&nbsp;';
# 	#$subH->{"    "} = '&nbsp;&nbsp;&nbsp;&nbsp;';
# }

# sub GetPerlHighlighter {
# 	# Some files such as filehandle.pm kill the Perl formatter,
# 	# and it starts spitting out unhighlighted text.
# 	# A reset seems to cure that.
# 	$formatter->reset();
# 	return ($formatter);
# }

# }    ##### Perl Syntax Highlight

{ ##### Internal Links
my $line;
my $len;

# These replacements are more easily done in reverse order to avoid throwing off the start/end.
my @repStr;    # new link, eg <a href="#Header_within_doc">#Header within doc</a>
my @repLen;    # length of substr to replace in line, eg length('#Header within doc')
my @repStartPos
	;    # where header being replaced starts, eg zero-based positon of '#' in '#Header within doc'

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

	# Skip any line that has a header element <h1> <h2> etc or doesn't have a header delimiter.
	if (index($$txtR, '><h') > 0 || index($$txtR, '"') < 0)
		{
		return;
		}

	# Init variables with "Internal Links" scope.
	$line   = $$txtR;
	$len    = length($line);
	@repStr = ();             # new link, eg <a href="#Header_within_doc">#Header within doc</a>
	@repLen = ();             # length of substr to replace in line, eg length('#Header within doc')
	@repStartPos = ()
		; # where header being replaced starts, eg zero-based positon of '#' in '#Header within doc'

	EvaluateInternalLinkCandidates($sectionIdExistsH);

	# Do all reps in reverse order at end.
	my $numReps = @repStr;
	if ($numReps)
		{
		for (my $i = $numReps - 1 ; $i >= 0 ; --$i)
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
		# Note stripping HTML elements will also strip trailing </td></td> if we're at end of line.
		$potentialID =~ s!<[^>]+>!!g;
		# File links can have &nbsp;
		$potentialID =~ s!&nbsp;!_!g;
		# Quotes don't help either.
		$potentialID =~ s!['"]!!g;
		# Convert spaces to underscores too.
		$potentialID =~ s! !_!g;
		# Remove unicode symbols from $id, especially the ones inserted by markdown above, to make
		# it easier to type the headers in links.
		# Eg 'server swarm.txt#TODO_List' for header '&#127895;TODO List'.
		$potentialID =~ s!\&#\d+;!!g;    # eg &#9755;

		# Have we matched a known header with our (potential) ID?
		my $haveGoodMatch = 0;
		if (defined($sectionIdExistsH->{$potentialID}))
			{
			# No match if '#' was inside a pre-existing file anchor.
			if (!InsideExistingAnchor('"', $currentMatchEndPos))
				{
				$haveGoodMatch = 1;
				my $repStartPosition = $currentMatchStartPos;
				my $repLength        = $currentMatchEndPos - $currentMatchStartPos + 1;

				# <a href="#Header_within_doc">Header within doc</a>
				# At this point, $repString is just the anchor $potentialID.
				my $srcHeader         = substr($line, $repStartPosition, $repLength);
				my $replacementAnchor = "<a href=\"#$potentialID\">$srcHeader</a>";
				push @repStr,      $replacementAnchor;
				push @repLen,      $repLength;
				push @repStartPos, $repStartPosition;
				}
			}

		# On to the next match, if any. For a good match, skip past the current matching text.
		# For a bad match, just skip past the current starting quote.
		$currentMatchStartPos =
			($haveGoodMatch) ? $currentMatchEndPos + 1 : $currentMatchStartPos + 1;
		$currentMatchEndPos = -1;
		if (   $currentMatchStartPos < $len - 2
			&& $line =~ m!^.{$currentMatchStartPos}.*?(["])!)
			{
			$currentMatchStartPos = $-[1];
			if (   $currentMatchStartPos < $len - 2
				&& $line =~ m!^.{$currentMatchStartPos}..*?(["])!)
				{
				$currentMatchEndPos = $-[1];
				}
			}

		if ($currentMatchEndPos < 0)
			{
			$currentMatchStartPos = -1;
			}
		}    # while ($currentMatchStartPos > 0)
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
		my $nextAnchorStartPos = index($line, '<a ',  $currentPos);
		my $nextAnchorEndPos   = index($line, '</a>', $currentPos);
		if ($nextAnchorEndPos >= 0
			&& ($nextAnchorStartPos < 0 || $nextAnchorEndPos < $nextAnchorStartPos))
			{
			$insideExistingAnchor = 1;
			}
		}

	return ($insideExistingAnchor);
}
}    ##### Internal Links

# Date time stamp in millisecons.
# See also common.pm#DateSizeString().
sub GetTimeStamp {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = "0";
	if (defined($formH->{'href'}))
		{
		my $filePath = $formH->{'href'};
		my $modDate  = GetFileModTimeWide($filePath);
		$result = $modDate;
		}

	return ($result);
}

sub DiffSpecificsPopup {
	my $result = <<'FINIS';
<div id='uniqueDiffSpecificsOverlay' class='diffOverlay'>
<div class='diffContent' id='diffContentId'>
<button id="closeDiffsButtonId" onclick="closeDiffPopup();">X</button>
<div id='theActualDiffs'>
</div>
</div>
</div>
FINIS

	return ($result);
}

# Obsolete, CodeMirror is being used instead for Perl display.
# Much as AddInternalLinksToLine() just above, but only single words
# are examined for a match against a TOC entry, and word must be followed immediately by '('
# (possibly with intervening span markup),
# which limits links to sub() mentions, in code or comments.
# Or preceded by '&', meaning a subrouting reference.
# OUTSIDE of a comment, a sub call looks like:
#		<span class="Subroutine">MakeDirectoriesForFile</span>\s*<span class="Symbol">(</span>....
# INSIDE of a comment, it's just
# 		MakeDirectoriesForFile(....
# sub AddInternalLinksToPerlLine {
# 	my ($txtR, $sectionIdExistsH) = @_;

# 	# Skip any line that does have a '(' or '&amp;' or is a sub definition.
# 	if ((index($$txtR, '(') < 0 && index($$txtR, '&amp;') < 0) || index($$txtR, 'sub<') > 0)
# 		{
# 		return;
# 		}

# 	my $line = $$txtR;

# 	# These replacements are more easily done in reverse order to avoid throwing off the start/end.
# 	my @repStr;    # new link, eg <a href="#GetBinFile">GetBinFile</a>(...)
# 	my @repLen;    # length of substr to replace in line, eg length('GetBinFile')
# 	my @repStartPos
# 		;    # where header being replaced starts, eg zero-based positon of 'B' in 'GetBinFile'

# 	my $currentMatchEndPos = 0;
# 	while (($currentMatchEndPos = index($line, '(', $currentMatchEndPos)) > 0)
# 		{
# 		my $haveGoodMatch = 0;
# 		# Find end and start of any word before '('. Skip over span stuff if it's code, not comment.
# 		my $wordEndPos = $currentMatchEndPos;
# 		if (substr($line, $wordEndPos - 1, 1) eq '>')
# 			{
# 			$wordEndPos = rindex($line, '<', $wordEndPos);
# 			$wordEndPos = rindex($line, '>', $wordEndPos) unless $wordEndPos < 0;
# 			$wordEndPos = rindex($line, '<', $wordEndPos) unless $wordEndPos < 0;
# 			}
# 		#else assume subroutine name is immediately before the '('.
# 		# If no word end, keep going.
# 		if ($wordEndPos < 0)
# 			{
# 			++$currentMatchEndPos;
# 			next;
# 			}

# 		my $wordStartPos  = rindex($line, ' ', $wordEndPos);
# 		my $rightAnglePos = rindex($line, '>', $wordEndPos);
# 		if ($rightAnglePos > 0 && ($wordStartPos < 0 || $rightAnglePos > $wordStartPos))
# 			{
# 			$wordStartPos = $rightAnglePos;
# 			}
# 		my $hashPos = rindex($line, '#', $wordEndPos);
# 		if ($hashPos > 0 && ($wordStartPos < 0 || $hashPos > $wordStartPos))
# 			{
# 			$wordStartPos = $hashPos;
# 			}
# 		++$wordStartPos;    # Skip the space or > or #.

# 		my $potentialID = substr($line, $wordStartPos, $wordEndPos - $wordStartPos);
# 		# Have we matched a known header with our (potential) ID?
# 		if (defined($sectionIdExistsH->{$potentialID}))
# 			{
# 			$haveGoodMatch = 1;
# 			my $charBeforeMatch = substr($line, $wordStartPos - 1, 1);
# 			if ($charBeforeMatch eq '#')
# 				{
# 				my $insideExistingAnchor = 0;
# 				# Is there an anchor on the line?
# 				if (index($line, '<a') > 0)
# 					{
# 					# Does the anchor enclose the header mention? That's a hard one.
# 					#<a href="http://192.168.0.3:43129/?href=c:/perlprogs/mine/notes/server swarm.txt#Set_HTML" target="_blank">server swarm.txt#Set_HTML</a>
# 					# If it's in the href, it will be preceded immediately by a port number.
# 					# If it's displayed as the anchor content, it will be preceded immediately
# 					# by a file extension.
# 					# REVISION if followed by single or double quote, but there isn't a
# 					# matching single or double quote before the #, skip it.
# 					#$posSep = index($line, '.', $prevPos);
# 					my $currentPos         = $wordEndPos;
# 					my $nextAnchorStartPos = index($line, '<a ',  $currentPos);
# 					my $nextAnchorEndPos   = index($line, '</a>', $currentPos);
# 					if ($nextAnchorEndPos >= 0
# 						&& ($nextAnchorStartPos < 0 || $nextAnchorEndPos < $nextAnchorStartPos))
# 						{
# 						$insideExistingAnchor = 1;
# 						}
# 					}

# 				if ($insideExistingAnchor)
# 					{
# 					$haveGoodMatch = 0;
# 					}
# 				else
# 					{
# 					# Skip if we see \w# before the word, likely meaning that a file name precedes
# 					# the word and it's really a link to another file.
# 					if ($wordStartPos > 2)
# 						{
# 						my $charBefore = substr($line, $wordStartPos - 2, 1);
# 						my $ordCB      = ord($charBefore);
# 						my $isExtensionChar =
# 							(      ($ordCB >= $ORD_a && $ordCB <= $ORD_z)
# 								|| ($ordCB >= $ORD_A && $ordCB <= $ORD_Z)
# 								|| ($ordCB >= $ORD_0 && $ordCB <= $ORD_9));
# 						if ($isExtensionChar)
# 							{
# 							$haveGoodMatch = 0;
# 							}
# 						}
# 					}
# 				}

# 			if ($haveGoodMatch)
# 				{
# 				# <a href="#potentialID">potentialID</a>
# 				push @repStr,      "<a href=\"#$potentialID\">$potentialID</a>";
# 				push @repStartPos, $wordStartPos;
# 				push @repLen,      $wordEndPos - $wordStartPos;
# 				}
# 			}

# 		++$currentMatchEndPos;
# 		}    # while ($currentMatchEndPos = (index($line, '(', $currentMatchEndPos)) > 0)

# 	# Also look for \&Subname. In practice, &Subname should do.
# 	# (Note & is &amp; in the HTML.)
# 	my $currentMatchStartPos = 0;
# 	while (($currentMatchStartPos = index($line, '&amp;', $currentMatchStartPos)) > 0)
# 		{
# 		# If chars following the '&' form a word, look it up in TOC entries.
# 		my $wordStartPos = $currentMatchStartPos + 5;
# 		my $wordEndPos   = $wordStartPos;
# 		my $nextChar     = substr($line, $wordEndPos, 1);
# 		my $ordNC        = ord($nextChar);
# 		while (($ordNC >= $ORD_a && $ordNC <= $ORD_z)
# 			|| ($ordNC >= $ORD_A && $ordNC <= $ORD_Z)
# 			|| ($ordNC >= $ORD_0 && $ordNC <= $ORD_9))
# 			{
# 			++$wordEndPos;
# 			$nextChar = substr($line, $wordEndPos, 1);
# 			$ordNC    = ord($nextChar);
# 			}
# 		if ($wordEndPos > $wordStartPos)
# 			{
# 			my $potentialID = substr($line, $wordStartPos, $wordEndPos - $wordStartPos);
# 			if (defined($sectionIdExistsH->{$potentialID}))
# 				{
# 				push @repStr,      "<a href=\"#$potentialID\">$potentialID</a>";
# 				push @repStartPos, $wordStartPos;
# 				push @repLen,      $wordEndPos - $wordStartPos;
# 				}
# 			$currentMatchStartPos += ($wordEndPos - $wordStartPos);
# 			}
# 		else
# 			{
# 			$currentMatchStartPos += 5;
# 			}
# 		}

# 	# Do all reps in reverse order at end.
# 	my $numReps = @repStr;
# 	if ($numReps)
# 		{
# 		for (my $i = $numReps - 1 ; $i >= 0 ; --$i)
# 			{
# 			# substr($line, $pos, $srcLen, $repString);
# 			substr($line, $repStartPos[$i], $repLen[$i], $repStr[$i]);
# 			}
# 		$$txtR = $line;
# 		}
# }

############## Video support
# Create a temporary .bat file containing the full path of the video,
# run the .bat file to open the video using default video player.
# chcp 65001 is done first to allow "Unicode" in the path.
# (goto) 2>nul & del \"%~f0\" deletes the bat file after the video player is closed.
# (If delete doesn't happen for some reason, intramine_filewatcher.pl#DeleteOldTempFiles()
# will limit the number of temp files every now and then.)
# Typical .bat file contents:
#    chcp 65001
#    "c:/perlprogs/intramine/test/video/rabbit320 × %.mp4"
#    (goto) 2>nul & del \"%~f0\"
sub ShowVideo {
	my ($obj, $formH, $peeraddress, $clientIsRemote) = @_;
	# Remote video viewing is not (yet) possible.
	if ($clientIsRemote)
		{
		return;
		}

	if (defined($formH->{'href'}))
		{
		$formH->{'FULLPATH'} = $formH->{'href'};
		}

	my $filePath = $formH->{'FULLPATH'};
	my $exists   = FileOrDirExistsWide($filePath);
	if (!$exists)
		{
		$filePath = "Error, |$filePath| not found on disk.\n";
		}
	else
		{
		# Experiment: open video directly in bat file.
		my $proc;
		my $status      = '';                                                           # Not used
		my $batContents = "chcp 65001\n\"$filePath\"\n(goto) 2>nul & del \"%~f0\"\n";
		my $tempBatPath = TempVideoPath('bat');
		WriteUTF8FileWide($tempBatPath, $batContents);
		# Run the .bat file.
		Win32::Process::Create($proc, $ENV{COMSPEC}, "/c \"$tempBatPath\" >nul", 0, 0, ".")
			|| ($status = Win32::FormatMessage(Win32::GetLastError()));
		}
}

# Make up a file path, hiding the file in IntraMine's Log folder.
sub TempVideoPath {
	my ($extNoPeriod)  = @_;
	my $LogDir         = FullDirectoryPath('LogDir');
	my $basePath       = $LogDir . 'temp/tempvideo';
	my $randomInteger2 = random_int_between(1001, 60000);
	my $tempVideoPath  = $basePath . time . $randomInteger2 . '.' . $extNoPeriod;
	return ($tempVideoPath);
}

# Some of the code below opens a video in the browser, not currently used.

# Not used
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

	return ($theBody);
}

# Not used
sub VideoElement {
	my ($filePath) = @_;

	my $theBody = <<'FINIS';
<video controls>
  <source src="_FILEPATH_"_MIMETYPE_ />
  <p>Sorry, your browser doesn't support this video.</p>
</video>
FINIS

	$filePath =~ s!\\!/!g;
	$theBody  =~ s!_FILEPATH_!$filePath!;
	my $mimeType    = VideoMimeTypeForPath($filePath);
	my $mimeTypeAtt = '';
	if ($mimeType ne '')
		{
		$mimeTypeAtt = " type='$mimeType'";
		}
	$theBody =~ s!_MIMETYPE_!$mimeTypeAtt!;

	return ($theBody);
}

# Not used
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

	return ($mimeType);
}

# Not used
sub SaveTempVideoFile {
	my ($theBody)      = @_;
	my $LogDir         = FullDirectoryPath('LogDir');
	my $basePath       = $LogDir . 'temp/tempvideo';
	my $randomInteger2 = random_int_between(1001, 60000);
	my $tempVideoPath  = $basePath . time . $randomInteger2 . '.html';
	WriteBinFileWide($tempVideoPath, $theBody);
	return ($tempVideoPath);
}

# Not used
sub OpenTempVideoFile {
	my ($tempVideoPath) = @_;
	my $proc;
	my $status = '';

	Win32::Process::Create($proc, $ENV{COMSPEC}, "/c $tempVideoPath", 0, 0, ".")
		|| ($status = Win32::FormatMessage(Win32::GetLastError()));
}
