#!/usr/bin/env perl

# docx2txt, a command-line utility to convert Docx documents to text format.
# Copyright (C) 2008-2014 Sandeep Kumar
# (This is still basically the work of Sandeep Kumar, but converted to docx2txt.pm, using 7-zip
# instead of unzip, with config file, directory handling and some other stuff removed,
# tested under Perl 5.22 and 5.30.)
# For IntraMine use, see intramine_viewer.pl#GetWordAsText().
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

#
# This script extracts text from document.xml contained inside .docx file.
# Perl v5.10.1 was used for testing this script.
#
# Author : Sandeep Kumar (shimple0 -AT- Yahoo .DOT. COM)
#
# ChangeLog :
#
#    10/08/2008 - Initial version (v0.1)
#    15/08/2008 - Script takes two arguments [second optional] now and can be
#                 used independently to extract text from docx file. It accepts
#                 docx file directly, instead of xml file.
#    18/08/2008 - Added support for center and right justification of text that
#                 fits in a line 80 characters wide (adjustable).
#    03/09/2008 - Fixed the slip in usage message.
#    12/09/2008 - Slightly changed the script invocation and argument handling
#                 to incorporate some of the shell script functionality here.
#                 Added support to handle embedded urls in docx document.
#    23/09/2008 - Changed #! line to use /usr/bin/env - good suggestion from
#                 Rene Maroufi (info>AT<maroufi>DOT<net) to reduce user work
#                 during installation.
#    31/08/2009 - Added support for handling more escape characters.
#                 Using OS specific null device to redirect stderr.
#                 Saving text file in binary mode.
#    03/09/2009 - Updations based on feedback/suggestions from Sergei Kulakov
#                 (sergei>AT<dewia>DOT<com).
#                 - removal of non-document text in between TOC related tags.
#                 - display of hyperlink alongside linked text user controlled.
#                 - some character conversion updates
#    05/09/2009 - Merged cjustify and rjustify into single subroutine justify.
#                 Added more character conversions.
#                 Organised conversion mappings in tabular form for speedup and
#                 easy maintenance.
#                 Tweaked code to reduce number of passes over document content.
#    10/09/2009 - For leaner text experience, hyperlink is not displayed if
#                 hyperlink and hyperlinked text are same, even if user has
#                 enabled hyperlink display.
#                 Improved handling of short line justification. Many
#                 justification tag patterns were not captured earlier.
#    11/09/2009 - A directory holding the unzipped content of .docx file can
#                 also be specified as argument to the script, in place of file.
#    17/09/2009 - Removed trailing slashes from input directory name.
#                 Updated unzip command invocations to handle path names
#                 containing spaces.
#    01/10/2009 - Added support for configuration file.
#    02/10/2009 - Using single quotes to specify path for unzip command. 
#    04/10/2009 - Corrected configuration option name lineIndent to listIndent.
#	 11/12/2011 - Configuration variables now begin with config_ .
#				  Configuration file is looked for in HOME directory as well.
#				  Added a check for existence of unzip command.
#				  Superscripted cross-references are placed within [...] now.
#				  Fixed bugs #3003903, #3082018 and #3082035.
#				  Fixed nullDevice for Cygwin.
#	 12/12/2011 - Configuration file is also looked for in /etc, default
#				  location for Unix-ish systems.
#	 22/12/2011 - Added &apos; and &quot; to docx specific escape characters
#				  conversions. [Bug #3463033]
#	 24/12/2011 - Improved handling of special (non-text) characters, along with
#				  support for more non-text characters.
#	 05/01/2012 - Configuration file is now looked for in current directory,
#				  user configuration directory and system configuration
#				  directory (in the specified order). This streamlining allows
#				  for per user configuration file even on Windows.
#	 14/01/2012 - Wrong code was committed during earlier fixing of nullDevice
#				  for Cygwin, fixed that.
#				  Usage is extended to accept docx file from standard input.
#				  "-h" has to be given as the first argument to get usage help.
#				  Added new configuration variable "config_tempDir".
#	 14/03/2014 - Remove deleted text from output. This effects in case changes
#				  are being tracked in docx document. Patch was contributed by
#				  William Parsons (wbparsons>AT<cshore>DOT<com).
#				  Removed experimental config option config_exp_extra_deEscape.
#	 27/03/2014 - Remove non-document_text content marked by wp/wp14 tags.
#	 07/04/2014 - Added support for handling lists (bullet, decimal, letter,
#				  roman) along with (attempt at) indentation.
#				  Added new configuration variable config_twipsPerChar.
#				  Removed configuration variable config_listIndent.
#	 14/04/2014 - Fixed list numbering - lvl start value needs to be considered.
#				  Improved list indentation and corresponding code.
#	 27/04/2014 - Improved paragraph content layout/indentation.
#	 13/05/2014 - Added new configuration variable config_unzip_opts. Users can
#				  now use unzipping programs like 7z, pkzipc, winzip as well.
#

