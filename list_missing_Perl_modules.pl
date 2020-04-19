# list_missing_Perl_modules.pl: list modules that are missing based on "use" in a Perl file
# or all Perl files at the top of a folder, and generate a bat file that can be run manually
# to install the modules. Examines given file, or for a folder examines all
# .pl and .pm files at the top level only of the folder. Output to the bat file is in the form of
# "ppm install moduleName" lines for the missing modules, with bat file name
# "install_these_modules_NNN.bat" where "NNN" just makes the file name unique.
# The bat file is saved in either i) if a single file name was supplied, at the top of
# same folder as the file, or ii) if a folder path was supplied, within the specified
# folder at the top level.
# Run the resulting .bat file if you want to install the missing modules (more on that just below).
# Only the first error in each file is reported, so run this program repeatedly until
# it reports "No missing modules, no output file was created." You can copy/paste
# the path to the .bat file to run it, from the second-last line printed by this program
# to stdout. Example output:
## ...
## 2 missing modules detected, see |C:/perlprogs/test/install_these_modules_3.bat|
## Run the .bat file now by copying and pasting the following line:
## C:/perlprogs/test/install_these_modules_3.bat
## Done.
#
# This program asks Perl to do a syntax check on each file, and look for entries of the form
# "Can't locate (module name)" in the feedback.
# Errors early in a program that don't involve missing modules may shroud missing module
# errors. To be sure all modules needed are installed, look for
## 		No missing modules, no output file was created.
# near the end of this program's output to stdout.
# If some files contain syntax errors not related to missing modules, paths to the files
# will be listed. Sometimes it's not a real error, just a side-effect of a module that's still
# missing. If output from another run of this program produces the same list of files with
# syntax errors and there are no missing modules, you should fix those errors before rerunning this
# program. Normally the list of files with "some sort of syntax error not caused by missing
# modules" should go away as more and more modules are installed after each run of this program.
# For example, it takes four runs of this program and resulting bat files to install missing
# modules for IntraMine, and the last two runs complain of syntax errors - but the fifth run
# comes back clean, with no errors.


# Typical messages from Perl for a missing module, and resulting output line:
# use DoesNotExist;
#Can't locate DoesNotExist.pm in @INC (you may need to install the DoesNotExist module) (@INC contains: C:/Perl64/site/lib C:/Perl64/lib .) at C:\perlprogs\test\missing_module_test.pl line 5.
#BEGIN failed--compilation aborted at C:\perlprogs\test\missing_module_test.pl line 5.
# ==> ppm line will read "ppm install DoesNotExist"

# use Somewhere::DoesNotExist;
#Can't locate Somewhere/DoesNotExist.pm in @INC (you may need to install the Somewhere::DoesNotExist module) (@INC contains: C:/Perl64/site/lib C:/Perl64/lib .) at C:\perlprogs\test\missing_module_test.pl line 5.
#BEGIN failed--compilation aborted at C:\perlprogs\test\missing_module_test.pl line 5.
# ==> ppm line will read "ppm install Somewhere::DoesNotExist"

# Generic run line:
# perl C:\perlprogs\mine\list_missing_Perl_modules.pl [file or folder path, examples just below]

# Tests:
# perl C:\perlprogs\mine\list_missing_Perl_modules.pl C:\perlprogs\test\missing_module_test.pl
# perl C:\perlprogs\mine\list_missing_Perl_modules.pl C:\perlprogs\test\syntax_check_test
# perl C:\perlprogs\mine\list_missing_Perl_modules.pl C:\perlprogs\test
# perl C:\perlprogs\mine\list_missing_Perl_modules.pl C:\perlprogs\test\test_sort.pl
# perl C:\perlprogs\mine\list_missing_Perl_modules.pl C:\perlprogs\mine\intramine_editor.pl
# perl C:\perlprogs\mine\list_missing_Perl_modules.pl C:\perlprogs\mine\backup.pl
# perl C:\perlprogs\mine\list_missing_Perl_modules.pl C:\perlprogs\mine\intramine_filetree.pl


