# intramine_search.pl: 'Search' page: answer JavaScript fetch() for search form, or search results.
# Return search form table, and any search results. This version uses Elasticsearch.
#  https://www.elastic.co/guide/en/elasticsearch/client/perl-api/current/contents.html
#
# See also Documentation/Search.html.
#
# SearchPage() returns an HTML skeleton for the page, and sets some JavaScript variables.
# The search form is loaded from JavaScript with a "req=frm" call, see also
# intramine_search.js#loadPageContent(), which is called when the page is "ready".
# Search results provide view and edit links for text files with a context fragment,
# and image files are given hover (show image on mouse hover) and view links.
#
# Searches can  be limited to specific folders, optionally including subfolders,
# and limited to specific languages. Results can be sorted in various ways
# (see intramine_search.js#sortSearchResults()).

# perl C:\perlprogs\mine\intramine_search.pl 81 43124

use strict;
use warnings;
use utf8;
use HTML::Entities;
#use Win32::FindFile;
use Time::Piece;
use Time::HiRes qw ( time );
use Win32;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use elasticsearcher;
use swarmserver;
use win_wide_filepaths;
use ext;

binmode(STDOUT, ":encoding(UTF-8)");
Win32::SetConsoleCP(65001);

#binmode(STDOUT, ":unix:utf8");
$|  = 1;

my $PAGENAME = '';
my $SHORTNAME = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

my $UseAppForLocalEditing = CVal('USE_APP_FOR_EDITING');
my $UseAppForRemoteEditing = CVal('USE_APP_FOR_REMOTE_EDITING');
my $AllowLocalEditing = CVal('ALLOW_LOCAL_EDITING');
my $AllowRemoteEditing = CVal('ALLOW_REMOTE_EDITING');

my $SHOWFILESIZESANDMODDATES = 1;
my $FILESIZEUNITS = [qw(B KB MB GB TB PB)];

my $kLOGMESSAGES = 0;			# 1 == Log Output() messages
my $kDISPLAYMESSAGES = 0;		# 1 == print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print.
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);
Output("Starting $SHORTNAME on port $port_listen\n\n");

my $FULL_ACCESS_STR = CVal('FULL_ACCESS_STR'); 						# See data\intramine_config.txt
# Obsolete my $ALWAYS_REMOTE_FOR_EDITING = CVal('ALWAYS_REMOTE_FOR_EDITING');

# Fire up the full text search engine.
my $esIndexName = CVal('ES_INDEXNAME'); # default 'intramine'
if ($esIndexName eq '')
	{
	print("Warning, ES_INDEXNAME is not set in intramine_config.txt config file. Using default of 'intramine'.\n");
	$esIndexName = 'intramine';
	}
my $numHits = CVal('ES_NUMHITS');
if ($numHits eq '' || $numHits == 0)
	{
	print("Warning, ES_NUMHITS is not set in intramine_config.txt config file. Using default of 25.\n");
	$numHits = 25;
	}
my $ElasticSearcher = elasticsearcher->new($esIndexName, $FULL_ACCESS_STR, $numHits);

my $kAllowNoExtension = CVal('ES_INDEX_NO_EXTENSION');

my %RequestAction;
$RequestAction{'req|main'} = \&SearchPage; 			# req=main  DEFAULT PAGE ACTION
$RequestAction{'req|frm'} = \&SearchForm; 			# req=frm
$RequestAction{'req|results'} = \&SearchResults; 	# req=results
$RequestAction{'dir'} = \&GetDirsAndFiles; 			# $formH->{'dir'} is directory path
$RequestAction{'/test/'} = \&SelfTest;				# Ask this server to test itself.
$RequestAction{'req|docCount'} = \&CountOfIndexedDocuments;	# see eg test_programs/test_Search.pl

#$RequestAction{'req|id'} = \&Identify; 			# req=id

# Over to swarmserver.pm to listen for requests.
MainLoop(\%RequestAction);

