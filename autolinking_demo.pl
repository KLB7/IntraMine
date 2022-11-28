# autolinking_demo.pl: test some link specifiers against a short list of
# known full paths to see what the suggested full paths are.
# Link specifiers are tested in a specific "context" and the full path
# closest to the context is picked when there is a choice.
#
# This program is based on IntraMine's /libs/reverse_filepaths.pm.
# IntraMine can be found at https://github.com/KLB7/IntraMine
# and contains a complete autolinking solution.
#
# In this demo the link specifiers are known in advance and listed in
# @TestLinkSpecifiers. In a real app the link specifiers might be part
# of ordinary text, such as "In src/main.cpp there is no singleton..."
# and so the link specifier would need to be experimentally determined
# by finding a file extension (here ".cpp") and then working backwards
# through the text to find the longest potential specifier that
# matches a known full path. For this example the following strings
# would be tested in turn: "main.cpp", "src/main.cpp", "In src/main.cpp"
# and the winner would likely be "src/main.cpp".
#
# NOTE if you want to modify this program (eg by adding/deleting some of the
# full paths or link specifiers or context directories below) it's best to
# do that in a copy saved somewhere else.
#
# There are lots of comments below that try to explain what's being done.

# Change the path below to match your installation, and then you can
# run this program by copying the line below (from "perl" onward)
# to a command window.
# perl C:\perlprogs\IntraMine\autolinking_demo.pl
# Syntax check:
# perl -c C:\perlprogs\IntraMine\autolinking_demo.pl


use strict;
use warnings;
use utf8;
use File::Basename;

# Build a list of full paths to all files that can be linked to.
# For this DEMO, the full path list is built here to be with the other lists.
# This is the list of all full paths of interest. If a link specifier is not
# itself a full path, a matching full path will be chosen from this list
# if appropriate.
my %FileNameForFullPath;
$FileNameForFullPath{'c:/projects/project51/src/main.cpp'} = 'main.cpp';
$FileNameForFullPath{'c:/projects/project999/src/main.cpp'} = 'main.cpp';
$FileNameForFullPath{'e:/other_projects/sailnav/src/main.cpp'} = 'main.cpp';
$FileNameForFullPath{'//Desktop-hrj/projects/project88/src/main.cpp'} = 'main.cpp';

# Build data structures to help search through full paths.
BuildFullPathTestHashes();

# Link specifiers, as you would type them in a text or source file.
my @TestLinkSpecifiers;
push @TestLinkSpecifiers, 'main.cpp';
push @TestLinkSpecifiers, 'project51/main.cpp';
push @TestLinkSpecifiers, 'project999/main.cpp';
push @TestLinkSpecifiers, 'e:/other_projects/sailnav/src/main.cpp';
push @TestLinkSpecifiers, 'e:/main.cpp';
push @TestLinkSpecifiers, '//Desktop-hrj/projects/project88/src/main.cpp';
push @TestLinkSpecifiers, 'project88/main.cpp';

# Directory paths holding the document wherein you have typed the link specifier.
my @TestContextDirectories;
push @TestContextDirectories, 'c:/projects/project51/src/docs';
push @TestContextDirectories, 'e:/other_projects/sailnav/misc';
push @TestContextDirectories, 'q:/elsewhereville';

# Test all link specifiers in all contexts (and no context).
for (my $i = 0; $i < @TestLinkSpecifiers; ++$i)
	{
	FindBestLinkFor($TestLinkSpecifiers[$i]);
	}

# Determine output formatting and print aligned results.
DumpResults();


###### subs

# Check each link specifier against all context directories, and no context.
sub FindBestLinkFor {
	my ($linkSpecifier) = @_;
	
	for (my $i = 0; $i < @TestContextDirectories; ++$i)
		{
		FindBestLinkInContextFor($linkSpecifier, $TestContextDirectories[$i]);
		}
	FindBestLinkInContextFor($linkSpecifier, "");
	}

# Find the best full path for a link specifier in context.
# $contextDir can be "".
# (In this test version BestMatchingFullPath() prints details on how things went.)
sub FindBestLinkInContextFor {
	my ($linkSpecifier, $contextDir) = @_;
	my $bestFullPath = BestMatchingFullPath($linkSpecifier, $contextDir);
	}

