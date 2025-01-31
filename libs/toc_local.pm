# toc_local.pm: generate a Table of Contents for a source file.
#
# perl -c C:\perlprogs\IntraMine\libs\toc_local.pm

package toc_local;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use utf8;
use Encode;
use Encode::Guess;
use HTML::Entities;
use URI::Escape;
use Text::Tabs;
$tabstop = 4;
use Syntax::Highlight::Perl::Improved ':BASIC';  # ':BASIC' or ':FULL' - FULL
use Time::HiRes qw ( time );
use Win32::Process; # for calling Universal ctags.exe
use JSON::MaybeXS qw(encode_json);
use Text::MultiMarkdown; # for .md files
use Path::Tiny qw(path);
use Pod::Simple::HTML;
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use win_wide_filepaths;
use ext; # for ext.pm#IsTextExtensionNoPeriod() etc.
use cobol_keywords;
use ex_ctags;

# Circled letters, used in tables of contents.
my $C_icon = '<span class="circle_green">C</span>'; 	# Class
my $S_icon = '<span class="circle_green">S</span>';		# Struct
my $M_icon = '<span class="circle_green">M</span>';		# Module
my $T_icon = '<span class="circle_blue">T</span>';		# Type
my $D_icon = '<span class="circle_blue">D</span>';		# Data
my $m_icon = '<span class="circle_red">m</span>';		# method
my $f_icon = '<span class="circle_red">f</span>';		# function
my $s_icon = '<span class="circle_red">s</span>';		# subroutine

my $HashHeadingRequireBlankBefore;

sub InitTocLocal {
	my ($firstPartOfPath, $portListen, $logDir, $ctags_dir, $hashHeadingRequireBlankBefore) = @_;
	$HashHeadingRequireBlankBefore = $hashHeadingRequireBlankBefore;
	InitExCtags($firstPartOfPath, $portListen, $logDir, $ctags_dir);
}

sub IsSupportedByExuberantCTags {
	my ($filePath) = @_;
	return(IsSupportedByCTags($filePath));
	}

# 1 if Table Of Contents is supported, else 0;
sub CanHaveTOC {
	my ($filePath) = @_;
	my $result = 0;

	if ( $filePath =~ m!\.(p[lm]|cgi|t)$!i
	  || $filePath =~ m!\.pod$!i
	  || $filePath =~ m!\.(txt|log|bat)$!i
	  || $filePath =~ m!\.go$!i
	  || $filePath =~ m!\.(f|f77|f90|f95|f03|for)$!i
	  || $filePath =~ m!\.(cob|cpy|cbl)$!i
	  || $filePath =~ m!\.(bas|cls|ctl|frm|vbs|vba|vb)$!i
	  || $filePath =~ m!\.css$!i
	  || IsSupportedByCTags($filePath) )
		{
		$result = 1;
		}
	
	return($result);
	}

# GetCMToc: Get Table of Contents Etc for a source file.
# => $filePath
# <= $toc_R: the Table of Contents
sub GetCMToc {
	my ($filePath, $toc_R) = @_;
	$$toc_R = '';

	# Processing depends on the file extension, most are handled by
	# universal CTags but some are custom.
	# Note not all extensions are supported, eg .pdf, .docx. Only extensions
	# that can be edited with CodeMirror are here. Some, such as .md,
	# can be edited with CM but don't support a Table of Contents.
	
	# (Numbers below are from intramine_viewer.pl#GetContentBasedOnExtension)
	# 2. pure custom with TOC: pl, pm, pod, txt, log, bat, cgi, t.
	if ($filePath =~ m!\.(p[lm]|cgi|t)$!i)
		{
		GetPerlTOC($filePath, $toc_R);
		}
	elsif ($filePath =~ m!\.pod$!i)
		{
		GetPodTOC($filePath, $toc_R);
		}
	elsif ($filePath =~ m!\.(txt|log|bat)$!i)
		{
		GetTextTOC($filePath, $toc_R);
		}
	# 3.1 go: CodeMirror for the main view with a custom Table of Contents
	elsif ($filePath =~ m!\.go$!i)
		{
		GetGoTOC($filePath, $toc_R);
		}
	# 3.2 CM with TOC, ctag support: cpp, js, etc, and now including .css
	elsif ($filePath =~ m!\.(f|f77|f90|f95|f03|for)$!i)
		{
		my $textContents = GetHtmlEncodedTextFile($filePath);
		if ($textContents ne '')
			{
			GetFortranTOC(\$textContents, $toc_R);
			}
		}
	# 3.1 cont'd, COBOL: CM for main view, custom TOC
	elsif ($filePath =~ m!\.(cob|cpy|cbl)$!i)
		{
		my $textContents = GetHtmlEncodedTextFile($filePath);
		if ($textContents ne '')
			{
			GetCOBOLTOC(\$textContents, $toc_R);
			}
		}
	# 3.1 cont'd, Visual Basic: CM for main view, custom TOC
	# NOTE at present only .vb and .vbs are supported.
	elsif ($filePath =~ m!\.(bas|cls|ctl|frm|vbs|vba|vb)$!i)
		{
		my $textContents = GetHtmlEncodedTextFile($filePath);
		if ($textContents ne '')
			{
			GetVBTOC(\$textContents, $toc_R);
			}
		}
	elsif ($filePath =~ m!\.css$!i)
		{
		# CSS is special, can have multiple entries per line.
		GetCssCTagsTOCForFile($filePath, $toc_R);
		}
	elsif (IsSupportedByCTags($filePath))
		{
		GetCTagsTOCForFile($filePath, $toc_R);
		}
	# 4. CM, no TOC: textile, out, other uncommon formats not supported by ctags.
	else
		{
		# TEST ONLY
		#print("NOT SUPPORTED\n");
		}
	}

# Get text file as a big string. Returns 1 if successful, 0 on failure.
sub LoadTextFileContents {
	my ($filePath, $contentsR, $octetsR) = @_;
	
	$$octetsR = ReadTextFileWide($filePath);
	if (!defined($$octetsR))
		{
		$$contentsR .= "Error, could not open $filePath.";
		return(0);
		}
	my $decoder = Encode::Guess->guess($$octetsR);
	
	my $eightyeightFired = 0;
	if (ref($decoder))
		{
		my $decoderName = $decoder->name();
		if ($decoderName =~ m!iso-8859-\d+!)
			{
			$$octetsR = $decoder->decode($$octetsR);
			$eightyeightFired = 1;
			}
		}
	
	if (!$eightyeightFired)
		{
		$$octetsR = decode_utf8($$octetsR);
		}
	
	return(1);
	}

sub GetHtmlEncodedTextFile {
	my ($filePath) = @_;
	my $result = '';
	
	if (FileOrDirExistsWide($filePath) != 1)
	#if (!(-f $filePath))
		{
		return('');
		}
	else
		{
		return(GetHtmlEncodedTextFileWide($filePath));
		}
	}

