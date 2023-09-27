# gloss.pm: a module for Gloss, as used by the ToDo page. See Gloss.txt.
# And see intramine_todolist.pl for an example of usage.
# This is a slightly reduced version of Gloss:
# - linking: only web links and full paths in double quotes are supported
# - cells in TABLEs should be separated by \t rather than actual tab
# - there is no automatic table of contents
# - line numbers are not supported
# - lesser niceties, such as highlighting all instances of a selection, are not supported.

package gloss;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use utf8;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use intramine_config;
use win_wide_filepaths;
use ext;

# These are set when Gloss() is called.
my $IMAGESDIR;
my $COMMONIMAGESDIR;

# VS Code is messing with me, trying to work around it. Success!
my $CONFIGLOADED = 0;

BEGIN {
    $CONFIGLOADED = 0;
}

# Return an HTML version of $text with Gloss-style markdown.
# Note no table of contents here.
# Contents are put in a simple table without line numbers.
sub Gloss {
    my ($text, $serverAddr, $mainServerPort, $contentsR, $doEscaping, $imagesDir, $commonImagesDir, $contextDir) = @_;
	$IMAGESDIR = $imagesDir;
	$COMMONIMAGESDIR = $commonImagesDir;

	if (!defined($doEscaping))
		{
		$doEscaping = 1;
		}
	
	if ($doEscaping)
		{
   		$text = horribleUnescape($text);
		}
 
	# If the gloss is going in a toolip, inline the images.
	# We are doing a tooltip if $doEscaping is 0;
	my $inlineImages = ($doEscaping) ? 0 : 1;

	if (!$CONFIGLOADED)
		{
		LoadConfigValues();
		$CONFIGLOADED = 1;
		}

    my @lines = split(/\n/, $text);

    my @jumpList;
    my $lineNum = 1;
    my %sectionIdExists; # used to avoid duplicated anchor id's for sections.
 	my $orderedListNum = 0;
	my $secondOrderListNum = 0;
	my $unorderedListDepth = 0; # 0 1 2 for no list, top level, second level.
	my $justDidHeadingOrHr = 0;
	# We are in a table from seeing a line that starts with TABLE|[_ \t:.-]? until a line with no tabs.
	my $inATable = 0;

    for (my $i = 0; $i < @lines; ++$i)
        {
        AddEmphasis(\$lines[$i]);

		if ($lines[$i] =~ m!^TABLE($|[_ \t:.-])!)
			{
			$inATable = 1;
			}
		elsif ($inATable && $lines[$i] !~ m!\t!)
			{
			$inATable = 0;
			}

		if (!$inATable)
			{
			UnorderedList(\$lines[$i], \$unorderedListDepth);
			OrderedList(\$lines[$i], \$orderedListNum, \$secondOrderListNum);
			
			# Underlines -> hr or heading. Heading requires altering line before underline.
			if ($i > 0 && $lines[$i] =~ m!^[=~-][=~-]([=~-]+)$!)
				{
				my $underline = $1;
				if (length($underline) <= 2) # ie three or four total
					{
					HorizontalRule(\$lines[$i], $lineNum);
					}
				elsif ($justDidHeadingOrHr == 0) # a heading - put in anchor and add to jump list too
					{
					Heading(\$lines[$i], \$lines[$i-1], $underline, \@jumpList, $i, \%sectionIdExists);
					}
				else # treat like any ordinary line
					{
					$lines[$i] = "<tr><td>" . $lines[$i] . '</td></tr>';
					}
				$justDidHeadingOrHr = 1;
				}
			else # treat like any ordinary line
				{
				if ($lines[$i] eq '')
					{
					$lines[$i] = "<tr><td>" . '&nbsp;' . '</td></tr>';
					$justDidHeadingOrHr = 0;
					}
				else
					{
					$lines[$i] = "<tr><td>" . $lines[$i] . '</td></tr>';
					$justDidHeadingOrHr = 0;
					}
				}
			}
		else
			{
			# Put contents in table cell.
			$lines[$i] = "<tr><td>" . $lines[$i] . '</td></tr>';
			$justDidHeadingOrHr = 0;
			}
		++$lineNum;
        }
    
    # Tables, see below.
	PutTablesInText(\@lines);

    # Put in web links and double-quoted full path links.
    for (my $i = 0; $i < @lines; ++$i)
        {
        AddLinks(\${lines[$i]}, $serverAddr, $mainServerPort, $inlineImages, $contextDir);
        }
    
	# TEST ONLY try using &quot;
	$$contentsR .= "<div class=&quot;gloss_div&quot;><table><tbody>" . join("\n", @lines) . "</tbody></table></div>";
	# $$contentsR .= "<div class='gloss_div'><table><tbody>" . join("\n", @lines) . "</tbody></table></div>";

	if ($doEscaping)
		{
    	$$contentsR = horribleEscape($$contentsR);
		}
   }

# See todo.js#horribleEscape();
sub horribleUnescape {
    my ($text) = @_;

    $text =~ s!__EQUALSIGN_REP__!\=!g;
    $text =~ s!__DQUOTE_REP__!\"!g;
    $text =~ s!__ONEQUOTE_REP__!\'!g;
    $text =~ s!__PLUSSIGN_REP__!\+!g;
    $text =~ s!__PERCENTSIGN_REP__!\%!g;
    $text =~ s!__AMPERSANDSIGN_REP__!\&!g;
    $text =~ s!__TABERINO__!\t!g; # true tab, as opposed to \t
    $text =~ s!__BSINO__!\\!g;

    return($text);
    }

sub horribleEscape {
    my ($text) = @_;

    $text =~ s!\=!__EQUALSIGN_REP__!g;
    $text =~ s!\"!__DQUOTE_REP__!g;
    $text =~ s!\'!__ONEQUOTE_REP__!g;
    $text =~ s!\+!__PLUSSIGN_REP__!g;
    $text =~ s!\%!__PERCENTSIGN_REP__!g;
    $text =~ s!\&!__AMPERSANDSIGN_REP__!g;
    $text =~ s!\t!__TABERINO__!g; # true tab replaced by placeholder
    $text =~ s!\\!__BSINO__!g;

    return($text);
    }

