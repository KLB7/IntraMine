# test_common.t: test libs/common.pm.
# The more useful subs are tested.
# Note GetTopFilesInFolder() and GetTopSubfoldersInFolder() aren't tested, it's better
# to use libs/win_wide_filepaths.pm#FindFileWide().

# prove "C:\perlprogs\mine\t\test_common.t"

use strict;
use warnings;
use Test::More;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent(2)->child('libs')->stringify;
use common;

my $ourPath = path($0)->absolute->parent();
my @testPaths;
push @testPaths, $ourPath . "/arrayhashpath.txt";
push @testPaths, $ourPath . "/anotherfile.txt";

my %hash;
$hash{'First'} = 'The First Entry';
$hash{'Second'} = 'The Second Entry';

SaveHashKeysToFile(\%hash, $testPaths[1], "saving test hash keys only for moddate test");
sleep(2);

SaveHashKeysToFile(\%hash, $testPaths[0], "saving test hash keys only");
ok(-f $testPaths[0], "test hash file exists");
my @readArr;
LoadFileIntoArray(\@readArr, $testPaths[0], "reading array", 0);
ok($readArr[0] eq 'First' || $readArr[0] eq 'Second', "array values retrieved");

unlink($testPaths[0]);
SaveKeyTabValueHashToFile(\%hash, $testPaths[0], "saving test hash");

my %readHash;
my $count = LoadKeyTabValueHashFromFile(\%readHash, $testPaths[0], "reading test hash", 0);
ok($count == 2, "two entries in hash file");
ok($readHash{'First'} eq 'The First Entry', "first hash entry is there");

%readHash = ();
$count = LC_LoadKeyTabValueHashFromFile(\%readHash, $testPaths[0], "reading test hash as lc", 0);
ok($count == 2, "two lc entries in hash file");
ok($readHash{'first'} eq 'the first entry', "first lc hash entry is there");

ok(ModDatesAreDifferent($testPaths[0], $testPaths[1], 1), "file mod dates differ");
ok(ModDatesAreDifferent($testPaths[1], $testPaths[0], 1), "file mod dates differ either way");
ok(IsNewerThan($testPaths[0], $testPaths[1], 1), "first file is newer than second");
ok(!IsNewerThan($testPaths[1], $testPaths[0], 1), "but not if tested backwards");
ok(!IsNewerThan($testPaths[0], $testPaths[1], 4), "but not by much");

ok(FreshPath($testPaths[0]) eq "$ourPath/arrayhashpath_1.txt", "fresh path");

unlink($testPaths[0]);
unlink($testPaths[1]);

my $pcname = PropercasedName('eldridge PALMER');
ok($pcname eq 'Eldridge Palmer', "proper cased name |$pcname|");

ok(LeftOverlapLength("C:/AA", "C:/AB") == 4, "overlap 4");
ok(LeftOverlapLength("C:/AA", "P:/AB") == 0, "no overlap");
ok(FileNameFromPath($testPaths[0]) eq 'arrayhashpath.txt', "file name from path");
ok(DirectoryFromPathTS($testPaths[0]) eq "$ourPath/", "dir path from full path");
my ($fileNameProper, $ext) = FileNameProperAndExtensionFromFileName('arrayhashpath.txt');
ok($fileNameProper eq 'arrayhashpath', "file name proper from file name");
ok($ext eq '.txt', "extension from file name");

done_testing();