################ subs
# Return Search page, with form, and JavaScript to drive searching and display of search results.
# This responds to requests such as http://IntraMineIP:port/Search
# where port can be for main (default 81) or a swarm server (default 43125..43172).
sub SearchPage {
	my ($obj, $formH, $peeraddress) = @_;

	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>Full Text Search</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="forms.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
<link rel="stylesheet" type="text/css" href="jqueryFileTree.css" />
<link rel="stylesheet" type="text/css" href="search.css" />
_THEME_
</head>
<body>
_TOPNAV_
<div id="searchform">loading...</div>
<div id='headingAboveContents'>&nbsp;</div>
<div id="scrollAdjustedHeight">no results yet...</div>
<script>
let weAreRemote = _WEAREREMOTE_;
let allowEditing = _ALLOW_EDITING;
let useAppForEditing = _USE_APP_FOR_EDITING;
let thePort = '_THEPORT_';
let clientIPAddress = '_CLIENT_IP_ADDRESS_';
let viewerShortName = '_VIEWERSHORTNAME_';
let openerShortName = '_OPENERSHORTNAME_';
let editorShortName = '_EDITORSHORTNAME_';
let errorID = "headingAboveContents";
</script>
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="restart.js"></script>
<script src="topnav.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
<script src="tooltip.js"></script>
<script src="quicksort.js"></script>
<script src="jquery-3.4.1.min.js"></script>
<script src="jquery.easing.1.3.min.js"></script>
<!--
<script src="jquery-3.1.0.min.js"></script>
<script src="jquery.easing.js"></script>
-->
<script src="jqueryFileTree.js"></script>
<script src="viewerLinks.js"></script>
<script src="lru.js"></script>
<script src="intramine_search.js"></script>
</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);
	$theBody =~ s!_TOPNAV_!$topNav!;
	
	# The IPv4 Address for this server (eg 192.168.0.14);
	# peeraddress might be eg 192.168.0.17
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
	
	# Set some JavaScript variables.
	$theBody =~ s!_WEAREREMOTE_!$amRemoteValue!;
	$theBody =~ s!_ALLOW_EDITING!$tfAllowEditing!;
	$theBody =~ s!_USE_APP_FOR_EDITING!$tfUseAppForEditing!;
	$theBody =~ s!_THEPORT_!$port_listen!;
	$theBody =~ s!_CLIENT_IP_ADDRESS_!$peeraddress!;
	my $viewerShortName = CVal('VIEWERSHORTNAME');
	my $openerShortName = CVal('OPENERSHORTNAME');
	my $editorShortName = CVal('EDITORSHORTNAME');
	$theBody =~ s!_VIEWERSHORTNAME_!$viewerShortName!;
	$theBody =~ s!_OPENERSHORTNAME_!$openerShortName!;
	$theBody =~ s!_EDITORSHORTNAME_!$editorShortName!;

	# Set the selected theme.
	my $theme = CVal('THEME');
	# DISABLED for now, perhaps later, there's a bit of work involved
	# in getting the Search page to display properly. Some text should
	# have a color change, and some shouldn't.
	#my $nonCmThemeCssFile =  NonCodeMirrorThemeCSS($theme);
	#$theBody =~ s!_THEME_!$nonCmThemeCssFile!;
	$theBody =~ s!_THEME_!!;

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
		print("ERROR could not find |$cssPath|\n");
		return('');
		}

	return("\n" . '<link rel="stylesheet" type="text/css"  href="/viewer_themes/' . $themeName . '_IM.css">' . "\n");
	}

