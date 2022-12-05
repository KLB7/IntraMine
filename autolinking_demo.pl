# autolinking_demo_noint.pl: test some link specifiers against a short list of
# known full paths to see what the suggested full paths are.
# Link specifiers are tested in a specific "context" and the full path
# closest to the context is picked when there is a choice.
#
# This is a Perl program, requiring only a version of Perl that isn't ancient.
# Windows file paths are assumed, and some changes would be needed
# to properly handle eg Linux file paths.
#
# This program is based on IntraMine's /libs/reverse_filepaths.pm.
# IntraMine can be found at https://github.com/KLB7/IntraMine
# and contains a complete autolinking solution for Windows 10/11.
#
# **Referencing file**: the source or text file where you're typing, and want
# to have a link to a target file.
# **Context**: this is the directory that holds the referencing file.
# **Link specifier**: a file name, plus optionally enough directory names in any
# order to uniquely identify a file. Plus optionally a drive letter (placed first
# so as not to confuse humans). For this to work properly, the file should be in a
# list of known full paths.
#
# In this demo the link specifiers are known in advance and listed in
# @TestLinkSpecifiers. In a real app the link specifiers would likely be part
# of ordinary text in a referencing file, such as "In src/main.cpp there is no singleton..."
# and so the link specifier would need to be experimentally determined
# by finding a file extension (here ".cpp") and then working backwards
# through the text to find the longest potential link specifier that
# matches a known full path. For the above example the following strings
# would be tested in turn: "main.cpp", "src/main.cpp", "In src/main.cpp"
# and the winner would likely be "src/main.cpp".
#
# NOTE if you want to modify this program (eg by adding/deleting some of the
# full paths or link specifiers or context directories below) it's best to
# do that in a copy.
#
# There are lots of comments below that try to explain what's being done.
#
# Change the path below to match your installation, and then you can
# run this program by copying the line below (from "perl" onward)
# to a command window.
# perl C:\perlprogs\IntraMine\programs_do_not_ship\autolinking_demo_noint.pl
# Syntax check:
# perl -c C:\perlprogs\IntraMine\programs_do_not_ship\autolinking_demo_noint.pl


use strict;
use warnings;
use utf8;
use File::Basename;

# A list of full paths to all files that can be linked to.
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

# Link specifiers, as you would type them in a text or source referencing file.
my @TestLinkSpecifiers;
push @TestLinkSpecifiers, 'main.cpp';
push @TestLinkSpecifiers, 'project51/main.cpp';
push @TestLinkSpecifiers, 'project999/main.cpp';
push @TestLinkSpecifiers, 'project88/main.cpp';
push @TestLinkSpecifiers, 'src/main.cpp';
push @TestLinkSpecifiers, 'e:/main.cpp';
push @TestLinkSpecifiers, '//Desktop-hrj/projects/project88/src/main.cpp';
push @TestLinkSpecifiers, 'nain.cpp';

# Context directory paths holding the referencing file wherein you have typed the link specifier.
my @TestContextDirectories;
push @TestContextDirectories, 'c:/projects/project51/docs';
push @TestContextDirectories, 'c:/projects/project999/docs';
push @TestContextDirectories, 'e:/other_projects/sailnav/misc';
#push @TestContextDirectories, 'q:/elsewhereville';

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
# Not needed for DEMO: my $FullPathListPath;
# Moved up top for this DEMO: my %FileNameForFullPath;
my %FullPathsForFileName; # Eg $FullPathsForFileName{'main.cpp'} = 'C:\proj1\main.cpp|C:\proj2\main.cpp';

# DEMO ONLY
my $MatchType; # "NO_MATCH", "FullMatch", "ExactPathInContext", "ExactPathNoContext", "RelaxedPathInContext", "RelaxedPathNoContext"

# Test replacement for InitDirectoryFinder() in reverse_filepaths.pm.
# Build a list of full paths to all files that can be linked to when determining the
# full path for a link specifier.
sub BuildFullPathTestHashes {
	# %FileNameForFullPath entries are up above.	
	BuildFullPathsForFileName(\%FileNameForFullPath);
	}
	
