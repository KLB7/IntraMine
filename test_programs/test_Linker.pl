# test_Linker.pl: test intramine_linker.pl.

# Command line, as invoked by swarmserver.pm#SelfTest() (path and numbers will vary):
# perl "C:\perlprogs\mine\test_programs\test_Linker.pl" 192.168.1.132 81 Linker 43125

use strict;
use warnings;
use URI::Escape;
use IO::Socket;
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
#my $driver = StartBrowserDriver(); # intramine_test.pm#StartBrowserDriver()

# Ask for a link on a known document.
my $indexedFileName = CVal('ES_INDEX_TEST_FILE_NAME'); # elasticsearch_index_test.txt
if ($indexedFileName eq '')
	{
	$canContinue = 0;
	push @errors, "'ES_INDEX_TEST_FILE_NAME' not found in config";
	}

if ($canContinue)
	{
	#request.open('get', 'http://' + mainIP + ':' + linkerPort + '/?req=nonCmLinks'
	#			+ '&remote=' + remoteValue + '&allowEdit=' + allowEditValue + '&useApp=' + useAppValue
	#			+ '&text=' + encodeURIComponent(visibleText) + '&peeraddress=' + encodeURIComponent(peeraddress)
	#			+ '&path=' + encodeURIComponent(thePath) + '&first=' + firstVisibleLineNum + '&last='
	#			+ lastVisibleLineNum);
	my $mainIP = ServerAddress();
	my $linkerPort = SwarmServerPort();
	my $remoteValue = 0;
	my $allowEdit = 0;
	my $useApp = 0;
	my $peerAddr = $mainIP;
	my $firstVisibleLineNum = 1;
	my $lastVisibleLineNum = 1;
	my $visibleText = $indexedFileName;
	my $url = "http://$mainIP:$linkerPort/?req=nonCmLinks&remote=$remoteValue" . 
			  "&allowEdit=$allowEdit&useApp=$useApp&text=$visibleText" . 
			  "&peeraddress=$peerAddr&path=none&" . 
			  "&first=$firstVisibleLineNum&last=$lastVisibleLineNum";
	my $req = "req=nonCmLinks&remote=$remoteValue" . 
			  "&allowEdit=$allowEdit&useApp=$useApp&text=$visibleText" . 
			  "&peeraddress=$peerAddr&path=none&" . 
			  "&first=$firstVisibleLineNum&last=$lastVisibleLineNum";
	
	# intramine_test.pm#GetResponseFromService()
	my $resp = GetResponseFromService($mainIP, $linkerPort, $req, \@errors);
	# Expect something like HTTP/1.1 200 OK...
	#<a href="http://192.168.1.132:81/Viewer/?href=c:/perlprogs/mine/test_programs/
	#elasticsearch_index_test.txt" onclick="openView(this.href); return false;"  target="_blank">
	#elasticsearch_index_test.txt</a>...
	# Note the Short name is "Viewer" there, since it's a link for the Viewer to handle.
	
	if ($resp !~ m!<a href\=\"http\://[^/]+/[^/]+/\?href\=.+?$indexedFileName!i)
		{
		$canContinue = 0;
		push @errors, "Anchor not found in |$resp|";
		}
	}

# Send back 'ok' or error details.
# intramine_test.pm#ReportDoneTesting()
ReportDoneTesting(\@errors);

