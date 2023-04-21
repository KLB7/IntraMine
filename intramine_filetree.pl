# intramine_filetree.pl: a tree display of local files in two columns, with drive selectors.
# Files open with intramine_viewer.pl. If editing has been configured, there will
# be "pencil" icons following editable files.
# A form at top of page allows opening a file by name or partial or full path.
# Note there is no "context" for this page, in terms of a
# default location on disk, so a partial or full path will more often be needed to avoid
# ambiguity (eg the form has no idea which "main.cpp" you might want, but
# entering "flattreeview\main.cpp" would probably bring up the right file).
# Uses http://www.abeautifulsite.net/jquery-file-tree/
# which is invoked by files.js#startFileTreeUp().
# perl C:\perlprogs\mine\intramine_filetree.pl 81 43131

use strict;
use warnings;
use utf8;
use HTML::Entities;
#use Win32::FindFile;
use Time::Piece;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;
use win_wide_filepaths;
use ext;  # for ext.pm#IsTextOrImageExtensionNoPeriod() and ext.pm#IsImageExtensionNoPeriod()

#binmode(STDOUT, ":unix:utf8");
$|  = 1;

my $PAGENAME = '';
my $SHORTNAME = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

my $FILESIZEUNITS = [qw(B KB MB GB TB PB)];

my $CSS_DIR = FullDirectoryPath('CSS_DIR');
my $JS_DIR = FullDirectoryPath('JS_DIR');
my $UseAppForLocalEditing = CVal('USE_APP_FOR_EDITING');
my $UseAppForRemoteEditing = CVal('USE_APP_FOR_REMOTE_EDITING');
my $AllowLocalEditing = CVal('ALLOW_LOCAL_EDITING');
my $AllowRemoteEditing = CVal('ALLOW_REMOTE_EDITING');

# For the file name / datetime / file size span width array @widths.
my $FILENAMEWIDTH = 0;
my $DATETIMEWIDTH = 1;
my $SIZEWIDTH = 2;

my $kLOGMESSAGES = 0;			# 1 == Log Output() messages
my $kDISPLAYMESSAGES = 0;		# 1 == print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print.
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);
Output("Starting $SHORTNAME on port $port_listen\n\n");

my %RequestAction;
$RequestAction{'req|main'} = \&FileTreePage; 				# req=main
$RequestAction{'dir'} = \&GetDirsAndFiles; 					# $formH->{'dir'} is directory path

# Over to swarmserver.pm.
MainLoop(\%RequestAction);

