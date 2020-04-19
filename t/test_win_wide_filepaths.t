# test_win_wide_filepaths.t: test libs/win_wide_filepaths..pm UTF-16 file paths and directory lists.
# Not tested:
# DeepFindFileWide(): for a working example, see elastic_indexer.pl#101.
# ActualPathIfTooDeep(): tested a bit, but not currently used in IntraMine.

# prove "C:\perlprogs\mine\t\test_win_wide_filepaths.t"

use strict;
use warnings;
use Test::More;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent(2)->child('libs')->stringify;
use common;
use win_wide_filepaths;

my $ourPath = path($0)->absolute->parent();
my @testPaths;
push @testPaths, $ourPath . "/北京.txt"; # Beijing, so I've been told
push @testPaths, $ourPath . "/doesnotexist.txt";
push @testPaths, $ourPath . "/copy.txt";
my $subDirToRemove = "remthis";
my $nestedSubDirToRemove = "inremthis";

# Write "unicode" to a file with "unicode" in the name. You know what I mean:)
# Check contents are correct, as text and HTML.
ok(!FileOrDirExistsWide($testPaths[0]), "$testPaths[0] does not exist");
WriteTextFileWide($testPaths[0], "/北京");
ok(FileOrDirExistsWide($testPaths[0]) == 1, "$testPaths[0] now exists");
my $contents = ReadTextFileWide($testPaths[0]);
ok($contents eq "/北京", "Contents are '/北京'");
AppendToTextFileWide($testPaths[0], " hello");
$contents = ReadTextFileWide($testPaths[0]);
ok($contents eq "/北京 hello", "Contents are '/北京 hello'");
AppendToExistingTextFileWide($testPaths[0], " <tag&>");
$contents = ReadTextFileWide($testPaths[0]);
ok($contents eq "/北京 hello <tag&>", "Contents are '/北京 hello <tag&>'");
$contents = GetHtmlEncodedTextFileWide($testPaths[0]);
ok($contents eq "/北京 hello &lt;tag&amp;&gt;", "Contents are '/北京 hello &lt;tag&amp;&gt;'");
my $fileSize = GetFileSizeWide($testPaths[0]);
ok($fileSize == 20, "file size is 20");

# Check modification time stamp is reasonable.
my $fileModTime = GetFileModTimeWide($testPaths[0]);
ok(defined($fileModTime), "file mode time is defined");
my $currentTime = time;
ok($currentTime >= $fileModTime && $fileModTime <= $currentTime + 2, "mod time is just before now");

# File copy tests.
ok(CopyFileWide($testPaths[0], $testPaths[2], 1), "copy to file that does not exist yet");
ok(!CopyFileWide($testPaths[0], $testPaths[2], 1), "no copy to file that exists");

# List directory items, check for the file we just made.
my @allTopLevelItems = FindFileWide($ourPath . '/');
my $numTopLevel = @allTopLevelItems;
ok($numTopLevel > 1, "more than one item in $ourPath");
my $foundIt = 0;
for (my $i = 0; $i < @allTopLevelItems; ++$i)
	{
	if ($allTopLevelItems[$i] eq "北京.txt")
		{
		$foundIt = 1;
		last;
		}
	}
ok($foundIt, "FindFileWide can find $testPaths[0]");

# Test making and removing a directory.
my $fullPathToMake = $ourPath . "/$subDirToRemove";
ok(MakeDirWide($fullPathToMake), "make dir $fullPathToMake");
my $fileInNewDirPath  = "$fullPathToMake/tempfile.txt";
CopyFileWide($testPaths[0],$fileInNewDirPath, 1);
ok(FileOrDirExistsWide($fileInNewDirPath) == 1, "$fileInNewDirPath now exists");
ok(!RemoveDirWide($fullPathToMake), "RemoveDirWide should fail, dir is not empty");
DeleteFileWide($fileInNewDirPath);
ok(RemoveDirWide($fullPathToMake), "RemoveDirWide should succeed, dir is empty");

# Test making and removing a directory, where two nested dirs are made.
my $nestedPathToMake = "$fullPathToMake/$nestedSubDirToRemove";
ok(MakeAllDirsWide($nestedPathToMake), "make a nested dir $nestedPathToMake");
$fileInNewDirPath  = "$nestedPathToMake/tempfile.txt";
CopyFileWide($testPaths[0],$fileInNewDirPath, 1);
ok(!RemoveDirWide($nestedPathToMake), "RemoveDirWide fail, nested dir is not empty");
DeleteFileWide($fileInNewDirPath);
ok(RemoveDirWide($nestedPathToMake), "RemoveDirWide ok, nested dir is empty");
ok(RemoveDirWide($fullPathToMake), "RemoveDirWide ok one level up, dir is empty");

# Clean up, and check files go away (and come back if wanted).
DeleteFileWide($testPaths[0]);
DeleteFileWide($testPaths[2]);
ok(!AppendToExistingTextFileWide($testPaths[1], "hello"), "no append if file does not exist");
ok(!FileOrDirExistsWide($testPaths[1]), "$testPaths[1] does not exist after attempted append");
ok(!FileOrDirExistsWide($testPaths[0]), "$testPaths[0] is gone again");
WriteBinFileWide($testPaths[0], "hello");
ok(FileOrDirExistsWide($testPaths[0]) == 1, "$testPaths[0] is back");
$contents = ReadBinFileWide($testPaths[0]);
ok($contents eq "hello", "Contents are 'hello'");
AppendToBinFileWide($testPaths[0], " world");
$contents = ReadBinFileWide($testPaths[0]);
ok($contents eq "hello world", "Contents are 'hello world'");
AppendToExistingBinFileWide($testPaths[0], " again");
$contents = ReadBinFileWide($testPaths[0]);
ok($contents eq "hello world again", "Contents are 'hello world again'");
DeleteFileWide($testPaths[0]);
ok(!AppendToExistingBinFileWide($testPaths[1], "hello"), "no binary append if file does not exist");
ok(!FileOrDirExistsWide($testPaths[1]), "$testPaths[1] does not exist after attempted binary append");
ok(!FileOrDirExistsWide($testPaths[0]), "$testPaths[0] is gone yet again");

done_testing();
