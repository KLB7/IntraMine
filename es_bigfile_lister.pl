# es_bigfile_lister.pl: Using dir list in data\search_directories.txt, list all files
# larger than a certain number of kbytes, in rough order by increasing size.
# Results are in C:/fwws/temp_large_file_dump.txt.
# This can be of interest in deciding the size cutoff to use when indexing files with Elasticsearch.
# See 'ELASTICSEARCH_MAXFILESIZE_KB' in data\intramine_config.txt
# for the current value (800 KB or so).

# perl C:\perlprogs\mine\es_bigfile_lister.pl maxFileSizeKB
# perl C:\perlprogs\mine\es_bigfile_lister.pl 800

use strict;
use utf8;
use FileHandle;
use File::Find;
use Math::SimpleHisto::XS;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use intramine_config;

my $MaxFileSizeKBArg = shift @ARGV;
die("Please supply max file size KB as arg: files over that size will be listed.")
	if (!defined($MaxFileSizeKBArg));

my $Extensions =
'(p[lm]|pod|txt|md|js|css|cpp?|c|cc|h|go|bat|html?|xml|log|out|qdoc|textile|cs|vb|java|class|py|php)';
# Optionally allow files with no extension.
my $IndexIfNoExtension = 0;
# Hack, tired of indexing hundreds of log files, so optionally skip any
# file with a .log or .out extension. See DoOne() below.
my $SKIPLOGFILES = 1;

LoadConfigValues();
InitFileSizeBinning();

# Load up list of directories to check.
my @DirectoriesToIndex;
my @DirectoriesToIgnore;
LoadDirectoriesToIndex();
my %myFileNameForPath;    # for indexing
my %rawPathList;          # for full path List
my $numDirs = @DirectoriesToIndex;
for (my $i = 0 ; $i < $numDirs ; ++$i)
	{
	if ($DirectoriesToIndex[$i] eq
		'_INTRAMINE_') # meaning the dir that holds this program, and by default all IntraMine files
		{
		$DirectoriesToIndex[$i] = path($0)->absolute->parent->stringify;
		}
	Output("Getting paths to $DirectoriesToIndex[$i]...\n");
	finddepth(\&DoOne, $DirectoriesToIndex[$i]);
	}

Output("Indexing files\n");
my $numDocs           = keys %myFileNameForPath;
my $docCounter        = 0;
my $numDocsIndexed    = 0;
my $numDocsNotIndexed = 0;
foreach my $fullPath (sort keys %myFileNameForPath)
	{
	if (($docCounter++ % 100) == 0)
		{
		Output("  $docCounter / $numDocs... $fullPath\n");
		}
	my (
		$dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
		$size, $atime, $mtime, $ctime, $blksize, $blocks
	) = stat $fullPath;

	AddToFileSizeBin($fullPath, $size);
	}

DumpFileSizeBinCountsAndLargeFiles();
print("Done.\n");

######### subs
sub Output {
	my ($txt) = @_;
	print("$txt");
}

sub LoadDirectoriesToIndex {
	my $configFilePath = FullDirectoryPath('ELASTICSEARCHDIRECTORIESPATH');
	my $dirCount       = 0;

	if (-f $configFilePath)
		{
		my @dummyMonitorArray;
		my $haveSome = LoadSearchDirectoriesToArrays($configFilePath, \@DirectoriesToIndex,
			\@dummyMonitorArray, \@DirectoriesToIgnore);

		$dirCount = @DirectoriesToIndex;

		if (!$dirCount)
			{
			die("ERROR, no directories found in |$configFilePath|\n");
			}
		}
	else
		{
		die("ERROR, |$configFilePath| not found!");
		}

	return ($dirCount);
}

# Called by finddepth() above for all files.
sub DoOne {
	my $sourceFileName     = $_;
	my $sourceFileFullPath = $File::Find::name;
	if ($_ eq "." || !-f $sourceFileFullPath)
		{
		;    # not a file
		return;
		}
	# else it's a file.
	else
		{
		# Full path list. Set %rawPathList for all files, eg to pick up folders that are all images.
		my $pathForwardSlashes = lc($sourceFileFullPath);
		$pathForwardSlashes =~ s![\\]!/!g;
		$rawPathList{$pathForwardSlashes} = lc($sourceFileName);
		# Indexing. Optionally skip .log files.
		if (FileShouldBeIndexed($pathForwardSlashes))
			{
			if (!ShouldIgnoreFile($pathForwardSlashes))
				{
				$myFileNameForPath{$pathForwardSlashes} = $sourceFileName;
				}
			}
		}
}

# True if file exists and isn't a "nuisance" file and has a good extension.
sub FileShouldBeIndexed {
	my ($fullPath) = @_;
	my $result = 0;
	if (   $fullPath !~ m!/\.!
		&& !($SKIPLOGFILES && $fullPath =~ m!\.(log|out)$!i)
		&& $fullPath !~ m!/(temp|junk)/!i)
		{
		if (EndsWithTextExtension($fullPath)
			|| ($IndexIfNoExtension && $fullPath !~ m!\.\w+$!))
			{
			$result = 1;
			}
		}

	return ($result);
}

