# win_wide_filepaths.pm: a few subs to deal with Windows paths and file names that contain "unicode"
# UTF-16 characters: exists, read, write, size, modtime, etc. Pass in a regular string and it's
# converted to a "wide" character string using "encode("UTF-16LE...".
# Then Win32API::File does the real work.
# Examples of use in IntraMine are mentioned below. If no example is given, the sub should
# be regarded as untested.
#
# Examples:
# if (-f $fileOrDir)
#  becomes
# if (FileOrDirExistsWide($fileOrDir) == 1) # 1==file, 2==dir, 0==does not exist.
#
# opendir my $dh, $dir or something bad happened;
# my @allEntries = readdir $dh;
#  becomes
# my @allEntries = FindFileWide($dir); # empty if something bad happened

package win_wide_filepaths;
require Exporter;
@ISA = qw(Exporter);

use strict;
use warnings;
use Carp;
use utf8;
use Encode qw/encode decode/;
use Win32API::File;
# TODO find a better way, GetFileTime (wide) often fails where stat works.
use Win32API::File::Time qw{GetFileTime};
use Win32::API;
use IO::Handle;
use Encode;
use Encode::Guess;
use HTML::Entities;
#use Path::Tiny qw(path);

# Some API calls aren't in the can, so we import them explicitly at the start.
BEGIN {
	Encode::Guess->add_suspects(qw/iso-8859-1/);
	Win32::API::More->Import(
    	Kernel32 => qq{BOOL CreateDirectoryW(LPWSTR lpPathNameW, VOID *p)}
		);
		
	my $CopyFileW = Win32::API::More->Import(
		Kernel32 => qq{BOOL CopyFileW(LPWSTR lpExistingFileName, LPWSTR lpNewFileName, BOOL bFailIfExists)}
		);
	die "Failed to import CopyFileW" if !$CopyFileW;

	Win32::API::More->Import(
		Kernel32 => qq{BOOL DeleteFileW(LPWSTR lpFileName)}
		);
		
	Win32::API::More->Import(
		Kernel32 => qq{BOOL RemoveDirectoryW(LPWSTR lpFileName)}
		);
	

	# For FindFileWide:
	Win32::API::Struct->typedef('FILETIME', qw(
	  DWORD dwLowDateTime;
	  DWORD dwHighDateTime;
	));				# 8 bytes
	
	Win32::API::Struct->typedef('WIN32_FIND_DATA', qw(
	  DWORD dwFileAttributes;
	  FILETIME ftCreationTime;
	  FILETIME ftLastAccessTime;
	  FILETIME ftLastWriteTime;
	  DWORD nFileSizeHigh;
	  DWORD nFileSizeLow;
	  DWORD dwReserved0;
	  DWORD dwReserved1;
	  TCHAR cFileName[260];
	  TCHAR cAlternateFileName[14];
	  )); # 4+8+8+8+4+4+4+4+260+14=318 bytes. OOops, add another 260 = 578, call it 600.
  
  	# For FindFileWide:
	Win32::API::More->Import(
		Kernel32 => qq{HANDLE FindFirstFileW(LPCWSTR lpFileName, LPWSTR lpFFData)}
	);
	
	Win32::API::More->Import(
		Kernel32 => qq{BOOL FindNextFileW(HANDLE hFindFile, LPWSTR lpFFData)}
	);
	
	Win32::API::More->Import(
		Kernel32 => qq{HANDLE FindClose(HANDLE hFindDile)}
	);
}


sub WideString {
	my ($str) = @_;
	return(encode("UTF-16LE", "$str\0"));
	}

# FileOrDirExistsWide. Returns
# 0 == not a file or directory
# 1 == file
# 2 == directory.
# Trailing slash is optional for dirs, eg "C:/temp" or "C:/temp/".
# This is used commonly in IntraMine, as a replacement for "if (-f $path)".
# See eg intramine_filewatcher.pl#FileShouldBeIndexed().
sub FileOrDirExistsWide {
	my ($filePathOrDir) = @_;
	my $filePathOrDirWin  = encode("UTF-16LE", "$filePathOrDir\0");
	my $uAttrs = Win32API::File::GetFileAttributesW($filePathOrDirWin);
	my $result = 0;
	
	if ($uAttrs == Win32API::File::INVALID_FILE_ATTRIBUTES)
		{
		; # nope
		}
	else
		{
		if ($uAttrs & Win32API::File::FILE_ATTRIBUTE_DIRECTORY)
			{
			$result = 2; # directory
			}
		else
			{
			$result = 1; # file			
			}
		}
	
	return($result);
	}

