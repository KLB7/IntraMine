# colour2gray.pl: convert #rrggbb to #xxxxxx gray, to stdout.

# perl C:\perlprogs\mine\colour2gray.pl file > outfile
# perl C:\perlprogs\mine\colour2gray.pl "C:/perlprogs/mine/test/formcss1.txt" > "C:/perlprogs/mine/test/formcss1_out.txt"

use strict;
use Carp;
use FileHandle;
use DirHandle;
use File::Path;
use File::Find;
use File::Copy;

my $filePath = shift @ARGV;
my $pathH = FileHandle->new("$filePath") or die("Could not open $filePath!");
my @outlines;
my $line = '';
while ($line = <$pathH>)
	{
	chomp($line);
	
	$line =~ s{#([0-9A-F]{6})\b}
{
	grayscaleRGB(
		hex substr($1, 0, 2),
		hex substr($1, 2, 2),
		hex substr($1, 4, 2)
	)
}eig;
	push @outlines, $line;
	}
close($pathH);

my $numLines = @outlines;
for (my $i = 0; $i < $numLines; ++$i)
	{
	print("$outlines[$i]\n");
	}

sub grayscaleRGB {
	my($r,$g,$b) = @_;
	
	# Convert RGB to grayscale
	$r=$g=$b = 0.30*$r + 0.59*$g + 0.11*$b;
	return(sprintf("#%x%x%x", $r, $g, $b));
	}
	