# Ignore file path if it starts with path to a folder to ignore, as
# listed in data/search_directories.txt. Comparisons are done
# in lower case with forward slashes only.
sub ShouldIgnoreFile {
	my ($fullPath) = @_;    # lc, / only
							#$fullPath = lc($fullPath);
							#$fullPath =~ s!\\!/!g;
	my $result     = 0;

	for (my $i = 0 ; $i < @DirectoriesToIgnore ; ++$i)
		{
		if (index($fullPath, $DirectoriesToIgnore[$i]) == 0)
			{
			$result = 1;
			last;
			}
		}

	return ($result);
}

{ ##### File sizes dump large file paths
# Of occasional interest, just how many big files are in the source directories?
# Typically source files over 1 MB are tables of such things as Unicode character names.
# Large files (over ~ 1MB) can really slow down Elasticsearch searching, so they are best skipped.
# intramine_config.txt ELASTICSEARCH_MAXFILESIZE_KB determines maximum file size for indexing,
# anything larger isn't indexed.
# See test\test_mathsimplehisto.pl for a test of Math::SimpleHisto::XS.
my $MaxKB;
my $NumBins;
my $hist;         # bins for 0..2000 KB (almost all files end up in the first bin, 0-100 KB)
my $SmallMaxKB;
my $SmallNumBins;
my $smallHist;    # bins for 0..100 KB (a finer breakdown for the vast majority of files)
my $MaxFileSizeKB;

# Track largest files, the ones not indexed.
my %FileSizeForFullPath;

# 20 bins in 100 KB increments up to 2 MB, indexed 0..19.
sub InitFileSizeBinning {
	$MaxKB   = 2000;
	$NumBins = 20;
	$hist    = Math::SimpleHisto::XS->new(
		min   => 0,
		max   => $MaxKB,
		nbins => $NumBins
	);
	$SmallMaxKB   = 100;
	$SmallNumBins = 10;
	$smallHist    = Math::SimpleHisto::XS->new(
		min   => 0,
		max   => $SmallMaxKB,
		nbins => $SmallNumBins
	);
	$MaxFileSizeKB = $MaxFileSizeKBArg;
}

sub AddToFileSizeBin {
	my ($path, $fileSizeBytes) = @_;
	my $fileSizeKiloB = $fileSizeBytes / 1000;
	$hist->fill($fileSizeKiloB);
	if ($fileSizeKiloB <= 100)
		{
		$smallHist->fill($fileSizeKiloB);
		}
	if ($fileSizeKiloB > $MaxFileSizeKB)
		{
		$FileSizeForFullPath{$path} = $fileSizeKiloB;
		}
}

sub DumpFileSizeBinCountsAndLargeFiles {
	my $FileWatcherDir = CVal('FILEWATCHERDIRECTORY');
	my $fileSizePath = $FileWatcherDir . 'temp_large_file_dump.txt';  # .../temp_large_file_dump.txt
	my $fileH        = FileHandle->new("> $fileSizePath")
		or die("FILE ERROR could not make $fileSizePath!");
	my $values         = $hist->all_bin_contents();
	my $bottoms        = $hist->bin_lower_boundaries();
	my $tops           = $hist->bin_upper_boundaries();
	my $underflowCount = $hist->underflow();
	my $overflowCount  = $hist->overflow();
	my $numBins        = @$values;

	if ($underflowCount > 0)
		{
		print $fileH
"LOGIC ERROR we have Underflow: |$underflowCount| files less than zero bytes in size (doh)\n";
		}

	print $fileH "TABLE 1 Bin Counts\n";
	print $fileH "Bin\tMin KB\tMax KB\tCount\n";
	for (my $i = 0 ; $i < $numBins ; ++$i)
		{
		print $fileH "$i\t$bottoms->[$i]\t$tops->[$i]\t$values->[$i]\n";
		}
	print $fileH "$numBins\t$MaxKB+\t-\t$overflowCount\n";

	# 2 Fine file counts in 10 KB bins for the 0..100 KB range.
	$values         = $smallHist->all_bin_contents();
	$bottoms        = $smallHist->bin_lower_boundaries();
	$tops           = $smallHist->bin_upper_boundaries();
	$underflowCount = $smallHist->underflow();
	$overflowCount  = $smallHist->overflow();
	$numBins        = @$values;
	print $fileH "\n\nTABLE 2 Bin Counts for 0 to 100 KB\n";
	print $fileH "Bin\tMin KB\tMax KB\tCount\n";
	for (my $i = 0 ; $i < $numBins ; ++$i)
		{
		print $fileH "$i\t$bottoms->[$i]\t$tops->[$i]\t$values->[$i]\n";
		}
	if ($overflowCount)
		{
		print $fileH "$numBins\t$SmallMaxKB+\t-\t$overflowCount\n";
		}

	# 3 List of files not indexed, typically due to being above the $maxFileSizeKB cutoff.
	print $fileH "\n\nTABLE 3 Large Files, by size\nPath\tKB\n";
	foreach my $path (
		sort {$FileSizeForFullPath{$a} <=> $FileSizeForFullPath{$b}}
		keys %FileSizeForFullPath
		)
		{
		print $fileH "$path\t$FileSizeForFullPath{$path}\n";
		}
	close($fileH);
	Output("List of large files and bin counts is in |$fileSizePath|\n");
}

}    ##### File sizes dump large file paths