# IntraMine - for a complete installation of missing modules, run the following four times,
# and run the generated .bat files (install_these_modules_1.bat etc, at the top of
# C:\perlprogs\mine) after each of the four runs:
# (Change "C:\perlprogs\mine" to the path where you installed IntraMine, ie the folder
# that has elastic_indexer.pl and intramine_all_stop.pl at the top level.)
#
# perl C:\perlprogs\mine\list_missing_Perl_modules.pl C:\perlprogs\mine
#
# (Best do a fifth run, to verify all needed modules have been installed.)

use strict;
use FileHandle;
use DirHandle;

my $FileOrFolderPath = shift @ARGV;
if (!defined($FileOrFolderPath))
	{
	print("Please provide a file or folder path as argument!\n");
	exit(0);
	}

$FileOrFolderPath =~ s!\\!/!g;
my $numFiles = GetFileList($FileOrFolderPath);
if ($numFiles <= 0)
	{
	print("Please give us at least one .pm or .pl file to work with!\n");
	exit(0);
	}

print("$numFiles files will be checked for use of modules that are not installed.\n");

DetermineOutputFilePath($FileOrFolderPath);
GetMissingModulesList();
WriteMissingModulesList();

print("Done.\n");

######### subs
{ ##### List of files to examine
my @FileList;
my $NumFiles;
my $CurrentFileIndex;
my $PathIsForFile;

sub GetFileList {
	my ($fileOrFolderPath) = @_;
	$NumFiles = 0;
	$CurrentFileIndex = 0;
	$PathIsForFile = -1;
	
	if (-f $fileOrFolderPath) # a file path
		{
		push @FileList, $fileOrFolderPath;
		$PathIsForFile = 1;
		}
	else
		{
		if (substr($fileOrFolderPath, -1, 1) ne "/")
			{
			$fileOrFolderPath .= "/";
			}
		if (-d $fileOrFolderPath) # a folder path
			{
			my $d = new DirHandle($fileOrFolderPath);
			if (defined($d))
				{
				my $fileName;
			    while (defined($fileName = $d->read))
					{
					my $path = $fileOrFolderPath . $fileName;
					if (-f $path && $path =~ m!\.p[lm]$!)
			        	{
			        	push @FileList, $path;
			        	}
					}
				}
			$PathIsForFile = 0;
			}
		}
	
	$NumFiles = @FileList;
	return($NumFiles);
	}
	
sub NextFilePath {
	my $path = '';
	if ($NumFiles && $CurrentFileIndex < $NumFiles)
		{
		$path = $FileList[$CurrentFileIndex++];
		}
	
	return($path);
	}

sub ArgumentPathIsForFile {
	if (!defined($PathIsForFile) || $PathIsForFile == -1)
		{
		die("Maintenance Error, ArgumentPathIsForFile() called but there are no files to process!");
		}
	return($PathIsForFile);
	}
} ##### List of files to examine

{ ##### Output file path
my $OutputFilePath;

sub DetermineOutputFilePath {
	my ($fileOrFolderPath) = @_;
	$OutputFilePath = '';
	my $dir = '';
	
	my $isFile = ArgumentPathIsForFile();
	if ($isFile)
		{
		my $lastSlashPos = rindex($fileOrFolderPath, "/");
		$dir = substr($fileOrFolderPath, 0, $lastSlashPos + 1);
		}
	else
		{
		if (substr($fileOrFolderPath, -1, 1) ne "/")
			{
			$fileOrFolderPath .= "/";
			}
		$dir = $fileOrFolderPath;
		}
	my $baseFileName = 'install_these_modules_';
	my $uniqueNumber = 1;
	my $extension = '.bat';
	my $outFilePath = $dir . $baseFileName . $uniqueNumber . $extension;
	while (-f $outFilePath)
		{
		++$uniqueNumber;
		$outFilePath = $dir . $baseFileName . $uniqueNumber . $extension;
		}
	$OutputFilePath = $outFilePath;
	
	print("List of missing modules will be in |$OutputFilePath|\n");
	}

sub OutputFilePath {
	if (!defined($OutputFilePath) ||$OutputFilePath eq '')
		{
		die("Maintenance Error when calling OutputFilePath(), \$OutputFilePath has not been set!");
		}
	return($OutputFilePath);
	}
} ##### Output file path

