# intramine_websockets_client.pm: WebSockets client for Main and all swarmservers
# except intramine_websockets.pl (which is the WebSockets server).
# Expects to send and receive strings only, no binary stuff.

package intramine_websockets_client;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use utf8;
use IO::Socket::INET;
use Protocol::WebSocket::Client;

my $NUM_TRIES = 5;  # Total tries when attempting to connect.
my $TRY_DELAY = .2; # Delay in seconds between tries.

# Many print's, versus just error messages.
my $CHATTY = 0;

my $sockHost;
my $sockPort;
my $tcp_socket;
my $client;
my $isConnected = 0;
my $buffer = '';

# $CHATTY = 0 suppresses merely informative messages.
sub ChattyPrint {
	my ($msg) = @_;
	
	if ($CHATTY)
		{
		print("$msg");
		}
	}

# Set host and port for WebSockets connection to use.
sub InitWebSocket {
	my ($host, $port) = @_;
	$sockHost = $host;
	$sockPort = $port;
	
	# TEST ONLY
	ChattyPrint("Host: |$sockHost|\n");
	ChattyPrint("Port: |$sockPort|\n");
}

# Set up client and connect to the WeSockets server at $sockHost:$sockPort.
# This is called by the first WebSocketSend().
sub WebSocketStart {
	$tcp_socket = IO::Socket::INET->new(
		PeerAddr => $sockHost,
		PeerPort => "ws($sockPort)",
		Proto => 'tcp',
		Blocking => 1,
		Timeout => 2
	) or die "Failed to connect to socket: $@";
	
	$client = Protocol::WebSocket::Client->new(url => "ws://$sockHost:$sockPort");
	
	if (!defined($client))
		{
		die("ERROR \$client is not defined!");
		}
	
	$client->on(
	write => sub {
		my ($client, $buf) = @_;
		ChattyPrint("Calling syswrite.\n");
		syswrite $tcp_socket, $buf;
		}
	);
	
	$client->on(
	connect => sub {
		my $client = shift;
		$isConnected = 1;
		ChattyPrint("Client connected!\n");
		}
	);
	
	$client->on(
	read => sub {
		my $client = shift;
		my ($buf) = @_;
		ChattyPrint("Received from socket: '$buf'\n");
		$buffer .= $buf;
		}
	);
	
	$client->on(
	error => sub {
		my $client = shift;
		my ($buf) = @_;
		print("ERROR ON WEBSOCKET: $buf\n");;
		$tcp_socket->close;
		$isConnected = 0;
		}
	);
	
	$client->connect;
	
	my $tryCount = 0;
	my $confirmed = 0;
	while ($tcp_socket->connected && ++$tryCount <= 10)
		{
		my $recv_data;
		my $bytes_read = sysread $tcp_socket, $recv_data, 16384;
		if (!defined $bytes_read) { ChattyPrint("sysread on tcp_socket failed!\n"); }
		elsif ($bytes_read == 0) { ChattyPrint("No bytes read. \$isConnected is |$isConnected|\n"); }
		else
			{
			# unpack response - this triggers any handler if a complete packet is read.
			ChattyPrint("Calling \$client->read in NEW\n");
			$client->read($recv_data);
			ChattyPrint("Client startup \$tryCount $tryCount saw |$recv_data|\n");
			}
		
		if ($isConnected)
			{
			last;
			}
		}
	}

# Return 1 if we see our message echoed back, 0 otherwise.
# WebSocketStart() is called if we aren't connected yet.
sub WebSocketSend {
	my ($msg, $disconnect) = @_;	
	$disconnect ||= 0;
	
	if ($disconnect)
		{
		WebSocketDisconnect();
		return(1);
		}
	
	
	my $numConnectTries = 0;
	my $wasConnected = WebSocketClientIsConnected();
	while (!WebSocketClientIsConnected() && ++$numConnectTries <= $NUM_TRIES)
		{
		ChattyPrint("WebSocketSend, calling WebSocketStart try $numConnectTries.\n");
		WebSocketStart();
		select(undef, undef, undef, $TRY_DELAY);
		}
	
	if (!WebSocketClientIsConnected())
		{
		print("ERROR, could not connect to WS service after $NUM_TRIES tries!\n");
		return(0);
		}
	
	ChattyPrint("About to call \$client->write |$msg|.\n");
	$client->write($msg);
	
	my $result = 0;
	
	# Confirm the send by reading the same message back from the WebSockets server.
	# Since the IntraMine WebSockets server is just an echo server there are
	# often other messages to ignore while looking for the $msg we sent.
	while ($tcp_socket->connected)
		{
		my $recv_data;
		my $bytes_read = sysread $tcp_socket, $recv_data, 16384;
		
		if (defined($bytes_read) && $bytes_read > 0)
			{
			if ($recv_data =~ m!^\W*$msg$!i)
				{
				# TEST ONLY
				ChattyPrint("MESSAGE CONFIRMED.\n");
				$result = 1;
				last;
				}
			else
				{
				ChattyPrint("Bogus data received: |$recv_data|\n")
				}
			}
		else
			{
			ChattyPrint("MESSAGE NOT CONFIRMED.\n");
			last;
			}
		}
			
	return($result);
	}

# Not really used at the moment.
sub WebSocketDisconnect {
	$client->disconnect;
	}

# $isConnected is set above around line 77.
sub WebSocketClientIsConnected {
	return($isConnected);
}

use ExportAbove;
1;
