# intramine_all_stop.pl: send "FORCEEXIT" request to main IntraMine server on $port_listen,
# which will stop all servers including Cmd before stopping itself.
# See also intramine_stop.pl.

# perl C:\perlprogs\mine\intramine_all_stop.pl

use strict;
use utf8;
use IO::Socket;
use Win32::Process;
use Win32;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use intramine_config;

# 'SRVR' loads current 'SERVER_ADDRESS' as saved by intramine_main.pl#InitServerAddress().
LoadConfigValues('SRVR');
my $port_listen = CVal('INTRAMINE_MAIN_PORT'); 			# default 81

my $serverAddress = CVal('SERVER_ADDRESS');
if ($serverAddress eq '')
	{
	# This is an error, but we will try to carry on.
	print("We will continue, using 'localhost' as the server address.\n");
	$serverAddress = 'localhost';
	}

AskServerToExit($port_listen, $serverAddress);
sleep(2); # let the dust settle

########### subs
sub ErrorReport{
        print 'intramine_all_stop.pl says: ' . Win32::FormatMessage( Win32::GetLastError() );
        return 1;
    }

# Ask main server to stop. This will in turn request all servers to stop.
sub AskServerToExit {
	my ($portNumber, $serverAddress) = @_;
	
	#print("Attempting to stop $serverAddress:$portNumber\n");
	my $remote = IO::Socket::INET->new(
	                Proto   => 'tcp',       # protocol
	                PeerAddr=> "$serverAddress", # Address of server
	                PeerPort=> "$portNumber"      # port of server, 81 591 or 8080 are standard variants
	                ) or (ErrorReport() && return);
#	print "intramine_stop.pl Connected to ", $remote->peerhost, # Info message
#	      " on port: ", $remote->peerport, "\n";
	
	print $remote "GET /?FORCEEXIT=1 HTTP/1.1\n";
	close $remote;
	}