# Sort line numbers, first stripping any initial 'a'.
sub LineNumComp {
	my ($numA, $numB) = @_;
	if (index($numA, 'a') == 0)
		{
		$numA = substr($numA, 1);
		}
	if (index($numB, 'a') == 0)
		{
		$numB = substr($numB, 1);
		}
	
	return($numA <=> $numB);
	}

sub UniqueTocID {
	my ($id, $idExists_H) = @_;

	my $idBump = 2;
	my $idBase = $id;
	while ($id eq '' || defined($idExists_H->{$id}))
		{
		$id = $idBase . $idBump;
		++$idBump;
		}
	$idExists_H->{$id} = 1;

	return($id);
	}

use ExportAbove;

sub GetPodTOC {
	my ($filePath, $toc_R) = @_;
	my $contents;
	my $octets;
	if (!LoadTextFileContents($filePath, \$contents, \$octets))
		{
		return;
		}

	my @lines = split(/\n/, $octets);
	my @jumpList;
	my $lineNum = 1;
	my %sectionIdExists; # used to avoid duplicated anchor id's for sections.
	my $numLines = @lines;

	for (my $i = 0; $i < $numLines; ++$i)
		{
		if ($lines[$i] =~ m!^=head(\d)\s+(.+)$!i)
			{
			my $level = $1;
			my $headerProper = $2;

			if ($i > 0)
				{
				++$level; # head 1 becomes h2, head2 becomes h3
				}

			my ($jumperHeader, $id) = GetTextJumperHeaderAndId($headerProper, \@jumpList, \%sectionIdExists);
			my $contentsClass = 'h' . $level;

			my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			my $jlEnd = "</a></li>";
			push @jumpList, $jlStart . $jumperHeader . $jlEnd;
			}
		++$lineNum;
		}
	
	$$toc_R = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n"  . join("\n", @jumpList) . "</ul>\n";
	}