# Return the Search form, with the usual standard search fields.
# Allow "no extension" only if $kAllowNoExtension=1.
# 2019-10-23 14_30_47-Full Text Search.png
sub SearchForm {
	my ($obj, $formH, $peeraddress) = @_;
	
	my $boxNoExtension = ($kAllowNoExtension == 1) ?
		"<label><input type=checkbox name='EXT_NONE' value='yes'>no extension</label>" : '';
	
	# A dropdown of many languages and their extensions, with check boxes.
	my $extsForLan = ExtensionsForLanguageHashRef();
	my $popularExtsForLan = PopularExtensionsForLanguageHashRef();
	my $languageItems = '';

	$languageItems .= "<a href='javascript:selectAllOrNone(true);' class='allOrNone'>All</a>&nbsp;&nbsp;";
	$languageItems .= "<a href='javascript:selectAllOrNone(false);' class='allOrNone'>None</a>";
	foreach my $key (sort keys %$popularExtsForLan)
		{
		my $nicerExtensionList = $popularExtsForLan->{$key};
		$nicerExtensionList =~ s!,!, !g;
		$languageItems .= "<label><input type=checkbox name='EXT_$key' value='yes'>$key ($nicerExtensionList)</label>";
		}
	$languageItems .= "<div>- - - - - - - - - - - - - - (and more below)</div>";
	foreach my $key (sort keys %$extsForLan)
		{
		if (!defined($popularExtsForLan->{$key}))
			{
			my $nicerExtensionList = $extsForLan->{$key};
			$nicerExtensionList =~ s!,!, !g;
			$languageItems .= "<label><input type=checkbox name='EXT_$key' value='yes'>$key ($nicerExtensionList)</label>";
			}
		}
	$languageItems .= $boxNoExtension;

	# THe dropdown for extensions, alphabetically.
	my $extensionItems = '';
	$extensionItems .= "<a href='javascript:selectAllOrNone(true);' class='allOrNone'>All</a>&nbsp;&nbsp;";
	$extensionItems .= "<a href='javascript:selectAllOrNone(false);' class='allOrNone'>None</a>";

	my %extensionsH;
	foreach my $key (sort keys %$extsForLan)
		{
		my $nicerExtensionList = $extsForLan->{$key};
		my @extensionsForLanguage = split(/,/, $nicerExtensionList);
		for (my $i = 0; $i < @extensionsForLanguage; ++$i)
			{
			$extensionsH{$extensionsForLanguage[$i]} = 1;
			}
		}

	foreach my $key (sort keys %extensionsH)
		{
		$extensionItems .= "<label><input type=checkbox name='EXT_$key' value='yes'>$key</label>";
		}
	
	my $languageDropdown = <<"TOHERE";
<div class="multiselect">
	<div class="selectBox" onclick="showCheckboxes()">
	  <select>
		<option id='multiLanguageSummary'>(all languages are selected)</option>
	  </select>
	  <div class="overSelect"></div>
	</div>
	<div id="checkboxes">
		$languageItems
	</div>
</div>
<div id='languageDropdownItems'>
$languageItems
</div>
<div id='extensionDropDownItems'>
$extensionItems
</div>
TOHERE

	my $sortByDropdown = <<'ENDIT';
<strong>Sort by:</strong> <select name="sortBy" id="sortBy" onchange="sortSearchResults(this)">
<option value="Score" selected="selected">Score</option>
<option value="Name">Name</option>
<option value="Date">Date</option>
<option value="Extension">Extension</option>
<option value="Size">Size</option>
</select>
ENDIT

	# The Search form proper:
	my $theSource = <<"FINIS";
<form class="form-container" id="ftsform" method="get" action=_ACTION_ onsubmit="searchSubmit(this); return false;">

<div id="form_1_1" class="formItemTitle"><h2>Search for&nbsp;</h2>
<input id="searchtext" class="form-field" type="search" name="findthis" placeholder='type here eh' list="searchlist" required /></div>
<div id="form_2_1"><label><input type='checkbox' name='matchexact' value='yes'>Match Exact Phrase</label></div>
<div id="form_3_1">_DOCCOUNT_</div>

<div id="form_1_2" class="formItemTitle"><h2>Directory&nbsp;</h2>
<input type="search" id="searchdirectory" class="form-field" name="searchdirectory" placeholder='type a path, hit the dots->, or leave blank for all dirs' list="dirlist" /></div>
<div id="form_2_2"><div id="annoyingdotcontainer"><img id="dotdotdot" src="dotdotdot24x48.png" onclick="showDirectoryPicker();" /></div></div>
<div id="form_3_2"><label><input type='checkbox' id="subDirCheck" name='subdirs' value='yes'_CHECKEDBYDEFAULT_>Subdirectories too</label></div>
<datalist id="searchlist">
</datalist>
<datalist id="dirlist">
</datalist>

<div id="form_1_3" class="formItemTitle">
<div id="languageGrid">
<div>
  <input type="radio" id="byLanguage" name="langExt" value="languageDropdownItems" onchange="swapLangExt();"
         checked>
  <label for="byLanguage"><h2>Language</h2>&nbsp;</label>
</div>
<div>
  <input type="radio" id="byExtension" name="langExt" value="extensionDropDownItems" onchange="swapLangExt();">
  <label for="byExtension"><h2>Extension</h2>&nbsp;</label>
</div>	<div id="languageDropdown">$languageDropdown</div>
</div>
</div>

<div id="form_2_3">$sortByDropdown</div>

<div id="form_3_3"><div class='submitbuttonthecontainer'>
		<input id="searchSubmitButton" class="submit-button" type="submit" value="Search" />
		</div></div>

<!-- <div id="form_1_4"><div id="languageSummaryDiv"><div id="languageSummary">(all are selected)</div></div></div>
<div id="form_2_4"></div>
<div id="form_3_4"></div> -->
</form>
FINIS

	# Rev May 26 2021, localhost is no longer used here.
	# Required by Chrome for "CORS-RFC1918 Support".
	my $serverAddr = ServerAddress();
	my $action = "http://$serverAddr:$port_listen/?rddm=1";

	$theSource =~ s!_ACTION_!\'$action\'!;
	
	# <div id='docCount'>_DOCCOUNT_</div>
	my $documentCount = Commify(CountOfIndexedDocuments());
	$documentCount = $documentCount . ' docs indexed';
	# Cluster health: set background colour of span id='docCount' to red/yellow/green.
	my $clusterStatus = lc(ClusterHealth()); # red yellow green
	my $healthClass = 'light' . $clusterStatus . 'Back'; # css .lightredBack etc - see forms.css#lightredBack
	my $docCountElement = "<div id='docCount' class='$healthClass'>$documentCount</div>";
	$theSource =~ s!_DOCCOUNT_!$docCountElement!;
	# Check "Subdirectories too" if config says to.
	my $checkSubdirsByDefault = CVal('SEARCH_SUBDIRS_BY_DEFAULT');
	my $checkSubsValue = ($checkSubdirsByDefault) ? ' checked': ''; # note the space
	$theSource =~ s!_CHECKEDBYDEFAULT_!$checkSubsValue!;
	
	# A separate dropdown selector for the directory picker.
	$theSource .= DirectoryPicker();
	
	return $theSource;
	}

