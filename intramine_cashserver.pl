# intramine_cashserver.pl: cash (flow). Monthly cash flow with annual totals, with
# events taken from text file named by CASHFLOWTEXTPATH value in /data/intramine_config.txt.
# The default location is data/Cash_events.txt.
#
# This is just for fun. Heavy on the JavaScript. It does illustrate GetStandardPageLoader(),
# but that's one of those clever solutions that I've decided in the end doesn't really
# address any problems. Calculations are done in cashflow.pm, and display is handled in
# JavaScript (see CalcAndLoadJavaScript below).
# First GetCashFlow() below calls cashflow.pm#GetDatesAndValues() get an HTML text version of
# the cash flow for all wanted months, and also to get the dates and
# ending balances for all months. Then these numbers are used to fill in the _DATA_
# placeholder in the JS for graphing (see CalcAndLoadJavaScript() below), then the page
# is shown, and a call to Google's graphing JS fills in the bar chart.
#
# Cash events file fields: any line starting with ^\s*# is a comment line, ignored.
# Fields are tab-separated.
# Events:
# OPENING amount YYYYMM (Description, ignored)				# Opening balance and month to start
# UNTIL YYYYMM (Description, ignored)						# Ending month, inclusive
# INCOME_ANNUAL amount YYYYMM YYYYMM Description			# Amount, start year and month, end year and month, applied once per year inclusive
# INCOME_MONTHLY amount YYYYMM YYYYMM Description			# Amount, start and end year/month, applied monthly inclusive
# EXPENSE_ANNUAL amount YYYYMM YYYYMM Description			# Like INCOME_ANNUAL, except amount is deducted
# EXPENSE_MONTHLY amount YYYYMM YYYYMM Description			# Like INCOME_MONTHLY, except amount is deducted
# ASSET amount YYYYMM Description							# One-shot expense, in the year/month specified

# There are no explicit twice-a-year or quarterly events, but you can do those with two or four ANNUAL events.
# It's ok if the range of dates for an annual or monthly item is wider than the OPENING/UNTIL range - events outside
# that range will be ignored.
# Example events (hardly complete, and also fictitious):
# OPENING	10000	201611	Opening balance of $10,000 starting Nov 1 2016
# UNTIL	202012	Ending month, inclusive, December 2020
# INCOME_MONTHLY	2000	201611	201812	Monthly income after taxes
# INCOME_MONTHLY	2100	201901	202012	Monthly income after taxes, with a raise
# INCOME_ANNUAL	100	201612	202012	Annual dividend every December
# EXPENSE_ANNUAL	500	201006	204006	Gym, paid every June (note date range is much wider than OPENING/UNTIL range, that's ok)
# EXPENSE_MONTHLY	600	201611	202012	Rent
# EXPENSE_MONTHLY	300	201611	202012	Food (me)
# EXPENSE_MONTHLY	350	201611	202012	Food (dog)
# ASSET	201806	1000	New pencil sharpener wth built-in TV

# Tip: create several scenarios in separate txt files, then one-by-one replace the contents of the cash flow events file and refresh
# the Cash page to see what the consequences are of your mad spending decisions.

# perl C:\perlprogs\mine\intramine_cashserver.pl 81 43129

use strict;
use warnings;
use utf8;
use Carp;
use warnings;
use FileHandle;
use Win32::Process;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;
use cashflow;

#binmode(STDOUT, ":unix:utf8");
$|  = 1;

my $PAGENAME = '';
my $SHORTNAME = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

my $kLOGMESSAGES = 0;			# 1 == Log Output() messages
my $kDISPLAYMESSAGES = 0;		# 1 == print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print.
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);
Output("Starting $SHORTNAME on port $port_listen\n\n");

my $CashTextPath = FullDirectoryPath('CASHFLOWTEXTPATH');

