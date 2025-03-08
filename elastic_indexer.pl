# elastic_indexer.pl: go through directories listed in
# (your Intramine folder)\data\search_directories.txt,
# ask Elasticsearch to add files to the "intramine" full text index, and update (add to) a list
# of full paths to all files seen, whether indexed or not.
# NOTE this program does NOT empty out or destroy/recreate the main "intramine" index.
# If you want to blow away the existing index and fill in a new one, first run
# elasticsearch_init_index.pl, then come back and run this program.
# You do need to run this at least once to get a full index and list of files going.
# Normally if Elasticsearch and IntraMine are running, the Elasticsearch index will be
# right up to date. The File Watcher service will pick up new or changed files
# in the directories that it is watching, and intramine_filewatcher.pl (which runs when you start
# IntraMine) will pass new and changed files over to Elasticsearch for indexing.
# After the first run, if you later want to add one or more directories to Elasticsearch, replace
# the contents of data\search_directories.txt with paths to the additional directories and then
# run this program again. Your existing search index, and list of full paths corresponding to
# files in your index folder, will be added to rather than replaced. Or, since a full reindex takes
# only an at most, you could just alter your search_directories.txt file and then run
# elasticsearch_init_index.pl before running this prog, as mentioned above.
#
# NOTE normally you should run bats/IM_INIT_INDEX.bat with Administrator privileges
# instead of running this program directly. Or run IM_ADD_INDEX.bat (as admin) to add a directory
# to indexing. Both require listing the directories in data/search_directories.txt beforehand.
# See Documentation/Configuring folders to index and monitor.html for details.
#
# File extensions for files that will be indexed are in ext.pm. To allow indexing of
# files without an extension, set ES_INDEX_NO_EXTENSION in data/intramine_config.txt to 1.
# Default is 0, skip them. Setting it to 1 is not well tested.
#
# Command line (see bats/elastic_stop_INIT_rebuild_start.bat etc for a better way to run this
# if you want to completely rebuild your index): 
# perl C:\perlprogs\mine\elastic_indexer.pl

use strict;
use utf8;
use FileHandle;
use Win32::RunAsAdmin qw(force);
use File::Find;
use Math::SimpleHisto::XS;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use intramine_config;
use elasticsearch_bulk_indexer;
use reverse_filepaths;
use win_wide_filepaths; # for win_wide_filepaths.pm#DeepFindFileWide()
use ext;				# For ext.pm#EndsWithTextExtension().

# If called by bats/IM_INIT_INDEX.bat there will be an argument "-addTestDoc"
# meaning add a test document or two, for later testing of Search if desired - see
# test_programs/test_Search.pl.
my $AddTestDocuments = shift@ARGV;
$AddTestDocuments ||= 0;
if ($AddTestDocuments =~ m!addTestDoc!i)
	{
	$AddTestDocuments = 1;
	}

# Unbuffer output, in case we are being called from the Intramine Cmd page.
select((select(STDOUT), $|=1)[0]);

LoadConfigValues();				# intramine_config.pm

# Load any existing full path list into memory.
my $FileWatcherDir = CVal('FILEWATCHERDIRECTORY');
my $fullFilePathListPath = $FileWatcherDir . CVal('FULL_PATH_LIST_NAME'); # .../fullpaths.out
InitFullPathList($fullFilePathListPath);
LoadIncrementalFullPathLists($fullFilePathListPath);

# While we're indexing, count up number of files in various size ranges.
InitFileSizeBinning();

# Hack, tired of indexing hundreds of log files, so optionally skip any
# file with a .log or .out extension. See FileShouldBeIndexed() below.
my $SKIPLOGFILES = 1;

# Optionally allow files with no extension.
# !!NOTE!! Setting ES_INDEX_NO_EXTENSION to 1 is not well tested!
my $IndexIfNoExtension = CVal('ES_INDEX_NO_EXTENSION');

# Load up list of directories to index. Default location is data/search_directories.txt.
my @DirectoriesToIndex;
my @DirectoriesToIgnore;
my $dirCount = LoadDirectoriesToIndex(\@DirectoriesToIndex, \@DirectoriesToIgnore);
if (!$dirCount)
	{
	print("No directories were found for indexing.\n");
	exit(0);
	}

my %myFileNameForPath;	# for Elasticsearch indexing
my %rawPathList; 		# for full path List (used for auto linking)
my %rawImagePathList;	# ditto, just images
my $numDirs = @DirectoriesToIndex;

my @files;
my @folders;