# See intramine_search.js#showDirectoryPicker() for use. This is a simplified version of the picker
# used on the Files page, the main difference is that file links are omitted here.
sub DirectoryPicker {
my $theSource = <<'FINIS';
<!--<form id="dirform">-->
<div id='dirpickerMainContainer'>
	<p id="directoryPickerTitle">Directory Picker</p>
	<div id='dirpicker'>
		<div id="scrollAdjustedHeightDirPicker">
			<div id="fileTreeLeft">
				<select id="driveselector_1" name="drive selector" onchange="driveChanged('scrollDriveListLeft', this.value);">
				  _DRIVESELECTOROPTIONS_
				</select>
				<div id='scrollDriveListLeft'>placeholder for drive list
				</div>
			</div>
		</div>
		<div id="pickerDisplayDiv">Selected directory:&nbsp;<span id="pickerDisplayedDirectory"></span></div>
	</div>
	<div id="okCancelHolder">
		<input type="button" id="dirOkButton" value="OK" onclick="setDirectoryFromPicker(); return false;" />
		<input type="button" id="dirCancelButton" value="Cancel" onclick="hideDirectoryPicker(); return false;" />
	</div>
</div>

<!--</form>-->
FINIS
	
	# Put a list of drives in the drive selector.
	my $driveSelectorOptions = DriveSelectorOptions();
	$theSource =~ s!_DRIVESELECTOROPTIONS_!$driveSelectorOptions!g;
	return $theSource;
	}