################### subs
# The main page showing two file lists, with drive selectors and a text field to enter
# a file path or name for quick opening.
# This is under "Files" in the top navigation on an IntraMine page.
# URL on the IntraMine box: http://localhost:81/Files
# 2019-12-03 18_09_20-Local Files.png
sub FileTreePage {
	my ($obj, $formH, $peeraddress) = @_;

	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<!-- <meta http-equiv="content-type" content="text/html; charset=windows-1252"> -->
<title>Files</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="twocolumns.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
<link rel="stylesheet" type="text/css" href="forms.css" />
<link rel="stylesheet" type="text/css" href="jqueryFileTree.css" />

</head>
<body>
_TOPNAV_
<!-- Simple input field with Open button, allow opening file from a typed-in path. -->
<form class="form-container" id="fileOpenForm" method="get" action=_ACTION_ onsubmit="openUserPath(this); return false;">
<input id="openfile" class="form-field" type="search" name="openthis" placeholder='file name or partial or full path' required />
<input class="submit-button" type="submit" value="Open" />
</form>

<div id='scrollAdjustedHeight'>
	<div id='fileTreeLeft'>
		<select id="driveselector_1" name="drive selector" onchange="driveChanged('scrollDriveListLeft', this.value);">
		  _DRIVESELECTOROPTIONS_
		</select><span id='sort_by'>Sort files by: </span>
		<!-- <select id="sort_1" name="sort order"> -->
		<select id="sort_1" name="sort order"  onchange="reSortExpandedDirectoriesOnSortChange();">
		  <option value='name_ascending' selected>Name A_Z</option>
		  <option value='name_descending'>Name Z_A</option>
		  <option value='date_newest'>Date newest</option>
		  <option value='date_oldest'>Date oldest</option>
		  <option value='size_smallest'>Size smallest</option>
		  <option value='size_largest'>Size largest</option>
		  <option value='extension'>File extension</option>
		</select>
		<span id="errorMessage">&nbsp;</span>
		<div id='scrollDriveListLeft'>
		</div>
	</div>
	<div id='fileTreeRight'>
		<div id="tocShrinkExpandDiv"><img src="707788g4.png" id="tocShrinkExpand" onclick="toggleRightListWidth();"></div>
		<select id="driveselector_2" name="drive selector" onchange="driveChanged('scrollDriveListRight', this.value);">
		  _DRIVESELECTOROPTIONS_
		</select>
		<div id='scrollDriveListRight'>
		</div>
	</div>
</div>
<script>
let weAreRemote = _WEAREREMOTE_;
let allowEditing = _ALLOW_EDITING;
let useAppForEditing = _USE_APP_FOR_EDITING;

let thePort = '_THEPORT_';
let clientIPAddress = '_CLIENT_IP_ADDRESS_';
let viewerShortName = '_VIEWERSHORTNAME_';
let openerShortName = '_OPENERSHORTNAME_';
let editorShortName = '_EDITORSHORTNAME_';
let linkerShortName = '_LINKERSHORTNAME_';
let contentID = 'scrollAdjustedHeight';
let errorID = "errorMessage";
let initialDirectoryPath = '_INITIALDIR_';
</script>
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
<script src="tooltip.js"></script>
<script src="jquery-3.4.1.min.js"></script>
<script src="jquery.easing.1.3.min.js"></script>
<script src="jqueryFileTree.js"></script>
<script src="viewerLinks.js"></script>
<script src="files.js"></script>
</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);
	$theBody =~ s!_TOPNAV_!$topNav!;
	$theBody =~ s!_CSS_DIR_!$CSS_DIR!g;
	$theBody =~ s!_JS_DIR_!$JS_DIR!g;
	
	# $peeraddress eq '127.0.0.1' determines whether we are local.
	# The IPv4 Address for this server (eg 192.168.0.14);
	my $serverAddr = ServerAddress();
	
	# Form action.
	my $action = "http://$serverAddr:$port_listen/?rddm=1";
	$theBody =~ s!_ACTION_!\'$action\'!;
	
	# Put in drive selector options (two of them). See swarmserver.pm#DriveSelectorOptions().
	my $driveSelectorOptions = DriveSelectorOptions();
	$theBody =~ s!_DRIVESELECTOROPTIONS_!$driveSelectorOptions!g;
	
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
	
	$theBody =~ s!_WEAREREMOTE_!$amRemoteValue!;
	$theBody =~ s!_ALLOW_EDITING!$tfAllowEditing!;
	$theBody =~ s!_USE_APP_FOR_EDITING!$tfUseAppForEditing!;
	
	$theBody =~ s!_THEPORT_!$port_listen!;
	$theBody =~ s!_CLIENT_IP_ADDRESS_!$peeraddress!;
	my $viewerShortName = CVal('VIEWERSHORTNAME');
	my $openerShortName = CVal('OPENERSHORTNAME');
	my $editorShortName = CVal('EDITORSHORTNAME');
	my $linkerShortName = CVal('LINKERSHORTNAME');
	$theBody =~ s!_VIEWERSHORTNAME_!$viewerShortName!;
	$theBody =~ s!_OPENERSHORTNAME_!$openerShortName!;
	$theBody =~ s!_EDITORSHORTNAME_!$editorShortName!;
	$theBody =~ s!_LINKERSHORTNAME_!$linkerShortName!;
	
	my $initialDirectory = defined($formH->{'directory'}) ? $formH->{'directory'}: '';
	# Encode: this goes with decodeURIComponent at top of files.js#showDirectory().
	$initialDirectory = uri_encode($initialDirectory);
	# The Files page will open to the $initialDirectory if provided. This is used
	# when opening directory links (see intramine_viewer.pl#OpenDirectory() etc).
	$theBody =~ s!_INITIALDIR_!$initialDirectory!;
	
	
	# Put in main IP, main port, our short name for JavaScript.
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()
	
	return $theBody;
	}

