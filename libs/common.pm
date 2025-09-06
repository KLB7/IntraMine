# common.pm: subroutines that have been found useful.
# !! Call SetCommonOutput(\&Output) early if you want to use your own "Output" sub. If you
# don't, you'll just get a regular print.

package common;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use utf8;
use Carp;
use FileHandle;
use DirHandle;
use File::Path;
use File::Find;
use File::Copy;
use Date::Business;
use Time::Piece;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
#use lib ".";
use holidays;    # holidays for use with Date::Business

my $FILESIZEUNITS = [qw(B KB MB GB TB PB)];

my $Output = \&_Com_JustPrint;    # print or log

# The default for $Output->("string"), just print.
sub _Com_JustPrint {
	my ($txt) = @_;
	print("$txt");
}

# Call this to use your own version of $Output for feedback when calling subs below.
sub SetCommonOutput {
	my ($of) = @_;
	if (defined($of))
		{
		$Output = $of;
		}
	else    # reset
		{
		$Output = \&_Com_JustPrint;
		}
}

{ ##### %DirectoriesCreated
my %DirectoriesCreated;

# This will quietly fail if directory already exists. Pass in a full path to a FILE
# (file name is required, but not used).
sub MakeDirectoriesForFile {
	my ($destFilePath) = @_;

	# Trim file name
	$destFilePath =~ m!^(.+)(/|\\)[^\\/]+$!;
	my $directoryOnPath = $1;
	# See if final directory exists: if not, make it.
	if (length($directoryOnPath) > 0)
		{
		if (   !defined($DirectoriesCreated{$directoryOnPath})
			&& !(-e $directoryOnPath))
			{
			$DirectoriesCreated{$directoryOnPath} += 1;
			$Output->("MAKING all of $directoryOnPath...\n");
			mkpath($directoryOnPath);
			}
		}
}
}    ##### %DirectoriesCreated

