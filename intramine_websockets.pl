# intramine_websockets.pl: a WebSockets server for IntraMine,
# using a single port.
# Supported:
#  broadcast: send to all connections
#  echo: send message back to sender
#  publish: send to all connections subscribed to a topic
#  subscribe: sign up to receive messages on a specific topic
#
# This is a WEBSOCKET server, which is an IntraMine BACKGROUND server that uses
# the ws:// protocol rather than http:// for communication.
# Expects to receive and send strings only, no binary stuff.
# All messages received are sent out unaltered.
#
# For details on use, see "Writing your own IntraMine server.txt#WebSockets"
# and the following section, "Writing your own IntraMine server.txt#IntraMine communications".
# See also Documentation/WS.html.
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
use Win32;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use LogFile;    # For logging - log files are closed between writes.
use intramine_config;

binmode(STDOUT, ":encoding(UTF-8)");
Win32::SetConsoleCP(65001);

$| = 1;

# Hash to store subscriptions:
# %subscriptions = ( topic1 => [conn1, conn2], topic2 => [conn3] );
my %subscriptions;

# Message "guards": each message should start with a fixed string
# for the type of message.
# For Publish and Subscribe, an variable "topic" is also needed,
# itself guarded by _TS_ the topic _TE_, eg
# _MG_SUBSCRIBE__TS_Startup_TE_    (note the double underscore)
# _MG_PUBLISH__TS_Activity_TE_    (note the double underscore)
my $MessageGuard = '_MG_';    # Broadcast
# my $EchoGuard      = '_MG_ECHO_';         # Echo
# my $SubscribeGuard = '_MG_SUBSCRIBE__';    # Subscribe
# my $PublishGuard   = '_MG_PUBLISH__';      # Publish

# my $ReconnectMessage  = 'R_E_C_N_N_E_C_T';    # sic
# my $ReconnectSeconds  = 0;                    #21600;                # 6 hours
# my $LastReconnectTime = time();

LoadConfigValues();

my $page_name   = shift @ARGV;
my $short_name  = shift @ARGV;
my $mainPort    = shift @ARGV;    # Default 81
my $port_listen = shift @ARGV;    # Default up over 42000

if (!defined($port_listen) || $port_listen !~ m!^\d+$!)
	{
	die("ERROR, no valid port number supplied to intramine_websockets.pl!");
	}

my $SERVERNAME       = 'WS';
my $kLOGMESSAGES     = 0;         # Log Output() messages
my $kDISPLAYMESSAGES = 0;         # Display Output() messages in cmd window

my $LogDir = FullDirectoryPath('LogDir');

my $logDate   = DateTimeForFileName();
my $OutputLog = '';
if ($kLOGMESSAGES)
	{
	my $LogPath = $LogDir . "$SERVERNAME $logDate.txt";
	#print("LogPath: |$LogPath|\n");
	MakeDirectoriesForFile($LogPath);
	$OutputLog = LogFile->new($LogPath);
	$OutputLog->Echo($kDISPLAYMESSAGES);
	}

ListenForWSConnections();

# Set up the WebSockets server, and on receiving a message
# rebroadcast to all listeners (including the original sender).
# Except for an exit message, for which just print good-bye and exit.
sub ListenForWSConnections {

	# TEST ONLY
	#print("$short_name is listening on port |$port_listen|\n");

	Net::WebSocket::Server->new(
		listen      => $port_listen,
		silence_max => 0,              # or maybe try 30 (seconds)
		on_connect  => sub {
			my ($serv, $conn) = @_;
			# TEST ONLY
			#Output("WS on connect.\n");

			$conn->on(
				utf8 => sub {
					my ($conn, $msg) = @_;
					# TEST ONLY
					Output("utf8: |$msg|\n");
					if ($msg =~ m!$MessageGuard(FORCEEXIT|EXITEXITEXIT)$MessageGuard!)
						{
						# Disconnect all. Doesn't work at the moment(20251122)
						#$serv->shutdown();
						print("WS EXIT bye!\n");
						exit(0);
						}
					else
						{
						if ($msg =~ m!^_MG_SUBSCRIBE__TS_(\w+)_TE_!)    # Subscribe to topic
							{
							my $topic = $1;
							push @{$subscriptions{$topic}}, $conn;
							# And echo
							$conn->send_utf8($msg);
							Output(
								"SUBSCRIBED: |$msg|, topic |$topic| by $conn->{ip}:$conn->{port}\n"
							);
							}
						elsif ($msg =~ m!^_MG_PUBLISH__TS_(\w+)_TE_!)    # Publish for topic
							{
							my $topic = $1;
							if (defined($subscriptions{$topic}))
								{
								my $arr      = $subscriptions{$topic};
								my $numConns = @$arr;
								Output("NUM SUBS for $topic: $numConns\n");
								for (my $i = 0 ; $i < $numConns ; ++$i)
									{
									my $subconn = $arr->[$i];
									Output("PUB TO: $subconn->{ip}, $subconn->{port}\n");
									}

								$_->send_utf8($msg) for @{$subscriptions{$topic}};
								}
							# else no subscribers, no big deal.
							# And echo
							$conn->send_utf8($msg);
							Output("PUBLISHED: |$msg|\n");
							}
						elsif ($msg =~ m!^_MG_ECHO_!)    # Echo
							{
							$conn->send_utf8($msg);
							Output("ECHOED: |$msg|\n");
							}
						else                             # Broadcast
							{
							$_->send_utf8($msg) for $conn->server->connections;
							Output("BROADCAST: |$msg|\n");
							}

						# Refresh now and then. Doesn't work.
						# if ($ReconnectSeconds > 0)
						# 	{
						# 	my $currentTime             = time();
						# 	my $secondsSinceLastRefresh = $currentTime - $LastReconnectTime;
						# 	if ($secondsSinceLastRefresh >= $ReconnectSeconds)
						# 		{
						# 		$LastReconnectTime = $currentTime;
						# 		my $reconnectMessage =
						# 			"$MessageGuard" . "$ReconnectMessage" . "$MessageGuard";
						# 		$_->send_utf8($reconnectMessage) for $conn->server->connections;
						# 		Output("RECONNECT: |$msg|\n");
						# 		}
						# 	}
						}
				},
				disconnect => sub {
					# Remove disconnected client from all subscription lists
					foreach my $topic (keys %subscriptions)
						{
						@{$subscriptions{$topic}} = grep {$_ ne $conn} @{$subscriptions{$topic}};
						}
					#Output("Client disconnected: $conn->{ip}:$conn->{port}\n");
				}

			);
		},
	)->start;
}

# Print, to cmd line and log file.
sub Output {
	my ($text) = @_;
	if ($text =~ m!c:/perlprogs/IntraMine/logs/!)
		{
		return;
		}
	if ($kLOGMESSAGES)
		{
		$OutputLog->Log("$text");
		}
	if ($kDISPLAYMESSAGES)
		{
		print("$text");
		}
}
