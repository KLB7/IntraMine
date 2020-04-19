# test_Viewer.pl: test intramine_file_viewer_cm.pl.
# For Selenium methods involving "$driver" below, see
# https://metacpan.org/pod/Selenium::Remote::Driver

################# NOTE ##################
# Some of the tests below call the Linker service (intramine_linker.pl).
# To avoid having the Linker-related tests fail, activate the Linker for testing
# by setting its Count entry to 1 in data/serverlist_for_testing.txt.

# Command line, as invoked by swarmserver.pm#SelfTest() (path and numbers will vary):
# perl "C:\perlprogs\mine\test_programs\test_Viewer.pl" 192.168.1.132 81 Viewer 43125

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

# Fabricate a test URL for test_programs/link_test.cpp. Load the page.
# CodeMirror view first, of link_test.cpp.
my $testProgDir = FullDirectoryPath('TEST_PROGRAM_DIR'); # .../test_programs/
my $testDocName = CVal('ES_INDEX_TEST_FILE_NAME_2'); # link_test.cpp
my $testDocPath = $testProgDir . $testDocName;
my $serverAddress = ServerAddress();
my $swarmServerPort = SwarmServerPort();
my $url = "http:$serverAddress:$swarmServerPort/$shortName/?href=$testDocPath&rddm=1";
$driver->get($url);

# Retrieve the page body.
my $body_text = $driver->get_body(); # whole body
# Body should contain file name (near top);
if ($body_text !~ m!$testDocName!i)
	{
	$canContinue = 0;
	push @errors, "'$testDocName' not found in body";
	}

my $indexedFileName = CVal('ES_INDEX_TEST_FILE_NAME'); # elasticsearch_index_test.txt
if ($canContinue)
	{
	# Retrieve the raw HTML.
	sleep(1);
	my $rawHtml = $driver->get_page_source();
	# This is a CodeMirror view, so there are no explicit links, just class "cmAutoLink"
	# on text that is a link. Look for "link" to elasticsearch_index_test.txt as
	# <span class="cm-comment cmAutoLink">elasticsearch_index_test.txt</span>
	my $linkedFileStr = '<span class="cm-comment cmAutoLink">' . $indexedFileName . '</span>';
	if ($rawHtml !~ m!$linkedFileStr!i)
		{
		$canContinue = 0;
		push @errors, "'$indexedFileName' link not found in CM body";
		}
	}

if ($canContinue)
	{
	# Now bring up elasticsearch_index_test.txt. This is not a CodeMirror view, and here the
	# autolinks are actual links. The last line should have a link on
	# 'test_programs/' . $indexedFileName;
	my $testDocPath2 = $testProgDir . $indexedFileName;
	$url = "http:$serverAddress:$swarmServerPort/$shortName/?href=$testDocPath2&rddm=1";
	$driver->get($url);
	
	sleep(1);
	my $rawHtml = $driver->get_page_source();
	# <a href="http://192.168.1.132:81/Viewer/?href=c:/perlprogs/mine/test_programs/elasticsearch_index_test.txt"
	# onclick="openView(this.href); return false;" target="_blank">"test_programs/elasticsearch_index_test.txt"</a>
	my $linkedFileStr = '<a href="http://[^/]+/Viewer/\?href=' . $testDocPath2
		. '" onclick="openView\(this.href\); return false;" target="_blank">"'
		. 'test_programs/' . $indexedFileName . '"</a>';
	#print("|$linkedFileStr|\n");
	if ($rawHtml !~ m!$linkedFileStr!i)
		{
		$canContinue = 0;
		push @errors, "'$indexedFileName' link not found in text body";
		# TEST ONLY codathon
		#push @errors, "<<<$rawHtml>>>";
		if ($rawHtml !~ m!<a!)
			{
			push @errors, "NO LINKS AT ALL found in text body";
			}
		}
		
	if ($canContinue)
		{
		# There should also be link on just plain $testDocName (link_test.cpp).
		my $linkedFileStr = '<a href="http://[^/]+/Viewer/\?href=' . $testDocPath
		. '" onclick="openView\(this.href\); return false;" target="_blank">'
		. $testDocName . '</a>';
		#print("|$linkedFileStr|\n");
		if ($rawHtml !~ m!$linkedFileStr!i)
			{
			$canContinue = 0;
			push @errors, "'$testDocName' link not found in text body";
			}
		}
		
	# Look for a display table element, "<td>r2c2</td>"
	my $tableTestR2C2 = "<td>r2c2</td>";
	if ($rawHtml !~ m!$tableTestR2C2!i)
		{
		$canContinue = 0;
		push @errors, "'$tableTestR2C2' r2c2 cell not found in text body";
		}
	
	# Look for a third level heading ("Third level heading", that's the text) in the TOC:
	# <a href="#Third_level_heading">Third level heading</a>
	my $headingLink3 = '<a href="#Third_level_heading">Third level heading</a>';
	if ($rawHtml !~ m!$headingLink3!i)
		{
		$canContinue = 0;
		push @errors, "'$headingLink3' TOC link not found in text body";
		}
	
	# The body text for the third level heading should be an h4.
	my $bodyHeading3 = '<h4 id="Third_level_heading">Third level heading</h4>';
	if ($rawHtml !~ m!$bodyHeading3!i)
		{
		$canContinue = 0;
		push @errors, "'$bodyHeading3' body heading not found in text body";
		}
	}


# Shut down the Chrome WebDriver (also closes the web page).
$driver->shutdown_binary;

# Send back 'ok' or error details.
# intramine_test.pm#ReportDoneTesting()
ReportDoneTesting(\@errors);
