# intramine_filewatcher.pl: check File Watcher log, on changes ask Elasticsearch to re-index the file.
# We also start a PowerShell script to do faster "push" monitoring. When it detects a change,
# it pushes a signal "signal=FILESYSTEMCHANGE" back to this program, which prompts an immediate
# check of the File Watcher log for changes. This cuts down response time
# for a disk change to less than five seconds. The File Watcher log contains most of the details
# for a change, but is looked at only once a minute if no FILESYSTEMCHANGE
# signal is received.
# PowerShell script: see StartPowerShellFolderMonitor(). And bats/foldermonitor.ps1.
# FILESYSTEMCHANGE signal handling: see OnChangeDelayedIndexChangedFiles().
#
# See also Documentation/FILEWATCHER.html.
#

# perl C:\perlprogs\mine\intramine_filewatcher.pl 81 43132

use strict;
use warnings;
use utf8;
use FileHandle;
use File::ReadBackwards;
use Encode qw(from_to);
use Encode::Guess;
use Win32::Process;
use Win32::Service;
use Time::HiRes qw(usleep);
# For stopping PowerShell script:
use Win32::Process 'STILL_ACTIVE';
use DateTime;
use Time::Local qw( timelocal_modern );
use Win32;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;
use elasticsearch_bulk_indexer;
use reverse_filepaths;
use tocmaker;
use win_wide_filepaths;
use ext; # for ext.pm#EndsWithTextOrImageExtension() etc.
use intramine_config; # For LoadSearchDirectoriesToArrays()

binmode(STDOUT, ":encoding(UTF-8)");
Win32::SetConsoleCP(65001);

$|  = 1;

my $SHORTNAME = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(undef, \$SHORTNAME, \$server_port, \$port_listen);

# Date comparisons are sometimes needed, time zone handling is a bit annoying.
SetTimeZone();

# Tired of indexing hundreds of log files, so optionally skip any
# file with a .log or .out extension.
my $SKIPLOGFILES = 1;

# Optionally allow files with no extension.
my $IndexIfNoExtension = 0;

my $kLOGMESSAGES = 0;			# 1 == Log Output() messages
my $kDISPLAYMESSAGES = 0;		# 1 == print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print.
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);
Output("Starting $SHORTNAME on port $port_listen\n\n");

my $FileWatcherDir = CVal('FILEWATCHERDIRECTORY');
my $FileWatcherLogPath = $FileWatcherDir . CVal('FILEWATCHER_LOG');
my $FileWatcherLogPathModDate = 0;
my $TimeStampPath = $FileWatcherDir . CVal('FWTIMESTAMPFILE');
my $CudPath = $FileWatcherDir . CVal('FWCURRENTCHANGESFILE');	# Changed Updated Deleted path
# With apologies, the keys for the two different glossary names are
# very close.
my $GLOSSARYFILENAME = lc(CVal('GLOSSARYFILENAME')); # default glossary_master.txt
my $STANDALONEGLOSSARYFILENAME = lc(CVal('GLOSSARY_FILE_NAME')); # default glossary.txt

# filewatcher.pl responds to common default requests (id, signal),
# and also signal=FILESYSTEMCHANGE, a request to re-index Elasticsearch and rebuild file paths list.
my %RequestAction;
$RequestAction{'signal|FILESYSTEMCHANGE'} = \&OnChangeDelayedIndexChangedFiles;
$RequestAction{'signal|HEARTBEAT'} = \&OnHeartbeatFromFolderMonitor;
$RequestAction{'signal|IGNOREFWWS'} = \&IgnoreFWWS;

my $HaveCheckedLogExists = 0; 	# we only check the first time, exit if File Watcher log is not found.
my $LastTimeStampChecked = ''; 	# When reading 'tail' of File Watcher log, just step back to the last time stamp seen before.
my %FilesForLastFileStamp;		# Files at end of last check

InitPeriodicConsolidation();

# Make an Elasticsearch bulk indexer client.
my $esIndexName = CVal('ES_INDEXNAME'); 	# default 'intramine'
my $esTextIndexType = CVal('ES_TEXTTYPE'); 	# default 'text'
my $maxFileSizeKB = CVal('ELASTICSEARCH_MAXFILESIZE_KB');
my $ElasticIndexer = elasticsearch_bulk_indexer->new($esIndexName, $esTextIndexType, $maxFileSizeKB);
my $fullFilePathListPath = $FileWatcherDir . CVal('FULL_PATH_LIST_NAME'); # .../fullpaths.out
my $filePathCount = InitFullPathList($fullFilePathListPath);
LoadIncrementalFullPathLists($fullFilePathListPath);
LoadAndRemoveDeletesFromHashes();

LoadLastTimeStamp();

my $MainLoopTimeout = 2; # seconds
my $NumTimeoutsBeforeIndexing = 30; # Re-index about once a minute
my $NumTimeoutsBeforeSignalledIndexing = 2; # Delay re-indexing after signal received
my $NumTimeoutsBeforeHeartbeatCheck = 70;

StartPowerShellFolderMonitor();

# We check File Watcher regularly, restart it if it crashes.
InitFWWSMonitor();

# Start up db for tracking deleted files.
InitDeletesDB();

# Detect large number of files added or deleted.
my $Congested = 0;
my $CongestionMinimum = 200; # Somewhat arbitrary, count of files receive all at once

GetDirectoriesToIgnore();

# Note we call IndexChangedFiles() once a minute (30 two-second timeouts).
MainLoop(\%RequestAction, $MainLoopTimeout, \&OnTimeoutIndexChangedFilesEtc);

StopPowerShellFolderMonitor();

############## subs
# Call IndexChangedFiles() after MainLoop() timeout has gone through enough to add up to a minute.
{ ##### Timeout IndexChangedFiles
my $numTimeoutsSinceLastCall;
my $numTimeoutsSinceLastHeartbeatCheck;
my $previousHeartbeatCount;
my $heartbeatReceived;

sub OnTimeoutIndexChangedFilesEtc {
	if (!defined($numTimeoutsSinceLastCall))
		{
		$numTimeoutsSinceLastCall = 0;
		}
	++$numTimeoutsSinceLastCall;
	if ($numTimeoutsSinceLastCall >= $NumTimeoutsBeforeIndexing)
		{
		IndexChangedFiles();
		$numTimeoutsSinceLastCall = 0;
		CancelDelayedIndexing();
		}
	else
		{
		if (ReindexIfRequested())
			{
			# Push off the next polled reindex by a full minute.
			$numTimeoutsSinceLastCall = 0;
			}
		}

	if (!defined($previousHeartbeatCount))
		{
		ResetHeartbeatReceived();
		}

	# Check that foldermonitor.ps1 is still running, if it is it sends
	# a 'signal|HEARTBEAT' about once a minute.
	++$numTimeoutsSinceLastHeartbeatCheck;
	if ($numTimeoutsSinceLastHeartbeatCheck >= $NumTimeoutsBeforeHeartbeatCheck)
		{
		my $currentHeartbeatCount = HeartBeatCount();
		if ($currentHeartbeatCount == $previousHeartbeatCount)
			{
			# Error, foldermonitor.ps1 is not responding.
			$heartbeatReceived = 0;
			}
		else
			{
			$heartbeatReceived = 1;
			}
		$previousHeartbeatCount = $currentHeartbeatCount;
		$numTimeoutsSinceLastHeartbeatCheck = 0;
		}

	if (!$heartbeatReceived)
		{
		ResetHeartbeatCount();
		RestartFolderMonitor();
		}

	# Also check that "File Watcher Windows Service" is running, restart if needed.
	if (!FWWSIsRunning())
		{
		my $status = RestartFWWS();
		if ($status ne 'OK')
			{
			Monitor("$status\n");
			}
		}
	}

sub FoldermonitorIsOk {
	return($heartbeatReceived);
	}

sub ResetHeartbeatReceived {
	$previousHeartbeatCount = 0;
	$numTimeoutsSinceLastHeartbeatCheck = 0;
	$heartbeatReceived = 1;
	}
} ##### Timeout IndexChangedFiles

