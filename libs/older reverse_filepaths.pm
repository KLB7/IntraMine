# Obsolete. This version builds a hash holding all full paths for each and every
# partial path for all known files. It works, but the newer reverse_filepaths.pm just
# builds a hash holding all full paths for each file name, which is sufficient.
# reverse_filepaths.pm: FullPathInContextNS() below implements the "auto" part of "autolink."
# This is done using a reverse index, which for each file name lists all full paths that
# end in the file name.
# Given a file name or a partial path that ends in the file name
# eg file.txt, dir3/dr2/dr1/file.txt, FullPathInContextNS() can be called to determine the full
# path. Dirs are required if the file name is not unique and the "$contextDir" does not properly
# resolve the path.
# If I were logically inclined I would a partial path a "rightmost complete partial path",
# meaning a path that agrees with a full path if you start at the rightmost end and go left.
# For example
#    Full path: c:\qtStuff\android\third_party\native_app_glue\android_native_app_glue.h
# Partial path:                                native_app_glue\android_native_app_glue.h
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
# intramine_file_viewer_cm.pl#callbackInitDirectoryFinder().
# The file holding a list of files and full paths for them must of course exist. This is
# built when indexing files with Elasticsearch - see elastic_indexer.pl around line 151,
# where there's a call back to AddIncrementalNewPaths(), defined here.
# Then to get the best matching full path for a partial path (which could be a full path) call
# FullPathInContextNS(): see intramine_file_viewer_cm.pl##FullPathForPartial() for a use.
# (FullPathInContextTrimmed() is similar, the "Trimmed" version deals with nuisance HTML).

package reverse_filepaths;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use utf8;
use FileHandle;
# TEST ONLY under development.
use DBM::Deep;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use win_wide_filepaths;


