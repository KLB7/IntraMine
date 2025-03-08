# ri.pl: re-index Elasticsearch, and create a new full path list
# based on directories listed in data/search_directories.txt,
# as well as setting directories for File Watcher Utilities to monitor.
# The name is deliberately cryptic, it should only be run
# via the Reindex service. All progress messages are written
# to a file which can then be read by some other program
# (eg the Reindex service).
# This is basically a combination of
# make_filewatcher_config.pl
# elasticsearch_init_index.pl
# elastic_indexer.pl -addTestDoc
# with stop/start of the Linker and Watcher services
# and with progress messages written to a temp file.
# Run as administrator is requested when starting.

# Summary
# Force to Run as admin
# Phase 1, configure File Watcher to watch new list of directories
# Phase 2 init Elasticsearch index and delete full paths list.
# PHASE 3 rebuild the Elasticsearch index and full paths list.
# Stop Linker and Watcher
# PHASE 3 concluded Save the new full paths list
# Restart Linker and Watcher

use strict;
use utf8;
use FileHandle;
use File::Find;
use Math::SimpleHisto::XS;
use IO::Socket;
use Win32::Process;

# For the RunAsAdmin code below
use Win32;
use Cwd;
use Win32::OLE;
use Devel::PL_origargv;

use Search::Elasticsearch;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use intramine_config;
use cmd_output;
use elasticsearch_bulk_indexer;
use reverse_filepaths;
use win_wide_filepaths; # for win_wide_filepaths.pm#DeepFindFileWide()
use ext;	# For ext.pm#EndsWithTextExtension()

# First, force Run as admin.
# Borrowed from Win32::RunAsAdmin,
# the only change is a fifth argument of 0 to ShellExecute
# below around l.77 to suppress the console.
restart() if (!check());

sub check { Win32::IsAdminUser(); }

sub escape_args {
    return '' unless @_;
    my @args = ();
    foreach (@_) {
        my $a = $_;
        $a =~ s/"/\\"/g;
        push @args, $a;
    }
    return '"' . join ('" "', @args) . '"';
}

sub restart {
    my @actual_args = Devel::PL_origargv->get; # Thank you, Anonymous Monk!
    run (shift(@actual_args), shift(@actual_args) . ' ' . escape_args(@actual_args));
    exit;
}

sub run {
    my $shell = Win32::OLE->new("Shell.Application");
    $shell->ShellExecute (shift, shift, shift, 'runas', 0);
}
# End Run as admin.

# Phase 3 wants to know if we should add a test document to the Elasticsearch index.
my $AddTestDocuments = shift@ARGV;
$AddTestDocuments ||= 0;
if ($AddTestDocuments =~ m!addTestDoc!i)
	{
	$AddTestDocuments = 1;
	}

##### PHASE 1 of 3, make File Watcher Utilitites config file.

my $TESTING = 0; # ==1: make fwatcher.xml.txt instead of fwatcher.xml.

select((select(STDOUT), $|=1)[0]); 	# Unbuffer output.

LoadConfigValues('SRVR');			# intramine_config.pm

my $LogDir = FullDirectoryPath('LogDir');
InitCmdOutput($LogDir . 'temp/tempout_' . 'REINDEX' . '.txt');

Output("Starting\n");

# Get our IP, which is saved to disk by IntraMine each time it starts.
my $ServerAddress = CVal('SERVER_ADDRESS');
if ($ServerAddress eq '')
	{
	Output("Error, cannot continue, could not determine IntraMine's IP address!\n");
	WriteDoneAndCloseOutput();
	die("Error no IP address found for IntraMine in config 'SERVER_ADDRESS'.");
	}

my $MainPort = CVal('INTRAMINE_MAIN_PORT');
if ($MainPort eq '')
	{
	Output("Error, cannot continue, could not determine IntraMine's main port!\n");
	WriteDoneAndCloseOutput();
	die("Error no main port found for IntraMine in config 'INTRAMINE_MAIN_PORT'.");
	}