# GetExistingReadFileHandleWide: open $filepath, get a Perl file handle and return it.
# Returns undef on error.
# NOTE the returned handle is not closed here.
# To close it later after my $fh = GetExistingReadFileHandleWide($filePath), do
# close($fh);
# See eg intramine_file_viewer_cm.pl#GetHTML().
sub GetExistingReadFileHandleWide {
	my ($filePath) = @_;
	my $filePathWin  = encode("UTF-16LE", "$filePath\0");
	
	my $F  = Win32API::File::CreateFileW($filePathWin, Win32API::File::GENERIC_READ, Win32API::File::FILE_SHARE_READ, [], Win32API::File::OPEN_EXISTING, 0, 0);
	if (!$F)
		{
		#carp("CreateFileW for read FAILED TO OPEN |$filePathWin|! error: |$^E|\n");
		return(undef);
		}

	my $fileH;
	if (!Win32API::File::OsFHandleOpen($fileH = IO::Handle->new(), $F, "r"))
		{
		#carp("OsFHandleOpen for reading FAILED for |$filePathWin|!\n");
		return(undef);
		}
	
	return($fileH);
	}

# WriteTextFileWide: write $contents to $filePath as text, replacing all previous contents.
# Creates file if it does not exist.
# Returns
# 1 == OK
# 0 == failure
# See eg gloss2html.pl#ConvertTextToHTML().
sub WriteTextFileWide {
	my ($filePath, $contents) = @_;
	my $filePathWin  = encode("UTF-16LE", "$filePath\0");

	my $F  = Win32API::File::CreateFileW($filePathWin, Win32API::File::GENERIC_WRITE, 0, [], Win32API::File::CREATE_ALWAYS, 0, 0);
	if (!$F)
		{
		#carp("CreateFileW for write FAILED TO OPEN |$filePathWin|! error: |$^E|\n");
		return(0);
		}
	
	my $fileH;
	if (!Win32API::File::OsFHandleOpen($fileH = IO::Handle->new(), $F, "w"))
		{
		#carp("OsFHandleOpen for writing FAILED for |$filePathWin|!\n");
		return(0);
		}
	
	print $fileH "$contents";
	close($fileH);
	
	return(1);
	}

# WriteBinFileWide: write $contents to $filePath verbatim, replacing all previous contents.
# Creates file if it does not exist.
# Returns
# 1 == OK
# 0 == failure
# See eg intramine_todolist.pl#PutData().
sub WriteBinFileWide {
	my ($filePath, $contents) = @_;
	my $filePathWin  = encode("UTF-16LE", "$filePath\0");

	my $F  = Win32API::File::CreateFileW($filePathWin, Win32API::File::GENERIC_WRITE, 0, [], Win32API::File::CREATE_ALWAYS, 0, 0);
	if (!$F)
		{
		#carp("CreateFileW for write FAILED TO OPEN |$filePathWin|! error: |$^E|\n");
		return(0);
		}
	
	my $fileH;
	if (!Win32API::File::OsFHandleOpen($fileH = IO::Handle->new(), $F, "w"))
		{
		#carp("OsFHandleOpen for writing FAILED for |$filePathWin|!\n");
		return(0);
		}
	
	binmode $fileH;
	print $fileH "$contents";
	close($fileH);
	
	return(1);
	}