{ ##### Directory list
my $FullPathListPath;		# For fullpaths.out, typ. CVal('FILEWATCHERDIRECTORY') . CVal('FULL_PATH_LIST_NAME')
my %FileNameForFullPath; 	# as saved in /fullpaths.out: $FileNameForFullPath{C:/dir1/dir2/dir3/file.txt} = 'file.txt';
my $NextFreePathInteger;	# for %FullPathForInteger keys: 1..up
my %FullPathForInteger;		# eg $FullPathForInteger{8397} = 'C:/dir1/dir2/dir3/file.txt';
my %IntegerForFullPath;		# eg $IntegerForFullPath{'C:/dir1/dir2/dir3/file.txt'} = 8397
my %IntKeysForPartialPath; # $IntKeysForPartialPath{'dir3/file.txt'} = '8397|27|90021';

# TEST currently under development.
# Conclusion: not worth writing %FullPathForPartialPath to a db, takes too long.
my %FullPathForPartialPath;
my $db;

# Load %IntKeysForPartialPath, and build %IntKeysForPartialPath from it.
sub InitDirectoryFinder {
	my ($filePath) = @_; # typ. CVal('FILEWATCHERDIRECTORY') . CVal('FULL_PATH_LIST_NAME')
	$NextFreePathInteger = 1;
	my $pathCount = InitFullPathList($filePath);
	BuildPartialPathList(\%FileNameForFullPath);
	LoadIncrementalDirectoryFinderLists($filePath);
	
	return($pathCount);
	}

sub ReinitDirectoryFinder {
	my ($filePath) = @_; # typ. CVal('FILEWATCHERDIRECTORY') . CVal('FULL_PATH_LIST_NAME')
	
	# Empty out %FileNameForFullPath and %IntKeysForPartialPath.
	%FileNameForFullPath = ();
	%IntKeysForPartialPath = ();
	%FullPathForInteger = ();
	%IntegerForFullPath = ();
	$NextFreePathInteger = 1;
	
	return(InitDirectoryFinder($filePath));
	}

# intramine_filewatcher.pl doesn't need the full list of partial paths vs full paths, it just needs the list
# of file names for full paths in %FileNameForFullPath.
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

# Associate an integer with each file path.
# %IntKeysForPartialPath values are a piped list of those integers. The integers are smaller
# than their corresponding paths, reducing memory needs.
sub BuildFullPathsForIntegers {
	my ($fileNameForFullPathH) = @_;
	
	keys %$fileNameForFullPathH; # reset iterator
	while (my ($fullPath, $fileName) = each %$fileNameForFullPathH)
		{
		$FullPathForInteger{$NextFreePathInteger} = $fullPath;
		$IntegerForFullPath{$fullPath} = $NextFreePathInteger;
		++$NextFreePathInteger;
		}
	}

# Fill in %IntKeysForPartialPath{'partial path to file'} =
#  'integer keys for one or more full paths corresponding to partial path, separate by |'.
# As an attempt at clarity, examples below use full paths rather than the integer keys to them.
# A real value in %IntKeysForPartialPath would look like "27|8397|200123" where
# $FullPathForInteger{27} = 'C:/project51/src/main.cpp' etc.
# Eg for "file.txt" in two different places,
# 	%FileNameForFullPath{'C:/...dir1/dir2/dir3/file.txt'} = 'file.txt';
# 	%FileNameForFullPath{'C:/...dir4/dir5/dir6/file.txt'} = 'file.txt';
# Add entries in %IntKeysForPartialPath:
# 	$IntKeysForPartialPath{'file.txt'} = 'C:/...dir1/dir2/dir3/file.txt|C:/...dir4/dir5/dir6/file.txt'; # note the pipe |	A
# 	$IntKeysForPartialPath{'dir3/file.txt'} = 'C:/...dir1/dir2/dir3/file.txt';												B
# 	$IntKeysForPartialPath{'dir2/dir3/file.txt'} = 'C:/...dir1/dir2/dir3/file.txt';											C
#	$IntKeysForPartialPath{'dir1/dir2/dir3/file.txt'} = 'C:/...dir1/dir2/dir3/file.txt';									D
# 	$IntKeysForPartialPath{'dir6/file.txt'} = 'C:/...dir4/dir5/dir6/file.txt';												E
# 	$IntKeysForPartialPath{'dir5/dir6/file.txt'} = 'C:/...dir4/dir5/dir6/file.txt';											F
# 	$IntKeysForPartialPath{'dir4/dir5/dir6/file.txt'} = 'C:/...dir4/dir5/dir6/file.txt';									G
# If dir3 and dir6 have the same names, instead of B and E add
#	$IntKeysForPartialPath{'dir3/file.txt'} = 'C:/...dir1/dir2/dir3/file.txt|C:/...dir4/dir5/dir6/file.txt'; - again note the pipe
# Called by InitDirectoryFinder() just above, and also incrementally when new files are seen,
# in intramine_file_viewer_cm.pl#HandleBroadcastRequest() by a call to LoadIncrementalDirectoryFinderLists().
# Note when called to add entries incrementally, %$fileNameForFullPathH should not duplicate any existing entries
#  - check first with: if (defined($fileNameForFullPathH->{$fullPath}))...skip it.
sub BuildPartialPathList {
	my ($fileNameForFullPathH) = @_;
	
	BuildFullPathsForIntegers($fileNameForFullPathH);
	
	keys %$fileNameForFullPathH; # reset iterator
	while (my ($fullPath, $fileName) = each %$fileNameForFullPathH)
		{
		# Add entry for just file name, see eg line A above.
		my $intKeyForFullPath = $IntegerForFullPath{$fullPath};
		if (defined($IntKeysForPartialPath{$fullPath}))
			{
			$IntKeysForPartialPath{$fullPath} .= "|$intKeyForFullPath";
			}
		else
			{
			$IntKeysForPartialPath{$fullPath} = "$intKeyForFullPath";
			}
		
		# Add entries for partial paths (lines B C etc above);
		# - skip entries where a period '.' starts the folder name.
		my $linkSpecifier = $fullPath;
		# Trim host/share at start.
		#$partialPath =~ s!^//[^/]+/[^/]+/!!;
		# Revision, trim just the host.
		$linkSpecifier =~ s!^//[^/]+/!!;
		# Trim the leading drive:/ spec.
		$linkSpecifier =~ s!^\w:/!!;
		
		# Progressively add entries and strip leading dirs until nothing is left.
		while ($partialPath ne '')
			{
			if (substr($partialPath, 0, 1) ne '.')
				{
				if (defined($IntKeysForPartialPath{$partialPath}))
					{
					# Avoid adding the same path twice.
					my $seenAlready = 0;
					my $allpaths = $IntKeysForPartialPath{$partialPath};
					if ($allpaths =~ m!\|!)
						{
						my @paths = split(/\|/, $allpaths);
						my $numPaths = @paths;
						for (my $i = 0; $i < $numPaths; ++$i)
							{
							if ($fullPath eq $FullPathForInteger{$paths[$i]})
								{
								$seenAlready = 1;
								last;
								}
							}
						}
					elsif ($fullPath eq $FullPathForInteger{$allpaths})
						{
						$seenAlready = 1;
						}
					
					if (!$seenAlready)
						{
						$IntKeysForPartialPath{$partialPath} .= "|$intKeyForFullPath";
						}
					}
				else
					{
					$IntKeysForPartialPath{$partialPath} = $intKeyForFullPath;
					}
				
				if ($partialPath !~ m!/!)
					{
					$linkSpecifier = '';
					}
				else
					{
					$linkSpecifier =~ s!^[^/]+/!!;
					}
				}
			else
				{
				last;
				}
			}
		}	
	}

# Load additional fullpaths2.out to %FileNameForFullPath.
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

# Load additional fullpaths2.out to %FileNameForFullPath, create new partial path entries too.
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
			while (my ($path, $fileName) = each %rawFileNameForFullPath)
				{
				if (!FullPathIsKnown($path))
					{
					$newFileNameForFullPath{$path} = $rawFileNameForFullPath{$path};
					}
				}
				
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
			}
		}
	}

