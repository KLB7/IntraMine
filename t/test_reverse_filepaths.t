# test_reverse_filepaths.t: test reverse_filepaths.pm.

# prove "C:\perlprogs\mine\t\test_reverse_filepaths.t"

use strict;
use warnings;
use Test::More;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent(2)->child('libs')->stringify;
use win_wide_filepaths;
use reverse_filepaths;

my $ourPath = path($0)->absolute->parent();
$ourPath =~ s!\\!/!g;

# Make a small file holding full paths.
my $fullPathsFile = "$ourPath/fullpaths.out";
my $filePath = ActualPathIfTooDeep("$ourPath/intramine_main.pl", 0);
AppendToTextFileWide($fullPathsFile, "$filePath\tintramine_main.pl\n");
$filePath = ActualPathIfTooDeep("$ourPath/Documentation/glossary.txt", 1);
AppendToTextFileWide($fullPathsFile, "$filePath\tglossary.txt\n");

# Load up the full paths file, and make a hash of all partial paths for full paths.
ok(InitDirectoryFinder($fullPathsFile) == 2, "two paths in $fullPathsFile");

# Test that full paths can be retrieved from full and partial paths.
my $contextDir = $ourPath;
$contextDir =~ s!/[^/]+!!g;
$contextDir .= '/';
my $fullPath = FullPathInContextNS("intramine_main.pl", "");
ok($fullPath =~ m!^\w\:.+?/intramine_main.pl$!i, "full path for Main");
$fullPath = FullPathInContextNS("intramine_main.pl", $contextDir);
ok($fullPath =~ m!^\w\:.+?/intramine_main.pl$!i, "full path for Main in context '$contextDir'");

$fullPath = FullPathInContextNS("Documentation/glossary.txt", "");
ok($fullPath =~ m!^\w\:.+?/Documentation/glossary.txt$!i, "full path for glossary.txt");
$fullPath = FullPathInContextNS("documentation/Glossary.txt", "");
ok($fullPath =~ m!^\w\:.+?/Documentation/glossary.txt$!i, "case-insensitive full path for glossary.txt");
$fullPath = FullPathInContextNS("Documentation/glossary.txt", $contextDir);
ok($fullPath =~ m!^\w\:.+?/Documentation/glossary.txt$!i, "full path for glossary.txt in context '$contextDir'");

$fullPath = FullPathInContextTrimmed("<strong>intramine_main.pl", $contextDir);
ok($fullPath =~ m!^\w\:.+?/intramine_main.pl$!i, "full path for Main with HTML trimmed, in context '$contextDir'");

# Look for files that don't exist.
$fullPath = FullPathInContextNS("absolutelydoesnotexists.pl", "");
ok($fullPath eq '', "absolutelydoesnotexists.pl does not exist");
my $badContext = "C:/argle/bargle/goo/";
$fullPath = FullPathInContextNS("intramine_main.pl", $badContext);
ok($fullPath =~ m!^\w\:.+?/intramine_main.pl$!i, "full path for Main in bad context '$badContext'");

# Now a bad path with a good file name.
$fullPath = FullPathInContextNS("babble/noggle/intramine_main.pl", $badContext);
ok($fullPath eq '', "NO full path for babble/noggle/intramine_main.pl in bad context '$badContext'");

$filePath = lc($filePath);
ok(FullPathIsKnown($filePath), "FullPathIsKnown knowns lower case full path to glossary");
$filePath = uc($filePath);
ok(!FullPathIsKnown($filePath), "FullPathIsKnown requires proper case");

# Picking up the pace, make a second full paths file.
my %newPaths;
my $extraFilePath = "$ourPath/intramine_search.pl";
$newPaths{$extraFilePath} = "intramine_search.pl";
AddIncrementalNewPaths(\%newPaths);
SaveIncrementalFullPaths(\%newPaths);
LoadIncrementalDirectoryFinderLists($fullPathsFile);
$fullPath = FullPathInContextNS("intramine_search.pl", "");
ok($fullPath =~ m!^\w\:.+?/intramine_search.pl$!i, "full path for Search from incremental");
ConsolidateFullPathLists(1);
ReinitDirectoryFinder($fullPathsFile);
$fullPath = FullPathInContextNS("intramine_search.pl", "");
ok($fullPath =~ m!^\w\:.+?/intramine_search.pl$!i, "full path for Search ok after reinit");

# Clean up.
#DeleteFileWide($fullPathsFile);
DeleteFullPathListFiles($fullPathsFile);
ok(!(-f $fullPathsFile), "full paths file is gone");

done_testing();