# AppendToTextFileWide: append $contents as text to $filepath, preserving previous contents.
# Creates file if it does not exist.
# Returns
# 1 == OK
# 0 == failure
sub AppendToTextFileWide {
	my ($filePath, $contents) = @_;
	my $filePathWin  = encode("UTF-16LE", "$filePath\0");

	my $F  = Win32API::File::CreateFileW($filePathWin, Win32API::File::GENERIC_WRITE, 0, [], Win32API::File::OPEN_ALWAYS, 0, 0); # to append, goes with "wa"
	if (!$F)
		{
		#carp("CreateFileW for write FAILED TO OPEN |$filePathWin|! error: |$^E|\n");
		return(0);
		}
	
	my $fileH;
	if (!Win32API::File::OsFHandleOpen($fileH = IO::Handle->new(), $F, "wa"))
		{
		#carp("OsFHandleOpen for writing FAILED for |$filePathWin|!\n");
		return(0);
		}
	
	print $fileH "$contents";
	close($fileH);
	
	return(1);
	}

# AppendToExistingTextFileWide: append $contents as text to $filepath, preserving previous contents.
# ERROR and returns 0 if $filepath does not exist, thanks to 'OPEN_EXISTING'.
# Returns
# 1 == OK
# 0 == failure
sub AppendToExistingTextFileWide {
	my ($filePath, $contents) = @_;
	my $filePathWin  = encode("UTF-16LE", "$filePath\0");

	my $F  = Win32API::File::CreateFileW($filePathWin, Win32API::File::GENERIC_WRITE, 0, [], Win32API::File::OPEN_EXISTING, 0, 0); # to append, goes with "wa"
	if (!$F)
		{
		#carp("CreateFileW for write FAILED TO OPEN |$filePathWin|! error: |$^E|\n");
		return(0);
		}
	
	my $fileH;
	if (!Win32API::File::OsFHandleOpen($fileH = IO::Handle->new(), $F, "wa"))
		{
		#carp("OsFHandleOpen for writing FAILED for |$filePathWin|!\n");
		return(0);
		}
	
	print $fileH "$contents";
	close($fileH);
	
	return(1);
	}

# AppendToBinFileWide: like AppendToTextFileWide, but uses bin mode.
sub AppendToBinFileWide {
	my ($filePath, $contents) = @_;
	my $filePathWin  = encode("UTF-16LE", "$filePath\0");

	my $F  = Win32API::File::CreateFileW($filePathWin, Win32API::File::GENERIC_WRITE, 0, [], Win32API::File::OPEN_ALWAYS, 0, 0); # to append, goes with "wa"
	if (!$F)
		{
		#carp("CreateFileW for write FAILED TO OPEN |$filePathWin|! error: |$^E|\n");
		return(0);
		}
	
	my $fileH;
	if (!Win32API::File::OsFHandleOpen($fileH = IO::Handle->new(), $F, "wa"))
		{
		#carp("OsFHandleOpen for writing FAILED for |$filePathWin|!\n");
		return(0);
		}
	
	binmode $fileH;
	print $fileH "$contents";
	close($fileH);
	
	return(1);
	}

# AppendToBinFileWide: like AppendToExistingTextFileWide, but uses bin mode.
sub AppendToExistingBinFileWide {
	my ($filePath, $contents) = @_;
	#my $octets = decode('utf8', $filePath);
	my $filePathWin  = encode("UTF-16LE", "$filePath\0");

	my $F  = Win32API::File::CreateFileW($filePathWin, Win32API::File::GENERIC_WRITE, 0, [], Win32API::File::OPEN_EXISTING, 0, 0); # to append, goes with "wa"
	if (!$F)
		{
		#carp("CreateFileW for write FAILED TO OPEN |$filePathWin|! error: |$^E|\n");
		return(0);
		}
	
	my $fileH;
	if (!Win32API::File::OsFHandleOpen($fileH = IO::Handle->new(), $F, "wa"))
		{
		#carp("OsFHandleOpen for writing FAILED for |$filePathWin|!\n");
		return(0);
		}
	
	binmode $fileH;
	print $fileH "$contents";
	close($fileH);
	
	return(1);
	}

