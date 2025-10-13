# intramine_spellcheck.pm: spell checking.
# At present spell checking is only available in the Editor for .txt files.
# SpellCheck() is called by intramine_linker.pl#AddWebAndFileLinksToVisibleLinesForCodeMirror().
# The English word list is mostly taken from
# https://www.lemoda.net/perl/text-fuzzy-spellchecker/index.html

package intramine_spellcheck;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use utf8;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use win_wide_filepaths;


# Dictionary.
my $dict;    # Word list file full path

my %wordsH;  # Hash of all words, lower case.
my $min_length = 4;
# Known mistakes, don't repeat.
my %known;

# Text to check.
my $haveRefToText;    # For CodeMirror we get the text not a ref, and this is 0.
my $line;             # Full text of a single line.
my $len;              # Length of $line.

# Spelling error markup.
# In non-CodeMirror views where the text is directly altered, replacements are
# more easily done in reverse order to avoid throwing off the start/end.
# For CodeMirror the @repStr etc entries are passed back without altering the text.
my @repStr;    # new link, eg <a href="#Header_within_doc">#Header within doc</a>
my @repLen;    # length of substr to replace in line, eg length('#Header within doc')
my @repStartPos
	;    # where header being replaced starts, eg zero-based positon of '#' in '#Header within doc'
my @repLinkType;    # For CodeMirror, 'glossary' is the only type here.


# Called around intramine_linker.pl#115.
sub InitDictionary {
	my ($dictionaryPath) = @_;
	$dict = $dictionaryPath;
	ReadDictionary();
}

# Called just above, and by intramine_linker.pl#HandleBroadcastRequest().
sub ReadDictionary {
	%wordsH = ();

	my $list  = ReadTextFileDecodedWide($dict);
	my @lines = split(/\n/, $list);
	for (my $i = 0 ; $i < @lines ; ++$i)
		{
		my $lcword = lc($lines[$i]);
		$wordsH{$lcword} = 1;
		}
}

sub DictionaryPath {
	return ($dict);
}

# Add $word to data/EnglishWords.txt.
# See intramine_linker.pl#AddToDictionary().
sub AddOneWordToDictionary {
	my ($word) = @_;
	if (defined($wordsH{$word}))
		{
		return (1);
		}

	AppendToExistingUTF8FileWide($dict, "$word\n");
	my $lcword = lc($word);
	$wordsH{$lcword} = 1;

	return (1);
}

# See intramine_linker.pl#AddWebAndFileLinksToVisibleLinesForCodeMirror().
sub SpellCheck {
	my ($txtR, $currentLineNumber, $linksA) = @_;

	if (ref($txtR) eq 'SCALAR')    # REFERENCE to a scalar, so doing text
		{
		# Not currently supported.
		return;
		}
	else                           # not a ref, so doing CodeMirror
		{
		$haveRefToText = 0;
		$line          = $txtR;
		}

	$len         = length($line);
	@repStr      = ();            # new link, eg <a href="#Header_within_doc">#Header within doc</a>
	@repLen      = ();            # length of substr to replace in line
	@repStartPos = ();            # where error being marked up starts
	@repLinkType = ();            # For CodeMirror, the "type" of link (file image dir etc)

	EvaluateSpelling($linksA, $currentLineNumber);

	my $numReps = @repStr;
	for (my $i = 0 ; $i < $numReps ; ++$i)
		{
		if ($repLen[$i] > 0)
			{
			my $nextLinkPos = @$linksA;
			$linksA->[$nextLinkPos]{'lineNumInText'} = $currentLineNumber;
			$linksA->[$nextLinkPos]{'columnInText'}  = $repStartPos[$i];
			$linksA->[$nextLinkPos]{'textToMarkUp'}  = substr($line, $repStartPos[$i], $repLen[$i]);
			$linksA->[$nextLinkPos]{'linkType'}      = $repLinkType[$i];
			$linksA->[$nextLinkPos]{'linkPath'}      = $repStr[$i];
			}
		}
}

use ExportAbove;

sub EvaluateSpelling {
	my ($linksA, $currentLineNumber) = @_;

	while ($line =~ m!(\w[\w'-]+\w)!g)
		{
		my $startPos     = $-[1];               # beginning of match
		my $endPos       = $+[1];               # one past last matching character
		my $originalWord = $1;
		my $wd           = lc($originalWord);
		my $WD           = uc($originalWord);
		if (!defined($wordsH{$wd}))
			{
			my $len = length($originalWord);
			if ($len >= $min_length
				&& !PositionIsInsideLink($startPos, $linksA, $currentLineNumber))
				{
				my $markItUp = 1;
				# Is word hyphenated, but parts are in the word list? Skip it
				my $hyphenPos = -1;
				if (($hyphenPos = index($originalWord, '-')) > 0)
					{
					my $leftWord  = substr($wd, 0, $hyphenPos);
					my $rightWord = substr($wd, $hyphenPos + 1);
					if (defined($wordsH{$leftWord}) && defined($wordsH{$rightWord}))
						{
						$markItUp = 0;
						}
					elsif (defined($wordsH{$leftWord . $rightWord}))
						{
						$markItUp = 0;
						}
					}

				if ($originalWord =~ m!.+[A-Z_]!)    # capital or underscore after first
					{
					$markItUp = 0;
					}

				if ($originalWord =~ m!^[0-9.-]+$!)    # number or date
					{
					$markItUp = 0;
					}

				if ($markItUp)
					{
					push @repStr,      $originalWord;
					push @repLen,      $len;
					push @repStartPos, $startPos;
					if (!$haveRefToText)
						{
						push @repLinkType, 'spelling';
						}
					}
				}
			}
		}
}

# Goal: skip marking any spelling errors inside FLASH links or glossary popups.
# $linksA is an array holding markup for all links and popups and spelling errors
# encountered so far.
sub PositionIsInsideLink {
	my ($startPos, $linksA, $currentLineNumber) = @_;
	my $result = 0;

	my $numLinks = @$linksA;
	for (my $i = 0 ; $i < $numLinks ; ++$i)
		{
		if ($linksA->[$i]{'lineNumInText'} == $currentLineNumber)
			{
			my $startInText = $linksA->[$i]{'columnInText'};
			if ($startPos >= $startInText)
				{
				my $len = length($linksA->[$i]{'textToMarkUp'});
				if ($startPos <= $startInText + $len)
					{
					$result = 1;
					last;
					}
				}
			}
		}

	return ($result);
}
1;