# From entries in %FileNameForFullPath build a "reverse" hash %FullPathsForFileName
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
		}
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
#  For more examples, see "Documentation/Linker.txt" and subs immediately below.
# -> $contextDir: path to the directory of file where $linkSpecifier is typed,
#  eg c:/projects/project51/docs/ or P:/project51/notes/.
#  A full path's distance from the $contextDir is measured by how many hops
# up and down it takes to go from the deepest directory in the full path
# to the $contextDir. For examples see subs below.
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
	
	$MatchType = "NO_MATCH"; # $MatchType is for DEMO ONLY.

	# 1.
	# Allow any full path, provided either we have a record of it or the file is on disk.
	if ($linkSpecifier =~ m!^\w:/!)
		{
		# In this demo we just check to see if the $linkSpecifier is in the list
		# of known full paths. In IntraMine's reverse_filepaths.pm there is also
		# a check to see if the path exists on disk
		###if (FullPathIsKnown($linkSpecifier) || FileOrDirExistsWide($linkSpecifier) == 1)
		if (FullPathIsKnown($linkSpecifier))
			{
			$MatchType = "FullMatch";
			$result = $linkSpecifier;
			}
		}
	# For a //host/share UNC, check for a record of the
	# link text in our %IntKeysForPartialPath hash. No checking the drive.
	elsif ($linkSpecifier =~ m!^//!)
		{
		if (FullPathIsKnown($linkSpecifier))
			{
			$MatchType = "FullMatch";
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
			# Relax requirements if no match yet, require match between full path
			# and $linkSpecifier, but the directory names in $linkSpecifier don't have to
			# be complete, some can be omitted. All directory names included in
			# $linkSpecifier must be found in a full path to count as a match.
			if ($result eq "")
				{
				my @partialPathParts = split(/\//, $linkSpecifier);
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
				
				if ( ($bestPath = RelaxedPathInContext($linkSpecifier, $contextDir, \@paths, \@partialPathParts)) ne ""
				  || ($bestPath = RelaxedPathNoContext(\@paths, \@partialPathParts)) ne "" )
					{
					$result = $bestPath;
					}
				}
			} # file name is associated with at least one known full path
		} # partial path
		
	# Put results in an array, for aligned printing at end.
	StoreOneResult($MatchType, $linkSpecifier, $contextDir, $result);
	
	return($result); # Not used in this demo, returned full path would become the href for a link.
	}

# -> $linkSpecifier, $contextDir: see comment above for BestMatchingFullPath().
# -> $pathsA: array of full paths where file name in full path matches file name in $linkSpecifier.
# <- returns index in $pathsA of best match, or -1.
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
	my $bestScore = 0;
	my $bestSlashScore = 999;
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
		
		# DEMO ONLY
		$MatchType = "ExactPathInContext";
		}
	
	return($result);
	}

# -> $linkSpecifier, $contextDir: see comment above for BestMatchingFullPath().
# -> $pathsA: array of full paths where file name in full path matches file name in $linkSpecifier.
# -> $linkSpecifierPartsA: array holding folder names in $linkSpecifier and drive if any
#    (file name is excluded).
# <- returns index in $pathsA of best match, or -1.
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
	my ($linkSpecifier, $contextDir, $pathsA, $linkSpecifierPartsA) = @_;
	my $numPaths = @$pathsA;
	my $bestScore = 0;
	my $bestSlashScore = 999;
	my $bestIdx = -1;
	
	for (my $i = 0; $i < $numPaths; ++$i)
		{
		my $testPath = $pathsA->[$i];
		
		if (AllPartialPartsAreInTestPath($linkSpecifierPartsA, $testPath))
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
		
		# DEMO ONLY
		$MatchType = "RelaxedPathInContext";
		}
	
	return($result);
	}

# -> $linkSpecifier: file name optionally preceded by one or more directory names, without skips
#    eg any of main.cpp, src/main.cpp, project51/src/main.cpp, P:/project51/src/main.cpp.
# -> $pathsA: array of full paths where file name in full path matches file name in $linkSpecifier.
# <- returns index in $pathsA of best match, or -1.
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
		
		# DEMO ONLY
		$MatchType = "ExactPathNoContext";
		}
	
	return($result);
	}

# -> $pathsA: array of full paths where file name in full path matches file name in $linkSpecifier.
# -> $linkSpecifierPartsA: array holding folder names in $linkSpecifier and drive if any
#    (file name is excluded).
# <- returns index in $pathsA of best match, or -1.
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
	my ($pathsA, $linkSpecifierPartsA) = @_;
	my $numPaths = @$pathsA;
	my $bestSlashScore = 999;
	my $bestIdx = -1;

	for (my $i = 0; $i < $numPaths; ++$i)
		{
		my $testPath = $pathsA->[$i];
		if (AllPartialPartsAreInTestPath($linkSpecifierPartsA, $testPath))
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
		
		# DEMO ONLY
		$MatchType = "RelaxedPathNoContext";
		}
	
	return($result);
	}

# -> $linkSpecifierPartsA: a list of /directory names/ in the link specifier
#    (eg for test/esindex/cmAutoLink.js the list would be "/test/", "/esindex/").
sub AllPartialPartsAreInTestPath {
	my ($linkSpecifierPartsA, $testPath) = @_;
	my $result = 1;
	
	for (my $i = 0; $i < @$linkSpecifierPartsA; ++$i)
		{
		if (index($testPath, $linkSpecifierPartsA->[$i]) < 0)
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
	my ($MatchType, $linkSpecifier, $contextDir, $fullPath) = @_;
	my $numRows = @rows;
	if ($numRows == 0)
		{
		push @rows, ["Match type", "Link specifier", "Context", "Full path"];
		}
	
	if ($contextDir eq '')
		{
		$contextDir = '(no context)';
		}
	push @rows, [$MatchType, $linkSpecifier, $contextDir, $fullPath];
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
