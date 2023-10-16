# intramine_config.pm: common config values for IntraMine, as
# retrieved from the main configuration file /data/intramine_config.txt.

package intramine_config;
use warnings;
require Exporter;
use Exporter qw(import);

use strict;
use utf8;
use FileHandle;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
#use lib ".";
use common;
use win_wide_filepaths;

{ ##### Config values
my %ConfigValues;
my $ScriptFullDirTS; # TS == Trailing Slash
my @AdditionalConfigFileNames;

# An IntraMine swarm server can load config values by calling swarmserver.pm#SSInitialize()
# which in turn calls this sub.
# See any std server near the top for the SSInitialize() call.
# If $extraConfigName is supplied, also attempt to load config values from
# data/$extraConfigName . _config.txt.
# For example, the DBX server has its own config file data/DBX_config.txt.
# $extraConfigName is optional and no error is raised if the file isn't found.
# SSInitialize() will pass the server's Short name as $extraConfigName, eg it will pass
# "DBX" for the intramine_db_example.pl server.
sub LoadConfigValues {
	my ($extraConfigName, $extraConfigName2) = @_;
	$extraConfigName ||= '';
	$extraConfigName2 ||= '';
	
	my $scriptFullPath = $0; # path of calling program
	my $scriptName = FileNameFromPath($scriptFullPath);
	my $configFileName = "intramine_config.txt";
	my $scriptFullDir = DirectoryFromPathTS($scriptFullPath);
	$ScriptFullDirTS = $scriptFullDir;
	my $configFilePath = $ScriptFullDirTS . "data/$configFileName";
	
	# Typically the calling program is in something like '.../mine/', 
	# (where 'mine' is the name of the IntraMine folder)
	# but if the caller is in say
	# '.../mine/test/' then we need to pop one dir off the end of
	# $ScriptFullDirTS to compensate for the calling program being down
	# an extra level. Or maybe two levels in '.../mine/test/unicode test/, so we just keep
	# popping and checking until we find '.../mine/data/intramine_config.txt'.
	while (!(-f $configFilePath))
		{
		if ($ScriptFullDirTS !~ m![^/]/$!)
			{
			last;
			}
		$ScriptFullDirTS =~ s![^/]+/$!!;
		$configFilePath = $ScriptFullDirTS . "data/$configFileName";
		}
	
	if (-f $configFilePath)
		{
		my $numConfigEntries = 
			LoadKeyMultiTabValueHashFromFile(\%ConfigValues, $configFilePath, "", 1);
		if ($numConfigEntries == 0)
			{
			die("ERROR could not load config file |$configFilePath|!\n");
			}
		else
			{
			LoadNumberedConfigFiles($configFileName);
			}
		}
	else
		{
		die("No config file found at |$configFilePath|! Please see 'IMPORTANT Make your own data folder' in /Documentation/IntraMine initial install.txt (or .html).\n");
		}
		
	# Load any extra config file if it exists, eg data/DBX_config.txt for the DBX server.
	if ($extraConfigName ne '')
		{
		my $serverConfigPath = $ScriptFullDirTS . "data/$extraConfigName" . '_config.txt';
		if (-f $serverConfigPath)
			{
			my $numConfigEntries = 
			LoadKeyMultiTabValueHashFromFile(\%ConfigValues, $serverConfigPath, "", 1);
			LoadNumberedConfigFiles($extraConfigName . '_config.txt');
			}
		# else no error, the server config file is optional.
		}
	
	if ($extraConfigName2 ne '')
		{
		my $serverConfigPath = $ScriptFullDirTS . "data/$extraConfigName2" . '_config.txt';
		if (-f $serverConfigPath)
			{
			my $numConfigEntries = 
			LoadKeyMultiTabValueHashFromFile(\%ConfigValues, $serverConfigPath, "", 1);
			LoadNumberedConfigFiles($extraConfigName2 . '_config.txt');
			}
		# else no error, the server config file is optional.
		}

	}

# Requires: the "base" config file has loaded. The "base" can be either the standard
# config file "intramine_config.txt" or a server-specific file such as DBX_config.txt.
# For intramine_config.txt load any existing intramine_config_NNN.txt in the same folder,
# where NNN is a sequence of one or more digits.
# Similarly for DBX load any additional existing DBX_config_NNN.txt files.
# The numbers NNN don't have to be in sequence.
# Config files are loaded in ascending numerical order.
sub LoadNumberedConfigFiles {
	my ($configFileName) = @_; # eg intramine_config.txt or DBX_config.txt
	my ($baseName, $ext) = FileNameProperAndExtensionFromFileName($configFileName);
	if ($ext eq '')
		{
		return;
		}
	
	my $dir = "$ScriptFullDirTS" . 'data/';
	my @allTopLevelItems = FindFileWide($dir);
	my @configFileNames;
	my @configFileNumbers;
	for (my $i = 0; $i < @allTopLevelItems; ++$i)
		{
		if ($allTopLevelItems[$i] =~ m!$baseName\_(\d+)$ext$!i)
			{
			my $configNumber = $1;
			push @configFileNames, $allTopLevelItems[$i];
			push @AdditionalConfigFileNames,  $allTopLevelItems[$i];
			push @configFileNumbers, $configNumber;
			}
		}
		
	my @idx = sort {$configFileNumbers[$a] <=> $configFileNumbers[$b]} 0..$#configFileNumbers;
	@configFileNames = @configFileNames[@idx];
	for (my $i = 0; $i < @configFileNames; ++$i)
		{
		my $configFilePath = $dir . $configFileNames[$i];
		LoadKeyMultiTabValueHashFromFile(\%ConfigValues, $configFilePath, "", 1);
		}
	}

sub GetAdditionalConfigFileNames {
	my ($configNamesA) = @_;
	@$configNamesA = @AdditionalConfigFileNames;
	}

# Look in the /_copy_and_rename_to_data folder, copy any files there that
# aren't yet in the /data folder to the /data folder.
# Called at intramine_main.pl#118, before any services load config values.
sub CopyNewConfigFiles {
	my $scriptFullPath = $0; # path of calling program, normally for intramine_main.pl
	my $scriptFullDir = DirectoryFromPathTS($scriptFullPath);
	my $copyFromDirectory = $scriptFullDir . '_copy_and_rename_to_data/';
	my $destinationDirectory = $scriptFullDir . 'data/';
	
	my @allCopyFromItems = FindFileWide($copyFromDirectory);
	my @existingDestinationItems = FindFileWide($destinationDirectory);
	
	my %DestFileNameExists;
	for (my $i = 0; $i < @existingDestinationItems; ++$i)
		{
		$DestFileNameExists{$existingDestinationItems[$i]} = 1;
		}
	
	for (my $i = 0; $i < @allCopyFromItems; ++$i)
		{
		my $srcPath = $copyFromDirectory . $allCopyFromItems[$i];
		if (   !defined($DestFileNameExists{$allCopyFromItems[$i]})
			&& FileOrDirExistsWide($srcPath) == 1 )
			{
			my $destPath = $destinationDirectory . $allCopyFromItems[$i];
			my $noFailIfExists = 0; # Suppress fail if file exists
			CopyFileWide($srcPath, $destPath, $noFailIfExists);
			print("NEW CONFIG FILE |$allCopyFromItems[$i]| copied from _copy_and_rename_to_data/ to data/.\n");
			}
		}
	}

# Value for a config name, eg CVal('IMAGES_DIR') == 'images_for_web_server/'.
# These can be values loaded from the config file via LoadConfigValues() above, or values
# dynamically set while running (eg 'OverdueCount')
sub CVal {
	my ($name) = @_;
	my $val = '';
	if (!defined($ConfigValues{$name}))
		{
		print("ERROR, no config value found for |$name|\n");
		}
	else
		{
		$val = $ConfigValues{$name};
		}
	
	return($val);
	}

# Set value for a key, available to all servers using serverswarm.pm, or this module directly.
# Eg SetCVal('OverdueCount', $count);
# Use LoadConfigValues() above to load fixed persistent config values, and SetCVal() to set dynamic ones.
# Note config values are not currently saved back to disk, so the persistent values are 'fixed' in the sense
# that you have to change them in the config file itself (data/intramine_config.txt).
sub SetCVal {
	my ($name, $val) = @_;
	$ConfigValues{$name} = $val;
	return($val);
	}
	
sub ConfigHashRef {
	return(\%ConfigValues);
}

# Dir paths are typically in two pieces: the dir for this module, and the path down from there to the wanted directory
# Eg 'C:/perlprogs/mine/' . 'images_for_seb_server/'   where $name == 'IMAGES_DIR'
sub FullDirectoryPath {
	my ($name) = @_;
	my $result = '';
	
	my $val = CVal($name);
	if ($val ne '')
		{
		# If retrieved path starts with colon then just prepend CVal('DRIVELETTER').
		# Otherwise, prepend $ScriptFullDirTS.
		# Eg ':/common/images/' becomes CVal('DRIVELETTER') . ':/common/images/', typically CVal('DRIVELETTER') is 'C'.
		# And if retrieved path is 'images_for_web_server/' and $ScriptFullDirTS is 'C:/perlprogs/mine/'
		# then returned path is 'C:/perlprogs/mine/images_for_web_server/'.
		if (substr($val, 0, 1) eq ':')
			{
			$result = CVal('DRIVELETTER') . $val;
			}
		else
			{
			$result = $ScriptFullDirTS . $val;
			}
		}
	
	return($result);
	}

# Valid after call to LoadConfigValues() above.
sub BaseDirectory {
	return($ScriptFullDirTS);
	}

# Save extra value(s) to a specially named config file.
# Eg SaveExtraConfigValues('SRVR', $h) with $h->{'SERVER_ADDRESS'} = 1.2.3.4
# will save the $h hash to data/MAIN_config.txt.
# And LoadConfigValues('SRVR') will read the 'SERVER_ADDRESS' key/value into %ConfigValues.
sub SaveExtraConfigValues {
	my ($extraConfigName, $h) = @_;
	my $scriptFullPath = $0; # path of calling program
	my $scriptFullDir = DirectoryFromPathTS($scriptFullPath);
	my $configFilePath = $ScriptFullDirTS . "data/$extraConfigName" . '_config.txt';
	my %extraValues = %$h;

	# First load any existing values from the file.
	my %allValues;
	LoadKeyMultiTabValueHashFromFile(\%allValues, $configFilePath, "", 1);
	# Add in the new values.
	foreach my $key (sort(keys %extraValues))
		{
		$allValues{$key} = $extraValues{$key};
		}
	# Write out the new values (plus existing unchanged values).
	SaveKeyTabValueHashToFile(\%allValues, $configFilePath, '');
	# Put all values in %ConfigValues.
	foreach my $key (sort(keys %allValues))
		{
		$ConfigValues{$key} = $allValues{$key};
		}
	}
} ##### Config values