my %RequestAction;
$RequestAction{'req|main'} = \&CashflowPage; 						# req=main
$RequestAction{'req|css'} = \&GetRequestedFile; 					# req=css
$RequestAction{'req|js'} = \&GetRequestedFile; 						# req=js
$RequestAction{'req|calcandloadjs'} = \&CalcAndLoadJavaScript; 		# req=calcandloadjs
$RequestAction{'req|loaddetails'} = \&CashflowDetails; 				# req=loaddetails
$RequestAction{'req|open'} = \&OpenTheFile; 						# req=open
#$RequestAction{'req|id'} = \&Identify; 							# req=id

# Over to swarmserver.pm.
MainLoop(\%RequestAction);

################ subs
sub CashflowPage {
	my ($obj, $formH, $peeraddress) = @_;

	my $theBody = <<'FINIS';
<!doctype html>
<html>    
<head>
<title>Cash Flow</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
</head>
<body>
  _TOPNAV_
    <!--Div that will hold the bar chart-->
    <div id="chart_div"></div>
    <div id="details">
    	<div id="scrollAdjustedHeight">
    		loading...
    	</div>
    </div>
<script src="tooltip.js"></script>
<!--Load the AJAX API-->
<script src="https://www.gstatic.com/charts/loader.js"></script>
<!-- javascript to draw the chart is loaded by an ajax request to CalcAndLoadJS(). -->
<script>
_LOADANDGO_
</script>
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="restart.js"></script>
<script src="topnav.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
<script>
window.addEventListener('wsinit', function (e) { wsSendMessage('activity ' + shortServerName + ' ' + ourSSListeningPort); }, false);
</script>
</body></html>
FINIS
	
	my $topNav = TopNav($PAGENAME);
	$theBody =~ s!_TOPNAV_!$topNav!;

	# $peeraddress eq '127.0.0.1' determines whether we are local.
	# The IPv4 Address for this server is  (eg 192.168.0.14);
	my $serverAddr = ServerAddress();
	
	my $loadItems = "'req=calcandloadjs', function fn(arrr) {LoadDetails(arrr);}";
	my $contentID = 'scrollAdjustedHeight';
	my $host = $serverAddr;
	my $port = $port_listen;
	my $pgLoader = GetStandardPageLoader($loadItems, $contentID, $host, $port);
	$theBody =~ s!_LOADANDGO_!$pgLoader!;

	# Put in main IP, main port, our short name for JavaScript.
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()

	return $theBody;	
	}

# Open the cash events input file in a text editor. Only if client is on the server box.
# Notepadd++ is hard wired as the editor, and from that you might infer that
# the code is "good enough" but not up to customer facing standards.
# As mentioned, this is just for fun. If you don't have notepad++ - why the heck not???
sub OpenTheFile {
	my ($obj, $formH, $peeraddress) = @_;
	my $status = 'OK';
	
	my $filepath = defined($formH->{'file'})? $formH->{'file'}: '';
	$filepath =~ s!\\!/!g;
	Output("|$filepath|\n");
	my $ProcessObj;
	my $openresult = Win32::Process::Create($ProcessObj, $ENV{COMSPEC}, "/c start notepad++ \"$filepath\"", 0, 0, ".");
	if (!$openresult)
		{
		$status = "Could not open |$filepath|";
		}
	return($status);
	}