# Module usage:
# (set path for docx2txt.pm wherever you save it, eg if it's up one from your Perl
# program and down into 'libs' then)
## use Path::Tiny qw(path);
## use lib path($0)->absolute->parent(2)->child('libs')->stringify;
## use docx2txt;
## my $filePath = 'C:/testdocs/wordtest.docx';
## my $docxReader = new docx2txt();
## # Showing hyperlink addresses and list numbering is off by default.
## $docxReader->ShowHyperlinks();
## $docxReader->ShowListNumbering();
## my $contents = $docxReader->Contents($filePath);
# (IntraMine, see intramine_viewer.pl#GetWordAsText())


package docx2txt;

use strict;

my $config_unzip = 'C:/Program Files/7-Zip/7z.exe';	# or 'C:/path/to/unzip.exe'
my $using7zip = ($config_unzip =~ m!7z!);
my $config_newLine = "\n";			# Alternative is "\r\n".
my $config_lineWidth = 80;			# Line width, used for short line justification.
my $config_showHyperLink = "n";		# Show hyperlink alongside linked text.
my $config_twipsPerChar = 120;		# Approx mapping for layout purpose.
my $config_showListNumbering = "n"; # Show 1. 2. 3. etc for lists

my $nulldevice = '';
if ($ENV{OS} =~ /^Windows/) {
    $nulldevice = "nul";
} else {
    $nulldevice = "/dev/null";
}

# Character conversion tables

# Only amp, gt and lt are required for docx escapes, others are used for better
# text experience.
my %escChrs = (	amp => '&', apos => '\'', gt => '>', lt => '<', quot => '"',
		acute => '\'', brvbar => '|', copy => '(C)', divide => '/',
		laquo => '<<', macr => '-', nbsp => ' ', raquo => '>>',
		reg => '(R)', shy => '-', times => 'x'
);

my %splchars = (
	"\xC2" => {
	"\xA0" => ' ',		# <nbsp> non-breaking space
	"\xA2" => 'cent',	# <cent>
	"\xA3" => 'Pound',	# <pound>
	"\xA5" => 'Yen',	# <yen>
	"\xA6" => '|',		# <brvbar> broken vertical bar
#	"\xA7" => '',		# <sect> section
	"\xA9" => '(C)',	# <copy> copyright
	"\xAB" => '<<',		# <laquo> angle quotation mark (left)
	"\xAC" => '-',		# <not> negation
	"\xAE" => '(R)',	# <reg> registered trademark
	"\xB1" => '+-',		# <plusmn> plus-or-minus
	"\xB4" => '\'',		# <acute>
	"\xB5" => 'u',		# <micro>
#	"\xB6" => '',		# <para> paragraph
	"\xBB" => '>>',		# <raquo> angle quotation mark (right)
	"\xBC" => '(1/4)',	# <frac14> fraction 1/4
	"\xBD" => '(1/2)',	# <frac12> fraction 1/2
	"\xBE" => '(3/4)',	# <frac34> fraction 3/4
	},

	"\xC3" => {
	"\x97" => 'x',		# <times> multiplication
	"\xB7" => '/',		# <divide> division
	},

	"\xCF" => {
	"\x80" => 'PI',		# <pi>
	},

	"\xE2\x80" => {
	"\x82" => '	 ',		# <ensp> en space
	"\x83" => '	 ',		# <emsp> em space
	"\x85" => ' ',		# <qemsp>
	"\x93" => ' - ',	# <ndash> en dash
	"\x94" => ' -- ',	# <mdash> em dash
	"\x95" => '--',		# <horizontal bar>
	"\x98" => '`',		# <soq>
	"\x99" => '\'',		# <scq>
	"\x9C" => '"',		# <doq>
	"\x9D" => '"',		# <dcq>
	"\xA2" => '::',		# <diamond symbol>
	"\xA6" => '...',	# <hellip> horizontal ellipsis
	"\xB0" => '%.',		# <permil> per mille
	},

	"\xE2\x82" => {
	"\xAC" => 'Euro'	# <euro>
	},

	"\xE2\x84" => {
	"\x85" => 'c/o',	# <care/of>
	"\x97" => '(P)',	# <sound recording copyright>
	"\xA0" => '(SM)',	# <servicemark>
	"\xA2" => '(TM)',	# <trade> trademark
	"\xA6" => 'Ohm',	# <Ohm>
	},

	"\xE2\x85" => {
	"\x93" => '(1/3)',
	"\x94" => '(2/3)',
	"\x95" => '(1/5)',
	"\x96" => '(2/5)',
	"\x97" => '(3/5)',
	"\x98" => '(4/5)',
	"\x99" => '(1/6)',
	"\x9B" => '(1/8)',
	"\x9C" => '(3/8)',
	"\x9D" => '(5/8)',
	"\x9E" => '(7/8)',
	"\x9F" => '1/',
	},

	"\xE2\x86" => {
	"\x90" => '<--',	# <larr> left arrow
	"\x92" => '-->',	# <rarr> right arrow
	"\x94" => '<-->',	# <harr> left right arrow
	},

	"\xE2\x88" => {
	"\x82" => 'd',		# partial differential
	"\x9E" => 'infinity',
	},

	"\xE2\x89" => {
	"\xA0" => '!=',		# <neq>
	"\xA4" => '<=',		# <leq>
	"\xA5" => '>=',		# <geq>
	},

	"\xEF\x82" => {
	"\xB7" => '*'		# small white square
	}
);