{ ##### Parse file(s) and note missing modules
my @MissingModuleNames; 			# Eg Thing.pm, Win32::OLE::Const.pm
my $CountOfFilesWithSyntaxErrors; 	# Includes errors of any sort, not just missing modules.
my @NonModuleErrorPaths; 			# Paths to files with non-missing-module syntax errors

sub GetMissingModulesList {
	my $errorCount = 0;
	$CountOfFilesWithSyntaxErrors = 0;
	while ((my $filePath = NextFilePath()) ne '')
		{
		my $syntaxOk = 0;
		my $otherError = 0;
		print("Checking |$filePath|...\n");
		# Ask Perl to do a syntax check.
		open( my $perl, "-|", 'perl -c ' . $filePath . ' 2>&1' )
            || die $@;
        while (my $item = <$perl>)
			{
			# TEST ONLY
			#print("** $item\n");
			
            if ($item =~ m!^Can\'t locate (.+?\.p[lm])!)
            	{
            	my $moduleName = $1;
                ++$errorCount;
                push @MissingModuleNames, $moduleName unless (grep {$moduleName eq $_} @MissingModuleNames);
                print("MISSING MODULE detected: |$moduleName|\n");
             	}
             elsif ($item =~ m!syntax ok!i)
             	{
             	$syntaxOk = 1;
             	}
             elsif ($item !~ m!BEGIN failed!)
             	{
             	++$otherError;
             	}
        	}
        
        if ($errorCount > 0 || $otherError > 0)
        	{
        	$syntaxOk = 0;
        	}
        if (!$syntaxOk)
        	{
        	++$CountOfFilesWithSyntaxErrors;
        	if ($otherError)
        		{
        		push @NonModuleErrorPaths, $filePath;
        		}
        	}
		}
	}

# Write lines of the form "ppm install moduleName" for entries in @MissingModuleNames, to .bat file.
# Mention files with syntax errors NOT due to missing modules (those errors need a personal touch).
sub WriteMissingModulesList {
	my $numMissingModules = @MissingModuleNames;
	my $countOfNonModuleErrors = @NonModuleErrorPaths;
	if ($countOfNonModuleErrors > 0)
		{
		my $countWord = ($countOfNonModuleErrors == 1) ? 'file': "$countOfNonModuleErrors files";
		print("\n\nNOTE the following $countWord had some sort of syntax error not caused by missing modules.\n");
		print("If you don't see 'No missing modules' after a few more runs, you might have a real syntax error.\n");
		print("----------------------\n");
		for (my $i = 0; $i < $countOfNonModuleErrors; ++$i)
			{
			print("$NonModuleErrorPaths[$i]\n");
			}
		print("----------------------\n\n");
		}

	if ($numMissingModules > 0)
		{
		# Sort missing module names, to eg install X before X::Y.
		my @sortedNames = sort { $a cmp $b } @MissingModuleNames;
		my $outFilePath = OutputFilePath();
		my $fileH = FileHandle->new("> $outFilePath")
			or die("FILE ERROR could not make $outFilePath!");
		for (my $i = 0; $i < $numMissingModules; ++$i)
			{
			my $missingModuleName = $sortedNames[$i];
			$missingModuleName =~ s!\.p[lm]$!!;
			$missingModuleName =~ s!/!::!g;
			if ($i > 0)
				{
				print $fileH " && ppm install $missingModuleName";
				}
			else
				{
				print $fileH "ppm install $missingModuleName";
				}
			}
		close($fileH);
		my $missing = ($numMissingModules > 1) ? 'missing modules' : 'missing module';
		print("$numMissingModules $missing detected, see |$outFilePath|\n");
		print("You can run the bat file now by copying and pasting the following line:\n");
		print("$outFilePath\n");
		}
	else
		{
		print("No missing modules, no output file was created.\n");
		}
	}
} ##### Parse file(s) and note missing modules
