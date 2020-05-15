# intramine_test.pm: common subs for test programs in the test_programs/ folder.
# See "Testing.txt" for details on setting up testing.
# perl -c C:\perlprogs\mine\libs\intramine_test.pm

# package intramine_test;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use IO::Socket;
use Selenium::Remote::Driver;
use Selenium::Waiter qw/wait_until/;
use Selenium::Chrome;
use URI::Escape;
use Time::HiRes qw ( time );
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
#use lib ".";
use intramine_config;

my $ServerAddress;
my $MainPort;
my $ShortName;
my $SwarmServerPort;

# Expect eg '192.168.1.132 81 Bp 43125' as arguments,
# ie $ServerAddress $MainPort $ShortName $SwarmServerPort
# Also load config values.
# The three ref args are required.
sub InitTesting {
	$ServerAddress = shift @ARGV;
	$MainPort = shift @ARGV;
	$ShortName = shift @ARGV;
	$SwarmServerPort = shift @ARGV;
	
	# Load standard intramine_config.txt, and any config file specific to this server,
	# eg data/DBX_config.txt for the DBX server.
	LoadConfigValues(\$ShortName);
	}

sub ServerAddress {
	return($ServerAddress);
}

sub MainPort {
	return($MainPort);
}

sub ShortName {
	return($ShortName);
}

sub SwarmServerPort {
	return($SwarmServerPort);
}

# Start the Chrome browser web test driver, and return a ref to it.
sub StartBrowserDriver {
	my $driverPath = CVal('CHROME_DRIVER_PATH');
	return(Selenium::Chrome->new(binary => "$driverPath"));
	}

# Eg if testing DBX listening on port 192.168.1.132:, send
# http://192.168.1.132:43125/DBX
# This asks Chrome to load the $url.
sub GetStandarURL {
	my ($driver) = @_;
	my $url = "http://$ServerAddress:$SwarmServerPort/$ShortName/";
	$driver->get($url);
	}

# More generally, load any URL into Chrome.
# Or you can call "$driver->get($url);" yourself if you prefer. I won't tell.
sub GetURL {
	my ($driver, $url) = @_;
	$driver->get($url);
}


# Send an ssinfo message to Main server, we are done testing one server.
# $result is 'ok' or a list of errors.
sub ReportDoneTesting {
	my ( $errorsA) = @_;
	my $result = 'ok';
	my $numErrors = @$errorsA;
	if ($numErrors)
		{
		$result = join('__SEP__', @$errorsA);
		}
	
	$result = uri_escape($result);
	
	my $remote = IO::Socket::INET->new(
	                Proto   => 'tcp',       		# protocol
	                PeerAddr=> "$ServerAddress", 	# Address of server
	                PeerPort=> "$MainPort"      	# port of main server typ. 81
	                ) or (return);
	
	print $remote "GET /?ssinfo=doneTesting&shortname=$ShortName&result=$result HTTP/1.1\n\n";
	close $remote;	# No reply needed.
	}

# Wait for readyState 'complete', for at most $timeout seconds.
sub WaitForPageToLoad {
    my ($driver, $timeout) = @_; # seconds
    $timeout ||= 10;
    
    return wait_until { 
        $driver->execute_script("return document.readyState") eq 'complete' 
    }, timeout => $timeout;
	}

# Send request to a server, return response after the 200 line.
# $msg: ?req=docCount
# or	apiName/path
sub GetResponseFromOurServer {
	my ($msg) = @_;
	my $remote = IO::Socket::INET->new(
	                Proto   => 'tcp',       		# protocol
	                PeerAddr=> "$ServerAddress", 	# Address of server
	                PeerPort=> "$SwarmServerPort"      		# port of swarm server typ. 43125..up
	                ) or (return);
	
	print $remote "GET /$ShortName/$msg HTTP/1.1\n\n";
	
	my $response = '';
	my $line = <$remote>; 	# 200 OK typically to start off the response
	
	# We want the lines after a blank line.	
	my $collectingResults = 0;
	while (defined($line))
		{
		chomp($line);
		if ($collectingResults)
			{
			if ($response eq '')
				{
				$response = $line;
				}
			else
				{
				$response .= "\n$line";
				}
			}
		if ($line=~ m!^\s*$!)
			{
			$collectingResults = 1;
			}
		$line = <$remote>;
		}
		
	return($response);
	}

# Make a request to a server at $serverAddress:$portNumber and get a response.
sub GetResponseFromService {
	my ($serverAddress, $portNumber, $req, $errorsA) = @_;
	my $result = '';
	
	my $mains = IO::Socket::INET->new(
	                Proto   => 'tcp',       		# protocol
	                PeerAddr=> "$serverAddress",
	                PeerPort=> "$portNumber"
	                ) or (return('ERROR no connection!'));
	#$req = uri_escape($req);
	print $mains "GET /?$req HTTP/1.1\n\n";
	
	my $line = '';
	while ($line=<$mains>)
		{
		$result .= $line . "\n";
		}
	close $mains;

	return($result);
	}

use ExportAbove;
1;