# Subs below are based on Intramine/libs/reverse_filepaths.pm, see https://github.com/KLB7/IntraMine.
{ ##### Directory list
#Not needed for DEMO: my $FullPathListPath;
# Moved up top for this DEMO: my %FileNameForFullPath;
my $NextFreePathInteger;	# for %FullPathForInteger keys: 1..up
my %FullPathForInteger;		# eg $FullPathForInteger{8397} = 'C:/dir1/dir2/dir3/file.txt';
my %IntegerForFullPath;		# eg $IntegerForFullPath{'C:/dir1/dir2/dir3/file.txt'} = 8397
# List of all (integer keys for) full paths that end in a given file name:
my %AllIntKeysForFileName;  # $AllIntKeysForFileName{'file.txt'} = '8397|27|90021';

# DEMO ONLY
my $MatchType; # "NO_MATCH", "FullMatch", "ExactInContext", "ExactFullPath", "RelaxedInContext", "RelaxedFullPath"

# Test replacement for InitDirectoryFinder() in reverse_filepaths.pm.
# Build a list of full paths to all files that can be linked to when determining the
# full path for a link specifier.
sub BuildFullPathTestHashes {
	$NextFreePathInteger = 1;
	
	# Moved to top of this file to be easier to read.	
	#$FileNameForFullPath{'c:/perlprogs/intramine/test/esindex/cmautolinks.js'} = 'cmautolinks.js';
	#$FileNameForFullPath{'c:/perlprogs/intramine/js_for_web_server/cmautolinks.js'} = 'cmautolinks.js';
	#$FileNameForFullPath{''} = '';
	
	BuildPartialPathList(\%FileNameForFullPath);
	}

# Associate an integer with each file path.
# The integers are smaller than their corresponding paths, reducing memory needs.
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

# Make %AllIntKeysForFileName, pipe-separated list of integers that correspond
# to all full paths for a file name.
# Eg $AllIntKeysForFileName{'file.txt'} = '8397|27|90021';
sub BuildPartialPathList {
	my ($fileNameForFullPathH) = @_;
	
	BuildFullPathsForIntegers($fileNameForFullPathH);
	
	keys %$fileNameForFullPathH; # reset iterator
	while (my ($fullPath, $fileName) = each %$fileNameForFullPathH)
		{
		# Add entry for just file name.
		my $intKeyForFullPath = $IntegerForFullPath{$fullPath};
		if (defined($AllIntKeysForFileName{$fileName}))
			{
			$AllIntKeysForFileName{$fileName} .= "|$intKeyForFullPath";
			}
		else
			{
			$AllIntKeysForFileName{$fileName} = "$intKeyForFullPath";
			}
		}	
	}

# BestMatchingFullPath
# -> $partialPath: in a real program, this would be a string of text
#  that ends with all or part of a file name, and a file extension. The
#  challenge is to see if the string corresponds to a "link specifier"
#  that can be matched to a known full path. A link specifier consists of:
#  (optional) drive specifier followed by (optional) directory names in any order
#  followed by a file name with extension. For example, a link specifier for
#  c:/projects/project51/src/main.cpp
#  could be any of
#  main.cpp, c:/main.cpp, src/main.cpp, project51/main.cpp, src/project51/main.cpp etc.
#  And the $partialPath could include extra words on the left end, such as
#  "as we see in src/main.cpp" (in which case the $partialPath would be rejected).
#  For more examples, see "Documentation/Linker.txt"
# -> $contextDir: path to the directory of file where $partialPath is typed,
#    eg c:/projects/project51/docs/ or P:/project51/notes/.
#  A full path's distance from the $contextDir is measured by how many hops
# up and down it takes to go from the deepest directory in the full path
# to the $contextDir.
# <- full path that best matches the partial path in context, or ''.
# We do five checks:
# 1. Is $partialPath (pp) a full path? Return  it.
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
# Note where the supplied $partialPath is ambiguous, the wrong path can be returned.
#
# If $partialPath contains ../ or ../../ , I can't think of a scenario where that
# produces a different result from the one implemented below, so leading ../'s
# should be stripped off before getting here. EXCEPT for double leading /'s, which
# signal a potential //host-name/share-name/ link mention.
sub BestMatchingFullPath {
	my ($partialPath, $contextDir) = @_;
	my $result = '';
	
	$MatchType = "NO_MATCH"; # $MatchType is for DEMO ONLY.

	# 1.
	# Allow any full path, provided either we have a record of it or the file is on disk.
	if ($partialPath =~ m!^\w:/!)
		{
		# In this demo we just check to see if the $partialPath is in the list
		# of known full paths. In IntraMine's reverse_filepaths.pm there is also
		# a check to see if the path exists on disk
		###if (FullPathIsKnown($partialPath) || FileOrDirExistsWide($partialPath) == 1)
		if (FullPathIsKnown($partialPath))
			{
			$MatchType = "FullMatch";
			$result = $partialPath;
			}
		}
	# For a //host/share UNC, check for a record of the
	# link text in our %IntKeysForPartialPath hash. No checking the drive.
	elsif ($partialPath =~ m!^//!)
		{
		if (FullPathIsKnown($partialPath))
			{
			$MatchType = "FullMatch";
			$result = $partialPath;
			}
		}
	
	if ($result eq '') # Check for a partial path (incomplete or scrambled).
		{
		my $fileName = basename($partialPath);
		
		if (defined($AllIntKeysForFileName{$fileName}))
			{
			my $allpaths = $AllIntKeysForFileName{$fileName};
			my @paths;
			if ($allpaths =~ m!\|!) # more than one candidate full path
				{
				@paths = split(/\|/, $allpaths);
				}
			else
				{
				push @paths, $allpaths;
				}
			
			my $bestIdx = -1;
			# 2., 3.
			# First check for a full path that matches $partialPath fully, preferring
			# some match on the left between full path and context directory.
			if ( ($bestIdx = ExactInContext($partialPath, $contextDir, \@paths)) >= 0
			  || ($bestIdx = ExactFullPath($partialPath, \@paths)) >= 0 )
				{
				$result = $FullPathForInteger{$paths[$bestIdx]};
				}
			# 4., 5.
			# Relax requirements if no match yet, require match between full path
			# and $partialPath, but the directory names in $partialPath don't have to
			# be complete, some can be omitted. All directory names included in
			# $partialPath must be found in a full path to count as a match.
			if ($bestIdx < 0)
				{
				my @partialPathParts = split(/\//, $partialPath);
				pop(@partialPathParts); # Remove file name (last entry).
				# Tack some forward slashes back on for accurate matching of each path part.
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
				
				if ( ($bestIdx = RelaxedInContext($partialPath, $contextDir, \@paths, \@partialPathParts)) >= 0
				  || ($bestIdx = RelaxedFullPath(\@paths, \@partialPathParts)) >= 0 )
					{
					$result = $FullPathForInteger{$paths[$bestIdx]};
					}
				}
			} # file name is associated with at least one known full path
		} # partial path
		
	# Put results in an array, for aligned printing at end.
	StoreOneResult($MatchType, $partialPath, $contextDir, $result);
	
	return($result); # Not used in this demo, returned full path would become the href for a link.
	}

# -> $partialPath, $contextDir: see comment above for BestMatchingFullPath().
# -> $pathsA: array of full paths where file name in full path matches file name in $partialPath.
# <- returns index in $pathsA of best match, or -1.
# For all full paths, if full path contains all of $partialPath it's a match. Among all matches,
# pick one where full path overlaps most on the left with $contextDir. If there's a tie,
# pick the path that's the fewest number of directory hops from the contextDir. If there's
# still a tie, pick the shortest full path. Return index of best full path (-1 if no match).
sub ExactInContext {
	my ($partialPath, $contextDir, $pathsA) = @_;
	my $partialLength = length($partialPath);
	my $numPaths = @$pathsA;
	my $bestScore = 0;
	my $bestSlashScore = 999;
	my $bestIdx = -1;
	
	for (my $i = 0; $i < $numPaths; ++$i)
		{
		my $testPath = $FullPathForInteger{$pathsA->[$i]};
		my $matchPos;
		
		if (($matchPos = index($testPath, $partialPath)) > 0)
			{
			my $testLength = length($testPath);
			# We want a full match on the $partialPath within $testPath, and to avoid a match
			# against a partial directory name we need the char preceding the match to be a slash.
			# (Eg avoid a match of test/file.txt against c:/stuff/bigtest/file.txt)
			if ($testLength == $matchPos + $partialLength && substr($testPath, $matchPos-1, 1) eq '/')
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
						if ($testLength < length($FullPathForInteger{$pathsA->[$bestIdx]}))
							{
							$bestIdx = $i;
							}
						}
					}
				}
			}
		}
		
	# DEMO ONLY
	if ($bestIdx >= 0)
		{
		$MatchType = "ExactInContext";
		}
	
	return($bestIdx);
	}