my @RomanNumbers = ( "",
	"i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii",
	"xiii", "xiv", "xv", "xvi", "xvii", "xviii", "xix", "xx", "xxi", "xxii",
	"xxiii", "xxiv", "xxv", "xxvi", "xxvii", "xxviii", "xxix", "xxx", "xxxi",
	"xxxii", "xxxiii", "xxxiv", "xxxv", "xxxvi", "xxxvii", "xxxviii", "xxxix",
	"xl", "xli", "xlii", "xliii", "xliv", "xlv", "xlvi", "xlvii", "xlviii",
	"xlix", "l", "li" );

my %bullets = (
	"\x6F" => 'o',
	"\xEF\x81\xB6" => '::',	# Diamond
	"\xEF\x82\xA7" => '#',	# Small Black Square
	"\xEF\x82\xB7" => '*',	# Small Black Circle
	"\xEF\x83\x98" => '>',	# Arrowhead
	"\xEF\x83\xBC" => '+'	# Right Sign
);

my %NFList = (
	"bullet"	  => \&bullet,
	"decimal"	  => \&decimal,
	"lowerLetter" => \&lowerLetter,
	"upperLetter" => \&upperLetter,
	"lowerRoman"  => \&lowerRoman,
	"upperRoman"  => \&upperRoman
);


sub new {
	my ($proto) = @_;
	my $class = ref($proto) || $proto;
	my $self  = {};
	bless ($self, $class);
	return $self;
    }

sub ShowHyperlinks {
	my ($self) = @_;
	$config_showHyperLink = "y";
	}

sub DoNotShowHyperlinks {
	my ($self) = @_;
	$config_showHyperLink = "n";
	}

sub ShowListNumbering {
	my ($self) = @_;
	$config_showListNumbering = "y";
	}

sub DoNotShowListNumbering {
	my ($self) = @_;
	$config_showListNumbering = "n";
	}

