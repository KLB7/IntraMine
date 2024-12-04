#
# OBSOLETE, SSE has been replaced in IntraMine by WebSockets.
#
# intramine_SSE.pl: a separate port for handling Server-Sent Events.
# On receiving a signal from Main (intramine_main.pl) call SendEventToClients()
# which will in turn send a Server-Sent Event to any web page that has registered with
# this server for SSEs.
# This is done on a separate port to avoid confusing a page content request with
# a Server-Sent Event.
# The hard work is done by swarmserver.pm#SendEventToClients().

# perl C:\perlprogs\mine\intramine_SSE.pl mainPort ourPort

use strict;
use warnings;
use utf8;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;
# Add modules to the above list as you need them.

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

##### Put in %RequestAction entries to load JS and CSS and respond to requests.
my %RequestAction;
$RequestAction{'signal'} = \&HandleBroadcastRequest; 			# signal = anything, for here eg signal=activity

MainLoop(\%RequestAction);

####### subs for this server

# Main sends us an activity event: in response call SendEventToClients() in swarmserver.pm,
# which in turn sends out events to all browser clients that have registered for
# Server-Sent Events with "source = new EventSource(sourceURL);".
# See eg statusEvents.js, part of the Status server.
sub HandleBroadcastRequest {
	my ($obj, $formH, $peeraddress) = @_;
	if (defined($formH->{'signal'}))
		{
		if ($formH->{'signal'} ne '' && defined($formH->{'activeserver'}))
			{
			my $port = (defined($formH->{'port'})) ? $formH->{'port'}: '';
			Output("Sending SSE $formH->{'signal'} to $formH->{'activeserver'}.\n");
			# Over to swarmserver.pm#SendEventToClients(), arguments are eg
			# SendEventToClients('activity', 'Search', port number); - 2nd arg is a server Short Name
			SendEventToClients($formH->{'signal'}, $formH->{'activeserver'}, $port);
			}
		}

	# Returned value is ignored by broadcaster
	# - this is more of a "UDP" than "TCP" approach to communicating.
	return('OK');
	}
