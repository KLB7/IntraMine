# intramine_glosser.pl: the "Glosser" service.
# Like gloss2html.pl, but with a web interface
# to select dir/file, inline, and hoverGIFs.
# And it can be used from anywhere on your intranet.
# The MainLoop() for this service times out every 2 seconds
# because when the "Generate" button on the web page is clicked
# the response from RunGlossToHTML() of "Ok" should be returned
# immediately - so all it does is set $StartRun to 1, and
# then when MainLoop times out, ActualRunGlossToHTML()
# will be called to do the actual run. All the real work
# is done by gloss_to_html.pm#ConvertGlossToHTML().
# Feedback here is not saved to disk but rather sent directly
# to the web page with WebSocketSend().
# See also "Documentation/Glosser.html".

use strict;
use warnings;
use Win32;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use win_wide_filepaths;
use swarmserver;
use gloss_to_html;

binmode(STDOUT, ":encoding(UTF-8)");
Win32::SetConsoleCP(65001);

$| = 1;

my $PAGENAME    = '';
my $SHORTNAME   = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

# Size and date are shut off for the Glosser dir/file picker,
# showing them can slow things down and they aren't really needed here.
my $SHOWFILESIZESANDMODDATES = 0;
my $FILESIZEUNITS            = [qw(B KB MB GB TB PB)];

# my $kLOGMESSAGES = 0;			# 1 == Log Output() messages, and print to console window
# my $kDISPLAYMESSAGES = 0;		# 1 == just print messages from Output() to console window
# # Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# # Use the Output() sub for routine log/print. See swarmserver.pm#Output().
# StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);
# Output("Starting $SHORTNAME on port $port_listen\n\n");

my %RequestAction;
$RequestAction{'req|main'}    = \&OurPage;            # req=main, return the full web page
$RequestAction{'dir'}         = \&GetDirsAndFiles;    # $formH->{'dir'} is directory path
$RequestAction{'req|convert'} = \&RunGlossToHTML;     # req=convert, do a run

my $MainLoopTimeout = 2;     # seconds
my $StartRun        = 0;     # 1 when running
my $RunIsUnderWeigh = 0;     # not used really
my $FileOrDir       = '';    # The file or directory to work with
my $InlineImages    = 0;     # 0 == hover images, 1 == inline images
my $HoverGIFS       = 0;     # 0 == follow #InlinImages for GIFs, 1 == always hover

# Time out frequently to pick up a run request.
MainLoop(\%RequestAction, $MainLoopTimeout, \&ActualRunGlossToHTML);

# The Glosser page.
# Top nav bar, dir/file picker, inline and hoverGif boxes text placeholder,
# and some JavaScript (especially glosser.js).
sub OurPage {
	my ($obj, $formH, $peeraddress) = @_;

	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>Glosser</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="forms.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
<link rel="stylesheet" type="text/css" href="jqueryFileTree.css" />
<link rel="stylesheet" type="text/css" href="glosser.css" />
</head>
<body>
_TOPNAV_
_DESCRIPTION_
<div id='top_buttons'>_CONTROLS_ <span id='running'></span>
</div>
<div id="runmessage">&nbsp;</div>
<div id='scrollAdjustedHeight'>
	<div id='theTextWithoutJumpList'>
	</div>
</div>
<script>
let thePort = '_THEPORT_';
let weAreRemote = _WEAREREMOTE_;
let runMessageDiv = 'runmessage';
let commandContainerDiv = 'cmdcontainer';
let commandOutputDiv = 'theTextWithoutJumpList';
let cmdOutputContainerDiv = 'scrollAdjustedHeight';
let errorID = "runMessageDiv";
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
<script src="jqueryFileTree.js"></script>
<script src="lru.js"></script>

<script src="glosser.js"></script>

</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);    # The top navigation bar, with our page name highlighted
	$theBody =~ s!_TOPNAV_!$topNav!;

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

	my $amRemoteValue = $clientIsRemote ? 'true' : 'false';
	my $port          = $port_listen;

	$theBody =~ s!_WEAREREMOTE_!$amRemoteValue!;

	$theBody =~ s!_THEPORT_!$port!;

	my $description = "<h2>Glosser</h2>";
	$description .= '<p>Generate standalone HTML from Gloss-styled .txt</p>';
	my $glossLink = "http://$serverAddr:$port_listen/$SHORTNAME/Glosser.html";
	$description .= "<p>See the <a href='$glossLink' target='_blank'>Glosser docs</a></p>";
	$theBody =~ s!_DESCRIPTION_!$description!;


	my $controls = GlosserControls();
	$theBody =~ s!_CONTROLS_!$controls!;

	# Put in main IP, main port (def. 81), and our Short name (Reindex) for JavaScript.
	# These are needed in intramine_config.js for example
	PutPortsAndShortnameAtEndOfBody(\$theBody);   # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()

	return ($theBody);
}