{ ##### FWWS monitor and restart
my $ServiceName;
my $RestartAlreadyRequested;
my $IgnoreFWWS;
my $RestartBatPath;
my %status;
my %status_code;

sub InitFWWSMonitor {
	my $foldermonitorPSPath = FullDirectoryPath('FOLDERMONITOR_PS1_FILE'); # ...bats/foldermonitor.ps1
	my $batDir = DirectoryFromPathTS($foldermonitorPSPath);
	my $batPathToRestart = $batDir . 'IM_RESTART_FWWS.bat';

	$RestartBatPath = $batPathToRestart;
	$RestartAlreadyRequested = 0;
	$IgnoreFWWS = 0;
	$ServiceName = "File Watcher Windows Service";

	%status_code = (
	Stopped => 1,
	StartPending => 2,
	StopPending => 3,
	Running => 4,
	ResumePending => 5,
	PausePending => 6,
	Paused => 7
);
}

sub FWWSIsRunning {
	my $result = 1;
	if ($IgnoreFWWS)
		{
		return($result);
		}
	Win32::Service::GetStatus('', $ServiceName, \%status);
	if ($status{"CurrentState"} ne $status_code{Running})
		{
		$result = 0;
		}
	else
		{
		$RestartAlreadyRequested = 0;
		}
	
	return($result);
	}

sub RestartFWWS {
	if ($RestartAlreadyRequested || $IgnoreFWWS)
		{
		return;
		}
	
	my $fwwsproc;
	my $status = 'OK';
	my $flag = Win32::Process::CREATE_NEW_CONSOLE();

	Win32::Process::Create($fwwsproc, $ENV{COMSPEC}, "/c $RestartBatPath", 0, $flag, ".")
				|| ($status = Win32::FormatMessage( Win32::GetLastError() ));

	$RestartAlreadyRequested = 1;

	return($status);
	}

sub IgnoreFWWS {
	Monitor("Watcher has stopped monitoring 'File Watcher Windows Service', this will resume in a few minutes.\n");
	$IgnoreFWWS = 1;
	}
} ##### FWWS monitor and restart

{ ##### foldermonitor.ps1 HEARTBEAT signal handling
my $heartbeatCount;

# Receive and count up 'heartbeat' signals from foldermonitor.ps1.
# If not received in time, foldermonitor.ps1 will be restarted.
# This nuisance tries to deal with cases where foldermonitor.ps1 is
# overloaded by too many file changes at once, and stops responding.
sub OnHeartbeatFromFolderMonitor {
	if (!defined($heartbeatCount))
		{
		ResetHeartbeatCount();
		}
	++$heartbeatCount;
	}

sub HeartBeatCount {
	if (!defined($heartbeatCount))
		{
		ResetHeartbeatCount();
		}

	return($heartbeatCount);
	}

sub ResetHeartbeatCount {
	$heartbeatCount = 0;
	ResetHeartbeatReceived();
	}
} ##### foldermonitor.ps1 HEARTBEAT signal handling

# Call IndexChangedFiles() after receiving FILESYSTEMCHANGE and MainLoop() timeout
# has happened twice.
{ ##### FILESYSTEMCHANGE IndexChangedFiles
my $numTimeOutsSinceRequestReceived;
my $reindexRequestPending;

# If Folder Monitor is being used, it will enthusiastically fire off several notifications for
# each file system change in directories that are being monitored. To avoid annoying
# Elasticsearch we pause for a few seconds, ignore subsequent notifications, and then do just
# one IndexChangedFiles() call.
sub OnChangeDelayedIndexChangedFiles {
	my ($obj, $formH, $peeraddress) = @_;

	# TEST OUT: OnHeartbeatFromFolderMonitor();

	# Do a quick initial re-index, to promptly catch changes to a single file.
	if (!defined($reindexRequestPending) || $reindexRequestPending == 0)
		{
		IndexChangedFiles();
		}

	$reindexRequestPending = 1;
	$numTimeOutsSinceRequestReceived = 0;
	}

sub ReindexIfRequested {
	my $result = 0;
	
	if (!defined($reindexRequestPending))
		{
		$reindexRequestPending = 0;
		$numTimeOutsSinceRequestReceived = 0;
		}
	
	if ($reindexRequestPending)
		{
		++$numTimeOutsSinceRequestReceived;
		if ($numTimeOutsSinceRequestReceived >= $NumTimeoutsBeforeSignalledIndexing)
			{
			$result = 1;
			IndexChangedFiles();
			$reindexRequestPending = 0;
			$numTimeOutsSinceRequestReceived = 0;
			}
		}
	
	return($result);
	}

sub CancelDelayedIndexing {
	$reindexRequestPending = 0;
	$numTimeOutsSinceRequestReceived = 0;
	}
} ##### FILESYSTEMCHANGE IndexChangedFiles

