# test_swarmserver1.t: it's difficult to test swarmserver.pm directly since it is designed
# to respond to requests from elsewhere. So tests of swarmserver.pm are mostly indirect,
# and can be found in the server-level test programs in the test_programs/ folder.

# prove C:\perlprogs\mine\t\test_swarmserver1.t

use strict;
use warnings;
use Test::More;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent(2)->child('libs')->stringify;
use common;
use swarmserver;

# Fake the arguments that any IntraMine service receives when starting normally.
# Eg "C:/Progs/Intramine/intramine_fileserver.pl Search Viewer 81 43126"
push @ARGV, "Page";
push @ARGV, "SWARMTEST";
push @ARGV, "81";
push @ARGV, "43126";

my $PAGENAME = '';
my $SHORTNAME = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

my $kLOGMESSAGES = 1;			# 1 == Log Output() messages, and print to console window
my $kDISPLAYMESSAGES = 0;		# 1 == just print messages from Output() to console window

StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);
Output("Pretending to start $SHORTNAME on port $port_listen\n\n");
my $logPath = LogPath();

LoadServerList();

# The tests.
is(OurPageName(), "Page", "Page name");
is(OurShortName(), "SWARMTEST", "Short name");
is(MainServerPort(), "81", "Main port");
is(OurListeningPort(), "43126", "Swarmserver listening port");
ok(defined($logPath), "Log path defined");
ok(NumPages() > 1, "Server list loaded");

my $testValue = CVal('SWARMSERVER_TEST_KEY'); # in data/SWARMTEST_config.txt
is($testValue, "42", "SWARMSERVER_TEST_KEY");

done_testing();