# Call Elasticsearch to do a search,
# return <div> containing Elasticsearch hit summary for passed-in $formH->{'findthis'}.
# Results can be filtered by extensions corresponding to one or more languages,
# and by containing folder (optionally including subfolders).
# The default search matches supplied search words anywhere in a document,
# selecting "Match Exact Phrase" means just that.
# Called by intramine_search.js#searchSubmit().
sub SearchResults {
	my ($obj, $formH, $peeraddress) = @_;
	my $rawquery = defined($formH->{'findthis'})? $formH->{'findthis'}: '';
	$rawquery =~ s!^\s+!!;
	$rawquery =~ s!\s+$!!;
	my $shouldQuote = defined($formH->{'matchexact'})? 1: 0;
	my $dir = defined($formH->{'directory'})? $formH->{'directory'}: 'ALL';
	if ($dir eq '')
		{
		$dir = 'ALL';
		}
	my $doSubDirs = defined($formH->{'subdirs'})?1: 0;
		
	if ($shouldQuote && $rawquery ne '')
		{
		if (index($rawquery, '"') != 0)
			{
			$rawquery = "\"$rawquery\"";
			}
		}
	else
		{
		; # Leave any user-typed quotes, sometimes typing is quicker.
		}
		
	# Extension filter, provided as wanted language names, eg $formH{'EXT_Plain%20Text'}='yes'.
	# See ext.pm for the corresponding lists of extensions for languages.
	my @wantedExt;
	my $allExtensionsSelected;
	GetWantedExtensions($formH, \@wantedExt, \$allExtensionsSelected);

	# Directory filter.
	my $folderSearchFilterName = ''; # for 'ALL', don't bother filtering
	GetDirectoryFilter(\$dir, \$folderSearchFilterName, $doSubDirs, $allExtensionsSelected);
		
	my $result = "";
	
	if (length($rawquery) == 0)
		{
		$result = '<p>Please provide something to Search for</p>';
		}
	else
		{
		Output("Searching for |$rawquery|\n");
		my $t1 = time;
		my $remote = (defined($formH->{'remote'})) ? $formH->{'remote'}: '0';
		my $alllowEditing = (defined($formH->{'allowEdit'})) ? $formH->{'allowEdit'}: '0';
		my $useAppForEditing = (defined($formH->{'useApp'})) ? $formH->{'useApp'}: '0';
		
		my $numHitsDisplayed = 0;
		my $numFiles = 0;
		# See elasticsearch_bulk_indexer.pm#AddDocumentToIndex() for details on the indexed
		# fields (especially "folder1" "folder2". Those are used to speed up searching
		# specific directories by looking only at files at a particular "depth", where depth is
		# measured by the number of '/' slashes in the path to a folder).
		# elasticsearcher.pm#GetPhraseHits() and getWordHits() build and exec the search.
		$result .= "<div id='theTextWithoutJumpList'>" . $ElasticSearcher->GetSearchResults($rawquery, 
			$remote, $alllowEditing, $useAppForEditing, \@wantedExt, $allExtensionsSelected,
			$folderSearchFilterName, $dir, \$numHitsDisplayed, \$numFiles) . '</div>';
		my $elapsed = time - $t1;
		my $ruffElapsed = substr($elapsed, 0, 4);
		if ($numFiles >= $numHits)
			{
			$result = "<span> ($ruffElapsed seconds, best $numHits files listed)</span>" . $result;
			}
		else
			{
			$result = "<span> ($ruffElapsed seconds, $numFiles files)</span>" . $result;
			}
		}
	
	return $result;
	}


# Push wanted extensions into an array ref $wantedExtA, in accordance with user-selected
# languages in the Search form. There are many languages, and over 200 extensions.
# So it's handy to set $$allExtensionsSelectedR to 1 (true) if all languages have been
# selected, in which case there's no need to ask Elasticsearch to filter on extension.
# See ext.pm for the corresponding lists of extensions for languages.
sub GetWantedExtensions {
	my ($formH, $wantedExtA, $allExtensionsSelectedR) = @_;
	my $extFilter = defined($formH->{'extFilter'}) ? $formH->{'extFilter'} : 'languageDropdownItems';

	if ($extFilter =~ m!language!i)
		{
		GetWantedLanguageExtensions($formH, $wantedExtA, $allExtensionsSelectedR);
		}
	else
		{
		GetwantedExplicitExtensions($formH, $wantedExtA, $allExtensionsSelectedR);
		}
	}