# Update all paths in %FileNameForFullPath after a folder rename. Follow with a call
# to ConsolidateFullPathLists() to make it permanent.
# All paths should be lowercase and use forward slashes.
sub UpdatePathsForFolderRenames {
	my ($numRenames, $renamedFolderPathsA, $oldFolderPathA, $newPathForOldPathH) = @_;
	my @oldFolderPathCopy = @$oldFolderPathA;
	my @renamedFolderPathsCopy = @$renamedFolderPathsA;
	my %tempFileNameForFullPath = %FileNameForFullPath;
	
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
				$newPathForOldPathH->{$path} = $newPath;
				delete($tempFileNameForFullPath{$path});
				$tempFileNameForFullPath{$newPath} = $oldEntry;
				# TEST ONLY
				#print("Renamed: |$newPath| was |$path|\n");
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

# Add to %FileNameForFullPath, and create new partial path entries too.
sub AddIncrementalNewDirectoryFinderLists {
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
			}
		BuildPartialPathList(\%newFileNameForFullPath);
		}	
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

# Requires $fullPath all lower case, with forward slashes.
sub FullPathIsKnown {
	my ($fullPath) = @_;
	my $result = (defined($FileNameForFullPath{$fullPath})) ? 1: 0;
	return($result);
	}

# Every now and then, consolidate fullpaths.out and fullpaths2.out, mainly to shrink
# the size of fullpaths2, which is completely loaded by intramine_fileserver.pl
# whenever a new file is seen. This can a few seconds. This is a transparent change when
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
	if ( $forceConsolidation || (-f $fragPath || !(-f $FullPathListPath)) )
		{
		unlink($FullPathListPath);
		unlink($fragPath);
		my $fileH = FileHandle->new("> $FullPathListPath") or return("File Error, could not open |$FullPathListPath|!");
		binmode($fileH, ":utf8");
	    foreach my $key (sort(keys %FileNameForFullPath))
	        {
	        print $fileH "$key\t$FileNameForFullPath{$key}\n";
	        }
	    close $fileH;
		}
	}

