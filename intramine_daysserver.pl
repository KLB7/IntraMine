# intramine_daysserver.pl: puts in an HTML skeleton, and supplies CSS and JS for the Days page,
# which shows two month calendars and calculates days (calendar and busines) between dates.
# This is another "mainly for fun" server, and it's all JavaScript. See days.js.

# perl C:\perlprogs\mine\intramine_daysserver.pl 81 43127

use strict;
use warnings;
use utf8;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;

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

# 'req=main' is called by any request for this page.
my %RequestAction;
$RequestAction{'req|main'} = \&DaysPage; 			# req=main
#$RequestAction{'req|id'} = \&Identify; 			# req=id

# Over to swarmserver.pm.
MainLoop(\%RequestAction);

################### subs
sub DaysPage {
	my ($obj, $formH, $peeraddress) = @_;

	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<title>Business Days between dates</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="jsDatePick_ltr.css" />
</head>
<body>
_TOPNAV_
<div id="pageContent" style="margin-left:15px;padding-left:10px;">
<form id='daysform'>
<table>
<tr><td id='startdate'>Start Date</td><td>&nbsp;</td><td id='enddate'>End Date</td></tr>
<tr><td><div id="calendar1" style="margin:10px 0 30px 0; width:205px; height:210px;"></div></td>
<td>&nbsp;&nbsp;&nbsp;</td><td><div id="calendar2" style="margin:10px 0 30px 0; width:205px; height:210px;"></div></td></tr>
<tr><td colspan='2' align='right'>Business days between dates:</td><td><input name='elapsed' size='5' style='font-weight:bold;'></td></tr>
<tr><td colspan='2' align='right'>Calendar days between dates:</td><td><span id="cal_elapsed">0</span></td></tr>
</table>
</td></tr></table>
<input type="submit" style="display:none">
</form>
</div>
<h3>Notes</h3>
<div style='width:90%'>
<ol>
	<li>Weekends and government standard holidays are not counted as business days.</li>
	<li>Start and End Date are both counted.</li>
	<li>Click on the calendars to set the start and end dates and see the days between those dates.</li>
	<li>Or set the start date and type in the &ldquo;Business days between dates&rdquo; to set the end date.</li>
</ol>
</div>
<script src="jquery-3.4.1.min.js"></script>
<script src="jsDatePick.full.1.3.js"></script>
<script src="days.js"></script>
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script>
window.addEventListener("load", startCustomDateJS);
hideSpinner();
</script>
</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);
	$theBody =~ s!_TOPNAV_!$topNav!;

	# Put in main IP, main port, our short name for JavaScript.
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()

	return $theBody;
	}
