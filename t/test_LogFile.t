# test_LogFile.t: test libs/LogFile.pm.

# prove "C:\perlprogs\mine\t\test_LogFile.t"

use strict;
use warnings;
use FileHandle;
use Test::More;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent(2)->child('libs')->stringify;
use common;
use intramine_config;
use LogFile;

my $OurShortName = 'TEST';
my $ourPath = path($0)->absolute->parent();
my $logPath = "$ourPath/testlog.txt";
# my $log = new LogFile(path, clear, echo, leave_open);
my $log = new LogFile($logPath, 1, 0, 0);
$log->Log("Hello from test.\n");

ok(-f $logPath, "log is on disk");
my $logH = new FileHandle($logPath);
ok(defined($logH), "log can be opened");
my $line;
my $ctr = 0;
while ($line = <$logH>)
	{
	chomp($line);
	if ($ctr == 0)
		{
		ok($line =~ m!^last cleared!i, "first log line has 'last cleared'")
		}
	elsif ($ctr == 1)
		{
		ok($line eq 'Hello from test.', "first log line is Hello from test.")
		}
	++$ctr;
	}
close($logH);

unlink($logPath);
ok(!(-f $logPath), "log file is gone");

done_testing();
