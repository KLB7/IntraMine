# test_Search.pl: test intramine_search.pl.
# For Selenium methods involving "$driver" below, see
# https://metacpan.org/pod/Selenium::Remote::Driver

# Command line, as invoked by swarmserver.pm#SelfTest() (path and numbers will vary):
# perl "C:\perlprogs\mine\test_programs\test_Search.pl" 192.168.1.132 81 Search 43125

use strict;
use warnings;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent(2)->child('libs')->stringify;
use intramine_test;

# Grab parameters that specify main ip and port, and our Short name. Also
# load configuration values.
InitTesting(); # intramine_test.pm#InitTesting()
my $shortName = ShortName();

# Collect error strings if any. ReportDoneTesting() at the bottom sends any errors back.
my @errors;
my $canContinue = 1;

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
my $wantedTitle = 'Full Text Search';
my $pageTitle = $driver->get_title();
if ($pageTitle eq '' || $pageTitle !~ m!$wantedTitle!i)
	{
	push @errors, "Bad page title, expected '$wantedTitle', got '$pageTitle'";
	}
	
# Check if any documents are indexed.
my $msg = "?req=docCount"; # See intramine_search.pl#CountOfIndexedDocuments()
my $docCountStr = GetResponseFromOurServer($msg);
my $docCount = 0;
if ($docCountStr =~ m!(\d+)!)
	{
	$docCount = $1;
	}
print("Document count: |$docCountStr|\n");
if ($docCount == 0)
	{
	$canContinue = 0;
	push @errors, "No documents have been indexed";
	}

# For an actual search test, we have to assume something is indexed. To avoid that,
# elastic_indexer.pl indexes test_programs/elasticsearch_index_test.txt if
# bats/IM_INIT_INDEX.bat or bats/ES_FIRST_RUN.bat are ever run. Typically anyone using
# IntraMine will do that if they want search capability. That test document contains
# words that have never been used before in the English language, or any other language.
my $searchWord = 'questionationable';

# Locate "Search for" input and type a word from the test file.
if ($canContinue)
	{
	my $inputTextElement = $driver->find_element_by_id('searchtext');
	if ($inputTextElement == 0)
		{
		$canContinue = 0;
		push @errors, "Search input 'searchtext' not found";
		}
	else
		{
		$inputTextElement->send_keys($searchWord);
		}
	}

# Hit the Search button.
if ($canContinue)
	{
	my $submitButton = $driver->find_element_by_id('searchSubmitButton');
	if ($submitButton == 0)
		{
		$canContinue = 0;
		push @errors, "Could not find 'searchSubmitButton' button";
		}
	else
		{
		$submitButton->click();
		sleep(1);
		}
	}

# Retrieve the page body.
# Look for a hit on our test file, error if not found.
my $body_text = '';
my $rawHtml = '';
my $testProgDir = FullDirectoryPath('TEST_PROGRAM_DIR');
my $testDocName = CVal('ES_INDEX_TEST_FILE_NAME');
my $testDocPath = $testProgDir . $testDocName;
if ($canContinue)
	{
	$body_text = $driver->get_body(); # whole body
	if ($body_text !~ m!$searchWord!i)
		{
		$canContinue = 0;
		push @errors, "'$searchWord' not found in body after searching for it";
		}
	else
		{
		
		if ($body_text !~ m!$testDocName!i)
			{
			$canContinue = 0;
			push @errors, "'$testDocName' not found in hits after searching for it";
			}
		else
			{
			# Did we get a link to the file?
			# <a href=\. path to test doc / testdoc name...
			# Note we want text inside a link href, which is in the "raw HTML" but
			# not in the body text.
			$rawHtml = $driver->get_page_source();
			my $linkString = "<a href=\.$testDocPath";
			if ($rawHtml !~ m!$linkString!i)
				{
				$canContinue = 0;
				push @errors, "Didn't find link for '$testDocPath'";
				}
			}
		}
	}

# Shut down the Chrome WebDriver (also closes the web page).
$driver->shutdown_binary;

# Send back 'ok' or error details.
# intramine_test.pm#ReportDoneTesting()
ReportDoneTesting(\@errors);
