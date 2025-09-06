# make_filewatcher_config.pl: write a new configuration file for File Watcher, to watch
# all directories listed in /data/search_directories.txt. The File Watcher config file
# path is assumed to be listed in /data/intramine_config.txt as 'FWWS_CONFIG', typically
# C:/fwws/fwatcher.xml.
# CHANGE that entry if you have installed the File Watcher service ('fwws') to
# a different folder.
# Also make data/foldermonitorlist.txt, used by bats/foldermonitor.ps1 to know
# which folders to monitor in "real time".
# After running this program, fwatcher.xml will contain <config> entries for all
# directories that are listed in search_directories, and any old version of
# fwatcher.xml will be renamed to fwatcher.xml.old.
# NOTE this program will stop and start "File Watcher Windows Service", to pick up
# the config changes. In order to do so, this program must be run using
# "Run as administrator".
#
# A manual stop/start of the File Watcher service is not needed here, but
# if you ever need to do that:
# at a cmd prompt,
# sc stop "File Watcher Windows Service"
# sc start "File Watcher Windows Service"
# or use services.msc and look for "File Watcher Windows Service".
#
# The <config> entries work with File Watcher "4.3.0.0_bin_45". If you have a later
# version of File Watcher and want to be sure this program will produce the right results,
# use your version of File Watcher Simple to configure a directory to watch, then
# open data/fwws_config_template.txt, use that as a guide to put _NAME_ and _PATH_NO_TS_
# placeholders in your new version, and then save the result over data/fwws_config_template.txt.
# (names get subtly confusing here, File Watcher Simple is an app found in a folder whose name
# starts with 'fws...' in the folder containing your File Watcher download, whereas the File
# Watcher Windows Service is in 'fwws...', so look for the extra w).

# perl C:\perlprogs\mine\make_filewatcher_config.pl

use strict;
use utf8;
use FileHandle;
use Win32::RunAsAdmin qw(force);
use Path::Tiny        qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use intramine_config;

# if (not Win32::RunAsAdmin::check) {
#    print("Sorry, this program must be started with administrator privileges.\n");
#    print("If you started this by running a shortcut to a .bat file,\n");
#    print("right-click on the shortcut, select Properties->Shortcut->Advanced...->Run as administrator,\n");
#    print("then run your shortcut again.\n");
#    print("If you started this by running perl at a cmd prompt, try again in a new cmd prompt\n");
#    print("window started by right-clicking and choosing \"Run as administrator\".\n");
#    print("This program will end with exit(1) now, terminating any .bat file that invoked it.\n");
#    exit(1);
# }


my $TESTING = 0;    # ==1: make fwatcher.xml.txt instead of fwatcher.xml.

select((select(STDOUT), $| = 1)[0])
	;               # Unbuffer output, in case we are being called from the Intramine Cmd page.

SetCommonOutput(\&Output);    # common.pm

LoadConfigValues();           # intramine_config.pm

# Stop and start the File Watcher service, to pick up the config changes made here.
my $startFileWatcherServicePath = FullDirectoryPath('FILEWATCHER_START_SERVICE');
my $stopFileWatcherServicePath  = FullDirectoryPath('FILEWATCHER_STOP_SERVICE');
if (!(-f $startFileWatcherServicePath))
	{
	die(
"Maintenance error, FILEWATCHER_START_SERVICE is incorrect in data/intramine_config.txt! Expecting path to start_filewatcher_service.bat."
	);
	}
if (!(-f $stopFileWatcherServicePath))
	{
	die(
"Maintenance error, FILEWATCHER_STOP_SERVICE is incorrect in data/intramine_config.txt! Expecting path to stop_filewatcher_service.bat."
	);
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
my $EntryTemplatePath     = FullDirectoryPath('FWWS_ENTRY_TEMPLATE');
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

Output("Done, $EntryCount directories will be monitored by File Watcher, see |$ConfigFilePath|.\n");


############## subs
sub Output {
	my ($txt) = @_;
	print("$txt");
}

# Make a new File Watcher config file specifying which directories to monitor.
# A template with placeholders ($entryTemplatePath) is used to stamp out XML entries for each
# directory to monitor using entries in $searchDirectoriesPath. Only the entries in that
# file with "Monitor" set to 1 are done.
sub MakeConfigFiles {
	my ($configFilePath, $entryTemplatePath, $searchDirectoriesPath) = @_;
	my $configTemplate = LoadConfigTemplate($entryTemplatePath);
	die("Error, |$entryTemplatePath| is missing or empty!") if ($configTemplate eq '');
	my %daemonNames;    # Avoid duplicate <daemonName> entries in fwatcher.xml
	my %loadedDirs;
	my $dirCount = 0;

	if (-f $searchDirectoriesPath)
		{
		my %indexDummyHash;
		LoadSearchDirectoriesToHashes($searchDirectoriesPath, \%indexDummyHash, \%loadedDirs);
		}
	else
		{
		print("ERROR, |$searchDirectoriesPath| not found!");
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
			my $after  = $configFilePath . '.old2';
			rename($before, $after)
				or die("File error, could not rename |$before| to |$after|!");
			}
		my $before = $configFilePath;
		my $after  = $configFilePath . '.old';
		unlink($after);
		rename($before, $after)
			or die("File error, could not rename |$before| to |$after|!");
		}

	my $configXML = '<?xml version="1.0" standalone="yes"?>' . "\n<fWatcherConfig>\n";

	my @configEntries;
	foreach my $dir (sort keys %dirs)
		{
		my $currentTemplate = $configTemplate;
		my $name            = '';
		# Pick up last dir name, use it as <config> item <daemonName>
		if ($dir =~ m!([^\\/]+)$!)
			{
			$name = $1;
			}
		elsif ($dir =~ m!\:!)    # $dir is a drive letter, eg H:\
			{
			$name = $dir;
			$name =~ s!\W!!g;
			}
		else
			{
			if ($dir =~ m!([^\\/]+)[\\/]*?$!)    # not needed - if a slash on the end snuck through
				{
				$name = $1;
				}
			}

		if ($name ne '')
			{
			# Avoid duplicate names.
			my $baseName  = $name;
			my $increment = 1;
			my $newName   = $name;
			while (defined($daemonNames{$newName}))
				{
				$newName = $name . '_' . $increment;
				++$increment;
				}
			$name = $newName;
			$daemonNames{$name} = 1;

			$currentTemplate =~ s!_NAME_!$name!;
			$currentTemplate =~ s!_PATH_NO_TS_!$dir!;    # <path> entry, no Trailing Slash
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

	return ($dirCount);
}

# Winnow %$loadedDirs_H, to avoid nested directories. Also normalize the entries for use
# by File Watcher (use back slashes).
sub GetDirsToMonitor {
	my ($loadedDirs_H, $dirsH) = @_;

	my %rawDirs;
	foreach my $dir (sort keys %$loadedDirs_H)
		{
		$dir =~ s!/!\\!g;      # Use backslashes
		$dir =~ s![\\/]$!!;    # Trim any trailing slash
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
	return ($dirCount);
}

# Load the template for one directory entry in File Watcher's XML config file.
sub LoadConfigTemplate {
	my ($filePath) = @_;

	my $result = '';
	my $fh     = FileHandle->new("$filePath") or return $result;
	my $line   = '';
	my @lines;
	while ($line = <$fh>)
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
	my $fh                          = FileHandle->new(">$folderMonitorFolderListPath")
		or die("File error, could not open |$folderMonitorFolderListPath|!");
	foreach my $dir (sort keys %$dirsH)
		{
		print $fh "$dir\n";
		}
	close($fh);
}