sub GetWantedLanguageExtensions {
	my ($formH, $wantedExtA, $allExtensionsSelectedR) = @_;

	# Extension filter, provided as wanted language names, eg $formH{'EXT_Plain%20Text'}='yes'.
	my $extsForLan = ExtensionsForLanguageHashRef();
	my %extensionHasBeenSeen;
	my $extensionNoneIsWanted = 0;
	
	foreach my $key (keys %$formH)
		{
		$key =~ s!\%20! !g;
		$key =~ s!\%2F!/!g;
		$key =~ s!\%2B!\+!g; # C/C++ comes through as C%2FC%2B%2B
		$key =~ s!\%23!#!g; # C# comes through as C%23, similarly F#
		if ($key =~ m!^EXT_(.+?)$!)
			{
			my $languageName = $1;
			if (defined($extsForLan->{$languageName}))
				{
				my $rawExtensions = $extsForLan->{$languageName};
				my @extForLanguage = split(/,/, $rawExtensions);
				for (my $i = 0; $i < @extForLanguage; ++$i)
					{
					if (!defined($extensionHasBeenSeen{$extForLanguage[$i]}))
						{
						my $correctedExt = $extForLanguage[$i];
						push @{$wantedExtA}, $correctedExt;
						}
					$extensionHasBeenSeen{$extForLanguage[$i]} = 1;
					}
				}
			elsif ($languageName =~ m!none!i)
				{
				push @{$wantedExtA}, 'NONE';
				$extensionNoneIsWanted = 1;
				}
			}
		}
	
	# Determine if all extensions are wanted (so no need to filter for extension).
	my $numExtensionsTotal = NumExtensions();
	if ($extensionNoneIsWanted)
		{
		++$numExtensionsTotal;
		}
	my $numExtensionsSeen = keys %extensionHasBeenSeen;
	$$allExtensionsSelectedR = ($numExtensionsTotal == $numExtensionsSeen) ? 1 : 0;
	}

sub GetwantedExplicitExtensions {
	my ($formH, $wantedExtA, $allExtensionsSelectedR) = @_;

	# Extension filter, provided as wanted language names, eg $formH{'EXT_Plain%20Text'}='yes'.
	#my $extsForLan = ExtensionsForLanguageHashRef();
	my %extensionHasBeenSeen;
	my $extensionNoneIsWanted = 0;

	foreach my $key (keys %$formH)
		{
		if ($key =~ m!^EXT_(.+?)$!)
			{
			my $extension = $1;
			push @{$wantedExtA}, $extension;
			$extensionHasBeenSeen{$extension} = 1;
			}
		}

	my $numExtensionsTotal = NumExtensions();
	my $numExtensionsSeen = keys %extensionHasBeenSeen;
	$$allExtensionsSelectedR = ($numExtensionsTotal == $numExtensionsSeen) ? 1 : 0;
	}

# Directory filter.
# See elasticsearch_bulk_indexer.pm#AddDocumentToIndex() for "folderN" index fields.
# Well, since this is an uncommon notion, perhaps some repetition helps.
# All indexed files have "folder1" "folder2" etc index fields that hold the partial
# path to the file corresponding to a depth of 1 2 etc, where "depth" is the number of '/'
# slashes in the path. So a file at 'C:/projects/51/src/main.cpp' has folderN entries
# folder1: C:/
# folder2: C:/projects/
# folder3: C:/projects/51/
# folder4: C:/projects/51/src/
# and all higher numbered folderN entries, folder5 folder6 etc, are ''.
# The folderExtN index entries would be the same, but with "cpp" appended, eg
# folderExt3: C:/projects/51/cpp
sub GetDirectoryFilter {
	my ($dirR, $folderSearchFilterNameR, $doSubDirs, $allExtensionsSelected) = @_;
	my $dir = $$dirR;
	my $dirDepth = 0;
	
	if ($dir ne 'ALL')
		{
		$dir =~ s!\\!/!g;
		if ($dir !~ m!/$!)
			{
			$dir .= '/';
			}
		$dir = lc($dir);
		
		if ($doSubDirs)
			{
			$dirDepth = $dir =~ tr!/!!;
			if ($allExtensionsSelected)
				{
				$$folderSearchFilterNameR = 'folder' . $dirDepth; # folder1, folder2 etc
				}
			else
				{
				$$folderSearchFilterNameR = 'folderExt' . $dirDepth; # folderExt1, folderExt2 etc
				}
			}
		else
			{
			if ($allExtensionsSelected)
				{
				$$folderSearchFilterNameR = 'allfolders';
				}
			else
				{
				$$folderSearchFilterNameR = 'allfoldersExt';
				}
			}
		$dir = DirEncodedForSearching($dir);
		$$dirR = $dir;
		}
	}