{ ##### IndexChangedFiles
my @PathsOfChangedFiles; 		# includes new files
my @PathsOfChangedFilesFileTimes; # time stamp from filewatcher log for same.
my %PathsOfCreatedFiles; 		# just new files, also helps when removing erroneous %PathsOfDeletedFiles entries
my %FileOnPathWasChanged; 		# For detecting a rapid deleted/created/changed - just report changed.
my %PathsOfDeletedFiles;
my @RenamedFolderPaths;			# holds full path to folder, with the new folder name
my @RenamedFilePaths;			# holds full path to renamed file, using the new name
my @DirectoriesToIgnore;

# For reading filewatcher log.
my %CurrentPathAlreadySeen; 	# Avoid doing the same file twice here, File Watcher can be a bit repetitive.
my $MostRecentTimeStampThisTimeAround;
my %FilesForMostRecentFileStamp;	# Files at end of current check (transferred to %FilesForLastFileStamp when done check)
my %TimeStampForPath; # $TimeStampForPath{'C:/folder/file.txt'} = '2023-10-31 5-49-24 PM'

sub GetDirectoriesToIgnore {
	my $configFilePath = FullDirectoryPath('ELASTICSEARCHDIRECTORIESPATH');
	if (-f $configFilePath)
		{
		my @dummyIndexArray;
		my @dummyMonitorArray;
		my $haveSome = LoadSearchDirectoriesToArrays($configFilePath, \@dummyIndexArray,
						\@dummyMonitorArray, \@DirectoriesToIgnore); # intramine_config.pm#LoadSearchDirectoriesToArrays()
		}
	}

# Ignore file path if it starts with path to a folder to ignore, as
# listed in data/search_directories.txt. Comparisons are done
# in lower case with forward slashes only.
# Also ignore "nuisance" files in /temp/ or /junk/, and files
# in folders that start with a period (eg /.tmp.driveupload/)
# and file names that start with a period too.
sub ShouldIgnoreFile {
	my ($fullPath) = @_; # lc, / only
	#$fullPath = lc($fullPath);
	#$fullPath =~ s!\\!/!g;
	my $result = 0;

	# Nuisance files: no period in path, or in temp or junk
	# or "ini" extension.
	if (index($fullPath, '.') < 0 || $fullPath =~ m!/(temp|junk)/!
	  || index($fullPath, '/.') > 0 || index($fullPath, '.ini') > 0)
		{
		return(1);
		}

	for (my $i = 0; $i < @DirectoriesToIgnore; ++$i)
		{
		if (index($fullPath, $DirectoriesToIgnore[$i]) == 0)
			{
			$result = 1;
			last;
			}
		}

	return($result);
	}

# Read FileWatcher Service log(s), ask Elasticsearch to index changed/new, remember full
# paths of any new files. If a folder is renamed, tell Viewer to reload partial path list.
sub IndexChangedFiles {
	
	# Look for fwatcher.log. Everything here depends on it.
	if (!$HaveCheckedLogExists && !(-f $FileWatcherLogPath))
		{
		ReportMissingFileWatcherLog();
		exit(0);
		}
	
	$HaveCheckedLogExists = 1;
	
	# Check/set timestamp $FileWatcherLogPathModDate on $FileWatcherLogPath,
	# no action needed if it hasn't changed.
	my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size,
			$atime, $mtime, $ctime, $blksize, $blocks) = stat $FileWatcherLogPath;
	my $currentModDate = $mtime;
	if ($FileWatcherLogPathModDate == 0) # First time, continue here.
		{
		$FileWatcherLogPathModDate = $currentModDate;
		}
	else
		{
		if ($FileWatcherLogPathModDate != $currentModDate)
			{
			$FileWatcherLogPathModDate = $currentModDate;
			}
		else
			{
			# No change, we're done this time around.
			return;
			}
		}
		
	if (!GetChangesFromWatcherLogs())
		{
		return;
		}
	
	# Notify user in Cmd window if indexing is under heavy load.
	ReportIfCongested();

	# Remove %PathsOfDeletedFiles entry if it was also seen as 'created', trying to work around
	# problem where a file can be reported as deleted (and also created) when it has been created
	# and not deleted at all whatsoever (unless notepad++ is doing something sneaky).
	my %FilePathDeletedAndCreated;
	foreach my $path (keys %PathsOfCreatedFiles)
		{
		if (defined($PathsOfDeletedFiles{$path}))
			{
			delete $PathsOfDeletedFiles{$path};
			$FilePathDeletedAndCreated{$path} = 1;
			}
		}
		
	# Sometimes a file is reported as deleted/created/changed. For this case we just removed the
	# delete above, also remove from created list.
	foreach my $path (keys %FileOnPathWasChanged)
		{
		if (defined($FilePathDeletedAndCreated{$path}))
			{
			# Delete from created files list, but only if the number of "created"
			# is 1. 2 or more means a genuine create.
			if ($PathsOfCreatedFiles{$path} == 1)
				{
				delete $PathsOfCreatedFiles{$path};
				}
			}
		}

	# Remove new files from list of deleted files - this means a deleted file
	# has been re-created and is no longer deleted. Beating it to death there:)
	RemoveNewFilesFromDeletes(\%PathsOfCreatedFiles);

	# Send out messages via WebSockets for changed files, so the Viewer can update.
	# (This needs more work, sometimes the WebSockets message doesn't go through.)
	SendFileContentsChanged(\@PathsOfChangedFiles, \%PathsOfCreatedFiles, \%TimeStampForPath);

	# File renames: not much needed, just find the old file name and remove the old
	# entry from Elasticsearch.
	my @OldFilePath; # old names for renamed files
	my $numFileRenames = @RenamedFilePaths;
	if ($numFileRenames)
		{
		GuessOldPathsForRenamedFiles($numFileRenames, \@RenamedFilePaths, \@OldFilePath);
		my $pathsChanged = UpdateFullPathsForFileRenames($numFileRenames, \@RenamedFilePaths,\ @OldFilePath);

		# Tell Viewer(s) to re-init all full and partial paths.
		if ($pathsChanged)
			{
			# File and folder rename handling is the same.
			RequestBroadcast('signal=folderrenamed');
			}
		}
	
	# Folder renames, the hardest part of all this.
	my @OldFolderPath;
	my $numRenames = @RenamedFolderPaths;
	if ($numRenames)
		{
		GuessOldNamesPathsForRenamedFolders($numRenames, \@RenamedFolderPaths, \@OldFolderPath);
		my $pathsChanged = UpdateFullPathsForFolderRenames($numRenames, \@RenamedFolderPaths, \@OldFolderPath);
		# Note that effectively does a PeriodicallyConsolidate().
		
		# Tell Viewer(s) to re-init all full and partial paths. Slow, but incremental is hard.
		if ($pathsChanged)
			{
			RequestBroadcast('signal=folderrenamed');
			}
		}
	
	my $numIndexedPaths = AskElasticsearchToIndexChanges(\@PathsOfChangedFiles);
	my %NewPaths;
	my $numNew = SaveAndRememberNewFullPaths(\@PathsOfChangedFiles, \%NewPaths);
	my $numDeleted = keys %PathsOfDeletedFiles;
	
	if ($numDeleted)
		{
		RemoveDeletes(\%PathsOfDeletedFiles); # Remove from in-memory hashes and arrays
		UpdateSearchIndexForDeletes(\%PathsOfDeletedFiles);
		}
	
	SaveLastTimeStamp();
	
	if (!$numRenames)
		{
		if ($numNew || $numDeleted)
			{
			# Tell Viewer(s) to update directory lists.
			RequestBroadcast('signal=reindex');
			}
		else
			{
			PeriodicallyConsolidate();
			# This is somewhat opportunistic, get rid of old temp files.
			DeleteOldTempFiles();
			}
		}
	
	# Notify Linker if any glossary files or dictionary have changed.
	BroadcastDefinitionFilesChangedOrNew(\@PathsOfChangedFiles, \%NewPaths);

	# For displaying a list of changed files in monitored folders, save a list
	# of changed (plus new) and deleted files, blowing away any old list.
	if ($numIndexedPaths || $numDeleted)
		{
		SaveChangedFilesList(\@PathsOfChangedFiles, \@PathsOfChangedFilesFileTimes, \%PathsOfCreatedFiles, \%PathsOfDeletedFiles);
		# Tickle the Status page, which will load the list of changed/new and deleted files.
		RequestBroadcast('signal=filechange');
		}
	
	# Make the Status light flash for this server.
	ReportActivity($SHORTNAME);
	}

# Notify if many files are coming in at once.
# And again when the load drops off.
sub ReportIfCongested {
	my $numChangedNewFiles = @PathsOfChangedFiles; # includes new
	my $numDeletedFilles = keys %PathsOfDeletedFiles;
	if ($numChangedNewFiles || $numDeletedFilles)
		{
		my $numTotal = $numChangedNewFiles + $numDeletedFilles;
		if ($numTotal >= $CongestionMinimum)
			{
			$Congested = 1;
			if ($numTotal > $CongestionMinimum*10)
				{
				Monitor("VERY heavy load on Watcher, $numTotal file system changes.\n");
				}
			else
				{
				Monitor("Heavy load on Watcher, $numTotal file system changes.\n");
				}

			# TEST ONLY
			#Monitor("First few files:\n");
			#for (my $i = 0; $i < @PathsOfChangedFiles && $i < 5; ++$i)
			#	{
			#	Monitor("    $PathsOfChangedFiles[$i]\n");
			#	}
			}
		elsif ($Congested)
			{
			Monitor("Watcher load has dropped off.\n");
			$Congested = 0;
			}
		}
	elsif ($Congested)
		{
		Monitor("Watcher load has dropped off.\n");
		$Congested = 0;
		}
	}

# Use WebSockets to send 'changeDetected' messages out to everyone, in particular
# so that the Viewer can refresh the view.
sub SendFileContentsChanged {
	my ($pathsOfChangedFilesA, $pathsOfCreatedFilesH, $timeStampForPathH) = @_;
	my $CHANGED_BROADCAST_LIMIT = 10; # or 5 or 3?
	my @pathsOfChangedNotNewFiles;
	my $numChangedNew = @$pathsOfChangedFilesA;
	for (my $i = 0; $i < $numChangedNew; ++$i)
		{
		if ($pathsOfChangedFilesA->[$i] ne '')
			{
			my $isAChange = (defined($pathsOfCreatedFilesH->{$pathsOfChangedFilesA->[$i]})) ? 0 : 1;
			if ($isAChange)
				{
				push @pathsOfChangedNotNewFiles, $pathsOfChangedFilesA->[$i];
				}
			}
		}
		
	my $numChanged = @pathsOfChangedNotNewFiles;
	if ($numChanged <= $CHANGED_BROADCAST_LIMIT)
		{
		for (my $i = 0; $i < $numChanged; ++$i)
			{
			my $timeStamp = defined($timeStampForPathH->{$pathsOfChangedNotNewFiles[$i]}) ? $timeStampForPathH->{$pathsOfChangedNotNewFiles[$i]}: '0';
			SendOneFileContentsChanged($pathsOfChangedNotNewFiles[$i], $timeStamp);
			}
		}
	}