# CopyFileWide: copy a file to a new location.
# Returns 1 if OK, 0 if fail. Can fail eg if $failIfExists ==1 and dest file exists.
# (NOTE if $failIfExists is 0 then this fn will return 1 if the file exists. If you want
# to overwrite regardless: set $failIfExists to 1, and if this fn returns 0 then
# call DeleteFileWide() and then call this fn a second time.)
# Set $failIfExists to 0 to force an overwrite.
# (Note this uses the Win32::API->Import version of CopyFileW, I had no luck with
# the win32api::files version.)
# See eg intramine_file_viewer_cm.pl#MakeCtagsForFile().
sub CopyFileWide {
	my ($srcFullPath, $destFullPath, $failIfExists) = @_;
	# being conservative, prevent overwrite by default.
	if (!defined($failIfExists))
		{
		$failIfExists = 1;
		}
	my $srcFullPathWin = encode("UTF-16LE", "$srcFullPath\0");
	my $destFullPathWin = encode("UTF-16LE", "$destFullPath\0");
	return(CopyFileW( $srcFullPathWin, $destFullPathWin, $failIfExists ));
	}

# DeleteFileWide: returns 1 if $filePath is deleted, 0 if not.
# (This uses the Win32::API->Import version of DeleteFileW. See BEGIN above.)
# See eg intramine_filewatcher.pl#CleanOutOldFileWatcherLogs().
sub DeleteFileWide {
	my ($filePath) = @_;
	my $filePathWin  = encode("UTF-16LE", "$filePath\0");
	return(DeleteFileW($filePathWin));	
	}

# Make a dir with or without unicode in path. All dirs leading up to the one being
# made must already exist. Returns 1 if dir is made, 2 if it already exists,
# 0 otherwise.
sub MakeDirWide {
	my ($dirPath) = @_;
	my $result = FileOrDirExistsWide($dirPath);
	
	if (!$result)
		{
		# Normalize slashes to fwd.
		$dirPath =~ s!\\!/!g;
		# Trim file name if any snuck in.
		if ($dirPath =~ m!\.\w+$!)
			{
			my $lastSlashPos = rindex($dirPath, "/");
			$dirPath = substr($dirPath, 0, $lastSlashPos);
			}
		# Trim any trailing slashes.
		$dirPath =~ s!/+$!!;
		
		$result = FileOrDirExistsWide($dirPath);
		if (!$result)
			{
			my $dirPathWin  = encode("UTF-16LE", "$dirPath\0");
			$result = CreateDirectoryW($dirPathWin, undef);
			}
		}
	
	return($result);
	}

# Make a dir with or without "unicode" in path. Make intermediate dirs as needed.
# Return 1 if last needed dir is made, 2 if it already exists, 0 otherwise.
# Accepts dir paths or full paths to files. Spurious slashes on the
# end of the dir path are ignored (eg "C:/folder1/folder2//")
# 
# NOTE include a trailing slash in $dirPath if the last folder name
# ends with something that looks like a file extension. Or
# supply the full path to a file in the folder. Eg to make the folder
# containing "C:/one/two.2/file.txt" pass the whole path "C:/one/two.2/file.txt"
# or "C:/one/two.2/" or even "C:/one/two.2//" rather than "C:/one/two.2" in $dirPath.
# For an example, see intramine_uploader.js#UploadTheFile().
sub MakeAllDirsWide {
	my ($dirPath) = @_;
	my $result = FileOrDirExistsWide($dirPath);
	
	if (!$result)
		{
		# Normalize slashes to fwd.
		$dirPath =~ s!\\!/!g;
		# Trim file name if any snuck in.
		if ($dirPath =~ m!\.\w+$!)
			{
			my $lastSlashPos = rindex($dirPath, "/");
			$dirPath = substr($dirPath, 0, $lastSlashPos);
			}
		# And trim any trailing slashes.
		$dirPath =~ s!/+$!!;
		
		$result = FileOrDirExistsWide($dirPath);
		
		if (!$result)
			{
			# Make all needed intermediate dirs down to and including the final full $dirPath.
			# Split on / if $dirPath can't be made on first try.
			my $dirPathWin  = encode("UTF-16LE", "$dirPath\0");
			$result = CreateDirectoryW($dirPathWin, undef);
			if (!$result)
				{
				my @dirParts = split('/', $dirPath);
				my $numParts = @dirParts;
				if ($numParts > 1)
					{
					my $dirPathToTry = $dirParts[0]; # . '/' . $dirParts[1];
					for (my $i = 1; $i < $numParts; ++$i)
						{
						$dirPathToTry .= "/$dirParts[$i]";
						$result = FileOrDirExistsWide($dirPathToTry);
						if (!$result)
							{
							my $winDirToTry = encode("UTF-16LE", "$dirPathToTry\0");
							$result = CreateDirectoryW($winDirToTry, undef);
							last if !$result;
							}
						}
					}
				}
			}
		}
	
	return($result);
	}

