# reverse_filepaths.pm: FullPathInContextNS() below implements the "auto" part of "autolink."
# More specifically, FLASH links (see "Documentation/Gloss.html#Links").
# This is done using a reverse index %FullPathsForFileName, which for each file name lists
# all full paths that end in the file name.
# Given a file name or a partial path that ends in the file name
# eg file.txt or dir3/dr2/dr1/file.txt, FullPathInContextNS() can be called to determine the full
# path. Dirs are required if the file name is not unique and the "$contextDir" does not properly
# resolve the path.
#    Full path: c:\qtStuff\android\third_party\native_app_glue\android_native_app_glue.h
#    Example partial path:                     native_app_glue\android_native_app_glue.h
# FullPathInContextNS() receives two arguments:
#	$linkSpecifier: partial path for which full path is wanted, eg "main.cpp" or "catclicker/src/main.cpp".
#		Typically the source of the partial path is text in a document being viewed.
#	$contextDir: the directory holding the document being viewed, where the request originated, eg
#		"C:/projects/catclicker/docs", or "P:/project summaries". In both examples the instance
#		of main.cpp that's closest to the $contextDir will have its full path returned.
#		In the former case, with context dir "C:/projects/catclicker/docs", the returned full path
#		for "main.cpp" would almost certainly be C:/projects/catclicker/src/main.cpp.
#		In the latter case, with a context dir on the P: drive, it's anyone's
#		guess which instance of main.cpp would be selected, so the source there should use a
#		fuller path such as "catclicker/src/main.cpp" to help resolve which main.cpp is wanted.
#
# Usage: first call InitDirectoryFinder(). For an example see
# intramine_linker.pl#callbackInitDirectoryFinder().
# The file holding a list of files and full paths for them must of course exist. This is
# built when indexing files with Elasticsearch - see elastic_indexer.pl around line 151,
# where there's a call back to AddIncrementalNewPaths(), defined here.
# Then to get the best matching full path for a partial path (which could be a full path) call
# FullPathInContextNS(): see intramine_linker.pl#FullPathForPartial() for a use.
# (FullPathInContextTrimmed() is similar, the "Trimmed" version deals with nuisance HTML).
# For more details see the comment above BestMatchingFullPath() and following subs below, and
# Documentation/Linker.html.
#
# And autolinking_demo.pl at the top level of the IntraMine folder isolates the functions
# in this file to show how they work on a small set of paths, reporting which function
# found a good match. If you want to implement FLASH links, that's a good place to start.

package reverse_filepaths;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use utf8;
use FileHandle;
use File::Basename;
use DBM::Deep;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
# For syntax check only: use lib path($0)->absolute->parent->parent->child('libs')->stringify;
#use lib ".";
use common;
use win_wide_filepaths;


