# intramine_boilerplate.pl: a simple example of an IntraMine page server.
# Shows std "boilerplate" code, how to set up %RequestAction, display a page, add scrollbars.
# To bring this server up, enter
#1	Bp	Bp	intramine_boilerplate.pl
# into your data/serverlist.txt file
# (omit the '#' at the start of the line and use one or more tabs only to separate fields).
# This page will be named 'Bp' in the top navigation bar on any Intramine page.
# You can also bring it up in a browser with the address
# http://localhost:81/Bp
# (replace the '81' if you're not running Intramine on port 81. And of course use the address
# of your Intramine server box if you're not on it, eg: http://192.168.1.132:81/Bp).
# Or you can use any valid IntraMine port number. By default ports start at 43124, and continue
# for another 47 consecutive numbers, so
# http://localhost:43124/Bp through http://localhost:43172/Bp would also bring up this page.
#
# See also Documentation/Bp.html.
#
# See intramine_main.pl#StartServerSwarm() for the cmd line that starts a server.
# perl C:\perlprogs\intramine\intramine_boilerplate.pl pagename shortname mainport ourport

##### COPY THIS TO YOUR NEW SERVER.
use strict;
use warnings;
use utf8;
use Win32;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;
# Add modules to the above list as you need them.

binmode(STDOUT, ":encoding(UTF-8)");
Win32::SetConsoleCP(65001);

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
##### END COPY THIS TO YOUR NEW SERVER. (But keeping reading, there's a bit more to do.)

##### MODIFY AND ADD THIS: %RequestAction, for actions that your server responds to.
##### Put in %RequestAction entries to show pages, load dynamic JS and CSS, respond to events.
my %RequestAction;
$RequestAction{'req|main'} = \&ThePage; 	# req=main: ThePage() returns HTML for our page
#$RequestAction{'req|test'} = \&SelfTest;	# Ask this server to test itself. Arg-based.
$RequestAction{'/test/'} = \&SelfTest;	# swarmserver.pm#SelfTest(), ask this server to test itself.
##### END MODIFY AND ADD THIS

##### COPY THIS line into your new server too, it does the network request/response handling.
MainLoop(\%RequestAction);
##### END COPY THIS line

####### subs for this server

# (Do up your own version of ThePage() for your server.)
# Make and return a full HTML page. This example shows contents of the hash $formH in a table.
# With a couple of "tooltips" to spice things up, otherwise this would be really boring.
# Note the sub name "ThePage" matches the entry in %RequestAction above, and receives three
# standard arguments when called by swarmserver.pm#HandleDefaultPageAction():
# - $obj holds the request string received.
# - $formH holds copies of any arguments received in $obj of the form "this=that",
#    eg $formH->{'this'} = "that".
# - $peerAddress is the LAN IP address of this server.
# The approach taken here is to use a "here doc" template for the HTML with placeholders
# such as "_TOPNAV_", and replace the placeholders with dynamic content.
#
# Other files included:
# main.css should be included on your page, for the overall look including navigation bar.
# tooltip.css/js are optional, include them if you want "tool tips".
# boilerplateDemo.js handles resizing, and stops the loading pacifier ("spinner").
# intramine_config.js contains setConfigValue() which can be used to retrieve a configuration
# value from IntraMine. It's used in spinner.js to retrieve the name of the main Help file.
# The call to PutPortsAndShortnameAtEndOfBody() puts in the port numbers and Short name
# that setConfigValue() needs.
# spinner.js shows a pacifier or a question mark in the top nav bar. The '?' links to Help.
# 2020-03-11 14_34_38-Example IntraMine Server.png
sub ThePage {
	my ($obj, $formH, $peeraddress) = @_;
	
	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>Example IntraMine Server</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
</head>
<body>
_TOPNAV_
<h2>Example IntraMine Server</h2>
<p onmouseOver='showhint("<p>Hello there I am a tip! For text tips, you&apos;ll need to supply the width to use. For image tips, the width is set to that of the image. The last arg to showhint() should be true for image tips, false for text tips.</p>", this, event, "400px", false);'>Here is some text with a popup text tip. See intramine_boilerplate.pl around line 95 for the source of this tip.</p>
<p onmouseOver='showhint("<img src=&apos;mstile-310x310.png&apos;>", this, event, "1px", true);'>And here is some text with a popup image for a tip.</p>
<div id='scrollAdjustedHeight'>
	<div id='theTextWithoutJumpList'>
		<h3>%$formH contents</h3>
		<p>Repeated a few times, so you'll see a scrollbar.</p>
		_FORMHCONTENTS_
	</div>
</div>
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="restart.js"></script>
<script src="topnav.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
<script src="boilerplateDemo.js"></script>
<script src="tooltip.js"></script>
<script>
window.addEventListener('wsinit', function (e) { wsSendMessage('activity ' + shortServerName + ' ' + ourSSListeningPort); }, false);
</script>
</body></html>
FINIS

	# The top navigation bar, with our page name highlighted.
	# See swarmserver.pm#TopNav();
	my $topNav = TopNav($PAGENAME);				
	$theBody =~ s!_TOPNAV_!$topNav!;

	# Show formH hash contents in a table, repeated a few times to trigger scrollbar.
	my $formHContents = GetHTMLforFormH($formH);
	$theBody =~ s!_FORMHCONTENTS_!$formHContents!;

	# Put in main IP, main port, our short name for JavaScript.
	# These are needed in intramine_config.js for example
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()

	return($theBody);
	}

# The custom contents for this example (you won't need this).
# Turn contents of hash %$formH into a table, contents repeated a few times.
sub GetHTMLforFormH {
	my ($formH) = @_;
	
	Output("GetHTMLforFormH refreshing table of hash \%$formH keys and values.\n");
	
	my $formHContents = '<table border="1"><tr><th>Key</th><th>Value</th></tr>' . "\n";
	for (my $i = 0; $i < 8; ++$i)
		{
		foreach my $key (sort keys %$formH)
			{
			my $value = $formH->{$key};
			if ($key eq 'EXTRAHEADERSA')
				{
				$value = '(Array of extra headers, currently used only for PDF display)';
				}
			$formHContents .= "<tr><td>$key</td><td>$value</td></tr>\n";
			}
		}
	$formHContents .= '</table>' . "\n";
	return($formHContents);
	}
