# intramine_chat.pl: a simple chat client for IntraMine.

use strict;
use warnings;
use utf8;
use Encode qw(decode encode);
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;

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

# %RequestAction, for actions that your server responds to.
# %RequestAction entries respond to requests to show pages, load dynamic JS and CSS, respond to events.
my %RequestAction;
$RequestAction{'req|main'} = \&OurPage;
$RequestAction{'req|getMessages'} = \&GetMessages;
$RequestAction{'req|clearMessages'} = \&ClearMessages;
$RequestAction{'req|peer'} = \&PeerAddress;
$RequestAction{'data'} = \&SaveMessage;

# Cheat a bit to get the Chats.txt path, it's where ToDo.txt is.
my $ToDoPath = FullDirectoryPath('TODODATAPATH');
my $ChatPath = $ToDoPath;
$ChatPath =~ s!/[^/]+$!!;
$ChatPath .= "/Chats.txt";

# Chats.txt message file is truncated. See TruncateChatFile().
my $kMAX_CHAT_MESSAGES = 50;

MainLoop(\%RequestAction);

##### subs
#
sub OurPage {
	my ($obj, $formH, $peeraddress) = @_;
	
	Output("\$peeraddress: |$peeraddress|\n");
	
	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>Chat</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="forms.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
<link rel="stylesheet" type="text/css" href="chat.css" />
</head>
<body>
_TOPNAV_
<h2>Chat<span id="errorid"></span></h2>

<form class="chat" id="chatformid" method="get" onsubmit="sendMessage(this); return(false);">
<table>
  <tr>
    <td><input id="nameid" class="chat-form-field chat-name-field" type="text" name="name" maxlength="20" placeholder="(nick) name" /></td>
	<td><textarea id="messageid" class="chat-form-field chat-message-field" name="message" rows="4" autofocus required onkeyup="autoGrow(this);"></textarea></td>
	<td><input id="messageSubmitButton" class="submit-button" type="submit" value="Send" /></td>
  </tr>
  <tr>
  <td id="clearButtonCell">
  <button id="clearButton" type="button" onclick="clearChat();" onmouseOver='showhint("<p>Clears all messages permanently.</p>", this, event, "300px", false);'>Clear</button>
  </td>
  <td colspan="2">
  <div class="center-align">
	<div class="radio-content">
  <input type="radio" id="newestFirst" name="newOld" value="new" onchange="toggleNewOld();"
         checked>
  <label for="newestFirst">Newest first</label>

  <input type="radio" id="oldestFirst" name="newOld" value="old" onchange="toggleNewOld();">
  <label for="oldestFirst">Oldest first</label>
	</div>
  </div>

  </td>
  </tr>
</table>
</form>

<div id='scrollAdjustedHeight'>
	<div id='theTextWithoutJumpList'>
		<div id='_MESSAGES_ID_' class="speech-wrapper">
		</div>
	</div>
</div>
<script>
let thePort = '_THEPORT_';
let messagesID = '_MESSAGES_ID_';
let errorID = 'errorid';
</script>
<!-- intramine_config.js allows loading IntraMine config values into JavaScript.
Here it's needed in spinner.js for the value of "SPECIAL_INDEX_NAME_HTML". -->
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="topnav.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
<script src="tooltip.js"></script>
<script src="chat.js"></script>
</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);		# The top navigation bar, with our page name highlighted
	$theBody =~ s!_TOPNAV_!$topNav!;

	$theBody =~ s!_THEPORT_!$port_listen!; # our port
	
	$theBody =~ s!_D_SHORTNAME_!$SHORTNAME!;
	$theBody =~ s!_D_OURPORT_!$port_listen!;
	$theBody =~ s!_D_MAINPORT_!$server_port!;
	
	# Put in main IP, main port (def. 81), and our Short name (DBX) for JavaScript.
	# These are needed in intramine_config.js for example
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()
	
	return($theBody);
	}

sub GetMessages {
	my ($obj, $formH, $peeraddress) = @_;
	my $filePath = $ChatPath;
	
	my $tryCount = 0;
	my $contents = ReadTextFileDecodedWide($filePath);
	while (!defined($contents) && ++$tryCount <= 3)
		{
		sleep(1);
		$contents = ReadTextFileDecodedWide($filePath);
		}
	if (!defined($contents))
		{
		if (FileOrDirExistsWide($filePath) == 0)
			{
			return('(none)');
			}
		else
			{
			return("ERROR, could not read |$filePath|!");
			}
		}
		
	my @lines = split(/\n/, $contents);
	my $messages = join("_MS_", @lines);
	
	$messages = uri_escape_utf8($messages);
	
	if ($messages eq '')
		{
		$messages = '(none)';
		}
	
	return($messages);
	}

sub SaveMessage {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = '';
	my $filePath = $ChatPath;
	my $data = $formH->{'data'};
	$data = uri_unescape($data);
	
	$data = encode_utf8($data);
	
	my $tryCount = 0;
	my $didit = AppendToTextFileWide($filePath, "$data\n");
	while (!$didit && ++$tryCount <= 3)
		{
		sleep(1);
		$didit = AppendToTextFileWide($filePath, "$data\n");
		}
	if (!$didit)
		{
		$result = "FILE ERROR! Could not access chat file |$filePath|.\n";
		}
	else
		{
		TruncateChatFile();
		}

	return('OK');
	}

sub ClearMessages {
	my ($obj, $formH, $peeraddress) = @_;
	my $filePath = $ChatPath;
	my $didit = WriteTextFileWide($filePath, "");
	my $returnMessage = $didit ? 'ok' : 'nuts';
	return($returnMessage);
	}

sub PeerAddress {
	my ($obj, $formH, $peeraddress) = @_;
	$peeraddress = uri_escape_utf8($peeraddress);
	return($peeraddress);
	}

# Shorten Chats.txt to at most $kMAX_CHAT_MESSAGES.
# One line is one message.
sub TruncateChatFile {
	my $filePath = $ChatPath;
	
	my $tryCount = 0;
	my $contents = ReadTextFileDecodedWide($filePath);
	while (!defined($contents) && ++$tryCount <= 3)
		{
		sleep(1);
		$contents = ReadTextFileDecodedWide($filePath);
		}
	if (!defined($contents) || $contents eq '')
		{
		return;
		}
	
	my @lines = split(/\n/, $contents);
	my $numMessages = @lines;
	if ($numMessages > $kMAX_CHAT_MESSAGES)
		{
		while ($numMessages > $kMAX_CHAT_MESSAGES)
			{
			shift(@lines);
			--$numMessages;
			}
		my $messages = join("\n", @lines);
		
		$messages = encode_utf8($messages);
		
		WriteTextFileWide($filePath, "$messages\n");
		}
	}