# Bold, italic, and special symbols.
sub AddEmphasis {
	my ($lineR) = @_;

	$$lineR =~ s!\&!\&amp;!g;
	$$lineR =~ s!\<!&#60;!g;
	$$lineR =~ s!\&#62;!&gt;!g;

	$$lineR =~ s!\*\!\*(.*?)\*\!\*!<code>$1</code>!g;
	# For italic and bold, avoid a space or tab as the last character,
	# to prevent bolding "*this, but *this doesn't always" etc.
	$$lineR =~ s!\*\*(.*?[^\s])\*\*!<strong>$1</strong>!g;
	$$lineR =~ s!\*(.*?[^\s])\*!<em>$1</em>!g;
	
	# # ***code*** **bold** *italic*  (NOTE __bold__  _italic_ not done, they mess up file paths).
	# # Require non-whitespace before trailing *, avoiding *this and *that mentions.
	# $$lineR =~ s!\*\*\*([a-zA-Z0-9_. \t'",-].+?[a-zA-Z0-9_.'"-])\*\*\*!<code>$1</code>!g;
	# $$lineR =~ s!\*\*([a-zA-Z0-9_. \t'",-].+?[a-zA-Z0-9_.'"-])\*\*!<strong>$1</strong>!g;
	# $$lineR =~ s!\*([a-zA-Z0-9_. \t'",-].+?[a-zA-Z0-9_.'"-])\*!<em>$1</em>!g;
	
	# Some "markdown": make TODO etc prominent.
	# CSS for .textSymbol has font-family: "Segoe UI Symbol", that font has better looking
	# symbols than most others on a std Windows box.
	# Beetle (lady bug): &#128030;
	# Bug: &#128029;
	# Bug (ugly): &#128027;
	# Ant: &#128028;
	# Note: &#9834;
	# Reminder (a bit of string): &#127895;
	# Check mark: &#10003;
	# Heavy check mark: &#10004;
	# Ballot box with check: &#9745;
	# Wrench: &#128295;
	# OK hand sign: &#128076;
	# Hand pointing right: &#9755;
	# Light bulb: &#128161;
	# Smiling face: &#9786;
	# PEBKAC, ID10T: &#128261;
	
	$$lineR =~ s!(TODO)!<span class='notabene'>\&#127895;$1</span>!;		
	$$lineR =~ s!(REMINDERS?)!<span class='notabene'>\&#127895;$1</span>!;
	$$lineR =~ s!(NOTE)(\W)!<span class='notabene'>$1</span>$2!;
	$$lineR =~ s!(BUGS?)!<span class='textSymbol' style='color: Crimson;'>\&#128029;</span><span class='notabene'>$1</span>!;
	$$lineR =~ s!^\=\>!<span class='textSymbol' style='color: Green;'>\&#9755;</span>!; 			# White is \&#9758; but it's hard to see.
	$$lineR =~ s!^( )+\=\>!$1<span class='textSymbol' style='color: Green;'>\&#9755;</span>!;
	$$lineR =~ s!(IDEA\!)!<span class='textSymbol' style='color: Gold;'>\&#128161;</span>$1!;
	$$lineR =~ s!(FIXED|DONE)!<span class='textSymbolSmall' style='color: Green;'>\&#9745;</span>$1!;
	$$lineR =~ s!(WTF)!<span class='textSymbol' style='color: Chocolate;'>\&#128169;</span>$1!;
	$$lineR =~ s!\:\)!<span class='textSymbol' style='color: #FFBF00;'>\&#128578;</span>!; # or \&#9786;
	}

# Bulleted lists start with space? hyphen hyphen* space? then not-a-hyphen, and then anything goes.
# - two levels are supported
#- an unordered list item begins flush left with a '-', '+', or '*'.
# - optionally you can put one or more spaces at the beginning of the line.
#   -- if you put two or more of '-', '+', or '*', eg '--' or '+++', you'll get a second-level entry.
# To make it prettier in the original text, you can insert spaces at the beginning of the line.
#   A top-level or second-level item can continue in following paragraphs.
# To have the following paragraphs count as part of an item, begin each with one or more tabs or spaces.
# The leading spaces or tabs will be suppressed in the HTML display.
#     ---++** Another second-level item, with excessive spaces.
sub UnorderedList {
	my ($lineR, $unorderedListDepthR) = @_;
	
	if ($$lineR =~ m!^\s*([-+*][-+*]*)\s+([^-].+)$!)
		{
		my $listSignal = $1;
		# One 'hyphen' is first level, two 'hyphens' is second level.
		if (length($listSignal) == 1)
			{
			$$unorderedListDepthR = 1;
			$$lineR = '<p class=\'outdent-unordered\'>' . '&nbsp;&bull; ' . $2 . '</p>'; # &#9830;(diamond) or &bull;
			}
		else
			{
			$$unorderedListDepthR = 2;
			$$lineR = '<p class=\'outdent-unordered-sub\'>' . '&#9702; ' . $2 . '</p>'; # &#9702; circle, &#9830;(diamond) or &bull;
			}
		}
	elsif ($$unorderedListDepthR > 0 && $$lineR =~ m!^\s+!)
		{
		$$lineR =~ s!^\s+!!;
		if ($$unorderedListDepthR == 1)
			{
			$$lineR = '<p class=\'outdent-unordered-continued\'>' . $$lineR . '</p>';
			}
		else
			{
			$$lineR = '<p class=\'outdent-unordered-sub-continued\'>' . $$lineR . '</p>';
			}
		}
	else
		{
		$$unorderedListDepthR = 0;
		}
	}

