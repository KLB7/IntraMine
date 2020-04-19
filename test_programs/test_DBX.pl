# test_DBX.pl: test the DBX server (intramine_db_example.pl).
# For Selenium methods involving "$driver" below, see
# https://metacpan.org/pod/Selenium::Remote::Driver
# Called by swarmserver.pm#SelfTest() when IntraMine is started under test
# with bats/TEST_INTRAMINE.bat.
# intramine_db_example.pl needs "$RequestAction{'/test/'} = \&SelfTest;"
# near the top to trigger calling this program.
# And you need an entry in IntraMine's data/serverlist_for_testing.txt
# with a positive Count for DBX, eg
# 1	DBX					DBX			intramine_db_example.pl
#
# Return 'ok' or a description of errors using __SEP__ between error messages.

# DBX test summary:
# Bring up a web page for DBX, check that title and body seem reasonable.
# Add a new fruit/rating, check it's there, delete it, check it's gone.

# Command line, as invoked by swarmserver.pm#SelfTest():
# perl path_to_IntraMine\test_programs\test_Shortname.pl serverIP mainPort Shortname listenPort
# (path and numbers will vary)
# perl C:\perlprogs\mine\test_programs\test_DBX.pl 192.168.1.132 81 DBX 43125

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
#my $serverAddress;
#my $mainPort;
#my $shortName;
InitTesting(); # intramine_test.pm#InitTesting()
my $shortName = ShortName();

# Collect error strings if any. ReportDoneTesting() at the bottom sends any errors back.
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
my $wantedTitle = 'Example of DB access';
my $pageTitle = $driver->get_title();
if ($pageTitle eq '' || $pageTitle !~ m!$wantedTitle!i)
	{
	push @errors, "Bad page title, expected '$wantedTitle', got '$pageTitle'";
	}
	
# Look for distinctive text in the body.
my $wantedText = 'IntraMine Example Server with db access';
my $body_text = $driver->get_body(); # whole body
if ($body_text !~ m!$wantedText!i)
	{
	push @errors, "Bad body, did not find '$wantedText'";
	}

# Add, verify, delete a test fruit.
# Test fruit: 'CARBUNCLE', rated 3 (yum).
my $newFruit = 'CARBUNCLE';
my $newRating = 3;
my $canContinue = 1;
# - type in a fruit
my $fruitTextElement = $driver->find_element_by_id('fruitnametext');
if ($fruitTextElement == 0)
	{
	$canContinue = 0;
	push @errors, "'fruitnametext' not found";
	}
if ($canContinue)
	{
	$fruitTextElement->send_keys($newFruit);
	}

# - give it a rating
if ($canContinue)
	{
	my $ratingElement = $driver->find_element_by_id('fruitratingtext');
	my $option = $driver->find_child_element($ratingElement, "./option[\@value='$newRating']");
	if ($option != 0)
		{
		$option->set_selected();
		}
	else
		{
		$canContinue = 0;
		push @errors, "'fruitratingtext' option $newRating not found";
		}
	}

# - hit the Add/Update button
if ($canContinue)
	{
	my $addSubmitElement = $driver->find_element_by_id('fruitSubmit');
	if ($addSubmitElement != 0)
		{
		$addSubmitElement->click();
		}
	else
		{
		$canContinue = 0;
		push @errors, "'fruitSubmit' submit button not found";
		}
	}

# - check body has entry for the new fruit
if ($canContinue)
	{
	$body_text = $driver->get_body(); # whole body
	if ($body_text !~ m!$newFruit!i)
		{
		$canContinue = 0;
		push @errors, "'$newFruit' not found in body after adding same";
		}
	}
	
# - hit Delete for the new fruit.
# Find <table> with id 'fruit-table'
# Fetch array of element children for that table (<tr> elements)
# For each tr of table, look for a first element (<td>) containing text 'CARBUNCLE'
# When found, call click on last td of that row to trigger the Delete button.
my $deletedOneFruit = 0;
if ($canContinue)
	{
	my $fruitTableElement = $driver->find_element_by_id('fruit-table');
	if ($fruitTableElement  != 0)
		{
		my $fruitRows = $driver->find_child_elements($fruitTableElement, "tr", 'tag_name');
		my $numRows = @$fruitRows;
		#print("Num fruit rows: |$numRows|\n");
		for (my $i = 0; $i < $numRows; ++$i)
			{
			my $cells = $driver->find_child_elements($fruitRows->[$i], "td", 'tag_name');
			my $numCells = @$cells;
			if ($numCells) # watch out for the <th> row! It has $numCells 0.
				{
				#print("Num cells: |$numCells|\n");
				my $fruitText = $cells->[0]->get_text();
				if ($fruitText =~ m!$newFruit!i)
					{
					if ($numCells >= 3)
						{
						my $lastIdx = $numCells - 1;
						my $lastRowElement = $cells->[$lastIdx];
						$lastRowElement->click();
						$deletedOneFruit = 1;
						sleep(1);
						last;
						}
					}
				}
			}
		}
	else
		{
		$canContinue = 0;
		push @errors, "table with id 'fruit-table' was not found";
		}
	}

if (!$deletedOneFruit)
	{
	$canContinue = 0;
	push @errors, "couldn't click the '$newFruit' Delete button";
	}

# - verify body no longer has entry for the new fruit
if ($canContinue)
	{
	$body_text = $driver->get_body(); # whole body
	if ($body_text =~ m!$newFruit!i)
		{
		$canContinue = 0;
		push @errors, "'$newFruit' still there after hitting its Delete button";
		}
	}


# Shut down the Chrome WebDriver (also closes the web page).
$driver->shutdown_binary;

# Send back 'ok' or error details to Main server.
# intramine_test.pm#ReportDoneTesting()
ReportDoneTesting(\@errors);