sub GetTextTOC {
	my ($filePath, $toc_R) = @_;
	my $contents;
	my $octets;
	if (!LoadTextFileContents($filePath, \$contents, \$octets))
		{
		return;
		}

	my @lines = split(/\n/, $octets);

	my @jumpList;
	my $lineNum = 1;
	my %sectionIdExists; # used to avoid duplicated anchor id's for sections.
	my $justDidHeadingOrHr = 0;
	my $numLines = @lines;

	my $allowOctothorpeHeadings = 1; 	# Whether to do ## Markdown headings
	my $numOctos = 0;					# Too many means probably not headings
	my $lineIsBlank = 1;
	my $lineBeforeIsBlank = 1; 			# Initally there is no line before, so it's kinda blank:)
	my $linesToCheck = 20;				
	my $hasSameHashesInARow = 0;		# Consecutive # or ## etc means not headings
	my $previousHashesCount = 0;
	my $insideCodeBlock = 0;			# 1 == inside CODE/ENDCODE block
	if ($linesToCheck > $numLines)
		{
		$linesToCheck = $numLines;
		}
	if ($linesToCheck)
		{
		for (my $i = 0; $i < $linesToCheck; ++$i)
			{
			if (index($lines[$i], '#') == 0)
				{
				++$numOctos;
				$lines[$i] =~ m!^(#+)!;
				my $startHashes = $1;
				my $currentHashesCount = length($startHashes);
				if ($currentHashesCount == $previousHashesCount)
					{
					$hasSameHashesInARow = 1;
					}
				$previousHashesCount = $currentHashesCount;
				}
			else
				{
				$previousHashesCount = 0;
				}
			}
		my $headingRatio = $numOctos / ($linesToCheck + 0.0);
		# .25 is admittedly somewhat arbitrary and untested.
		if ($headingRatio > .25 || $hasSameHashesInARow)
			{
			$allowOctothorpeHeadings = 0;
			}
		}

	for (my $i = 0; $i < $numLines; ++$i)
		{
		$lineBeforeIsBlank = $lineIsBlank;
		if ($lines[$i] eq '')
			{
			$lineIsBlank = 1;
			}
		else
			{
			$lineIsBlank = 0;
			}

		if ($lines[$i] eq 'CODE')
			{
			$insideCodeBlock = 1;
			$justDidHeadingOrHr = 0;
			}
		elsif ($lines[$i] eq 'ENDCODE')
			{
			$insideCodeBlock = 0; 
			}

		if (!$insideCodeBlock)
			{
			# Hashed heading eg ## Heading. Require blank line before # heading
			# (or first line).
			if ( $allowOctothorpeHeadings && $lines[$i] =~ m!^#+\s+!
				&& ($lineBeforeIsBlank || !$HashHeadingRequireBlankBefore) )
				{
				NoteTextHeading(\$lines[$i], undef, undef, \@jumpList, $i, \%sectionIdExists);
				$justDidHeadingOrHr = 1;
				}
			# Underlines -> hr or heading. Heading requires altering line before underline.
			elsif ($i > 0 && $lines[$i] =~ m!^[=~-][=~-][=~-]([=~-]+)$!)
				{
				my $underline = $1;
				if ($justDidHeadingOrHr == 0) # a heading - put in anchor and add to jump list too
					{
					NoteTextHeading(\$lines[$i], \$lines[$i-1], $underline, \@jumpList, $i, \%sectionIdExists);
					}
				$justDidHeadingOrHr = 1;
				}
			else
				{
				$justDidHeadingOrHr = 0;
				}
			}

		++$lineNum;
		}

	$$toc_R = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n"  . join("\n", @jumpList) . "</ul>\n";
	}

# Pick up hashtag and underlined headings, make up <li>...goToAnchor(...)</li> entries for them.
sub NoteTextHeading {
	my ($lineR, $lineBeforeR, $underline, $jumpListA, $i, $sectionIdExistsH) = @_;

	# Use text of header for anchor id if possible.
	my $isHashedHeader = 0; #  ### header vs underlined header
	my $beforeHeader = '';
	my $headerProper = '';
	my $afterHeader = '';
	my $headerLevel = 0;
	# ### style heading, heading is on $lineR.
	if ($$lineR =~ m!^(#.+)$!)
		{
		$isHashedHeader = 1;
		$beforeHeader = '';
		my $rawHeader = $1;
		$afterHeader = '';
		$rawHeader =~ m!^(#+)!;
		my $hashes = $1;
		$headerLevel = length($hashes);
		if ($i <= 1) # right at the top of the document, assume it's a document title <h1>
			{
			$headerLevel = 1;
			}
		$rawHeader =~ s!^#+\s+!!;
		$headerProper = $rawHeader;
		}
	# Underlined heading, heading is on $lineBeforeR.
	elsif ($$lineBeforeR ne '')
	#elsif ($$lineBeforeR =~ m!^(<tr id='R\d+'><td[^>]+></td><td>)(.*?)(</td></tr>)$!)
		{
		#$beforeHeader = $1;
		$headerProper = $$lineBeforeR;
		#$afterHeader = $3;
		if (substr($underline,0,1) eq '=')
			{
			$headerLevel = 2;
			}
		elsif (substr($underline,0,1) eq '-')
			{
			$headerLevel = 3;
			}
		elsif (substr($underline,0,1) eq '~')
			{
			$headerLevel = 4;
			}
		if ($i == 1) # right at the top of the document, assume it's a document title <h1>
			{
			$headerLevel = 1;
			}
		}

	if (!defined($headerProper) || $headerProper eq '')
		{
		return;
		}

	my ($jumperHeader, $id) = GetTextJumperHeaderAndId($headerProper, $jumpListA, $sectionIdExistsH);
	my $contentsClass = 'h' . $headerLevel;

	my $lineNum = $i; # + 1;
	if ($isHashedHeader)
		{
		$lineNum += 1;
		}
	my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
	my $jlEnd = "</a></li>";
	push @$jumpListA, $jlStart . $jumperHeader . $jlEnd;

	# my $jlStart = "<li class='$contentsClass' im-text-ln='$i'><a href='#$id'>";
	# my $jlEnd = "</a></li>";
	# push @$jumpListA, $jlStart . $jumperHeader . $jlEnd;
	}

# $jumperHeader is $headerProper (orginal header text) with HTML etc removed.
# $id also has unicode etc removed, and is forced to be unique.
sub GetTextJumperHeaderAndId {
	my ($headerProper, $jumpListA, $sectionIdExistsH) = @_;

	my $id = $headerProper;
	# Remove leading white from header, it looks better.
	$headerProper =~ s!^\s+!!;
	$headerProper =~ s!^&nbsp;!!g;
	# A minor nuisance, we have span, strong, em wrapped around some or all of the header, get rid of that in the id.
	# And thanks to links just being added, also remove <a ...> and </a> and <img ...>.
	# Rev, remove from both TOC entry and id.
	$id =~ s!<[^>]+>!!g;
	$id =~ s!^\s+!!;
	$id =~ s!\s+$!!;
	$id =~ s!\t+! !g;
	my $jumperHeader = $id;				
	$id =~ s!\s+!_!g;
	# File links can have &nbsp; Strip any leading ones, and convert the rest to _.
	$id =~ s!^&nbsp;!!;
	$id =~ s!&nbsp;!_!g;
	$id =~ s!_+$!!;
	# Quotes don't help either.
	$id =~ s!['"]!!g;
	# Remove unicode symbols from $id, especially the ones inserted by markdown above, to make
	# it easier to type the headers in links. Eg 'server swarm.txt#TODO_List' for header '&#127895;TODO List'.
	$id =~ s!\&#\d+;!!g; # eg &#9755;

	if ($id eq '' || defined($sectionIdExistsH->{$id}))
		{
		my $anchorNumber = @$jumpListA;
		$id = "hdr_$anchorNumber";
		}
	$sectionIdExistsH->{$id} = 1;

	return($jumperHeader, $id);
	}

sub GetPerlTOC {
	my ($filePath, $toc_R) = @_;
	my $contents;
	my $octets;
	if (!LoadTextFileContents($filePath, \$contents, \$octets))
		{
		return;
		}

	my @lines = split(/\n/, $octets);

	my @jumpList;
	my @subNames;
	my @sectionList;
	my @sectionNames;
	my $lineNum = 1;
	my %sectionIdExists; # used to avoid duplicated anchor id's for sections.
	my $numLines = @lines;
	my $jlEnd = "</a></li>";

	for (my $i = 0; $i < $numLines; ++$i)
		{
		if ($lines[$i] =~ m!^\s*sub\s*(\w+)!)
			{
			my $subName = $1;
			push @subNames, $subName;
			my $anchorLineNum = $i;
			my $numCommentLines = 0;
			while ($anchorLineNum >= 0
			  && index($lines[$anchorLineNum - $numCommentLines - 1], '#') == 0)
				{
				++$numCommentLines;
				}
			$anchorLineNum -= $numCommentLines;
			++$anchorLineNum;
			my $jlStart = "<li class='h2'><a onmousedown='goToAnchor(\"$subName\", $lineNum);'>";
			push @jumpList, $jlStart . $s_icon . $subName . $jlEnd;
			}
		elsif ($lines[$i] =~ m!^{\s*##+\s+(.+)$!)
			{
			my $sectionName = $1;
			my $id = $sectionName;
			$id =~ s!\s+!_!g;
			if (defined($sectionIdExists{$id}))
				{
				my $anchorNumber = @sectionList;
				$id = "hdr_$anchorNumber";
				}
			$sectionIdExists{$id} = 1;
			my $jlStart = "<li class='h2'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			push @sectionList, $jlStart . $S_icon . $sectionName . $jlEnd;
			push @sectionNames, $sectionName;
			}
		++$lineNum;
		}
	
	my @idx = sort { $subNames[$a] cmp $subNames[$b] } 0 .. $#subNames;
	@jumpList = @jumpList[@idx];
	@idx = sort { $sectionNames[$a] cmp $sectionNames[$b] } 0 .. $#sectionNames;
	@sectionList = @sectionList[@idx];
	my $numSectionEntries = @sectionList;
	my $sectionBreak = ($numSectionEntries > 0) ? '<br>': '';

	$$toc_R = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n" . join("\n", @sectionList) . $sectionBreak . join("\n", @jumpList) . "</ul>\n";
	}

sub GetGoTOC {
	my ($filePath, $toc_R) = @_;

	my $contents;
	my $octets;
	if (!LoadTextFileContents($filePath, \$contents, \$octets))
		{
		return;
		}

	my @lines = split(/\n/, $octets);
	my @classList;
	my @classNames;
	my @methodList;
	my @methodNames;
	my %idExists; # used to avoid duplicated anchor id's.

	my $numLines = @lines;
	my $lineNum = 1;
	for (my $i = 0; $i < $numLines; ++$i)
		{
		# Put structs in jumplist.
		# type parser struct {
		if ($lines[$i] =~ m!^\s*type\s*(\w+)\s*struct! )
			{
			my $className = $1;
			my $contentsClass = 'h2';
			my $id = $className;
			$id =~ s!\s+!_!g;
			$id = UniqueTocID($id, \%idExists);
			my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			my $jlEnd = "</a></li>";
			push @classList, $jlStart . $S_icon . $className . $jlEnd;
			push @classNames, $className;
			}
		# and functions:
		# func (p *parser) init(
		# func trace(
		elsif ( $lines[$i] =~ m!^\s*func\s+\([^)]+\)\s*(\w+)\s*\(!
			||  $lines[$i] =~ m!^\s*func\s+(\w+)\s*\(! )
			{
			my $rawName = $1;
			# Avoid keywords
			if ($rawName !~ m!^(if|do|for|while|else|elsif|switch)$!)
				{
				my $methodName = $rawName;
				my $contentsClass = 'h2';
				my $id = $methodName;
				$id =~ s!\s+!_!g;
				$id = UniqueTocID($id, \%idExists);
				my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
				my $jlEnd = "</a></li>";
				push @methodList, $jlStart . $f_icon . $methodName . '()' . $jlEnd;
				push @methodNames, $methodName;
				}
			}

		++$lineNum;
		}

	my @idx = sort { $classNames[$a] cmp $classNames[$b] } 0 .. $#classNames;
	@classList = @classList[@idx];
	@idx = sort { $methodNames[$a] cmp $methodNames[$b] } 0 .. $#methodNames;
	@methodList = @methodList[@idx];
	my $numClassListEntries = @classList;
	my $classBreak = ($numClassListEntries > 0) ? '<br>': '';

	$$toc_R = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n" . join("\n", @classList) . $classBreak . join("\n", @methodList) . "</ul>\n";
	}

# Ctags handling, for CSS files. There can be multiple entries per line, and tag can be
# somewhat modified for use as an anchor.
sub GetCssCTagsTOCForFile {
	my ($filePath, $tocR) = @_;
	my $dir = lc(DirectoryFromPathTS($filePath));
	my $fileName = FileNameFromPath($filePath);
	my $contentsClass = 'h2';

	# First, get ctags for the file
	my $errorMsg = '';
	my ($ctagsFilePath, $tempFilePath) = MakeCtagsForFile($dir, $fileName, \$errorMsg);
	if ($ctagsFilePath eq '' || length($errorMsg) > 0)
		{
		$$tocR = "<strong>$errorMsg</strong>\n";
		return;
		}
	my %tagEntryForLine;
	my %tagDisplayedNameForLine;
	$fileName = lc($fileName);
	my $itemCount = LoadCssCtags($ctagsFilePath, $fileName,
								\%tagEntryForLine,
								\%tagDisplayedNameForLine,
								\$errorMsg);
	if ($errorMsg ne '')
		{
		$$tocR = "<strong>$errorMsg</strong>\n";
		return;
		}
	
	my @anchorList;
	my @displayedTagNames;
	my %idExists; # used to avoid duplicated anchor id's.
	my $jlEnd = "</a></li>";
	foreach my $lineNum (keys %tagEntryForLine)
		{
		my $tag = $tagEntryForLine{$lineNum};
		my $displayedTag = $tagDisplayedNameForLine{$lineNum};
		if (index($tag, "|") > 0) # multiple entries for line
			{
			my @tags = split(/\|/, $tag);
			my @displayedtags = split(/\|/, $displayedTag);
			for (my $j = 0; $j < @tags; ++$j)
				{
				$tag = $tags[$j];
				$displayedTag = $displayedtags[$j];
				my $id = $tag;
				if (!defined($idExists{$id}))
					{
					my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
					my $jlEnd = "</a></li>";
					push @anchorList, $jlStart . $displayedTag . $jlEnd;
					push @displayedTagNames, $displayedTag;
					}
				$idExists{$id} = 1;
				}
			}
		else # single entry for line
			{
			my $id = $tag;
			if (!defined($idExists{$id}))
				{
				my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
				my $jlEnd = "</a></li>";
				push @anchorList, $jlStart . $displayedTag . $jlEnd;
				push @displayedTagNames, $displayedTag;
				}
			$idExists{$id} = 1;
			}
		}
	
	my @idx = sort { $displayedTagNames[$a] cmp $displayedTagNames[$b] } 0 .. $#displayedTagNames;
	@anchorList = @anchorList[@idx];
	$$tocR = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n" .
				join("\n", @anchorList) . "</ul>\n";

	# Get rid of the one or two temp files made while getting ctags.
	unlink($ctagsFilePath);
	if ($tempFilePath ne '')
		{
		unlink($tempFilePath);
		}
	}

# Use ctags to generate a Table Of Contents (TOC) for a source file. Ctags are written to
# a temp file and then read back in, a bit clumsy but it works.
sub GetCTagsTOCForFile {
	my ($filePath, $tocR) = @_;
	my $dir = lc(DirectoryFromPathTS($filePath));
	my $fileName = FileNameFromPath($filePath);

	# First, get ctags for the file
	my $errorMsg = '';
	my ($ctagsFilePath, $tempFilePath) = MakeCtagsForFile($dir, $fileName, \$errorMsg);
	if ($ctagsFilePath eq '' || length($errorMsg) > 0)
		{
		$$tocR = "<strong>$errorMsg</strong>\n";
		return;
		}
	my %classEntryForLine;
	my %structEntryForLine;
	my %methodEntryForLine;
	my %functionEntryForLine;
	my $itemCount = LoadCtags($filePath, $ctagsFilePath,
						\%classEntryForLine,
						\%structEntryForLine, \%methodEntryForLine,
						\%functionEntryForLine, \$errorMsg);
	if ($errorMsg ne '')
		{
		$$tocR = "<strong>$errorMsg</strong>\n";
		return;
		}
	
	my @classList;
	my @classNames;
	my @structList;
	my @structNames;
	my @methodList;
	my @methodNames;
	my @functionList;
	my @functionNames;
	my %idExists; # used to avoid duplicated anchor id's.
	my $jlEnd = "</a></li>";
	
	foreach my $lineNum (sort {$a <=> $b} keys %structEntryForLine)
		{
		my $className = $structEntryForLine{$lineNum};
		my $contentsClass = 'h2';
		my $id = $className;
		$id =~ s!\s+!_!g;
		$id = UniqueTocID($id, \%idExists);
		my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
		push @structList, $jlStart . $S_icon . $className . $jlEnd;
		push @structNames, $className;
		}

	# LineNumComp() strips any initial 'a' from line numbers
	# before sorting numerically.
	foreach my $lineNum (sort { LineNumComp($a, $b) } keys %classEntryForLine)
	# foreach my $lineNum (sort {$a <=> $b} keys %classEntryForLine)
		{
		my $className = $classEntryForLine{$lineNum};
		my $contentsClass = (index($className, ':') > 0) ? 'h3' : 'h2';
		# And also h3 if entry contains '#' indicating a method (eg Java).
		if (index($className, '#') > 0)
			{
			$contentsClass = 'h3';
			}
		my $id = $className;
		$id =~ s!\s+!_!g;
		$id = UniqueTocID($id, \%idExists);
		
		# As a special case, if $lineNum starts with a letter then the
		# entry is shown "disabled" (gray) and there is no functioning link.
		# (Needed eg for Julia, see LoadJuliaTags()).
		my $jlStart;
		if ($lineNum =~ m!^[a-zA-Z]!)
			{
			$jlStart = "<li class='h2Disabled'><a>";
			#$jlStart = "<li class='h2Disabled'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			}
		else
			{
			$jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			}
		push @classList, $jlStart . $C_icon . $className . $jlEnd;
		push @classNames, $className;
		}
		
	foreach my $lineNum (sort {$a <=> $b} keys %methodEntryForLine)
		{
		my $methodName = $methodEntryForLine{$lineNum};
		my $contentsClass = 'h2';
		my $id = $methodName;
		$id =~ s!\s+!_!g;
		$id = UniqueTocID($id, \%idExists);
		my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
		push @methodList, $jlStart . $m_icon . $methodName . '()' . $jlEnd;
		push @methodNames, $methodName;
		}

	foreach my $lineNum (sort {$a <=> $b} keys %functionEntryForLine)
		{
		my $methodName = $functionEntryForLine{$lineNum};
		my $contentsClass = 'h2';
		my $id = $methodName;
		$id =~ s!\s+!_!g;
		$id = UniqueTocID($id, \%idExists);
		my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
		push @functionList, $jlStart . $f_icon . $methodName . '()' . $jlEnd;
		push @functionNames, $methodName;
		}

	my $numStructs = @structList;
	my $numClasses = @classList;
	my $numMethods = @methodList;
	my $numFunctions = @functionList;
	my @idx;
	
	if ($numStructs)
		{
		@idx = sort { $structNames[$a] cmp $structNames[$b] } 0 .. $#structNames;
		@structList = @structList[@idx];
		}
	if ($numClasses)
		{
		@idx = sort { $classNames[$a] cmp $classNames[$b] } 0 .. $#classNames;
		@classList = @classList[@idx];
		}
	if ($numMethods)
		{
		@idx = sort { $methodNames[$a] cmp $methodNames[$b] } 0 .. $#methodNames;
		@methodList = @methodList[@idx];
		}
	if ($numFunctions)
		{
		@idx = sort { $functionNames[$a] cmp $functionNames[$b] } 0 .. $#functionNames;
		@functionList = @functionList[@idx];
		}
	
	my $numClassListEntries = @classList;
	my $typeBreak = ($numClassListEntries > 0) ? '<br>': '';
	$$tocR = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n";
	if ($numStructs)
		{
		my $structString = join("\n", @structList);
		$$tocR .= $structString;
		}
	if ($numClasses)
		{
		# If the classList contains method/interface'::' tags, remove those
		# to make the TOC narrower. Also remove method/interface tags
		# if entry contains '#' indicating a method name.
		for (my $i = 0; $i < @classList; ++$i)
			{
			if (index($classList[$i], ':') > 0)
				{
				$classList[$i] =~ s!\w+\:\:!!g;
				# Fix the icon
				$classList[$i] =~ s!$C_icon!$m_icon!;
				}
			
			if (index($classList[$i], '#') > 0)
				{
				$classList[$i] =~ s!\w+\.!!g;
				$classList[$i] =~ s!\w+\#!!g;
				# Fix the icon
				$classList[$i] =~ s!$C_icon!$m_icon!;
				}
			}
		my $classString = join("\n", @classList);
		if ($numStructs)
			{
			$classString = $typeBreak . $classString;
			}
		$$tocR .= $classString;
		}
	if ($numMethods)
		{
		my $methodString = join("\n", @methodList);
		if ($numStructs || $numClasses)
			{
			$methodString = $typeBreak . $methodString;
			}
		$$tocR .= $methodString;
		}
	if ($numFunctions)
		{
		my $functionString = join("\n", @functionList);
		if ($numStructs || $numClasses || $numMethods)
			{
			$functionString = $typeBreak . $functionString;
			}
		$$tocR .= $functionString;
		}
	
	# Get rid of the one or two temp files made while getting ctags.
	unlink($ctagsFilePath);
	if ($tempFilePath ne '')
		{
		unlink($tempFilePath);
		}
	}

# Table of contents for a Fortan file. Types, and procedures (subroutines and functions).
sub GetFortranTOC {
	my ($txtR, $tocR) = @_;
	my @lines = split(/\n/, $$txtR);
	my @classList;
	my @classNames;
	my @methodList;
	my @methodNames;
	my %idExists; # used to avoid duplicated anchor id's.
	
	my $numLines = @lines;
	my $lineNum = 1;
	for (my $i = 0; $i < $numLines; ++$i)
		{
		if ( $lines[$i] =~ m!^[^\!]*?type\s+(\w+)!i
		  || $lines[$i] =~ m!^[^\!]*?type\s*,[^\:]+\:\:\s+(\w+)!i)
			{
			if ($lines[$i] !~ m!end\s+type!)
				{
				$lines[$i] =~ m!type\s+(\w+)!i;
				my $className = $1; # Really should be $typeName, sorry
				my $contentsClass = 'h2';
				my $id = $className;
				$id =~ s!\s+!_!g;
				$id = UniqueTocID($id, \%idExists);
				my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
				my $jlEnd = "</a></li>";
				push @classList, $jlStart . $T_icon . $className . $jlEnd;
				push @classNames, $className;
				}
			}
		elsif ($lines[$i] =~ m!^[^\!]*?(function|subroutine)\s+(\w+)!i)
			{
			if ($lines[$i] !~ m!end\s+(function|subroutine)!)
				{
				$lines[$i] =~ m!(function|subroutine)\s+(\w+)!;
				my $callType = lc($1);
				my $methodName = $2; # Really should be $procedureName, sorry
				my $contentsClass = 'h2';
				my $id = $methodName;
				$id =~ s!\s+!_!g;
				$id = UniqueTocID($id, \%idExists);
				my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
				my $jlEnd = "</a></li>";
				my $icon = ($callType eq 'function') ? $f_icon : $s_icon;
				push @methodList, $jlStart . $icon . $methodName . '()' . $jlEnd;
				push @methodNames, $methodName;
				}
			}
		++$lineNum;
		}
		
	my @idx = sort { $classNames[$a] cmp $classNames[$b] } 0 .. $#classNames;
	@classList = @classList[@idx];
	@idx = sort { $methodNames[$a] cmp $methodNames[$b] } 0 .. $#methodNames;
	@methodList = @methodList[@idx];
	my $numClassListEntries = @classList;
	my $classBreak = ($numClassListEntries > 0) ? '<br>': '';
	$$tocR = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n" . join("\n", @classList) . $classBreak . join("\n", @methodList) . "</ul>\n";
	}

# COBOL table of contents entries. Divisions, sections, procedures, records, file descriptors.
sub GetCOBOLTOC {
	my ($txtR, $tocR) = @_;
	$$tocR = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n";
	my @lines = split(/\n/, $$txtR);
	my $numLines = @lines;
	my $numCalls = 0;
	my %idExists; # used to avoid duplicated anchor id's.

	for (my $i = 0; $i < $numLines; ++$i)
		{
		if ($lines[$i] =~ m!^(\d{6}.)?\s*identification\s+division!i)
			{
			++$numCalls;

			# Look ahead a bit to see if we're dealing with Object Oriented COBOL
			my $isOOCOBOL = 0;
			my $lookAheadLimit = $i + 10;
			if ($lookAheadLimit > $numLines)
				{
				$lookAheadLimit = $numLines;
				}
			for (my $j = $i + 1; $j < $lookAheadLimit; ++$j)
				{
				if ($lines[$j] =~ m!^(\d{6}.)?\s*class-id[.\s]*([a-zA-Z0-9-]+)!i)
					{
					$isOOCOBOL = 1;
					$i = $j;
					last;
					}
				}

			if ($isOOCOBOL)
				{
				$i = getOneOOCOBOLTOC(\@lines, $numLines, $i, $numCalls, \%idExists, $tocR);
				}
			else
				{
				$i = GetOneProgramCOBOLTOC(\@lines, $numLines, $i, $numCalls, \%idExists, $tocR);
				}
			}
		else # not id, look for class-id only
			{
			if ($lines[$i] =~ m!^(\d{6}.)?\s*class-id[.\s]*([a-zA-Z0-9-]+)!i)
				{
				$i = getOneOOCOBOLTOC(\@lines, $numLines, $i, $numCalls, \%idExists, $tocR);
				}
			}
		}

	$$tocR .= "</ul>\n";
	}

sub GetOneProgramCOBOLTOC {
	my ($lines_A, $numLines, $i, $numCalls, $idExists_H, $tocR) = @_;
	my $identificationCounter = 0;
	if ($lines_A->[$i] !~ m!^(\d{6}.)?\s*identification\s+division!i)
		{
		return($numLines);
		}

	my @classList;
	my @classNames;
	my @methodList;
	my @methodNames;

	my %sortLetterForDivision;
	$sortLetterForDivision{'IDENTIFICATION'} = 'A ';
	$sortLetterForDivision{'ENVIRONMENT'} = 'B ';
	$sortLetterForDivision{'DATA'} = 'C ';
	$sortLetterForDivision{'PROCEDURE'} = 'D ';
	
	my $divisionName = '';
	my $divisionNameUC = ''; 	# Uppercase division name
	#my $sectionName = '';
	my $sectionNameUC = '';
	my $inDeclaratives = 0; 	# DECLARATIVES in PROCEDURE division, skip
	my %varNames; 				# Remember variable names from WORKING-STORAGE etc
	my %topLevelVars;			# Variables displayed in the TOC under DATA
	my $topLevelIndentLength = -1; # Pick up only record names with the least indent, based on first seen.
	for (; $i < $numLines; ++$i)
		{
		my $lineNum = $i + 1;
		# DIVISION
		if ($lines_A->[$i] =~ m!^(\d{6}.)?\s*([a-zA-Z0-9-]+)\s+division!i)
			{
			my $className = defined($2) ? $2 : $1; # Really should be $divisionName, sorry
			$divisionName = $className;
			$divisionNameUC = uc($divisionName);

			# Move on to next subprogram if we see a second IDENTIFICATION DIVISION
			if ($divisionNameUC eq 'IDENTIFICATION')
				{
				++$identificationCounter;
				if ($identificationCounter >= 2)
					{
					last;
					}
				}
			my $contentsClass = 'h2';
			my $id = $className;
			$id =~ s!\s+!_!g;
			$id = UniqueTocID($id, $idExists_H);
			my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			my $jlEnd = "</a></li>";
			push @classList, $jlStart . $divisionNameUC . $jlEnd;
			my $sortLetter = defined($sortLetterForDivision{$divisionNameUC}) ? $sortLetterForDivision{$divisionNameUC}: 'Z';
			push @classNames, $sortLetter . uc($className);
			}
		# PROGRAM-ID in IDENTIFICATION division
		elsif ($lines_A->[$i] =~ m!^(\d{6}.)?\s*program-id\.?\s+([a-zA-Z0-9-]+)!i)
			{
			my $programID = defined($2) ? $2 : $1;
			# Use "PROGRAM-ID $programID" as a section name under current division (identification)
			my $className = $divisionNameUC . ' ' . "PROGRAM-ID " . $programID;
			my $contentsClass = 'h3';
			my $id = $className;
			$id =~ s!\s+!_!g;
			$id = UniqueTocID($id, $idExists_H);
			my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			my $jlEnd = "</a></li>";
			push @classList, $jlStart . "PROGRAM-ID " . $programID . $jlEnd;
			#push @classList, $jlStart . $className . $jlEnd;
			my $sortLetter = defined($sortLetterForDivision{$divisionNameUC}) ? $sortLetterForDivision{$divisionNameUC}: 'Z';
			push @classNames, $sortLetter . uc($className);
			}
		# SECTION
		elsif ($divisionNameUC ne 'PROCEDURE' && $lines_A->[$i] =~ m!^(\d{6}.)?\s*([a-zA-Z0-9-]+)\s+section!i)
			{
			my $sectionName = defined($2) ? $2 : $1;
			$sectionNameUC = uc($sectionName);
			# Use division-section as the name.
			my $className = $divisionNameUC . ' ' . $sectionName;
			my $contentsClass = 'h3';
			my $id = $className;
			$id =~ s!\s+!_!g;
			$id = UniqueTocID($id, $idExists_H);
			my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			my $jlEnd = "</a></li>";
			push @classList, $jlStart . $S_icon . $sectionName . $jlEnd;
			#push @classList, $jlStart . $className . $jlEnd;
			my $sortLetter = defined($sortLetterForDivision{$divisionNameUC}) ? $sortLetterForDivision{$divisionNameUC}: 'Z';
			push @classNames, $sortLetter .uc($className);
			}
		# DATA variables and records (top level only)
		elsif ( $divisionNameUC eq 'DATA'
			 && $lines_A->[$i] =~ m!^(\d{6}.)?\s*([a-zA-Z0-9-]+)\s+([a-zA-Z0-9-]+)!)
			{
			my $varName = defined($3) ? $3 : $2;
			my $prefix = defined($3) ? $2 : $1; # Eg "01" or "FD"
			if (!defined($2)) # Shouldn't happen with compilable code
				{
				$varName = $1;
				$prefix = '';
				}
			$varNames{$varName} += 1;

			if ($prefix !~ m!^\d+$! && $prefix !~ m!^[a-zA-Z][a-zA-Z]$!)
				{
				++$lineNum; # This is why I don't like doing "next;"
				next;
				}

			# Pick up top level vars. This is mainly done by matching the indentation
			# level of the first variable seen in all subsequent matches (except 01 vars).
			$lines_A->[$i] =~ m!^((\d{6}.)?\s*)!;
			my $indent = $1;
			my $indentLength = length($indent);
			if ($topLevelIndentLength < 0)
				{
				$topLevelIndentLength = $indentLength;
				}
			if ($topLevelIndentLength >= 0)
				{
				if ($indentLength == $topLevelIndentLength ||
					$prefix eq "01" || $prefix eq "1" || $prefix eq "77")
					{
					my $className = $divisionNameUC . ' ' . $sectionNameUC . ' ' . $varName;
					my $contentsClass = 'h4';
					my $id = $className;
					$id =~ s!\s+!_!g;
					$id = UniqueTocID($id, $idExists_H);
					my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
					my $jlEnd = "</a></li>";
					push @classList, $jlStart . $D_icon . $varName . $jlEnd;
					#push @classList, $jlStart . $className . $jlEnd;
					my $sortLetter = defined($sortLetterForDivision{$divisionNameUC}) ? $sortLetterForDivision{$divisionNameUC}: 'Z';
					push @classNames, $sortLetter . uc($className);
					}
				}
			}
		# Procedures
		elsif ($divisionNameUC eq 'PROCEDURE') # procedure division, procedure
			{
			if ($lines_A->[$i] =~ m!DECLARATIVES!i)
				{
				if ($lines_A->[$i] =~ m!END\s+DECLARATIVES!i)
					{
					$inDeclaratives = 0;
					}
				else
					{
					$inDeclaratives = 1;
					}
				}
			
			if ( !$inDeclaratives
			  && ( $lines_A->[$i] =~ m!^(\d{6}.)?\s*([a-zA-Z0-9-]+)\.?\s*$!
			    || $lines_A->[$i] =~ m!^(\d{6}.)?\s*([a-zA-Z0-9-]+)\s+SECTION!i))
				{
				my $methodName = defined($2) ? $2 : $1;
				if (!isCobolKeyWord($methodName) && !defined($varNames{$methodName}))
					{
					my $contentsClass = 'h3';
					my $id = $methodName;
					$id =~ s!\s+!_!g;
					$id = UniqueTocID($id, $idExists_H);
					my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
					my $jlEnd = "</a></li>";
					push @methodList, $jlStart . $f_icon . $methodName . '()' . $jlEnd;
					push @methodNames, uc($methodName);
					}
				}
			}
		
		++$lineNum;
		}

	my @idx = sort { $classNames[$a] cmp $classNames[$b] } 0 .. $#classNames;
	@classList = @classList[@idx];
	@idx = sort { $methodNames[$a] cmp $methodNames[$b] } 0 .. $#methodNames;
	@methodList = @methodList[@idx];
	my $numClassListEntries = @classList;
	my $programBreak = ($numCalls > 1) ? '<br>': '';
	#my $classBreak = ($numClassListEntries > 0) ? '<br>': '';
	$$tocR .= $programBreak . join("\n", @classList) . join("\n", @methodList);
	
	if ($i > 0)
		{
		--$i; # Step back a line, for loop in caller will step ahead one.
		}
	
	return($i);
	}

# Table of Contents for a COBOL class (Object Oriented COBOL).
# Because I decided to do a COBOL TOC, so might as well finish the job.
sub getOneOOCOBOLTOC {
	my ($lines_A, $numLines, $i, $numCalls, $idExists_H, $tocR) = @_;
	my $ooClassName = '';

	my @classList;
	my @classNames;
	my @methodList;
	my @methodNames;

	my %sortLetterForDivision;
	$sortLetterForDivision{'IDENTIFICATION'} = 'A ';
	$sortLetterForDivision{'ENVIRONMENT'} = 'B ';
	$sortLetterForDivision{'DATA'} = 'C ';
	$sortLetterForDivision{'PROCEDURE'} = 'D ';
	
	my $divisionName = '';
	my $divisionNameUC = ''; 	# Uppercase division name
	#my $sectionName = '';
	my $sectionNameUC = '';
	my $inDeclaratives = 0; 	# DECLARATIVES in PROCEDURE division, skip
	my %varNames; 				# Remember variable names from WORKING-STORAGE etc
	my %topLevelVars;			# Variables displayed in the TOC under DATA
	my $topLevelIndentLength = -1; # Pick up only record names with the least indent, based on first seen.
	my $inObject = 0;

	if ($lines_A->[$i] =~ m!^(\d{6}.)?\s*CLASS-ID[.\s]*([a-zA-Z0-9-]+)!i)
		{
		$ooClassName = defined($2) ? $2 : $1;
		++$i;

		my $lineNum = $i;
		my $className = $ooClassName;
		my $contentsClass = 'h2';
		my $id = $className;
		$id =~ s!\s+!_!g;
		$id = UniqueTocID($id, $idExists_H);
		my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
		my $jlEnd = "</a></li>";
		push @classList, $jlStart . $C_icon . $ooClassName . $jlEnd;
		push @classNames, $sortLetterForDivision{'IDENTIFICATION'} . uc($className);
		}
	else # No class, no TOC. Maintenance error probably.
		{
		return($numLines);
		}

	for (; $i < $numLines; ++$i)
		{
		my $lineNum = $i + 1;

		# Methods: pick up the name and skip to END.
		if ($lines_A->[$i] =~ m!^(\d{6}.)?\s*METHOD-ID\.?\s+([a-zA-Z0-9-]+)!i)
			{
			my $methodName = defined($2) ? $2 : $1;
			my $contentsClass = 'h3';
			my $id = $methodName;
			$id =~ s!\s+!_!g;
			$id = UniqueTocID($id, $idExists_H);
			my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
			my $jlEnd = "</a></li>";
			if ($methodName =~ m!^new$!i)
				{
				push @methodList, $jlStart . $m_icon . "<strong>" . $methodName . "</strong>" . '()' . $jlEnd;
				}
			else
				{
				push @methodList, $jlStart . $m_icon. $methodName . '()' . $jlEnd;
				}
			push @methodNames, uc($methodName);

			# Skip to END METHOD.
			++$i;
			while ($i < $numLines
				&& $lines_A->[$i] !~ m!^(\d{6}.)?\s*END\s+METHOD!i)
				{
				++$i;
				}
			}
		# Drop out if we see "END CLASS".
		elsif ($lines_A->[$i] =~ m!^(\d{6}.)?\s*END\s+CLASS!i)
			{
			last;
			}

		# Are we in an OBJECT?
		elsif ($lines_A->[$i] =~ m!^(\d{6}.)?\s*OBJECT[^-]*!i)
			{
			$inObject = 1;
			}
		elsif ($lines_A->[$i] =~ m!^(\d{6}.)?\s*END\s+OBJECT!i)
			{
			$inObject = 0;
			#last;
			}
		# Pick up top level vars, just 01 and 77.
		elsif ($lines_A->[$i] =~ m!^(\d{6}.)?\s*([a-zA-Z0-9-]+)\s+([a-zA-Z0-9-]+)!)
			{
			my $varName = defined($3) ? $3 : $2;
			my $prefix = defined($3) ? $2 : $1; # Eg "01" or "FD"
			if (!defined($2)) # Shouldn't happen with compilable code
				{
				$varName = $1;
				$prefix = '';
				}
			$varNames{$varName} += 1;

			if ($prefix !~ m!^\d+$! && $prefix !~ m!^[a-zA-Z][a-zA-Z]$!)
				{
				++$lineNum; # This is why I don't like doing "next;"
				next;
				}

			if ($prefix eq "01" || $prefix eq "1" || $prefix eq "77"
				|| $prefix =~ m!^[a-zA-Z][a-zA-Z]$!)
				{
				my $className = $ooClassName . ' ' . $varName;
				my $contentsClass = 'h3';
				my $id = $className;
				$id =~ s!\s+!_!g;
				$id = UniqueTocID($id, $idExists_H);
				my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
				my $jlEnd = "</a></li>";
				push @classList, $jlStart . $D_icon. $varName . $jlEnd;
				push @classNames, uc($className);
				}
			}
		++$lineNum;
		}

	my @idx = sort { $classNames[$a] cmp $classNames[$b] } 0 .. $#classNames;
	@classList = @classList[@idx];
	@idx = sort { $methodNames[$a] cmp $methodNames[$b] } 0 .. $#methodNames;
	@methodList = @methodList[@idx];
	my $numClassListEntries = @classList;
	my $programBreak = ($numCalls > 1) ? '<br>': '';
	my $classBreak = ($numClassListEntries > 0) ? '<br>': '';
	$$tocR .= $programBreak . join("\n", @classList) . $classBreak . join("\n", @methodList);

	# We don't need to step back a line.
	return($i);
	}

# Table of contents for a Visual Basic file.
sub GetVBTOC {
	my ($txtR, $tocR) = @_;
	my @lines = split(/\n/, $$txtR);
	my @moduleList;
	my @moduleNames;
	my @classList;
	my @classNames;
	my @methodList;
	my @methodNames;
	my %idExists; # used to avoid duplicated anchor id's.
	
	# Tag hierarchy.
	my $currentModule = '';
	my $currentClass = '';
	my $currentStructure = '';

	my $numLines = @lines;
	my $lineNum = 1;
	my $quotePos = -1;
	for (my $i = 0; $i < $numLines; ++$i)
		{
		# Crudely remove comments (not perfect, but good enough for us
		# since we are looking for top level defining instances).
		$quotePos = index($lines[$i], "'");
		if ($quotePos >= 0)
			{
			$lines[$i] = substr($lines[$i], 0, $quotePos);
			}
		# Look for tag on line where defined.
		if ($lines[$i] =~ m!^(.*?)(module|sub|function|structure|class)\s+(\w+)!i)
			{
			my $tagType = lc($2);
			my $tagName = $3;
			
			if ($tagType eq 'module')
				{
				$currentModule = $tagName . '.';
				PushVBTag(\@moduleList, \@moduleNames, \%idExists,
						  $lineNum, $tagName, 'h2', $M_icon);
				}
			elsif ($tagType eq 'class')
				{
				$currentClass = $tagName . '.';
				PushVBTag(\@classList, \@classNames, \%idExists,
						  $lineNum, $tagName, 'h2', $C_icon);
				}
			elsif ($tagType eq 'structure')
				{
				$currentStructure = $tagName . '.';
				PushVBTag(\@classList, \@classNames, \%idExists,
						  $lineNum, $tagName, 'h2', $S_icon);
				}
			elsif ($tagType eq 'sub' || $tagType eq 'function')
				{
				my $owner = $currentClass . $currentStructure;
				# Strip final '.' if any.
				my $lastDotPos = rindex($owner, ".");
				if ($lastDotPos > 0)
					{
					$owner = substr($owner, 0, $lastDotPos);
					}
				
				if ($owner ne '')
					{
					PushVBTag(\@classList, \@classNames, \%idExists,
						  $lineNum, $owner . '#' . $tagName, 'h3', $m_icon);
					}
				else
					{
					PushVBTag(\@methodList, \@methodNames, \%idExists,
						  $lineNum, $tagName, 'h2', $f_icon);
					}
				}
			}
		# Look for end tag.
		elsif ($lines[$i] =~ m!^(.*?)end\s+(\w+)!i)
			{
			my $tagType = lc($2);

			if ($tagType eq 'module')
				{
				$currentModule = '';
				}
			elsif ($tagType eq 'class')
				{
				$currentClass = '';
				}
			elsif ($tagType eq 'structure')
				{
				$currentStructure = '';
				}
			
			}
		++$lineNum;
		}
	
	my @idx = sort { $classNames[$a] cmp $classNames[$b] } 0 .. $#classNames;
	@classList = @classList[@idx];
	@idx = sort { $methodNames[$a] cmp $methodNames[$b] } 0 .. $#methodNames;
	@methodList = @methodList[@idx];
	@idx = sort { $moduleNames[$a] cmp $moduleNames[$b] } 0 .. $#moduleNames;
	@moduleList = @moduleList[@idx];
	
	my $numModuleEntries = @moduleList;
	my $moduleBreak = ($numModuleEntries > 0) ? '<br>': '';
	my $numClassListEntries = @classList;
	my $classBreak = ($numClassListEntries > 0) ? '<br>': '';

	# Trim down sub and function entries in @classList, remove owners.
	for (my $i = 0; $i < $numClassListEntries; ++$i)
		{
		if (index($classList[$i], '#') > 0)
			{
			$classList[$i] =~ s!\w+\.!!g;
			$classList[$i] =~ s!\w+\#!!g;
			}
		}
	
	$$tocR = "<ul>\n<li class='h2' id='cmTopTocEntry'><a onmousedown='jumpToLine(1, false);'>TOP</a></li>\n" . join("\n", @moduleList) . $moduleBreak . join("\n", @classList) . $classBreak . join("\n", @methodList) . "</ul>\n";
	}

sub PushVBTag {
	my ($listA, $namesA, $idExistsH, $lineNum, $tagName, $contentsClass, $icon) = @_;

	my $id = $tagName;
	$id =~ s!\s+!_!g;
	$id = UniqueTocID($id, $idExistsH);
	my $jlStart = "<li class='$contentsClass'><a onmousedown='goToAnchor(\"$id\", $lineNum);'>";
	my $jlEnd = "</a></li>";
	push @$listA, $jlStart . $icon . $tagName . $jlEnd;
	push @$namesA, $tagName;
	}
1;