sub SendOneFileContentsChanged {
	my ($filePath, $timeStamp) = @_;
	
	$filePath =~ s!%!%25!g;
	$filePath =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;

	# Revision Sept 2024, for the time stamp send milliseconds since
	# the Epoch () instead of a readable string.
	# Typical $timeStamp coming in: 2024-09-11 11-13-40 AM
	# Regex: !^(\d\d\d\d)-(\d+)-(\d+)\s+(\d+)-(\d+)-(\d+)\s(\w+)$!
	# my $time = timelocal_modern($sec, $min, $hour, $mday, $mon, $year);
	# $sec: 0..59
	# $min: 0..59
	# $hour: 0..23
	# $mday: 1..31
	# $mon: 0..11
	# $year: 4 digits
	my $messageTime = 0;
	if ($timeStamp =~ m!^(\d\d\d\d)-(\d+)-(\d+)\s+(\d+)-(\d+)-(\d+)\s(\w+)$!)
		{
		my $year = $1;
		my $mon = $2;
		my $mday = $3;
		my $hour = $4;
		my $min = $5;
		my $sec = $6;
		my $ampm = $7;

		$mon -= 1;
		if ($ampm =~ m!pm!i)
			{
			$hour += 12;
			}
		if ($hour >= 24)
			{
			$hour -= 24;
			}

		if ($year > 2020 && $year < 2038 && $mon >= 0 && $mon < 12 && $mday >= 1
			&& $mday <= 31 && $hour >= 0 && $hour < 24 && $min >= 0 && $min < 60
			&& $sec >= 0 && $sec < 60)
			{
			# Time in seconds since Jan 1, 1970.
			$messageTime = timelocal_modern($sec, $min, $hour, $mday, $mon, $year);
			# Make it milliseconds, to agree with JavaScript down the road.
			$messageTime *= 1000;
			}
		}

	my $msg = 'changeDetected 0 ' . $filePath . '     ' . $messageTime;

	WebSocketSend($msg);
	}

sub ReportMissingFileWatcherLog {
	Monitor("ERROR, File Watcher log not found at |$FileWatcherLogPath|!\n");
	Monitor(" if you don't want to use File Watcher for real-time reindexing of your search folders, remove the line\n");
	Monitor("1	FILEWATCHER	Watcher		intramine_filewatcher.pl	BACKGROUND\n");
	Monitor("from your data/serverlist.txt file.\n");
	Monitor("Or perhaps the entry for FILEWATCHERDIRECTORY in data/intramine_config.txt needs updating?\n");
	Monitor("  (current log path is |$FileWatcherLogPath|)\n");
	Monitor("intramine_filewatcher.pl is stopping now. Bye.\n");
	}

# Can't simply read file backwards to the last position, since the File Watcher log is 
# archived and truncated periodically.
# So, remember the last time stamp, and read backwards until it's seen.
# We should be checking only once
# a minute at most, so that should save us from re-indexing the same file twice
# in a minute, but it's completely harmless if we accidentally do that.
# Retrieve paths of changed, renamed, and deleted files, back to time stamp from last
# check. If time stamp of last check is not seen, we call this a second time with the path
# of the newest archived log and $doingArchived == 1.
# The basic code here is "borrowed" from intramine_commandserver.pl#CommandOutput().
# Typical log lines:
#[2016-06-08 5:46:14 PM] [Info] File or folder changed (system generated) 'C:\perlprogs\mine\test\testcreate.txt'.
#[2016-06-08 6:43:45 PM] [Info] File or folder changed 'C:\perlprogs\mine\notes\server swarm.txt'.
sub GetChangesFromWatcherLogs {
	# Init module-scope variables.
	@PathsOfChangedFiles = (); 		# includes new files
	@PathsOfChangedFilesFileTimes = (); # time stamp from filewatcher log for same.
	%PathsOfCreatedFiles = (); 		# just new files, also helps when removing erroneous %PathsOfDeletedFiles entries
	%PathsOfDeletedFiles = ();
	@RenamedFolderPaths = ();		# holds full path to folder, with the new folder name
	@RenamedFilePaths = ();			# holds full path to renamed file, using the new name
	%TimeStampForPath = ();			# holds time a file changed, to the second
	
	%CurrentPathAlreadySeen = (); 	# Avoid doing the same file twice here, File Watcher can be a bit repetitive.
	$MostRecentTimeStampThisTimeAround = '';
	my $HaveSeenLastTime = 0;
	%FilesForMostRecentFileStamp = ();	# Files at end of current check (transferred to %FilesForLastFileStamp when done check)

	my $result = 0; # 0 == serious trouble, 1 == retrieval of changes went ok.
	my $gotEmAll = GetLogChanges($FileWatcherLogPath, 0);
	if ($gotEmAll < 0)
		{
		Monitor("***E-R-R-O-R***Could not open '$FileWatcherLogPath'!\n");
		return($result);
		}
	else
		{
		if (!$gotEmAll)
			{
			my $archivedNewestLogPath = MostRecentOldFileWatcherLogPath();
			if ($archivedNewestLogPath ne '')
				{
				$gotEmAll = GetLogChanges($archivedNewestLogPath, 1);
				if ($gotEmAll >= 0)
					{
					$result = 1;
					}
				else
					{
					Monitor("***E-R-R-O-R***Could not open '$archivedNewestLogPath'!\n");
					}
				}
			# else probably there is no archived watcher log yet
			}
		else
			{
			$result = 1;
			}
		}
		
	# Remember files seen for $MostRecentTimeStampThisTimeAround
	# (which becomes $LastTimeStampChecked for the next check).
	%FilesForLastFileStamp = %FilesForMostRecentFileStamp;
	$LastTimeStampChecked = $MostRecentTimeStampThisTimeAround;

	$result = 1;
	return($result);
	}
	
