# max_folder_depth.pl: find the deepest subfolder in Elasticsearch indexed folders.
# This is largely stolen from elastic_indexer.pl.
# Why? IntraMine's Elasticsearch index has a fixed number of folder-related fields,
# with the hard-coded names folder1, folder2, folder3,...folder32. 32 was chosen as the
# maximum after running this program and seeing a maxumum folder depth of 20.
# see elasticsearch_bulk_indexer.pm#AddDocumentToIndex().

# perl C:\perlprogs\mine\max_folder_depth.pl

use strict;
use utf8;
use FileHandle;
use File::Find;
use Math::SimpleHisto::XS;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use intramine_config;

LoadConfigValues();				# intramine_config.pm

# Hack, tired of indexing hundreds of log files, so optionally skip any
# file with a .log or .out extension. See DoOne() below.
my $SKIPLOGFILES = 1;

# Optionally allow files with no extension.
# !!NOTE!! Setting ES_INDEX_NO_EXTENSION to 1 is COMPLETELY UNTESTED!
my $IndexIfNoExtension = CVal('ES_INDEX_NO_EXTENSION');

# Load up list of directories to index.
my @DirectoriesToIndex;
my @DirectoriesToIgnore;
LoadDirectoriesToIndex();


my $MaximumDepth = 0;
my $PathForMaximumDepth = '';
my $numDirs = @DirectoriesToIndex;
for (my $i = 0; $i < $numDirs; ++$i)
	{
	if ($DirectoriesToIndex[$i] eq '_INTRAMINE_') # Meaning the dir that holds this program, and by default all IntraMine files
		{
		$DirectoriesToIndex[$i] = path($0)->absolute->parent->stringify;
		}
	Output("Getting paths to $DirectoriesToIndex[$i]...\n");
	finddepth(\&DoOne, $DirectoriesToIndex[$i]);
	}

Output("Max depth $MaximumDepth for |$PathForMaximumDepth|\n");
Output("Done.\n");

########## subs
############## subs
sub Output {
	my ($txt) = @_;
	print("$txt");
	}

sub LoadDirectoriesToIndex {
	my $configFilePath = FullDirectoryPath('ELASTICSEARCHDIRECTORIESPATH');
	my $dirCount = 0;
	
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
		
	return($dirCount); # not currently used
	}

# Pick up lists of all files in all directories to index, one file at a time. Called by
# finddepth() above.
sub DoOne {
	my $sourceFileName = $_;
    my $sourceFileFullPath = $File::Find::name;
    if ($_ eq "." || ! -f $sourceFileFullPath)
		{
		;# not a file
		return;
		}
    # else it's a file.
    else
        {
		# Full path list. Set %rawPathList for *all* files, eg to pick up folders that are all images.
		my $pathForwardSlashes = lc($sourceFileFullPath);
		$pathForwardSlashes =~ s![\\]!/!g;
		if (!ShouldIgnoreFile($pathForwardSlashes))
			{
			my $slashCount = $pathForwardSlashes =~ tr!/!!;
			if ($MaximumDepth < $slashCount)
				{
				$MaximumDepth = $slashCount;
				$PathForMaximumDepth = $pathForwardSlashes;
				Output ("Depth $MaximumDepth for |$PathForMaximumDepth|\n");
				}
			}
        }
	}

# Ignore file path if it starts with path to a folder to ignore, as
# listed in data/search_directories.txt. Comparisons are done
# in lower case with forward slashes only.
sub ShouldIgnoreFile {
	my ($fullPath) = @_; # lc, / only
	#$fullPath = lc($fullPath);
	#$fullPath =~ s!\\!/!g;
	my $result = 0;

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