# Extract xml document content from argument docx file/directory.
sub Contents {
	my ($self, $filePath) = @_;
	my $content = '';
	
	# Extract xml document content from argument docx file.
	if ($using7zip)
		{
		# 7-zip version
    	$content = `"$config_unzip" e "$filePath" word/document.xml -so 2>$nulldevice`;
		}
	else
		{
		# unzip version:
		$content = `"$config_unzip" -p "$filePath" word/document.xml 2>$nulldevice`;
		}
	
	# Gather information about header, footer, hyperlinks, images, footnotes etc.
	if ($using7zip)
		{
		# 7-zip version:
    	$_ = `"$config_unzip" e "$filePath" word/_rels/document.xml.rels -so 2>$nulldevice`;
		}
	else
		{
		# unzip version:
		$_ = `"$config_unzip" -p "$filePath" word/_rels/document.xml.rels 2>$nulldevice`;
		}
	
	my %docurels;
	while (/<Relationship Id="(.*?)" Type=".*?\/([^\/]*?)" Target="(.*?)"( .*?)?\/>/g)
		{
		$docurels{"$2:$1"} = $3;
		}
	
	# Gather list numbering information.
	$_ = "";
	my %abstractNum;
	my @N2ANId = ();
	if ($config_showListNumbering eq "y")
		{
			if ($using7zip)
				{
				$_ = `"$config_unzip" e "$filePath" word/numbering.xml -so 2>$nulldevice`;
				}
			else
				{
				#$_ = `$unzip_cmd "$ARGV[0]" word/numbering.xml 2>$nullDevice`;
				$_ = `"$config_unzip" -p "$filePath" word/numbering.xml 2>$nulldevice`;
				}
			
			
			
			if ($_) {
		#		while (/<w:abstractNum w:abstractNumId="(\d+)">(.*?)<\/w:abstractNum>/g)
				while (/<w:abstractNum w:abstractNumId="(\d+)"[^>]*>(.*?)<\/w:abstractNum>/g)
				{
					my $abstractNumId = $1;
					my $temp = $2;
			
				while ($temp =~ /<w:lvl w:ilvl="(\d+)"[^>]*><w:start w:val="(\d+)"[^>]*><w:numFmt w:val="(.*?)"[^>]*>.*?<w:lvlText w:val="(.*?)"[^>]*>.*?<w:ind w:left="(\d+)" w:hanging="(\d+)"[^>]*>/g )
					{
						# $2: Start $3: NumFmt, $4: LvlText, ($5,$6): (Indent (twips), hanging)
						
						@{$abstractNum{"$abstractNumId:$1"}} = (
							$NFList{$3},
							$4,
							$2,
							int ((($5-$6) / $config_twipsPerChar) + 0.5),
							$5
						);
					}
				}
			
				while ( /<w:num w:numId="(\d+)"><w:abstractNumId w:val="(\d+)"/g )
				{
					$N2ANId[$1] = $2;
				}
			}
		}

	#
	# Text extraction starts.
	#
	
	my %tag2chr = (tab => "\t", noBreakHyphen => "-", softHyphen => " - ");
	
	$content =~ s/<?xml .*?\?>(\r)?\n//;
	
	$content =~ s{<(wp14|wp):[^>]*>.*?</\1:[^>]*>}||og;
	
	# Remove the field instructions (instrText) and data (fldData), and deleted
	# text.
	$content =~ s{<w:(instrText|fldData|delText)[^>]*>.*?</w:\1>}||ogs;
	
	# Mark cross-reference superscripting within [...].
	$content =~ s|<w:vertAlign w:val="superscript"/></w:rPr><w:t>(.*?)</w:t>|[$1]|og;
	
	$content =~ s{<w:(tab|noBreakHyphen|softHyphen)/>}|$tag2chr{$1}|og;
	
	my $hr = '-' x $config_lineWidth . $config_newLine;
	$content =~ s|<w:pBdr>.*?</w:pBdr>|$hr|og;
	
	$content =~ s{<w:caps/>.*?(<w:t>|<w:t [^>]+>)(.*?)</w:t>}/uc $2/oge;
	
	$content =~ s{<w:hyperlink r:id="(.*?)".*?>(.*?)</w:hyperlink>}/hyperlink($1,$2, \%docurels)/oge;
	
	$content =~ s|<w:numPr><w:ilvl w:val="(\d+)"/><w:numId w:val="(\d+)"\/>|listNumbering($2,$1, \%abstractNum, \@N2ANId)|oge;
	
	$content =~ s{<w:ind w:(left|firstLine)="(\d+)"( w:hanging="(\d+)")?[^>]*>}|' ' x int((($2-$4)/$config_twipsPerChar)+0.5)|oge;
	
	$content =~ s{<w:p [^/>]+?/>|<w:br/>}|$config_newLine|og;
	
	$content =~ s/<w:p[^>]+?>(.*?)<\/w:p>/processParagraph($1)/ogse;
	
	$content =~ s/<.*?>//og;
	
	
	#
	# Convert non-ASCII characters/character sequences to ASCII characters.
	#
	
	$content =~ s/(\xC2|\xC3|\xCF|\xE2.|\xEF.)(.)/($splchars{$1}{$2} ? $splchars{$1}{$2} : $1.$2)/oge;
	
	#
	# Convert docx specific (reserved HTML/XHTML) escape characters.
	#
	$content =~ s/(&)(amp|apos|gt|lt|quot)(;)/$escChrs{lc $2}/iog;
	
	return($content);
	}

#
# Subroutines for center and right justification of text in a line.
#