{ ##### Cash flow details
my $CashFlowHtmlDetails;

# Load some JS from right here in the main program, after poking in some dynamic values.
# This is of course not a great way of doing it, better would be to load the JS from a file.
# But this is a "fun" server after all, so I've followed the rule of
# "if it works, don't refactor it" which I just made up.
sub CalcAndLoadJavaScript {
	my ($obj, $formH, $peeraddress) = @_;
	my $theJS = <<'FINIS';
      // Load the Visualization API and the corechart package.
      google.charts.load('current', {'packages':['corechart']});
      ////google.charts.load('current', {'packages':['bar']});

      // Set a callback to run when the Google Visualization API is loaded.
      google.charts.setOnLoadCallback(drawChart);

      // Callback that creates and populates a data table,
      // instantiates the pie chart, passes in the data and
      // draws it.
      function drawChart() {

		var data = new google.visualization.DataTable();
		data.addColumn('string', 'Year End'); // Implicit domain label col.
		data.addColumn('number', 'Balance'); // Implicit series 1 data col.
		data.addColumn({type:'string', role: 'style'});  // style role col.

		data.addRows([
    			_DATA_
		]);

        // Set chart options
        var options = {'title':'Cash Flow',
                    'width':1200,
                    'height':400,
                    legend: { position: "none" },
			        'hAxis': {
						  title: 'Year',
						  titleTextStyle: {
						    color: '#CCCCCC'
						  },
						  gridlines: {color: '#333', count: 4}
						},
					'vAxis': {
						title: 'Balance',
						titleTextStyle: {
						    color: '#CCCCCC'
						  }
						}
        			};

        // Instantiate and draw our chart, passing in some options.
        var chart = new google.visualization.ColumnChart(document.getElementById('chart_div'));
        ////var chart = new google.charts.Bar(document.getElementById('chart_div'));
        chart.draw(data, options);
        //chart.draw(data, google.charts.Column.convertOptions(options));
      }
      
	window.addEventListener("load", doResize);
	window.addEventListener("resize", doResize);

	function getRandomInt(min, max) {
  		return Math.floor(Math.random() * (max - min + 1) + min);
		}

	function LoadDetails() {
		showSpinner();
		var request = new XMLHttpRequest();
		request.open('get', 'http://_THEHOST_:_THEPORT_/?req=loaddetails', true);
		
		request.onload = function() {
		  if (request.status >= 200 && request.status < 400) {
		    // Success!
		    var e1 = document.getElementById(contentID);
			e1.innerHTML = request.responseText;
			setTimeout(function()
						{
						doResize(); 
						var e1 = document.getElementById('theTextWithoutJumpList');
						e1.scrollTop = e1.scrollHeight;
						}, 1000);
			hideSpinner();
		  } else {
		    // We reached our target server, but it returned an error
			var e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Error, server reached but it returned an error!</p>';
			hideSpinner();
		  }
		};
		
		request.onerror = function() {
		  	// There was a connection error of some sort
		  	var e1 = document.getElementById(errorID);
			e1.innerHTML = '<p>Connection error!</p>';
			hideSpinner();
		};
		
		request.send();
	}

	function OpenCashFlowFile(hrefplusRand) {
		var remote = _WEAREREMOTE_;
		if (!remote)
			{
			var arrayMatch = /^([^?]+)\?/.exec(hrefplusRand);
			var href = arrayMatch[1];
			var properHref = href.replace(/^file\:\/\/\//, '');
			
			showSpinner();
			var request = new XMLHttpRequest();
			request.open('get', 'http://_THEHOST_:_THEPORT_/?req=open&file=' + properHref, true);
			
			request.onload = function() {
				  if (request.status >= 200 && request.status < 400) {
				    // Success?
				    var resp = request.responseText;
				    if (resp !== 'OK')
				    	{
				    	var e1 = document.getElementById('cashfloweditlink');
						e1.innerHTML = 'Error trying to open events file, server said ' + resp + '!';
				    	}
				    else
				    	{
				    	var e1 = document.getElementById('cashfloweditlink');
				    	e1.innerHTML = 'Edit Cash Flow Events';
				    	}
					hideSpinner();
				  } else {
				    // We reached our target server, but it returned an error
					var e1 = document.getElementById('cashfloweditlink');
					e1.innerHTML = 'Error, server reached but it could not open the events file!';
					hideSpinner();
				  }
				};
				
				request.onerror = function() {
				  	// There was a connection error of some sort
				  	var e1 = document.getElementById('cashfloweditlink');
					e1.innerHTML = 'Connection error while attempting to open events file!';
					hideSpinner();
				};
				
				request.send();
			}
	}

function doResize() {
	var el = document.getElementById(contentID);
	
	var pos = getPosition(el);
	var windowHeight = window.innerHeight;
	var elHeight = windowHeight - pos.y;
	//var newHeightPC = (elHeight/windowHeight)*100;
	////el.style.height = newHeightPC + "%";
	el.style.height = elHeight - 24 + "px";
	
	var windowWidth = window.innerWidth;
	el.style.width = windowWidth - 4 + "px";
	}

FINIS

	my @labels;
	my @values;
	$CashFlowHtmlDetails = '';
	GetCashFlow(\@labels, \@values, \$CashFlowHtmlDetails);
	if (substr($labels[0], 0, 5) ne 'FAIL!')
		{
		my $graphData = CashFlowDataString(\@labels, \@values);
		$theJS =~ s!_DATA_!$graphData!;
		}
	else
		{
		$theJS =~ s!_DATA_!!;
		}
		
	my $serverAddr = ServerAddress();
	my $clientIsRemote = 0;
	#print("EVENTS srvr addr: $serverAddr\n");
	#print("EVENTS peer addr: $peeraddress\n");
	# ARG if client is on the server then peeraddress can be either 127.0.0.1 or $serverAddr:
	# if client is NOT on the server then peeraddress is not 127.0.0.1 and differs from $serverAddr.
	if ($peeraddress ne '127.0.0.1' && $peeraddress ne $serverAddr)	#if ($peeraddress ne $serverAddr)
	#if ($peeraddress ne '127.0.0.1')
		{
		$clientIsRemote = 1;
		}
	
	my $amRemoteValue = $clientIsRemote ? 'true' : 'false';
	my $host = $serverAddr;
	my $port = $port_listen;
	$theJS =~ s!_WEAREREMOTE_!$amRemoteValue!;
	$theJS =~ s!_THEHOST_!$host!g;
	$theJS =~ s!_THEPORT_!$port!g;

	return($theJS);
	}

sub CashflowDetails {
	my ($obj, $formH, $peeraddress) = @_;
	
	my $serverAddr = ServerAddress();
	my $clientIsRemote = 0;
	if ($peeraddress ne '127.0.0.1' && $peeraddress ne $serverAddr)
		{
		$clientIsRemote = 1;
		}
	my $rdm = random_int_between(1, 65000);
	my $editDiv = '';
	if (!$clientIsRemote)
		{
		my $editL = "<a id='cashfloweditlink' href='$CashTextPath?rddm=$rdm'  onclick='OpenCashFlowFile(this.href); return false;'>Edit Cash Flow Events</a>";
		# Throw in an edit link
		$editDiv = "<div id='editcashflow'>$editL</div>\n";
		}
	
	my $result = $editDiv . "<div id='theTextWithoutJumpList'>$CashFlowHtmlDetails</div>";
	return($result); # See just above
	}

sub GetCashFlow {
	my ($labels, $vals, $CashFlowHtmlDetailsR) = @_;
	
	my $cashflow = cashflow->new($CashTextPath);
	$cashflow->GetDatesAndValues($labels, $vals, $CashFlowHtmlDetailsR);
	}

# Note color does not (yet) work with material charts (Feb 14 2016).
sub CashFlowDataString {
	my ($labels, $vals)= @_;
	my $graphData = '';
	
	for (my $i = 0; $i <@$vals; ++$i)
		{
		my $comma = ($i > 0) ? ',' : '';
		my $val = $vals->[$i];
		my $clr = '#00C000';
		if ($val < 0)
			{
			$clr = '#C00000';
			}
		elsif ($val <= 2000)
			{
			$clr = '#FACC2E';
			}
		$graphData .= "${comma}\['$labels->[$i]', $val, 'color: $clr'\]";
		}
	return $graphData;
	}
} ##### Cash flow details