# -> $partialPath, $contextDir: see comment above for BestMatchingFullPath().
# -> $pathsA: array of full paths where file name in full path matches file name in $partialPath.
# -> $partialPathPartsA: array holding folder names in $partialPath and drive if any
#    (file name is excluded).
# <- returns index in $pathsA of best match, or -1.
# For all full paths, if full path contains all of the directory names mentioned in $partialPath
# regardless of position or order (drive too if provided) then it's a match. Among all matches,
# pick one where full path overlaps most on the left with $contextDir. If there's a tie,
# pick the path that's the fewest number of directory hops from the $contextDir. If there's
# still a tie, pick the shortest full path. Return index of best full path (-1 if no match).
sub RelaxedInContext {
	my ($partialPath, $contextDir, $pathsA, $partialPathPartsA) = @_;
	my $numPaths = @$pathsA;
	my $bestScore = 0;
	my $bestSlashScore = 999;
	my $bestIdx = -1;
	
	for (my $i = 0; $i < $numPaths; ++$i)
		{
		my $testPath = $FullPathForInteger{$pathsA->[$i]};
		
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
					if ($testLength < length($FullPathForInteger{$pathsA->[$bestIdx]}))
						{
						$bestIdx = $i;
						}
					}
				}
			}
		}
	
	# DEMO ONLY
	if ($bestIdx >= 0)
		{
		$MatchType = "RelaxedInContext";
		}

	return($bestIdx);
	}