# $rawDir should be lc, use forward slashes only, and end with a forward slash.
sub DirEncodedForSearching {
	my ($rawDir) = @_;
	my $encodedPath = $rawDir;
	$encodedPath =~ s![^A-Za-z0-9_]!_!g;
	return($encodedPath);
	}

sub CountOfIndexedDocuments {
	my ($obj, $formH, $peeraddress) = @_;
	return($ElasticSearcher->Count());
	}

sub ClusterHealth {
	return($ElasticSearcher->ClusterHealth());
	}

# Generate the directory and file lists for the Search form. This is called by the
# JavaScript directory file tree display "widget" with a 'dir=path' request,
# where 'path' is a directory or file path.
# See also intramine_search.js#initDirectoryDialog() and jqueryFileTree.js (look for "action").
sub GetDirsAndFiles {
	my ($obj, $formH, $peeraddress) = @_;
	my $dir = $formH->{'dir'};
	my $clientIsRemote = ($formH->{'rmt'} eq 'false') ? 0 : 1;
	my $result = '';
	
	Output("GetDirsAndFiles request for dir: |$dir|\n");
	
	if (FileOrDirExistsWide($dir) == 2)
		{
		# See win_wide_filepaths.pm#FindFileWide().
		my $fullDirForFind = $dir . '*';
		my @allEntries = FindFileWide($fullDirForFind);
		my $numEntries = @allEntries;
		
		if ($numEntries)
			{
			my (@folders, @files);
			my $total = 0;
			
			for (my $i = 0; $i < @allEntries; ++$i)
				{
				my $fileName = $allEntries[$i];
				# Not needed: $fileName = decode("utf8", $fileName);
				my $fullPath = "$dir$fileName";
				if (FileOrDirExistsWide($fullPath) == 2)
					{
					if ($fileName !~ m!^\.\.?$! && substr($fileName, 0, 1) ne '$')
						{
						push @folders, $fileName;
						}
					}
				else
					{
					if ($fileName =~ m!\.\w+$! && $fileName !~ m!\.sys$! && substr($fileName, 0, 1) ne '$')
						{
						push @files, $fileName;
						}
					}
				}
			
			my $numDirs = @folders;
			my $numFiles = @files;
			$total = $numDirs + $numFiles;
			
	        if ($total)
	        	{
	        	my $serverAddr = ServerAddress();
	        	$result = "<ul class=\"jqueryFileTree\" style=\"display: none;\">";
	        	
				# print Folders
				foreach my $file (sort {lc $a cmp lc $b} @folders)
					{
					next if (FileOrDirExistsWide($dir . $file) == 0);
				    $result .= '<li class="directory collapsed"><a href="#" rel="' . 
				          &HTML::Entities::encode($dir . $file) . '/">' . 
				          &HTML::Entities::encode($file) . '</a></li>';
					}

				# print Files
				foreach my $file (sort {lc $a cmp lc $b} @files)
					{
					next if (FileOrDirExistsWide($dir . $file) == 0);
				    
				    my $sizeDateStr =  FileDateAndSizeString($dir, $file);
				    
				    $file =~ /\.([^.]+)$/;
				    my $ext = $1;
				    # Gray out unsuported file types. Show thumbnail on hover for images.
				    if (defined($ext) && IsTextDocxPdfOrImageExtensionNoPeriod($ext))
				    	{
				    	if (IsImageExtensionNoPeriod($ext))
				    		{
				    		$result .= ImageLine($serverAddr, $dir, $file, $ext, $sizeDateStr);
				    		}
				    	else # Text, for the most part - could also be pdf or docx
				    		{
				    		$result .= TextDocxPdfLine($dir, $file, $ext, $sizeDateStr);
				    		}
				    	}
				    else # Unsupported type, can't produce a read-only HTML view.
				    	{
				    	my $fileName = &HTML::Entities::encode($file);
					    $result .= '<li class="file ext_' . $ext . '">' . "<span class='unsupported'>" . $fileName . '</span>' . '</li>';
				    	}
					}
	        	
	        	$result .= "</ul>\n";
	        	}
			}
		# else no files or subfolders
		}
	else
		{
		print("ERROR, |$dir| not found!\n");
		}
	
	$result = ' ' if ($result eq ''); # return something (but not too much), to avoid 404
	
	return($result);
	}

