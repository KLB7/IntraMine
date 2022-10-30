# intramine_eventsserver.pl: calendar with events.
# There's a link to edit the calendar events on the resulting web page.
# NOTE this is not recommended as a starting point for your own server - for that, see
# intramine_boilerplate.pl and intramine_db_example.pl.
# This is more an example of a first draft of a service, before the JavaScript is moved out
# to separate files.
#
# TO run this server, uncomment the line
# 1	Events				Events		intramine_eventsserver.pl
# in data/serverlist.txt.
#
# This server is invoked by Main through
# perl C:\perlprogs\mine\intramine_eventsserver.pl 81 43128
# (the port numbers might vary).

use strict;
use warnings;
use utf8;
use Win32::Process;
use HTML::CalendarMonthSimple;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use holidays; 	# holidays for EventsPage()
use swarmserver;

# Start standard boilerplate.
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
# End standard boilerplate.

# Text file holding calendar events.
my $EventsTextPath = FullDirectoryPath('EVENTSTEXTPATH');

# Request actions, dependent on the task at hand.
my %RequestAction;
$RequestAction{'req|main'} = \&EventsPage; 					# req=main
$RequestAction{'req|css'} = \&GetRequestedFile; 			# req=css
$RequestAction{'req|eventsjs'} = \&EventsPageJS; 			# req=eventsjs
$RequestAction{'req|js'} = \&GetRequestedFile; 				# req=js
$RequestAction{'req|eventscontent'} = \&EventsPageContent; 	# req=eventscontent
$RequestAction{'req|open'} = \&OpenTheFile; 				# req=open
#$RequestAction{'req|id'} = \&Identify; 					# req=id - see swarmserver.pm#ServerIdentify()

# One last line of boilerplate, over to swarmserver.pm to handle network request/response.
MainLoop(\%RequestAction);

##################### subs
# Looking for Output()? See swarmserver.pm#Output().

# NOTE this is very first draft, the call to Notepad++ is hard wired.
sub OpenTheFile {
	my ($obj, $formH, $peeraddress) = @_;
	my $status = 'OK';
	
	#print("EVENTS OpenTheFile called, for |$formH->{'file'}|\n");
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

# Called in response to 'req=main' from intramine_main.pl.
sub EventsPage {
	my ($obj, $formH, $peeraddress) = @_;

	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<title>Events</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="events.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
<script type="text/javascript" src="tooltip.js"></script>
<!-- addtional CSS inserted by intramine_eventsserver.pl -->
<script type="text/javascript">

	function getRandomInt(min, max) {
  		return Math.floor(Math.random() * (max - min + 1) + min);
		}

_LOADANDGO_
</script>
</head>
<body>
_TOPNAV_
<!-- content will be loaded by intramine_eventsserver.pl#EventsPageContent() in response to
req=eventscontent which is sent by loadPageContent(). And loadPageContent() JS is
loaded by 'req=eventsjs'. So goes the dance.
-->
<div id="eventscalendars">loading...</div>
<script>
window.addEventListener('wsinit', function (e) { wsSendMessage('activity ' + shortServerName + ' ' + ourSSListeningPort); }, false);
</script>
</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);
	$theBody =~ s!_TOPNAV_!$topNav!;
	
	my $serverAddr = ServerAddress();
	my $loadItems = "'req=eventsjs', function fn(arrr) {loadPageContent(arrr);}";
	my $contentID = 'eventscalendars';
	my $host = $serverAddr;
	my $port = $port_listen;
	my $pgLoader = GetStandardPageLoader($loadItems, $contentID, $host, $port);
	$theBody =~ s!_LOADANDGO_!$pgLoader!;

	# Put in main IP, main port, our short name for JavaScript.
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()

	return $theBody;
	}

sub EventsPageContent {
	my ($obj, $formH, $peeraddress) = @_;
	my $todayDate = DateYYYYMMDD();
	$todayDate =~ m!^(\d\d\d\d)(\d\d)!;
	my $startYear = $1;
	my $startMonth = $2;
	if (defined($formH->{'startym'}))
		{
		$formH->{'startym'} =~ m!^(\d\d\d\d)(\d\d)!;
		my $yr = $1;
		my $mn = $2;
		if ( defined($yr) && defined($mn)
		  && $yr >= 2010 && $yr <= 2030 && $mn >= 1 && $mn <= 12 )
			{
			$startYear = $yr;
			$startMonth = $mn;
			}
		}
		
	LoadCalendarEventsFromText($EventsTextPath);
	
	my $theBody = EventsPageContentHTML($peeraddress, $todayDate, $startYear, $startMonth);
	return $theBody;
	}