sub justify {
	my $len = length $_[1];

	if ($_[0] eq "center" && $len < ($config_lineWidth - 1)) {
		return ' ' x (($config_lineWidth - $len) / 2) . $_[1];
	} elsif ($_[0] eq "right" && $len < $config_lineWidth) {
		return ' ' x ($config_lineWidth - $len) . $_[1];
	} else {
		return $_[1];
	}
}

#
# Subroutines for dealing with embedded links and images
#

sub hyperlink {
    my $hlrid = $_[0];
    my $hltext = $_[1];
    my $docuerlsR = $_[2];
    my $hlink = $docuerlsR->{"hyperlink:$hlrid"};

	$hltext =~ s/<[^>]*?>//og;
	#$hltext .= " [HYPERLINK: $hlink]" if (lc $config_showHyperLink eq "y" && $hltext ne $hlink);
	$hltext .= " [$hlink]" if (lc $config_showHyperLink eq "y" && $hltext ne $hlink);

	return $hltext;
}

#
# Subroutines for processing paragraph content.
#

sub processParagraph {
    my $para = $_[0] . "$config_newLine";
    my $align = $1 if ($_[0] =~ /<w:jc w:val="([^"]*?)"\/>/);

    $para =~ s/<.*?>//og;
    return justify($align,$para) if $align;

    return $para;
}

#
# Subroutines for processing numbering information.
#

sub lowerRoman {
	return $RomanNumbers[$_[0]] if ($_[0] < @RomanNumbers);

	my @rcode = ("i", "iv", "v", "ix", "x", "xl", "l", "xc", "c", "cd", "d", "cm", "m");
	my @dval = (1, 4, 5, 9, 10, 40, 50, 90, 100, 400, 500, 900, 1000);

	my $roman = "";
	my $num = $_[0];

	my $div;
	my $i = (@rcode - 1);
	while ($num > 0) {
		$i-- while ($num < $dval[$i]);
		$div = $num / $dval[$i];
		$num = $num % $dval[$i];
		$roman .= $rcode[$i] x $div;
	}

	return $roman;
}

sub upperRoman {
	return uc lowerRoman(@_);
}


sub lowerLetter {
	my @Alphabets = split '' , "abcdefghijklmnopqrstuvwxyz";
	return $Alphabets[($_[0] % 26) - 1] x (($_[0] - 1)/26 + 1);
}

sub upperLetter {
	return uc lowerLetter(@_);
}


sub decimal {
	return $_[0];
}

sub bullet {
	return $bullets{$_[0]} ? $bullets{$_[0]} : 'oo';
}

my @lastCnt = (0);
my @twipStack = (0);
my @keyStack = (undef);
my $ssiz = 1;

sub listNumbering {
	my $abstractNumH = $_[2];
	my $N2ANIdA = $_[3];
	#my $aref = \@{$abstractNum{"$N2ANId[$_[0]]:$_[1]"}};
	my $aref = \@{$abstractNumH->{"$N2ANIdA->[$_[0]]:$_[1]"}};
	my $lvlText;

	if ($aref->[0] != \&bullet) {
		#my $key = "$N2ANId[$_[0]]:$_[1]";
		my $key = "$N2ANIdA->[$_[0]]:$_[1]";
		my $ccnt;

		if ($aref->[4] < $twipStack[$ssiz-1]) {
			while ($twipStack[$ssiz-1] > $aref->[4]) {
				pop @twipStack;
				pop @keyStack;
				pop @lastCnt;
				$ssiz--;
			}
		}

		if ($aref->[4] == $twipStack[$ssiz-1]) {
			if ($key eq $keyStack[$ssiz-1]) {
				++$lastCnt[$ssiz-1];
			}
			else {
				$keyStack[$ssiz-1] = $key;
				$lastCnt[$ssiz-1] = $aref->[2];
			}
		}
		elsif ($aref->[4] > $twipStack[$ssiz-1]) {
			push @twipStack, $aref->[4];
			push @keyStack, $key;
			push @lastCnt, $aref->[2];
			$ssiz++;
		}

		$ccnt = $lastCnt[$ssiz-1];

		$lvlText = $aref->[1];
		$lvlText =~ s/%\d([^%]*)$/($aref->[0]->($ccnt)).$1/oe;

		my $i = $ssiz - 2;
		$i-- while ($lvlText =~ s/%\d([^%]*)$/$lastCnt[$i]$1/o);
	}
	else {
		$lvlText = $aref->[0]->($aref->[1]);
	}

	return ' ' x $aref->[3] . $lvlText . ' ';
}

1;