sub FileDateAndSizeString {
	my ($dir, $file) = @_;
	my $sizeDateStr = '';
	
	if (!$SHOWFILESIZESANDMODDATES)
		{
		return($sizeDateStr);
		}
	
	my $modDate = GetFileModTimeWide($dir . $file);
	my $dateStr = localtime($modDate)->datetime;

	my $sizeBytes = GetFileSizeWide($dir . $file);
	my $exp = 0;
	my $sizeStr = '';
	for (@$FILESIZEUNITS)
		{
		last if $sizeBytes < 1024;
		$sizeBytes /= 1024;
		$exp++;
		}
	if ($exp == 0)
		{
		$sizeStr = sprintf("%d %s", $sizeBytes, $FILESIZEUNITS->[$exp]);
		}
	else
		{
		$sizeStr = sprintf("%.1f %s", $sizeBytes, $FILESIZEUNITS->[$exp]);
		}
    
     if ($dateStr ne '' || $sizeStr ne '')
    	{
    	$sizeDateStr = "<span>";
    	if ($dateStr ne '')
    		{
    		$sizeDateStr .= $dateStr;
    		}
    	if ($sizeStr ne '')
    		{
    		if ($dateStr ne '')
    			{
    			$sizeDateStr .= ' ';
    			}
    		$sizeDateStr .= $sizeStr;
    		}
    	$sizeDateStr .= "</span>";
    	}

	return($sizeDateStr);
	}

# Image lines in the directory picker get a "show image on mouse hover" onmouseover action.
# Which isn't really needed, just showing off a bit:) Images can't be searched for.
# See GetDirsAndFiles() above.
sub ImageLine {
	my ($serverAddr, $dir, $file, $ext, $sizeDateStr) = @_;
	my $imagePath = $dir . $file;
	my $imageHoverPath = $imagePath;
	$imageHoverPath =~ s!%!%25!g;
	my $imageName = $file;
	$imageName = &HTML::Entities::encode($imageName);	# YES this works fine!		    		
	$imagePath = &HTML::Entities::encode($imagePath);
	$imageHoverPath = &HTML::Entities::encode($imageHoverPath);
	
	my $serverImageHoverPath = "http://$serverAddr:$port_listen/$imageHoverPath";
	my $leftHoverImg = "<img src='http://$serverAddr:$port_listen/hoverleft.png' width='17' height='12'>";
	my $rightHoverImg = "<img src='http://$serverAddr:$port_listen/hoverright.png' width='17' height='12'>";
	my $result = '<li class="file ext_' . $ext . '"><a href="#" rel="' . 
		$imagePath . '"' . "onmouseOver=\"showhint('<img src=&quot;$serverImageHoverPath&quot;>', this, event, '250px', true);\""
		. '>' . "$leftHoverImg$imageName$rightHoverImg" . '</a>' . $sizeDateStr . '</li>';
		
	return($result);
	}

# Keeping it simple, this is just for a directory picker for limiting searches.
# See GetDirsAndFiles() above.
sub TextDocxPdfLine {
	my ($dir, $file, $ext, $sizeDateStr) = @_;
	my $filePath = &HTML::Entities::encode($dir . $file);
	my $fileName = &HTML::Entities::encode($file);
	
	my $result = '<li class="file ext_' . $ext . '"><a href="#" rel="' . 
		$filePath . '">' .
		$fileName . '</a>' .
		'&nbsp;&nbsp;' . $sizeDateStr . '</li>'; # No edit link.
		
	return($result);
	}