# Stop and start the File Watcher service, to pick up the config changes made here.
# Tell intramine_filewatcher.pl to stop monitoring the File Watcher service
# - monitoring will pick up again when intramine_filewatcher.pl is restarted below.
TellWatcherIgnoreFWWS();
my $startFileWatcherServicePath = FullDirectoryPath('FILEWATCHER_START_SERVICE');
my $stopFileWatcherServicePath = FullDirectoryPath('FILEWATCHER_STOP_SERVICE');
if (!(-f $startFileWatcherServicePath))
	{
	Output("Error, cannot continue, FILEWATCHER_START_SERVICE is incorrect in data/intramine_config.txt\n");
	WriteDoneAndCloseOutput();
	die ("Maintenance error, FILEWATCHER_START_SERVICE is incorrect in data/intramine_config.txt! Expecting path to start_filewatcher_service.bat.")
	}
if (!(-f $stopFileWatcherServicePath))
	{
	Output("Error, cannot continue, FILEWATCHER_STOP_SERVICE is incorrect in data/intramine_config.txt\n");
	WriteDoneAndCloseOutput();
	die ("Maintenance error, FILEWATCHER_STOP_SERVICE is incorrect in data/intramine_config.txt! Expecting path to stop_filewatcher_service.bat.")
	}

my $ConfigFilePath = CVal('FWWS_CONFIG');
if ($ConfigFilePath eq '')
	{
	Output("Error, cannot continue, |FWWS_CONFIG| not found in /data/intramine_config.txt!\n");
	WriteDoneAndCloseOutput();
	die("Error |FWWS_CONFIG| not found in /data/intramine_config.txt");
	}

if ($TESTING)
	{
	$ConfigFilePath .= '.txt';
	}
my $EntryTemplatePath = FullDirectoryPath('FWWS_ENTRY_TEMPLATE');
my $SearchDirectoriesPath = FullDirectoryPath('ELASTICSEARCHDIRECTORIESPATH');

my $batresult = system(1, "\"$stopFileWatcherServicePath\">nul 2>&1");
if ($batresult == -1)
	{
	Output("Error, cannot continue, could not stop the File Watcher service with |$stopFileWatcherServicePath|!\n");
	WriteDoneAndCloseOutput();	
	die("ERROR, could not stop the File Watcher service with |$stopFileWatcherServicePath|!\n");
	}

# Allow a few seconds for File Watcher to stop.
Output("Waiting briefly for File Watcher to stop.\n");
sleep(5);

Output("Making File Watcher Utility config file.\n");
my $EntryCount = MakeConfigFiles($ConfigFilePath, $EntryTemplatePath, $SearchDirectoriesPath);

# And let the dust settle on that, in case the disk gerbil is a bit tired today.
sleep(2);

Output("Starting File Watcher.\n");

$batresult = system(1, "\"$startFileWatcherServicePath\">nul 2>&1");
if ($batresult == -1)
	{
	Output("Error, cannot continue, could not restart the File Watcher service with |$startFileWatcherServicePath|!\n");
	WriteDoneAndCloseOutput();	
	die("ERROR, could not restart the File Watcher service with |$startFileWatcherServicePath|!\n");
	}

Output("$EntryCount directories will be monitored by File Watcher, see |$ConfigFilePath|.\n");

##### PHASE 2, init Elasticsearch index and delete full paths list.
Output("Beginning Elasticsearch index and full path list rebuild.\n");

my $esIndexName = CVal('ES_INDEXNAME'); 	# default 'intramine'
my $esTextIndexType = CVal('ES_TEXTTYPE'); 	# default 'text'
if ($esIndexName eq '' || $esTextIndexType eq '')
	{
	Output("Error, cannot continue, intramine_config.pm does not have values for ES_INDEXNAME and ES_TEXTTYPE!\n");
	WriteDoneAndCloseOutput();	
	die("ERROR, intramine_config.pm does not have values for ES_INDEXNAME and ES_TEXTTYPE!");
	}

