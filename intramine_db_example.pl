# intramine_db_example.pl: a simple database example service. It just rates some fruit.
# A small form lets you add a fruit with rating, or change a rating. The main goal here is to
# show how to write the callbacks that an IntraMine service needs, to bring up a page and
# respond to events detected by a JavaScript function such as clicking a button.
# A RESTful approach is used for communications between the JavaScript handling the db display
# and update form,  and the backend Perl supplying and updating db entries.
# A GET to /DBX/fruit/ returns all db entries (fruit names and ratings).
# A POST to /DBX/fruit/orange/3/ sets the rating for "orange" to 3.
# A DELETE to /DBX/fruit/banana/ will delete the fruit named "banana".
# Companion JS is in db_examples.js.
#
# Running and accessing this service:
# To run this server up, put
#1 	DBX			DBX		intramine_db_example.pl
# in your data/serverlist.txt file, and restart IntraMine if it's running.
# (omit the '#' at the start of the line and use one or more tabs only to separate fields).
# This service will be named 'DBX' in the top navigation bar on any Intramine page.
# Under the hood:
# As mentioned, IntraMine services use callbacks to get things done. The callbacks should be
# entered in your %RequestAction hash (see below l. 103 for an example).
# You can use two different approaches to trigger a callback, either a RESTful approach
# with a trigger word in the URL (eg GET or POST http://host:port/shortName/trigger/more/stuff/)
# or an argument-based approach, with "trigger=value" arguments in the URL
# (eg http://host:port/optionalwords/?arg1=more&arg2=stuff).
# This example service uses the RESTful approach for creating, updating, and reading db entries.
# The single request action for that is
# $RequestAction{"/fruit/"} = \&HandleFruitRequest;
# In db_example.js, xmlHttpRequests are sent back to the "/fruit/" action with for example:
# http://host:port/DBX/fruit/apple/3/ as a POST to create or update the "apple" entry
#  with a rating of 3;
# http://host:port/DBX/fruit/ as a GET to retrieve all fruit names and ratings.
# To bring up the DBX page, the request action is
# $RequestAction{'req|main'} = \&OurPage;
# which calls OurPage() in response to http://host:port/DBX
# - and also in response to http://host:port/DBX/?req=main
# but the "req=main" is optional, and is the default action.
# All services that respond to browser URLs with an HTML page should have a
# $RequestAction{'req|main'} entry, and of course return a full HTML page.
# All request action callback such as HandleFruitRequest() and OurPage() receive three
# arguments: $obj, $formH, $peeraddress
#  - $obj holds the URL (or URI) such as /DBX/fruit/apple/4/
# - $formH is a reference to a hash, holding whatever arguments were supplied with the URL,
#   for example with http://host:port/optionalwords/?arg1=more&arg2=stuff
#   you would find $formH->{arg1} == 'more' and $formH->{'arg2'} has value 'stuff'.
# - $peeraddress is the your service address, which will be different from your
#   numeric localhost address if you are accessing IntraMine from a remote PC (ie not directly
#   on the PC where IntraMine is running).

# Command line using default ports, as called by intramine_main.pl#StartServerSwarm():
# 	perl C:\perlprogs\mine\intramine_db_example.pl DBX DBX 81 431NN
# (431NN is replaced by a port number, determined when Main starts.)

##### COPY THIS TO YOUR NEW SERVER.
use strict;
use warnings;
use utf8;
use DBM::Deep; # not really needed in your own server, most likely
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;

$|  = 1;

my $PAGENAME = '';
my $SHORTNAME = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

my $kLOGMESSAGES = 0;			# 1 == Log Output() messages, and print to console window
my $kDISPLAYMESSAGES = 0;		# 1 == just print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print. See swarmserver.pm#Output().
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);
Output("Starting $SHORTNAME on port $port_listen\n\n");
##### END COPY THIS TO YOUR NEW SERVER. (But keeping reading, there's a bit more to do
# after we make and access our little database.)

# Make a tiny db table, just for this example. No need to copy this bit.
my $dbPath = FullDirectoryPath('DBEGPATH');
if ($dbPath eq '')
	{
	die("ERROR, \$dbPath is empty!");
	}
my $dbExisted = 0;
if (-f $dbPath)
	{
	$dbExisted = 1;
	}
my $db = DBM::Deep->new($dbPath);
# If db has just been created, poke in some fruits with their ratings.
if (!$dbExisted)
	{
	# Poke a few entries in. Rate that fruit.
	$db->{Apple} = '4';
	$db->{Orange} = '3';
	$db->{Banana} = '5';
	$db->{Lime} = '1';
	}
# End make a tiny table. Things get interesting again:)