for (my $i = 0; $i < $numDirs; ++$i)
	{
	# _INTRAMINE_ stands for the dir that holds this program, and by default all IntraMine files.
	if ($DirectoriesToIndex[$i] eq '_INTRAMINE_')
		{
		$DirectoriesToIndex[$i] = path($0)->absolute->parent->stringify;
		}
	$DirectoriesToIndex[$i] =~ s![\\]!/!g;
	if ($DirectoriesToIndex[$i] !~ m!/$!)
		{
		$DirectoriesToIndex[$i] .= '/';
		}
	
	Output("Getting paths to |$DirectoriesToIndex[$i]|\n");
	
	# win_wide_filepaths.pm#DeepFindFileWide()
	DeepFindFileWide($DirectoriesToIndex[$i], \@files, \@folders);
	}
	
for (my $i = 0; $i < @files; ++$i)
	{
	my $pathForwardSlashes = $files[$i];
	$pathForwardSlashes =~ s![\\]!/!g;
	$pathForwardSlashes =~ m!([^/]+)$!;
	my $sourceFileName = $1;
	
	my $lcpathForwardSlashes = $pathForwardSlashes;
	$lcpathForwardSlashes = lc($lcpathForwardSlashes);
	# Indexing. Optionally skip .log files. 
	if (FileShouldBeIndexed($pathForwardSlashes, \@DirectoriesToIgnore))
		{
		$myFileNameForPath{$pathForwardSlashes} = $sourceFileName;
		$rawPathList{$lcpathForwardSlashes} = lc($sourceFileName);
		}
	elsif (FileIsImageInGoodLocation($pathForwardSlashes, \@DirectoriesToIgnore))
		{
		$rawImagePathList{$lcpathForwardSlashes} = lc($sourceFileName);
		}
	}

# Connect to Elasticsearch.
my $esIndexName = CVal('ES_INDEXNAME'); 	# default 'intramine'
my $esTextIndexType = CVal('ES_TEXTTYPE'); 	# default 'text'
my $maxFileSizeKB = CVal('ELASTICSEARCH_MAXFILESIZE_KB');
my $ElasticIndexer = elasticsearch_bulk_indexer->new($esIndexName, $esTextIndexType, $maxFileSizeKB);

# Add our test document to index, and list of file paths.
if ($AddTestDocuments)
	{
	AddTestDocuments($ElasticIndexer, \%rawPathList);
	}

# Run through all files, load and index them into Elasticsearch.
Output("Indexing files\n");
my $numDocs = keys %myFileNameForPath;
my $docCounter = 0;
my $numDocsIndexed = 0;
my $numDocsNotIndexed = 0;
foreach my $fullPath (sort keys %myFileNameForPath)
	{
	if (($docCounter++%100) == 0)
		{
		Output("  $docCounter / $numDocs... $fullPath\n");
		}
#	if (($docCounter%500) == 0)
#		{
		#Output("  FLUSHING, and waiting a few...\n");
		#$ElasticIndexer->Flush();	
		#sleep(5);
#		}
	# Note $fileSizeBytes is always set, whether or not added to index.
	my $fileSizeBytes = 0;
	my $wasIndexed = $ElasticIndexer->AddDocumentToIndex($myFileNameForPath{$fullPath},
														 $fullPath, \$fileSizeBytes);
	
	if ($wasIndexed)
		{
		++$numDocsIndexed;
		}
	else
		{
		++$numDocsNotIndexed;
		RememberNonIndexedFile($fullPath, $fileSizeBytes);
		}
	AddToFileSizeBin($fileSizeBytes);
	}

if ($numDocs)
	{
	Output("\nElasticSearch final flush...\n");
	$ElasticIndexer->Flush();
	sleep(1);
	Output("$numDocsIndexed out of $numDocs files indexed, $numDocsNotIndexed skipped due to being too large or file errors.\n");
	}
else
	{
	Output("\nODD, no documents were found for indexing!\n");
	}

# Save file listing full paths to all files found in indexed directories,
# for use by intramine_fileserver.pl etc when turning file paths into links.
# (intramine_filewatcher.pl runs as part of IntraMine to keep the list up to date,
# using changes reported by File Watcher.)
Output("Saving full path list...\n");
# Add all found paths to reverse_filepath.pm's master hash of paths.
AddIncrementalNewPaths(\%rawPathList);
AddIncrementalNewPaths(\%rawImagePathList);
# reverse_filepaths.pm#ConsolidateFullPathLists() assumes the path list is in memory
# (which it is at this point), saves it over the main full paths file, and deletes any
# secondary file that was holding additional paths.
# To get here, we initially loaded paths from the
# main and secondary files, and added in the new paths found here. So
# Consolidate will do the right thing, even though the name isn't quite right
# (mainly it's used by intramine_filewatcher.pl when IntraMine is running,
# to consolidate the two full path files during the wee hours of the night).
ConsolidateFullPathLists(1); # 1 == force consolidation