my $numShards = CVal('ELASTICSEARCH_NUMSHARDS') + 0;

# See Documentation/Elasticsearch with replicas.txt.
my $numReplicas = CVal('ELASTICSEARCH_NUMREPLICAS') + 0;

# Delete file(s) holding list of full paths to all files in indexed directories.
my $FileWatcherDir = CVal('FILEWATCHERDIRECTORY');
my $fullFilePathListPath = $FileWatcherDir . CVal('FULL_PATH_LIST_NAME'); # .../fullpaths.out

DeleteFullPathListFiles($fullFilePathListPath); # reverse_filepaths.pm

my $e = Search::Elasticsearch->new(nodes => "localhost:9200");

my $response = '';

# Delete IntraMine's Elasticsearch index if it exists.
if ($e->indices->exists(index => $esIndexName))
	{
	$response = $e->indices->delete(
			index => $esIndexName
		);
	ShowResponse($response, "$esIndexName index deletion");
	Output("Pausing for a few seconds to allow deletion to complete.\n");
	sleep(12);
	}
else
	{
	Output("$esIndexName does not exist (yet).\n");
	}

# Create a new empty Elasticsearch index for IntraMine.
$response = $e->indices->create(
	index      => $esIndexName,
	body => {
		settings => {
	       number_of_shards 	=> $numShards,			# default 5
	       number_of_replicas 	=> $numReplicas,		# default 0
	       auto_expand_replicas	=> 'false',				# prevents autocreating unwanted replica(s)
			"analysis" => {
				"analyzer" => {
					"index_analyzer" => {
						"char_filter" 	=> "icu_normalizer",
						"tokenizer" 	=> "icu_tokenizer",
						"filter"    	=> "icu_folding"
					}
				}
			}
		}
	}
);

ShowResponse($response, "$esIndexName index creation");

Output("Finished Elasticsearch index init.\n");

##### PHASE 3 rebuild the Elasticsearch index and full paths list.
InitFullPathList($fullFilePathListPath);
LoadIncrementalFullPathLists($fullFilePathListPath);

# While we're indexing, count up number of files in various size ranges.
InitFileSizeBinning();

# Hack, tired of indexing hundreds of log files, so optionally skip any
# file with a .log or .out extension. See FileShouldBeIndexed() below.
my $SKIPLOGFILES = 1;

# Optionally allow files with no extension.
# !!NOTE!! Setting ES_INDEX_NO_EXTENSION to 1 is COMPLETELY UNTESTED!
my $IndexIfNoExtension = CVal('ES_INDEX_NO_EXTENSION');

# Load up list of directories to index. Default location is data/search_directories.txt.
my @DirectoriesToIndex;
my @DirectoriesToIgnore;
my $dirCount = LoadDirectoriesToIndex(\@DirectoriesToIndex, \@DirectoriesToIgnore);
if (!$dirCount)
	{
	Output("No directories were found for indexing.\n");
	WriteDoneAndCloseOutput();
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
	# _INTRAMINE_ stands for the dir that holds this program, and all IntraMine files.
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
	if (FileShouldBeIndexed($lcpathForwardSlashes, \@DirectoriesToIgnore))
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
#my $esIndexName = CVal('ES_INDEXNAME'); 	# default 'intramine'
#my $esTextIndexType = CVal('ES_TEXTTYPE'); 	# default 'text'
my $maxFileSizeKB = CVal('ELASTICSEARCH_MAXFILESIZE_KB');
my $ElasticIndexer = elasticsearch_bulk_indexer->new($esIndexName, $esTextIndexType, $maxFileSizeKB);

# Add our test document to index, and list of file paths.
if ($AddTestDocuments)
	{
	AddTestDocuments($ElasticIndexer, \%rawPathList);
	}

# Run through all files, load and index them into Elasticsearch.
Output("File list gathered, indexing files.\n");
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
#	if (($docCounter%10000) == 0)
#		{
		#Output("  FLUSHING, and waiting five seconds...\n");
		#my $flushResult = $ElasticIndexer->Flush();
		#Output("  Flush result: |$flushResult|\n");
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

	my $healthResult = $ElasticIndexer->ClusterHealth();
	Output("Elasticsearch cluster Health: |$healthResult|\n");
	}
