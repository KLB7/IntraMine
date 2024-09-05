# ri.pl: re-index Elasticsearch, and create a new full path list
# based on directories listed in data/search_directories.txt
# The name is deliberately cryptic, it should only be run
# via the Reindex service. All progress messages are written
# to a file which can then be read by some other program
# (eg the Reindex service).
# This is basically a combination of
# make_filewatcher_config.pl
# elasticsearch_init_index.pl
# elastic_indexer.pl -addTestDoc
# but with progress messages written to a temp file.

# Summary
# Force to Run as admin
# Phase 1, configure File Watcher to watch new list of directories
# Stop IntraMine
# Phase 2 init Elasticsearch index and delete full paths list.
# PHASE 3 rebuild the Elasticsearch index and full paths list.
# Restart IntraMine (done by a separate call in IM_REINDEX.bat).

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
# below around l.63.
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

select((select(STDOUT), $|=1)[0]); # Unbuffer output.

LoadConfigValues();				# intramine_config.pm

my $LogDir = FullDirectoryPath('LogDir');
InitCmdOutput($LogDir . 'temp/tempout_' . 'REINDEX' . '.txt');

# TEST ONLY
# Output("TESTING\n");
# for (my $i = 0; $i < 100; ++$i)
# 	{
# 	Output("Hello $i\n");
# 	}
# sleep(5);
# WriteDoneAndCloseOutput();
# exit(0);


# Stop and start the File Watcher service, to pick up the config changes made here.
my $startFileWatcherServicePath = FullDirectoryPath('FILEWATCHER_START_SERVICE');
my $stopFileWatcherServicePath = FullDirectoryPath('FILEWATCHER_STOP_SERVICE');
if (!(-f $startFileWatcherServicePath))
	{
	die ("Maintenance error, FILEWATCHER_START_SERVICE is incorrect in data/intramine_config.txt! Expecting path to start_filewatcher_service.bat.")
	}
if (!(-f $stopFileWatcherServicePath))
	{
	die ("Maintenance error, FILEWATCHER_STOP_SERVICE is incorrect in data/intramine_config.txt! Expecting path to stop_filewatcher_service.bat.")
	}

my $ConfigFilePath = CVal('FWWS_CONFIG');
die("Error |FWWS_CONFIG| not found in /data/intramine_config.txt") if ($ConfigFilePath eq '');

# FWWS_CONFIG file might be missing on a first run, so ignore error if it doesn't exist yet.
#die ("Please install File Watcher and set |FWWS_CONFIG| in /data/intramine_config.txt")
#	if (!(-f $ConfigFilePath));

if ($TESTING)
	{
	$ConfigFilePath .= '.txt';
	}
my $EntryTemplatePath = FullDirectoryPath('FWWS_ENTRY_TEMPLATE');
my $SearchDirectoriesPath = FullDirectoryPath('ELASTICSEARCHDIRECTORIESPATH');

my $batresult = system(1, "\"$stopFileWatcherServicePath\">nul 2>&1");
if ($batresult == -1)
	{
	die("ERROR, could not stop the File Watcher service with |$stopFileWatcherServicePath|!\n");
	}

# Allow a few seconds for File Watcher to stop.
sleep(5);

my $EntryCount = MakeConfigFiles($ConfigFilePath, $EntryTemplatePath, $SearchDirectoriesPath);

# And let the dust settle on that, in case the disk gerbil is a bit tired today.
sleep(2);

$batresult = system(1, "\"$startFileWatcherServicePath\">nul 2>&1");
if ($batresult == -1)
	{
	die("ERROR, could not restart the File Watcher service with |$startFileWatcherServicePath|!\n");
	}

Output("$EntryCount directories will be monitored by File Watcher, see |$ConfigFilePath|.\n");

##### Stop IntraMine
# 'SRVR' loads current 'SERVER_ADDRESS' as saved by intramine_main.pl#InitServerAddress().
LoadConfigValues('SRVR');
my $port_listen = CVal('INTRAMINE_MAIN_PORT'); 			# default 81

my $serverAddress = CVal('SERVER_ADDRESS');
if ($serverAddress eq '')
	{
	# This is an error, but we will try to carry on.
	Output("We will continue, using 'localhost' as the server address.\n");
	$serverAddress = 'localhost';
	}

AskServerToExit($port_listen, $serverAddress);
sleep(2); # let the dust settle