# Search directory list, load to hashes or arrays. There are two hashes or arrays, one for
# directories to monitor (with File Watcher) and one for dirs to initially index with Elasticsearch.
# Entries in $filePath (default data/search_directories.txt) should have the form
# Location<tabs>Index<tabs>Monitor
# "Location" can be a directory (C:/Common or C:\Common) or
# host\share name (\\Desktop-hjrpnqo\ps - note backslashes only).
# "Index" 1 means add all contained files to Elasticsearch index
#  during initial indexing, and also note the file paths.
# "Monitor" 1 means update Elasticsearch and file paths on any changes to the location.
# Comment lines starting with 'whitespace*#' are skipped.
# Both subs below return 1 if anything is loaded, 0 otherwise.
sub LoadSearchDirectoriesToHashes {
	my ($filePath, $indexThesePathsH, $monitorThesePathsH) = @_;
	my $fileH = FileHandle->new("$filePath") or return(0);
	
	binmode($fileH, ":utf8");
	my $line;
	
	while ($line = <$fileH>)
    	{
        chomp($line);
        if (length($line) && $line !~ m!^\s*#!)
         	{
        	my @kv = split(/\t+/, $line, 3);
        	my $numEntriesOnLine = @kv;
        	if ($numEntriesOnLine == 3)
        		{
        		if ($kv[1] eq '1') # Index
        			{
        			$indexThesePathsH->{$kv[0]} = 1;
        			}
        		if ($kv[2] eq '1') # Monitor
        			{
        			$monitorThesePathsH->{$kv[0]} = 1;
        			}
         		}
        	}
        }
    close $fileH;
    
    my $count = keys %$indexThesePathsH;
    $count += keys %$monitorThesePathsH;
    my $result = ($count) ? 1 : 0;
	return($result);
	}

# Like above, but arrays instead of hashes.
sub LoadSearchDirectoriesToArrays {
	my ($filePath, $indexThesePathsA, $monitorThesePathsA) = @_;
	my $fileH = FileHandle->new("$filePath") or return(0);
	
	binmode($fileH, ":utf8");
	my $line;
	
	while ($line = <$fileH>)
    	{
        chomp($line);
        if (length($line) && $line !~ m!^\s*#!)
         	{
        	my @kv = split(/\t+/, $line, 3);
        	my $numEntriesOnLine = @kv;
        	if ($numEntriesOnLine == 3)
        		{
        		if ($kv[1] eq '1') # Index
        			{
        			push @$indexThesePathsA, $kv[0];
        			}
        		if ($kv[2] eq '1') # Monitor
        			{
        			push @$monitorThesePathsA, $kv[0];
        			}
         		}
        	}
        }
    close $fileH;
    
    my $count = @$indexThesePathsA;
    $count += @$monitorThesePathsA;
    my $result = ($count) ? 1 : 0;
	return($result);
	}


use ExportAbove;
1;