# -> $partialPath: file name optionally preceded by one or more directory names, without skips
#    eg any of main.cpp, src/main.cpp, project51/src/main.cpp, P:/project51/src/main.cpp.
# -> $pathsA: array of full paths where file name in full path matches file name in $partialPath.
# <- returns index in $pathsA of best match, or -1.
# For all full paths, if full path contains all of $partialPath return its index.
# On a tie, prefer the shallowest path (fewest directories).
sub ExactFullPath {
	my ($partialPath, $pathsA) = @_;
	my $partialLength = length($partialPath);
	my $numPaths = @$pathsA;
	my $bestSlashScore = 999;
	my $bestIdx = -1;
	
	for (my $i = 0; $i < $numPaths; ++$i)
		{
		my $testPath = $FullPathForInteger{$pathsA->[$i]};
		my $matchPos;
		if (($matchPos = index($testPath, $partialPath)) > 0)
			{
			my $testLength = length($testPath);
			if ($testLength == $matchPos + $partialLength && substr($testPath, $matchPos-1, 1) eq '/')
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
	
	# DEMO ONLY
	if ($bestIdx >= 0)
		{
		$MatchType = "ExactFullPath";
		}

	return($bestIdx);
	}

# -> $pathsA: array of full paths where file name in full path matches file name in $partialPath.
# -> $partialPathPartsA: array holding folder names in $partialPath and drive if any
#    (file name is excluded).
# <- returns index in $pathsA of best match, or -1.
# For all full paths, if full path contains all of the subfolders mentioned in $partialPath
# regardless of position or order (drive too if provided) then return its index.
# On a tie, prefer the shallowest path (fewest directories).
sub RelaxedFullPath {
	my ($pathsA, $partialPathPartsA) = @_;
	my $numPaths = @$pathsA;
	my $bestSlashScore = 999;
	my $bestIdx = -1;

	for (my $i = 0; $i < $numPaths; ++$i)
		{
		my $testPath = $FullPathForInteger{$pathsA->[$i]};
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
		
	# DEMO ONLY
	if ($bestIdx >= 0)
		{
		$MatchType = "RelaxedFullPath";
		}

	return($bestIdx);
	}

# -> $partialPathPartsA: a list of /directory names/ in the link specifier
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
} ##### Directory list

# (Borrowed from intramine/libs/common.pm.)
# Length of overlap between two strings, starting at left.
# LeftOverlapLength("C:/AA", "C:/AB") == 4,
# LeftOverlapLength("C:/AA", "P:/AB") == 0,
# you get the idea.
sub LeftOverlapLength {
    my ($str1, $str2) = @_;
    
    # Equalize Lengths
    if (length $str1 < length $str2) {
        $str2 = substr $str2, 0, length($str1);
    } elsif (length $str1 > length $str2) {
        $str1 = substr $str1, 0, length($str2);
    }

    # Reduce on right until match found
    while ($str1 ne $str2) {
        chop $str1;
        chop $str2;
    }

    return(length($str1));
	}

{ ##### Formatted Results
# For this demo only.
# Mostly borrowed from the answer in https://stackoverflow.com/questions/13038898/getting-fixed-width-columnar-output-using-printf-in-perl  by Adam Thomason.
my @rows;
my @widths;

sub StoreOneResult {
	my ($MatchType, $partialPath, $contextDir, $fullPath) = @_;
	my $numRows = @rows;
	if ($numRows == 0)
		{
		push @rows, ["Match type", "Link specifier", "Context", "Full path"];
		}
	
	if ($contextDir eq '')
		{
		$contextDir = '(no context)';
		}
	push @rows, [$MatchType, $partialPath, $contextDir, $fullPath];
	}

sub SetColumnWidths {
	for my $row (@rows)
		{
		for (my $col = 0; $col < @$row; $col++)
			{
			$widths[$col] = length $row->[$col] if length $row->[$col] > ($widths[$col] // 0);
			}
		}
	}

sub DumpResults {
	SetColumnWidths();
	
	my $format = join(' ', map { "%-${_}s" } @widths) . "\n";
	
	for my $row (@rows)
		{
		printf $format, @$row;
		}
	}
} ##### Formatted Results