##### PHASE 2, init Elasticsearch index and delete full paths list.
my $esIndexName = CVal('ES_INDEXNAME'); 	# default 'intramine'
my $esTextIndexType = CVal('ES_TEXTTYPE'); 	# default 'text'
if ($esIndexName eq '' || $esTextIndexType eq '')
	{
	die("ERROR, intramine_config.pm could not find values for ES_INDEXNAME and ES_TEXTTYPE!");
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
	sleep(10);
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

 # For Elasticsearch 6.5.1, this worked fine: it doesn't have the "settings" wrapper.
#$response = $e->indices->create(
#	index      => $esIndexName,
#	"body" => {
#       number_of_shards 	=> $numShards,			# default 5
#       number_of_replicas 	=> $numReplicas,		# default 0
#       auto_expand_replicas	=> 'false',				# prevents autocreating unwanted replica(s)
#		"analysis" => {
#			"analyzer" => {
#				"index_analyzer" => {
#					"char_filter" 	=> "icu_normalizer",
#					"tokenizer" 	=> "icu_tokenizer",
#					"filter"    	=> "icu_folding"
#				}
#			}
#		}
#	}
#);
ShowResponse($response, "$esIndexName index creation");

Output("Done Elasticsearch index init.\n");

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
my $dirCount = LoadDirectoriesToIndex(\@DirectoriesToIndex);
if (!$dirCount)
	{
	Output("No directories were found for indexing.\n");
	exit(0);
	}

my %myFileNameForPath;	# for Elasticsearch indexing
my %rawPathList; 		# for full path List (used for auto linking)
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
	$rawPathList{$lcpathForwardSlashes} = lc($sourceFileName);
	# Indexing. Optionally skip .log files. 
	if (FileShouldBeIndexed($pathForwardSlashes))
		{
		$myFileNameForPath{$pathForwardSlashes} = $sourceFileName;
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
	if (($docCounter%500) == 0)
		{
		Output("  FLUSHING, and waiting a few...\n");
		$ElasticIndexer->Flush();	
		sleep(5);
		}
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
# reverse_filepaths.pm#ConsolidateFullPathLists() assumes the path list is in memory
# (which it is at this point), saves it over the main full paths file, and deletes any
# secondary file that was holding additional paths.
# To get here, we initially loaded paths from the
# main and secondary files, and added in the new paths found here. So
# Consolidate will do the right thing, even though the name isn't quite right
# (mainly it's used by intramine_filewatcher.pl when IntraMine is running,
# to consolidate the two full path files during the wee hours of the night).
my $howItWent = ConsolidateFullPathLists(1); # 1 == force consolidation
if ($howItWent ne "ok")
	{
	Output("$howItWent\n");
	}

# Dump a table of file counts in various size ranges.
DumpFileSizeBinCountsAndLargeFiles();

Output("\nDone. Full path list is in |$fullFilePathListPath|.\n");

# All finished. Write an "all done" message to the output progress file.
WriteDoneAndCloseOutput();

############## subs
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
	die("Error, |$entryTemplatePath| is missing or empty!") if ($configTemplate eq '');
	my %daemonNames; # Avoid duplicate <daemonName> entries in fwatcher.xml
	my %loadedDirs;
	my $dirCount = 0;
	
	if (-f $searchDirectoriesPath)
		{
		my %indexDummyHash;
		LoadSearchDirectoriesToHashes($searchDirectoriesPath, \%indexDummyHash, \%loadedDirs);
		}
	else
		{
		die("ERROR, |$searchDirectoriesPath| not found!");
		}
									
	if (defined($loadedDirs{'_INTRAMINE_'}))
		{
		my $intramineDir = path($0)->absolute->parent->stringify;
		$loadedDirs{$intramineDir} = 1;
		delete $loadedDirs{'_INTRAMINE_'};
		}
	
	my %dirs;
	$dirCount = GetDirsToMonitor(\%loadedDirs, \%dirs);
	
	if (-f $configFilePath)
		{
		unlink($configFilePath . '.old2');
		if (-f $configFilePath . '.old')
			{
			my $before = $configFilePath . '.old';
			my $after = $configFilePath . '.old2';
			rename($before, $after) or
				die("File error, could not rename |$before| to |$after|!");
			}
		my $before = $configFilePath;
		my $after = $configFilePath . '.old';
		unlink($after);
		rename($before, $after) or
			die("File error, could not rename |$before| to |$after|!");
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
	my $fh = FileHandle->new(">$configFilePath")
		or die("File error, could not open |$configFilePath|!");
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
	
	# Avoid nested dirs, eg c:\stuff and c:\stuff\run.
	foreach my $dir (sort keys %rawDirs)
		{
		my $pathAbove = $dir;
		$pathAbove =~ s!\\([^\\]+)$!!;
		if ($pathAbove !~ m!\\([^\\]+)$!)
			{
			$pathAbove = '';
			}
		while ($pathAbove ne '')
			{
			if (defined($rawDirs{$pathAbove}))
				{
				Output("(skipping |$dir|, it is included under |$pathAbove|.)\n");
				$rawDirs{$dir} = 'skip';
				last;
				}
			if ($pathAbove !~ m!\\([^\\]+)$!)
				{
				$pathAbove = '';
				}
			else
				{
				$pathAbove =~ s!\\([^\\]+)$!!;
				}
			}
		}

	#my %dirs;
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
	my $fh = FileHandle->new(">$folderMonitorFolderListPath")
		or die("File error, could not open |$folderMonitorFolderListPath|!");
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
	my ($directoriesToIndexA) = @_;
	my $configFilePath = FullDirectoryPath('ELASTICSEARCHDIRECTORIESPATH');
	my $dirCount = 0;
	
	if (-f $configFilePath)
		{
		my @dummyMonitorArray;
		my $haveSome = LoadSearchDirectoriesToArrays($configFilePath, $directoriesToIndexA,
						\@dummyMonitorArray); # intramine_config.pm#LoadSearchDirectoriesToArrays()
		
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
	my ($fullPath) = @_;
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

# Subs for stopping IntraMine
########### subs
sub ErrorReport{
        Output('intramine_all_stop.pl says: ' . Win32::FormatMessage( Win32::GetLastError() ));
        return 1;
    }

# Ask main server to stop. This will in turn request all servers to stop.
sub AskServerToExit {
	my ($portNumber, $serverAddress) = @_;
	
	Output("Attempting to stop $serverAddress:$portNumber\n");
	my $remote = IO::Socket::INET->new(
	                Proto   => 'tcp',       # protocol
	                PeerAddr=> "$serverAddress", # Address of server
	                PeerPort=> "$portNumber"      # port of server, 81 591 or 8080 are standard variants
	                ) or (ErrorReport() && return);
#	print "intramine_stop.pl Connected to ", $remote->peerhost, # Info message
#	      " on port: ", $remote->peerport, "\n";
	
	print $remote "GET /?FORCEEXIT=1 HTTP/1.1\n";
	close $remote;
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

# Doesn't work.
# BEGIN {
#     Win32::SetChildShowWindow(0)
#         if defined &Win32::SetChildShowWindow; 
# }