# Remove an EMPTY directory. Needed by IntraMine only for testing.
# See eg t/Modules/ test_win_wide_filepaths.t.
# Returns 1 on success, 0 if directory can't be removed (for example because it is not empty).
sub RemoveDirWide {
	my ($dirPath) = @_;
	$dirPath =~ s!\\!/!g;
	# Normalize slashes to fwd.
	$dirPath =~ s!\\!/!g;
	# Trim file name if any snuck in.
	if ($dirPath =~ m!\.\w+$!)
		{
		my $lastSlashPos = rindex($dirPath, "/");
		$dirPath = substr($dirPath, 0, $lastSlashPos);
		}
	# Trim any trailing slashes.
	$dirPath =~ s!/+$!!;
	
	my $dirPathWin  = encode("UTF-16LE", "$dirPath\0");
	my $result = RemoveDirectoryW($dirPathWin);
	
	return($result);
	}

# Return an array of all files and subdirs at the top level of $dir.
# Can be dropped in as a replacement for readdir.
# Eg replace
#  opendir my $dh, $dir or something bad happened;
#  @allEntries = readdir $dh;
# with
# @allEntries = FindFileWide($dir); # empty if something bad happened
# See eg intramine_filetree.pl#GetDirsAndFiles().
sub FindFileWide {
	my ($dir) = @_;
	$dir =~ s!/!\\!g;
	my $lastChar = substr($dir, -1);
	if ($lastChar ne '*')
		{
		$dir .= '*';
		}
	my $dirPathWin  = encode("UTF-16LE", "$dir\0");
	# WIN32_FIND_DATA struct has 58 + 2x260 = 578 bytes, round up to 600. It's not 318.
	my $memoryBucket = chr(0) x 600;
	my @allEntries;
	
	my $hFF = FindFirstFileW($dirPathWin, $memoryBucket ) or return(@allEntries);
	do
		{
		my $path = substr($memoryBucket, 44); # 44 bytes before cFileName[]
		if ($path =~ m!^((.+?)\x00)\x00\x00!)
			{
			$path = $1;
			# If the last character is some kind of real "unicode" with its second
			# byte not null, then we will have grabbed an odd number of bytes,
			# with a spurious null. Drop it.
			my $pathLen = length($path);
			if (($pathLen%2) != 0)
				{
				$path = substr($path, 0, -1);
				}
			my $decoded = decode("UTF-16LE", $path);
			push @allEntries, $decoded;
			}
		} while FindNextFileW( $hFF, $memoryBucket );
	FindClose( $hFF );
	
	return(@allEntries);
	}

# "Go deep", call FindFileWide() recursively on subdirs. Sets separate arrays of
# files and subdirectories.
# See eg elastic_indexer.pl#101.
sub DeepFindFileWide {
	my ($dir, $filesA, $dirsA) = @_;

	my @allEntries = FindFileWide($dir);

	for (my $i = 0; $i < @allEntries; ++$i)
		{
		my $fileName = $allEntries[$i];
		my $fullPath = "$dir$fileName";
		if (FileOrDirExistsWide($fullPath) == 2
			&& $fileName !~ m!^\.\.?$! && substr($fileName, 0, 1) ne '$') # dir
			{
			push @$dirsA, $fullPath;
			#print("Going deep on |$fullPath|\n");
			DeepFindFileWide($fullPath . '/', $filesA, $dirsA);
			}
		else # file - require an extension, not .sys, and no leading '$'
			{
			if ($fileName =~ m!\.\w+$! && $fileName !~ m!\.sys$! && substr($fileName, 0, 1) ne '$')
				{
				#print("Found file |$fullPath|\n");
				push @$filesA, $fullPath;
				}
			}
		}
	}

