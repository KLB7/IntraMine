# codemirror_extensions.pl: pull a list of file extensions that CodeMirror supports.
# Plus ".bat", which CodeMirror doesn't support as of Feb 2019.

# perl C:\perlprogs\mine\codemirror_extensions.pl

use strict;
use FileHandle;
use DirHandle;

my $cmMetaFile = "C:/perlprogs/mine/CodeMirror-master/mode/meta.js";
my $outFile = "C:/perlprogs/mine/temp/cm_extensions.txt";

my @extensionArray;
my %extensionHash; # to check for duplicates
my %extsForLanguage; # $extsForLanguage{'HTML'} = 'html,htm,handlebars,hbs';

my $cmFileH = new FileHandle($cmMetaFile)
	or die("Could not find |$cmMetaFile|!\n");
my $line;
my $name = '';
while ($line = <$cmFileH>)
	{
	chomp($line);
	if ($line =~ m!\{name\:\s+\"([^"]+)\"!)
		{
		$name = $1;
		# Childproofing
		$name =~ s!fuck!f__k!g;
		}
		
	if ($line =~ m!ext\:\s*\[([^\]]+)\]!)
		{
		my $extensions = $1;
		my @extArr = split(/,\s+/, $extensions);
		for (my $j = 0; $j < @extArr; ++$j)
			{
			my $extProper = $extArr[$j];
			$extProper =~ s!"!!g;
			if (index($extProper, ".") > 0)
				{
				$extProper = substr($extProper, index($extProper, ".") + 1);
				}
			
			if (!defined($extensionHash{$extProper}))
				{
				my $correctedExt = $extProper;
				$correctedExt =~ s!\+!\\\+!g;
				push @extensionArray, $correctedExt;
				$extensionHash{$extProper} = 1;
				}
				
			if (!defined($extsForLanguage{$name}))
				{
				$extsForLanguage{$name} = $extProper;
				}
			else
				{
				$extsForLanguage{$name} .= ",$extProper";
				}
			}
		}
	}
close($cmFileH);

# Add in bat.
push @extensionArray, 'bat';
$extsForLanguage{'Batch'} = 'bat';

my @sortedExtensions = sort @extensionArray;

my $outFileH = new FileHandle("> $outFile")
	or die("FILE ERROR could not make |$outFile|!");
for (my $i = 0; $i < @sortedExtensions; ++$i)
	{
	if ($i == 0)
		{
		print $outFileH "$sortedExtensions[$i]";
		}
	else
		{
		print $outFileH "|$sortedExtensions[$i]";
		}
	}
print $outFileH "\n\n";

foreach my $key (sort keys %extsForLanguage)
	{
	print $outFileH "\$extensionsForLanguage{'$key'} = '$extsForLanguage{$key}';\n";
	}
close($outFileH);

print("Done. See |$outFile|\n");