# Retrieve paths of changed, renamed, and deleted files, back to time stamp from last
# check. If time stamp of last check is not seen, we call this a second time with the path
# of the newest archived log and $doingArchived == 1.
# Returns 1 if saw last time check, 0 if not, but -1 if any error.
sub GetLogChanges {
	my ($logFilePath, $doingArchived) = @_;
	my $bw = File::ReadBackwards->new($logFilePath);
	if (!defined($bw))
		{
		Monitor("***E-R-R-O-R***Could not open '$logFilePath'!\n");
		return(-1);
		}

	my $lastDT;
	if ($doingArchived)
		{
		$lastDT = DateTimeFromLogString($LastTimeStampChecked);
		}
	my $line = '';
	my $lineCounter = 0;
	my $haveSeenLastTime = 0;
	my $wentPastLastTime = 0;
	# Read backwards. Notice the first timestamp this time around,
	# which at end becomes the $LastTimeStampChecked.
	# Continue while line timestamp differs from $LastTimeStampChecked.
	# Keep going while line timestamp *does* equal $LastTimeStampChecked,
	# but skip over files that were picked up last time for that time stamp.
	# Done when line timestamp again no longer equals $LastTimeStampChecked.
	# If there is no $LastTimeStampChecked, go through the whole file.
	# $LastTimeStampChecked is saved between runs (see SaveLastTimeStamp() below).
	# (On a restart, we will go through all files that have the last
	# saved timestamp. That's slightly inefficient, but Elasticsearch
	# can index very quickly, so that should be ok.)
	while (defined($line = $bw->readline))
		{
		++$lineCounter;
		chomp($line);
		$line = decode_utf8($line);
		
		# Testing suggests (system generated) entries are always duplicates.
		if ($line =~ m!^\[([^\]]+)\]\s+\[Info\]\s+File[^\']+'([^']+)'! &&
			index($line, "(system generated)") < 0)
			{
			my $timestamp = $1;
			my $pathProperCased = $2;
			$pathProperCased =~ s!\\!/!g;
			my $path = lc($pathProperCased);
			
			# SKIP all lines where folder or file name starts with a period.
			if ($path =~ m!/\.!)
				{
				next;
				}
			if ($MostRecentTimeStampThisTimeAround eq '')
				{
				$MostRecentTimeStampThisTimeAround = $timestamp;
				}
			
			if ($timestamp eq $MostRecentTimeStampThisTimeAround)
				{
				$FilesForMostRecentFileStamp{$path} = 1;
				}
			
			if ($timestamp ne $LastTimeStampChecked && $haveSeenLastTime)
				{
				$wentPastLastTime = 1;
				last;
				}
			
			if ($timestamp eq $LastTimeStampChecked)
				{
				$haveSeenLastTime = 1;
				}
				
			# In archived log, check to see if we've gone back too far in time.
			if ($doingArchived && !$haveSeenLastTime)
			#if ($doingArchived && ($lineCounter%20) == 0 && !$haveSeenLastTime)
				{
				my $dt = DateTimeFromLogString($timestamp);
				my $cmp = DateTime->compare_ignore_floating($lastDT, $dt);
				if ($cmp > 0)
					{
					Output("File Watcher log trouble, \$LastTimeStampChecked '$LastTimeStampChecked' not seen!\n");
					$wentPastLastTime = 1;
					last;
					}
				}
			
			# Skip file if we saw it with the same timestamp as $LastTimeStampChecked during the previous check.
			my $sawFileLastTime = ( ($timestamp eq $LastTimeStampChecked) && defined($FilesForLastFileStamp{$path}) );
			
			# Log lines will read File or folder changed/created/renamed/deleted.
			# Folder renamed if see renamed and quoted path is for a folder.
			if (!$sawFileLastTime)
				{
				# Skip if should ignore containing folder.
				if (ShouldIgnoreFile($path))
					{
					next;
					}
				if ($line !~ m!File or folder deleted!i)
					{
					if ($line =~ m!File or folder renamed!i)
						{
						if ($path !~ m!\.\w+$!)
							{
							push @RenamedFolderPaths, $pathProperCased;
							}
						else # regular file rename, not folder
							{
							push @RenamedFilePaths, $pathProperCased;
							}
						}
					elsif ($line =~ m!File or folder created!i)
						{
						$PathsOfCreatedFiles{$pathProperCased} += 1;
						}
					
					if (!defined($CurrentPathAlreadySeen{$path}))
						{
						push @PathsOfChangedFiles, $pathProperCased;
						push @PathsOfChangedFilesFileTimes, $timestamp;
						if (!defined($TimeStampForPath{$pathProperCased}))
							{
							my $timestampWithHyphens = $timestamp;
							$timestampWithHyphens =~ s!:!-!g;
							$TimeStampForPath{$pathProperCased} = $timestampWithHyphens;
							}
						}
						
					# If a file  is changed after delete/create, just show it as changed.
					if ($line =~ m!File or folder changed!i && $path =~ m!\.\w+$!)
						{
						$FileOnPathWasChanged{$pathProperCased} = 1;
						}

					$CurrentPathAlreadySeen{$path} = 1;
					}
				else
					{
					if (DeletedFileWasMemorable($pathProperCased))
						{
						$PathsOfDeletedFiles{$pathProperCased} = 1;
						}
					}
				} # if (!$sawFileLastTime)
			} # If it's an [Info] File ... line
		} # while (defined($line = $bw->readline))
	$bw->close();
	
	my $result = ($LastTimeStampChecked eq '' || $wentPastLastTime);
	$result = $result ? 1 : 0;
	return($result);
	}
	
# Remove Elasticsearch index entries for any files just deleted.
sub UpdateSearchIndexForDeletes {
	my ($pathsOfDeletedFilesH) = @_;
	
	foreach my $fullPath (keys %$pathsOfDeletedFilesH)
		{
		$ElasticIndexer->DeletePathFromIndex($fullPath);
		}
	
	$ElasticIndexer->Flush();
	}
} ##### IndexChangedFiles

sub GuessOldPathsForRenamedFiles {
	my ($numRenames, $renamedFolderPathsA, $oldFolderPathA) = @_;
	for (my $i = 0; $i < $numRenames; ++$i)
		{
		my $newFolderPath = $renamedFolderPathsA->[$i];
		$newFolderPath =~ s!\\!/!g;
		my $oldPath = BestGuessAtOldFolderPath($newFolderPath);
		push @$oldFolderPathA, $oldPath;
		}
	}

# Collect all old folder paths for renamed paths. Works for renamed files too.
sub GuessOldNamesPathsForRenamedFolders {
	my ($numRenames, $renamedFolderPathsA, $oldFolderPathA) = @_;
	for (my $i = 0; $i < $numRenames; ++$i)
		{
		my $newFolderPath = $renamedFolderPathsA->[$i];
		$newFolderPath =~ s!\\!/!g;
		my $oldPath = BestGuessAtOldFolderPath($newFolderPath);
		push @$oldFolderPathA, $oldPath;
		}
	}

# Check files C:/fwws/oldnew7.txt etc generated by foldermonitor.ps1,
# containing lines with old path | new path.
# Return old path for new if found, otherwise '';
sub BestGuessAtOldFolderPath {
	my ($newFolderPath) = @_;
	$newFolderPath = lc($newFolderPath);
	my @oldSubDirs;
	my $oldFolderPath = '';
	my $oldNewBasePath = CVal('FOLDERMONITOR_OLDNEWBASEPATH'); 	# eg C:/fwws/oldnew
	my $numOldNewMax = CVal('FOLDERMONITOR_NUMOLDNEWMAX'); 		# 10 or so
	my $foundIt = 0;
	
	for (my $i = 1; $i <= $numOldNewMax; ++$i)
		{
		my $oldNewPath = $oldNewBasePath . $i . '.txt'; # eg  C:/fwws/oldnew3.txt
		if (-f $oldNewPath)
			{
			my $fh = FileHandle->new("$oldNewPath") or return('');
			binmode($fh, ":encoding(UTF-8)");
			my $line = '';
			my $firstLine = 1;
			while ($line=<$fh>)
				{
				chomp($line);
				if ($firstLine)
					{
					$line =~ s/\A\N{BOM}//;
					$firstLine = 0;
					}
				
				my @oldnew = split(/\|/, $line);
				my $numParts = @oldnew;
				
				if ($numParts >= 2)
					{
					my $newPath = lc($oldnew[1]);
					$newPath =~ s!\\!/!g;
					
					if (!$foundIt && $newPath eq $newFolderPath)
						{
						my $oldPath = $oldnew[0]; # Note keeping original case
						$oldPath =~ s!\\!/!g;
						$oldFolderPath = $oldPath;
						$foundIt = 1;
						}
					}
				}
			close($fh);
			}
		if ($foundIt)
			{
			last;
			}
		}
	
	return($oldFolderPath);
	}

sub UpdateFullPathsForFileRenames {
	my ($numRenames, $renamedFilePathsA, $oldFilePathA) = @_;

	# Remove bad entries, where $oldFilePathA->[$i] is blank.
	my %newPathForOldPath;
	for (my $i = 0; $i < $numRenames; ++$i)
		{
		if ($oldFilePathA->[$i] ne '')
			{
			$newPathForOldPath{$oldFilePathA->[$i]} = $renamedFilePathsA->[$i];
			}
		}

	my $remainingRenameCount = %newPathForOldPath;
	if ($remainingRenameCount)
		{
		Monitor("Starting full paths update for file rename(s).\n");
		my $startTime = time;
		# Update reverse_filepaths.pm %FileNameForFullPath.
		UpdatePathsForFileRenames(\%newPathForOldPath);
		my $howItWent = ConsolidateFullPathLists(1); # 1 == force consolidation no matter what
		if ($howItWent ne "ok" && $howItWent ne "1")
			{
			Monitor("$howItWent\n");
			}
		my $endTime = time;
		my $elapsedSecs = int($endTime - $startTime + 0.5);
		Monitor("Full paths update for file rename(s) complete, took $elapsedSecs s.\n");
		# Now update Elasticsearch entries corresponding to the new paths.
		AskElasticsearchToUpdateFilePaths(\%newPathForOldPath);
		}

	return($remainingRenameCount);
	}

sub UpdateFullPathsForFolderRenames {
	my ($numRenames, $renamedFolderPathsA, $oldFolderPathA) = @_;
	my $numPathsChanged = 0;
	
	# Remove bad entries, where $oldFolderPathA->[$i] is blank.
	my @renamedFolderPaths;
	my @oldFolderPaths;
	for (my $i = 0; $i < $numRenames; ++$i)
		{
		if ($oldFolderPathA->[$i] ne '')
			{
			push @renamedFolderPaths, $renamedFolderPathsA->[$i];
			push @oldFolderPaths, $oldFolderPathA->[$i];
			}
		}
	
	my $remainingRenameCount = @renamedFolderPaths;
	if ($remainingRenameCount)
		{
		Monitor("Starting full paths update for folder rename.\n");
		my $startTime = time;
		my %newPathForOldPath;
		UpdatePathsForFolderRenames($remainingRenameCount, \@renamedFolderPaths, \@oldFolderPaths, \%newPathForOldPath);
		my $howItWent = ConsolidateFullPathLists(1); # 1 == force consolidation no matter what
		if ($howItWent ne "ok" && $howItWent ne "1")
			{
			Monitor("$howItWent\n");
			}
		my $endTime = time;
		my $elapsedSecs = int($endTime - $startTime + 0.5);
		Monitor("Full paths update for folder rename complete, took $elapsedSecs s.\n");
		
		# Now update Elasticsearch entries corresponding to the new paths.
		AskElasticsearchToUpdateFilePaths(\%newPathForOldPath);
		
		# Return rename count, if positive then Viewer(s) will be notified.
		$numPathsChanged = keys %newPathForOldPath;
		}
		
	return($numPathsChanged);
	}

# True if file exists and isn't a "nuisance" file and has a good extension.
sub FileShouldBeIndexed {
	my ($fullPath) = @_;
	my $result = 0;
	my $exists = FileOrDirExistsWide($fullPath);
	
	if ($exists == 1)
		{
		if (   $fullPath !~ m!/\.!
		  && !($SKIPLOGFILES && $fullPath =~ m!\.(log|out)$!i)
		  &&   $fullPath !~ m!/(temp|junk)/!i )
			{
			if (  EndsWithTextExtension($fullPath)
	          || ($IndexIfNoExtension && $fullPath !~ m!\.\w+$!)  )
	        	{
	        	$result = 1;
	        	}
			}
		}
	
	return($result);
	}

# True if path is for known image or video type and isn't a "nuisance" file. Note there is
# no check that the file exists. Image paths are remembered, though of course the
# image file itself is not sent to Elasticsearch.
sub IsImageOrVideoFilePath {
	my ($fullPath) = @_;
	my $result = 0;
	
	if ($fullPath !~ m!/\.! && $fullPath !~ m!/(temp|junk)/!i && EndsWithImageOrVideoExtension($fullPath))
		{
		$result = 1;
		}
	
	return($result);
	}

# "Memorable" if dir or file name doesn't start with a '.' and has a
# recognized extension (text or image).
# (Note /temp/ and /junk/ folders are no longer being skipped
# because sometimes a file there ends up masking the preferred path
# when inferring the best FLASH link.
sub DeletedFileWasMemorable {
	my ($fullPath) = @_;
	my $result = 0;
	if (   $fullPath !~ m!/\.!
	  && !($SKIPLOGFILES && $fullPath =~ m!\.(log|out)$!i) )
		{
		if (  EndsWithTextOrImageExtension($fullPath)
          || ($IndexIfNoExtension && $fullPath !~ m!\.\w+$!)  )
        	{
        	$result = 1;
        	}
		}
	
	return($result);
	}

# We handle new and changed, but not delete. I'm thinking the simplest way to "delete" a file
# from the Elasticsearch index is to re-index it with empty content, but haven't tried it.
# If a path is not of interest for either indexing or remembering for linking purposes
# it is set to '' here.
sub AskElasticsearchToIndexChanges {
	my ($pathsOfChangedFilesA) = @_;
	my $numPaths = @$pathsOfChangedFilesA;
	
	my $numIndexedPaths = 0;
	for (my $i = 0; $i < $numPaths; ++$i)
		{
		my $fullPath = $pathsOfChangedFilesA->[$i];
		if (FileShouldBeIndexed($fullPath))
			{
			my $fileName = FileNameFromPath($fullPath);
			Output("Index updated for |$fileName|, |$fullPath|\n");
			$ElasticIndexer->AddDocumentToIndex($fileName, $fullPath);
			++$numIndexedPaths;
#			if (($numIndexedPaths%500) == 0)
#				{
				#Output("  FLUSHING ES Indexer, and waiting a few...\n");
				#$ElasticIndexer->Flush();	
				#sleep(5);
#				}
			}
		else
			{
			if (!IsImageOrVideoFilePath($fullPath))
				{
				$pathsOfChangedFilesA->[$i] = '';
				}
			}
		}
	
	if ($numIndexedPaths)
		{
		$ElasticIndexer->Flush();
		}
	
	return($numIndexedPaths);
	}

sub AskElasticsearchToUpdateFilePaths {
	my ($newPathForOldPathH) = @_;
	
	Monitor("Updating Elasticsearch path entries for file or folder rename.\n");
	my $startTime = time;
	my $numIndexedPaths = 0;
	
	foreach my $oldpath (keys %$newPathForOldPathH)
		{
		if (FileShouldBeIndexed($newPathForOldPathH->{$oldpath}))
			{
			my $fileName = FileNameFromPath($oldpath);
			$ElasticIndexer->UpdatePath($fileName, $oldpath, $newPathForOldPathH->{$oldpath});
			++$numIndexedPaths;
#			if (($numIndexedPaths%500) == 0)
#				{
				#Output("  FLUSHING ES Indexer during path update, and waiting a few...\n");
				#$ElasticIndexer->Flush();	
				#sleep(5);
#				}
			}
		}
	$ElasticIndexer->Flush();
	sleep(1);
	
	my $endTime = time;
	my $elapsedSecs = int($endTime - $startTime + 0.5);
	Monitor("Elasticsearch path update complete, $numIndexedPaths paths updated, took $elapsedSecs s.\n");
	}

# "New" here means new to IntraMine. This includes truly new files "right now"
# and files that might have been changed recently while IntraMine was shut down,
# but have revealed themselves here after being changed, thanks to the tireless
# File Watcher service.
sub SaveAndRememberNewFullPaths {
	my ($pathsOfChangedFilesA, $newPathsH) = @_;
	my $numPaths = @$pathsOfChangedFilesA;
	my $numNew = 0;
	if ($numPaths)
		{
		#my %newPaths;
		for (my $i = 0; $i < $numPaths; ++$i)
			{
			if ($pathsOfChangedFilesA->[$i] ne '')
				{
				my $fullPath = lc($pathsOfChangedFilesA->[$i]);
				if (!FullPathIsKnown($fullPath))
					{
					$fullPath =~ m!/([^/]+)$!;
					my $fileName = $1;
					$newPathsH->{$fullPath} = $fileName;
					}
				}
			}
		$numNew = keys %$newPathsH;
		if ($numNew)
			{
			AddIncrementalNewPaths($newPathsH);
			SaveIncrementalFullPaths($newPathsH);
			}
		}
	
	return($numNew);
	}

# For the Status page, save a list of new/changed and deleted files.
# Here, "new" means newly created, as reported "just now" by File Watcher.
sub SaveChangedFilesList {
	my ($pathsOfChangedFilesA, $PathsOfChangedFilesFileTimesA, $pathsOfCreatedFilesH, $pathsOfDeletedFilesH) = @_;
	my $fileH = FileHandle->new("> $CudPath") or return;
	binmode($fileH, ":utf8");
	my $numChangedNew = @$pathsOfChangedFilesA;
	for (my $i = 0; $i < $numChangedNew; ++$i)
		{
		if ($pathsOfChangedFilesA->[$i] ne '')
			{
			my $newChanged = (defined($pathsOfCreatedFilesH->{$pathsOfChangedFilesA->[$i]})) ? 'NEW' : 'CHG';
			print $fileH "$pathsOfChangedFilesA->[$i]\t$newChanged $PathsOfChangedFilesFileTimesA->[$i]\n";
			}
		}
	foreach my $path (keys %$pathsOfDeletedFilesH)
		{
		print $fileH "$path\tDEL\n";
		}
	close($fileH);
	}

sub LoadLastTimeStamp {
	my $fileH = FileHandle->new("$TimeStampPath") or return(0);
	my $line = <$fileH>;
	chomp($line);
	$LastTimeStampChecked = $line;
	return(1);
	}

sub SaveLastTimeStamp {
	my $fileH = FileHandle->new("> $TimeStampPath") or return(0);
	print $fileH "$LastTimeStampChecked\n";
	close($fileH);
	return(1);
	}

sub IsGlossaryFile {
	my ($filePath) = @_;
	my $result = 0;
	if ($filePath =~ m!$GLOSSARYFILENAME$!i || $filePath =~ m!$STANDALONEGLOSSARYFILENAME$!i)
		{
		$result = 1;
		}
	
	return($result);
}

sub BroadcastDefinitionFilesChangedOrNew {
	my ($pathsOfChangedFilesA, $newPathsH) = @_;
	my $numPaths = @$pathsOfChangedFilesA;
	my $numNew = keys %$newPathsH;
	my %pathSeen; # Avoid broadcasting twice for the same file.
	
	if ($numPaths)
		{
		for (my $i = 0; $i < $numPaths; ++$i)
			{
			my $filePath = lc($pathsOfChangedFilesA->[$i]);
			if (IsGlossaryFile($filePath) && !defined($pathSeen{$filePath}))
				{
				RequestBroadcast('signal=glossaryChanged&path=' . $filePath);
				$pathSeen{$filePath} = 1;
				}
			elsif ($filePath =~ m!englishwords\.txt!i && !defined($pathSeen{$filePath}))
				{
				RequestBroadcast('signal=dictionaryChanged&path=' . $filePath);
				$pathSeen{$filePath} = 1;
				}
			}
		}
	if ($numNew)
		{
		keys %$newPathsH;
		while (my ($filePath, $fileName) = each %$newPathsH)
			{
			if (IsGlossaryFile($filePath) && !defined($pathSeen{$filePath}))
				{
				RequestBroadcast('signal=glossaryChanged&path=' . $filePath);
				$pathSeen{$filePath} = 1;
				}
			# The dictionary EnglishWords.txt should not be deleted and recreated,
			# but you never know....
			elsif ($filePath =~ m!englishwords\.txt!i && !defined($pathSeen{$filePath}))
				{
				RequestBroadcast('signal=dictionaryChanged&path=' . $filePath);
				$pathSeen{$filePath} = 1;
				}
			}
		}
	}

{ ##### Full paths consolidation
my $LastTimeChecked;
my $StartHour;
my $EndHour;
my $MinSecondsBetweenConsolidations;

# Consolidation occurs if at least $MinSecondsBetweenConsolidations has elapsed since
# startup or the last consolidation, within a window of opportunity (currently between
# $StartHour and $EndHour == 3 and 5 AM).
sub InitPeriodicConsolidation {
	$LastTimeChecked = time;
	# This is just for consolidation of the full path log files, which
	# only takes a few seconds so no maintenance outage is formally implemented, we
	# just do it in the dark of night.
	# Note SeemsLikeAGoodTimeToConsolidate() below also checks
	# that it's between (default) 3 and 5 AM local time. So $MinSecondsBetweenConsolidations
	# should not currently be set to less than 2 hours.
	$StartHour = CVal('FILEWATCHER_CONSOLIDATION_START_HOUR');
	if ($StartHour eq '')
		{
		$StartHour = 3;
		}
	$EndHour = CVal('FILEWATCHER_CONSOLIDATION_END_HOUR');
	if ($EndHour eq '')
		{
		$EndHour = 5;
		}
	$StartHour += 0;
	$EndHour += 0;
	
	$MinSecondsBetweenConsolidations = 3*60*60;
	}

# In the wee hours, when things seem quiet, combine fullpaths.out and
# fullpaths2.out into one file. Other servers need not know about this.
# Takes about one second per 10 MB of content in fullpaths.out.
# fullpaths.out size is roughly 10 MB per 100,000 files, or 100 bytes per file.
sub PeriodicallyConsolidate {
	my ($forceConsolidation) = @_;
	$forceConsolidation ||= 0;
	
	if ($forceConsolidation || SeemsLikeAGoodTimeToConsolidate())
		{
		RememberTimeOfLastConsolidation();
		my $startTime = time;
		my $howItWent = ConsolidateFullPathLists(0); # reverse_filepaths.pm#ConsolidateFullPathLists(), 0==no forcing
		if ($howItWent ne "" && $howItWent ne "ok" && $howItWent ne "1")
			{
			Monitor("$howItWent\n");
			}
		my $endTime = time;
		my $elapsedSecs = int($endTime - $startTime + 0.5);
		my $timeNow = NiceToday();
		my $addOn = ($elapsedSecs == 1) ? ' Erm, second.' : '';
		Monitor("File paths consolidated at $timeNow, took $elapsedSecs seconds.$addOn\n");
		
		# Clean out stale FileWatcher logs, as a nicety. It takes a while for them to pile up,
		# but at 10 MB each might as well get rid of them now and then.
		CleanOutOldFileWatcherLogs();
		}
	}

# If enough time has elapsed since startup or last consolidation, and it's
# in the wee hours of the morning....
sub SeemsLikeAGoodTimeToConsolidate {
	my $result = 0;
	my ($sec, $min, $hr, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
	if ($hr >= $StartHour && $hr <= $EndHour)
		{
		my $timeNow = time;
		my $diffSeconds = $timeNow - $LastTimeChecked;
		if ($diffSeconds >= $MinSecondsBetweenConsolidations)
			{
			$result = 1;
			}
		}
	
	return($result);
	}

sub RememberTimeOfLastConsolidation {
	$LastTimeChecked = time;
	}
} ##### Full paths consolidation

sub DeleteOldTempFiles {
	my @tempFileList;
	my $fileCountMax = 50;
	my $tempFileCount = GetTempFilesOlderFirst(\@tempFileList);

	if ($tempFileCount > $fileCountMax)
		{
		my $numFilesLeft = $tempFileCount;
		for (my $i = 0; $i < $tempFileCount; ++$i)
			{
			if (!DeleteFileWide($tempFileList[$i]))
				{
				Output("Error, could not delete |$tempFileList[$i]|!\n");
				Monitor("Error, could not delete |$tempFileList[$i]|!\n");
				last;
				}
			--$numFilesLeft;
			if ($numFilesLeft <= $fileCountMax)
				{
				last;
				}
			}
		}
	}

sub GetTempFilesOlderFirst {
	my ($sortedFileListA) = @_;
	my $LogDir = FullDirectoryPath('LogDir');
	my $tempDir = $LogDir . 'temp/';
	my @fileList;
	my @logFileList;
	my %modTimeForPath;
	
	GetTopFilesInFolder($tempDir, \@fileList);

	# Count old logs and get mod times.
	for (my $i = 0; $i < @fileList; ++$i)
		{
		my $mtime = GetFileModTimeWide($fileList[$i]);
		push @logFileList, $fileList[$i];
		my $j = @logFileList - 1;
		$modTimeForPath{$logFileList[$j]} = $mtime;
		}
		
	my $oldLogCount = @logFileList;
	if ($oldLogCount >= 1)
		{
		if ($oldLogCount == 1)
			{
			push @$sortedFileListA, $logFileList[0];
			}
		else
			{
			# Note older modTimes are smaller than newer, std sort order $a <=> $b works
			# since we want to delete older logs first.
			my @sortedFileList = sort {$modTimeForPath{$a} <=> $modTimeForPath{$b}} @logFileList;
			for (my $i = 0; $i < @sortedFileList; ++$i)
				{
				push @$sortedFileListA, $sortedFileList[$i];
				}
			}
		}
	
	return($oldLogCount);
	}

# FileWatcher logs are renamed and become inactive when log size reaches about 10 MB.
# Delete all but the latest two old logs.
sub CleanOutOldFileWatcherLogs {
	my @logFileList;
	my $oldLogCount = GetLogsOlderFirst(\@logFileList);

	if ($oldLogCount >= 3)
		{
		my $numLogsLeft = $oldLogCount;
		for (my $i = 0; $i < $oldLogCount; ++$i)
			{
			if (!DeleteFileWide($logFileList[$i]))
				{
				Output("Error, could not delete |$logFileList[$i]|!\n");
				Monitor("Error, could not delete |$logFileList[$i]|!\n");
				last;
				}
			--$numLogsLeft;
			if ($numLogsLeft <= 2)
				{
				last;
				}
			}
		}
	}

# Return path to most recent of the older FileWatcher logs.
sub MostRecentOldFileWatcherLogPath {
	my @logFileList;
	my $oldLogCount = GetLogsOlderFirst(\@logFileList);
	my $result = '';
	if ($oldLogCount >= 1)
		{
		$result = $logFileList[$oldLogCount - 1];
		}
	
	return($result);
	}

sub GetLogsOlderFirst {
	my ($sortedFileListA) = @_;
	my $filewatcherDir = DirectoryFromPathTS($FileWatcherLogPath);
	my @fileList;
	my @logFileList;
	my %modTimeForPath;
	
	GetTopFilesInFolder($filewatcherDir, \@fileList);

	# Count old logs and get mod times.
	for (my $i = 0; $i < @fileList; ++$i)
		{
		my $mtime = GetFileModTimeWide($fileList[$i]);
		if ($fileList[$i] =~ m!/([^/]+)$!)
			{
			my $fileName = $1;
			# fwatcher_97c28b86463842319f597d4710311fdc.log
			if ($fileName =~ m!^fwatcher_\w\w\w\w\w\w+\.log$!)
				{
				push @logFileList, $fileList[$i];
				my $j = @logFileList - 1;
				$modTimeForPath{$logFileList[$j]} = $mtime;
				}
			}
		}
		
	my $oldLogCount = @logFileList;
	if ($oldLogCount >= 1)
		{
		if ($oldLogCount == 1)
			{
			push @$sortedFileListA, $logFileList[0];
			}
		else
			{
			# Note older modTimes are smaller than newer, std sort order $a <=> $b works
			# since we want to delete older logs first.
			my @sortedFileList = sort {$modTimeForPath{$a} <=> $modTimeForPath{$b}} @logFileList;
			for (my $i = 0; $i < @sortedFileList; ++$i)
				{
				push @$sortedFileListA, $sortedFileList[$i];
				}
			}
		}
	
	return($oldLogCount);
	}

{ ##### DateTime
my $TZ;

# Call this before DateTimeFromLogString();
sub SetTimeZone {
	$TZ = DateTime::TimeZone->new( name => 'local' );
	}

sub LooksLikeLogDateString {
	my ($datStr) = @_;
	my $result = 0;
	# '2019-10-20 6:09:02 PM'
	if  ($datStr =~ m!^\d\d\d\d\-\d+\-\d+\s+\d+\:\d+\:\d+\s+(AM|PM)$!)
		{
		$result = 1;
		}
	return($result);
	}

sub DateTimeFromLogString {
	my ($datStr) = @_;
	if (!LooksLikeLogDateString($datStr))
		{
		return '';
		}
	$datStr =~ m!^(\d\d\d\d)\-(\d+)\-(\d+)\s+(\d+)\:(\d+)\:(\d+)\s+(AM|PM)$!;
	my $yr = $1;
	my $mo = $2;
	my $dy = $3;
	my $hr = $4;
	my $mn = $5;
	my $s = $6;
	my $ampm = $7;
	if ($ampm eq 'PM')
		{
		$hr += 12;
		if ($hr >= 24)
			{
			$hr = 0;
			}
		}
	
	my $dt = DateTime->new(
    year       => $yr,
    month      => $mo,
    day        => $dy,
    hour       => $hr,
    minute     => $mn,
    second     => $s,
    time_zone  => $TZ
	);
	
	return($dt);
	}
} ##### DateTime

{ ##### PowerShell folder monitor start/stop
my $PowerShellProc;

# Start bats/foldermonitor.ps1, which sends a signal when a file or folder changes, and writes the
# old and new name of a folder to a file when a folder is renamed.
sub StartPowerShellFolderMonitor {
	
	# Get main port number from config, data/intramine_config.txt.
	my $mainPortNumber = CVal('INTRAMINE_MAIN_PORT');
	my $folderMonitorListPath = FullDirectoryPath('FOLDERMONITOR_FOLDERLISTPATH');
	$folderMonitorListPath =~ s!/!\\!g;
	my $oldNewBasePath = CVal('FOLDERMONITOR_OLDNEWBASEPATH'); 	# eg C:/fwws/oldnew
	$oldNewBasePath =~ s!/!\\!g;
	my $fmChangeSignal = CVal('FOLDERMONITOR_CHANGE_SIGNAL'); # default /?signal=FILESYSTEMCHANGE&name=Watcher
	my $fmHeartbeatSignal = CVal('FOLDERMONITOR_HEARTBEAT_SIGNAL'); # default /?signal=HEARTBEAT&name=Watcher
	
	my $powerShellPath = "C:\\Windows\\System32\\WindowsPowershell\\v1.0\\powershell.exe";
	my $foldermonitorPSPath = FullDirectoryPath('FOLDERMONITOR_PS1_FILE'); # ...bats/foldermonitor.ps1
	# Arguments for $foldermonitorPSPath script:
	# Perl						PowerShell
	# $mainPortNumber 			$mainPort = $args[0], port number of Main (default 81)
	# $folderMonitorListPath 	$dirListPath = $args[1], holds list of directories to monitor
	# $oldNewBasePath 			$global:oldNewBasePath = $args[2], base file name for old and new names of renamed dir
	my $powerShellArgs = "-NoProfile -ExecutionPolicy Bypass -InputFormat None -File \"$foldermonitorPSPath\" $mainPortNumber \"$folderMonitorListPath\" \"$oldNewBasePath\" \"$fmChangeSignal\" \"$fmHeartbeatSignal\"";
	my $result = Win32::Process::Create($PowerShellProc, $powerShellPath, $powerShellArgs, 0, 0, ".");
	if ($result == 0)
		{
		Monitor("WARNING, could not start |$foldermonitorPSPath|.\n");
		}
	return($result);
	}

sub StopPowerShellFolderMonitor {
	my $exitcode = 1;
	$PowerShellProc->GetExitCode($exitcode);
	if ($exitcode == STILL_ACTIVE)
		{
		$PowerShellProc->Kill(0);
		# Doesn't help, IM START window stays up: $PowerShellProc->Wait(2000);
		}
	}

sub RestartFolderMonitor {
	Monitor("bats/foldermonitor.ps1 is slow or not running.\n");
	Monitor("If you see this message repeatedly, and you have not\n");
	Monitor("just dumped a huge number of files into an indexed folder,\n");
	Monitor("please read /Documentation/Unblocking foldermonitor.html.\n");
	Monitor("Restarting foldermonitor.ps1...\n");
	StopPowerShellFolderMonitor();
	# 1 millisecond == 1000 microseconds
	usleep(300000); # 0.3 seconds
	my $result = StartPowerShellFolderMonitor();
	if ($result)
		{
		Monitor("foldermonitor.ps1 restart attempt complete.\n");
		}
	}
} ##### PowerShell folder monitor start/stop
1;