{ ##### Directory list
my $FullPathListPath;		# For fullpaths.out, typ. CVal('FILEWATCHERDIRECTORY') . CVal('FULL_PATH_LIST_NAME')
my %FileNameForFullPath; 	# as saved in /fullpaths.out: $FileNameForFullPath{c:/dir1/dir2/dir3/file.txt} = 'file.txt';
my %FullPathsForFileName; # Eg $FullPathsForFileName{'main.cpp'} = 'c:/proj1/main.cpp|c:/proj2/main.cpp';
my %FullDirectoryPathsForDirName; # Eg $FullDirectoryPathsForDirName{'docs'} = '|c:/proj1/docs|c:/p2/docs|';
my %LastDirForFullDirPath; # $LastDirForFullDirPath{'c:/proj1/docs'} = 'docs';

# For tracking deleted files.
my $DeletesDbPath;
my $DeletesDB;

# Load %IntKeysForPartialPath, and build %IntKeysForPartialPath from it.
sub InitDirectoryFinder {
	my ($filePath) = @_; # typ. CVal('FILEWATCHERDIRECTORY') . CVal('FULL_PATH_LIST_NAME')
	my $pathCount = InitFullPathList($filePath);
	BuildPartialPathList(\%FileNameForFullPath);
	LoadIncrementalDirectoryFinderLists($filePath);
	LoadAndRemoveDeletesFromHashes($filePath);
	
	return($pathCount);
	}

sub ReinitDirectoryFinder {
	my ($filePath) = @_; # typ. CVal('FILEWATCHERDIRECTORY') . CVal('FULL_PATH_LIST_NAME')
	
	# Empty out %FileNameForFullPath etc.
	%FileNameForFullPath = ();
	%FullPathsForFileName = ();
	%FullDirectoryPathsForDirName = ();
	%LastDirForFullDirPath = ();
	
	return(InitDirectoryFinder($filePath));
	}

# Load %FileNameForFullPath.
# Eg $FileNameForFullPath{C:/dir1/dir2/dir3/file.txt} = 'file.txt';
sub InitFullPathList {
	my ($filePath) = @_; # typ. CVal('FILEWATCHERDIRECTORY') . CVal('FULL_PATH_LIST_NAME')
	$FullPathListPath = $filePath;
	
	my $pathCount = LC_LoadKeyTabValueHashFromFile(\%FileNameForFullPath, $FullPathListPath, "file names for full paths");
	if (!$pathCount)
		{
		print("WARNING (will continue) in reverse_filepaths.pm#InitFullPathList(), |$FullPathListPath| did not load. First run maybe.\n");
		}
		return($pathCount);
	}

# From entries in %FileNameForFullPath build a "reverse" hash %FullPathsForFileName
# and also %FullDirectoryPathsForDirName for directory matching.
sub BuildFullPathsForFileName {
	my ($fileNameForFullPathH) = @_;
	
	keys %$fileNameForFullPathH; # reset iterator
	while (my ($fullPath, $fileName) = each %$fileNameForFullPathH)
		{
		if (defined($FullPathsForFileName{$fileName}))
			{
			$FullPathsForFileName{$fileName} .= "|$fullPath";
			}
		else
			{
			$FullPathsForFileName{$fileName} = $fullPath;
			}
		AddToDirectoryPaths($fullPath);
		}
	}

# From the full file path in $fullPath, build up dir paths
# progressively from left to right and add entries to both
# dir hashes. All dir paths end in a '/'.
sub AddToDirectoryPaths {
	my ($fullPath) = @_;
	# Remove the file name and last '/'.
	if (index($fullPath, "/") >= 0)
		{
		my $lastSlashPos = rindex($fullPath, "/");
		$fullPath = substr($fullPath, 0, $lastSlashPos);
		}
	
	my @dirNames = split(/\//, $fullPath);
	# Add back the last slash.
	$fullPath = $fullPath . '/';
	
	my $partialDirPath = '';
	for (my $i = 0; $i < @dirNames; ++$i)
		{
		$partialDirPath .= $dirNames[$i] . '/';
		if (!defined($LastDirForFullDirPath{$partialDirPath}))
			{
			$LastDirForFullDirPath{$partialDirPath} = $dirNames[$i];
			if (defined($FullDirectoryPathsForDirName{$dirNames[$i]}))
				{
				$FullDirectoryPathsForDirName{$dirNames[$i]} .= "$partialDirPath|";
				}
			else
				{
				$FullDirectoryPathsForDirName{$dirNames[$i]} = "|$partialDirPath|";
				}
			}
		}
	}

# A bit obsolete, just call BuildFullPathsForFileName() above.
sub BuildPartialPathList {
	my ($fileNameForFullPathH) = @_;
	
	BuildFullPathsForFileName($fileNameForFullPathH);
	}

# Load additional fullpaths2.out etc to %FileNameForFullPath.
sub LoadIncrementalFullPathLists {
	my ($filePath) = @_; # typ. CVal('FILEWATCHERDIRECTORY') . CVal('FULL_PATH_LIST_NAME')
	$filePath =~ m!^(.+?)(\.\w+)$!;
	my $base = $1;
	my $ext = $2;
	my $num = 2;
	my $fragPath = $base . $num . $ext;
	while (-f $fragPath)
		{
		my %rawFileNameForFullPath;
		my $pathCount = LC_LoadKeyTabValueHashFromFile(\%rawFileNameForFullPath, $fragPath, "more file names for full paths");
		if ($pathCount)
			{
			my %newFileNameForFullPath;
			keys %rawFileNameForFullPath;
			while (my ($path, $fileName) = each %rawFileNameForFullPath)
				{
				if (!FullPathIsKnown($path))
					{
					$newFileNameForFullPath{$path} = $rawFileNameForFullPath{$path};
					}
				}
			keys %newFileNameForFullPath;
			while (my ($path, $fileName) = each %newFileNameForFullPath)
				{
				$FileNameForFullPath{$path} = $newFileNameForFullPath{$path};
				}
			}
		++$num;
		$fragPath = $base . $num . $ext;
		}
	}

# Load additional fullpaths2.out etc to %FileNameForFullPath, create new partial path entries too.
sub LoadIncrementalDirectoryFinderLists {
	my ($filePath) = @_; # typ. CVal('FILEWATCHERDIRECTORY') . CVal('FULL_PATH_LIST_NAME')
	$filePath =~ m!^(.+?)(\.\w+)$!;
	my $base = $1;
	my $ext = $2;
	my $num = 2;
	my $fragPath = $base . $num . $ext;
	while (-f $fragPath)
		{
		my %rawFileNameForFullPath;
		my $pathCount = LC_LoadKeyTabValueHashFromFile(\%rawFileNameForFullPath, $fragPath, "more file names for full paths");
		if ($pathCount)
			{
			my %newFileNameForFullPath;
			keys %rawFileNameForFullPath;

			# Prepare to add files that aren't currently being tracked.
			while (my ($path, $fileName) = each %rawFileNameForFullPath)
				{
				if (!FullPathIsKnown($path))
					{
					$newFileNameForFullPath{$path} = $rawFileNameForFullPath{$path};
					}
				}
				
			# Track the genuinely new files.
			my $numNewEntries = keys %newFileNameForFullPath;
			if ($numNewEntries)
				{
				keys %newFileNameForFullPath;
				while (my ($path, $fileName) = each %newFileNameForFullPath)
					{
					$FileNameForFullPath{$path} = $newFileNameForFullPath{$path};
					}
				BuildPartialPathList(\%newFileNameForFullPath);
				}
			}
		++$num;
		$fragPath = $base . $num . $ext;
		}
	}

# Add to %FileNameForFullPath.
sub AddIncrementalNewPaths {
	my ($fileNameForFullPathH) = @_;
	my %newFileNameForFullPath;
	
	keys %$fileNameForFullPathH;
	while (my ($path, $fileName) = each %$fileNameForFullPathH)
		{
		if (!FullPathIsKnown($path))
			{
			$newFileNameForFullPath{$path} = $fileNameForFullPathH->{$path};
			}
		}
	
	my $numNewPaths = keys %newFileNameForFullPath;
	if ($numNewPaths)
		{
		keys %newFileNameForFullPath;
		while (my ($path, $fileName) = each %newFileNameForFullPath)
			{
			$FileNameForFullPath{$path} = $newFileNameForFullPath{$path};
			AddToDirectoryPaths($path);
			}
		}
	}

# Path to the deletes.db little database used to recorded full paths of deleted files.
sub DeletesDbPath {
	my $scriptFullPath = $0; # path of calling program
	my $scriptDirTS = DirectoryFromPathTS($scriptFullPath);
	my $path = $scriptDirTS . 'data/deletes.db';
	return($path);
	}

sub InitDeletesDB {
	$DeletesDbPath = DeletesDbPath();
	$DeletesDB = DBM::Deep->new($DeletesDbPath);
	}

# Remove entries from reverse_filepaths.pm %FileNameForFullPath and %FullPathsForFileName.
# Add paths to $DeletesDB so they'll be remembered for restart.
sub RemoveDeletes {
	my ($pathsOfDeletedFilesH) = @_;

	RemoveDeletesFromHashes($pathsOfDeletedFilesH);

	RememberDeletedPaths($pathsOfDeletedFilesH);
	}

sub RemoveDeletesFromHashes {
	my ($pathsOfDeletedFilesH) = @_;

	foreach my $fullPath (keys %$pathsOfDeletedFilesH)
		{
		DeleteFullPath($fullPath); #  reverse_filepaths.pm#DeleteFullPath()
		}
	}

# Delete $path from %FileNameForFullPath and %FullPathsForFileName.
sub DeleteFullPath {
	my ($path) = @_;
	$path = lc($path);

	delete $FileNameForFullPath{$path};

	my $fileName = FileNameFromPath($path);
	my $allpaths = GetAllPathsForFileName($fileName);
	my @paths;
	if ($allpaths =~ m!\|!) # more than one candidate full path
		{
		@paths = split(/\|/, $allpaths);
		}
	else
		{
		push @paths, $allpaths;
		}

	my @remainingPaths;
	for (my $i = 0; $i < @paths; ++$i)
		{
		if ($paths[$i] ne $path)
			{
			push @remainingPaths, $paths[$i];
			}
		}

	my $numPathsLeft = @remainingPaths;
	if ($numPathsLeft)
		{
		if ($numPathsLeft > 1)
			{
			$FullPathsForFileName{$fileName} = join('|', @remainingPaths);
			}
		else
			{
			$FullPathsForFileName{$fileName} = $remainingPaths[0];
			}
		}
	else
		{
		delete $FullPathsForFileName{$path};
		}
	}

sub RememberDeletedPaths {
	my ($pathsOfDeletedFilesH, $deletedFilesPath) = @_;

	foreach my $key (sort(keys %{$pathsOfDeletedFilesH}))
		{
		$key = lc($key);
		$DeletesDB->{$key} = 1;
		}
	}

sub LoadDeletedPaths {
	my ($pathsOfDeletedFilesH) = @_;
	%{$pathsOfDeletedFilesH} = ();

	while (my ($key, $value) = each %$DeletesDB)
		{
		$pathsOfDeletedFilesH->{$key} = $value;
		}
	}

sub LoadAndRemoveDeletesFromHashes {
	my %pathsOfDeletedFiles;
	LoadDeletedPaths(\%pathsOfDeletedFiles);
	RemoveDeletesFromHashes(\%pathsOfDeletedFiles);

	# TEST ONLY
	# my $numPathEntries = keys %pathsOfDeletedFiles;
	# my $tipPaths = $FullPathsForFileName{'tooltip.js'};
	# print("$numPathEntries paths, tip paths: |$tipPaths|\n");
}

# Remove $path from deletes db if file was re-created.
sub RemoveNewFilesFromDeletes {
	my ($pathsOfCreatedFilesH) = @_;

	foreach my $key (sort(keys %{$pathsOfCreatedFilesH}))
		{
		$key = lc($key);
		$DeletesDB->delete($key);
		}
	}

# Update all paths in %FileNameForFullPath after a folder rename. Follow with a call
# to ConsolidateFullPathLists() to make it permanent.
# All paths are lowercase and use forward slashes.
sub UpdatePathsForFolderRenames {
	my ($numRenames, $renamedFolderPathsA, $oldFolderPathA, $newPathForOldPathH) = @_;
	my @oldFolderPathCopy = @$oldFolderPathA;
	my @renamedFolderPathsCopy = @$renamedFolderPathsA;
	my %tempFileNameForFullPath = %FileNameForFullPath;
		
	for (my $i = 0; $i < @oldFolderPathCopy; ++$i)
		{
		$oldFolderPathCopy[$i] = lc($oldFolderPathCopy[$i]);
		}
	for (my $i = 0; $i < @renamedFolderPathsCopy; ++$i)
		{
		$renamedFolderPathsCopy[$i] = lc($renamedFolderPathsCopy[$i]);
		}
	
	if ($numRenames == 1)
		{
		my $oldFolderPath = $oldFolderPathCopy[0];
		my $newFolderPath = $renamedFolderPathsCopy[0];		
		keys %FileNameForFullPath;
		while (my ($path, $fileName) = each %FileNameForFullPath)
			{
			if (index($path, $oldFolderPath) == 0)
				{
				my $newPath = $newFolderPath . substr($path, length($oldFolderPath));
				my $oldEntry = $FileNameForFullPath{$path};
				delete($tempFileNameForFullPath{$path});
				$tempFileNameForFullPath{$newPath} = $oldEntry;
				$newPathForOldPathH->{$path} = $newPath;
				}
			}
		}
	else
		{
		keys %FileNameForFullPath;
		while (my ($path, $fileName) = each %FileNameForFullPath)
			{
			# If old path agrees with left part of %FileNameForFullPath, kill the old entry and
			# replace it with new one. We spin off a new hash to avoid confusing the loop.
			for (my $i = 0; $i < $numRenames; ++$i)
				{
				if (index($path, $oldFolderPathCopy[$i]) == 0)
					{
					my $newPath = $renamedFolderPathsCopy[$i] . substr($path, length($oldFolderPathCopy[$i]));
					my $oldEntry = $FileNameForFullPath{$path};
					$newPathForOldPathH->{$path} = $newPath;
					delete($tempFileNameForFullPath{$path});
					$tempFileNameForFullPath{$newPath} = $oldEntry;
					last;
					}
				}
			}
		}
	%FileNameForFullPath = %tempFileNameForFullPath;
	}

sub SaveIncrementalFullPaths {
	my ($fileNameForFullPathH) = @_;
	$FullPathListPath =~ m!^(.+?)(\.\w+)$!;
	my $base = $1;
	my $ext = $2;
	my $num = 2;
	my $fragPath = $base . $num . $ext;
	my $fileH = FileHandle->new(">> $fragPath") or return("File Error, could not open |$fragPath|!");
	binmode($fileH, ":utf8");
    foreach my $key (sort(keys %$fileNameForFullPathH))
        {
        print $fileH "$key\t$fileNameForFullPathH->{$key}\n";
        }
    close $fileH;
	}

# Every now and then, consolidate fullpaths.out and fullpaths2.out, mainly to shrink
# the size of fullpaths2, which is completely loaded by intramine_fileserver.pl
# whenever a new file is seen. This can take a few seconds. This is a transparent change when
# called by intramine_filewatcher.pl, no need to notify anyone or restart.
# Call InitDirectoryFinder() or InitFullPathList() before this. And LoadIncrementalFullPathLists()
# or dir equiv. And ensure all paths are loaded. Called in intramine_filewatcher.pl.
# If fullpaths2.out does not exist, there is nothing to consolidate.
sub ConsolidateFullPathLists {
	my ($forceConsolidation) = @_;
	
	$FullPathListPath =~ m!^(.+?)(\.\w+)$!;
	my $base = $1;
	my $ext = $2;
	my $num = 2;
	my $fragPath = $base . $num . $ext;
	my $fileWatcherDir = DirectoryFromPathTS($FullPathListPath);

	if ( $forceConsolidation || (-f $fragPath || !(-f $FullPathListPath)) )
		{
		unlink($FullPathListPath);
		unlink($fragPath);

		unlink($DeletesDbPath);
		$DeletesDB = DBM::Deep->new($DeletesDbPath);

		my $fileH = FileHandle->new("> $FullPathListPath") or return("File Error, could not open |$FullPathListPath|!");
		binmode($fileH, ":utf8");
	    foreach my $key (sort(keys %FileNameForFullPath))
	        {
	        print $fileH "$key\t$FileNameForFullPath{$key}\n";
	        }
	    close $fileH;
		}
	}

# Return pipe-separated string holding all full paths for $fileName.
sub GetAllPathsForFileName {
	my ($fileName) = @_;
	my $result = defined($FullPathsForFileName{$fileName}) ? $FullPathsForFileName{$fileName} : '';
	return($result);
	}

# The main call for autolinking.
# Return full path given partial path and context directory.
# $linkSpecifier is 'normed' here, as opposed to
# FullPathInContextTrimmed() which expects only forward slashes
# and no starting slash. UNLESS we see a leading double-slash, which happens
# in a //host-name/share... link.
# Used in intramine_linker.pl#AddWebAndFileLinksToLine() etc.
# See notes below for BestMatchingFullPath().
sub FullPathInContextNS {
	my ($linkSpecifier, $contextDir) = @_;
	
	$linkSpecifier = lc($linkSpecifier);
	$linkSpecifier =~ s!\\!/!g;
	
	if ($linkSpecifier !~ m!^//!)
		{
		$linkSpecifier =~ s!^/!!;
		}
	
	return(BestMatchingFullPath($linkSpecifier, $contextDir));
	}

# Full path, given a partial path and context directory.
# For linking with perhaps nuisance HTML prepended. Used in intramine_linker.pl#ModuleLink().
# $linkSpecifier: for success, one of:
# file.txt
# dir1/file.txt
# dir2/dir1/file.txt
# dir3/dir2/dir1/file.txt
# etc
# or full path to file.txt, C:/dirN/.../dir1/file.txt
# See notes below for BestMatchingFullPath().
sub FullPathInContextTrimmed {
	my ($linkSpecifier, $contextDir) = @_;
	$linkSpecifier = lc($linkSpecifier);
	
	my $result = BestMatchingFullPath($linkSpecifier, $contextDir);
	if ($result ne '')
		{
		return($result);
		}
	
	# Try again, trim any leading HTML tags or spaces etc.
	# Eg &nbsp;&nbsp;&bull;&nbsp;<strong>bootstrap.min.css
	# NOTE this changes $linkSpecifier for all below.
	$linkSpecifier =~ s!^.+?\;([^;]+)$!$1!; # leading spaces or bullets etc
	$linkSpecifier =~ s!^\<\w+\>(.+)$!$1!; # leading <strong> or <em>
	$result = BestMatchingFullPath($linkSpecifier, $contextDir);
	if ($result ne '')
		{
		return($result);
		}
	
	# No luck
	return('');	
	}

# BestMatchingFullPath
# -> $linkSpecifier: in a real program, this would be a string of text
#  that ends with all or part of a file name, and a file extension. The
#  challenge is to see if the string corresponds to a "link specifier"
#  that can be matched to a known full path. A link specifier consists of:
#  (optional) drive specifier followed by (optional) directory names in any order
#  followed by a file name with extension. For example, a link specifier for
#  c:/projects/project51/src/main.cpp
#  could be any of
#  main.cpp, c:/main.cpp, src/main.cpp, project51/main.cpp, src/project51/main.cpp etc.
#  And the $linkSpecifier could include extra words on the left end, such as
#  "as we see in src/main.cpp" (in which case the $linkSpecifier would be rejected).
#  For more examples, see "Documentation/Linker.txt"
# -> $contextDir: path to the directory of file where $linkSpecifier is typed,
#    eg c:/projects/project51/docs/ or P:/project51/notes/.
#  A full path's distance from the $contextDir is measured by how many hops
# up and down it takes to go from the deepest directory in the full path
# to the $contextDir.
# <- full path that best matches the partial path in context, or ''.
# We do five checks:
# 1. Is $linkSpecifier (pp) a full path? Return  it.
# 2. Is there some overlap on the left between some full path and $contextDir? Return the
#    full path that has best overlap, "closest" to the context directory on a tie.
# 3. Does pp match fully with the right side of a full path, ignoring context? Return the
#    full path that has best overlap.
# 4. Do pp folder names all match those in a full path, regardless of position, with some overlap
# on the left between full path and context dir? Return the full path that has best overlap,
# "closest" to the context directory on a tie.
# 5. Do pp folder names all match those in a full path, regardless of position, ignoring context?
# Return the full path with best overlap.
# If all of the above checks fail, return ''.
# Note where the supplied $linkSpecifier is ambiguous, the wrong path can be returned.
#
# If $linkSpecifier contains ../ or ../../ , I can't think of a scenario where that
# produces a different result from the one implemented below, so leading ../'s
# should be stripped off before getting here. EXCEPT for double leading /'s, which
# signal a potential //host-name/share-name/ link mention.
sub BestMatchingFullPath {
	my ($linkSpecifier, $contextDir) = @_;
	my $result = '';

	# 1.
	# Allow any full path, provided either we have a record of it or the file is on disk.
	if ($linkSpecifier =~ m!^\w:/!)
		{
		if (FullPathIsKnown($linkSpecifier) || FileOrDirExistsWide($linkSpecifier) == 1)
			{
			$result = $linkSpecifier;
			}
		}
	# For a //host/share UNC, check for a record of the
	# link text in our %FileNameForFullPath hash. No checking the drive.
	elsif ($linkSpecifier =~ m!^//!)
		{
		if (FullPathIsKnown($linkSpecifier))
			{
			$result = $linkSpecifier;
			}
		}
	
	if ($result eq '') # Check for a link specifier, possibly incomplete or scrambled.
		{
		my $fileName = basename($linkSpecifier);

		if (defined($FullPathsForFileName{$fileName}))
			{
			my $allpaths = $FullPathsForFileName{$fileName};
			my @paths;
			if ($allpaths =~ m!\|!) # more than one candidate full path
				{
				@paths = split(/\|/, $allpaths);
				}
			else
				{
				push @paths, $allpaths;
				}
			
			my $bestPath = "";
			# 2., 3.
			# First check for a full path that matches $linkSpecifier fully, preferring
			# some match on the left between full path and context directory.
			if ( ($bestPath = ExactPathInContext($linkSpecifier, $contextDir, \@paths)) ne ""
			  || ($bestPath = ExactPathNoContext($linkSpecifier, \@paths)) ne "" )
				{
				$result = $bestPath;
				}
			# 4., 5.
			# Relax requirements if no match yet, require full match between full path
			# and $linkSpecifier, but the directory names in $linkSpecifier don't have to
			# be complete, some can be omitted. All directory names included in
			# $linkSpecifier must be found in a full path to count as a match.
			if ($result eq "")
				{
				my @partialPathParts = split(/\//, $linkSpecifier);
				pop(@partialPathParts); # Remove file name (last entry).
				# Tack some forward slashes back on for accurate matching with index().
				for (my $i = 0; $i < @partialPathParts; ++$i)
					{
					if (index($partialPathParts[$i], ':') > 0) # drive letter
						{
						$partialPathParts[$i] .= '/';
						}
					else
						{
						$partialPathParts[$i] = '/' . $partialPathParts[$i] . '/';
						}
					}
				
				if ( ($bestPath = RelaxedPathInContext($linkSpecifier, $contextDir, \@paths, \@partialPathParts)) ne ""
				  || ($bestPath = RelaxedPathNoContext(\@paths, \@partialPathParts)) ne "" )
					{
					$result = $bestPath;
					}
				}
			} # file name is associated with at least one known full path
		} # partial path
		
	return($result);
	}

# -> $linkSpecifier, $contextDir: see comment above for BestMatchingFullPath().
# -> $pathsA: array of full paths where file name in full path matches file name in $linkSpecifier.
# <- returns full path of best match, or "".
# "Exact" means a candidate full path in $pathsA must match all of the $linkSpecifier,
# file name and directory names and drive name if any in sequence, and no omissions.
# "InContext" means a candidate full path must overlap to some extent with the
# context directory $contextDir on the left (so at least the drive letters must agree).
# For all full paths, if full path contains all of $linkSpecifier it's a match. Among all matches,
# pick one where full path overlaps most on the left with $contextDir. If there's a tie,
# pick the path that's the fewest number of directory hops from the contextDir. If there's
# still a tie, pick the shortest full path. Return index of best full path (-1 if no match).
#
# Example of a good match:
# Link specifier:                             src/main.cpp
# Path being tested:    c:/projects/project51/src/main.cpp
# Context directory:    c:/projects/project51/docs/
# Context/path overlap: c:/projects/project51/
# All of the link specifier matches the right end of the path being tested exactly,
# and the context directory agrees with the path except for the rightmost directory.
sub ExactPathInContext {
	my ($linkSpecifier, $contextDir, $pathsA) = @_;
	my $linkSpecifierLength = length($linkSpecifier);
	my $numPaths = @$pathsA;
	my $bestScore = 0;			# context/full path overlap, higher is better
	my $bestSlashScore = 999; 	# Slash count in leftoverPath, lower is better
	my $bestIdx = -1;
	
	for (my $i = 0; $i < $numPaths; ++$i)
		{
		my $testPath = $pathsA->[$i];
		my $matchPos;
		
		if (($matchPos = index($testPath, $linkSpecifier)) > 0)
			{
			my $testLength = length($testPath);
			# We want a full match on the $linkSpecifier within $testPath, and to avoid a match
			# against a partial directory name we need the char preceding the match to be a slash.
			# (Eg avoid a match of test/file.txt against c:/stuff/bigtest/file.txt)
			if ($testLength == $matchPos + $linkSpecifierLength && substr($testPath, $matchPos-1, 1) eq '/')
				{
				my $currentScore = LeftOverlapLength($contextDir, $testPath);
				
				if ($bestScore < $currentScore)
					{
					my $leftoverPath = substr($testPath, $currentScore);
					my $currentSlashScore = $leftoverPath =~ tr!/!!;
					$bestSlashScore = $currentSlashScore;
					$bestScore = $currentScore;
					$bestIdx = $i;
					}
				elsif ($bestScore > 0 && $bestScore == $currentScore)
					{
					my $leftoverPath = substr($testPath, $currentScore);
					my $currentSlashScore = $leftoverPath =~ tr!/!!; # Count directory slashes in $leftoverPath
					# Fewer slashes means $testPath is closer to context directory.
					if ($bestSlashScore > $currentSlashScore)
						{
						$bestSlashScore = $currentSlashScore;
						$bestIdx = $i;
						}
					elsif ($bestSlashScore == $currentSlashScore) # Prefer shorter path
						{
						if ($testLength < length($pathsA->[$bestIdx]))
							{
							$bestIdx = $i;
							}
						}
					}
				}
			}
		}
	
	my $result = "";
	if ($bestIdx >= 0)
		{
		$result = $pathsA->[$bestIdx];
		}
	
	return($result);
	}

# -> $linkSpecifier, $contextDir: see comment above for BestMatchingFullPath().
# -> $pathsA: array of full paths where file name in full path matches file name in $linkSpecifier.
# -> $linkSpecifierPartsA: array holding folder names in $linkSpecifier and drive if any
#    (file name is excluded).
# <- returns full path of best match, or "".
# "Relaxed" means all the directory names and drive letter (if supplied)
# in $linkSpecifier must match those in a candidate full path, but they can be
# in any order and not all directory names in the candidate full path need to be present
# in the $linkSpecifier.
# "InContext" means a candidate full path must overlap to some extent with the
# context directory $contextDir on the left (so at least the drive letters must agree).
# For all full paths, if full path contains all of the directory names mentioned in $linkSpecifier
# regardless of position or order (drive too if provided) then it's a match. Among all matches,
# pick one where full path overlaps most on the left with $contextDir. If there's a tie,
# pick the path that's the fewest number of directory hops from the $contextDir. If there's
# still a tie, pick the shortest full path. Return index of best full path (-1 if no match).
#
# Example of a good match:
# Link specifier:                             project51/main.cpp
# Path being tested:    c:/projects/project51/src/main.cpp
# Context directory:    c:/projects/project51/docs/
# Context/path overlap: c:/projects/project51/
# The directory and file name of the link specifier match parts of the path,
# and the context directory agrees with the path except for the rightmost directory.
sub RelaxedPathInContext {
	my ($linkSpecifier, $contextDir, $pathsA, $partialPathPartsA) = @_;
	my $numPaths = @$pathsA;
	my $bestScore = 0;
	my $bestSlashScore = 999;
	my $bestIdx = -1;
	
	for (my $i = 0; $i < $numPaths; ++$i)
		{
		my $testPath = $pathsA->[$i];
		
		if (AllPartialPartsAreInTestPath($partialPathPartsA, $testPath))
			{
			my $currentScore = LeftOverlapLength($contextDir, $testPath);
			if ($bestScore < $currentScore)
				{
				my $leftoverPath = substr($testPath, $currentScore);
				my $currentSlashScore = $leftoverPath =~ tr!/!!;
				$bestSlashScore = $currentSlashScore;
				$bestScore = $currentScore;
				$bestIdx = $i;
				}
			elsif ($bestScore > 0 && $bestScore == $currentScore)
				{
				my $leftoverPath = substr($testPath, $currentScore);
				my $currentSlashScore = $leftoverPath =~ tr!/!!; # Count directory slashes in $leftoverPath
				# Fewer slashes means $testPath is closer to context directory.
				if ($bestSlashScore > $currentSlashScore)
					{
					$bestSlashScore = $currentSlashScore;
					$bestIdx = $i;
					}
				elsif ($bestSlashScore == $currentSlashScore) # Prefer shorter path
					{
					my $testLength = length($testPath);
					if ($testLength < length($pathsA->[$bestIdx]))
						{
						$bestIdx = $i;
						}
					}
				}
			}
		}
	
	my $result = "";
	if ($bestIdx >= 0)
		{
		$result = $pathsA->[$bestIdx];
		}
	
	return($result);
	}

# -> $linkSpecifier: file name optionally preceded by one or more directory names, without skips
#    eg any of main.cpp, src/main.cpp, project51/src/main.cpp, P:/project51/src/main.cpp.
# -> $pathsA: array of full paths where file name in full path matches file name in $linkSpecifier.
# <- returns full path of best match, or "".
# "Exact" means a candidate full path in $pathsA must match all of the $linkSpecifier,
# file name and directory names and drive name if any in sequence, and no omissions.
# "NoContext" means there is no check that a candidate full path is near a context directory.
# For all full paths, if full path contains all of $linkSpecifier return its index.
# On a tie, prefer the shallowest path (fewest directories).
#
# Example of a good match:
# Link specifier:                             src/main.cpp
# Path being tested:    c:/projects/project51/src/main.cpp
# (No context directory)
# There is a match between the link specifier and the right side of the path.
# However, there may be other matches that do as well, such as
# c:/projects/project999/src/main.cpp,
# so it's a good match but using project51/main.cpp would be better.
# (That would be a good match in RelaxedPathNoContext)
sub ExactPathNoContext {
	my ($linkSpecifier, $pathsA) = @_;
	my $linkSpecifierLength = length($linkSpecifier);
	my $numPaths = @$pathsA;
	my $bestSlashScore = 999;
	my $bestIdx = -1;
	
	for (my $i = 0; $i < $numPaths; ++$i)
		{
		my $testPath = $pathsA->[$i];
		my $matchPos;
		if (($matchPos = index($testPath, $linkSpecifier)) > 0)
			{
			my $testLength = length($testPath);
			if ($testLength == $matchPos + $linkSpecifierLength && substr($testPath, $matchPos-1, 1) eq '/')
				{
				my $currentSlashScore = $testPath =~ tr!/!!;
				if ($bestSlashScore > $currentSlashScore)
					{
					$bestSlashScore = $currentSlashScore;
					$bestIdx = $i;
					}
				}
			}
		}
	
	my $result = "";
	if ($bestIdx >= 0)
		{
		$result = $pathsA->[$bestIdx];
		}
	
	return($result);
	}

# -> $pathsA: array of full paths where file name in full path matches file name in $linkSpecifier.
# -> $linkSpecifierPartsA: array holding folder names in $linkSpecifier and drive if any
#    (file name is excluded).
# <- returns full path of best match, or "".
# "Relaxed" means all the directory names and drive letter (if supplied)
# in $linkSpecifier must match those in a candidate full path, but they can be
# in any order and not all directory names in the candidate full path need to be present
# in the $linkSpecifier.
# "NoContext" means there is no check that a candidate full path is near a context directory.
# For all full paths, if full path contains all of the subfolders mentioned in $linkSpecifier
# regardless of position or order (drive too if provided) then return its index.
# On a tie, prefer the shallowest path (fewest directories).
#
# Example of a good match:
# Link specifier:                             project51/main.cpp
# Path being tested:    c:/projects/project51/src/main.cpp
# (No context directory)
# The directory and file name of the link specifier match parts of the path.
# As long as there's no other project51 directory with a main.cpp,
# or second main.cpp in the project51 directory, this will be the best match.
sub RelaxedPathNoContext {
	my ($pathsA, $partialPathPartsA) = @_;
	my $numPaths = @$pathsA;
	my $bestSlashScore = 999;
	my $bestIdx = -1;

	for (my $i = 0; $i < $numPaths; ++$i)
		{
		my $testPath = $pathsA->[$i];
		if (AllPartialPartsAreInTestPath($partialPathPartsA, $testPath))
			{
			my $currentSlashScore = $testPath =~ tr!/!!;
			if ($bestSlashScore > $currentSlashScore)
				{
				$bestSlashScore = $currentSlashScore;
				$bestIdx = $i;
				}
			}
		}
		
	my $result = "";
	if ($bestIdx >= 0)
		{
		$result = $pathsA->[$bestIdx];
		}
	
	return($result);
	}

# -> $partialPathPartsA: a list of /directory names/ in the target specifier
#    (eg for test/esindex/cmAutoLink.js the list would be "/test/", "/esindex/").
sub AllPartialPartsAreInTestPath {
	my ($partialPathPartsA, $testPath) = @_;
	my $result = 1;
	
	for (my $i = 0; $i < @$partialPathPartsA; ++$i)
		{
		if (index($testPath, $partialPathPartsA->[$i]) < 0)
			{
			$result = 0;
			last;
			}
		}
	
	return($result);
	}

# Requires $fullPath all lower case, with forward slashes.
sub FullPathIsKnown {
	my ($fullPath) = @_;
	my $result = (defined($FileNameForFullPath{$fullPath})) ? 1: 0;

	return($result);
	}

# Return 1 if directory path in $fullDir is recognized.
# $fullDir should start with a drive letter and be complete
# with dirs in correct order, using '/' only.
sub FullDirPathIsKnown {
	my ($fullDir) = @_;
	# Put '/' on end of $fullDir if missing: all entries in
	# %LastDirForFullDirPath end in '/'.
	my $lastSlashPos = rindex($fullDir, '/');
	if ($lastSlashPos != length($fullDir) - 1)
		{
		$fullDir .= '/';
		}
	my $result = (defined($LastDirForFullDirPath{$fullDir})) ? 1: 0;

	return($result);	
	}

# Much like BestMatchingFullPath above, but for directory paths.
# Requires $linkSpecifier "normalized": no leading or trailing slash,
# only forward slashes, lowercase.
sub BestMatchingFullDirectoryPath {
	my ($linkSpecifier, $contextDir) = @_;
	my $result = '';
	
	# 1.
	# Allow any full dir path, provided either we have a record of it or the file is on disk.
	if ($linkSpecifier =~ m!^\w:/!)
		{
		if (FullDirPathIsKnown($linkSpecifier) || FileOrDirExistsWide($linkSpecifier) == 2)
			{
			$result = $linkSpecifier;
			}
		}
	# For a //host/share UNC, check for a record of the
	# link text in our %LastDirForFullDirPath. No checking the drive.
	elsif ($linkSpecifier =~ m!^//!)
		{
		if (FullDirPathIsKnown($linkSpecifier))
			{
			$result = $linkSpecifier;
			}
		}
	
	if ($result eq '') # Check for a link specifier, possibly incomplete or scrambled.
		{
		# Pull last dir from a $linkSpecifier:
		my $bottomDir = '';
		my $lastSlashPos = rindex($linkSpecifier, "/");
		if ($lastSlashPos > 0)
			{
			$bottomDir = substr($linkSpecifier, $lastSlashPos + 1);
			}
		else
			{
			$bottomDir = $linkSpecifier;
			}
		
		if (defined($FullDirectoryPathsForDirName{$bottomDir}))
			{
			my $allpaths = $FullDirectoryPathsForDirName{$bottomDir};
			my @paths;
			# Remove leading and trailing pipes.
			$allpaths = substr($allpaths, 1);
			$allpaths = substr($allpaths, 0, -1);
			if ($allpaths =~ m!\|!) # more than one candidate full path
				{
				@paths = split(/\|/, $allpaths);
				}
			else
				{
				push @paths, $allpaths;
				}
			
			my $bestPath = "";
			# 2., 3.
			# First check for a full path that matches $linkSpecifier fully, preferring
			# some match on the left between full path and context directory.
			if ( ($bestPath = ExactDirectoryPathInContext($linkSpecifier, $contextDir, \@paths)) ne ""
			  || ($bestPath = ExactDirectoryPathNoContext($linkSpecifier, \@paths)) ne "" )
				{
				$result = $bestPath;
				}
			# 4., 5.
			# Relax requirements if no match yet, require full match between full path
			# and $linkSpecifier, but the directory names in $linkSpecifier don't have to
			# be complete, some can be omitted. All directory names included in
			# $linkSpecifier must be found in a full path to count as a match.
			if ($result eq "")
				{
				my @partialPathParts = split(/\//, $linkSpecifier);
				# Tack some forward slashes back on for accurate matching with index().
				for (my $i = 0; $i < @partialPathParts; ++$i)
					{
					if (index($partialPathParts[$i], ':') > 0) # drive letter
						{
						$partialPathParts[$i] .= '/';
						}
					else
						{
						$partialPathParts[$i] = '/' . $partialPathParts[$i] . '/';
						}
					}
				if ( ($bestPath = RelaxedDirectoryPathInContext($linkSpecifier, $contextDir, \@paths, \@partialPathParts)) ne ""
				  || ($bestPath = RelaxedDirectoryPathNoContext(\@paths, \@partialPathParts)) ne "" )
					{
					$result = $bestPath;
					}				
				}
			} # directory name is associated with at least one known full path
		} # partial directory path
	
	return($result);
	}

# Just a punt, ExactPathInContext() above works for directories too.
sub ExactDirectoryPathInContext {
	my ($linkSpecifier, $contextDir, $pathsA) = @_;
	return(ExactPathInContext($linkSpecifier . '/', $contextDir, $pathsA));
	}

# ExactPathNoContext() above works for directories too.
sub ExactDirectoryPathNoContext {
	my ($linkSpecifier, $pathsA) = @_;
	return(ExactPathNoContext($linkSpecifier . '/', $pathsA));
	}

# If the directories in a FILE path are out of order, the key for the
# list of associated full file paths doesn't change, because the key
# is the file name (and that must always be rightmost to work).
# However if the directory names in a directory $linkSpecifier are
# permuted then we don't know which directory name if any is the
# right key to use in %FullDirectoryPathsForDirName, so we
# try all  directory names in $linkSpecifier in turn until
# a corresponding directory is found.
sub RelaxedDirectoryPathInContext {
	my ($linkSpecifier, $contextDir, $pathsA, $partialPathPartsA) = @_;
	my $bestPath = RelaxedPathInContext($linkSpecifier . '/', $contextDir, $pathsA, $partialPathPartsA);
	
	if ($bestPath eq '')
		{
		my $numPartialParts = @$partialPathPartsA;
		for (my $i = 0; $i < $numPartialParts - 1; ++$i)
			{
			my $bottomDir = $partialPathPartsA->[$i];
			# Strip leading and trailing slashes.
			$bottomDir = substr($bottomDir, 1);
			$bottomDir = substr($bottomDir, 0, -1);

			if (defined($FullDirectoryPathsForDirName{$bottomDir}))
				{
				my $allpaths = $FullDirectoryPathsForDirName{$bottomDir};
				my @paths;
				# Remove leading and trailing slashes.
				$allpaths = substr($allpaths, 1);
				$allpaths = substr($allpaths, 0, -1);
				if ($allpaths =~ m!\|!) # more than one candidate full path
					{
					@paths = split(/\|/, $allpaths);
					}
				else
					{
					push @paths, $allpaths;
					}
				$bestPath = RelaxedPathInContext($linkSpecifier . '/', $contextDir, \@paths, $partialPathPartsA);
				if ($bestPath ne '')
					{
					last;
					}
				}
			}
		}
	
	return($bestPath);
	}

# See comment just above for RelaxedDirectoryPathInContext.
sub RelaxedDirectoryPathNoContext {
	my ($pathsA, $partialPathPartsA) = @_;
	my $bestPath = RelaxedPathNoContext($pathsA, $partialPathPartsA);
	
	if ($bestPath eq '')
		{
		my $numPartialParts = @$partialPathPartsA;
		for (my $i = 0; $i < $numPartialParts - 1; ++$i)
			{
			my $bottomDir = $partialPathPartsA->[$i];
			# Strip leading and trailing slashes.
			$bottomDir = substr($bottomDir, 1);
			$bottomDir = substr($bottomDir, 0, -1);
			if (defined($FullDirectoryPathsForDirName{$bottomDir}))
				{
				my $allpaths = $FullDirectoryPathsForDirName{$bottomDir};
				my @paths;
				# Remove leading and trailing slashes.
				$allpaths = substr($allpaths, 1);
				$allpaths = substr($allpaths, 0, -1);
				if ($allpaths =~ m!\|!) # more than one candidate full path
					{
					@paths = split(/\|/, $allpaths);
					}
				else
					{
					push @paths, $allpaths;
					}
				$bestPath = RelaxedPathNoContext(\@paths, $partialPathPartsA);
				if ($bestPath ne '')
					{
					last;
					}
				}
			}
		}
	
	return($bestPath);
	}

sub DeleteFullPathListFiles {
	my ($filePath) = @_; # typ. CVal('FILEWATCHERDIRECTORY') . CVal('FULL_PATH_LIST_NAME')
	$filePath =~ m!^(.+?)(\.\w+)$!;
	my $base = $1;
	my $ext = $2;
	my $num = 2;
	my $fragPath = $base . $num . $ext;
	
	unlink($filePath);
	
	while (-f $fragPath)
		{
		unlink($fragPath);
		++$num;
		$fragPath = $base . $num . $ext;
		}
	}
} ##### Directory list

use ExportAbove;
1;