sub GlosserControls {
	my $formContents = '';

	# The dir/file picker, inline images yes/no, hover GIFs yer/no:
	my $theFilePickerAndChecks = <<"FINIS";
<div id="form_1_1"><h2>Directory or File&nbsp;</h2></div>
<input type="search" id="searchdirectory" class="form-field" name="searchdirectory" placeholder='type a path to a file or directory, or hit the dots' list="dirlist" />
<span id="form_2_1"><span id="annoyingdotcontainer"><img id="dotdotdot" src="dotdotdot24x48.png" onclick="showDirectoryPicker();" /></span></span>
<datalist id="dirlist">
</datalist>

<div id="form_3_1"><label><input type='checkbox' id="inlineCheck" name='inline' value='yes'_CHECKEDBYDEFAULT_>Inline images (unchecked means hover for images)</label></div>

<div id="form_4_1"><label><input type='checkbox' id="hoverGIFsCheck" name='hoverGIFs' value='yes'_CHECKEDBYDEFAULT_>Always hover GIFs (unchecked means do same as Inline images)</label></div>
FINIS
	$formContents .= $theFilePickerAndChecks;

	# The "Generate" button:
	my $tipStr      = "<p>Generate standalone HTML from .txt</p>";
	my $onmouseOver = "onmouseOver='showhint(\"$tipStr\", this, event, \"500px\", false)'";
	my $button =
"<input id=\"convert_button\" class=\"submit-button\" type=\"submit\" value=\"Generate\" />";
	$formContents .=
"\n<a href='' id='convert_anchor' class='plainhintanchor' onclick='runConversion(); return false;' $onmouseOver style=\"text-align:right; width:100%; padding:0;\">$button</a>"
		. "\n";


	# THe form, with controls. Not really needed, except for styling.
	my $theSource = <<"FINIS";
<form class="form-container" id="ftsform" method="get" action=_ACTION_ onsubmit="runConversion(this); return false;">
$formContents
</form>
FINIS

	# A separate dropdown selector for the directory picker.
	$theSource .= DirectoryPicker();

	return ($theSource);
}

# See glosser.js#showDirectoryPicker() for use. This is a simplified version of the picker
# used on the Files page. Directory or file can be selected.
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
		<div id="pickerDisplayDiv">Selected directory/file:&nbsp;<span id="pickerDisplayedDirectory"></span></div>
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