# ReadTextFileWide: read in text file in one shot.
# Returns contents of file (which may be ''), or undef if error.
# See eg intramine_file_viewer_cm.pl#LoadTextFileContents().
sub ReadTextFileWide {
	my ($filePath) = @_;
	my $result = '';
	
	my $fh = GetExistingReadFileHandleWide($filePath);
	if (!defined($fh))
		{
		#carp("GetExistingReadFileHandleWide in ReadTextFileWide FAILED for |$filePath|! error: |$^E|\n");
		return($result);
		}
	
	my $contents = do { local $/; <$fh> };
	if (!defined($contents))
		{
		#carp("RTFW read_file FAILED for |$filePath|\n");
		return($result);
		}
	close($fh);
	
	return($contents);
	}

# ReadTextFileDecodedWide: read in text file in one shot, with decoding (utf_8 given preference).
# For UTF-8, if $allowOutOfRangeCharacters is set to 1 then the decoded contents, errors and all,
# will be returned. If it's 0, then $result = '' if any out of range Unicode character is seen.
# if the $allowOutOfRangeCharacters is not supplied, it is set to 0.
# See eg elasticsearch_bulk_indexer.pm#AddDocumentToIndex().
sub ReadTextFileDecodedWide {
	my ($filePath, $allowOutOfRangeCharacters) = @_;
	$allowOutOfRangeCharacters ||= 0;
	my $result = '';

	my $fh = GetExistingReadFileHandleWide($filePath);
	if (!defined($fh))
		{
		#carp("GetExistingReadFileHandleWide in ReadTextFileWide FAILED for |$filePath|! error: |$^E|\n");
		return($result);
		}
	
	my $octets = do { local $/; <$fh> };
	if (!defined($octets))
		{
		return($result);
		}
	close($fh);

	my $decoder = Encode::Guess->guess($octets);
	if (ref($decoder))
		{
		my $decoderName = $decoder->name();
		if ($decoderName =~ m!iso-8859-\d+!)
			{
			$result = $decoder->decode($octets);
			}
		else
			{
			if ($allowOutOfRangeCharacters)
				{
				$result = decode_utf8($octets);
				}
			else
				{
				eval { $result = decode("UTF-8", $octets); };
				if ($@)
					{
					#print("Bad character encountered\n");
					$result = '';
					}
				}
			}
		#carp("ESBI decoder name for |$filePath| is : |$decoderName|\n");
		}
	else
		{
		#carp("ESBI for |$filePath| guess says: |$decoder|\n");
		if ($allowOutOfRangeCharacters)
			{
			$result = decode_utf8($octets);
			}
		else
			{
			eval { $result = decode("UTF-8", $octets); };
			if ($@)
				{
				#print("Bad character encountered\n");
				$result = '';
				}
			}
		}
	
	return($result);
	}

# Read a file verbatim (binary).
# See eg swarmserver.pm#GetBinFile(), intramine_todolist.pl#GetData().
sub ReadBinFileWide {
	my ($filePath) = @_;
	my $result = '';
	
	my $fh = GetExistingReadFileHandleWide($filePath);
	if (!defined($fh))
		{
		#carp("GetExistingReadFileHandleWide in ReadBinFileWide FAILED for |$filePath|! error: |$^E|\n");
		return($result);
		}

	binmode $fh;
	my $contents = do { local $/; <$fh> };
	if (!defined($contents))
		{
		return($result);
		}
	close($fh);
	
	return($contents);
	}

# Not currently used, though tested once and it worked.
sub RefReadBinFileWide {
	my ($filePath, $contentsR) = @_;
	$$contentsR = '';
	
	my $fh = GetExistingReadFileHandleWide($filePath);
	if (!defined($fh))
		{
		#carp("GetExistingReadFileHandleWide in ReadBinFileWide FAILED for |$filePath|! error: |$^E|\n");
		return;
		}

	binmode $fh;
	$$contentsR = do { local $/; <$fh> };
	close($fh);
	}

# GetHtmlEncodedTextFileWide: returns text contents of $filePath,
# with <>&" encoded for use in HTML.
# Returns '' on error (same as if file is empty).
# See eg intramine_file_viewer_cm.pl#GetHtmlEncodedTextFile().
sub GetHtmlEncodedTextFileWide {
	my ($filePath) = @_;
	my $result = '';
	
	my $octets = ReadTextFileWide($filePath);
	if (!defined($octets))
		{
		return('');
		}

	my $decoder = Encode::Guess->guess($octets);

	if (ref($decoder))
		{
		my $decoderName = $decoder->name();
		if ($decoderName =~ m!iso-8859-\d+!)
			{
			$octets = $decoder->decode($octets);
			print("\n---8859---! for |$filePath|\n");
			}
		}

	$octets = encode_entities($octets, '<>&"');
	
	return($octets);
	}

