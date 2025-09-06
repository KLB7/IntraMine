# intramine_test_main.pl: a tiny service "NoPage/MainTest", for testing intramine_main.pl (Main).
# When Main is under test it will run up two of these and check that
# consecutive requests alternate between the two.

# perl C:\perlprogs\mine\intramine_test_main.pl

##### COPY THIS TO YOUR NEW SERVER.
use strict;
use warnings;
use utf8;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;
# Add modules to the above list as you need them.

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
##### END COPY THIS TO YOUR NEW SERVER. (But keeping reading, there's a bit more to do.)

##### MODIFY AND ADD THIS: %RequestAction, for actions that your server responds to.
##### Put in %RequestAction entries to show pages, load dynamic JS and CSS, respond to events.
my %RequestAction;
$RequestAction{'req|main'} = \&ThePage;     # req=main: ThePage() returns HTML for our page
$RequestAction{'/test/'}   = \&SelfTest;    # Ask this server to test itself.
$RequestAction{'signal'}   = \&HandleBroadcastRequest;    # for signal=testMaintenance

##### END MODIFY AND ADD THIS

##### COPY THIS line into your new server too, it does the network request/response handling.
MainLoop(\%RequestAction);
##### END COPY THIS line

# Maintenance status.
my $MaintenanceStatus = 'NOT DONE YET';

####### subs for this server

sub ThePage {
	my ($obj, $formH, $peeraddress) = @_;

	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>Test Server for Main</title>
</head>
<body>
<p>My service port: _PORTLISTEN_</p>
<p>Maintenance _MAINTENANCE_STATUS</p>
</body></html>
FINIS

	$theBody =~ s!_PORTLISTEN_!$port_listen!g;
	$theBody =~ s!_MAINTENANCE_STATUS!$MaintenanceStatus!g;

	return ($theBody);
}

sub HandleBroadcastRequest {
	my ($obj, $formH, $peeraddress) = @_;
	if (defined($formH->{'signal'}))
		{
		if ($formH->{'signal'} eq 'testMaintenance')
			{
			print("Test main maintenance $SHORTNAME $port_listen ...\n");
			sleep(1);
			$MaintenanceStatus = 'COMPLETE';
			RequestBroadcast(
				'signal=backinservice&sender=' . $SHORTNAME . '&respondingto=testMaintenance');
			print("END test main maintenance $SHORTNAME $port_listen ...\n");
			}
		}

	# Returned value is ignored by broadcaster - this is more of a "UDP" than "TCP" approach
	# to communicating.
	return ('OK');
}