else
	{
	Output("\nODD, no documents were found for indexing!\n");
	}

# Stop services that rely on the full paths list.
Output("Briefly stopping Linker and Watcher services.\n");
StopLinkerAndWatcherServices();

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

Output("\nIndexing complete. Full path list is in |$fullFilePathListPath|.\n");

# Full paths list has been recreated, so start up stopped services.
StartLinkerAndWatcherServices();

Output("Linker and Watcher services have been restarted.\n");
Output("All done!\n");

# All finished. Write an "all done" message to the output progress file.
WriteDoneAndCloseOutput();

############## subs
# Note this has nothing to do with common.pm#Output(), I was
# just lazy in picking the name, sorry.
sub Output {
	my ($txt) = @_;
	WriteToOutput($txt);
	}

# Make a new File Watcher config file specifying which directories to monitor.
# A template with placeholders ($entryTemplatePath) is used to stamp out XML entries for each
# directory to monitor using entries in $searchDirectoriesPath. Only the entries in that
# file with "Monitor" set to 1 are done.
sub MakeConfigFiles {
	my ($configFilePath, $entryTemplatePath, $searchDirectoriesPath) = @_;
	my $configTemplate = LoadConfigTemplate($entryTemplatePath);
	if ($configTemplate eq '')
		{
		Output("Error, cannot continue, |$entryTemplatePath| is missing or empty!\n");
		WriteDoneAndCloseOutput();
		die("Error, |$entryTemplatePath| is missing or empty!");
		}
	my %daemonNames; # Avoid duplicate <daemonName> entries in fwatcher.xml
	my %loadedDirs;
	my $dirCount = 0;
	
	if (-f $searchDirectoriesPath)
		{
		my %indexDummyHash;
		my %ignoreDummyHash;
		LoadSearchDirectoriesToHashes($searchDirectoriesPath, \%indexDummyHash, \%loadedDirs, \%ignoreDummyHash);
		}
	else
		{
		Output("Error, cannot continue, |$searchDirectoriesPath| not found!\n");
		WriteDoneAndCloseOutput();
		die("ERROR, |$searchDirectoriesPath| not found!");
		}

	# This is now done in LoadSearchDirectoriesToHashes.
	# if (defined($loadedDirs{'_INTRAMINE_'}))
	# 	{
	# 	my $intramineDir = path($0)->absolute->parent->stringify;
	# 	$loadedDirs{$intramineDir} = 1;
	# 	delete $loadedDirs{'_INTRAMINE_'};
	# 	}
	
	my %dirs;
	$dirCount = GetDirsToMonitor(\%loadedDirs, \%dirs);
	
	if (-f $configFilePath)
		{
		unlink($configFilePath . '.old2');
		if (-f $configFilePath . '.old')
			{
			my $before = $configFilePath . '.old';
			my $after = $configFilePath . '.old2';
			if (!rename($before, $after))
				{
				Output("Error, cannot continue, could not rename |$before| to |$after|!\n");
				WriteDoneAndCloseOutput();
				die("File error, could not rename |$before| to |$after|!");
				}
			}
		my $before = $configFilePath;
		my $after = $configFilePath . '.old';
		unlink($after);
		if (!rename($before, $after))
			{
			Output("Error, cannot continue, could not rename |$before| to |$after|!\n");
			WriteDoneAndCloseOutput();
			die("File error, could not rename |$before| to |$after|!");
			}
		}

	my $configXML = '<?xml version="1.0" standalone="yes"?>' . "\n<fWatcherConfig>\n";
	
	my @configEntries;
	foreach my $dir (sort keys %dirs)
		{
		my $currentTemplate = $configTemplate;
		my $name = '';
		# Pick up last dir name, use it as <config> item <daemonName>
		if ($dir =~ m!([^\\/]+)$!)
			{
			$name = $1;
			}
		elsif ($dir =~ m!\:!) # $dir is a drive letter, eg H:\
			{
			$name = $dir;
			$name =~ s!\W!!g;
			}
		else
			{
			if ($dir =~ m!([^\\/]+)[\\/]*?$!) # not needed - if a slash on the end snuck through
				{
				$name = $1;
				}
			}
		
		if ($name ne '')
			{
			# Avoid duplicate names.
			my $baseName = $name;
			my $increment = 1;
			my $newName = $name;
			while (defined($daemonNames{$newName}))
				{
				$newName = $name . '_' . $increment;
				++$increment;
				}
			$name = $newName;
			$daemonNames{$name} = 1;
			
			$currentTemplate =~ s!_NAME_!$name!;
			$currentTemplate =~ s!_PATH_NO_TS_!$dir!;	# <path> entry, no Trailing Slash
			push @configEntries, $currentTemplate;
			}
		}
	
	$configXML .= join("\n", @configEntries);
	$configXML .= "</fWatcherConfig>";
	
	unlink($configFilePath);
	my $fh = FileHandle->new(">$configFilePath");
	if (!defined($fh))
		{
		Output("Error, cannot continue, could not open |$configFilePath|!\n");
		WriteDoneAndCloseOutput();
		die("File error, could not open |$configFilePath|!");
		}

	print $fh "$configXML";
	close($fh);
	
	# Make a special list of folders to monitor. Used by bats/foldermonitor.ps1.
	MakeFolderListForFolderMonitor(\%dirs);
	
	return($dirCount);
	}