# Dump a table of file counts in various size ranges.
DumpFileSizeBinCountsAndLargeFiles();

Output("\nDone. Full path list is in |$fullFilePathListPath|.\n");


############## subs
sub Output {
	my ($txt) = @_;
	print("$txt");
	}

# Load array with directories to index. Default file is data/search_directories.txt.
# If it's not the default, then only you know where it is:)
sub LoadDirectoriesToIndex {
	my ($directoriesToIndexA, $directoriesToIgnoreA) = @_;
	my $configFilePath = FullDirectoryPath('ELASTICSEARCHDIRECTORIESPATH');
	my $dirCount = 0;
	
	if (-f $configFilePath)
		{
		my @dummyMonitorArray;
		my $haveSome = LoadSearchDirectoriesToArrays($configFilePath, $directoriesToIndexA,
						\@dummyMonitorArray, $directoriesToIgnoreA); # intramine_config.pm#LoadSearchDirectoriesToArrays()
		
		$dirCount = @$directoriesToIndexA;

		for (my $i = 0; $i < $dirCount; ++$i)
			{
			$directoriesToIndexA->[$i] =~ s!\\!/!g;
			}
		}
	else
		{
		die("ERROR, |$configFilePath| not found!");
		}
		
	return($dirCount);
	}

# True if file exists and isn't a "nuisance" file and has a good extension.
sub FileShouldBeIndexed {
	my ($fullPath, $directoriesToIgnoreA) = @_;
	my $result = 0;
	if (   $fullPath !~ m!/\.!
	  && !($SKIPLOGFILES && $fullPath =~ m!\.(log|out)$!i)
	  &&   $fullPath !~ m!/(temp|junk)/!i )
		{
		if (EndsWithTextExtension($fullPath)
          || ($IndexIfNoExtension && $fullPath !~ m!\.\w+$!)  )
        	{
        	$result = 1;
        	}
		}
	
	my $numIgnoreDirs = @$directoriesToIgnoreA;
	for (my $i = 0; $i < $numIgnoreDirs; ++$i)
		{
		if (index($fullPath, $directoriesToIgnoreA->[$i]) == 0)
			{
			$result = 0;
			last;
			}
		}

	return($result);
	}

sub FileIsImageInGoodLocation {
	my ($fullPath, $directoriesToIgnoreA) = @_;
	my $result = 0;

	if (EndsWithImageExtension($fullPath))
		{
		$result = 1;
		}

	my $numIgnoreDirs = @$directoriesToIgnoreA;
	for (my $i = 0; $i < $numIgnoreDirs; ++$i)
		{
		if (index($fullPath, $directoriesToIgnoreA->[$i]) == 0)
			{
			$result = 0;
			last;
			}
		}

	return($result);
	}

# Add a text file and a .cpp file for index and link testing.
sub AddTestDocuments {
	my ($es, $rawPathListH) = @_;
	my $testProgDir = FullDirectoryPath('TEST_PROGRAM_DIR');
	
	my $testDocName = CVal('ES_INDEX_TEST_FILE_NAME');
	my $testDocPath = $testProgDir . $testDocName;
	AddOneTestDocument($testDocName, $testDocPath, $es, $rawPathListH);

	$testDocName = CVal('ES_INDEX_TEST_FILE_NAME_2');
	$testDocPath = $testProgDir . $testDocName;
	AddOneTestDocument($testDocName, $testDocPath, $es, $rawPathListH);
	}

sub AddOneTestDocument {
	my ($testDocName, $testDocPath, $es, $rawPathListH) = @_;

	if (FileOrDirExistsWide($testDocPath) == 1)
		{
		my $fileSizeBytes = 0;
		my $wasIndexed = $es->AddDocumentToIndex($testDocName, $testDocPath, \$fileSizeBytes);
		$testDocPath = lc($testDocPath);
		$rawPathListH->{$testDocPath} = lc($testDocName);
		}
	else
		{
		print("ERROR (will continue), |$testDocPath| was not found on disk. test_Search.pl and other test programs might fail if run later.\n");
		}
	}

