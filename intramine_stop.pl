# intramine_stop.pl: send "EXITEXITEXIT" stop request to server on $port_listen.
# 'PERSISTENT' servers will ignore this request. To kill them too, use intramine_all_stop.pl.

# perl C:\perlprogs\mine\intramine_stop.pl

use strict;
use utf8;
use IO::Socket;
use Win32::Process;
use Win32;
use Win32;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use intramine_config;

# 'SRVR' loads current 'SERVER_ADDRESS' as saved by intramine_main.pl#InitServerAddress().
LoadConfigValues('SRVR');
my $port_listen = CVal('INTRAMINE_MAIN_PORT');    # default 81

my $serverAddress = CVal('SERVER_ADDRESS');
if ($serverAddress eq '')
	{
	# This is an error, but we will try to carry on.
	$serverAddress = 'localhost';
	}

AskServerToExit($port_listen, $serverAddress);
sleep(2);                                         # let the dust settle
print("DONE SLEEPING in intramine_stop.pl\n");

########### subs
sub ErrorReport {
	print 'intramine_stop.pl says: ' . Win32::FormatMessage(Win32::GetLastError());
	return 1;
}

sub AskServerToExit {
	my ($portNumber, $serverAddress) = @_;

	#print("Attempting to stop $serverAddress:$portNumber\n");
	my $remote = IO::Socket::INET->new(
		Proto    => 'tcp',               # protocol
		PeerAddr => "$serverAddress",    # Address of server
		PeerPort => "$portNumber"        # port of server 591 or 8080 are standard HTML variants
	) or (ErrorReport() && return);
	print "intramine_stop.pl Connected to ", $remote->peerhost,    # Info message
		" on port: ", $remote->peerport, "\n";

	print $remote "GET /?EXITEXITEXIT=1 HTTP/1.1\n";
	close $remote;
}
