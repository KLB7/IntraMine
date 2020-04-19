# test_Bp.pl: with Bp server running, call up a web page for it and test what comes back.
# For Selenium methods involving "$driver" below, see
# https://metacpan.org/pod/Selenium::Remote::Driver
# Called by swarmserver.pm#SelfTest() when IntraMine is started under test
# with bats/TEST_INTRAMINE.bat.
# intramine_boilerplate.pl needs "$RequestAction{'/test/'} = \&SelfTest;"
# near the top to trigger calling this program.
# And you need an entry in IntraMine's data/serverlist_for_testing.txt
# with a positive Count for Bp, eg
# 1	Bp					Bp			intramine_boilerplate.pl

# Return 'ok' or a description of errors using __SEP__ between error messages.

# This is about the simplest and dullest test program. See test_programs/test_DBX.pl for more fun.

# Command line, as invoked by swarmserver.pm#SelfTest():
# perl path_to_IntraMine\test_programs\test_Shortname.pl serverIP mainPort Shortname listenPort
# (path and numbers will vary)
# perl C:\perlprogs\mine\test_programs\test_Bp.pl 192.168.1.132 81 Bp 43125

use strict;
use warnings;
# These are brought in by intramine_test:
#use Selenium::Remote::Driver;
#use Selenium::Waiter qw/wait_until/;
#use Selenium::Chrome;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent(2)->child('libs')->stringify;
use intramine_test;

# Grab parameters that specify main ip and port, and our Short name. Also
# load configuration values.
my $serverAddress;
my $mainPort;

InitTesting(); # intramine_test.pm#GetTestArguments()
my $shortName = ShortName();

# Collect error strings if any.
my @errors;

# Start the Google Chrome driver.
my $driver = StartBrowserDriver(); # intramine_test.pm#StartBrowserDriver()

# Ask Chrome to load our page.
GetStandarURL($driver);

# Wait for the page to load fully. Default up to 10 seconds.
if (!WaitForPageToLoad($driver)) # intramine_test.pm#WaitForPageToLoad(driver, optional timeout in seconds)
	{
	$driver->shutdown_binary;
	return("$shortName page load failed!");
	}

# Check the page title.
my $wantedTitle = 'Example IntraMine Server';
my $pageTitle = $driver->get_title();
if ($pageTitle eq '' || $pageTitle !~ m!$wantedTitle!i)
	{
	push @errors, "Bad page title, expected '$wantedTitle', got '$pageTitle'";
	}
	
# Look for distinctive text in the body.
my $wantedText = 'Here is some text with a popup text tip';
my $body_text = $driver->get_body(); # whole body
if ($body_text !~ m!$wantedText!i)
	{
	push @errors, "Bad body, expected '$wantedText'";
	}

# Shut down the Chrome WebDriver (also closes the web page).
$driver->shutdown_binary;

# Send back 'ok' or error details.
# intramine_test.pm#ReportDoneTesting()
ReportDoneTesting(\@errors);
