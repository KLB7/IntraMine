# reverse_filepaths_lite.pm: a stripped-down version of reverse_filepaths.pm
# with just two main subs:
# sub InitLiteFullPathList: pass a path to a full paths list to initialize
# sub FullPathInContext taking $linkSpecifier, $contextDir and returning one full path
# sub FullDirectoryPathLite taking $linkSpecifier, $contextDir and returning one directory (full) path

# Syntax check
# perl -c "C:/perlprogs/Intramine/libs/reverse_filepaths_lite.pm"

package reverse_filepaths_lite;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use utf8;
use FileHandle;
use File::Basename;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use win_wide_filepaths;

{ ##### Directory list
my %FullPathsForFileName
	;    # Eg $FullPathsForFileName{'main.cpp'} = 'c:/proj1/main.cpp|c:/proj2/main.cpp';
my %FullDirectoryPathsForDirName
	;    # Eg $FullDirectoryPathsForDirName{'docs'} = '|c:/proj1/docs|c:/p2/docs|';
my %LastDirForFullDirPath;    # $LastDirForFullDirPath{'c:/proj1/docs'} = 'docs';

sub InitLiteFullPathList {
	my ($filePath) = @_;
	%FullPathsForFileName = ();
	%FullDirectoryPathsForDirName = ();
	%LastDirForFullDirPath = ();
	
	my %fileNameForFullPath;
	my $pathCount  = InitFullPathList($filePath, \%fileNameForFullPath);
	BuildFullPathsForFileName(\%fileNameForFullPath);
	LoadIncrementalDirectoryFinderLists($filePath, \%fileNameForFullPath);
	
	return($pathCount);
}

sub FullPathInContext {
	my ($linkSpecifier, $contextDir) = @_;
	$linkSpecifier = lc($linkSpecifier);
	$linkSpecifier =~ s!\\!/!g;

	if ($linkSpecifier !~ m!^//!)
		{
		$linkSpecifier =~ s!^/!!;
		}

	return (BestMatchingFullPath($linkSpecifier, $contextDir));
}

# Based on reverse_filepaths.pm#BestMatchingFullDirectoryPath().
sub FullDirectoryPathLite {
	my ($linkSpecifier, $contextDir) = @_;
	my $result = '';
	$linkSpecifier = lc($linkSpecifier);
	$linkSpecifier =~ s!\\!/!g;
	if ($linkSpecifier !~ m!^//!)
		{
		$linkSpecifier =~ s!^/!!;
		}
	$linkSpecifier =~ s!/$!!;
	
	# Pull last dir from a $linkSpecifier:
	my $bottomDir    = '';
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
		if ($allpaths =~ m!\|!)    # more than one candidate full path
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
		if (($bestPath = ExactDirectoryPathInContext($linkSpecifier, $contextDir, \@paths)) ne
			""
			|| ($bestPath = ExactDirectoryPathNoContext($linkSpecifier, \@paths)) ne "")
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
			for (my $i = 0 ; $i < @partialPathParts ; ++$i)
				{
				if (index($partialPathParts[$i], ':') > 0)    # drive letter
					{
					$partialPathParts[$i] .= '/';
					}
				else
					{
					$partialPathParts[$i] = '/' . $partialPathParts[$i] . '/';
					}
				}
			if (
				(
					$bestPath = RelaxedDirectoryPathInContext(
						$linkSpecifier, $contextDir, \@paths, \@partialPathParts
					)
				) ne ""
				|| ($bestPath = RelaxedDirectoryPathNoContext(\@paths, \@partialPathParts)) ne
				""
				)
				{
				$result = $bestPath;
				}
			}
		}    # directory name is associated with at least one known full path
	
	return($result);
}

# Load %FileNameForFullPath.
# Eg $FileNameForFullPath{C:/dir1/dir2/dir3/file.txt} = 'file.txt';
sub InitFullPathList {
	my ($filePath, $fileNameForFullPathH) = @_;    # typ. CVal('FILEWATCHERDIRECTORY') . CVal('FULL_PATH_LIST_NAME')

	my $pathCount = LC_LoadKeyTabValueHashFromFile($fileNameForFullPathH, $filePath,
		"file names for full paths");

	return ($pathCount);
}

# From entries in %FileNameForFullPath build a "reverse" hash %FullPathsForFileName
# and also %FullDirectoryPathsForDirName for directory matching.
sub BuildFullPathsForFileName {
	my ($fileNameForFullPathH) = @_;

	keys %$fileNameForFullPathH;    # reset iterator
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
	for (my $i = 0 ; $i < @dirNames ; ++$i)
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

# Load additional fullpaths2.out etc to %FileNameForFullPath, create new partial path entries too.
sub LoadIncrementalDirectoryFinderLists {
	my ($filePath, $fileNameForFullPathH) = @_;    # typ. CVal('FILEWATCHERDIRECTORY') . CVal('FULL_PATH_LIST_NAME')
	$filePath =~ m!^(.+?)(\.\w+)$!;
	my $base     = $1;
	my $ext      = $2;
	my $num      = 2;
	my $fragPath = $base . $num . $ext;
	while (-f $fragPath)
		{
		my %rawFileNameForFullPath;
		my $pathCount = LC_LoadKeyTabValueHashFromFile(\%rawFileNameForFullPath, $fragPath,
			"more file names for full paths");
		if ($pathCount)
			{
			my %newFileNameForFullPath;
			keys %rawFileNameForFullPath;

			# Prepare to add files that aren't currently being tracked.
			while (my ($path, $fileName) = each %rawFileNameForFullPath)
				{
				if (!defined($fileNameForFullPathH->{$path}))
				#if (!FullPathIsKnown($path))
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
					$fileNameForFullPathH->{$path} = $newFileNameForFullPath{$path};
					}
				BuildFullPathsForFileName(\%newFileNameForFullPath);
				}
			}
		++$num;
		$fragPath = $base . $num . $ext;
		}
}

sub BestMatchingFullPath {
	my ($linkSpecifier, $contextDir) = @_;
	my $result = '';
	
	$linkSpecifier = lc($linkSpecifier);
	$linkSpecifier =~ s!\\!/!g;

	if ($linkSpecifier !~ m!^//!)
		{
		$linkSpecifier =~ s!^/!!;
		}
	
	my $fileName = basename($linkSpecifier);
	
	if (defined($FullPathsForFileName{$fileName}))
		{
		my $allpaths = $FullPathsForFileName{$fileName};
		my @paths;
		if ($allpaths =~ m!\|!)    # more than one candidate full path
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
		if (   ($bestPath = ExactPathInContext($linkSpecifier, $contextDir, \@paths)) ne ""
			|| ($bestPath = ExactPathNoContext($linkSpecifier, \@paths)) ne "")
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
			pop(@partialPathParts);    # Remove file name (last entry).
				# Tack some forward slashes back on for accurate matching with index().
			for (my $i = 0 ; $i < @partialPathParts ; ++$i)
				{
				if (index($partialPathParts[$i], ':') > 0)    # drive letter
					{
					$partialPathParts[$i] .= '/';
					}
				else
					{
					$partialPathParts[$i] = '/' . $partialPathParts[$i] . '/';
					}
				}

			if (
				(
					$bestPath = RelaxedPathInContext(
						$linkSpecifier, $contextDir, \@paths, \@partialPathParts
					)
				) ne ""
				|| ($bestPath = RelaxedPathNoContext(\@paths, \@partialPathParts)) ne ""
				)
				{
				$result = $bestPath;
				}
			}
		}    # file name is associated with at least one known full path
		
	return ($result);
}

sub ExactPathInContext {
	my ($linkSpecifier, $contextDir, $pathsA) = @_;
	my $linkSpecifierLength = length($linkSpecifier);
	my $numPaths            = @$pathsA;
	my $bestScore           = 0;                      # context/full path overlap, higher is better
	my $bestSlashScore      = 999;                    # Slash count in leftoverPath, lower is better
	my $bestIdx             = -1;

	for (my $i = 0 ; $i < $numPaths ; ++$i)
		{
		my $testPath = $pathsA->[$i];
		my $matchPos;

		if (($matchPos = index($testPath, $linkSpecifier)) > 0)
			{
			my $testLength = length($testPath);
			# We want a full match on the $linkSpecifier within $testPath, and to avoid a match
			# against a partial directory name we need the char preceding the match to be a slash.
			# (Eg avoid a match of test/file.txt against c:/stuff/bigtest/file.txt)
			if ($testLength == $matchPos + $linkSpecifierLength
				&& substr($testPath, $matchPos - 1, 1) eq '/')
				{
				my $currentScore = LeftOverlapLength($contextDir, $testPath);

				if ($bestScore < $currentScore)
					{
					my $leftoverPath      = substr($testPath, $currentScore);
					my $currentSlashScore = $leftoverPath =~ tr!/!!;
					$bestSlashScore = $currentSlashScore;
					$bestScore      = $currentScore;
					$bestIdx        = $i;
					}
				elsif ($bestScore > 0 && $bestScore == $currentScore)
					{
					my $leftoverPath = substr($testPath, $currentScore);
					my $currentSlashScore =
						$leftoverPath =~ tr!/!!;    # Count directory slashes in $leftoverPath
						# Fewer slashes means $testPath is closer to context directory.
					if ($bestSlashScore > $currentSlashScore)
						{
						$bestSlashScore = $currentSlashScore;
						$bestIdx        = $i;
						}
					elsif ($bestSlashScore == $currentSlashScore)    # Prefer shorter path
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

	return ($result);
}

sub ExactPathNoContext {
	my ($linkSpecifier, $pathsA) = @_;
	my $linkSpecifierLength = length($linkSpecifier);
	my $numPaths            = @$pathsA;
	my $bestSlashScore      = 999;
	my $bestIdx             = -1;

	for (my $i = 0 ; $i < $numPaths ; ++$i)
		{
		my $testPath = $pathsA->[$i];
		my $matchPos;
		if (($matchPos = index($testPath, $linkSpecifier)) > 0)
			{
			my $testLength = length($testPath);
			if ($testLength == $matchPos + $linkSpecifierLength
				&& substr($testPath, $matchPos - 1, 1) eq '/')
				{
				my $currentSlashScore = $testPath =~ tr!/!!;
				if ($bestSlashScore > $currentSlashScore)
					{
					$bestSlashScore = $currentSlashScore;
					$bestIdx        = $i;
					}
				}
			}
		}

	my $result = "";
	if ($bestIdx >= 0)
		{
		$result = $pathsA->[$bestIdx];
		}

	return ($result);
}

sub RelaxedPathInContext {
	my ($linkSpecifier, $contextDir, $pathsA, $partialPathPartsA) = @_;
	my $numPaths       = @$pathsA;
	my $bestScore      = 0;
	my $bestSlashScore = 999;
	my $bestIdx        = -1;

	for (my $i = 0 ; $i < $numPaths ; ++$i)
		{
		my $testPath = $pathsA->[$i];

		if (AllPartialPartsAreInTestPath($partialPathPartsA, $testPath))
			{
			my $currentScore = LeftOverlapLength($contextDir, $testPath);
			if ($bestScore < $currentScore)
				{
				my $leftoverPath      = substr($testPath, $currentScore);
				my $currentSlashScore = $leftoverPath =~ tr!/!!;
				$bestSlashScore = $currentSlashScore;
				$bestScore      = $currentScore;
				$bestIdx        = $i;
				}
			elsif ($bestScore > 0 && $bestScore == $currentScore)
				{
				my $leftoverPath = substr($testPath, $currentScore);
				my $currentSlashScore =
					$leftoverPath =~ tr!/!!;    # Count directory slashes in $leftoverPath
					# Fewer slashes means $testPath is closer to context directory.
				if ($bestSlashScore > $currentSlashScore)
					{
					$bestSlashScore = $currentSlashScore;
					$bestIdx        = $i;
					}
				elsif ($bestSlashScore == $currentSlashScore)    # Prefer shorter path
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

	return ($result);
}

sub RelaxedPathNoContext {
	my ($pathsA, $partialPathPartsA) = @_;
	my $numPaths       = @$pathsA;
	my $bestSlashScore = 999;
	my $bestIdx        = -1;

	for (my $i = 0 ; $i < $numPaths ; ++$i)
		{
		my $testPath = $pathsA->[$i];
		if (AllPartialPartsAreInTestPath($partialPathPartsA, $testPath))
			{
			my $currentSlashScore = $testPath =~ tr!/!!;
			if ($bestSlashScore > $currentSlashScore)
				{
				$bestSlashScore = $currentSlashScore;
				$bestIdx        = $i;
				}
			}
		}

	my $result = "";
	if ($bestIdx >= 0)
		{
		$result = $pathsA->[$bestIdx];
		}

	return ($result);
}

sub AllPartialPartsAreInTestPath {
	my ($partialPathPartsA, $testPath) = @_;
	my $result = 1;

	for (my $i = 0 ; $i < @$partialPathPartsA ; ++$i)
		{
		if (index($testPath, $partialPathPartsA->[$i]) < 0)
			{
			$result = 0;
			last;
			}
		}

	return ($result);
}

# Just a punt, ExactPathInContext() above works for directories too.
sub ExactDirectoryPathInContext {
	my ($linkSpecifier, $contextDir, $pathsA) = @_;
	return (ExactPathInContext($linkSpecifier . '/', $contextDir, $pathsA));
}

# ExactPathNoContext() above works for directories too.
sub ExactDirectoryPathNoContext {
	my ($linkSpecifier, $pathsA) = @_;
	return (ExactPathNoContext($linkSpecifier . '/', $pathsA));
}

sub RelaxedDirectoryPathInContext {
	my ($linkSpecifier, $contextDir, $pathsA, $partialPathPartsA) = @_;
	my $bestPath =
		RelaxedPathInContext($linkSpecifier . '/', $contextDir, $pathsA, $partialPathPartsA);

	if ($bestPath eq '')
		{
		my $numPartialParts = @$partialPathPartsA;
		for (my $i = 0 ; $i < $numPartialParts - 1 ; ++$i)
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
				if ($allpaths =~ m!\|!)    # more than one candidate full path
					{
					@paths = split(/\|/, $allpaths);
					}
				else
					{
					push @paths, $allpaths;
					}
				$bestPath = RelaxedPathInContext($linkSpecifier . '/',
					$contextDir, \@paths, $partialPathPartsA);
				if ($bestPath ne '')
					{
					last;
					}
				}
			}
		}

	return ($bestPath);
}

# See comment just above for RelaxedDirectoryPathInContext.
sub RelaxedDirectoryPathNoContext {
	my ($pathsA, $partialPathPartsA) = @_;
	my $bestPath = RelaxedPathNoContext($pathsA, $partialPathPartsA);

	if ($bestPath eq '')
		{
		my $numPartialParts = @$partialPathPartsA;
		for (my $i = 0 ; $i < $numPartialParts - 1 ; ++$i)
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
				if ($allpaths =~ m!\|!)    # more than one candidate full path
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

	return ($bestPath);
}

}    ##### Directory list

use ExportAbove;
1;