# See eg intramine_search.pl#FileDateAndSizeString().
sub GetFileSizeWide {
	my ($filePath) = @_;
	my $filePathWin  = encode("UTF-16LE", "$filePath\0");
	my $result = 0;

	my $F  = Win32API::File::CreateFileW($filePathWin, Win32API::File::GENERIC_READ, Win32API::File::FILE_SHARE_READ, [], Win32API::File::OPEN_EXISTING, 0, 0);
	if (!$F)
		{
		#carp("CreateFileW for read FAILED TO OPEN |$filePathWin|! error: |$^E|\n");
		return($result);
		}
	$result = Win32API::File::getFileSize($F);
	Win32API::File::CloseHandle($F);
	
	return($result);
	}

# Oct 21 2016, having random trouble with Win32API::File::Time GetFileTime. As a temporary
# partial workaround, if it fails fall back to stat.
# See eg intramine_search.pl#FileDateAndSizeString().
sub GetFileModTimeWide {
	my ($filePath) = @_;
	my $filePathWin  = encode("UTF-16LE", "$filePath\0");
	my $result = undef;
	local ${^WIDE_SYSTEM_CALLS} = 1;
	my ($atime, $mtime, $ctime) = GetFileTime($filePathWin);
	if (defined($mtime))
		{
		$result = $mtime;
		}
	else
		{
		# Hack, this is not a good solution, will fail for file names containing "unicode" (you know what I mean).
		# But it does work in some cases where GetFileTime() fails.
		my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size,
			$atime, $modtime, $ctime, $blksize, $blocks) = stat $filePath;
		$result = $modtime;
		}
	
	return($result);
	}

# ActualPathIfTooDeep (not currently used in IntraMine):
# If for example
# $proposedFilePath = "C:/perlprogs/mine/t/Swarmserver/data/serverlist.txt"
# and $dirsToKeep = 1:
# If $proposedFilePath exists, return it.
# Else keep "data/serverlist.txt" (file name plus 1 $dirsToKeep)
# And progressively trim folders from the left partial path, looking at
# "C:/perlprogs/mine/t" .'/' . "data/serverlist.txt"  - nope
# "C:/perlprogs/mine" .'/' . "data/serverlist.txt"  - HIT! Return that.
# If nothing found that exists, return the original $proposedFilePath.
sub ActualPathIfTooDeep {
	my ($proposedFilePath, $dirsToKeep) = @_;
	#print("Top of ActualPathIfTooDeep.\n");
	if (FileOrDirExistsWide($proposedFilePath) == 1)
		{
		# TEST ONLY codathon
		#print("Path as given.\n");
		return($proposedFilePath);
		}
	
	my $fnPosition = rindex($proposedFilePath, '/');
	my $fileName = substr($proposedFilePath, $fnPosition + 1);
	my $dirPath = substr($proposedFilePath, 0, $fnPosition);
	for (my $i = 0; $i < $dirsToKeep; ++$i)
		{
		$fnPosition = rindex($dirPath, '/');
		$fileName = substr($dirPath, $fnPosition + 1) . '/' . $fileName;
		$dirPath = substr($dirPath, 0, $fnPosition);
		}
	my $foundIt = 0;
	
	#print("Initial file part: |$fileName|\n");
	#print("Initial dir part: |$dirPath|\n");
	
	while ($fnPosition > 0)
		{
		if (FileOrDirExistsWide("$dirPath/$fileName") == 1)
			{
			$foundIt = 1;
			last;
			}
		$fnPosition = rindex($dirPath, '/');
		$dirPath = substr($dirPath, 0, $fnPosition);
		#print("Testing dir: |$dirPath|\n");
		}

	my $actualPath = $foundIt ? "$dirPath/$fileName" : $proposedFilePath;

	return($actualPath);
	}

use ExportAbove;
1;