# Load single field into array - handy if duplicates should be preserved.
# Otherwise, use LoadHashKeysFromFile to remove duplicates.
# Comment lines starting with '#' are skipped, if $skipCommentLines.
sub LoadFileIntoArray {
	my ($arr, $filePath, $arrayDescription, $skipCommentLines) = @_;
	$skipCommentLines ||= 0;

	if (defined($arrayDescription) && $arrayDescription ne '')
		{
		$Output->("Loading $arrayDescription from $filePath into array\n");
		}
	my $fileH = FileHandle->new("$filePath") or return (0);
	binmode($fileH, ":utf8");
	my $line;
	my $count = 0;

	while ($line = <$fileH>)
		{
		chomp($line);
		if (length($line) && !($skipCommentLines && $line =~ m!^\s*#!))
			#if (length($line))
			{
			push @$arr, $line;
			++$count;
			}
		}
	close $fileH;
	return $count;
}

# Load lines from a text file into a hash. Hash values are set to 1.
# Comment lines starting with '#' are skipped, if $skipCommentLines.
sub LoadHashKeysFromFile {
	my ($hashRef, $filePath, $hashDescription, $skipCommentLines) = @_;
	$skipCommentLines ||= 0;

	if (defined($hashDescription) && $hashDescription ne '')
		{
		$Output->("Loading $hashDescription from $filePath\n");
		}
	my $fileH = FileHandle->new("$filePath") or return (0);
	binmode($fileH, ":utf8");
	my $line;
	my $count = 0;

	while ($line = <$fileH>)
		{
		chomp($line);
		if (length($line) && !($skipCommentLines && $line =~ m!^\s*#!))
			#if (length($line))
			{
			$hashRef->{$line} = 1;
			++$count;
			}
		}
	close $fileH;
	return $count;
}

# Write keys only from %$hashRef to file $filePath.
sub SaveHashKeysToFile {
	my ($hashRef, $filePath, $hashDescription) = @_;
	if (defined($hashDescription) && $hashDescription ne '')
		{
		$Output->("Saving list of $hashDescription to $filePath...\n");
		}
	MakeDirectoriesForFile($filePath);
	my $hfileH = FileHandle->new("> $filePath") || die("Can't write to $filePath!");
	binmode($hfileH, ":utf8");
	foreach my $key (sort(keys %$hashRef))
		{
		print $hfileH "$key\n";
		}

	close $hfileH;
}

# Load key<tab>value lines from a file into a hash, %$hashRef.
# Comment lines starting with '#' are skipped, if $skipCommentLines.
sub LoadKeyTabValueHashFromFile {
	my ($hashRef, $filePath, $hashDescription, $skipCommentLines) = @_;
	$skipCommentLines ||= 0;
	if (defined($hashDescription) && $hashDescription ne '')
		{
		$Output->("KeyTabValue Loading $hashDescription from $filePath\n");
		}
	my $fileH = FileHandle->new("$filePath") or return (0);
	binmode($fileH, ":utf8");
	my $line;
	my $count = 0;

	while ($line = <$fileH>)
		{
		chomp($line);
		if (length($line) && !($skipCommentLines && $line =~ m!^\s*#!))
			#if (length($line) && !($skipCommentLines && substr($line, 0, 1) eq '#'))
			{
			my @kv = split(/\t/, $line, 2);
			$hashRef->{$kv[0]} = $kv[1];
			++$count;
			}
		}
	close $fileH;
	return $count;
}

# Like LoadKeyTabValueHashFromFile(), but all keys and values are lowercased.
sub LC_LoadKeyTabValueHashFromFile {
	my ($hashRef, $filePath, $hashDescription, $skipCommentLines) = @_;
	$skipCommentLines ||= 0;
	if (defined($hashDescription) && $hashDescription ne '')
		{
		$Output->("KeyTabValue Loading $hashDescription from $filePath\n");
		}
	my $fileH = FileHandle->new("$filePath") or return (0);
	binmode($fileH, ":utf8");
	my $line;
	my $count = 0;

	while ($line = <$fileH>)
		{
		chomp($line);
		if (length($line) && !($skipCommentLines && $line =~ m!^\s*#!))
			#if (length($line) && !($skipCommentLines && substr($line, 0, 1) eq '#'))
			{
			my @kv = split(/\t/, $line, 2);
			$hashRef->{lc($kv[0])} = lc($kv[1]);
			++$count;
			}
		}
	close $fileH;
	return $count;
}

# Load key<tabs>value lines from a file into a hash, %$hashRef.
# Comment lines starting with '#' are skipped, if $skipCommentLines.
# Yes, this is much like the above sub:)
sub LoadKeyMultiTabValueHashFromFile {
	my ($hashRef, $filePath, $hashDescription, $skipCommentLines) = @_;
	$skipCommentLines ||= 0;
	if (defined($hashDescription) && $hashDescription ne '')
		{
		$Output->("KeyTabValue Loading $hashDescription from $filePath\n");
		}
	my $fileH = FileHandle->new("$filePath") or return (0);
	binmode($fileH, ":utf8");
	my $line;
	my $count = 0;

	while ($line = <$fileH>)
		{
		chomp($line);
		if (length($line) && !($skipCommentLines && $line =~ m!^\s*#!))
			{
			my @kv = split(/\t+/, $line, 2);
			$hashRef->{$kv[0]} = $kv[1];
			++$count;
			}
		}
	close $fileH;
	return $count;
}


# Save keys and values from hash $hashRef to a file.
# Lines in the file have the format
# key<tab>value
sub SaveKeyTabValueHashToFile {
	my ($hashRef, $filePath, $hashDescription) = @_;
	if (defined($hashDescription) && $hashDescription ne '')
		{
		$Output->("Saving list of $hashDescription to $filePath...\n");
		}
	MakeDirectoriesForFile($filePath);
	my $hfileH = FileHandle->new("> $filePath") || die("Can't write to $filePath!");
	binmode($hfileH, ":utf8");
	foreach my $key (sort(keys %$hashRef))
		{
		print $hfileH "$key\t$hashRef->{$key}\n";
		}

	close $hfileH;
}

#
sub SizeInBytesString {
	my ($sizeBytes) = @_;
	my $exp         = 0;
	my $sizeStr     = '';
	for (@$FILESIZEUNITS)
		{
		last if $sizeBytes < 1024;
		$sizeBytes /= 1024;
		$exp++;
		}
	if ($exp == 0)
		{
		$sizeStr = sprintf("%d %s", $sizeBytes, $FILESIZEUNITS->[$exp]);
		}
	else
		{
		$sizeStr = sprintf("%.1f %s", $sizeBytes, $FILESIZEUNITS->[$exp]);
		}

	return ($sizeStr);
}

# Date and time from a file $modDate.
# <- my $modDate = GetFileModTimeWide($filePath);
# -> YYYY-MM-DD HH:MM:SS
sub DateTimeString {
	my ($modDate) = @_;
	my $dateStr   = localtime($modDate)->datetime;    # eg 2010-06-24T11:02:06
	my $result    = '';

	if ($dateStr =~ m!^(\d+\-\d+-\d+)T(\d\d)\:(\d\d)\:(\d\d)$!)
		{
		my $date = $1;
		my $hr   = $2;
		my $min  = $3;
		my $sec  = $4;
		$result = "$date $hr:$min:$sec";
		}
	else
		{
		$result = $dateStr;
		}

	return ($result);
}

# Eg  <span>YYYY-MM-DDThh:mm:ss 123 KB</span>.
# Usage:
#	my $modDate = GetFileModTimeWide($filePath);
#	my $size = GetFileSizeWide($filePath);
#	my $sizeDateStr =  DateSizeString($modDate, $size);
sub DateSizeString {
	my ($modDate, $sizeBytes) = @_;
	my $sizeDateStr = '';
	my $dateStr     = localtime($modDate)->datetime;

	my $exp     = 0;
	my $sizeStr = '';
	for (@$FILESIZEUNITS)
		{
		last if $sizeBytes < 1024;
		$sizeBytes /= 1024;
		$exp++;
		}
	if ($exp == 0)
		{
		$sizeStr = sprintf("%d %s", $sizeBytes, $FILESIZEUNITS->[$exp]);
		}
	else
		{
		$sizeStr = sprintf("%.1f %s", $sizeBytes, $FILESIZEUNITS->[$exp]);
		}

	if ($dateStr ne '' || $sizeStr ne '')
		{
		$sizeDateStr = "<span>";
		if ($dateStr ne '')
			{
			$sizeDateStr .= $dateStr;
			}
		if ($sizeStr ne '')
			{
			if ($dateStr ne '')
				{
				$sizeDateStr .= ' ';
				}
			$sizeDateStr .= $sizeStr;
			}
		$sizeDateStr .= "</span>";
		}

	return ($sizeDateStr);
}

sub DateTimeForFileName {
	my ($sec, $min, $hr, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
	$mon += 1;
	if ($year < 1900)
		{
		$year += 1900;
		}
	my $niceDate = sprintf("%04d-%02d-%02d-%02d-%02d", $year, $mon, $mday, $hr, $min);
	$niceDate;
}

# YYYY-MM-DD for today.
sub DateForFileName {
	my ($sec, $min, $hr, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
	$mon += 1;
	if ($year < 1900)
		{
		$year += 1900;
		}
	my $niceDate = sprintf("%04d-%02d-%02d", $year, $mon, $mday);
	$niceDate;
}

sub DateYYYYMMDD {
	my ($sec, $min, $hr, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
	$mon += 1;
	if ($year < 1900)
		{
		$year += 1900;
		}
	my $niceDate = sprintf("%04d%02d%02d", $year, $mon, $mday);
	$niceDate;
}

sub DateDDMMYYYSlashed {
	my ($sec, $min, $hr, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
	$mon += 1;
	if ($year < 1900)
		{
		$year += 1900;
		}
	my $niceDate = sprintf("%02d/%02d%/04d", $mday, $mon, $year);
	$niceDate;
}

# Message and time stamp to stdout.
sub TimeStamp {
	my ($whazzup) = @_;
	my $niceDate = NiceToday();
	$Output->("$whazzup: $niceDate\n\n");
}

sub NiceToday {
	my ($sec, $min, $hr, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
	$mon += 1;
	if ($year < 1900)
		{
		$year += 1900;
		}
	my $niceDate = sprintf("%04d/%02d/%02d %02d:%02d:%02d", $year, $mon, $mday, $hr, $min, $sec);
	$niceDate;
}

# "Thursday March 24 2010".
sub TodayForPeople {
	my ($useShortMonthName) = @_;
	$useShortMonthName = defined($useShortMonthName) ? 1 : 0;
	my @dayName;
	push @dayName, 'Sunday';
	push @dayName, 'Monday';
	push @dayName, 'Tuesday';
	push @dayName, 'Wednesday';
	push @dayName, 'Thursday';
	push @dayName, 'Friday';
	push @dayName, 'Saturday';
	my @MonthNames = (
		'Imaginary', 'January', 'February', 'March',     'April',   'May',
		'June',      'July',    'August',   'September', 'October', 'November',
		'December'
	);
	my @MnNmes = (
		'ZIP', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul',
		'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
	);

	my $todayString = DateForFileName();
	$todayString =~ m!^(\d+)\-(\d+)\-(\d+)$!;
	my $yr        = $1;
	my $mn        = $2;
	my $dy        = $3;
	my $monthName = $useShortMonthName ? $MnNmes[$mn] : $MonthNames[$mn];
	$todayString =~ s!\-!!g;
	my $todayDate =
		Date::Business->new(DATE => $todayString);    # eg Thursday March 24 2010, dayofweek==4
	my $todayDOW    = $todayDate->day_of_week();
	my $weekDayName = $dayName[$todayDOW];
	my $result      = "$weekDayName $monthName $dy, $yr";
	return $result;
}

sub YYYYMMDDForPeople {
	my ($yyyymmdd, $useShortMonthName) = @_;
	$useShortMonthName = defined($useShortMonthName) ? 1 : 0;

	my @dayName;
	push @dayName, 'Sunday';
	push @dayName, 'Monday';
	push @dayName, 'Tuesday';
	push @dayName, 'Wednesday';
	push @dayName, 'Thursday';
	push @dayName, 'Friday';
	push @dayName, 'Saturday';
	my @MonthNames = (
		'Imaginary', 'January', 'February', 'March',     'April',   'May',
		'June',      'July',    'August',   'September', 'October', 'November',
		'December'
	);
	my @MnNmes = (
		'ZIP', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul',
		'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
	);

	my $yr        = substr($yyyymmdd, 0, 4);
	my $mn        = substr($yyyymmdd, 4, 2);
	my $dy        = substr($yyyymmdd, 6, 2);
	my $monthName = $useShortMonthName ? $MnNmes[$mn] : $MonthNames[$mn];
	my $date = Date::Business->new(DATE => $yyyymmdd);    # eg Thursday March 24 2010, dayofweek==4
	my $dOW  = $date->day_of_week();
	my $weekDayName = $dayName[$dOW];
	my $result      = "$weekDayName $monthName $dy, $yr";
	return $result;
}

# NOTE this calculates elapsed business days, not calendar days.
# $elapsedDays for 20120605 to 20120608: |3| Tuesday to Friday
# $elapsedDays for 20120608 to 20120611: |1| Friday to Monday
sub ElapsedDaysYYYYMMDD {
	my ($fromDate, $toDate) = @_;
	my $toDat   = Date::Business->new(DATE => $toDate,   HOLIDAY => \&holiday);
	my $fromDat = Date::Business->new(DATE => $fromDate, HOLIDAY => \&holiday);
	my $diff    = $toDat->diffb($fromDat);
	return $diff;
}

sub IsWeekendYYYYMMDD {
	my ($yyyymmdd) = @_;
	my $date   = Date::Business->new(DATE => $yyyymmdd);   # eg Thursday March 24 2010, dayofweek==4
	my $dOW    = $date->day_of_week();
	my $result = ($dOW == 0 || $dOW == 6) ? 1 : 0;
	return $result;
}

# And this one calculates regular calendar days, weekends and holidays and all,
# for project that have been sabotaged by indifferent planning, so no actual
# working days, every day is a working day.
sub FullElapsedDaysYYYYMMDD {
	my ($fromDate, $toDate) = @_;
	my $toDat   = Date::Business->new(DATE => $toDate);
	my $fromDat = Date::Business->new(DATE => $fromDate);
	my $diff    = $toDat->diff($fromDat);
	return $diff;
}

# 1 if firstFile has a mod date at least slopSeconds seconds after
# the secondFile, 0 otherwise. So if the two files are dated within slopSeconds
# of each other, 0 will be returned for first vs second and second vs first.
# 0 if either file doesn't exist.
{
	my %ModTimeForFile;

	sub IsNewerThan {
		my ($firstFilePath, $secondFilePath, $slopSeconds) = @_;
		if (!(-e $firstFilePath) || !(-e $secondFilePath))
			{
			return 0;
			}

		my $firstTime;
		if (defined($ModTimeForFile{$firstFilePath}))
			{
			$firstTime = $ModTimeForFile{$firstFilePath};
			}
		else
			{
			my (
				$dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
				$size, $atime, $mtime, $ctime, $blksize, $blocks
			) = stat $firstFilePath;
			$firstTime = $mtime;
			$ModTimeForFile{$firstFilePath} = $firstTime;
			}

		my $secondTime;
		if (defined($ModTimeForFile{$secondFilePath}))
			{
			$secondTime = $ModTimeForFile{$secondFilePath};
			}
		else
			{
			my (
				$dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
				$size, $atime, $mtime, $ctime, $blksize, $blocks
			) = stat $secondFilePath;
			$secondTime = $mtime;
			$ModTimeForFile{$secondFilePath} = $secondTime;
			}

		my $result = ($firstTime - $secondTime >= $slopSeconds) ? 1 : 0;
	}

	# For use when paranoia is appropriate, returns 1 if mod dates on files
	# differ by more than $slopSeconds (5 is a good num there).
	sub ModDatesAreDifferent {
		my ($firstFilePath, $secondFilePath, $slopSeconds) = @_;
		if (!(-e $firstFilePath) || !(-e $secondFilePath))
			{
			return 0;
			}

		my $firstTime;
		if (defined($ModTimeForFile{$firstFilePath}))
			{
			$firstTime = $ModTimeForFile{$firstFilePath};
			}
		else
			{
			my (
				$dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
				$size, $atime, $mtime, $ctime, $blksize, $blocks
			) = stat $firstFilePath;
			$firstTime = $mtime;
			$ModTimeForFile{$firstFilePath} = $firstTime;
			}

		my $secondTime;
		if (defined($ModTimeForFile{$secondFilePath}))
			{
			$secondTime = $ModTimeForFile{$secondFilePath};
			}
		else
			{
			my (
				$dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
				$size, $atime, $mtime, $ctime, $blksize, $blocks
			) = stat $secondFilePath;
			$secondTime = $mtime;
			$ModTimeForFile{$secondFilePath} = $secondTime;
			}

		my $absTimeDiff =
			($firstTime >= $secondTime) ? $firstTime - $secondTime : $secondTime - $firstTime;
		my $result = ($absTimeDiff >= $slopSeconds) ? 1 : 0;
	}
}

sub Pct {
	my ($num) = @_;
	$num *= 100;
	my $pct = sprintf("%.2f%", $num);
	return $pct;
}

sub PctInt {
	my ($num) = @_;
	$num *= 100;
	my $pct = int($num + 0.5);
	$pct .= '%';
	return $pct;
}

# For use with human names in English, so eldridge PALMER becomes Eldridge Palmer.
sub PropercasedName {
	my ($name) = @_;
	$name =~ s!^\s+!!;
	$name =~ s!\s+$!!;
	my @nameParts = split(/ /, $name);
	my $pcName    = '';
	for (my $i = 0 ; $i < @nameParts ; ++$i)
		{
		my $part = ucfirst(lc($nameParts[$i]));
		if ($i > 0)
			{
			$pcName .= " $part";
			}
		else
			{
			$pcName = $part;
			}
		}

	return $pcName;
}

# Simplify a string to just a-zA-Z0-9, and _ in place of all other chars.
sub RepNonAlphaWithUnderscores {
	my ($str) = @_;
	$str =~ s![^a-zA-Z0-9]!_!g;
	return ($str);
}

# The original intent here was to turn a file path into a unique numeric ID for
# use with Elasticsearch.
# Note this is busted as of Qt 5.12.3, paths there are so long that the number string generated here
# goes over Elasticsearch's limit of 512 characters.
# Used with eg Elasticsearch as a unique numeric ID.
# The "numbers" are just ASCII codes for the characters in $string.
# Eg "c:/qt/5.7/msvc2013_64/include/qtnfc/qndefmessage.h" becomes
# 9958471131164753465547109115118995048495195545247105110991081171001014711311611010299471131101001011021091011151159710310146104
sub NumberStringFor {
	my ($string) = @_;
	my @ASCII    = unpack("C*", $string);
	my $result   = '';
	for (my $i = 0 ; $i < @ASCII ; ++$i)
		{
		$result .= $ASCII[$i];
		}

	return $result;
}

# Inverse of NumberStringFor, pass it a number string and get back ASCII
sub StringNumberFor {
	my ($numString) = @_;

	my $len        = length($numString);
	my $result     = '';
	my $curCharStr = '';
	for (my $i = 0 ; $i < $len ; ++$i)
		{
		my $nextChar = substr($numString, $i, 1);
		if (length($curCharStr) < 2)
			{
			$curCharStr .= $nextChar;
			}
		elsif (length($curCharStr) == 2 && ($curCharStr + 0) < 32)
			{
			$curCharStr .= $nextChar;
			}

		my $charStrAsNumber = $curCharStr + 0;
		if ($charStrAsNumber >= 32)
			{
			my $character = chr($charStrAsNumber);
			$result .= $character;
			$curCharStr = '';
			}
		}

	return ($result);
}

# Length of overlap between two strings, starting at left.
# LeftOverlapLength("C:/AA", "C:/AB") == 4,
# LeftOverlapLength("C:/AA", "P:/AB") == 0,
# you get the idea.
sub LeftOverlapLength {
	my ($str1, $str2) = @_;

	# Equalize Lengths
	if (length $str1 < length $str2)
		{
		$str2 = substr $str2, 0, length($str1);
		}
	elsif (length $str1 > length $str2)
		{
		$str1 = substr $str1, 0, length($str2);
		}

	# Reduce on right until match found
	while ($str1 ne $str2)
		{
		chop $str1;
		chop $str2;
		}

	return (length($str1));
}

sub Trim {
	my ($s) = @_;
	$s =~ s/^\s+|\s+$//g;
	return ($s);
}

# http://sysarch.com/Perl/autoviv.txt
# print "\$defined_tree->{foo}[0]{bar} is defined.\n"
#     if deep_defined($defined_tree, 'foo', 0, 'bar');
sub deep_defined {
	my ($ref, @keys) = @_;

	unless (@keys)
		{
		warn "deep_defined: no keys";
		return;
		}

	foreach my $key (@keys)
		{
		if (ref $ref eq 'HASH')
			{
			# fail when the key doesn't exist at this level
			return unless defined($ref->{$key});

			$ref = $ref->{$key};
			next;
			}

		if (ref $ref eq 'ARRAY')
			{
			# fail when the index is out of range or is not defined
			return unless 0 <= $key && $key < @{$ref};
			return unless defined($ref->[$key]);
			$ref = $ref->[$key];
			next;
			}

		# fail when the current level is not a hash or array ref
		return;
		}

	return 1;
}

# This works with older versions of Perl, where !/([^/]+)$! might not.
# Returns "" if path ends in \ or /.
sub FileNameFromPath {
	my ($path) = @_;
	$path =~ s!\\!/!g;
	my $fileName = '';
	if (index($path, "/") >= 0)
		{
		$fileName = substr($path, rindex($path, "/") + 1, length($path) - rindex($path, "/") - 1);
		#		my $lastSlashPos = length($path) - 1;
		#		while ($lastSlashPos >= 0 && substr($path, $lastSlashPos, 1) ne "/")
		#			{
		#			--$lastSlashPos;
		#			}
		#		$fileName = substr($path, $lastSlashPos + 1);
		}
	else
		{
		$fileName = $path;
		}
	return $fileName;
}

# TS - trailing slash.
# => path: |E:\COMPUNIT\AMAPCEO JE Phase 3\Software Support Files\Appendix C Mgr Comment Forms\Comment Forms\junk.xyz|
# <= dir:  |E:/COMPUNIT/AMAPCEO JE Phase 3/Software Support Files/Appendix C Mgr Comment Forms/Comment Forms/|
sub DirectoryFromPathTS {
	my ($path) = @_;
	$path =~ s!\\!/!g;
	my $dir = '';
	if (index($path, "/") >= 0)
		{
		my $lastSlashPos = rindex($path, "/");
		$dir = substr($path, 0, $lastSlashPos + 1);
		}
	else
		{
		$dir = $path;
		}
	return $dir;
}

# "argle.txt" -> ("argle", ".txt")
sub FileNameProperAndExtensionFromFileName {
	my ($name) = @_;
	$name =~ m!(\.[^.]+)$!;
	my $ext = $1;
	$ext ||= '';
	my $fileNameProper = $name;
	$fileNameProper =~ s!$ext$!!;
	return ($fileNameProper, $ext);
}

# Tack a _NN onto file name if needed, ++ until there's no file at that path.
sub FreshPath {
	my ($path) = @_;
	$path =~ s!\\!/!g;
	my $result = $path;
	if (-f $result)
		{
		my $suffixNumber = 1;
		my $fileName     = FileNameFromPath($path);
		my $dir          = $path;
		$dir =~
			s!/[^/]+$!!;  # was  s!/$fileName$!!; - that failed on things like "(2)" in the filename
		$fileName =~ m!(\.[^.]+)$!;
		my $ext            = $1;
		my $fileNameProper = $fileName;
		$fileNameProper =~ s!$ext$!!;
		my $newPath = $dir . '/' . $fileNameProper . '_' . $suffixNumber . $ext;
		while (-f $newPath)
			{
			++$suffixNumber;
			$newPath = $dir . '/' . $fileNameProper . '_' . $suffixNumber . $ext;
			}
		$result = $newPath;
		}

	return $result;
}

# Unique name, limited length. No silly short $maxNameLength please.
# If we run into a number and length is >= 24 and <= 8 numbers, drop the whole number
# (plus any spaces or underscores). Eg 00012345 00023456.txt -> 00012345.txt';
sub FreshPathWithShortenedName {
	my ($path, $maxNameLength) =
		@_;    # $maxNameLength >= 8 total, >= 4 minus extension, or no shortening
	my $originalMaxNameLength = $maxNameLength;
	$path =~ s!\\!/!g;
	my $name          = FileNameFromPath($path);
	my $currentLength = length($name);
	my $dir           = $path;
	$dir =~ s!/[^/]+$!!;
	$name = ShortenedFileName($name, $maxNameLength);
	my $result = $dir . '/' . $name;

	if (-f $result)
		{
		my $freshPath =
			FreshPath($result);    # fresh file name proper could be longer due to _NN on end
		$name          = FileNameFromPath($freshPath);
		$currentLength = length($name);
		while ($currentLength > $maxNameLength && $maxNameLength >= 8)
			{
			--$maxNameLength;
			$name          = ShortenedFileName($name, $maxNameLength);
			$result        = $dir . '/' . $name;
			$freshPath     = FreshPath($result);
			$name          = FileNameFromPath($freshPath);
			$currentLength = length($name);
			}
		$result = $dir . '/' . $name;

		if (-f $result
			|| ($originalMaxNameLength >= 8 && $currentLength > $originalMaxNameLength)
			)  # give up keeping the original file name, just use a number - but keep the extension.
			{
			my ($fileNameProper, $ext) = FileNameProperAndExtensionFromFileName($name);
			my $num = 1;
			$result = $dir . '/' . $num . $ext;
			while (-f $result && $num <= 10000)
				{
				++$num;
				$result = $dir . '/' . $num . $ext;
				}
			}
		}

	return $result;
}

# Limit total file name length to $maxNameLength, by removing characters
# before the extension if any. No check that path is unique - we don't even
# have the path here.
sub ShortenedFileName {
	my ($name, $maxNameLength) =
		@_;    # $maxNameLength >= 8 total, >= 4 minus extension, or no shortening
	my $result        = $name;
	my $currentLength = length($name);
	if ($maxNameLength >= 8 && $currentLength > $maxNameLength)
		{
		$name =~ m!(\.[^.]+)$!;
		my $ext            = $1;
		my $fileNameProper = $name;
		$fileNameProper =~ s!$ext$!!;
		my $extLength        = length($ext);
		my $properNameLength = length($fileNameProper);
		my $maxProperLength  = $maxNameLength - $extLength;  # no wonkie superlong extensions please
		if ($maxProperLength >= 4)
			{
			# Special case: file name ends in [_ ]*\d+[_ ]+ and removing that would leave
			# at least 8 chars in the proper name.
			# Ensure however that if any number can be removed that there is still a number
			# left in the name after removal.
			# (In other words when taking out entire numbers don't take out all the numbers.)
			my $madeItShorter = 1;
			while ($properNameLength >= 8
				&& $properNameLength > $maxProperLength
				&& $fileNameProper =~ m!\D\d+[_ ]*$!
				&& $madeItShorter)
				{
				my $testShorterName = $fileNameProper;
				$testShorterName =~ s!\d+[_ ]*$!!;
				$testShorterName =~ s![_ ]+$!!;
				my $testLen = length($testShorterName);
				if ($testLen >= 8 && $testShorterName =~ m!\d!)
					{
					$fileNameProper   = $testShorterName;
					$properNameLength = length($fileNameProper);
					}
				else
					{
					$madeItShorter = 0;
					}
				}


			if ($properNameLength > $maxProperLength)
				{
				my $trailerTrimmed = substr($fileNameProper, $maxProperLength);
				$fileNameProper = substr($fileNameProper, 0, $maxProperLength);
				# Nuisance, we might have left part of a number on the end, get rid of it
				# if resulting name would
				# still contain a number and not be too short. Getting too hard to do much
				# better than that.
				if ($trailerTrimmed =~ m!^\d! && $fileNameProper =~ m!\D\d+$!)
					{
					my $testShorterName = $fileNameProper;
					$testShorterName =~ s!\d+[_ ]*$!!;
					$testShorterName =~ s![_ ]+$!!;
					my $testLen = length($testShorterName);
					if ($testLen >= 8 && $testShorterName =~ m!\d!)
						{
						$fileNameProper   = $testShorterName;
						$properNameLength = length($fileNameProper);
						}
					}
				}

			# Lastly, trim space and optional single letter from end of name, looks ugly
			if ($properNameLength >= 10 && $fileNameProper =~ m![ _]\D?$!)
				{
				$fileNameProper =~ s![ _]\D?$!!;
				$properNameLength = length($fileNameProper);
				}

			$result = $fileNameProper . $ext;
			}
		}

	return $result;
}

# Return path to local copy after making it. C:/temp/ is used for the copy.
# Return '' on failure.
sub MakeLocalCopy {
	my ($path)   = @_;
	my $result   = '';
	my $fileName = FileNameFromPath($path);
	my $tempPath = 'C:/temp/' . $fileName;
	unlink($tempPath);
	if (copy($path, $tempPath))
		{
		$result = $tempPath;
		}

	return $result;
}

sub MakeLocalRenamedCopy {
	my ($path)   = @_;
	my $result   = '';
	my $fileName = FileNameFromPath($path);
	$fileName =~ s!\.(\w+)$!_temp.$1!;
	my $tempPath = 'C:/temp/' . $fileName;
	unlink($tempPath);
	if (copy($path, $tempPath))
		{
		$result = $tempPath;
		}

	return $result;
}

# Extension ext is taken from file name, copy is
# C:/temp/tempcopy.ext
# Requires: $path must end in a file extension.
sub MakeLocalTempCopy {
	my ($path)   = @_;
	my $result   = '';
	my $fileName = FileNameFromPath($path);
	$fileName =~ m!\.([^.]+)$!;
	my $ext      = $1;
	my $tempPath = "C:/temp/tempcopy.$ext";
	unlink($tempPath);
	if (copy($path, $tempPath))
		{
		$result = $tempPath;
		}

	return $result;
}

# Copy file from local to network storage, optional delete of local.
# Returns 1 if copy succeeds, 0 otherwise.
# Local copy is kept if $keepLocalCopy is defined.
# Meh, you can ignore this one.
sub CopyLocalToNetwork {
	my ($localPath, $networkPath, $keepLocalCopy) = @_;
	$keepLocalCopy = defined($keepLocalCopy) ? 1 : 0;
	my $result = 0;
	unlink($networkPath);
	if (copy($localPath, $networkPath))
		{
		if (!$keepLocalCopy)
			{
			unlink($localPath);
			}
		$result = 1;
		}

	return $result;
}

sub LocalPathForNetworkPath {
	my ($path)   = @_;
	my $fileName = FileNameFromPath($path);
	my $result   = 'C:/temp/' . $fileName;
	return $result;
}

# Excel HYPERLINK.
sub ValueFromHyperLink {
	my ($link) = @_;
	my $value;
	if ($link =~ m!\"([^"]+)\"\)$!)    # ..."value")
		{
		$value = $1;
		}
	else
		{
		$value = $link;
		}

	return $value;
}

sub PathFromHyperlink {
	my ($hLink) = @_;
	my $result = '';
	if ($hLink =~ m!^=HYPERLINK\(\"([^"]+)\"[^"]+\"([^"]+)\"!)
		{
		$result = $1;
		}

	return $result;
}

sub PathAndValueFromHyperlink {
	my ($hLink) = @_;
	my $path    = '';
	my $value   = '';
	if ($hLink =~ m!^=HYPERLINK\(\"([^"]+)\"[^"]+\"([^"]+)\"!)
		{
		$path  = $1;
		$value = $2;
		}
	else
		{
		$value = $hLink;
		}

	return ($path, $value);
}

# Letter for column index and column index for letter
# in Excel. All indexes are 1-based.
# 'A' is 1, 26 is 'Z'.
sub ExcelLetterForColumn {
	my ($col) = @_;
	my $letter = 'A';
	for (my $i = 1 ; $i < $col ; ++$i)
		{
		++$letter;
		}
	$letter;
}

sub ExcelColumnForLetter {
	my ($letter) = @_;

	$letter = uc($letter);
	my $tryLetter = 'A';
	my $num       = 1;
	while ($tryLetter ne $letter)
		{
		++$tryLetter;
		++$num;
		if ($num > 100000)
			{
			$num = 0;
			last;
			}
		}
	$num;
}

sub ExcelHyperlink {
	my ($link, $value) = @_;
	$link =~ s!/!\\!g;
	my $result = "=HYPERLINK(\"$link\", \"$value\")";
	return $result;
}

# Legacy, do not use.
sub GetDriveLetter {
	my $driveLetter = 'C';
	return $driveLetter;
}

# Put list of full paths for files at top level of folder $dirToSearch in @$fileListA.
# Returns count of files, -1 if $dirToSearch can't be opened.
# Note  @$fileListA is not emptied out beforehand here, or sorted. All slashes
# in returned list are forward slashes '/'.
# Note for a "wide" version use libs/win_wide_filepaths.pm#FindFileWide().
sub GetTopFilesInFolder {
	my ($dirToSearch, $fileListA) = @_;
	$dirToSearch =~ s!\\!/!g;
	if (substr($dirToSearch, -1, 1) ne "/")
		{
		$dirToSearch .= "/";
		}
	my $d        = DirHandle->new($dirToSearch);
	my $numFiles = -1;

	if (defined($d))
		{
		$numFiles = 0;
		my $fileName = '';
		while (defined($fileName = $d->read))
			{
			my $path = $dirToSearch . $fileName;
			if (-f $path)
				{
				push @$fileListA, $path;
				++$numFiles;
				}
			}
		}

	return ($numFiles);
}

# Put list of full paths to directories at top level of folder $dirToSearch in @$dirListA.
# Returns count of subfolders, -1 if $dirToSearch can't be opened.
# Note @$dirListA is not emptied out beforehand here, or sorted. All slashes in the returned
# list are forward slashes '/', and each entry has a trailing forward slash.
# Note for a "wide" version use libs/win_wide_filepaths.pm#FindFileWide().
sub GetTopSubfoldersInFolder {
	my ($dirToSearch, $dirListA) = @_;
	$dirToSearch =~ s!\\!/!g;
	if (substr($dirToSearch, -1, 1) ne "/")
		{
		$dirToSearch .= "/";
		}
	my $d       = DirHandle->new($dirToSearch);
	my $numDirs = -1;

	if (defined($d))
		{
		$numDirs = 0;
		my $dirName = '';
		while (defined($dirName = $d->read))
			{
			my $path = $dirToSearch . $dirName . '/';
			if (-d $path && $dirName !~ m!^\.\.?$!)    # Skip '.' and '..'
				{
				push @$dirListA, $path;
				++$numDirs;
				}
			}
		}
	return ($numDirs);
}

sub random_int_between {
	my ($min, $max) = @_;
	# Assumes that the two arguments are integers!
	return $min if $min == $max;
	($min, $max) = ($max, $min) if $min > $max;
	return $min + int rand(1 + $max - $min);
}

sub Commify {
	local $_ = shift;
	1 while s/^([-+]?\d+)(\d{3})/$1,$2/;
	return $_;
}

use ExportAbove;
return 1;