# Generate the directory and file lists for the Search form. This is called by the
# JavaScript directory file tree display "widget" with a 'dir=path' request,
# where 'path' is a directory or file path.
# See also glosser.js#initDirectoryDialog() and jqueryFileTree.js (look for "action").
sub GetDirsAndFiles {
	my ($obj, $formH, $peeraddress) = @_;
	my $dir            = $formH->{'dir'};
	my $clientIsRemote = ($formH->{'rmt'} eq 'false') ? 0 : 1;
	my $result         = '';

	if (FileOrDirExistsWide($dir) == 2)
		{
		# See win_wide_filepaths.pm#FindFileWide().
		my $fullDirForFind = $dir . '*';
		my @allEntries     = FindFileWide($fullDirForFind);
		my $numEntries     = @allEntries;

		if ($numEntries)
			{
			my (@folders, @files);
			my $total = 0;

			for (my $i = 0 ; $i < @allEntries ; ++$i)
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
					if (   $fileName =~ m!\.\w+$!
						&& $fileName !~ m!\.sys$!
						&& substr($fileName, 0, 1) ne '$')
						{
						push @files, $fileName;
						}
					}
				}

			my $numDirs  = @folders;
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
					$result .=
						  '<li class="directory collapsed"><a href="#" rel="'
						. &HTML::Entities::encode($dir . $file) . '/">'
						. &HTML::Entities::encode($file)
						. '</a></li>';
					}

				# print Files
				foreach my $file (sort {lc $a cmp lc $b} @files)
					{
					next if (FileOrDirExistsWide($dir . $file) == 0);

					my $sizeDateStr = FileDateAndSizeString($dir, $file);

					$file =~ /\.([^.]+)$/;
					my $ext = $1;
					# Gray out unsuported file types. Show thumbnail on hover for images.
					if (defined($ext) && IsTextDocxPdfOrImageExtensionNoPeriod($ext))
						{
						if (IsImageExtensionNoPeriod($ext))
							{
							$result .= ImageLine($serverAddr, $dir, $file, $ext, $sizeDateStr);
							}
						else    # Text, for the most part - could also be pdf or docx
							{
							$result .= TextDocxPdfLine($dir, $file, $ext, $sizeDateStr);
							}
						}
					else        # Unsupported type, can't produce a read-only HTML view.
						{
						my $fileName = &HTML::Entities::encode($file);
						$result .=
							  '<li class="file ext_'
							. $ext . '">'
							. "<span class='unsupported'>"
							. $fileName
							. '</span>' . '</li>';
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

	$result = ' ' if ($result eq '');    # return something (but not too much), to avoid 404

	return ($result);
}

sub FileDateAndSizeString {
	my ($dir, $file) = @_;
	my $sizeDateStr = '';

	if (!$SHOWFILESIZESANDMODDATES)
		{
		return ($sizeDateStr);
		}

	my $modDate = GetFileModTimeWide($dir . $file);
	my $dateStr = localtime($modDate)->datetime;

	my $sizeBytes = GetFileSizeWide($dir . $file);
	my $exp       = 0;
	my $sizeStr   = '';
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

	return ($sizeDateStr);
}

# Image lines in the directory picker get a "show image on mouse hover" onmouseover action.
# Which isn't really needed, just showing off a bit:) Images can't be searched for.
# See GetDirsAndFiles() above.
sub ImageLine {
	my ($serverAddr, $dir, $file, $ext, $sizeDateStr) = @_;
	my $imagePath      = $dir . $file;
	my $imageHoverPath = $imagePath;
	$imageHoverPath =~ s!%!%25!g;
	my $imageName = $file;
	$imageName      = &HTML::Entities::encode($imageName);        # YES this works fine!
	$imagePath      = &HTML::Entities::encode($imagePath);
	$imageHoverPath = &HTML::Entities::encode($imageHoverPath);

	my $serverImageHoverPath = "http://$serverAddr:$port_listen/$imageHoverPath";
	my $leftHoverImg =
		"<img src='http://$serverAddr:$port_listen/hoverleft.png' width='17' height='12'>";
	my $rightHoverImg =
		"<img src='http://$serverAddr:$port_listen/hoverright.png' width='17' height='12'>";
	my $result =
		  '<li class="file ext_'
		. $ext
		. '"><a href="#" rel="'
		. $imagePath . '"'
		. "onmouseOver=\"showhint('<img src=&quot;$serverImageHoverPath&quot;>', this, event, '250px', true);\""
		. '>'
		. "$leftHoverImg$imageName$rightHoverImg" . '</a>'
		. $sizeDateStr . '</li>';

	return ($result);
}

# Keeping it simple, this is just for a directory picker for limiting searches.
# See GetDirsAndFiles() above.
sub TextDocxPdfLine {
	my ($dir, $file, $ext, $sizeDateStr) = @_;
	my $filePath = &HTML::Entities::encode($dir . $file);
	my $fileName = &HTML::Entities::encode($file);

	my $result =
		  '<li class="file ext_'
		. $ext
		. '"><a href="#" rel="'
		. $filePath . '">'
		. $fileName . '</a>'
		. '&nbsp;&nbsp;'
		. $sizeDateStr
		. '</li>';    # No edit link.

	return ($result);
}

# Start the generation of HTML. When the MainLoop() times out next,
# $StartRun==1 will be noticed in ActualRunGlossToHTML() just below.
sub RunGlossToHTML {
	my ($obj, $formH, $peeraddress) = @_;

	$FileOrDir       = defined($formH->{'file_or_dir'}) ? $formH->{'file_or_dir'} : '';
	$InlineImages    = defined($formH->{'inline'})      ? $formH->{'inline'}      : 0;
	$HoverGIFS       = defined($formH->{'hover_gifs'})  ? $formH->{'hover_gifs'}  : 0;
	$StartRun        = 1;
	$RunIsUnderWeigh = 1;

	if ($FileOrDir eq '')
		{
		return ("Error, no dir or file provided!");
		}
	else
		{
		return ("Ok");
		}
}

sub ActualRunGlossToHTML {
	if (!$StartRun)
		{
		return;
		}

	$StartRun = 0;
	ConvertGlossToHTML($FileOrDir, $InlineImages, $HoverGIFS, \&ShowFeedback);
	$RunIsUnderWeigh = 0;
	WebSocketSend('ENABLEGLOSSERGENERATE');
}

sub ShowFeedback {
	my ($msg) = @_;
	my @msgA = split(/\n/, $msg);
	$msg = 'NEWGLOSSMESSAGE:' . '<p>' . join('</p><p>', @msgA) . '</p>';
	WebSocketSend($msg);
}
