# intramine_glosser.pl

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

$|  = 1;

my $PAGENAME = '';
my $SHORTNAME = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

my $kLOGMESSAGES = 0;			# 1 == Log Output() messages, and print to console window
my $kDISPLAYMESSAGES = 0;		# 1 == just print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print. See swarmserver.pm#Output().
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);
Output("Starting $SHORTNAME on port $port_listen\n\n");

my %RequestAction;
# Respond with the Mon page, where #theTextWithoutJumpList will show messages
# generated in Main and all swarmserver.pm-based services with Monitor($msg).
# (Include mon.js for message sending.)
$RequestAction{'req|main'} = \&OurPage; 			# req=main
# Return latest messages from the main log file.
$RequestAction{'req|convert'} = \&RunGlossToHTML; 	# req=convert

MainLoop(\%RequestAction);

# The Glosser page. 
# Top nav bar, dir/file piakcer, inline and hoverGif boxes text placeholder,
# and some JavaScript (especially mon.js).
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
<script src="glosser.js"></script>

<script src="jquery-3.4.1.min.js"></script>
<script src="jquery.easing.1.3.min.js"></script>
<script src="jqueryFileTree.js"></script>
<script src="lru.js"></script>

</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);		# The top navigation bar, with our page name highlighted
	$theBody =~ s!_TOPNAV_!$topNav!;

	my $description ="<h2>Glosser</h2>";
	$theBody =~ s!_DESCRIPTION_!$description!;

	# $peeraddress eq '127.0.0.1' determines whether we are local.
	# The IPv4 Address for this server (eg 192.168.0.14);
	my $serverAddr = ServerAddress();

	my $clientIsRemote = 0;
	# If client is on the server then peeraddress can be either 127.0.0.1 or $serverAddr:
	# if client is NOT on the server then peeraddress is not 127.0.0.1 and differs from $serverAddr.
	if ($peeraddress ne '127.0.0.1' && $peeraddress ne $serverAddr)	#if ($peeraddress ne $serverAddr)
	#if ($peeraddress ne '127.0.0.1')
		{
		$clientIsRemote = 1;
		}
	
	my $amRemoteValue = $clientIsRemote ? 'true' : 'false';
	my $port = $port_listen;

	$theBody =~ s!_WEAREREMOTE_!$amRemoteValue!;

	$theBody =~ s!_THEPORT_!$port!;

	my $controls = GlosserControls();
	$theBody =~ s!_CONTROLS_!$controls!;
	
	# Put in main IP, main port (def. 81), and our Short name (Reindex) for JavaScript.
	# These are needed in intramine_config.js for example
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()
	
	return($theBody);
	}

sub GlosserControls {
	my $cmdString = '';

	# The dir/file picker:
	my $theFilePicker = <<"FINIS";
<div id="form_1_2"><h2>Directory&nbsp;</h2></div>
<input type="search" id="searchdirectory" class="form-field" name="searchdirectory" placeholder='type a path, hit the dots->, or leave blank for all dirs' list="dirlist" />
<div id="form_2_2"><div id="annoyingdotcontainer"><img id="dotdotdot" src="dotdotdot24x48.png" onclick="showDirectoryPicker();" /></div></div>
<datalist id="dirlist">
</datalist>
FINIS
	$cmdString .= $theFilePicker;

	# -inline:

	# -hoverGIFs:

	# The "Convert" button:
	my $tipStr = "<p>Convert from txt to HTML</p>";
	my $onmouseOver = "onmouseOver='showhint(\"$tipStr\", this, event, \"500px\", false)'";
	my $button = "<input id=\"convert_button\" class=\"submit-button\" type=\"submit\" value=\"Convert\" />";
	$cmdString .= "\n<a href='' id='convert_anchor' class='plainhintanchor' onclick='runConversion(); return false;' $onmouseOver >$button</a>" . "\n";

	return($cmdString);
	}

sub RunGlossToHTML {
	my ($obj, $formH, $peeraddress) = @_;

	my $fileOrDir = defined($formH->{'file_or_dir'}) ? $formH->{'file_or_dir'}: '';
	my $inlineImages = defined($formH->{'inline'}) ? $formH->{'inline'}: 0;
	my $hoverGIFS = defined($formH->{'hover_gifs'}) ? $formH->{'hover_gifs'}: 0;

	ConvertGlossToHTML($fileOrDir, $inlineImages, $hoverGIFS, \&ShowFeedback);
	}

sub ShowFeedback {
	my ($msg) = @_;
	my @msgA = split(/\n/, $msg);
	$msg = '' . '<p>' . join('</p><p>', @msgA) . '</p>';
	WebSocketSend($msg);
}