# Return a list of directories and files for the current drive or directory.
# Called by jqueryFileTree.js on line 69: "$.post(o.script, { dir: t, rmt: o.remote,..."
# which sends a "dir" request to the program (see %RequestAction above).
sub GetDirsAndFiles {
	my ($obj, $formH, $peeraddress) = @_;
	my $dir = $formH->{'dir'};
	my $result = '';
	
	Output("GetDirsAndFiles request for dir: |$dir|\n");
	if (FileOrDirExistsWide($dir) != 2)
		{
		return(' '); # return something (but not too much), to avoid 404
		}
	
	my @folders;
	my @files;
	my @modDates;
	my @fileSizes;
	GetFoldersFilesDatesAndSizes($dir, \@folders, \@files, \@modDates, \@fileSizes);
	
	my $numFolders = @folders;
	my $numFiles = @files;
	my $total = $numFolders + $numFiles;
	
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
		my $sortOrder = (defined($formH->{'sort'})) ? $formH->{'sort'}: '';
		SortFilesDatesAndSizes($sortOrder, \@files, \@modDates, \@fileSizes);
		
		my @modDatesStrings;
		my @fileSizesStrings;
		my @widths;
		GetDateSizeStringsAndColumnWidths(\@files, \@modDates, \@fileSizes,
			\@modDatesStrings, \@fileSizesStrings, \@widths);
		
		PutFiles($dir, $formH, \@files, \@modDatesStrings, \@fileSizesStrings, \@widths, \$result);
		}
		
	if ($total)
		{
		$result .= "</ul>\n";
		}
	
	if ($result eq '')
		{
		$result = ' ' ; # return something (but not too much), to avoid 404
		}
	
	return($result);
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
	for (my $i = 0; $i < @allEntries; ++$i)
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
		$$resultR .= '<li class="directory collapsed"><a href="#" rel="' . 
			  &HTML::Entities::encode($dir . $folderName) . '/">' . 
			  &HTML::Entities::encode($folderName) . '</a></li>';
		}
	}

sub SortFilesDatesAndSizes {
	my ($sortOrder, $filesA, $modDatesA, $fileSizesA) = @_;
	my @idx;
	
	if ($sortOrder eq 'size_smallest')
		{
		@idx = sort {$fileSizesA->[$a] <=> $fileSizesA->[$b]} 0..$#$fileSizesA;
		}
	elsif ($sortOrder eq 'size_largest')
		{
		@idx = sort {$fileSizesA->[$b] <=> $fileSizesA->[$a]} 0..$#$fileSizesA;
		}
	elsif ($sortOrder eq 'date_newest')
		{
		# Newest first, so [$b] <=> [$a].
		@idx = sort {$modDatesA->[$b] <=> $modDatesA->[$a]} 0..$#$modDatesA;
		}
	elsif ($sortOrder eq 'date_oldest')
		{
		# Newest first, so [$b] <=> [$a].
		@idx = sort {$modDatesA->[$a] <=> $modDatesA->[$b]} 0..$#$modDatesA;
		}
	elsif ($sortOrder eq 'name_descending')
		{
		@idx = sort {lc $filesA->[$b] cmp lc $filesA->[$a]} 0..$#$filesA;
		}
	elsif ($sortOrder eq 'extension')
		{
		my @extensions;
		Extensions($filesA, \@extensions);
		@idx = sort{$extensions[$a] cmp $extensions[$b]} 0..$#extensions;
		}
	else # 'name_ascending', the default
		{
		@idx = sort {lc $filesA->[$a] cmp lc $filesA->[$b]} 0..$#$filesA;
		}
	
	@$filesA = @$filesA[@idx];
	@$modDatesA = @$modDatesA[@idx];
	@$fileSizesA = @$fileSizesA[@idx];
	}

sub GetDateSizeStringsAndColumnWidths {
	my ($filesA, $modDatesA, $fileSizesA, $modDatesStringsA, $fileSizesStringsA, $widthsA) = @_;
	my $numFiles = @$filesA;
	my $filesWidth = 0;
	my $modDatesWidth = 0;
	my $fileSizesWidth = 0;
	for (my $i = 0; $i < $numFiles; ++$i)
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
	$widthsA->[$SIZEWIDTH] = $wS;
	}