{ ##### Events Calendar
# Year-Month-Day, Event type, Text (assume event type 'deadline' if it's blank)
my %CalendarEvents; # $CalendarEvents{YYYYMMDD} = "deadline\tAppendix out\tLeave a tip"
my $lastRefreshTime;
my $lastModTime;
my $minimumRefreshSeconds;
my $loadedOnce;
my $loadFromText;

sub LoadCalendarEventsFromText {
	my ($path) = @_;
	
	%CalendarEvents = ();
	my @events;
	my $numEvents = LoadFileIntoArray(\@events, $path, "calendar events");
	Output("$numEvents calendar event rows loaded.\n");
	for (my $row = 1; $row < $numEvents; ++$row)
		{
		my @fields = split(/\t/, $events[$row]);
		my $numFields = @fields;
		my $dateEntry = $fields[0];
		if ($numFields >= 3 && $dateEntry =~ m!\d+!)
			{
			my $date = $dateEntry;
			if ($date ne '0')
				{
				my $eventType = lc($fields[1]);
				$eventType =~ s!^\s+!!;
				$eventType =~ s!\s+$!!;
				if ($eventType eq '')
					{
					$eventType = 'deadline';
					}
				my $eventText = $fields[2];
				my $comment = $fields[3];
				$comment ||= '';
				if ($eventText ne '')
					{
					if (defined($CalendarEvents{$date}))
						{
						$CalendarEvents{$date} .= "|$eventType\t$eventText\t$comment";
						}
					else
						{
						$CalendarEvents{$date} = "$eventType\t$eventText\t$comment";
						}
					}
				}
			}
		}
	}


sub EventsPageContentHTML {
	my ($peeraddress, $todayDate, $startYear, $startMonth) = @_;
	my $theBody = EventsPageContentHtmlTemplate();
	
	my $yr = $startYear;
	my $m = $startMonth;
	
	my $todayIsNotAWorkingDay = (IsWeekendYYYYMMDD($todayDate) || IsAHolidayYYYYMMDD($todayDate));
	
	my @cals;
	for (my $i = 1; $i <= 4; ++$i)
		{
		my $month = $m;
		my $year = $yr;
		
		my $cal = HTML::CalendarMonthSimple->new('year'=>$year,'month'=>$month);
		for (my $day = 1; $day < 32; ++$day)
			{
			my $yyyymd = sprintf("%04d%02d%02d", $year,$month,$day);
			if (IsAHolidayYYYYMMDD($yyyymd))
				{
				my $holidayName = HolidayNameForYYYYMMDD($yyyymd);
				$cal->setcontent($day, "<p class='holiday'>$holidayName</p>");
				}
			}
		foreach my $ymd (keys %CalendarEvents)
			{
			$ymd =~ m!^(\d\d\d\d)(\d\d)(\d\d)$!;
			my $y = $1;
			my $m = $2;
			my $d = $3;
			if ($y == $year && $m == $month)
				{
				my $evtAndText = $CalendarEvents{$ymd};
				my @entries = split(/\|/, $evtAndText);
				for (my $i = 0; $i < @entries; ++$i)
					{
					my @fields = split(/\t/, $entries[$i]);
					my $eventType = $fields[0];
					my $name = $fields[1];
					$name =~ s!'!\\'!g;
					
					if ($eventType eq 'deadline')
						{
						if ($ymd < $todayDate)
							{
							$eventType = 'pastdeadline'; # These show in a slightly darker and more ominous colour. Yes I am Canadian.
							}
						}
					
					# Always show tip if there's a comment in $fields[2] or event is in the future (show days remaining).
					if ((defined($fields[2]) && $fields[2] ne '') || $todayDate < $ymd)
						{
						my $tipStr = '';
						if ($todayDate < $ymd)
							{
							my $daysRemaining = ElapsedDaysYYYYMMDD($todayDate, $ymd) + 1;
							if ($todayIsNotAWorkingDay)
								{
								--$daysRemaining;
								}
							my $daysLeftStr = "$daysRemaining business days left (inclusive)";
							$tipStr = $daysLeftStr;
							}
							
						my $haveUserComment = 0;
						if (defined($fields[2]) && $fields[2] ne '') # comment
							{
							$haveUserComment = 1;
							my $comment = $fields[2];
							$comment =~ s!'!\\'!g;
							if ($tipStr ne '')
								{
								$tipStr .= "<br > $comment";
								}
							else
								{
								$tipStr = "$comment";
								}
							}
							
						if ($haveUserComment)
							{
							my $tipMarker = "<div class='tipmarker'><p class='tipmarkeractual'><img src='comment.png' alt='' width='6' height='6' /></p></div>";
							$cal->addcontent($d, "<div class='$eventType hastip'><a href=\"#\" class=\"plainhintanchor\" onmouseOver=\"showhint('$tipStr', this, event, '500px', false)\">$name</a>$tipMarker</div>");
							}
						else
							{
							$cal->addcontent($d, "<p class='$eventType'><a href=\"#\" class=\"plainhintanchor\" onmouseOver=\"showhint('$tipStr', this, event, '500px', false)\">$name</a></p>");
							}
						}
					else # In the past and no comment: no tooltip.
						{
						$cal->addcontent($d, "<p class='$eventType'>$name</p>");
						}
					} # for entries in current calendar events record
				} # if year and month agree
			}# for each calendar events record
		
		$cal->border(3);
		$cal->weekendcolor('#DDDDDD');
		$cal->todaycolor('#CBFFA8'); # '#FFFFDD'
		$cal->headercolor('black'); # or 
		$cal->headercontentcolor('white');
		
		$cal->saturday('Sat');
		$cal->sunday('Sun');
		$cal->weekdays('Mon','Tue','Wed','Thu','Fri');
		
		push @cals, $cal;
		
		
		++$m;
		if ($m > 12)
			{
			$m = 1;
			++$yr;
			}
		} # for 1 to 4 (months)
	
	for (my $i = 0; $i < @cals; ++$i)
		{
		my $calNumber = $i + 1;
		my $calRepString = '_CALENDAR' . $calNumber . '_';
		my $htmlCal = $cals[$i]->as_HTML;
		$theBody =~ s!$calRepString!$htmlCal!g;
		}
	
	# Ahead-back arrows nav links.
	my $singleAheadMonth = $startMonth + 1;
	my $singleAheadYear = $startYear;
	if ($singleAheadMonth > 12)
		{
		$singleAheadMonth -= 12;
		++$singleAheadYear;
		}
	my $singleAheadYM = sprintf("%04d%02d", $singleAheadYear,$singleAheadMonth);
	my $doubleAheadMonth = $startMonth + 3;
	my $doubleAheadYear = $startYear;
	if ($doubleAheadMonth > 12)
		{
		$doubleAheadMonth -= 12;
		++$doubleAheadYear;
		}
	my $doubleAheadYM = sprintf("%04d%02d", $doubleAheadYear,$doubleAheadMonth);
	my $singleBackMonth = $startMonth - 1;
	my $singleBackYear = $startYear;
	if ($singleBackMonth < 1)
		{
		$singleBackMonth += 12;
		--$singleBackYear;
		}
	my $singleBackYM = sprintf("%04d%02d", $singleBackYear,$singleBackMonth);
	my $doubleBackMonth = $startMonth - 3;
	my $doubleBackYear = $startYear;
	if ($doubleBackMonth < 1)
		{
		$doubleBackMonth += 12;
		--$doubleBackYear;
		}
	my $doubleBackYM = sprintf("%04d%02d", $doubleBackYear,$doubleBackMonth);
	
	my $serverAddr = ServerAddress();
	my $clientIsRemote = 0;
	# If client is on the server then peeraddress can be either 127.0.0.1 or $serverAddr:
	# if client is NOT on the server then peeraddress is not 127.0.0.1 and differs from $serverAddr.
	if ($peeraddress ne '127.0.0.1' && $peeraddress ne $serverAddr)
		{
		$clientIsRemote = 1;
		}
	
	my $rdm = random_int_between(1, 65000);
	my $editL = '';
	if (!$clientIsRemote)
		{
		$editL = "<a id='eventseditlink' href='$EventsTextPath?rddm=$rdm'  onclick='OpenEventsFile(this.href); return false;'>Edit Events</a>";
		}
	$theBody =~ s!_EDITEVENTSLINK_!$editL!;
	$theBody =~ s!_DOUBLEBACK_!startym=$doubleBackYM\&rddm=$rdm!;
	$theBody =~ s!_BACK_!startym=$singleBackYM\&rddm=$rdm!;
	$theBody =~ s!_AHEAD_!startym=$singleAheadYM\&rddm=$rdm!;
	$theBody =~ s!_DOUBLEAHEAD_!startym=$doubleAheadYM\&rddm=$rdm!;

	# Rev May 26 2021, localhost is no longer used here.
	# Required by Chrome for "CORS-RFC1918 Support".
	$theBody =~ s!localhost!$serverAddr!g;
	
	# Put in port for this server.
	$theBody =~ s!_EVENTSPORT_!$port_listen!g;

	
	return $theBody;
	}

sub EventsPageContentHtmlTemplate {
	my $theBody = <<'FINIS';
<!-- _DATESTAMP_ -->
<div class='editevents'>
_EDITEVENTSLINK_
</div>
<div class="tinyspacernobreak">&nbsp;</div>
<table class='navarrows'>
<tr>
	<td>
		<a href='_DOUBLEBACK_' onclick='loadPageContent(this.href); return false;'><img src='http://localhost:_EVENTSPORT_/Actions-arrow-left-double-icon.png' alt='Back three months' title='Back three months' width='48' height='48'></a>
	</td>
	<td>
		<a href='_BACK_' onclick='loadPageContent(this.href); return false;'><img src='http://localhost:_EVENTSPORT_/Actions-arrow-left-icon.png' alt='Back one month' title='Back one month' width='48' height='48'></a>
	</td>
	<td>
		<a href='_AHEAD_' onclick='loadPageContent(this.href); return false;'><img src='http://localhost:_EVENTSPORT_/Actions-arrow-right-icon.png' alt='Ahead one month' title='Ahead one month' width='48' height='48'></a>
	</td>
	<td>
		<a href='_DOUBLEAHEAD_' onclick='loadPageContent(this.href); return false;'><img src='http://localhost:_EVENTSPORT_/Actions-arrow-right-double-icon.png' alt='Ahead three months' title='Ahead three months' width='48' height='48'></a>
	</td>
</tr>
</table>
<div class="allcalendars">
	<div class="calendar13">
	_CALENDAR1_
	</div>
	<div class="calendar24">
	_CALENDAR2_
	</div>
	<div style="clear:both;"></div>
	<div class="spacer">&nbsp;</div>
	<div class="calendar13">
	_CALENDAR3_
	</div>
	<div class="calendar24">
	_CALENDAR4_
	</div>
	<div style="clear:both;"></div>
</div>
FINIS
		
	my $today = NiceToday();
	$theBody =~ s!_DATESTAMP_!$today!g;
	
	return $theBody;
	}

sub EventsPageJS {
	my ($obj, $formH, $peeraddress) = @_;
	my $theJS = <<'FINIS';
var remote = _WEAREREMOTE_;
	
// loadPageContent() is called initially as last entry in GetStandardPageLoader() for Events page, and also by
// actions on the fwd/back anchors.
// errorID and contentID are defined in swarmserver.pm#GetStandardPageLoader().
function loadPageContent(href) {
	var request = new XMLHttpRequest();
	var arrayMatch = /startym=(\d+)/.exec(href);
	if (arrayMatch !== null)
		{
		var startYM = arrayMatch[1];
		// TEST ONLY
		console.log("New startYM :" + startYM);
		showSpinner();
		request.open('get', 'http://_THEHOST_:_THEPORT_/?req=eventscontent&startym=' + startYM, true);
		}
	else // initial request, spinner is going and startYM will be set by intramine_eventsserver.pl
		{
		request.open('get', 'http://_THEHOST_:_THEPORT_/?req=eventscontent', true);
		}
	
	request.onload = function() {
	  if (request.status >= 200 && request.status < 400) {
	    // Success!
	    var e1 = document.getElementById(contentID);
		e1.innerHTML = request.responseText;
		hideSpinner();
	  } else {
	    // We reached our target server, but it returned an error
		var e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>loadPageContent Error, server reached but it returned an error!</p>';
		hideSpinner();
	  }
	};
	
	request.onerror = function() {
	  	// There was a connection error of some sort
	  	var e1 = document.getElementById(errorID);
		e1.innerHTML = '<p>loadPageContent Connection error!</p>';
		hideSpinner();
	};
		
	request.send();
	}

function OpenEventsFile(hrefplusRand) {
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
			    	var e1 = document.getElementById('eventseditlink');
					e1.innerHTML = 'Error trying to open events file, server said ' + resp + '!';
			    	}
			    else
			    	{
			    	var e1 = document.getElementById('eventseditlink');
			    	e1.innerHTML = 'Edit Events';
			    	}
				hideSpinner();
			  } else {
			    // We reached our target server, but it returned an error
			    // TODO make this less offensive.
				var e1 = document.getElementById('eventseditlink');
				e1.innerHTML = 'Error, server reached but it could not open the events file!';
				hideSpinner();
			  }
			};
			
			request.onerror = function() {
			  	// There was a connection error of some sort
			  	// TODO make this less offensive.
			  	var e1 = document.getElementById('eventseditlink');
				e1.innerHTML = 'Connection error while attempting to open events file!';
				hideSpinner();
			};
			
			request.send();
		}
	}	
FINIS

	my $serverAddr = ServerAddress();
	my $clientIsRemote = 0;
	if ($peeraddress ne '127.0.0.1' && $peeraddress ne $serverAddr)
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

} ##### Events Calendar

