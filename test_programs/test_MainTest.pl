# test_MainTest.pl: this is run when Main is being tested.
# Tested by intramine_test_main.pl:
# - retrieving config values
# - round robin (NextPortForShortName() etc)
# - redirect: RedirectBasedOnShortName() etc
# - %RequestAction handlers
# - server list load and startup
# - signal handling (ReceiveInfo() starts up testing)
# - MainLoop(), ResultPage, GrabArguments to some extent
# - testing: RunAllTests() etc


# Command line, as invoked by swarmserver.pm#SelfTest() (path and numbers will vary):
# perl "C:\perlprogs\mine\test_programs\test_MainTest.pl" 192.168.1.132 81 MainTest 43125

use strict;
use warnings;
use URI::Escape;
use IO::Socket;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent(2)->child('libs')->stringify;
use intramine_test;

# Collect error strings if any. ReportDoneTesting() at the bottom sends any errors back.
my @errors;
my $canContinue = 1;


# Grab parameters that specify main ip and port, and our Short name. Also
# load configuration values.
InitTesting(); # intramine_test.pm#InitTesting()
my $shortName = ShortName();
my $swarmServerPort = SwarmServerPort();
my $serverAddress = ServerAddress();

# Start the Google Chrome driver.
my $driver = StartBrowserDriver(); # intramine_test.pm#StartBrowserDriver()


#my $url = "http:$serverAddress:$swarmServerPort/$shortName/?req=main";
#$driver->get($url);
GetStandarURL($driver);

my $body_text = $driver->get_body();
my $firstPort = '';
# Body should contain <p>My service port: _PORTLISTEN_</p>
# and <p>Maintenance COMPLETE</p>
if ($body_text =~ m!My service port\: (\d+)!)
	{
	$firstPort = $1;
	}
else
	{
	$canContinue = 0;
	push @errors, "No first port number received.";
	}
# Body should say that maintenance happened.
if ($body_text !~ m!COMPLETE!)
	{
	push @errors, "Maintenance not done for port $swarmServerPort.";
	}

# Ask Main to redirect a request to the intramine_test_main.pl MainTest server.
my $mainPort = MainPort();
my $url = "http:$serverAddress:$mainPort/$shortName/?req=main";
$driver->get($url);
$body_text = $driver->get_body();
my $secondPort = '';
if ($body_text =~ m!My service port\: (\d+)!)
	{
	$secondPort = $1;
	}
else
	{
	$canContinue = 0;
	push @errors, "Going to Main, no second port number received.";
	}

if ($firstPort == $secondPort)
	{
	push @errors, "No round robin, port does not change.";
	}
# Body should say that maintenance happened.
elsif ($body_text !~ m!COMPLETE!)
	{
	push @errors, "Maintenance not done for port $swarmServerPort.";
	}

# With two instances of MainTest running, a third request should send back
# the $firstPort number.
$driver->get($url);
$body_text = $driver->get_body();
my $thirdPort = '';
if ($body_text =~ m!My service port\: (\d+)!)
	{
	$thirdPort = $1;
	}
else
	{
	$canContinue = 0;
	push @errors, "Going to Main, no third port number received.";
	}
if ($firstPort != $thirdPort)
	{
	push @errors, "Round robin fail, third port is not same as first port.";
	}
	
# Use a bad port, see if Main can redirect.
my $bogusPort = $swarmServerPort + 10;
$url = "http:$serverAddress:$bogusPort/$shortName/?req=main";
$driver->get($url);
$body_text = $driver->get_body();
if ($body_text !~ m!My service port\: (\d+)!)
	{
	push @errors, "Bogus port ten above did not work, no redirect.";
	}

# Shut down the Chrome WebDriver (also closes the web page).
$driver->shutdown_binary;

# Send back 'ok' or error details.
# intramine_test.pm#ReportDoneTesting()
ReportDoneTesting(\@errors);