# Winnow %$loadedDirs_H, to avoid nested directories. Also normalize the entries for use
# by File Watcher (use back slashes).
sub GetDirsToMonitor {
	my ($loadedDirs_H, $dirsH) = @_;

	my %rawDirs;
	foreach my $dir (sort keys %$loadedDirs_H)
		{
		$dir =~ s!/!\\!g;			# Use backslashes
		$dir =~ s![\\/]$!!;			# Trim any trailing slash
		# Arg, put  a slash back at the end if it was the only one (for a drive letter)
		if ($dir !~ m!\\!)
			{
			$dir .= "\\";
			}
		$rawDirs{$dir} = 1;
		}
	
	foreach my $dir (sort keys %rawDirs)
		{
		if ($rawDirs{$dir} ne 'skip')
			{
			$dirsH->{$dir} = 1;
			}
		}
	
	my $dirCount = keys %$dirsH;
	return($dirCount);
	}

# Load the template for one directory entry in File Watcher's XML config file.
sub LoadConfigTemplate {
	my ($filePath) = @_;
	
	my $result = '';
	my $fh = FileHandle->new("$filePath") or return $result;
	my $line = '';
	my @lines;
	while ($line=<$fh>)
		{
		chomp $line;
		push @lines, $line;
		}
	close($fh);
	$result = join("\n", @lines);
	return $result;
	}