# Ordered lists: eg 4. or 4.2 preceded by optional whitespace and followed by at least one space.
# Ordered lists are auto-numbered, provided the following guidelines are followed:
# 1. Two levels, major (2.) and minor (2.4) are supported
# 2. If the first entry in a list starts with a number, that number is used as the
#    starting number for the list.
# 3. '#' can be used as a placeholder, but it's not recommended because if you want to refer
#    to a numbered entry you have to know the number ("see #.# above" can't be filled in for you
#    without AI-level intelligence). In practice, careful numbering by hand is more useful.
# 4. If you use two levels, there should be a single level entry starting off each top-level
#    item, such as the "1." "2." "3." entries in 1., 1.1, 1.2, 2., 2.1, 3., 3.1.
# An item can have more than one paragraph. To signal that a paragraph belongs to a list item,
# begin the paragraph with one or more spaces or tabs. The leading spaces or tabs will be
# suppressed in the resulting HTML.
# Naming: "ol-1-2-c" = ordered list - one digit top level - two digits second - continuation
#  paragraph.
# "ol-2" = ordered list - two digits top level, no second level, first paragraph.
sub OrderedList {
	my ($lineR, $listNumberR, $subListNumberR) = @_;
	
	# A major list item, eg "3.":
	if ($$lineR =~ m!^\s*(\d+|\#)\. +(.+?)$!)
		{
		my $suggestedNum = $1;
		my $trailer = $2;
		if ($suggestedNum eq '#')
			{
			$suggestedNum = 0;
			}
		if ($$listNumberR == 0 && $suggestedNum > 0)
			{
			$$listNumberR = $suggestedNum;
			}
		else
			{
			++$$listNumberR;
			}
		
		$$subListNumberR = 0;
		my $class = (length($suggestedNum) > 1) ? "ol-2": "ol-1";
        $$lineR = "<p class='" . $class . "'>" . "$$listNumberR. $trailer" . '</p>';
		}
	# A minor entry, eg "3.1":
	elsif ($$lineR =~ m!^\s*(\d+|\#)\.(\d+|\#) +(.+?)$!)
		{
		my $suggestedNum = $1;			# not used
		my $secondSuggestedNum = $2;	# not used
		my $trailer = $3;
		
		++$$subListNumberR;
		if ($$listNumberR <= 0)
			{
			$$listNumberR = 1;
			}
		if (length($$listNumberR) > 1)
			{
			my $class = (length($$subListNumberR) > 1) ? "ol-2-2": "ol-2-1";
			$$lineR = "<p class='" . $class . "'>" . "$$listNumberR.$$subListNumberR $trailer" . '</p>';
			}
		else
			{
			my $class = (length($$subListNumberR) > 1) ? "ol-1-2": "ol-1-1";
			$$lineR = "<p class='" . $class . "'>" . "$$listNumberR.$$subListNumberR $trailer" . '</p>';
			}
		}
	# Line continues an item if we're in one and it starts with one or more tabs or spaces.
	elsif ($$listNumberR > 0 && $$lineR =~ m!^\s+!)
		{
		$$lineR =~ s!^\s+!!;
		if ($$subListNumberR > 0)
			{
			if (length($$listNumberR) > 1)
				{
				my $class = (length($$subListNumberR) > 1) ? "ol-2-2-c": "ol-2-1-c";
				$$lineR = "<p class='" . $class . "'>" . $$lineR . '</p>';
				}
			else
				{
				my $class = (length($$subListNumberR) > 1) ? "ol-1-2-c": "ol-1-1-c";
				$$lineR = "<p class='" . $class . "'>" . $$lineR . '</p>';
				}
			}
		else
			{
			my $class = (length($$listNumberR) > 1) ? "ol-2-c": "ol-1-c";
			$$lineR = "<p class='" . $class . "'>" . $$lineR . '</p>';
			}
		}
	else
		{
		# A blank line or line that doesn't start with a space or tab restarts the auto numbering.
		if ($$lineR =~ m!^\s*$! || $$lineR !~ m!^\s!)
			{
			$$listNumberR = 0;
			$$subListNumberR = 0;
			}
		}	
	}

sub HorizontalRule {
	my ($lineR, $lineNum) = @_;
	
	# <hr> equivalent for three or four === or --- or ~~~
	# If it's === or ====, use a slightly thicker rule.
	my $imageName = ($$lineR =~ m!^\=\=\=\=?!) ? 'mediumrule4.png': 'slimrule4.png';
	my $height = ($imageName eq 'mediumrule4.png') ? 6: 3;
	$$lineR = "<tr><td class='vam'><img style='display: block;' src='$imageName' width='98%' height='$height' /></td></tr>";
	}

# Heading(\$lines[$i], \$lines[$i-1], $underline, \@jumpList, $i, \%sectionIdExists);
sub Heading {
	my ($lineR, $lineBeforeR, $underline, $jumpListA, $i, $sectionIdExistsH) = @_;
		
	# Use text of header for anchor id if possible.
	$$lineBeforeR =~ m!^(<tr><td>)(.*?)(</td></tr>)$!;
	my $beforeHeader = $1;
	my $headerProper = $2;
	my $afterHeader = $3;

	# No heading if the line before has no text.
	if (!defined($headerProper) || $headerProper eq '')
		{
		return;
		}
	
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
	
	my $contentsClass = 'h2';
	if (substr($underline,0,1) eq '-')
		{
		$contentsClass = 'h3';
		}
	elsif (substr($underline,0,1) eq '~')
		{
		$contentsClass = 'h4';
		}
	# if ($i == 1) # right at the top of the document, assume it's a document title <h1>
	# 	{
	# 	$contentsClass = 'h1';
	# 	}
	
	# im-text-ln='$i' rather than $lineNum=$i+1, because we're on the
	# underline here and want to record the heading line number on the line before.
	my $jlStart = "<li class='$contentsClass'>";
	my $jlEnd = "</li>";

	# Turn the underline into a tiny blank row, make line before look like a header
	$$lineR = "<tr class='shrunkrow'><td></td><td></td></tr>";
	$$lineBeforeR = "$beforeHeader<$contentsClass>$headerProper</$contentsClass>$afterHeader";
	# Back out any "outdent" wrapper that might have been added, for better alignment.
	if ($jumperHeader =~ m!^<p!)
		{
		$jumperHeader =~ s!^<p[^>]*>!!;
		$jumperHeader =~ s!</p>$!!;
		}
	push @$jumpListA, $jlStart . $jumperHeader . $jlEnd;
	}

# Where a line begins with TABLE, convert lines following TABLE that contain tab(s) into an HTML table.
# NOTE here "tab" means \t rather than an actual tab.
# We have already put in line numbers and <tr> with <td> for the line numbers and contents proper, see just above.
# A table begins with TABLE followed by optional text, provided the first character in the optional text
# is one of space tab underscore colon period hyphen. The following line must also
# contain at least one tab. The table continues for all following lines containing at least one tab.
## Cells are separated by one or more tabs. Anything else, even a space, counts as cell content. ##
# The opening TABLE is suppressed. Text after TABLE is used as the caption.
# If TABLE is the only text on the line, the line is made shorter in height.
# Now, the whole body of a document is in a single table with
# each row having cells for line number and actual content. For a TABLE, the
# body table is ended with </table>, our special TABLE is put in, and then a regular
# body table is started up again with <table> afterwards. The overall <table> and </table>
# wrappers for the body are done at the end of GetPrettyTextContents().
# For the TABLE line: end previous (body) table, start new table, remove TABLE from line and also line number
# if there is no text following TABLE, and give the row class='shrunkrow' (in the table being ended).
# But if TABLE is followed by text on the same line, display the line, including the line number.
# Any following text becomes the table caption (TABLE is always removed from the text).
# Subsequent lines: first table row is <th> except for the line number which is <td>. Every table
# row starts with a line number, so there is one extra column in each row for that.
# At table end, tack on </table><table> to revert back to the regular document body table.
# In content rows, if there are too many cells then the rightmost will be combined into one
# And if there are too few, colspan will extend the last cell.
# To "skip" a column, put an unobtrusive character such as space or period for its content (it will be centered up)
# Any character that's not a tab counts as content for a cell.
# If a cell starts with <\d+> it's treated as a colspan request. The last cell doesn't need a
# <N> to span the remaining columns.
# If a cell starts with <L> or <R> or <C>, text in the cell is aligned left or right or center.
# Colspan and alignment can be combined, eg <C3>.
# See Gloss.txt for examples.
sub PutTablesInText {
	my ($lines_A) = @_;
	my $numLines = @$lines_A;
	my %alignmentString;
	$alignmentString{'L'} = " class='left_cell'";
	$alignmentString{'R'} = " class='right_cell'";
	$alignmentString{'C'} = " class='centered_cell'";
	
	for (my $i = 0; $i <$numLines; ++$i)
		{
		if ( $lines_A->[$i] =~ m!^<tr><td>TABLE(</td>|[_ \t:.-])! 
		  && $i <$numLines-1 && $lines_A->[$i+1] =~ m!\t! )
			{
			my $numColumns = 0;
			my $tableStartIdx = $i;
			my $idx = $i + 1;
			my $startIdx = $idx;
			
			# Preliminary pass, determine the maximum number of columns. Rather than check all the
			# rows, assume a full set of columns will be found on the first or second row, and
			# no colspans. Ok, four rows. Otherwise madness reigns.
			my @cellMaximumChars;
			
			GetMaxColumns($idx, $numLines, $lines_A, \$numColumns, \@cellMaximumChars);
						
			# Start the table, with optional title.
			StartNewTable($lines_A, $tableStartIdx, \@cellMaximumChars, $numColumns);

			# Main pass, make the table rows.
			$idx = $startIdx;
			$idx = DoTableRows($idx, $numLines, $lines_A, $numColumns, \%alignmentString);;

			# Stop/start table on the last line matched.
			$lines_A->[$idx-1] = $lines_A->[$idx-1] . '</tbody></table><table><tbody>';
			} # if TABLE
		} # for (my $i = 0; $i <$numLines; ++$i)
	}

# Check first few rows, determine maximum number of columns and length of each cell.
sub GetMaxColumns {
	my ($idx, $numLines, $lines_A, $numColumnsR, $cellMaximumChars_A) = @_;
	
	my $rowsChecked = 0;
	while ($idx < $numLines && $lines_A->[$idx] =~ m!\t! && ++$rowsChecked <= 4)
		{
		$lines_A->[$idx] =~ m!^<tr><td>(.+?)</td></tr>!;
		my $content = $1;
		my @contentFields = split(/\t+/, $content);
		my $currentNumColumns = @contentFields;
		if ($$numColumnsR < $currentNumColumns)
			{
			$$numColumnsR = $currentNumColumns;
			}
		for (my $j = 0; $j < $currentNumColumns; ++$j)
			{
			if ( !defined($cellMaximumChars_A->[$j])
				|| length($cellMaximumChars_A->[$j]) < length($contentFields[$j]) )
				{
				$cellMaximumChars_A->[$j] = length($contentFields[$j]);
				}
			}
		
		++$idx;				
		}
	}

sub StartNewTable {
	my ($lines_A, $tableStartIdx, $cellMaximumChars_A, $numColumns) = @_;

	if ($lines_A->[$tableStartIdx] =~ m!TABLE[_ \t:.-]\S!)
		{
		# Use supplied text after TABLE as table "caption".
		if ($lines_A->[$tableStartIdx] =~ m!^(<tr><td>)TABLE[_ \t:.-](.+?)(</td></tr>)!)
			{
			# Arg, caption can be no wider than the table, disregarding the caption. ?!?!?
			# So we'll just use text above the table if the caption is too long.
			#$lines_A->[$i] = "$1$3</table><table class='bordered'><caption>$2</caption>";
			my $pre = $1;
			my $caption = $2;
			my $post = $3;
			# If the caption will be roughly no wider than the resulting table,
			# use a caption. But if the caption will be smaller than the table,
			# just use slightly indented text. An empty line has
			# about 36 characters, the rest is the caption. Less 6 for "TABLE ".
			# A table row will be as wide as needed for the widest cell in each column,
			# and count the width of one character between columns.
			my $captionChars = length($caption);
			my $longestLineChars = 0;
			for (my $j = 0; $j < @$cellMaximumChars_A; ++$j)
				{
				$longestLineChars += $cellMaximumChars_A->[$j];
				}
			$longestLineChars += $numColumns - 1;
			if ($captionChars < $longestLineChars)
				{
				$lines_A->[$tableStartIdx] = "$pre$post</tbody></table><table class='bordered'><caption>$caption</caption><thead>";
				}
			else
				{
				$lines_A->[$tableStartIdx] = "$pre&nbsp; &nbsp;&nbsp; &nbsp;&nbsp;<span class='fakeCaption'>$caption</span>$post</tbody></table><table class='bordered'><thead>";
				}
			}
		else
			{
			# Probably a maintenance failure. Struggle on.
			$lines_A->[$tableStartIdx] = "<tr class='shrunkrow'><td></td></tr></tbody></table><table class='bordered'><thead>";
			}
		}
	else # no caption
		{
		$lines_A->[$tableStartIdx] = "<tr class='shrunkrow'><td></td></tr></tbody></table><table class='bordered'><thead>";
		}			
	}

sub DoTableRows {
	my ($idx, $numLines, $lines_A, $numColumns, $alignmentString_H) = @_;

	my $isFirstTableContentLine = 2; # Allow up to two headers rows up top.
	while ($idx < $numLines && $lines_A->[$idx] =~ m!\t!)
		{
		# Grab line number and content.
		$lines_A->[$idx] =~ m!^<tr><td>(.+?)</td></tr>!;
		#my $lineNum = $1;
		my $content = $1;
		
		# Break content into cells. Separator is one or more tabs.
		my @contentFields = split(/\t+/, $content);
		my $currentNumColumns = @contentFields;
		
		# Determine the colspan of each field. If the field starts with <[LRC]?N> where N
		# is an integer, use that as the colspan. If we're at the last field
		# and don't have enough columns yet, add them to the last field.
		my $numColumnsIncludingSpans = 0;
		my @colSpanForFields;
		my @alignmentForFields;
		my $lastUsableFieldIndex = -1;
		
		for (my $j = 0; $j < $currentNumColumns; ++$j)
			{
			my $requestedColSpan = 0;
			my $alignment = '';
			# Look for <[LRC]\d+> at start of cell text. Eg <R>, <C3>, <4>.
			if ($contentFields[$j] =~ m!^(\&#60;|\&lt\;|\<)([LRClrc]?\d+|[LRClrc])(\&#62;|\&gt\;|\>)!)
				{
				my $alignSpan = $2;
				if ($alignSpan =~ m!(\d+)!)
					{
					$requestedColSpan = $1;
					if ($requestedColSpan <= 1)
						{
						$requestedColSpan = 0;
						}
					}
				if ($alignSpan =~ m!([LRClrc])!)
					{
					$alignment = uc($1);
					}
				}
			push @colSpanForFields, $requestedColSpan;
			push @alignmentForFields, $alignment;
			$numColumnsIncludingSpans += ($requestedColSpan > 0) ? $requestedColSpan: 1;
			
			# Ignore <N> if max columns has been hit. Note when it happens.
			if ($numColumnsIncludingSpans >= $numColumns)
				{
				$lastUsableFieldIndex = $j unless ($lastUsableFieldIndex >= 0);
				$colSpanForFields[$j] = 0;
				}
			
			if ($j == $currentNumColumns - 1) # last entry
				{
				if ($lastUsableFieldIndex < 0)
					{
					$lastUsableFieldIndex = $currentNumColumns - 1;
					}
				
				if ($numColumnsIncludingSpans < $numColumns)
					{
					$colSpanForFields[$j] = $numColumns - $numColumnsIncludingSpans + 1;
					}
				# Note $numColumnsIncludingSpans > $numColumns shouldn't happen
				}
			
			# Remove the colspan hint <N> from field.
			$contentFields[$j] =~ s!^(\&#60;|\&lt\;|\<)([LRClrc]?\d+|[LRClrc])(\&#62;|\&gt\;|\>)!!;
			}

		my $cellName = ($isFirstTableContentLine) ? 'th' : 'td';
		my $newLine;

		# A line with nothing but spaces for content will be shrunk vertically.
		if ($content =~ m!^\s+$!)
			{
			$newLine = "<tr class='reallyshrunkrow'>";
			$newLine .= "<td></td>"x$numColumns;
			$newLine .= "</tr>";
			}
		else
			{
			
			#my $rowID = 'R' . $lineNum;
			$newLine = "<tr>";
			for (my $j = 0; $j <= $lastUsableFieldIndex; ++$j)
				{
				# A single non-word char such as a space or period is taken as a signal for
				# an empty cell. Just centre it up, which makes it less obtrusive.
				if ($contentFields[$j] =~ m!^\W$!)
					{
					$newLine = $newLine . "<$cellName class='centered_cell'>$contentFields[$j]</$cellName>";
					}
				else
					{
					# Leading spaces are typically for numeric alignment and should be preserved.
					# We'll adjust for up to six spaces at the start of cell contents, replacing every
					# second space with a non-breaking space, starting with the first space.
					if (index($contentFields[$j], ' ') == 0)
						{
						$contentFields[$j] =~ s!^     !&nbsp; &nbsp; &nbsp;!; 	# five spaces there
						$contentFields[$j] =~ s!^   !&nbsp; &nbsp;!;			# three spaces
						$contentFields[$j] =~ s!^ !&nbsp;!;						# one space
						}
						
					my $colspanStr = '';
					if (defined($colSpanForFields[$j]) && $colSpanForFields[$j] > 1)
						{
						$colspanStr = " colspan='$colSpanForFields[$j]'";
						}

					my $alignStr = '';
					if (defined($alignmentForFields[$j]) && $alignmentForFields[$j] ne '')
						{
						$alignStr = $alignmentString_H->{$alignmentForFields[$j]};
						}
						
					# Center up multi-column text by default.
					if ($colspanStr ne '' && $alignmentForFields[$j] eq '')
						{
						$alignStr = $alignmentString_H->{'C'};
						}

					$newLine = $newLine . "<$cellName$colspanStr$alignStr>$contentFields[$j]</$cellName>";
					}
				}
			}
		$newLine = $newLine . '</tr>';
		
		$lines_A->[$idx] = $newLine;
		
		# To allow for grouping headers above the headers proper, don't cancel
		# $isFirstTableContentLine until a full set of column entries is seen, or we've
		# seen two rows (there have to be limits).
		if ($isFirstTableContentLine > 0)
			{
			--$isFirstTableContentLine;
			
			if ($currentNumColumns == $numColumns && $isFirstTableContentLine > 0)
				{
				$isFirstTableContentLine = 0;
				}
			
			# Terminate thead and start tbody at end of header row(s).
			if ($isFirstTableContentLine == 0)
				{
				$lines_A->[$idx] .= '</thead><tbody>';
				}
			}
			
		++$idx;
		}
		
	return($idx);
	}

# Put in links to
# - web pages
# - double-quoted full paths to text files
# - double-quoted full paths to images
# For the file links to function, IntraMine's Viewer must be running.
# The ToDo page has no "context" and the Linker is not guaranteed to be running,
# so links are a bit limited.
sub AddLinks {
    my ($txtR, $serverAddr, $mainServerPort, $inlineImages, $contextDir) = @_;
    my $line = $$txtR;
    my @repStr;
	my @repLen;
	my @repStartPos;

    my $previousEndPos = 0;
    my $haveGoodMatch = 0;

    while ($line =~ m!((\"([^"]+)\.\w+(#[^"]+)?\")|(\'([^']+)\.\w+(#[^']+)?\')|(&amp;#8216;(.+?)&amp;#8216;)|(&amp;quot;(.+?)&amp;quot;)|((https?://([^\s)<\"](?\!ttp:))+)))!g)
        {
		my $startPos = $-[0];
		my $endPos = $+[0];		# pos of char after end of entire match
		my $ext = $1;			# double-quoted chunk, or url
		my $entityQuote1 = $9;
		my $entityQuote2 = $11;

		# print("\$ext: |$ext|\n");
		# if (defined($entityQuote1))
		# 	{
		# 	print("\$entityQuote: |$entityQuote1|\n");
		# 	}
		# elsif (defined($entityQuote2))
		# 	{
		# 	print("\$entityQuote: |$entityQuote2|\n");
		# 	}

        my $haveQuotation = ((index($ext, '"') == 0) || (index($ext, "'") == 0));
        my $quoteChar = '';
        if ($haveQuotation)
            {
            # Trim quotes and pick up $quoteChar.
			$quoteChar =  substr($ext, 0, 1);
			$ext = substr($ext, 1);
			$ext = substr($ext, 0, length($ext) - 1);
			#print("Have regular quotation\n");
            }
		else
			{
			if (defined($entityQuote1))
				{
				$ext = $entityQuote1;
				$haveQuotation = 1;
				$quoteChar = '&amp;#8216;'; # s.b. $quoteChars, sorry.
				#print("Quot: |$entityQuote1|\n");
				}
			elsif (defined($entityQuote2))
				{
				$ext = $entityQuote2;
				$haveQuotation = 1;
				$quoteChar = '&amp;quot;';
				#print("Quot: |$entityQuote2|\n");
				}
			}

        my $haveURL = (index($ext, 'http') == 0);
        my $url = $haveURL ? $ext : '';
        if ($haveURL)
            {
            RememberUrlGloss($url, $haveQuotation, $quoteChar, $startPos, \@repStr, \@repLen, \@repStartPos);
			$haveGoodMatch = 1;
            }
        else
            {
            # A spurious tab can sneak in if there's a literal \t in a path,
            # such as C:\temp\file.xt.
            # Change it to a forward slash (it won't be displayed).
            # This is a case where a regex won't work, due to the enclosing "while" regex above.
            # Or maybe I'm just dumb.
            my $extOriginal = $ext;
            $ext = str_replace("\t", '/t', $ext);

            # File path (trim #anchor) and check it's a path to an existing file.
            my $pathToCheck = $ext;
			
            my $anchorPos = index($ext, '#');
            if ($anchorPos > 0)
                {
                $pathToCheck = substr($ext, 0, $anchorPos);
                }
            
            my $fileExtension = GetTextOrImageExtensionNoPeriod($pathToCheck);
			my $isFullKnownPath = (FileOrDirExistsWide($pathToCheck) == 1);
			my $fullImagePath = $extOriginal;
			if (!$isFullKnownPath && IsImageExtensionNoPeriod($fileExtension))
				{
				$fullImagePath = ImageFileNamePath($pathToCheck, $contextDir);
				if ($fullImagePath ne '')
					{
					$isFullKnownPath = 1;
					#$extOriginal = $fullImagePath;
					#$pathToCheck = $extOriginal; # A big redundant, sorry.
					}
				}
            if ($isFullKnownPath && $fileExtension ne '')
                {
                RememberTextOrImageFileMentionGloss($extOriginal, $fullImagePath, $serverAddr, $mainServerPort, $haveQuotation, $quoteChar, $startPos, \@repStr, \@repLen, \@repStartPos, $inlineImages);
                }
           $haveGoodMatch = 1;
            }

        if (!$haveGoodMatch)
            {
            pos($line) = $startPos + 1;
            }
        }

    my $numReps = @repStr;
    if ($numReps)
        {
        DoTextRepsGloss($numReps, \@repStr, \@repLen, \@repStartPos, $txtR);
        }
    }

# Look around for a full path to the supplied partial image path ($fileName).
# Return a full path to an existing file, or ''.
sub ImageFileNamePath {
	my ($fileName, $contextDir) = @_;
	my $filePath = '';

	for (my $pass = 1; $pass <= 2; ++$pass)
		{
		if ($pass == 2)
			{
			if ($filePath eq '')
				{
				my $justFileName = FileNameFromPath($fileName);
				if ($justFileName eq $fileName)
					{
					last;
					}
				else
					{
					$fileName = $justFileName;
					}
				}
			else
				{
				last;
				}
			}

		if (FileOrDirExistsWide($IMAGESDIR . $fileName) == 1)
			{
			$filePath = $IMAGESDIR . $fileName;
			}
		elsif ($COMMONIMAGESDIR ne '' && FileOrDirExistsWide($COMMONIMAGESDIR . $fileName) == 1)
			{
			$filePath = $COMMONIMAGESDIR . $fileName;
			}
		elsif ($contextDir ne '' && FileOrDirExistsWide($contextDir . $fileName) == 1)
			{
			$filePath = $contextDir . $fileName;
			}
		elsif ($contextDir ne '' && FileOrDirExistsWide($contextDir . 'images/' . $fileName) == 1)
			{
			$filePath = $contextDir . 'images/' . $fileName;
			}
		}

	return($filePath);
	}

# From http://www.bin-co.com/perl/scripts/str_replace.php.
# Replace a string without using RegExp.
sub str_replace {
	my $replace_this = shift;
	my $with_this  = shift; 
	my $string   = shift;
	
	my $length = length($string);
	my $target = length($replace_this);
	
	for(my $i=0; $i<$length - $target + 1; $i++) {
		if(substr($string,$i,$target) eq $replace_this) {
			$string = substr($string,0,$i) . $with_this . substr($string,$i+$target);
	#		return $string; # Commented out to do global replace.
		}
	}
	return $string;
}

sub RememberUrlGloss {
    my ($url, $haveQuotation, $quoteChar, $startPos, $repStrA, $repLenA, $repStartPosA) = @_;

    $url =~ s!\&amp;quot;.?.?.?.?.?$!!;
    $url =~ s![.,:;?\!\)\] \t\-]$!!;
    if (length($url) < 10)
        {
        return;
        }
    my $displayedURL = $url;
    if ($haveQuotation)
        {
        $displayedURL = $quoteChar . $displayedURL . $quoteChar;
        }
	
    my $repLength = length($displayedURL);
	$displayedURL = TextWithSpanBreaks($displayedURL, 28);
    my $repString = "<a href='$url' target='_blank'>$displayedURL</a>";
    my $repStartPosition = $startPos;
    push @$repStrA, $repString;
    push @$repLenA, $repLength;
    push @$repStartPosA, $repStartPosition;
    }

# Break up long text using <span>. This allows a browser
# to break long lines that don't have spaces etc.
# This could be better (eg break on slashes or words) but it's good enough.
sub TextWithSpanBreaks {
	my ($text, $maxPartLength) = @_;
	my $lineBreaker = '<span class="noshow"></span>';
	my $textLen = length($text);
	my $excessLength = $textLen - $maxPartLength;

	if ($excessLength <= 0)
		{
		return($text);
		}

	my $result = '';
	
	while (length($text) >= $maxPartLength)
		{
		$result .= substr($text, 0, $maxPartLength);
		$text = substr($text, $maxPartLength);
		if ($text ne '')
			{
			$result .= $lineBreaker;
			}
		}
	if ($text ne '')
		{
		$result .= $text;
		}
	
	return($result);
	}

# Push link replacement details into $repStrA, $repLenA, $repStartPosA arrays.
# $repStrA: the replacement text for the link
# $repStartPosA: where the replacement starts in the original text
# $repLenA: length of text being replaced.
sub RememberTextOrImageFileMentionGloss {
    my ($extOriginal, $fullImagePath, $serverAddr, $mainServerPort, $haveQuotation, $quoteChar, $startPos, $repStrA, $repLenA, $repStartPosA, $inlineImages) = @_;
    my $ext = $extOriginal; # $ext for href, $extOriginal when caculating $repLength
    $ext = str_replace("\t", '/t', $ext);
    my $pathToCheck = $ext;
    my $anchorWithNum = '';
    my $anchorPos = index($ext, '#');
    if ($anchorPos > 0)
        {
        $pathToCheck = substr($ext, 0, $anchorPos);
        $anchorWithNum = substr($ext, $anchorPos);
        }
    my $anchorLength = length($anchorWithNum);
    my $doingQuotedPath = $haveQuotation;
    my $longestSourcePath = $pathToCheck;
    my $bestVerifiedPath = $longestSourcePath;
    my $fileExtension = GetTextOrImageExtensionNoPeriod($pathToCheck);
    my $haveImageExtension = IsImageExtensionNoPeriod($fileExtension);
    my $haveTextExtension = IsTextExtensionNoPeriod($fileExtension);
    my $repString = '';

     my $repLength = length($extOriginal);
   if ($haveTextExtension)
        {
        GetTextFileRepGloss($serverAddr, $mainServerPort, $haveQuotation, $quoteChar, $fileExtension, $longestSourcePath,
							$anchorWithNum, \$repString);

        }
    else # currently only image extension
        {
        GetImageFileRepGloss($serverAddr, $mainServerPort, $haveQuotation, $quoteChar, 0,
							$fullImagePath, \$repString, $inlineImages);
        # GetImageFileRepGloss($serverAddr, $mainServerPort, $haveQuotation, $quoteChar, 0,
		# 					$longestSourcePath, \$repString, $inlineImages);
		#my $repLength = length($fullImagePath);

        }

    if ($haveQuotation)
        {
        $repLength += 2*length($quoteChar); # for the quotes
        }

    my $repStartPosition = $startPos;

    push @$repStrA, $repString;
    push @$repLenA, $repLength;
    push @$repStartPosA, $repStartPosition;
    }

# Get link for full file path $longestSourcePath.
sub GetTextFileRepGloss {
    my ($serverAddr, $mainServerPort, $haveQuotation, $quoteChar, $fileExtension, $longestSourcePath, $anchorWithNum, $repStringR) = @_;
    
    my $editLink = '';
	my $viewerPath = $longestSourcePath;
    my $editorPath = $viewerPath;
	$editorPath =~ s!\\!/!g;
	$editorPath =~ s!%!%25!g;
	$editorPath =~ s!\+!\%2B!g;

	$viewerPath =~ s!\\!/!g;
	$viewerPath =~ s!%!%25!g;
	$viewerPath =~ s!\+!\%2B!g;

    my $displayedLinkName = $longestSourcePath . $anchorWithNum;
    # In a ToDo item a full link can be too wide too often.
    # So shorten the displayed link name to just the file name with anchor.
    $displayedLinkName = ShortenedLinkText($displayedLinkName, $quoteChar, 28);

 	if ($haveQuotation)
		{
		$displayedLinkName = $quoteChar . $displayedLinkName . $quoteChar;
		}

    my $host = $serverAddr;
	my $port = $mainServerPort;
    my $ViewerShortName = CVal('VIEWERSHORTNAME');

    my $AllowLocalEditing = CVal('ALLOW_LOCAL_EDITING');
    my $AllowRemoteEditing = CVal('ALLOW_REMOTE_EDITING');
    # This is a cheat. If it fails, clicking on the pencil icon to edit will fail.
    my $allowEditing = ($AllowRemoteEditing || $AllowLocalEditing);

	if ($allowEditing)
		{
		$editLink = "<a href='$editorPath' class='canedit' onclick=\"editOpen(this.href); return false;\">"
					. "<img class='edit_img' src='edit1.png' width='17' height='12'>" . '</a>';
		}


    my $viewerLink = "<a href=\"http://$host:$port/$ViewerShortName/?href=$viewerPath$anchorWithNum\" onclick=\"openView(this.href); return false;\"  target=\"_blank\">$displayedLinkName</a>";
	$$repStringR = "$viewerLink$editLink";
    }

# Get image link for full path $longestSourcePath. Optionally includes showhint() popup call
# and the little hummingbird images to suggest hovering.
sub GetImageFileRepGloss {
	my ($serverAddr, $mainServerPort, $haveQuotation, $quoteChar, $usingCommonImageLocation, $longestSourcePath, $repStringR, $inlineImages) = @_;

    my $fullPath = $longestSourcePath;
	$fullPath =~ s!\\!/!g;
	#$fullPath =~ s!%!%25!g;	
	$fullPath =~ s!\+!\%2B!g;

    my $host = $serverAddr;
	my $port = $mainServerPort;
    my $ViewerShortName = CVal('VIEWERSHORTNAME');
    my $imagePath = "http://$host:$port/$ViewerShortName/$fullPath";
    my $displayedLinkName = $longestSourcePath;
    # In a ToDo item a full link can be too wide too often.
    # So shorten the displayed link name to just the file name with anchor.
    $displayedLinkName = ShortenedLinkText($displayedLinkName, $quoteChar, 28);

	if ($haveQuotation)
		{
		$displayedLinkName = $quoteChar . $displayedLinkName . $quoteChar;
		}

	if ($inlineImages)
		{
		# TEST ONLY
		#$$repStringR = "<img src=&quot;$imagePath&quot;>";
		$$repStringR = "<img src='$imagePath'>";
		}
	else
		{
		my $leftHoverImg = "<img src='http://$host:$port/hoverleft.png' width='17' height='12'>"; # actual width='32' height='23'>";
		my $rightHoverImg = "<img src='http://$host:$port/hoverright.png' width='17' height='12'>";

		$$repStringR = "<a href=\"http://$host:$port/$ViewerShortName/?href=$fullPath\" onclick=\"openView(this.href); return false;\"  target=\"_blank\" onmouseover=\"showhint('<img src=&quot;$imagePath&quot;>', this, event, '500px', true);\">$leftHoverImg$displayedLinkName$rightHoverImg</a>";
		}
    }

# Replacements of file/url mentions with links are done straight in the text.
# Do all reps in reverse order for text, so as to not throw off positions.
sub DoTextRepsGloss {
	my ($numReps, $repStrA, $repLenA, $repStartPosA, $txtR) = @_;
	my $line = $$txtR;

	for (my $i = $numReps - 1; $i >= 0; --$i)
		{
		if ($repLenA->[$i] > 0)
			{
			# substr($line, $pos, $srcLen, $repString);
			substr($line, $repStartPosA->[$i], $repLenA->[$i], $repStrA->[$i]);
			}
		}
	
	$$txtR = $line;
	}

# Truncate displayed link text.
# Set $truncLimit to about 28 for ToDo item links.
sub ShortenedLinkText {
    my ($text, $quoteChar, $truncLimit) = @_;
	my $quoteLen = length($quoteChar);
	if ($quoteLen > 0)
		{
		$truncLimit += 2 * length($quoteChar);
		$truncLimit -= 2;
		}
	
    my $filename = FileNameFromPath($text);

    my $len = length($filename);

	if ($len > $truncLimit)
		{
		my $offset = $len - $truncLimit;
		$filename = substr($filename, $offset);
		}

    return($filename);
}

use ExportAbove;
return 1;
