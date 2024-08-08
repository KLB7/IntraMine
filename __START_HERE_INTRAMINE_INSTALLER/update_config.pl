# intramine_update_config.pl:
# This runs as part of IntraMine's installer
# and has no other intended use.
# Modify value for a key in data/intramine_config.txt

use strict;
use warnings;
use FileHandle;

#my $TESTING = 1; # Remove or set to 0 for release!

my $IntraMineDir = shift @ARGV;
my $ConfigKey = shift @ARGV;
my $ConfigNewValue = shift @ARGV;
$IntraMineDir =~ s!\\!/!g;
my $ConfigFilePath = $IntraMineDir . "/data/intramine_config.txt";

# if ($TESTING)
# 	{
#	$ConfigFilePath = $IntraMineDir . "/intramine_config.txt";
# 	print("\$ConfigFilePath: |$ConfigFilePath|\n");
# 	print("  Key: |$ConfigKey|\n");
# 	print("Value: |$ConfigNewValue|\n");
# 	}

my $fileH = FileHandle->new("$ConfigFilePath")
			or die("FILE ERROR could not open $ConfigFilePath for reading!");
my $line = '';
my @lines;
while ($line = <$fileH>)
	{
	chomp($line);
	if ($line =~ m!^$ConfigKey\t!)
		{
		# if ($TESTING)
		# 	{
		# 	print("REP DONE!\n");
		# 	}
		$line = "$ConfigKey\t$ConfigNewValue";
		}
	push @lines, $line;
	}
close($fileH);

$fileH = FileHandle->new("> $ConfigFilePath")
			or die("FILE ERROR could not open $ConfigFilePath for writing!");
print $fileH join("\n", @lines);
print $fileH "\n";
close($fileH);