##### ADD AND MODIFY THIS: %RequestAction, for actions that your server responds to.
##### %RequestAction entries respond to requests to show pages, load dynamic JS and CSS, respond to events.
# For this example
#  OurPage() returns the whole page to the browser,
#  AddOrUpdateFruit() is called by db_example.js#addFruitSubmit() when the Add/Update button is clicked, and
#  GetHTMLforDbContents() is called by db_example.js#addFruitSubmit() when it completes
#   succesfully, to update the HTML table of fruits and ratings in the browser window.
my $APINAME = 'fruit';
my %RequestAction;
# Always put a 'req|main' action if your service responds to user requests with an HTML page.
$RequestAction{'req|main'} = \&OurPage; 				# req=main: OurPage() returns HTML for our page
# "/fruit/" handles GET/POST to retrieve/set db entries.
$RequestAction{"/$APINAME/"} = \&HandleFruitRequest;	# get to return whole table, post to add or update a fruit rating
$RequestAction{'/test/'} = \&SelfTest;	# swarmserver.pm#SelfTest(), ask this server to test itself.
# If we were using an argument-based rather than RESTful approach, the request actions
# would look like this:
###$RequestAction{'req|addafruit'} = \&AddOrUpdateFruit; 	# req=addafruit: Create/Update a fruit entry
###$RequestAction{'req|getfruit'} = \&GetHTMLforDbContents;# req=getfruit: get the whole fruit table for display
### and something similar to delete, maybe 'dumpfruit'.
##### END ADD AND MODIFY THIS

#### COPY THIS line into your new server too, it does the HTTP request/response handling.
MainLoop(\%RequestAction);
#### END COPY THIS line

########## subs

# Our example of returning a web page. You will want your own version of this if you present
# a web page to users.
# Note the name "OurPage" corresponds to the %RequestAction value above for 'req|main'.
# You might find the css files useful, but feel free to use your own. main.css contains
# styling for the top navigation bar and scrollable text areas.
# spinner.js handles the pacifier in the top nav, which turns into a question mark and links
# to IntraMines help files when it is stopped. The spinner itself is added by the call
# below to swarmserver.pm#TopNav().
# tooltip.js provides tooltips, for an example of use see intramine_boilerplate.pl.
# Most of the HTML in OurPage() just sets up a simple form, with a table displaying
# fruit details where the _DBCONTENTS_ placeholder is.
#
# Make and return full HTML page. This example shows contents of a small database
# holding fruit names and ratings. See also intramine_boilerplate.pl#ThePage().
#
# intramine_config.js contains setConfigValue() which can be used to retrieve a configuration
# value from IntraMine. It's used in spinner.js to retrieve the name of the main Help file.
# The call to PutPortsAndShortnameAtEndOfBody() puts in the port numbers and Short name
# that setConfigValue() needs.
# spinner.js shows a pacifier or a question mark in the top nav bar. The '?' links to Help.
# 2020-02-18 12_43_13-Example of DB access.png
sub OurPage {
	my ($obj, $formH, $peeraddress) = @_;
	
	Output("\$peeraddress: |$peeraddress|\n");
	
	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>Example of DB access</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="forms.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
</head>
<body>
_TOPNAV_
<div>(Short name _D_SHORTNAME_, our port _D_OURPORT_, main port _D_MAINPORT_)</div>
<h2>IntraMine Example Server with db access</h2>
<div id='scrollAdjustedHeight'>
	<div id='theTextWithoutJumpList'>
		<!-- Form for adding a fruit, with rating. -->
		<form class="form-container-medium" id="ftsform" method="get" onsubmit="addFruitSubmit(this); return false;">
		<table>
			<tr>
				<td><h2>Fruit&nbsp;</h2></td>
				<td><input id="fruitnametext" class="form-field" type="search" name="fruitname" placeholder='name a fruit' required /></td>
				<td><h2>Rating&nbsp;</h2></td>
				<td>
				<select name="fruitrating" id="fruitratingtext"">
					<option value="1">1</option>
					<option value="2">2</option>
					<option value="3">3</option>
					<option value="4">4</option>
					<option value="5">5</option>
				</select>
				</td>
			</tr>
			<tr>
				<td>&nbsp;</td>
				<td colspan="3">
					<div style="text-align:right; width:100%; padding:0;">
						<input id="fruitSubmit" class="submit-button" type="submit" value="Add/Update" />
					</div>
				</td>
			</tr>
		</table>
		</form>
		<!-- Fruit table display. -->
		<h3>db contents, from _DBPATH_</h3>
			<div id='_FRUIT_TABLE_ID_'>
				_DBCONTENTS_
			</div>
	</div>
</div>
<script>
let thePort = '_THEPORT_';
let apiName = '_APINAME_';
let fruitTableId = '_FRUIT_TABLE_ID_';
</script>
<!-- intramine_config.js allows loading IntraMine config values into JavaScript.
Here it's needed in spinner.js for the value of "SPECIAL_INDEX_NAME_HTML". -->
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="todoFlash.js"></script>
<script src="tooltip.js"></script>
<script src="db_example.js"></script>
</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);		# The top navigation bar, with our page name highlighted
	$theBody =~ s!_TOPNAV_!$topNav!;

	# Make up a name for the fruit table div container.
	my $fruitTableId = 'fruit-table';
	$theBody =~ s!_FRUIT_TABLE_ID_!$fruitTableId!g; # There are two instances, hence the 'g'

	# We could show the fruit table contents here, if desired. Instead, the table is loaded
	# at the bottom of db_example.js, which allows putting in the DELETE buttons more easily.
