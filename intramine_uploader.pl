# intramine_uploader.pl: a file uploader for those remote people. Upload a file from
# user's computer to IntraMine server's box. NOTE this works only for source
# and text files. "Binary" files (such as images and executables) will
# be rejected. Some day I would like to allow images.
# Server name: "Upload".
# To enable, uncomment the line
#1	Upload				Upload		intramine_uploader.pl
# in data/serverlist.txt.
#
# See also Documentation/Upload.html.
#

# perl -c C:\perlprogs\mine\intramine_uploader.pl mainPort ourListeningPort

use strict;
use warnings;
use utf8;
use Win32::Process;
use Win32;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;
use win_wide_filepaths;
# Added Jan 2023, check to see if file to be copied has a known file extension.
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

my $kLOGMESSAGES = 0;			# 1 == Log Output() messages
my $kDISPLAYMESSAGES = 0;		# 1 == print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print.
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);
Output("Starting $SHORTNAME on port $port_listen\n\n");

my %RequestAction;
$RequestAction{'req|main'} = \&UploadPage; 		# req=main
$RequestAction{'req|upload'} = \&UploadTheFile; # req=upload $formH->{'filename'}, 'contents', 'directory'
$RequestAction{'req|checkFile'} = \&OkToSave; 	# req=checkFile $formH->{'filename'}, 'directory'
#$RequestAction{'req|id'} = \&Identify; # req=id

# Over to swarmserver.pm.
MainLoop(\%RequestAction);

############## subs
# Return a web page with a form for selecting and uploading a file.
# 2019-12-03 17_45_57-Upload a File.png
sub UploadPage {
	my ($obj, $formH, $peeraddress) = @_;

	my $theBody = <<'FINIS';
<!DOCTYPE html>
<html><head>
<meta http-equiv="content-type" content="text/plain; charset=utf-8">
<title>Upload a File</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="forms.css" />
<link rel="stylesheet" type="text/css" href="uploader.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
</head>
<body>
_TOPNAV_
<p>Note this uploader only works for source and text files with known extensions.</p>
<div id='upload-status'>&nbsp;</div>

<div id="searchform">
<form class="form-container" action="/" method="post" enctype="multipart/form-data" id="form-id">
<table>
<tr class="form_row">
	<td><label for="file-id" class="custom-file-upload">Choose File</label>
	<input id="file-id" type="file" name="filename" onchange="updateChosenFileDisplay(this);" onclick="clearStatus(); return(true);" /></td>
	<td class="title_right">File:&nbsp;</td>
	<td><span id="file-upload-value">&nbsp;</span></td>
</tr>
<tr class="form_row">
	<td>&nbsp;</td>
	<td class="title_right"><label>Server Directory:&nbsp;</td>
	<td><input name="directory" type="text" id="other-field-id" /></label></td>
</tr>
<tr>
	<td colspan="2"><div id='progress'>&nbsp;</div></td>
	<!-- <td>&nbsp;</td> -->
	<td id="submit_paragraph"><input class="submit-button" type="submit" value="Upload" /></td>
</tr>
</table>
</form>
</div>
<p>Leave &quot;Server Directory&quot; blank to use default directory (_DEFAULTUPLOADDIR_).</p>
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="restart.js"></script>
<script src="topnav.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
<script src="tooltip.js"></script>
<script type="text/javascript">
	let thePort = '_THEPORT_';
	let theDefaultUploadDir = '_DEFAULTUPLOADDIR_';
</script>
<script src="uploader.js"></script>
</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);
	$theBody =~ s!_TOPNAV_!$topNav!;
	
	my $serverAddr = ServerAddress();
	my $host = $serverAddr;
	my $port = $port_listen;
	my $defaultDir = DefaultUploadDirectory(); # swarmserver.pm#DefaultUploadDirectory()
	$theBody =~ s!_THEPORT_!$port!g;
	$theBody =~ s!_DEFAULTUPLOADDIR_!$defaultDir!g;
	
	# Put in main IP, main port, our short name for JavaScript.
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()

	return($theBody);
	}

