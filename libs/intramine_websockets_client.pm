# intramine_websockets_client.pm: WebSockets client for Main and all swarmservers
# except intramine_websockets.pl (which is the WebSockets server).
# Expects messages as strings only, no binary stuff.
# Note a Perl program using this module can only send messages
# (using WebSocketSend()).
# There is no monitoring loop to receive other messages.
# (However on the browser client side, websockets,js can receive messages).

package intramine_websockets_client;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use utf8;
use Time::HiRes qw ( time );
use IO::Select;
use IO::Socket::INET;
#use IO::Socket::Timeout; # DOESN'T WORK, at least not the way I tried it....
#use Errno qw(ETIMEDOUT EWOULDBLOCK);
use Protocol::WebSocket::Client;

# Flush after every write.
$| = 1;

my $NUM_TRIES = 5;  # Total tries when attempting to connect.
my $TRY_DELAY = .2; # Delay in seconds between tries.

# Many print's, versus just error messages.
my $CHATTY = 0;

my $sockHost;
my $sockPort;
my $tcp_socket;
my $client;
my $s;
my $isConnected = 0;

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
		Timeout => 10 #,
		#Reuse	=> 1
	) or die "Failed to connect to socket: $@";
	
	# enable read and write timeouts on the socket
	# DOESN'T WORK.
	#IO::Socket::Timeout->enable_timeouts_on($tcp_socket);
	## setup the timeouts
	#$tcp_socket->read_timeout(0.5);
	#$tcp_socket->write_timeout(0.5);
	
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
		$s = IO::Select->new();
		$s->add($tcp_socket);
		ChattyPrint("Client connected!\n");
		}
	);
	
	$client->on(
	read => sub {
		my $client = shift;
		my ($buf) = @_;
		ChattyPrint("Received from socket: '$buf'\n");
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
		my $bytes_read = $tcp_socket->sysread($recv_data, 8000);
		if (!defined $bytes_read) { ChattyPrint("sysread on tcp_socket failed!\n"); last; }
		elsif ($bytes_read == 0) { ChattyPrint("No bytes read. \$isConnected is |$isConnected|\n"); last; }
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
		
	if (!$isConnected)
		{
		print("Error, Websockets Perl client did not start!\n");
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
	
	# TEST ONLY
	###print("WebSocketSend '$msg'.\n");
	
	my $wsStart = time;
	
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
	
	my $timeout = 10; # seconds
	
	# TEST ONLY
	#print("Confirming |$msg|...\n");
	
	while (1)
		{
		my $recv_data;
		#print("WSRAM about to call can_read.\n");
		my @ready = $s->can_read($timeout);
		my $numReady = @ready;
		if ($numReady == 1)
			{
			#print("WebSocketSend about to call SYSREAD;\n");
			sysread $ready[0], $recv_data, 8000; 
			# or maybe $ready[0]->sysread();
			
			if (defined($recv_data) && length($recv_data) > 0)
				{
				# A control character is often present at the start of the message,
				# hence the \W*.
				if ($recv_data =~ m!^\W*$msg$!i)
					{
					#print("WebSocketSend MESSAGE CONFIRMED.\n");
					$result = 1;
					last;
					}
				}
			else
				{
				#print("WebSocketSend NO BYTES READ, dropping out.\n");
				last;
				}
			}
		else
			{
			print("WebSocketSend TIMEOUT COULD NOT READ for |$msg|!\n");
			last;
			}
		}
	
	# TEST ONLY
	my $wsElapsed = time - $wsStart;
	if ($wsElapsed > 2.1)
		{
		my $ruffElapsed = substr($wsElapsed, 0, 6);
		print("LONG DELAY |$ruffElapsed| s WebSocketSend end.\n");
		}
	else
		{
		###print("WebSocketSend end.\n");
		}

	# TEST ONLY
	if (!$result)
		{
		print("WS message |$msg$| NOT CONFIRMED!\n");
		}
	return($result);
	}

# Send a WebSockets messate without waiting for confirmation.
# Mainly for testing, not recommended for regular use.
sub WebSocketSendNoConfirm {
	my ($msg) = @_;
	if (!WebSocketClientIsConnected())
		{
		print("ERROR, not connected to WS service!\n");
		return(0);
		}

	$client->write($msg);
	
	return(1);
	}

# Not really used at the moment.
sub WebSocketDisconnect {
	$client->disconnect;
	}

# $isConnected is set above around line 77.
sub WebSocketClientIsConnected {
	return($isConnected);
}

# DO NOT USE.
# NOTE this does not help performance, consider it a FAILED experiment.
# It's been stubbed out with return(0); near the top.
#
# A placeholder for receiving WebSocket messages in a Perl service.
# For now the messages are just drained, but someday we might need
# a callback.
# intramine_main.pl#DoMaintenance() calls this about once a minute.
# Without this, WebSockets messages to Main can pile up and slow things down.
# Other IntraMine servers
sub WebSocketReceiveAllMessages {

	my $numMessagesSeen = 0;
	
	# TEST ONLY
	return(0);
	
	# TEST ONLY
	###print("WSRAM start.\n");

	
	my $timeout = 1; # seconds
	
	while (1)
		{
		my $recv_data;
		#print("WSRAM about to call can_read.\n");
		my @ready = $s->can_read($timeout);
		my $numReady = @ready;
		if ($numReady == 1)
			{
			# First try just print something, don't attempt to read.
			ChattyPrint("Socket is ready for reading\n");
			# use HTTP/1.1, which keeps the socket open by default
			# $sock->print("GET / HTTP/1.1\r\nHost: $host\r\n\r\n");
			# Read from $ready[0]
			ChattyPrint("About to call SYSREAD;\n");
			sysread $ready[0], $recv_data, 8000; 
			# or maybe $ready[0]->sysread();
			
			if (defined($recv_data) && length($recv_data) > 0)
				{
				++$numMessagesSeen;
				ChattyPrint("Saw a message, count so far $numMessagesSeen\n");
				
				# TEST ONLY
				###print("WSRAM msg: |$recv_data|\n");
				}
			else
				{
				ChattyPrint("NO BYTES READ, dropping out.\n");
				last;
				}
			}
		else
			{
			last;
			}
		}

	# TEST ONLY
	###print("WSRAM end.\n");
	
	return($numMessagesSeen);
	}

use ExportAbove;
1;