# The main call for autolinking.
# Full path given partial path and context directory.
# Perhaps a bad name, $linkSpecifier is 'normed' here, as opposed to
# FullPathInContextTrimmed() which expects only forward slashes
# and no starting slash. UNLESS we see a leading double-slash, which happens
# in a //host-name/share... link.
# Used in intramine_file_viewer_cm.pl#AddWebAndFileLinksToLine() etc.
# See notes below for BestMatchingFullPath().
sub FullPathInContextNS {
	my ($partialPath, $contextDir) = @_;
	
	$linkSpecifier = lc($partialPath);
	$linkSpecifier =~ s!\\!/!g;
	
	if ($partialPath !~ m!^//!)
		{
		$linkSpecifier =~ s!^/!!;
		}
	
	return(BestMatchingFullPath($partialPath, $contextDir));
	}

# Full path, given a partial path and context directory.
# For linking with perhaps nuisance HTML prepended. Used in intramine_file_viewer_cm.pl#ModuleLink().
# $linkSpecifier: for success, one of:
# file.txt
# dir1/file.txt
# dir2/dir1/file.txt
# dir3/dir2/dir1/file.txt
# etc
# or full path to file.txt, C:/dirN/.../dir1/file.txt
# See notes below for BestMatchingFullPath().
sub FullPathInContextTrimmed {
	my ($partialPath, $contextDir) = @_;
	$linkSpecifier = lc($partialPath);
	
	my $result = BestMatchingFullPath($partialPath, $contextDir);
	if ($result ne '')
		{
		# TEST ONLY
		#print("FPFFAOD_1 QUICK HIT on |$partialPath|!\n");
		return($result);
		}
	
	# Try again, trim any leading HTML tags or spaces etc.
	# Eg &nbsp;&nbsp;&bull;&nbsp;<strong>bootstrap.min.css
	# NOTE this changes $linkSpecifier for all below.
	$linkSpecifier =~ s!^.+?\;([^;]+)$!$1!; # leading spaces or bullets etc
	$linkSpecifier =~ s!^\<\w+\>(.+)$!$1!; # leading <strong> or <em>
	$result = BestMatchingFullPath($partialPath, $contextDir);
	if ($result ne '')
		{
		# TEST ONLY
		#print("FPFFAOD_2 TRIMMED HIT on |$partialPath|!\n");
		return($result);
		}
	
	# No luck
	return('');	
	}

# BestMatchingFullPath
# Args: a $linkSpecifier such as src/main.cpp, and a $contextDir (which is
# the directory holding the file that wants the link) such as c:/cpp_projects/gofish/docs/.
# $linkSpecifier could in fact be a full path (c:/cpp_projects/gofish/src/main.cpp), in which case we're done.
# Otherwise, look for a full path for the $linkSpecifier, and there might be several, separated
# by '|' in %IntKeysForPartialPath, for example
# c:/cpp_projects/gofish/src/main.cpp|c:/cpp_projects/bendit/src/main.cpp|
# p:/olderprojects/compuserve/main.pp: find the one that best matches the $contextDir.
# Score is number of matching characters starting from the left.
# If there are no full paths corresponding to the $linkSpecifier, try stripping any
# leading dir from the path, eg if gofish/src/main.cpp has nothing then look at src/main.cpp,
# and continue until a candidate entry is found or wer'e down to just the file name.
# If $linkSpecifier is ambiguous and $contextDir is pretty much unrelated to any potential full
# path, return the best match anyway, but it could be wrong. Here it's up to the user to
# provide a longer $linkSpecifier, eg src/main.cpp might be highly ambiguous in an arbitrary
# context, but gofish/src/main.cpp would pretty much always pin it down.
# If no candidate full path exists in $IntKeysForPartialPath{$partialPath} for any
# progressively shorter partial path tried, truly give up and return ''.
#
# If $linkSpecifier contains ../ or ../../ , I can't think of a scenario where that
# produces a different result from the one implemented below, so leading ../'s
# are stripped off before getting here. EXCEPT for double leading /'s, which
# signal a potential //host-name/share-name/ link mention.
sub BestMatchingFullPath {
	my ($partialPath, $contextDir) = @_;
	my $result = '';
	
	# Allow any full path, not just the indexed ones.
	if ($partialPath =~ m!^\w:/!)
		{
		if (defined($IntKeysForPartialPath{$partialPath})
		 || FileOrDirExistsWide($partialPath))
			{
			$result = $linkSpecifier; # it's actually a full path (probably)
			}
		}
	# For a //host/share UNC, check for a record of the
	# link text in our %IntKeysForPartialPath hash. No checking the drive.
	elsif ($partialPath =~ m!^//!)
		{
		if (defined($IntKeysForPartialPath{$partialPath}))
			{
			$result = $linkSpecifier;
			}
		}
	else
		{		
		if (defined($IntKeysForPartialPath{$partialPath}))
			{
			my $allpaths = $IntKeysForPartialPath{$partialPath};
			
			if ($allpaths =~ m!\|!) # more than one candidate full path
				{
				# We will try to pick up on the context provided by $contextDir to produce
				# the best candidate. See 'Multipath link resolution.txt' for examples. The key is
				# how much the $contextDir overlaps with each of the @paths, starting from the left.
				# This is effectively the same as finding the "shortest path" from the file
				# in $contextDir that mentions $linkSpecifier to one of the candidates.
				# So if "C:\Proj1\src\dialog.cpp"" is the file wanting the link, with a context dir
				# of "C:\Proj1\src", and if it asks for a full path corresponding to
				# "dialog.h", we should return "C:\Proj1\headers\dialog.h", not some other dialog.h
				# that is "farther away" from our current dialog.cpp.
				my @paths = split(/\|/, $allpaths);
				my $numPaths = @paths;
				my $bestScore = 0;
				my $bestIdx = 0;
				
				for (my $i = 0; $i < $numPaths; ++$i)
					{
					my $testPath = $FullPathForInteger{$paths[$i]};
					my $currentScore = LeftOverlapLength($contextDir, $testPath);
					if ($bestScore < $currentScore)
						{
						$bestScore = $currentScore;
						$bestIdx = $i;
						}
					# On a tie score, prefer the shorter path? Perhaps, you decide....
					elsif ($bestScore > 0 && $bestScore == $currentScore 
						&& length($testPath) < length($FullPathForInteger{$paths[$bestIdx]}))
						{
						$bestIdx = $i;
						}
					}
				# If $bestScore is 0, then contextDir hasn't helped much. We could check for any similarity
				# between a path and the contextDir, but that gets expensive and could be misleading in some cases.
				$result = $FullPathForInteger{$paths[$bestIdx]};
				}
			else
				{
				$result = $FullPathForInteger{$allpaths};
				}
			}
		else
			{
			; # well there's not much we can do really
			}
		}
	
	return($result);
	}

# NOT USED. See ConsolidateFullPathLists.
# Save $FullPathListPath (eg C:/fwws/fullpaths.out),
# and delete any associated "fragment" updates such as fullpaths2.out.
sub SaveRawFullPathList {
	my ($rawListH, $filePath) = @_;
	$FullPathListPath = $filePath;
	
	my $fileH = FileHandle->new("> $FullPathListPath") or return("File Error, could not open |$FullPathListPath|!");
	binmode($fileH, ":utf8");
    foreach my $key (sort(keys %$rawListH))
        {
        print $fileH "$key\t$rawListH->{$key}\n";
        }
    close $fileH;
    
	# Delete any "fragment" update files that accompany $FullPathListPath: fullpaths2.out etc
	$FullPathListPath =~ m!^(.+?)(\.\w+)$!;
	my $base = $1;
	my $ext = $2;
	my $num = 2;
	my $fragPath = $base . $num . $ext;
	while (-f $fragPath)
		{
		unlink($fragPath);
		++$num;
		$fragPath = $base . $num . $ext;
		}

    return('');
	}
	
sub DeleteFullPathListFiles {
	my ($filePath) = @_; # typ. CVal('FILEWATCHERDIRECTORY') . CVal('FULL_PATH_LIST_NAME')
	$filePath =~ m!^(.+?)(\.\w+)$!;
	my $base = $1;
	my $ext = $2;
	my $num = 2;
	my $fragPath = $base . $num . $ext;
	unlink($filePath);
	unlink($fragPath);
	}
	
# TEST currently under development.
# For now, I've decided that too much work would be needed to implement a db-based
# approach to auto-linking, probably a two-month delay. Maybe next version....
sub TestInitDirectoryFinder_DB {
	my ($filePath, $dbPath) = @_; # typ. CVal('FILEWATCHERDIRECTORY') . CVal('FULL_PATH_LIST_NAME')
	
	# First test, put all file paths in db as values.
	# This takes 80 minutes, 2.2 GB for 293,000 files. Too slow.
	# $NextFreePathInteger = 1;
	# my $pathCount = InitFullPathList($filePath);
	#TestBuildPartialPathList_DB(\%FileNameForFullPath, $dbPath);
	# For test, skip incremental.
	#LoadIncrementalDirectoryFinderLists($filePath);
	
	# Second test, use full path indexes. They are temp, we're just after a speed estimate.
	# This takes 50 minutes, 1.8 GB - so a bit better than the first one.
	# There were about 3.6 million db entries for the 293,000 files indexed.
	print("Building \%IntKeysForPartialPath in memory\n");
	my $pathCount = InitDirectoryFinder($filePath);
	print("Done building \%IntKeysForPartialPath in memory\n");
	SavePartialPathsDB($dbPath);
	
	return($pathCount);
	}

sub SavePartialPathsDB {
	my ($dbPath) = @_;
	
	if (-f $dbPath)
		{
		unlink($dbPath);
		}
	
	$db = DBM::Deep->new($dbPath);

	# Pump out %FullPathForPartialPath to the db.
	print("Putting \%IntKeysForPartialPath to disk\n");
	my $soFarCount = 0;
	my $totalCount = keys %IntKeysForPartialPath; # reset iterator
	while (my ($partialPath, $fullPaths) = each %IntKeysForPartialPath)
		{
		if (($soFarCount++%10000) == 0)
			{
			print("  $soFarCount / $totalCount...\n");
			}
		
		$db->{$partialPath} = $fullPaths;
		}
	print("Done putting \%IntKeysForPartialPath to disk\n");
	}

sub TestBuildPartialPathList_DB {
	my ($fileNameForFullPathH, $dbPath) = @_;
	
	if (-f $dbPath)
		{
		unlink($dbPath);
		}
	
	$db = DBM::Deep->new($dbPath);
	
	# First build the list in memory.
	print("Building \%FullPathForPartialPath in memory\n");
	foreach my $fullPath (keys %$fileNameForFullPathH)
		{
		# Add entry for just file name, see eg line A above.
		if (defined($FullPathForPartialPath{$fullPath}))
			{
			$FullPathForPartialPath{$fullPath} .= "|$fullPath";
			}
		else
			{
			$FullPathForPartialPath{$fullPath} = $fullPath;
			}
		
		# Add entries for partial paths (lines B C etc above);
		# - skip entries where a period '.' starts the folder name.
		my $linkSpecifier = $fullPath;
		# Trim host/share at start.
		#$partialPath =~ s!^//[^/]+/[^/]+/!!;
		# Revision, trim just the host.
		$linkSpecifier =~ s!^//[^/]+/!!;
		# Trim the leading drive:/ spec.
		$linkSpecifier =~ s!^\w:/!!;
		
		# Progressively add entries and strip leading dirs until nothing is left.
		while ($partialPath ne '')
			{
			if (substr($partialPath, 0, 1) ne '.')
				{
				if (defined($FullPathForPartialPath{$partialPath}))
					{
					# Avoid adding the same path twice.
					my $seenAlready = 0;
					my $allpaths = $FullPathForPartialPath{$partialPath};
					if ($allpaths =~ m!\|!)
						{
						my @paths = split(/\|/, $allpaths);
						my $numPaths = @paths;
						for (my $i = 0; $i < $numPaths; ++$i)
							{
							if ($fullPath eq $paths[$i])
								{
								$seenAlready = 1;
								last;
								}
							}
						}
					elsif ($fullPath eq $allpaths)
						{
						$seenAlready = 1;
						}
					
					if (!$seenAlready)
						{
						$FullPathForPartialPath{$partialPath} .= "|$fullPath";
						}
					}
				else
					{
					$FullPathForPartialPath{$partialPath} = $fullPath;
					}
				# TEST ONLY
				#print("BPPL added partialPath |$partialPath|\n");
				if ($partialPath !~ m!/!)
					{
					$linkSpecifier = '';
					}
				else
					{
					$linkSpecifier =~ s!^[^/]+/!!;
					}
				}
			else
				{
				last;
				}
			}
		}
		
	# Pump out %FullPathForPartialPath to the db.
	print("Putting FullPathForPartialPath to disk\n");
	my $soFarCount = 0;
	my $totalCount = keys %FullPathForPartialPath; # reset iterator
	while (my ($partialPath, $fullPaths) = each %FullPathForPartialPath)
		{
		if (($soFarCount++%10000) == 0)
			{
			print("  $soFarCount / $totalCount...\n");
			}
		
		$db->{$partialPath} = $fullPaths;
		}
	print("Done putting FullPathForPartialPath to disk\n");
	}

sub FullPathsForPartial_DB {
	my ($partialPath) = @_;
	my $result = $db->{$partialPath};
	if (!defined($result))
		{
		$result = '';
		}
	
	return($result);
	}
} ##### Directory list

use ExportAbove;
1;