# Save posted contents of file in $formH->{'contents'} to server with path
# $formH->{'directory'} . $formH->{'filename'}.
# OkToSave() should be called before this, via JavaScript request with req=checkFile,
# to allow/deny overwrite, as indicated by $formH->{'allowOverwrite'}.
# NOTE only source and text files will be uploaded. If the file extension is not
# recognized as source or text, there will just be an ERROR message returned.
sub UploadTheFile {
	my ($obj, $formH, $peeraddress) = @_;
	my $fullPath = '';
	my $result = 'OK';
	
	if (defined($formH->{'filename'}) && defined($formH->{'contents'}) && defined($formH->{'directory'}))
		{
		my $dir = $formH->{'directory'};
		$dir =~ s!\\!/!g;
		if ($dir !~ m!/$!)
			{
			$dir .= '/';
			}
		$fullPath = $dir . $formH->{'filename'};
		
		$fullPath = decode("utf8", $fullPath);
		$dir = decode("utf8", $dir);
		
		# Reject if extension is not for a source or text file.
		my $fileName = FileNameFromPath($fullPath);
		my ($fileNameProper, $extWithPeriod) = FileNameProperAndExtensionFromFileName($fileName);
		my $ext = substr($extWithPeriod, 1);
		if (!IsTextExtensionNoPeriod($ext))
			{
			$result = "ERROR, |.$ext| not recognized as a source or text file extension, no copy made.";
			return($result);
			}

		
		# Make directories in the path if they don't exist yet.
		MakeAllDirsWide($fullPath);
				
		if (FileOrDirExistsWide($dir) == 2)
			{
			# Write $formH->'contents'} to the destination path. Note at the moment this
			# only works properly for source or text files, not binaries such as images
			# or executables.
			if (FileOrDirExistsWide($fullPath) == 0 || defined($formH->{'allowOverwrite'}))
				{
				my $writeResult = WriteBinFileWide($fullPath, $formH->{'contents'});
				if (!$writeResult)
					{
					$result = "ERROR, could not write to |$fullPath|!";
					}
				}
			else
				{
				$result = "ERROR, server file |$fullPath| exists, overwrite is not allowed!";
				}
			}
		else
			{
			$result = "ERROR, directory |$dir| could not be found or made!";
			}
		}
	else
		{
		if (!defined($formH->{'filename'}))
			{
			$result = 'ERROR missing filename!';
			}
		elsif (!defined($formH->{'contents'}))
			{
			$result = 'ERROR missing contents! File must contain at least one character.';
			}
		else
			{
			# There is a default dir $DEFAULT_UPLOAD_DIR in swarmserver.pm, so it's hard to get here.
			$result = 'ERROR missing directory!';
			}
		}
	
	return($result);
	}

# This is called before UploadTheFile(), if it doesn't return OK then user will be asked to confirm
# overwrite of an existing file. 'OK missing filename!' will just let the upload go through without
# asking anything, and UploadTheFile() will return 'ERROR missing filename!'. So no worries.
sub OkToSave {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = 'OK';
	if (defined($formH->{'filename'}))
		{
		my $dir = (defined($formH->{'directory'}) && $formH->{'directory'} ne '') ?
					$formH->{'directory'}: DefaultUploadDirectory();
		$dir =~ s!\\!/!g;
		if ($dir !~ m!/$!)
			{
			$dir .= '/';
			}
		my $fullPath = $dir . $formH->{'filename'};
		# One of life's mysteries, "$fullPath = decode("utf8", $fullPath);"
		# isn't needed or wanted here, unlike UploadTheFile() above.
		
		if (FileOrDirExistsWide($fullPath) == 1)
			{
			$result = 'ERROR file exists'
			}
		}
	else
		{
		$result = 'OK missing filename!';
		}
	
	return($result);
	}
