# intramine_websockets.pl: a WebSockets server for IntraMine,
# using a single port. If any client sends a message, the message
# is sent out to all connected clients, which in turn decide
# what to do with the message.
# This is a WEBSOCKET server, which is a BACKGROUND server that uses
# the ws:// protocol rather than http:// for communication.
# Expects to receive and send strings only, no binary stuff.
#
# For details on use, see "Writing your own IntraMine server.txt#WebSockets"
# and the following section, "Writing your own IntraMine server.txt#IntraMine communications".
#
# This service is started by intramine_main.pl and needs no entry in data/serverlist.txt
# ( see "intramine_main.pl#LoadServerList()" ).
#
# Solo start without IntraMine (change to your path and preferred port number):
# perl C:\perlprogs\IntraMine\intramine_websockets.pl WEBSOCKETS WS 81 43140


use strict;
use warnings;
use utf8;
use Net::WebSocket::Server;

$|  = 1;

my $page_name = shift @ARGV;
my $short_name = shift @ARGV;
my $mainPort = shift @ARGV;		# Default 81
my $port_listen = shift @ARGV;	# Default up over 42000

if (!defined($port_listen) || $port_listen !~ m!^\d+$!)
	{
	die("ERROR, no valid port number supplied to intramine_websockets.pl!");
	}

ListenForWSConnections();

# Set up the WebSockets server, and on receiving a message
# rebroadcast to all listeners (including the original sender).
# Except for an exit message, for which just print good-bye and exit.
sub ListenForWSConnections {
	my $MessageGuard = '_MG_';
	
	# TEST ONLY
	print("$short_name is listening on port |$port_listen|\n");
	
	Net::WebSocket::Server->new
		(
	    listen => $port_listen,
		silence_max => 0, # or maybe try 30 (seconds)
	    on_connect => sub {
	        my ($serv, $conn) = @_;
	        # TEST ONLY
	        #print("WS on connect.\n");
	        
	        $conn->on(
	            utf8 => sub {
	                my ($conn, $msg) = @_;
	                # TEST ONLY
	                #print("utf8: |$msg|\n");
					if ($msg =~ m!$MessageGuard(FORCEEXIT|EXITEXITEXIT)$MessageGuard!)	                
	                # if (   $msg =~ m!^(..)?FORCEEXIT(..)?$!
	                # 	|| $msg =~ m!^(..)?EXITEXITEXIT(..)?$! )
	                	{
	                	print("WS EXIT bye!\n");
	                	exit(0);
	                	}
	                else
	                	{
	                	$_->send_utf8($msg) for $conn->server->connections;
	                	}
	            	}
	        	);
	    	},
		)->start;
	}