#	my $dbTableContents = GetHTMLforDbContents();
#	$theBody =~ s!_DBCONTENTS_!$dbTableContents!;
	
	# Display database table path.
	$theBody =~ s!_DBPATH_!$dbPath!;
	
	# db_examples.js needs this service's IP address and port for XMLHttpRequest() calls.
	# The IPv4 Address for this server (eg 192.168.0.14):
	# peeraddress might be eg 192.168.0.17
	$theBody =~ s!_THEPORT_!$port_listen!; # our port
	$theBody =~ s!_APINAME_!$APINAME!;
	
	$theBody =~ s!_D_SHORTNAME_!$SHORTNAME!;
	$theBody =~ s!_D_OURPORT_!$port_listen!;
	$theBody =~ s!_D_MAINPORT_!$server_port!;
	
	# Put in main IP, main port (def. 81), and our Short name (DBX) for JavaScript.
	# These are needed in intramine_config.js for example
	PutPortsAndShortnameAtEndOfBody(\$theBody); # swarmserver.pm#PutPortsAndShortnameAtEndOfBody()
	
	return($theBody);
	}

sub HandleFruitRequest {
	my ($obj, $formH, $peeraddress) = @_;
	if (!defined($obj) || !defined($formH->{'METHOD'}))
		{
		return("ERROR");
		}
	
	if ($formH->{'METHOD'} =~ m!post!i)
		{
		if ($obj =~ m!$SHORTNAME/$APINAME/([^/]+)/([^/]+)/!i)
			{
			my $fruitName = $1;
			my $rating = $2;
			return(AddOrUpdateFruit($obj, $formH, $peeraddress, $fruitName, $rating));
			}
		# An argument-based approach to adding a fruit would look like this:
		# (given GET http://host:port/DBX/?fruitname=apple&rating=4)
#		else
#			{
#			my $fruitName = $formH->{'fruitname'};
#			my $rating = $formH->{'rating'};
#			return(AddOrUpdateFruit($obj, $formH, $peeraddress, $fruitName, $rating));
#			}
		}
	elsif ($formH->{'METHOD'} =~ m!get!i) # GET, return whole table
		{
		return(GetHTMLforDbContents($obj, $formH, $peeraddress));
		}
	elsif ($formH->{'METHOD'} =~ m!delete!i)
		{
		if ($obj =~ m!$SHORTNAME/$APINAME/([^/]+)/!i)
			{
			my $fruitName = $1;
			return(DeleteFruit($obj, $formH, $peeraddress, $fruitName));
			}
		}
	else
		{
		return("ERROR BAD METHOD");
		}
	}

# Load up an HTML table from our $db. This is called by OurPage() above for initial display
# and by db_examples.js#refreshFruitDisplay().
sub GetHTMLforDbContents {
	my ($obj, $formH, $peeraddress) = @_; # these are ignored
	
	Output("GetHTMLforDbContents refreshing fruit table display.\n");
	
	my $contents = '<table border="1"><tr><th>Fruit</th><th>Rating</th><th>&nbsp;</th></tr>' . "\n";
	while (my ($key, $value) = each %$db)
		{
		if (!defined($value))
			{
			$value = 'UNDEF';
			}
		$contents .= "<tr><td>$key</td><td>$value</td><td>DELBTN</td></tr>\n";
  		}
  	$contents .= '</table>' . "\n";
	return($contents);
	}

# Add or update db entry for eg DBX/fruit/apple/3/.
# see db_example.js#addFruitSubmit() for the Ajax call to this.
sub AddOrUpdateFruit {
	my ($obj, $formH, $peeraddress, $fruitName, $rating) = @_;
	
	my $propercaseFruitName = ucfirst($fruitName);
	$propercaseFruitName =~ s![^A-Za-z0-9_ -]+!!g;
	if ($propercaseFruitName eq '')
		{
		$propercaseFruitName = 'Bogus fruit';
		}
	if (!defined($rating) || $rating < 1 || $rating > 5)
		{
		$rating = 1;
		}
	
	Output("AddOrUpdateFruit adding |$propercaseFruitName| with rating |$rating|.\n");
	$db->{$propercaseFruitName} = $rating;
	
	# Returned value is mostly ignored.
	return('OK');
	}

# Respond to eg DELETE DBX/fruit/apple/
sub DeleteFruit {
	my ($obj, $formH, $peeraddress, $fruitName) = @_;

	$db->delete($fruitName);
	
	return('OK');
	}