# Make a special list of folders to monitor. Used by bats/foldermonitor.ps1. We monitor
# directories that have a "1" in the Monitor column in (default) data/search_directories.txt.
# This list is used by bats/foldermonitor.ps1
# - see intramine_filewatcher.pl#StartPowerShellFolderMonitor().
sub MakeFolderListForFolderMonitor {
	my ($dirsH) = @_;
	
	# Default location data/foldermonitorlist.txt.
	my $folderMonitorFolderListPath = FullDirectoryPath('FOLDERMONITOR_FOLDERLISTPATH');
	my $fh = FileHandle->new(">$folderMonitorFolderListPath");
	if (!defined($fh))
		{
		Output("Error, cannot continue, could not open |$folderMonitorFolderListPath|!\n");
		WriteDoneAndCloseOutput();
		die("File error, could not open |$folderMonitorFolderListPath|!");
		}

	foreach my $dir (sort keys %$dirsH)
		{
		print $fh "$dir\n";
		}
	close($fh);
	}

##### PHASE2 sub
sub ShowResponse {
	my ($response, $title) = @_;
	
	Output("\n\n$title response:\n-----\n");
	foreach my $key (sort keys %$response)
		{
		Output("$key: $response->{$key}\n");
		}
	Output("-----\n");
	}


##### PHASE 3 subs
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
		Output("Error, cannot continue, could not find |$configFilePath|!\n");
		WriteDoneAndCloseOutput();
		die("ERROR, |$configFilePath| not found!");
		}
		
	return($dirCount);
	}

# True if file exists and isn't a "nuisance" file and has a good extension.
# And not in a subfolder that should be ignored, as listed in
# data/search_directories.txt.
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
		Output("ERROR (will continue), |$testDocPath| was not found on disk. test_Search.pl and other test programs might fail if run later.\n");
		}
	}

# Start/stop services.
sub StopLinkerAndWatcherServices {
	my $serverAddress = $ServerAddress;
	my $portNumber = $MainPort;
	my $msg = 'rddm=1&req=stop_one_specific_server&shortName=' . 'Linker';
	Output("Stopping Linker service\n");
	SendRequest($serverAddress, $portNumber, $msg);
	sleep(1);

	$msg = 'rddm=1&req=stop_one_specific_server&shortName=' . 'Watcher';
	Output("Stopping Watcher service\n");
	SendRequest($serverAddress, $portNumber, $msg);
	}

sub StartLinkerAndWatcherServices {
	my $serverAddress = $ServerAddress;
	my $portNumber = $MainPort;
	my $msg = 'rddm=1&req=start_one_specific_server&shortName=' . 'Linker';
	Output("Starting Linker service\n");
	SendRequest($serverAddress, $portNumber, $msg);
	sleep(1);

	$msg = 'rddm=1&req=start_one_specific_server&shortName=' . 'Watcher';
	Output("Starting Watcher service\n");
	SendRequest($serverAddress, $portNumber, $msg);
	}

sub SendRequest {
	my ($serverAddress, $portNumber, $msg) = @_;
	my $main = IO::Socket::INET->new(
				Proto   => 'tcp',       		# protocol
				PeerAddr=> "$serverAddress", 	# Address of server
				PeerPort=> "$portNumber"      	# port of server typ. 43124..up
				) or (ServerErrorReport() && return);
	
	print $main "GET /?$msg HTTP/1.1\n\n";
	close $main;	# No reply needed.
	}

# Called by ri.pl when Reindex command is running,
# tell intramine_filewatcher.pl to not restart
# File Watcher Windows Service.
# (we stop and restart here)
# too soon.
sub TellWatcherIgnoreFWWS {
	my $serverAddress = $ServerAddress;
	my $portNumber = $MainPort;
	my $msg = 'signal=IGNOREFWWS&name=Watcher';
	SendRequest($serverAddress, $portNumber, $msg);
	}

sub ServerErrorReport{
        print Win32::FormatMessage( Win32::GetLastError() );
        return 1;
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
	my $fileH = FileHandle->new("> $fileSizePath");
	if (!defined($fileH))
		{
		Output("Error (will continue), could not open $fileSizePath\n");
		return;
		}
	
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

# Doesn't work.
# BEGIN {
#     Win32::SetChildShowWindow(0)
#         if defined &Win32::SetChildShowWindow; 
# }