# For each file: file icon based on extension, file name, datetime, size in bytes.
# Fixed-width inline-block <span>s are used to align entries.
sub PutFiles {
	my ($dir, $formH, $filesA, $modDatesStringsA, $fileSizesStringsA, $widthsA, $resultR) = @_;
	my $numFiles = @$filesA;
	my $clientIsRemote = ($formH->{'rmt'} eq 'false') ? 0 : 1;
	my $allowEditing = ($formH->{'edt'} eq 'false') ? 0 : 1;
	my $useAppForEditing = ($formH->{'app'} eq 'false') ? 0 : 1;
	my $serverAddr = ServerAddress();
	
	for (my $i = 0; $i < $numFiles; ++$i)
		{
		my $file = $filesA->[$i];
		next if (FileOrDirExistsWide($dir . $file) == 0);
		my $modDate = $modDatesStringsA->[$i];
		my $size = $fileSizesStringsA->[$i];
		
		$file =~ /\.([^.]+)$/;
		my $ext = $1;
		
		# Gray out unsuported file types. Show thumbnail on hover for images.
		if (defined($ext) && IsTextDocxPdfOrImageExtensionNoPeriod($ext))
			{
			if (IsImageExtensionNoPeriod($ext))
				{
				$$resultR .= ImageLine($serverAddr, $dir, $file, $ext, $modDate, $size, $widthsA);
				}
			else # Text, for the most part - could also be pdf or docx
				{
				$$resultR .= TextDocxPdfLine($dir, $file, $ext, $modDate, $size,
							$allowEditing, $clientIsRemote, $widthsA);
				}
			}
		else # Unsupported type, can't produce a read-only HTML view. So no link.
			{
			my $dateSpanStart = "<span style='display: inline-block; width: $widthsA->[$DATETIMEWIDTH];'>";
			my $sizesSpanStart = "<span style='display: inline-block; width: $widthsA->[$SIZEWIDTH];'>";
			my $endSpan = '</span>';

			my $fileName = &HTML::Entities::encode($file);
			$$resultR .= '<li class="file ext_' . $ext . '">' .
			"<span class='unsupported' style='display: inline-block; width: $widthsA->[$FILENAMEWIDTH];'>" . $fileName . '</span>' .
			$dateSpanStart . $modDate . $endSpan . $sizesSpanStart . $size . $endSpan . '</li>';
			}
		}
	}

sub FileDatesAndSizes {
	my ($dir, $filesA, $modDatesA, $sizesA) = @_;
	my $numFiles = @$filesA;
	
	for (my $i = 0; $i < $numFiles; ++$i)
		{
		my $file = $filesA->[$i];
		my $modDate = GetFileModTimeWide($dir . $file);
		my $sizeBytes = GetFileSizeWide($dir . $file);
		push @$modDatesA, $modDate;
		push @$sizesA, $sizeBytes;
		}
	}

sub Extensions {
	my ($filesA, $extA) = @_;
	my $numFiles = @$filesA;

	for (my $i = 0; $i < $numFiles; ++$i)
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
	my $imagePath = $dir . $file;
	my $imageHoverPath = $imagePath;
	$imageHoverPath =~ s!%!%25!g;
	my $imageName = $file;
	$imageName = &HTML::Entities::encode($imageName);	# YES this works fine.
	$imagePath = &HTML::Entities::encode($imagePath);
	$imageHoverPath = &HTML::Entities::encode($imageHoverPath);
	
	my $serverImageHoverPath = "http://$serverAddr:$port_listen/$imageHoverPath";
	my $leftHoverImg = "<img src='http://$serverAddr:$port_listen/hoverleft.png' width='17' height='12'>";
	my $rightHoverImg = "<img src='http://$serverAddr:$port_listen/hoverright.png' width='17' height='12'>";
	
	my $result = '<li class="file ext_' . $ext . '">' .
	"<span style='display: inline-block; width: $widthsA->[$FILENAMEWIDTH];'>" .
	'<a href="#" rel="' . $imagePath . '"' . "onmouseOver=\"showhint('<img src=&quot;$serverImageHoverPath&quot;>', this, event, '250px', true);\"" . '>' .
	"$leftHoverImg$imageName$rightHoverImg" . '</a></span>' .
	"<span style='display: inline-block; width: $widthsA->[$DATETIMEWIDTH];'>" .
	$modDate . '</span>' .
	"<span style='display: inline-block; width: $widthsA->[$SIZEWIDTH];'>" .
	$size . '</span></li>';
			
	return($result);
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
		$result .= '<li class="file ext_' . $ext . '">' .
		"<span style='display: inline-block; width: $widthsA->[$FILENAMEWIDTH];'>" .
		'<a href="#" rel="' . $filePath . '">' .
		$fileName . '</a>' . '</span>' .
		"<span style='display: inline-block; width: $widthsA->[$DATETIMEWIDTH];'>" .
		$modDate . '</span>' .
		"<span style='display: inline-block; width: $widthsA->[$SIZEWIDTH];'>" .
		$size . '</span></li>';
		}
	else # editing allowed
		{
		$result .= '<li class="file ext_' . $ext . '">' .
		"<span style='display: inline-block; width: $widthsA->[$FILENAMEWIDTH];'>" .
		'<a href="#" rel="' . $filePath . '">' .
		$fileName . '</a>' .
		'<a href="#"><img src="edit1.png" width="17" height="12" rel="' .
		$filePath . '" />' . '</a>' . '</span>' .
		"<span style='display: inline-block; width: $widthsA->[$DATETIMEWIDTH];'>" .
		$modDate . '</span>' .
		"<span style='display: inline-block; width: $widthsA->[$SIZEWIDTH];'>" .
		$size . '</span></li>';
		}
	
	return($result);
	}