{ ##### File sizes histogram
# Of occasional interest, just how many big files are in the source directories?
# Typically source files over 800 KB are tables of such things as Unicode character names
# and auto-generated headers.
# Large files (over 800 KB) can really slow down Elasticsearch searching, so they are best skipped.
# intramine_config.txt ELASTICSEARCH_MAXFILESIZE_KB determines maximum file size for indexing,
# anything larger isn't indexed.
my $MaxKB;
my $NumBins;
my $hist;			# bins for 0..2000 KB (almost all files end up in the first bin, 0-100 KB)
my $SmallMaxKB;
my $SmallNumBins;
my $smallHist;		# bins for 0..100 KB (a finer breakdown for the vast majority of files)

# Track largest files, the ones not indexed.
my %FileSizeForFullPath;

# 20 bins in 100 KB increments up to 2 MB, indexed 0..19.
sub InitFileSizeBinning {
	$MaxKB = 2000;
	$NumBins = 20;
	$hist = Math::SimpleHisto::XS->new(
    	min => 0, max => $MaxKB, nbins => $NumBins
  		);
  	
  	$SmallMaxKB = 100;
  	$SmallNumBins = 10;
	$smallHist = Math::SimpleHisto::XS->new(
    	min => 0, max => $SmallMaxKB, nbins => $SmallNumBins
  		);
	}

sub AddToFileSizeBin {
	my ($fileSizeBytes) = @_;
	my $fileSizeKiloB = $fileSizeBytes / 1000;
	$hist->fill($fileSizeKiloB);
	if ($fileSizeKiloB <= 100)
		{
		$smallHist->fill($fileSizeKiloB);
		}
	}

sub DumpFileSizeBinCountsAndLargeFiles {
	my $FileWatcherDir = CVal('FILEWATCHERDIRECTORY');
	my $fileSizePath = $FileWatcherDir . CVal('FILESIZE_BIN_NAME'); # .../filesizes.out
	my $fileH = FileHandle->new("> $fileSizePath")
		or die("FILE ERROR could not make $fileSizePath! (Index is not affected.)");
	
	# 1 Coarse file counts in 100 KB bins.
	my $values = $hist->all_bin_contents();
	my $bottoms = $hist->bin_lower_boundaries();
	my $tops = $hist->bin_upper_boundaries();
	my $underflowCount = $hist->underflow();
	my $overflowCount = $hist->overflow();
	my $numBins = @$values;
	
	if ($underflowCount > 0)
		{
		print $fileH "LOGIC ERROR we have Underflow: |$underflowCount| files less than zero bytes in size (doh)\n";
		}
	
	print $fileH "TABLE 1 Bin Counts\n";
	print $fileH "Bin\tMin KB\tMax KB\tCount\n";
	for (my $i = 0; $i < $numBins; ++$i)
		{
		print $fileH "$i\t$bottoms->[$i]\t$tops->[$i]\t$values->[$i]\n";
		}
	print $fileH "$numBins\t$MaxKB+\t-\t$overflowCount\n";
	
	# 2 Fine file counts in 10 KB bins for the 0..100 KB range.
	$values = $smallHist->all_bin_contents();
	$bottoms = $smallHist->bin_lower_boundaries();
	$tops = $smallHist->bin_upper_boundaries();
	$underflowCount = $smallHist->underflow();
	$overflowCount = $smallHist->overflow();
	$numBins = @$values;
	print $fileH "\n\nTABLE 2 Bin Counts for 0 to 100 KB\n";
	print $fileH "Bin\tMin KB\tMax KB\tCount\n";
	for (my $i = 0; $i < $numBins; ++$i)
		{
		print $fileH "$i\t$bottoms->[$i]\t$tops->[$i]\t$values->[$i]\n";
		}
	if ($overflowCount)
		{
		print $fileH "$numBins\t$SmallMaxKB+\t-\t$overflowCount\n";
		}
	
	# 3 List of files not indexed, typically due to being above the $maxFileSizeKB cutoff.
	print $fileH "\n\nTABLE 3 Files not indexed, by size\nPath\tKB\n";
	foreach my $path (sort {$FileSizeForFullPath{$a} <=> $FileSizeForFullPath{$b}} keys %FileSizeForFullPath)
		{
		print $fileH "$path\t$FileSizeForFullPath{$path}\n";
		}
	close($fileH);
	Output("List of skipped files is in |$fileSizePath|\n");
	}

sub RememberNonIndexedFile {
	my ($path, $fileSizeBytes) = @_;
	my $fileSizeKiloB = $fileSizeBytes / 1000;
	$FileSizeForFullPath{$path} = $fileSizeKiloB;
	}
} ##### File sizes histogram
