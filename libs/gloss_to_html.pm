# gloss_to_html.pm: take .txt files styled with Gloss, convert to standalone HTML.
# This is the "guts" of the process. It's in a module to allow different feedback:
# print, when called through the Perl program gloss2html.pl;
# and a WebSockets message, when called by intramine_glosser.pl.
# Most of Gloss is supported, see "Documentation/gloss2html.pl for standalone Gloss files.txt".

package gloss_to_html;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use utf8;
use HTML::Entities;
use File::Copy;
use File::Path;
use FileHandle;
use File::Slurp;
use Encode;
use Encode::Guess;
use URI::Escape;
use MIME::Base64 qw(encode_base64);
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use intramine_config;
use win_wide_filepaths;
use win_user32_local;
use ext;
use gloss;


{ ##### gloss_to_html scope to hide variables
my $fileOrDir;
my $inlineImages;
my $hoverGIFS;
my $context;
my $numFilesToConvert;
my $IMAGES_DIR;
my $COMMON_IMAGES_DIR;
my $CSS_DIR;
my $JS_DIR;
my $INLINE_IMAGES;
my $SUPPRESS_IMAGE_LINKS;
my $HashHeadingRequireBlankBefore;

my $CallbackNotify;			# Send a WebSockets message
my $USECALLBACK;

# The main call. If $callbackForMessageNotification is undef
# then print() is used for feedback. Otherwise it should be a callback
# to a sub that sends a WebSockets message. See intramine_glosser.pl for an example.
sub ConvertGlossToHTML {
	my ($fileOrDir_IN, $inlineImages_IN, $hoverGIFS_IN, $callbackForMessageNotification) = @_;
	$fileOrDir = $fileOrDir_IN;
	$inlineImages = $inlineImages_IN;
	$hoverGIFS = $hoverGIFS_IN;
	$CallbackNotify = $callbackForMessageNotification;
	$USECALLBACK = (defined($CallbackNotify)) ? 1 : 0;

	$fileOrDir =~ s!\\!/!g;
	my @listOfFilesToConvert;
	my $thingType = FileOrDirExistsWide($fileOrDir);
	if ($thingType == 1) # file
		{
		if ($fileOrDir =~ /\.txt$/i)
			{
			my $lastSlashPos = rindex($fileOrDir, '/');
			$context = substr($fileOrDir, 0, $lastSlashPos + 1);
			push @listOfFilesToConvert, $fileOrDir;
			}
		else
			{
			Output("Text files (.txt) only please!\n");
			return;
			}
		}
	elsif ($thingType == 2) # directory
		{
		$context = $fileOrDir;
		if ( rindex($fileOrDir, '/') != length($fileOrDir)-1)
			{
			$context .= '/';
			}
			
		my @allTopLevelItems = FindFileWide($context); # win_wide_filepaths.pm#FindFileWide()
		for (my $i = 0; $i < @allTopLevelItems; ++$i)
			{
			my $sourceFilePath = $context. $allTopLevelItems[$i];
			$sourceFilePath =~ s!\\!/!g;
			
			if (FileOrDirExistsWide($sourceFilePath) == 1
			&& $sourceFilePath =~ /\.txt$/i)
				{
				push @listOfFilesToConvert, $sourceFilePath;
				}
			}
		}
	else
		{
		Output("Could not find '$fileOrDir' on disk!\n");
		return;
		}

	$numFilesToConvert = @listOfFilesToConvert;
	if ($numFilesToConvert == 0)
		{
		Output("No .txt files found!\n");
		return;
		}

	LoadConfigValues(); # intramine_config.pm#LoadConfigValues()

	# Standard css, js, and image folders.
	$IMAGES_DIR = FullDirectoryPath('IMAGES_DIR');
	$COMMON_IMAGES_DIR = CVal('COMMON_IMAGES_DIR');
	if (FileOrDirExistsWide($COMMON_IMAGES_DIR) != 2)
		{
		Output("No common images dir, setting \$COMMON_IMAGES_DIR to ''\n");
		$COMMON_IMAGES_DIR = '';
		}

	$CSS_DIR = FullDirectoryPath('CSS_DIR');
	$JS_DIR = FullDirectoryPath('JS_DIR');
	$INLINE_IMAGES = CVal('GLOSS_SHOW_IMAGES');
	if ($inlineImages)
		{
		$INLINE_IMAGES = 1;
		}

	# Should popup or inlined images have a link to the
	# original image file? See the data/intramine_config.txt entry for more about that.
	$SUPPRESS_IMAGE_LINKS = CVal('SUPPRESS_IMAGE_LINKS');

	# For ATX-style headings that start with a '#', optionally require blank line before
	# (which is the default).
	$HashHeadingRequireBlankBefore = CVal("HASH_HEADING_NEEDS_BLANK_BEFORE");

	Output("Using JavaScript folder |$JS_DIR|\n");

	# Just a whimsy - for contents.txt files that start with CONTENTS, try to make it look
	# like an old-fashioned "special" table of contents. Initialized here.
	InitSpecialIndexFileHandling();

	my $fileWord = ($numFilesToConvert > 1) ? 'files' : 'file';
	Output("Converting $numFilesToConvert $fileWord from .txt to .html in |$context|\n");

	# Is there a file named "glossary.txt"? Load a list of glossary entries into memory.
	# Note the glossary file is converted later by ConvertTextToHTML().
	# The glossary file is loaded even if just one file is being converted.
	LoadGlossary($context);

	for (my $i = 0; $i < $numFilesToConvert; ++$i)
		{
		ConvertTextToHTML($context, $listOfFilesToConvert[$i]);
		}
	Output("Done.\n");
	}

# Default output is to just print.
# If a callback sub reference is supplied, it's called instead,
# See intramine_glosser.pl (the "Glosser" service) for an example.
# It writes the message to a file and sends a WebSockets message.
sub Output {
	my ($txt) = @_;

	if ($USECALLBACK)
		{
		$CallbackNotify->($txt);
		}
	else
		{
		print("$txt");
		}
	}

sub ConvertTextToHTML {
	my ($context, $filePath) = @_;
	Output("Converting |$filePath|\n");
	
	ClearDocumentGlossaryTermsSeen();

	# Initialize JS code for the image cache used with glossary popups.
	InitImageCache(); #gloss.pm#InitImageCache()
	
	my $contents = "";
	StartHtmlFile($filePath, $context, \$contents); # Start HTML, inline CSS
	GetPrettyText($context, $filePath, \$contents); # The text, in tables
	EndHtmlFile($filePath, \$contents);				# inline JavaScript, finish HTML
	
	my $outPath = $filePath;
	$outPath =~ s!txt$!html!i;
	
	WriteTextFileWide($outPath, $contents);
	#WriteUTF8FileWide($outPath, $contents); # Doesn't handle non-ASCII well. Sigh.
	}

# Get text file as a big string. Returns 1 if successful, 0 on failure.
sub LoadTextFileContents {
	my ($filePath, $octetsR) = @_;
	
	$$octetsR = ReadTextFileWide($filePath);
	if (!defined($$octetsR))
		{
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

sub OptionalCustomCSSforGlossExists {
	my ($fileName) = @_;
	my $result = 0;
	my $customFilePath = $CSS_DIR . $fileName;
	if (FileOrDirExistsWide($customFilePath))
		{
		$result = 1;
		}

	return($result);
	}

sub OptionalCustomJSforGlossExists {
	my ($fileName) = @_;
	my $result = 0;
	my $customFilePath = $JS_DIR . $fileName;
	if (FileOrDirExistsWide($customFilePath))
		{
		$result = 1;
		}

	return($result);
	}

sub StartHtmlFile {
	my ($filePath, $context, $contents_R) = @_;
	my $htmlStart = <<'FINIS';
<!doctype html>
<html lang="en">
<head>
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="apple-touch-fullscreen" content="yes" />
<meta name="google" content="notranslate">
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>_TITLE_</title>
FINIS
	my $fileName = FileNameFromPath($filePath);
	my $title = $fileName;
	$title =~ s!\.\w+$!!;
	$htmlStart =~ s!_TITLE_!$title!g;
	$$contents_R = $htmlStart;
	
	# CSS files, inlined.
	$$contents_R .= InlineCssForFile('main.css');
	#$$contents_R .= InlineCssForFile('forms.css');
	$$contents_R .= InlineCssForFile('non_cm_text.css');
	$$contents_R .= InlineCssForFile('non_cm_tables.css');
	$$contents_R .= InlineCssForFile('tooltip.css');
	$$contents_R .= InlineCssForFile('dragTOC.css');
	$$contents_R .= InlineCssForFile('lolight_custom.css');

	my $optionalCssFileName = 'im_gloss.css';
	if (OptionalCustomCSSforGlossExists($optionalCssFileName))
		{
		$$contents_R .= InlineCssForFile($optionalCssFileName);
		}
	
	my $htmlBodyTop = <<'ENDIT';
</head>
<body>
<!-- added for touch scrolling, an indicator -->
<div id="indicator"></div>
<hr id="rule_above_editor" />
<div id='scrollAdjustedHeight'>
ENDIT

	$$contents_R .= $htmlBodyTop;
	}

# This is a variant of intramine_viewer.pl#GetPrettyTextContents().
sub GetPrettyText {
	my ($context, $filePath, $contents_R) = @_;
	my $isGlossaryFile = IsGlossaryPath($filePath);
	
	ClearPlaceholdersAndGetTimestamp();

	my $octets;
	if (!LoadTextFileContents($filePath, \$octets))
		{
		Output("Error, could not load |$filePath|!\n");
		return;
		}
	
	# Pull raw (inline) HTML and footnotes.
	$octets = ReplaceHTMLAndFootnoteswithKeys($octets);

	my @lines = split(/\n/, $octets);

	my @jumpList;
	my $lineNum = 1;
	my %sectionIdExists; # used to avoid duplicated anchor id's for sections.
	my $orderedListNum = 0;
	my $secondOrderListNum = 0;
	my $unorderedListDepth = 0; # 0 1 2 for no list, top level, second level.
	my $justDidHeadingOrHr = 0;
	# Track whether within TABLE, and skip lists, hr, and heading if so.
	# We are in a table from seeing a line that starts with TABLE[_ \t:.-]? until a line with no tabs.
	my $inATable = 0;
	my $inACodeBlock = 0; 	# Set if see CODE on a line by itself,
							# continue until ENDCODE on a line by itself.
	my $lineIsBlank = 1;
	my $lineBeforeIsBlank = 1; 			# Initally there is no line before, so it's kinda blank:)
	my $inlineIndex = 1; # Key numbers start at 1.

	# Gloss, aka minimal memorable Markdown for your intranet.
	for (my $i = 0; $i < @lines; ++$i)
		{
		if (index($lines[$i], '__HH__') == 0)
			{
			my $lpos = -1;
			if (($lpos = index($lines[$i], '_L_')) > 0)
				{
				# Require $index to be in strict sequence. This
				# reduces errors caused by user entering a line
				# that mimics an __HH__ line used for inline HTML
				# removal and subsequent replacement.
				my $fullKey = substr($lines[$i], 0, $lpos);
				my $index = substr($fullKey, 6); # 6 == length('__HH__')
				if ($index =~ m!^\d+$! && $index == $inlineIndex
					&& InlineHTMLKeyIsDefined($fullKey))
					{
					++$inlineIndex;
					my $lineCount = substr($lines[$i], $lpos + 3);
					$lineNum += $lineCount;
					next;
					}
				}
			}

		# Blank out footnote markers and adjust line count
		if (index($lines[$i], '__FN__') == 0)
			{
			my $lpos = -1;
			my $rpos = -1;
			if (($lpos = index($lines[$i], '_L_')) > 0
			  && ($rpos = index($lines[$i], '_IND_')) > $lpos
			  && FootNoteIsDefined($lines[$i]))
				{
				$lpos += 3;
				my $lineCount = substr($lines[$i], $lpos, $rpos - $lpos);
				$lineNum += $lineCount;
				$lines[$i] = '';
				next;
				}
			}

		$lineBeforeIsBlank = $lineIsBlank;
		if ($lines[$i] eq '')
			{
			$lineIsBlank = 1;
			}
		else
			{
			$lineIsBlank = 0;
			}

		# See if we're entering or leaving a code block.
		# A code block starts with 'CODE' on a line by itself,
		# and ends with 'ENDCODE' on a line by itself.
		# CODE/ENDCODE is replaced by '_STARTCB_FL_',
		# and intervening lines have '_STARTCB_' added
		# at the beginning. Later, viewerStart.js#finishStartup()
		# will delete the markers and wrap lines in <pre> elements,
		# and lolight will style them when the page is ready.
		if (!$inATable)
			{
			if ($lines[$i] eq 'CODE')
				{
				$lines[$i] = '_STARTCB_FL_';
				$inACodeBlock = 1;
				}
			elsif ($lines[$i] eq 'ENDCODE')
				{
				$lines[$i] = '_STARTCB_FL_';
				$inACodeBlock = 0;
				}
			}

		# Highlight code blocks. Actual highlighting is done by
		# lolight.js for all class="lolight" elements.
		if ($inACodeBlock)
			{
			if ($lines[$i] ne '_STARTCB_FL_')
				{
				$lines[$i] = '_STARTCB_' . $lines[$i];
				}
			}

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
			
			# Hashed heading eg ## Heading.
			if ($lines[$i] =~ m!^#+\s+! && ($lineBeforeIsBlank || !$HashHeadingRequireBlankBefore))
				{
				Heading(\$lines[$i], undef, undef, \@jumpList, $i, \%sectionIdExists);
				$justDidHeadingOrHr = 1;
				}
			# Underlines -> hr or heading. Heading requires altering line before underline.
			elsif ($i > 0 && $lines[$i] =~ m!^[=~-][=~-]([=~-]+)$!)
				{
				my $underline = $1;
				if (length($underline) <= 2) # ie three or four total
					{
					Underline(\$lines[$i], $lineNum);
					}
				elsif ($justDidHeadingOrHr == 0) # a heading - put in anchor and add to jump list too
					{
					Heading(\$lines[$i], \$lines[$i-1], $underline, \@jumpList, $i, \%sectionIdExists);
					}
				else # treat like any ordinary line
					{
					my $rowID = 'R' . $lineNum;
					$lines[$i] = "<tr id='$rowID'><td n='$lineNum'></td><td>" . $lines[$i] . '</td></tr>';
					}
				$justDidHeadingOrHr = 1;
				}
			else
				{
				if ($isGlossaryFile)
					{
					if ($lines[$i] =~ m!^\s*(.+?[^\\]):!)
					#if ($lines[$i] =~ m!^([^:]+)\:!)
						{
						my $term = $1;
						my $anchorText = lc(AnchorForGlossaryTerm($term));
						my $contentsClass = 'h2';
						my $jlStart = "<li class='$contentsClass' im-text-ln='$lineNum'><a href='#$anchorText'>";
						my $jlEnd = "</a></li>";
						push @jumpList, $jlStart . $term . $jlEnd;
						}
					# For display, remove '\' from '\:'.
					$lines[$i] =~ s!\\:!:!g;
					}
				AddWebAndFileLinksToLine(\${lines[$i]}, $i, $context, $isGlossaryFile);
				if ($lines[$i] =~ m!(^|\s)(use|import)\s!)
					{
					#####AddModuleLinkToText(\${lines[$i]}, $dir, $serverAddr, $port_listen, $clientIsRemote);
					}
					
				# Put contents in table, use separate cells for line number and line proper.
				my $rowID = 'R' . $lineNum;
				$lines[$i] = "<tr id='$rowID'><td n='$lineNum'></td><td>" . $lines[$i] . '</td></tr>';
				$justDidHeadingOrHr = 0;
				}
			}
		else # in a table - note a glossary file should not contain any TABLE's.
			{
			AddWebAndFileLinksToLine(\${lines[$i]}, $i, $context, $isGlossaryFile);
			if ($lines[$i] =~ m!(^|\s)(use|import)\s!)
				{
				#####AddModuleLinkToText(\${lines[$i]}, $dir, $serverAddr, $port_listen, $clientIsRemote);
				}
				
			# Put contents in table, separate cells for line number and line proper.
			my $rowID = 'R' . $lineNum;
			$lines[$i] = "<tr id='$rowID'><td n='$lineNum'></td><td>" . $lines[$i] . '</td></tr>';
			$justDidHeadingOrHr = 0;
			}

		++$lineNum;
		}
	
	PutTablesInText(\@lines);
	
	# Put in links that reference headers within the current document.
	if (!$isGlossaryFile)
		{
		for (my $i = 0; $i < @lines; ++$i)
			{
			AddInternalLinksToLine(\${lines[$i]}, \%sectionIdExists);
			AddGlossaryHints(\${lines[$i]}, $context);
			}
		}
	else
		{
		for (my $i = 0; $i < @lines; ++$i)
			{
			AddGlossaryAnchor(\${lines[$i]});
			}
		}
	
	DoFinalLinkReps(\@lines);
	
	# Assemble the table of contents and text.
	# Special treatment (optional) for an contents.txt file with "contents" as the first line;
	# Style it up somewhat to more resemble a proper Table Of Contents.
	my $textContents = '';
	
	if (IsSpecialIndexFile($filePath, \@lines))
		{
		MakeSpecialIndexFileLookSpecial(\@lines, $context);
		my $oldPaperImage = '';
		
		GetOldBackgroundImage($context, \$oldPaperImage);
		$oldPaperImage =~ s!\n!!g;
		
		$textContents = "<div id='specialScrollTextRightOfContents' style='background-image: url(data:image/jpeg;base64,$oldPaperImage);'><div id='special-index-wrapper'><table>" . join("\n", @lines) . '</table></div></div>';
#		$textContents = "<div id='specialScrollTextRightOfContents'><div id='special-index-wrapper'><table>" . join("\n", @lines) . '</table></div></div>';
		}
	else
		{
		my $topSpan = '';
		if (defined($lines[0]))
			{
			$topSpan = "<span id='top-of-document'></span>";
			}
		
		if ($isGlossaryFile)
			{
			@jumpList = sort TocSort @jumpList;
			}
		unshift @jumpList, "<li class='h2' im-text-ln='1'><a href='#top-of-document'>TOP</a></li>";
		unshift @jumpList, "<ul>";
		$textContents = "<div id='scrollContentsList'>" . join("\n", @jumpList) . '</ul></div>';
		my $bottomShim = "<p id='bottomShim'></p>";

		# Replace raw HTML placeholders with original HTML. Add footnotes.
		my $numLines = @lines;
		ReplaceKeysWithHTMLAndFootnotes(\@lines, $numLines, $filePath);

		$textContents .= "<div id='scrollTextRightOfContents'>$topSpan<table class='imt'>" . join("\n", @lines) . "</table>$bottomShim</div>";
		}

	$$contents_R .= encode_utf8($textContents);
	}

{##### HTML hash and footnotes
# Text (Gloss) only, id inline HTML blocks and replace with fairly unique keys.
# Based on Text::MultiMarkdown's _HashHTMLBlocks();
my %g_html_blocks;
my %footnotes;
my %popupFootnotes;
my %newIdForOld;
my %referenceSeen; # defined if a reference id has already been seen

sub ReplaceHTMLAndFootnoteswithKeys {
	my ($text) = @_;

	%g_html_blocks = ();
	%footnotes = ();
	%popupFootnotes = ();
	%newIdForOld = ();
	%referenceSeen = ();
	my $block_tags_a = qr/p|div|h[1-6]|blockquote|pre|table|dl|ol|ul|script|noscript|form|fieldset|iframe|math|ins|del/;
	#my $block_tags_b = qr/p|div|h[1-6]|blockquote|pre|table|dl|ol|ul|script|noscript|form|fieldset|iframe|math/;
	my $htmlStart = qr/!/; # Inline HTML must start with a !
	my $index = 1;

	# Look for nested blocks, e.g.:
	# 	!<div>
	# 		<div>
	# 		tags for inner block must be indented.
	# 		</div>
	# 	</div>
	#
	# See "Gloss.html#Inline HTML" for details.
	$text =~ s{
				^						# start of line  (with /m)
				$htmlStart				# inline HTML marker start char
				(						# save in $1
					<($block_tags_a)	# start tag = $2
					\b					# word break
					(.*\n)*?			# any number of lines, minimally matching
					</\2>				# the matching end tag
					[ \t]*				# trailing spaces/tabs
					(?=\n+|\Z)			# followed by a newline or end of document
				)
			}{
				my $key = '__HH__' . $index++;
				$g_html_blocks{$key} = $1;
				my $nr_of_lines = $1 =~ tr/\n//;
				++$nr_of_lines; # num lines == num newlines + 1
				# Return key with number of lines in original appended
				# so we can adjust Viewer line count to match Editor.
				$key . '_L_' . $nr_of_lines;
			}egmx;

	# Pick up footnote text, put in link to where footnote will be mentioned.
	$index = 1;
	$text =~ s{
				^						# start of line  (with /m)
				(						# save in $1
				\[\^					# standard [^ starting a footnote
				(\w+)					# footnote id, $2
				]:						# close id plus colon
				.*?\n					# Remainder of first line
				(^.+?(\n|$))* 			# following lines, must not be empty
				)

	}{
		my $note = $1;
		my $idProper = $2;
		my $nr_of_lines = $note =~ tr/\n//;
		++$nr_of_lines;
		my $key = '__FN__' . $idProper . '_L_' . $nr_of_lines . '_IND_' . $index++;
		
		my $backLink = "<a href=\"#fnref_BACKREF_\" onclick=\"scrollBackToFootnoteRef(this); return(false);\"" . " class=\"footnote-backref\">↩</a>";

		chomp($note);
		$footnotes{$key} = "<div id='fn$idProper'>" . $note . ' ' . $backLink . "</div>";
		$popupFootnotes{'__FNP__' . $idProper} = $note;
		$key;
	}egmx;
	
	return($text);
	}

# Text (Gloss) only, replace HTML keys with orginal inline HTML.
# Everything in Gloss is in a <table> EXCEPT the inline HTML,
# so that's why we end a table and start a new table. Mostly.
# Footnote keys are not in the text, for them we notice a
# footnote reference such as [^27] and look for key fn27;
sub ReplaceKeysWithHTMLAndFootnotes {
	my ($linesA, $numLines, $filePath) = @_;
	my $previousLineForChunk = -1;
	my $footIndex = 1;
	my $newIndex = 1;

	for (my $i = 0; $i < $numLines; ++$i)
		{
		# Inline HTML.
		my $key = '';
		if (index($linesA->[$i], '__HH__') == 0)
			{
			my $lpos = -1;
			if (($lpos = index($linesA->[$i], '_L_')) > 0)
				{
				$key = substr($linesA->[$i], 0, $lpos);
				}
			}
		
		if (defined($g_html_blocks{$key}))
			{
			my $putEndTable = 1;
			my $putStartTable = 1;

			# Check for a preceding chunk.
			if ($i == $previousLineForChunk + 1)
				{
				$putEndTable = 0;
				}

			# Check for a following chunk.
			if ( $i < $numLines - 1
				&& index($linesA->[$i+1], '__HH__') == 0
				&& index($linesA->[$i+1], '_L_') > 0 )
				{
				$putStartTable = 0;
				}
			
			if ($putEndTable && $putStartTable)
				{
				$linesA->[$i] = "</table><div class='rawHTML'>" . $g_html_blocks{$key} . "</div><table class='imt'>";
				}
			elsif (!$putEndTable && !$putStartTable)
				{
				$linesA->[$i] = "<div class='rawHTML'>" . $g_html_blocks{$key} . "</div>";
				}
			elsif (!$putEndTable)
				{
				$linesA->[$i] = "<div class='rawHTML'>" . $g_html_blocks{$key} . "</div><table class='imt'>";
				}
			elsif (!$putStartTable) # possibly redundant:)
				{
				$linesA->[$i] = "</table><div class='rawHTML'>" . $g_html_blocks{$key} . "</div>";
				}

			$previousLineForChunk = $i;
			}

		# Footnote references. Skip refs with no actual corresponding footnote.
		if (index($linesA->[$i], '[^') >= 0) # footnote ref if it's [^stuff]no colon
			{
			$linesA->[$i] =~ s{
				(\[\^(\w+)](?=[^:]|$))
				}{
					if (defined($popupFootnotes{'__FNP__' . $2}))
						{
						if (!defined($referenceSeen{$2}))
							{
							$referenceSeen{$2} = 1;
							$newIndex = $footIndex++;
							$newIdForOld{$2} = $newIndex;
							}
						else
							{
							$referenceSeen{$2} += 1;
							$newIndex = $newIdForOld{$2};
							}
						my $noteId = 'fn' . $newIndex;
						my $refLineNumber = LineNumberFromRowText($linesA->[$i]);
						my $matchStartPos = $-[0];
						my $isFootnote = 1;
						if ($matchStartPos > 0)
							{
							my $beforeChar = substr($linesA->[$i], $matchStartPos - 1, 1);
							if ($beforeChar eq ' ' || $beforeChar eq "\t")
								{
								$isFootnote = 0; # Counts as a citation, no <sup>
								}
							}
						my $supStart = ($isFootnote) ? "<sup class='footenoteref'>": '';
						my $supEnd = ($isFootnote) ? "</sup>": '';
						my $refID = 'fnref' . $newIndex . '_' . $referenceSeen{$2};
						"$supStart<a href='#fn$newIndex' onclick=\"scrollToFootnote('$noteId', '$refLineNumber')\"  id='$refID'" . GlossedPopupForFootnote($2, $newIndex, $filePath) . ">\[$newIndex]</a>$supEnd";
						}
					else
						{
						$1;
						}
				}egx;
			}
		}

	# Restore footnotes at bottom. They have been removed from the text where defined.
	# Unreferenced footnotes/citations are not included in the output.
	my $numFootnotes = keys %footnotes;
	if ($numFootnotes)
		{
		push(@{$linesA}, "\n");
		push(@{$linesA}, "</table>");
		push(@{$linesA}, "<hr>");
		push(@{$linesA}, "<div class='allfootnotes'>\n");
		foreach my $key (sort { FootnoteIndexComp($a, $b) } keys %footnotes)
			{
			my $isReferenced = 0;
			if ($key =~ m!__FN__(\w+?)_L_!)
				{
				my $idProper = $1;
				if (defined($newIdForOld{$idProper}))
					{
					$isReferenced = 1;
					}
				}
			
			if ($isReferenced)
				{
				my $footnote = $footnotes{$key};
				$footnote = GlossedFootnote($footnote, $filePath);
				push(@{$linesA}, $footnote);
				}
			}
		push(@{$linesA}, "\n</div>\n<table class='imt'>");
		}

	%g_html_blocks = ();
	%footnotes = ();
	%popupFootnotes = ();
	%newIdForOld = ();
	%referenceSeen = ();
	}

sub ReplaceKeysWithHTMLInsideFootnotes {
	my ($linesA, $numLines) = @_;
	my $previousLineForChunk = -1;

	for (my $i = 0; $i < $numLines; ++$i)
		{
		# Inline HTML.
		my $key = '';
		my $hpos = -1;
		if (($hpos = index($linesA->[$i], '__HH__')) >= 0)
			{
			my $lpos = -1;
			if (($lpos = index($linesA->[$i], '_L_')) > $hpos)
				{
				$key = substr($linesA->[$i], $hpos, $lpos - $hpos);
				}
			}
		
		if (defined($g_html_blocks{$key}))
			{
			my $putEndTable = 1;
			my $putStartTable = 1;

			# Check for a preceding chunk.
			if ($i == $previousLineForChunk + 1)
				{
				$putEndTable = 0;
				}

			# Check for a following chunk.
			if ( $i < $numLines - 1
				&& index($linesA->[$i+1], '__HH__') >= 0
				&& index($linesA->[$i+1], '_L_') > 0 )
				{
				$putStartTable = 0;
				}
			
			# Pull out any trailing back reference anchor
			my $backRef = '';
			if ($linesA->[$i] =~ m!(\s*<a\s+href="#fnref[^"]+"\s+onclick.+?</a>)!)
				{
				$backRef = $1;
				}
			if ($putEndTable && $putStartTable)
				{
				$linesA->[$i] = "</table><div class='rawHTML'>" . $g_html_blocks{$key} . $backRef . "</div><table class='imt'>";
				}
			elsif (!$putEndTable && !$putStartTable)
				{
				$linesA->[$i] = "<div class='rawHTML'>" . $g_html_blocks{$key} . $backRef . "</div>";
				}
			elsif (!$putEndTable)
				{
				$linesA->[$i] = "<div class='rawHTML'>" . $g_html_blocks{$key} . $backRef . "</div><table class='imt'>";
				}
			elsif (!$putStartTable) # possibly redundant:)
				{
				$linesA->[$i] = "</table><div class='rawHTML'>" . $g_html_blocks{$key} . $backRef . "</div>";
				}

			$previousLineForChunk = $i;
			}
		}
	}

# Used to skip user-entered instances of __HH__... at a line start.
sub InlineHTMLKeyIsDefined {
	my ($key) = @_;
	my $result = defined($g_html_blocks{$key}) ? 1 : 0;
	return($result);
	}

sub FootNoteIsDefined {
	my ($key) = @_;
	my $result = defined($footnotes{$key}) ? 1 : 0;
	return($result);
	}

sub GlossedFootnote {
	my ($footnote, $filePath) = @_;
	my @footnoteLines = split(/\n/, $footnote);
	my $oldIndex = '';
	my $newIndex = '';

	# Find new index for footnote. Footnotes are renumbered to
	# be in sequence, according to sequence of footnote references
	# in the body text.
	if ($footnoteLines[0] =~ m!id=\'fn(\w+)!)
		{
		$oldIndex = $1;
		if (defined($newIdForOld{$oldIndex}))
			{
			$newIndex = $newIdForOld{$oldIndex};
			}
		else
			{
			$newIndex = $oldIndex;
			}
		}
	$footnoteLines[0] =~ s!^(<div\s+id=\'fn\w+\'>)\[\^(\w+)]:!$1\*\*$newIndex\*\*\.!;

	# Fix the back ref too, on the last line. Look for #fnref_BACKREF_
	my $lastLine = @footnoteLines;
	--$lastLine;
	if ($lastLine >= 0)
		{
		my $refID = '#fnref' . $newIndex . '_' . '1';
		$footnoteLines[$lastLine] =~ s!#fnref_BACKREF_!$refID!;
		}

	$footnote = join("\n", @footnoteLines);
	my $glossedFootnote;
	my $serverAddr = undef; #ServerAddress();
	my $mainServerPort = undef; #$server_port;
	my $contextDir = lc($filePath);
	$contextDir = DirectoryFromPathTS($contextDir);

	my $doNotCacheImages = 1;
	Gloss($footnote, $serverAddr, $mainServerPort, \$glossedFootnote, 0, $IMAGES_DIR, $COMMON_IMAGES_DIR, $contextDir, undef, undef, $doNotCacheImages);

	#my $foot = $glossedFootnote;

	# TO DO avoid re-splitting the footnote.
	# Rep inline HTML keys with HTML, preserving the back reference.
	@footnoteLines = split(/\n/, $glossedFootnote);
	my $numLines = @footnoteLines;
	ReplaceKeysWithHTMLInsideFootnotes(\@footnoteLines, $numLines);
	my $foot = join("\n", @footnoteLines);

	# Spurious LF's, stomp them with malice.
	$foot =~ s!\%0A!!gm;
	
	$foot =~ s!&quot;!"!gm;
	$foot =~ s!&#60;!<!gm;

	return($foot);
	}

sub GlossedPopupForFootnote {
	my ($idProper, $newIndex, $filePath) = @_;
	my $gloss = '';

	my $key = '__FNP__' . $idProper;
	if (defined($popupFootnotes{$key}))
		{
		my $footnote = $popupFootnotes{$key};
		$footnote =~ s!^\[\^(\w+)]:!\*\*$newIndex\*\*\.!;
		my $glossedFootnote;
		my $serverAddr = undef; #ServerAddress();
		my $mainServerPort = undef; #$server_port;
		my $contextDir = lc($filePath);
		$contextDir = DirectoryFromPathTS($contextDir);

		Gloss($footnote, $serverAddr, $mainServerPort, \$glossedFootnote, 0, $IMAGES_DIR, $COMMON_IMAGES_DIR, $contextDir, undef, undef);

		# TO DO avoid splitting the footnote.
		# Rep inline HTML keys with HTML, preserving the back reference.
		my @footnoteLines = split(/\n/, $glossedFootnote);
		my $numLines = @footnoteLines;
		ReplaceKeysWithHTMLInsideFootnotes(\@footnoteLines, $numLines);
		my $foot = join("\n", @footnoteLines);
		$foot = uri_escape_utf8("<div class='footDiv'>" . $foot . "</div>");

		$gloss = " onmouseover=\"loadAndShowHint('$foot', this, event, '600px', false, true);\"";
		}
	
	return($gloss);
	}

# Key: my $key = '__FN__' . $2 . '_L_' . $nr_of_lines . '_IND_' . $index++;
# Compare NEW index values to order by new index.
sub FootnoteIndexComp {
	my ($keyA, $keyB) = @_;
	my $indexA = -1;
	my $indexB = -1;
	my $pos = -1;
	my $rpos = -1;

	if (   ($pos = index($keyA, '__FN__')) == 0
		&& ($rpos = index($keyA, '_L_')) > 0 )
		{
		my $oldIndex = substr($keyA, $pos + 6, $rpos - $pos - 6);
		if (defined($newIdForOld{$oldIndex}))
			{
			$indexA = $newIdForOld{$oldIndex};
			}
		}

	if (   ($pos = index($keyB, '__FN__')) == 0
		&& ($rpos = index($keyB, '_L_')) > 0 )
		{
		my $oldIndex = substr($keyB, $pos + 6, $rpos - $pos - 6);
		if (defined($newIdForOld{$oldIndex}))
			{
			$indexB = $newIdForOld{$oldIndex};
			}
		}
	
	return($indexA <=> $indexB);
}

} ##### HTML hash and footnotes

sub LineNumberFromRowText {
	my ($text) = @_;
	my $lineNumber = 0;

	if ($text =~ m!<td n=['"](\d+)['"]>!)
		{
		$lineNumber = $1;
		}
	return($lineNumber);
}

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

	# Some "markdown": make TODO etc prominent.
	# CSS for .textSymbol has font-family: "Segoe UI Symbol", that font has better looking
	# symbols than most others on a std Windows box.
	# Beetle (lady bug): &#128030;
	# Bug (pretty): &#128029;
	# Bug (ugly): &#128027;
	# Ant: &#128028;
	# Note: &#9834;
	# Reminder (a bit of string): &#127895;
	# Uranus: &#9954; Yes, if you see this one in the text, Uranus is on the line....
	# Check mark: &#10003;
	# Heavy check mark: &#10004;
	# Ballot box with check: &#9745;
	# Wrench: &#128295;
	# OK hand sign: &#128076;
	# Hand pointing right: &#9755;
	# Light bulb: &#128161;
	# Smiling face: &#128578;
	
	$$lineR =~ s!(TODO)!<span class='notabene'>\&#127895;$1</span>!;		
	$$lineR =~ s!(REMINDERS?)!<span class='notabene'>\&#127895;$1</span>!;
	$$lineR =~ s!(NOTE)(\W)!<span class='notabene'>$1</span>$2!;
	$$lineR =~ s!(BUGS?)!<span class='textSymbol' style='color: Crimson;'>\&#128029;</span><span class='notabene'>$1</span>!;
	$$lineR =~ s!^\=\>!<span class='textSymbol' style='color: Green;'>\&#9755;</span>!; 			# White is \&#9758; but it's hard to see.
	$$lineR =~ s!^( )+\=\>!$1<span class='textSymbol' style='color: Green;'>\&#9755;</span>!;
	$$lineR =~ s!(IDEA\!)!<span class='textSymbol' style='color: Gold;'>\&#128161;</span>$1!;
	$$lineR =~ s!(FIXED|DONE)!<span class='textSymbolSmall' style='color: Green;'>\&#9745;</span>$1!;
	$$lineR =~ s!(WTF)!<span class='textSymbol' style='color: Chocolate;'>\&#128169;</span>$1!;
	$$lineR =~ s!\:\)!<span class='textSymbol' style='color: DarkGreen;'>\&#128578;</span>!; # or \&#9786;
	# Three or more @'s on a line by themselves produce a "flourish" section break.
	if ($$lineR =~ m!^@@@@*$!)
		{
		my $sectionImage = '';
		GetFlourishImage('', \$sectionImage, '_black', '100%');
		$$lineR =~ s!@@@@*!$sectionImage!;
		}

	# No good, messes up glossary popup: $$lineR =~ s!FLASH!F<span class='smallCaps'>LASH</span>!g;
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
			$$lineR = '<p class="outdent-unordered">' . '&nbsp;&bull; ' . $2 . '</p>'; # &#9830;(diamond) or &bull;
			}
		else
			{
			$$unorderedListDepthR = 2;
			$$lineR = '<p class="outdent-unordered-sub">' . '&#9702; ' . $2 . '</p>'; # &#9702; circle, &#9830;(diamond) or &bull;
			}
		}
	elsif ($$unorderedListDepthR > 0 && $$lineR =~ m!^\s+!)
		{
		$$lineR =~ s!^\s+!!;
		if ($$unorderedListDepthR == 1)
			{
			$$lineR = '<p class="outdent-unordered-continued">' . $$lineR . '</p>';
			}
		else
			{
			$$lineR = '<p class="outdent-unordered-sub-continued">' . $$lineR . '</p>';
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
		$$lineR = '<p class="' . $class . '">' . "$$listNumberR. $trailer" . '</p>';
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
			$$lineR = '<p class="' . $class . '">' . "$$listNumberR.$$subListNumberR $trailer" . '</p>';
			}
		else
			{
			my $class = (length($$subListNumberR) > 1) ? "ol-1-2": "ol-1-1";
			$$lineR = '<p class="' . $class . '">' . "$$listNumberR.$$subListNumberR $trailer" . '</p>';
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
				$$lineR = '<p class="' . $class . '">' . $$lineR . '</p>';
				}
			else
				{
				my $class = (length($$subListNumberR) > 1) ? "ol-1-2-c": "ol-1-1-c";
				$$lineR = '<p class="' . $class . '">' . $$lineR . '</p>';
				}
			}
		else
			{
			my $class = (length($$listNumberR) > 1) ? "ol-2-c": "ol-1-c";
			$$lineR = '<p class="' . $class . '">' . $$lineR . '</p>';
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

sub Underline {
	my ($lineR, $lineNum) = @_;
	
	# <hr> equivalent for three or four === or --- or ~~~
	# If it's === or ====, use a slightly thicker rule.
	my $imageName = ($$lineR =~ m!^\=\=\=\=?!) ? 'mediumrule4.png': 'slimrule4.png';
	my $enc64 = '';
	ImageBase64($imageName, $context, \$enc64);
	my $height = ($imageName eq 'mediumrule4.png') ? 6: 3;
	#$$lineR = "<tr><td n='$lineNum'></td><td class='vam'><img style='display: block;' src='$imageName' width='98%' height='$height' /></td></tr>";
	# "<img src=\"data:image/png;base64,$enc64\"$width$height  />";
	my $rowID = 'R' . $lineNum;
	$$lineR = "<tr id='$rowID'><td n='$lineNum'></td><td class='vam'><img style='display: block;' src=\"data:image/png;base64,$enc64\" width='98%' height='$height' /></td></tr>";
	}

# Heading(\$lines[$i], \$lines[$i-1], $underline, \@jumpList, $i, \%sectionIdExists);
# Note if doing underlined header then line before will have td etc, but
# if doing # header then the line we're on will be plain text.
# Note line counts as # header only if the #'s are followed by at least one space.
sub Heading {
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
	elsif ($$lineBeforeR =~ m!^(<tr id='R\d+'><td[^>]+></td><td>)(.*?)(</td></tr>)$!)
		{
		$beforeHeader = $1;
		$headerProper = $2;
		$afterHeader = $3;
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

	# Mark up as an ordinary line and return if no header pattern matched.
	if (!defined($headerProper) || $headerProper eq '')
		{
		++$i; # Convert to 1-based line number.
		my $rowID = 'R' . $i;
		$$lineR = "<tr id='$rowID'><td n='$i'></td><td>" . $$lineR . '</td></tr>';
		return;
		}
	
	my ($jumperHeader, $id) = GetJumperHeaderAndId($headerProper, $jumpListA, $sectionIdExistsH);

	my $contentsClass = 'h' . $headerLevel;
	
	# For ### hash headers we link to $i+1, for underlined link to $i.
	# im-text-ln is short for IntraMine text line.
	# Note $i is 0-based, but im-text-ln is 1-based, so $i refers to line $i-1.
	if ($isHashedHeader)
		{
		++$i; # $i is now a 1-based line number.
		my $rowID = 'R' . $i;
		$$lineR = "<tr id='$rowID'><td n='$i'></td><td>" . "<$contentsClass id=\"$id\">$headerProper</$contentsClass>" . '</td></tr>';
		}
	else
		{
		# Turn the underline into a tiny blank row, make line before look like a header
		$$lineR = "<tr class='shrunkrow'><td></td><td></td></tr>";
		$$lineBeforeR = "$beforeHeader<$contentsClass id=\"$id\">$headerProper</$contentsClass>$afterHeader";
		# Back out any "outdent" wrapper that might have been added, for better alignment.
		if ($jumperHeader =~ m!^<p!)
			{
			$jumperHeader =~ s!^<p[^>]*>!!;
			$jumperHeader =~ s!</p>$!!;
			}
		}
	
	my $jlStart = "<li class='$contentsClass' im-text-ln='$i'><a href='#$id'>";
	my $jlEnd = "</a></li>";
	push @$jumpListA, $jlStart . $jumperHeader . $jlEnd;
	}

# $jumperHeader is $headerProper (orginal header text) with HTML etc removed.
# $id also has unicode etc removed, and is forced to be unique.
sub GetJumperHeaderAndId {
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

# Sort @jumpList (above) based on anchor text. Typical @jumpList entry:
# <li class="h2" im-text-ln="41"><a href="#map_network_drive">Map network drive</a></li>
sub TocSort {
	my $result = -1;
	
	if ($a =~ m!\#([^\>]+)\>!)
		{
		my $aStr = $1;
		if ($b =~ m!\#([^\>]+)\>!)
			{
			my $bStr = $1;
			$result = $aStr cmp $bStr;;
			}
		}

	return($result);
}

# Where a line begins with TABLE, convert lines following TABLE that contain tab(s) into an HTML table.
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
		if ( $lines_A->[$i] =~ m!^<tr id='R\d+'><td[^>]+></td><td>TABLE(</td>|[_ \t:.-])! 
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
			$lines_A->[$idx-1] = $lines_A->[$idx-1] . "</tbody></table><table class='imt'><tbody>";
			} # if TABLE
		} # for (my $i = 0; $i <$numLines; ++$i)
	}

# Check first few rows, determine maximum number of columns and length of each cell.
sub GetMaxColumns {
	my ($idx, $numLines, $lines_A, $numColumnsR, $cellMaximumChars_A) = @_;
	
	my $rowsChecked = 0;
	while ($idx < $numLines && $lines_A->[$idx] =~ m!\t! && ++$rowsChecked <= 4)
		{
		$lines_A->[$idx] =~ m!^<tr id='R\d+'><td\s+n\=['"](\d+)['"]></td><td>(.+?)</td></tr>!;
		my $content = $2;
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

	if ($lines_A->[$tableStartIdx] =~ m!TABLE[_ \t:.-]+\S!)
		{
		# Use supplied text after TABLE as table "caption".
		if ($lines_A->[$tableStartIdx] =~ m!^(<tr id='R\d+'><td[^>]+></td><td>)TABLE[_ \t:.-]+(.+?)(</td></tr>)!)
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
				$lines_A->[$tableStartIdx] = "$pre$post</tbody></table><table class='bordered imt'><caption>$caption</caption><thead>";
				}
			else
				{
				$lines_A->[$tableStartIdx] = "$pre&nbsp; &nbsp;&nbsp; &nbsp;&nbsp;<span class='fakeCaption'>$caption</span>$post</tbody></table><table class='bordered imt'><thead>";
				}
			}
		else
			{
			# Probably a maintenance failure. Struggle on.
			$lines_A->[$tableStartIdx] = "<tr class='shrunkrow'><td></td><td></td></tr></tbody></table><table class='bordered imt'><thead>";
			}
		}
	else # no caption
		{
		$lines_A->[$tableStartIdx] = "<tr class='shrunkrow'><td></td><td></td></tr></tbody></table><table class='bordered imt'><thead>";
		}			
	}

sub DoTableRows {
	my ($idx, $numLines, $lines_A, $numColumns, $alignmentString_H) = @_;

	my $isFirstTableContentLine = 2; # Allow up to two headers rows up top.
	while ($idx < $numLines && $lines_A->[$idx] =~ m!\t!)
		{
		# Grab line number and content.
		$lines_A->[$idx] =~ m!^<tr id='R\d+'><td\s+n\=['"](\d+)['"]></td><td>(.+?)</td></tr>!;
		my $lineNum = $1;
		my $content = $2;
		
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
			$newLine = "<tr class='reallyshrunkrow'><td></td>";
			$newLine .= "<td></td>"x$numColumns;
			$newLine .= "</tr>";
			}
		else
			{
			# Leftmost cell is for line number.
			my $rowID = 'R' . $lineNum;
			$newLine = "<tr id='$rowID'><$cellName n='$lineNum'></$cellName>";
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



{ ##### Special handling for contents.txt table of CONTENTS files
my $IndexGetsSpecialTreatment;
my $SpecialIndexFileName;
my $ContentTriggerWord;
my $SpecialIndexFont;
my $SpecialIndexFlourishImage;
my $FlourishImageHeight;
my $SpecialImageBackgroundImage;

sub InitSpecialIndexFileHandling {
	$IndexGetsSpecialTreatment = CVal('INDEX_GETS_SPECIAL_TREATMENT');
	$SpecialIndexFileName = CVal('SPECIAL_INDEX_NAME');
	$ContentTriggerWord = CVal('SPECIAL_INDEX_EARLY_TEXT_MUST_CONTAIN');
	$SpecialIndexFont = CVal('SPECIAL_INDEX_FONT');
	$SpecialIndexFlourishImage = CVal('SPECIAL_INDEX_FLOURISH');
	$FlourishImageHeight = CVal('SPECIAL_INDEX_FLOURISH_HEIGHT');
	$SpecialImageBackgroundImage = CVal('SPECIAL_INDEX_BACKGROUND');
	}

sub IsSpecialIndexFile {
	my ($filePath, $lines_A) = @_;
	my $result = 0;
	
	if ($IndexGetsSpecialTreatment)
		{
		if ($filePath =~ m!$SpecialIndexFileName$!i)
			{
			my $numLines = @$lines_A;
			if ($numLines && $lines_A->[0] =~ m!$ContentTriggerWord!
				&& $numLines <= 100 )
				{
				$result = 1;
				}
			}
		}
	
	return($result);
	}
	
sub MakeSpecialIndexFileLookSpecial {
	my ($lines_A, $contextDir) = @_;
	
	my $numLines = @$lines_A;
	if ($numLines)
		{
		my $flourishImage = '';
		GetFlourishImage($contextDir, \$flourishImage, '', '100%');
		$lines_A->[0] =~ s!(<td>)(.*?$ContentTriggerWord.*?)(</td>)!<th align='center'><span id='toc-line'>$2</span><br/>$flourishImage</th>!i;
		}
	}

sub GetFlourishImage {
	my ($contextDir, $imageR, $suffix, $forcedWidth) = @_;
	my $flourishImageName = $SpecialIndexFlourishImage;
	if ($suffix ne '' && $flourishImageName =~ m!^(.+?)\.(\w+)$!)
		{
		my $baseName = $1;
		my $extension = $2;
		$flourishImageName = $baseName . $suffix . '.' . $extension;
		}
	ImageLink($flourishImageName, $contextDir, $imageR, $forcedWidth);
	}

sub GetOldBackgroundImage {
	my ($contextDir, $imageR) = @_;
	
	ImageBase64($SpecialImageBackgroundImage, $contextDir, $imageR);

	#ImageLink($SpecialImageBackgroundImage, $contextDir, $imageR);
	}
} ##### Special handling for contents.txt table of CONTENTS files

{ ##### AutoLink for Gloss
my $line;
my $revLine;
my $contextDir;
my $len;

# Placeholder links on each line.
my @repStr;
my @repLen;
my @repStartPos;
my @linkIsPotentiallyTooLong; # For unquoted links to text headers, we grab 100 chars, which might be too much.

# Final links, replacing placeholders on all lines.
my %LineRepsForMarkers; # $LineRepsForMarkers->{line number}{unique marker} = file or image link.
my $Timestamp; # used to help make markers unique
my $longestSourcePath;
my $bestVerifiedPath;

sub ClearPlaceholdersAndGetTimestamp {
	%LineRepsForMarkers = ();
	$Timestamp = DateTimeForFileName();
}

# This is a simplified version of intramine_linker.pl#AddWebAndFileLinksToLine().
sub AddWebAndFileLinksToLine {
	my ($txtR, $lineNumber, $theContextDir, $isGlossaryFile) = @_;

	$line = $$txtR;
	$len = length($line);
	$revLine = scalar reverse($line);
	$contextDir = $theContextDir;
	
	# These replacements are more easily done in reverse order to avoid throwing off the start/end.
	@repStr = ();
	@repLen = ();
	@repStartPos = ();
	@linkIsPotentiallyTooLong = (); # For unquoted links to text headers, we grab 100 chars, which might be too much.

	# Look for all of: single or double quoted text, a potential file extension, or a url.
	EvaluateLinkCandidates($isGlossaryFile);
	
	# Do all reps in reverse order at end.
	my $numReps = @repStr;
	if ($numReps)
		{
		DoPlaceholderLinkReps($numReps, $lineNumber, $txtR);
		}
	}

sub EvaluateLinkCandidates {
	my ($isGlossaryFile) = @_;
	
	my $previousEndPos = 0;
	my $previousRevEndPos = $len;
	my $haveGoodMatch = 0; # check-back distance is not adjusted if there is no good current match.

	# Look for:
	# ".ext#optional heading"
	# 'ext#optional heading'
	# .ext up to 7 chars
	# http:// or https://
	while ($line =~ m!((\[([^\]]+)]\((https?://[^)]+)\))|(\"([^"]+)\.\w+(#[^"]+)?\")|(\'([^']+)\.\w+(#[^']+)?\')|\.(\w\w?\w?\w?\w?\w?\w?)(\#[A-Za-z0-9_:]+)?|((https?://([^\s)<\"](?\!ttp:))+)))!g)
		{
		my $startPos = $-[0];	# this does include the '.', beginning of entire match
		my $endPos = $+[0];		# pos of char after end of entire match
		my $ext = $1;			# double-quoted chunk, or extension (plus any anchor), or url
		my $doMarkdownLink = (defined($3)) ? 1 : 0;
		my $markdownDisplayText = ($doMarkdownLink) ? $3: '';
		my $markdownLink = ($doMarkdownLink) ? $4: '';

		$haveGoodMatch = 0;
		
		my $haveQuotation = ((index($ext, '"') == 0) || (index($ext, "'") == 0));
		my $quoteChar = '';
		my $badQuotation = 0;
		if ($haveQuotation)
			{
			# Check for non-word or BOL before first quote, non-word or EOL after second.
			if ($startPos > 0)
				{
				my $charBefore = substr($line, $startPos - 1, 1);
				if ($charBefore !~ m!\W!)
					{
					$badQuotation = 1;
					}
				else
					{
					# Check we aren't inside a generated header id such as
					# <h3 id="gloss2html.pl#AddWebAndFileLinksToLine()_refactor"...
					if ($startPos >= 7)
						{
						if (substr($line, $startPos - 3, 3) eq "id=")
							{
							$badQuotation = 1;
							}
						}
					}
				}
			if ($endPos < $len)
				{
				my $charAfter = substr($line, $endPos, 1);
				if ($charAfter !~ m!\W!)
					{
					$badQuotation = 1;
					}
				}

			# Trim quotes and pick up $quoteChar.
			$quoteChar =  substr($ext, 0, 1);
			$ext = substr($ext, 1);
			$ext = substr($ext, 0, length($ext) - 1);
			}
		
		if ($badQuotation)
			{
			pos($line) = $startPos + 1;
			}
		else
			{
			my $haveURL = (index($ext, 'http') == 0);
			my $anchorWithNum = (!$haveQuotation && !$haveURL && defined($9)) ? $12 : ''; # includes '#'
			# Need to sort out actual anchor if we're dealing with a quoted chunk.
			if ($haveQuotation && !$haveURL)
				{
				if ($ext =~ m!(\#[^"]+)!)
					{
					$anchorWithNum = $1; # includes '#'
					}
				}
			my $url = $haveURL ? $ext : '';
			my $extProper = (!$haveQuotation && !$haveURL) ? substr($ext, 1) : '';
			# Get file extension if it's a quoted chunk (many won't have an extension).
			if ($haveQuotation && !$haveURL)
				{
				if ($ext =~ m!\.(\w\w?\w?\w?\w?\w?\w?)(\#|$)!)
					{
					$extProper = $1;
					}
				}
			if ($anchorWithNum ne '' && !$haveURL && !$haveQuotation)
				{
				my $pos = index($extProper, '#');
				$extProper = substr($extProper, 0, $pos);
				}
			
			# "$haveTextExtension" includes docx|pdf
			my $haveTextExtension = (!$haveURL && IsTextDocxPdfExtensionNoPeriod($extProper));
			my $haveImageExtension = $haveTextExtension ? 0 : (!$haveURL && IsImageExtensionNoPeriod($extProper));
			my $haveVideoExtension = (!$haveURL && IsVideoExtensionNoPeriod($extProper));
			my $haveGoodExtension = ($haveTextExtension || $haveImageExtension || $haveVideoExtension); # else URL
			
			my $linkIsMaybeTooLong = 0;
			
			# Potentially a text file mention or an image.
			if ($haveGoodExtension)
				{
				$haveGoodMatch = CheckForTextOrImageFile($startPos, $previousRevEndPos, $ext, $extProper,
							$haveQuotation, $haveTextExtension, $haveVideoExtension,
							$quoteChar, $anchorWithNum, $isGlossaryFile);
				} # if known extensions
			elsif ($haveURL)
				{
				PackUpUrlRep($startPos, $haveQuotation, $quoteChar, $url);
				$haveGoodMatch = 1;
				}
			elsif ($doMarkdownLink)
				{
				PackUpMarkdownLinkRep($startPos, $ext, $markdownDisplayText, $markdownLink);
				$haveGoodMatch = 1;
				}
			
			if ($haveGoodMatch)
				{
				$previousEndPos = $endPos;
				$previousRevEndPos = $len - $previousEndPos - 1; # Limit backwards extent of 2nd and subsequent searches.
				}
			elsif (!$haveGoodMatch && $haveQuotation)
				{
				pos($line) = $startPos + 1;
				}
			}
		} # while another extension matched
	}

# Look for matching text or image or video file.
sub CheckForTextOrImageFile {
	my ($startPos, $previousRevEndPos, $ext, $extProper, $haveQuotation,
		$haveTextExtension, $haveVideoExtension, $quoteChar, $anchorWithNum, $isGlossaryFile) = @_;
	my $linkIsMaybeTooLong = 0;
	my $checkStdImageDirs = (!$haveTextExtension) ? 1 : 0;
	
	# To allow for spaces in #anchors where file#anchor hasn't been quoted, grab the
	# 100 chars following '#' here, and sort it out on the other end when going to
	# the anchor. Only for txt files.
	if ($extProper =~ m!txt|html?!i && !$haveQuotation && $anchorWithNum ne '')
		{
		my $anchorPosOnLine = $startPos;
		$anchorPosOnLine = index($line, '#', $anchorPosOnLine);
		$anchorWithNum = substr($line, $anchorPosOnLine, 100);
		# Remove any HTML junk there.
		$anchorWithNum =~ s!\</[A-Za-z]+\>!!g;
		$anchorWithNum =~ s!\<[A-Za-z]+\>!!g;				
		$linkIsMaybeTooLong = 1;
		}
	
	my $fileTail = '.' . $extProper;
	my $fileTailLength = length($fileTail);
	my $anchorLength = length($anchorWithNum);
	my $periodPlusAfterLength = $fileTailLength + $anchorLength;

	$longestSourcePath = '';
	$bestVerifiedPath = '';

	# Get quotes out of the way first:
	# $haveQuotation: set $longestSourcePath, $bestVerifiedPath, $doingQuotedPath
	# to match approach just below if quote follows an extension mention.
	my $doingQuotedPath = 0;
	if ($haveQuotation)
		{
		my $pathToCheck = $ext;
		my $pos = index($pathToCheck, '#');
		if ($pos > 0)
			{
			$pathToCheck = substr($pathToCheck, 0, $pos);
			}
		#my $verifiedPath = FullPathInContextNS($pathToCheck, $contextDir);
		my $verifiedPath = FullPathForFile($pathToCheck, $contextDir);
		if ($verifiedPath ne '')
			{
			$longestSourcePath = $pathToCheck;
			$bestVerifiedPath = $verifiedPath;
			$doingQuotedPath = 1;
			}
		elsif ($checkStdImageDirs && $pathToCheck ne '')
			{
			if (FileOrDirExistsWide($IMAGES_DIR . $pathToCheck) == 1)
				{
				$longestSourcePath = $pathToCheck;
				$verifiedPath = $IMAGES_DIR . $pathToCheck;
				$bestVerifiedPath = $verifiedPath;
				$doingQuotedPath = 1;
				}
			elsif ($COMMON_IMAGES_DIR ne '' && FileOrDirExistsWide($COMMON_IMAGES_DIR . $pathToCheck) == 1)
				{
				$longestSourcePath = $pathToCheck;
				$verifiedPath = $COMMON_IMAGES_DIR . $pathToCheck;
				$bestVerifiedPath = $verifiedPath;
				$doingQuotedPath = 1;
				}
			}
		}
	
	my $revPos = $len - $startPos - 1 + 1; # extra +1 there to skip '.' before the extension proper.
	
	# Extract the substr to search.
	# (Note to self, using ^.{}... might be faster.)
	my $revStrToSearch = substr($revLine, $revPos, $previousRevEndPos - $revPos + 1);
	
	# Good break points for hunt are [\\/ ], and [*?"<>|\t] end the hunt. NOTE not accounting for paths in "" or '' yet.
	# For image files only, we look in a couple of standard places for just the file name.
	# This can sometimes be expensive, but we look at the standad locations only until
	# either a slash is seen or a regular mention is found.
	my $commonDirForImageName = ''; # Set if image found one of the std image dirs
	my $imageName = ''; 			# for use if image found in one of std image dirs
	
	GetLongestGoodPath($doingQuotedPath, $checkStdImageDirs, $revStrToSearch, $fileTail,
					\$imageName, \$commonDirForImageName);
	
	my $haveGoodMatch = 0;
	if (($longestSourcePath ne '' || $commonDirForImageName ne '')
		&& ($extProper =~ m!txt|(html?)$!i || $extProper =~ m!(png|jpeg|jpg|gif|webp)$!i
		|| $haveVideoExtension))
		{
		my $linkType = 'file'; # For CodeMirror
		my $usingCommonImageLocation = 0;
		if ($longestSourcePath eq '')
			{
			$longestSourcePath = $imageName;
			$usingCommonImageLocation = 1;
			}
		my $repString = '';
		
		if ($haveTextExtension)
			{
			GetTextFileRep($haveQuotation, $quoteChar, $extProper, $longestSourcePath,
							$anchorWithNum, \$repString);
			}
		# Video is limited to the /images/ subdirectory for the moment.
		elsif ($haveVideoExtension && LocationIsImageSubdirectory($bestVerifiedPath, $contextDir))
			{
			GetVideoFileRep($haveQuotation, $quoteChar, $usingCommonImageLocation,
							$imageName, $isGlossaryFile, \$repString);
			}
		else # currently only image extension
			{
			$linkType = 'image'; # For CodeMirror
			GetImageFileRep($haveQuotation, $quoteChar, $usingCommonImageLocation,
							$imageName, $isGlossaryFile, \$repString);
			}
			
		my $repLength = length($longestSourcePath) + $anchorLength;
		if ($haveQuotation)
			{
			$repLength += 2; # for the quotes
			}
		
		my $repStartPosition = ($haveQuotation) ? $startPos : $startPos - $repLength + $periodPlusAfterLength;
		push @repStr, $repString;
		push @repLen, $repLength;
		push @repStartPos, $repStartPosition;
		push @linkIsPotentiallyTooLong, $linkIsMaybeTooLong;
		$haveGoodMatch = 1;
		}
	
	return($haveGoodMatch);
	}

sub GetLongestGoodPath {
	my ($doingQuotedPath, $checkStdImageDirs, $revStrToSearch, $currentPath,
		$imageNameR, $commonDirForImageNameR) = @_;
	my $trimmedCurrentPath = $currentPath;
	my $slashSeen = 0; 				# stop checking standard locs for image if a dir slash is seen
	my $checkToEndOfLine = 0;
	my $currentRevPos = ($doingQuotedPath) ? -1: 0;
	my $prevSubRevPos = 0;
	
	# Look for next space or slash or end in the reversed str. We don't go into this loop
	# if balanced quotes around path have been found just above.
	while ($currentRevPos >= 0 || $checkToEndOfLine)
		{
		if ($checkToEndOfLine)
			{
			$currentRevPos = $len;
			}
		else
			{
			if ($revStrToSearch =~ m!^.{$prevSubRevPos}.*?([ \t/\\,\(])!s)
				{
				$currentRevPos = $-[1];
				my $charSeen = $1;
				if ($charSeen eq "/" || $charSeen eq "\\")
					{
					$slashSeen = 1;
					}
				}
			else
				{
				$currentRevPos = -1;
				}
			}
		
		if ($currentRevPos >= 0) 
			{
			# substr EXPR,OFFSET,LENGTH,REPLACEMENT
			# Pick up next reversed term, including space.
			my $nextRevTerm = substr($revStrToSearch, $prevSubRevPos, $currentRevPos - $prevSubRevPos + 1);
			# Drop out if we see a double quote.
			if (index($nextRevTerm, '"') >= 0)
				{
				last;
				}
			# Reversing puts the matched space at beginning of $nextTerm.
			my $nextTerm = scalar reverse($nextRevTerm);
			my $trimOffset = ($checkToEndOfLine) ? 0 : 1;
			# Trim only "stop" characters, space tab etc.
			if ($trimOffset && !IsStopCharacter(substr($nextTerm, 0, 1)))
				{
				$trimOffset = 0;
				}
			my $trimmedNextTerm = substr($nextTerm, $trimOffset); # trim space etc at start, unless checking to end
			$trimmedCurrentPath = $trimmedNextTerm . $currentPath;
			$currentPath = $nextTerm . $currentPath;

			#my $verifiedPath = FullPathInContextNS($trimmedCurrentPath, $contextDir);
			my $verifiedPath = FullPathForFile($trimmedCurrentPath, $contextDir);
			
			if ($verifiedPath ne '')
				{
				$longestSourcePath = $trimmedCurrentPath;
				$bestVerifiedPath = $verifiedPath;
				}
			elsif ($checkStdImageDirs && $longestSourcePath eq '')
				{
				if (FileOrDirExistsWide($IMAGES_DIR . $trimmedCurrentPath) == 1)
					{
					$$imageNameR = $trimmedCurrentPath;
					$$commonDirForImageNameR = $IMAGES_DIR;
					$bestVerifiedPath = $$commonDirForImageNameR . $$imageNameR;
					$checkStdImageDirs = 0;
					}
				elsif ($COMMON_IMAGES_DIR ne '' && FileOrDirExistsWide($COMMON_IMAGES_DIR . $trimmedCurrentPath) == 1)
					{
					$$imageNameR = $trimmedCurrentPath;
					$$commonDirForImageNameR = $COMMON_IMAGES_DIR;
					$bestVerifiedPath = $$commonDirForImageNameR . $$imageNameR;
					$checkStdImageDirs = 0;
					}
				}
			}
		
		if ($checkToEndOfLine)
			{
			last;
			}
		elsif ($currentRevPos >= 0)
			{
			$prevSubRevPos = $currentRevPos + 1;
			}
		# else we're dropping out of the while soon, but as a last step check the whole line
		elsif (!$checkToEndOfLine)
			{
			$checkToEndOfLine = 1;
			}
		
		if ($slashSeen)
			{
			$checkStdImageDirs = 0;
			}
		} # while ($currentRevPos >= 0 ...
	}

# Stop chars limit search for next word to add to the string being tested as a target specifier.
sub IsStopCharacter {
	my ($char) = @_;
	return($char eq ' ' || $char eq "\t" || $char eq '/' || $char eq "\\" || $char eq ',' || $char eq '(' || $char eq '<' || $char eq '>' || $char eq ':' || $char eq '|');
	}

sub GetTextFileRep {
	my ($haveQuotation, $quoteChar, $extProper, $longestSourcePath,
		$anchorWithNum, $repStringR) = @_;

	my $editLink = '';
	my $viewerPath = $bestVerifiedPath;
	my $editorPath = $bestVerifiedPath;
	$viewerPath =~ s!\\!/!g;
	$viewerPath =~ s!%!%25!g;
	$viewerPath =~ s!\+!\%2B!g;

	# If it's a relative link containing '../' or './', keep from there to the end.
	# Else just the file name from $viewerPath, with a './' in front.
	# Convert txt to html too.
	#$viewerPath = FileNameFromPath($viewerPath);
	if ($viewerPath =~ m!(\.\.?/)(.+)$!)
		{
		my $relPath = $1 . $2;
		$viewerPath = $relPath;
		}
	else
		{
		$viewerPath = FileNameFromPath($viewerPath);
		$viewerPath = './' . $viewerPath;
		}

	$viewerPath =~ s!\.txt!.html!i;
	
	$editorPath =~ s!\\!/!g;
	$editorPath =~ s!%!%25!g;
	$editorPath =~ s!\+!\%2B!g;
	
	my $displayedLinkName = $longestSourcePath . $anchorWithNum;
	if ($haveQuotation)
		{
		$displayedLinkName = $quoteChar . $displayedLinkName . $quoteChar;
		}
	
	$$repStringR = "<a href=\"$viewerPath$anchorWithNum\" target=\"_blank\">$displayedLinkName</a>";
	}

sub GetVideoFileRep {
	my ($haveQuotation, $quoteChar, $usingCommonImageLocation, $imageName,
		$isGlossaryFile, $repStringR) = @_;
	
	#$bestVerifiedPath =~ s!%!%25!g;
	#$bestVerifiedPath =~ s!\+!\%2B!g;

	my $fileName = lc(FileNameFromPath($bestVerifiedPath));
	my $acceptedPath = lc($contextDir . 'images/' . $fileName);

	MakeHTMLFileForVideo($acceptedPath);
	GetVideoRep($haveQuotation, $quoteChar, 0,
							$acceptedPath, $acceptedPath, $repStringR, $inlineImages);
	
	}

sub GetVideoRep {
	my ($haveQuotation, $quoteChar, $usingCommonImageLocation, $longestSourcePath, $properCasedPath, $repStringR, $inlineImages) = @_;

	my $fullPath = $longestSourcePath;
	# Change from video extension to .html to call the HTML stub file.
	$fullPath =~ s!\.\w+$!.html!;
	$fullPath =~ s!\\!/!g;
	#$fullPath =~ s!%!%25!g;	
	$fullPath =~ s!\+!\%2B!g;
	my $htmlFileName = FileNameFromPath($fullPath);
	$htmlFileName =~ s!\.\w+$!.html!;

	my $displayedLinkName = $properCasedPath;
    # In a ToDo item a full link can be too wide too often.
    # So shorten the displayed link name to just the file name with anchor.
	# $inlineImages true means we're doing eg glossary definitions, where
	# we have lots of room. If it's false, we're doing Gloss in a ToDo
	# item, which is narrow.
	my $maxDisplayedLinkNameLength = ($inlineImages) ? 72 : 28;
    $displayedLinkName = ShortenedText($displayedLinkName, $quoteChar, $maxDisplayedLinkNameLength);

	$$repStringR = "<a href='./images/$htmlFileName' target='_blank'>$displayedLinkName</a>";
	}

# Truncate displayed link text.
# Set $truncLimit to about 28 for ToDo item links.
sub ShortenedText {
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

sub GetImageFileRep {
	my ($haveQuotation, $quoteChar, $usingCommonImageLocation, $imageName,
		$isGlossaryFile, $repStringR) = @_;
	
	$bestVerifiedPath =~ s!%!%25!g;
	$bestVerifiedPath =~ s!\+!\%2B!g;
	
	#my $fullPath = $bestVerifiedPath;
	#my $imagePath = "http://$host:$port/$fullPath";
	my $originalPath = $usingCommonImageLocation ? $imageName : $longestSourcePath;
	my $displayedLinkName = $originalPath;
	if ($haveQuotation)
		{
		$displayedLinkName = $quoteChar . $displayedLinkName . $quoteChar;
		}
	#my $leftHoverImg = "<img src='http://$host:$port/hoverleft.png' width='17' height='12'>"; # actual width='32' height='23'>";
	#my $rightHoverImg = "<img src='http://$host:$port/hoverright.png' width='17' height='12'>";
	#my $imageOpenHref = "http://$host:$port/Viewer/?href=$fullPath";
	#$repString = "<a href='$imageOpenHref' target='_blank' onmouseOver=\"showhint('<img src=&quot;$imagePath&quot;>', this, event, '500px', true);\">$leftHoverImg$displayedLinkName$rightHoverImg</a>";
	
	$bestVerifiedPath = "./$bestVerifiedPath";
	
	if (($INLINE_IMAGES || $isGlossaryFile) && !($bestVerifiedPath =~ m!\.gif!i && $hoverGIFS))
		{
		my $bin64Img = '';
		ImageLink($originalPath, $contextDir, \$bin64Img);
		if ($SUPPRESS_IMAGE_LINKS)
			{
			$$repStringR = $bin64Img;
			}
		else
			{
			$$repStringR = "<a href='$bestVerifiedPath' target='_blank'>$bin64Img</a>";
			}
		}
	else
		{
		my $bin64Img = '';
		ImageLinkQuoted($originalPath, $contextDir, \$bin64Img);
		$bin64Img =~ s!\n!!g; # JS doesn't like \n inside the image string
		my $bin64LeftHover = '';
		ImageLink('hoverleft.png', $contextDir, \$bin64LeftHover, 17, 12);
		my $bin64RightHover = '';
		ImageLink('hoverright.png', $contextDir, \$bin64RightHover, 17, 12);
		if ($SUPPRESS_IMAGE_LINKS)
			{
			$$repStringR = "<span href='$bestVerifiedPath' onmouseOver=\"showhint('$bin64Img', this, event, '500px', true);\">$bin64LeftHover$displayedLinkName$bin64RightHover</span>";
			}
		else
			{
			$$repStringR = "<a href='$bestVerifiedPath' target='_blank' onmouseOver=\"showhint('$bin64Img', this, event, '500px', true);\">$bin64LeftHover$displayedLinkName$bin64RightHover</a>";
			}
		}
	}

sub PackUpUrlRep {
	my ($startPos, $haveQuotation, $quoteChar, $url) = @_;
	# Trim any trailing punctuation character from $url - period, comma etc. Typically those are not part
	# of a URL, eg "if you go to http://somewhere.com/things, you will find...".
	# (Only    .^$*+?()[{\|  need escaping in regex outside of a character class, and only  ^-]\  inside one).
	# If it's a quoted chunk, mind you, trust the user.
	if (!$haveQuotation)
		{
		# First trim any trailing "&quot;..." that might have come along for the ride.
		# Along with a few spurious chars, things like |&amp;quot;&gt;'|.
		$url =~ s!\&amp;quot;.?.?.?.?.?$!!;
		$url =~ s![.,:;?\!\)\] \t\-]$!!;
		}
	my $displayedURL = $url;
	if ($haveQuotation)
		{
		$displayedURL = $quoteChar . $displayedURL . $quoteChar;
		}
	my $repString = "<a href='$url' target='_blank'>$displayedURL</a>";
	
	my $linkIsMaybeTooLong = 0;
	my $repLength = length($url);
	my $repStartPosition = $startPos;
	if ($haveQuotation)
		{
		$repLength += 2;
		}
	push @repStr, $repString;
	push @repLen, $repLength;
	push @repStartPos, $repStartPosition;
	push @linkIsPotentiallyTooLong, $linkIsMaybeTooLong;
	}

sub PackUpMarkdownLinkRep {
	my ($startPos, $captured, $markdownDisplayText, $markdownLink) = @_;

	my $repString = "<a href='$markdownLink' target='_blank'>$markdownDisplayText</a>";
	my $repLength = length($captured);
	my $repStartPosition = $startPos;

	push @repStr, $repString;
	push @repLen, $repLength;
	push @repStartPos, $repStartPosition;
	push @linkIsPotentiallyTooLong, 0;
	}

# Remember all the replacement link strings for a line, and put placeholders (markers)
# for them in the line text.
# This is needed for gloss2html.pl because images are not plain links here, instead the
# entire contents of the image file are put in the text. This can produces lines
# that are 100,000 characters long and more, which causes serious trouble for
# AddGlossaryHints(). Small placeholders are inserted here for the final links,
# and DoFinalLinkReps() below replaces the placeholders with the final link
# contents at the end of GetPrettyText() when it's safe.
# IntraMine's Viewer just puts in links for images and doesn't have this problem.
sub DoPlaceholderLinkReps {
	my ($numReps, $lineNumber, $txtR) = @_;

		for (my $i = $numReps - 1; $i >= 0; --$i)
			{
			if ($i > 0 && $linkIsPotentiallyTooLong[$i-1])
				{
				# If repstart [$i] is greater that [$i-1] end, shorten [$i-1].
				if ($repStartPos[$i] <= $repStartPos[$i-1] + $repLen[$i-1])
					{
					my $amtToLeave = $repStartPos[$i] - $repStartPos[$i-1] - 1;
					$repLen[$i-1] = $amtToLeave;
					if ($repLen[$i-1] <= 0)
						{
						$repLen[$i-1] = 0;
						}
					else
						{
						# Need to shorten text inside repStr <a>.this</a>
						if ($repStr[$i-1] =~ m!^(\<a([^>]+)\>)(.+)$!)
							{
							my $anchorStart = $1;
							my $remainder = $3;
							my $anchorEndPos = rindex($remainder, "</a>");
							if ($anchorEndPos > 0)
								{
								my $anchortext = substr($remainder, 0, $anchorEndPos);
								$remainder =~ s!\<span class\=\"noshow\"\>\<\/span\>!!g;
								$remainder = substr($remainder, 0, $amtToLeave);
								# Put $repStr[$i-1] back together.
								$repStr[$i-1] = $anchorStart . $remainder . "</a>";
								}
							}
						}
					}
				}
			if ($repLen[$i] > 0)
				{
				# substr($line, $pos, $srcLen, $repString);
				#substr($line, $repStartPos[$i], $repLen[$i], $repStr[$i]);
				
				# Save the rep strings to a list, and for now just put placeholders for them
				# in the text. Later, DoFinalLinkReps() will put in the final replacements.
				my $marker = '<marker_' . $Timestamp . '_' . $lineNumber . '_' . $i . '>';
				$LineRepsForMarkers{$lineNumber}{$marker} = $repStr[$i];
				substr($line, $repStartPos[$i], $repLen[$i], $marker);
				}
			}
		$$txtR = $line;	
	}

# Replace all link markers with actual links.
sub DoFinalLinkReps {
	my ($linesA) = @_;
	my $numLines = @$linesA;
	
	foreach my $line (sort keys %LineRepsForMarkers)
		{
		foreach my $marker (keys %{$LineRepsForMarkers{$line}})
			{
			$linesA->[$line] =~ s!$marker!$LineRepsForMarkers{$line}{$marker}!;
			}
		}

	}
} ##### AutoLink for Gloss

sub FullPathForFile {
	my ($pathToCheck, $contextDir) = @_;
	my $textPath = '';
	if ($pathToCheck =~ m!\.html?$!i)
		{
		$textPath = $pathToCheck;
		$textPath =~ s!\.html?$!.txt!;
		}
	my $result = '';
	
	if (FileOrDirExistsWide($pathToCheck) == 1)
		{
		$result = $pathToCheck;
		}
	elsif (FileOrDirExistsWide($contextDir . $pathToCheck) == 1)
		{
		$result = $contextDir . $pathToCheck;
		}
	elsif (FileOrDirExistsWide($contextDir . 'images/' . $pathToCheck) == 1)
		{
		$result = $contextDir . 'images/' . $pathToCheck;
		}
	elsif ($textPath ne '')
		{
		if (FileOrDirExistsWide($textPath) == 1)
			{
			$result = $textPath;
			}
		elsif (FileOrDirExistsWide($contextDir . $textPath) == 1)
			{
			$result = $contextDir . $textPath;
			}
		}
	return($result);
	}

{ ##### Internal Links
my $line;
my $len;
	
# These replacements are more easily done in reverse order to avoid throwing off the start/end.
my @repStr;			# new link, eg <a href="#Header_within_doc">#Header within doc</a>
my @repLen;			# length of substr to replace in line, eg length('#Header within doc')
my @repStartPos;	# where header being replaced starts, eg zero-based positon of '#' in '#Header within doc'

# AddInternalLinksToLine
# Turn mention of a header within a txt file into a link.
# Called only for .txt files, see GetPrettyTextContents() above.
# Header mentions must start with # or be enclosed in "", and can be either the
# actual text of the header or the boiled-down anchor (spaces -> underscores etc) eg:
# #Header name #Header_name "Header name" "Header_name"
# Header mentions starting with '#' must also be followed immediately by one of
# [space . ; , " # end-of-text].
# Existing links to anchors in other files should be skipped. This check is needed only
# after a potential header has been found.
# Any found mention of a header, such as #Header within doc, is turned into a link
# <a href="#Header_within_doc">#Header within doc</a>.
# NOTE you should prefer putting internal header mentions in "double quotes", because that's the only
# form that IntraMine's Viewer supports. It used to support #hash mentions, but that proved
# too slow. Here, speed doesn't matter as much.
sub AddInternalLinksToLine {
	my ($txtR, $sectionIdExistsH) = @_;
	
	# Skip any line that does have a header element <h1> <h2> etc or doesn't have a header delimiter.
	if (index($$txtR, '><h') > 0 || (index($$txtR, '#') < 0 && index($$txtR, '"') < 0))
		{
		return;
		}
	
	# Init variables with "Internal Links" scope.
	$line = $$txtR;
	$len = length($line);
	@repStr = ();		# new link, eg <a href="#Header_within_doc">#Header within doc</a>
	@repLen = ();		# length of substr to replace in line, eg length('#Header within doc')
	@repStartPos = ();	# where header being replaced starts, eg zero-based positon of '#' in '#Header within doc'

	EvaluateInternalLinkCandidates($sectionIdExistsH);

	# Do all reps in reverse order at end.
	my $numReps = @repStr;
	if ($numReps)
		{
		for (my $i = $numReps - 1; $i >= 0; --$i)
			{
			# substr($line, $pos, $srcLen, $repString);
			substr($line, $repStartPos[$i], $repLen[$i], $repStr[$i]);
			}
		$$txtR = $line;
		}
	}
	
sub EvaluateInternalLinkCandidates {
	my ($sectionIdExistsH) = @_;
	
	# Get things started by spotting the first delimiter, # or ". At least one is guaranteed above.
	$line =~ m!([#"])!;
	my $currentMatchStartPos = $-[1];
	my $delimiter = $1;
	
	# Limit how far ahead to look for first potential anchor name. Default is end of line.
	my $currentMatchEndPos = $len;
	if ($line =~ m!^.{$currentMatchStartPos}..*?([#"])!)
		{
		$currentMatchEndPos = $-[1];
		}
	
	# Loop over all potential matches on the line.
	while ($currentMatchStartPos > 0)
		{
		my $potentialID = '';
		my $haveGoodMatch = 0;
		my $repString = '';
		my $repLength = 0;
		my $repStartPosition = $currentMatchStartPos + 1;
		my $currentPos = -1; 						# **$endPos**
		my $prevPos = $currentMatchStartPos + 1;	# **$startPos**
		my $currentDelimiter = '';
		my $previousDelimiter = '';
		my $haveCheckedToEndOfLine = 0;
		
		# Within range, look for separator characters (space period semicolon etc), collect a potential header.
		while ($prevPos > 0)
			{
			# Find next term separator, if any. If none, $currentPos stays at -1.
			# (Probably a bug around here, sometimes $prevPos is > 65534.)
			if ($prevPos < 65534 && $line =~ m!^.{$prevPos}.*?([ \t.,;#"])!)
				{
				$currentPos =  $-[1];
				$currentDelimiter = $1;
				}
			elsif (!$haveCheckedToEndOfLine)
				{
				$currentPos = $len;
				$haveCheckedToEndOfLine = 1;
				}
			
			if ($currentPos > 0)
				{
				# Collect next term ($idPart), render it into an acceptable string for an anchor and add it to $potentialID.
				my $idPart = substr($line, $prevPos, $currentPos - $prevPos);
				# First clean up the $idPart.
				# (Note stripping HTML elements will also strip trailing </td></td> if we're at end of line.)
				$idPart =~ s!<[^>]+>!!g;
				# File links can have &nbsp;
				$idPart =~ s!&nbsp;!_!g;
				# Quotes don't help either.
				$idPart =~ s!['"]!!g;
				# Remove unicode symbols from $id, especially the ones inserted by markdown above, to make
				# it easier to type the headers in links. Eg 'server swarm.txt#TODO_List' for header '&#127895;TODO List'.
				$idPart =~ s!\&#\d+;!!g; # eg &#9755;
				# Bolt new idPart onto $potentialID (with underscore instead of space).
				my $joiner = ($previousDelimiter eq ' ') ? '_': $previousDelimiter;
				if ($joiner eq ' ')
					{
					$joiner = '_';
					}
				$potentialID .= "$joiner$idPart";
				
				# Have we matched a known header with our (potential) ID?
				if (defined($sectionIdExistsH->{$potentialID}))
					{
					# No match if '#' was inside a pre-existing file anchor.
					$haveGoodMatch = (InsideExistingAnchor($delimiter, $currentPos)) ? 0: 1;
					if ($haveGoodMatch)
						{
						# Remember just the $id into repStr for now, turn it into an anchor below.
						$repString = $potentialID;
						$repStartPosition = $currentMatchStartPos;
						$repLength = $currentPos - $currentMatchStartPos;
						}
					}
				
				# Set separator for next term.
				$previousDelimiter = $currentDelimiter; #substr($line, $currentPos, 1);
				}
			
			# Advance the search.
			$prevPos = $currentPos + 1;
			if ($prevPos >= $currentMatchEndPos || $haveCheckedToEndOfLine)
				{
				$prevPos = -1;
				}
			$currentPos = -1;
			} # while ($prevPos > 0)
		
		# Remember good match if any.
		if ($haveGoodMatch)
			{
			# <a href="#Header_within_doc">Header within doc</a>
			# At this point, $repString is just the anchor $potentialID.
			my $srcHeader = substr($line, $repStartPosition, $repLength);
			my $replacementAnchor = "<a href=\"#$repString\">$srcHeader</a>";
			push @repStr, $replacementAnchor;
			push @repLen, $repLength;
			push @repStartPos, $repStartPosition;
			}
		
		# Advance before doing next match.
		my $charsToSkip = 1; # chars to advance before looking for next delimiter.
		if ($haveGoodMatch)
			{
			$charsToSkip = ($delimiter eq '#') ? $repLength : $repLength + 1;
			}
		$currentMatchStartPos += $charsToSkip;
		
		# Find next delimiter and range, or set $currentMatchStartPos to -1.
		if ($currentMatchStartPos < 65534 && $line =~ m!^.{$currentMatchStartPos}.*?([#"])!)
			{
			$currentMatchStartPos = $-[1];
			$delimiter = $1;
			if ($currentMatchStartPos < 65534 && $line =~ m!^.{$currentMatchStartPos}..*?([#"])!)
				{
				$currentMatchEndPos = $-[1];
				}
			else
				{
				$currentMatchEndPos = $len;
				}
			}
		else
			{
			$currentMatchStartPos = -1;
			}
		} # while ($currentMatchStartPos > 0)
	}

sub InsideExistingAnchor {
	my ($delimiter, $currentPos) = @_;
	my $insideExistingAnchor = 0;
	
	# Is there an anchor on the line, when delimiter is '#'?
	if ($delimiter eq '#' && index($line, '<a') > 0)
		{
		# Does the anchor enclose the header mention?
		#<a href="http://192.168.0.3:43129/?href=c:/perlprogs/mine/notes/server swarm.txt#Set_HTML" target="_blank">server swarm.txt#Set_HTML</a>
		# Look ahead for either '<a ' or '</a>, and if '</a>' is seen first
		# then it's inside an anchor.
		# If it's in the href, it will be preceded immediately by a port number.
		# If it's displayed as the anchor content, it will be preceded immediately
		# by a file extension.
		my $nextAnchorStartPos = index($line, '<a ', $currentPos);
		my $nextAnchorEndPos = index($line, '</a>', $currentPos);
		if ($nextAnchorEndPos >= 0 &&
			($nextAnchorStartPos < 0 || $nextAnchorEndPos < $nextAnchorStartPos ))
			{
			$insideExistingAnchor = 1;
			}
		}
	
	return($insideExistingAnchor);
	}
} ##### Internal Links

# Inline the needed JavaScript, and finish off the HTML.
sub EndHtmlFile {
	my ($filePath, $contents_R) = @_;
	$$contents_R .= "</div>\n"; # This closes <div id='scrollAdjustedHeight'>
	
	
	my $topJS = <<'DONEIT';
<script>
let thePath = '_PATH_';
let theEncodedPath = '_ENCODEDPATH_';
let usingCM = false;
let cmTextHolderName = 'scrollTextRightOfContents';
let specialTextHolderName = 'specialScrollTextRightOfContents';
let theMainPort = '99999';
let mainIP = '99999';
let ourServerPort = '99999';
let peeraddress = '99999';	// ip address of client
let weAreRemote = false;
let errorID = "editor_error";
let highlightItems = [];
let b64ToggleImage = '_B64TOGGLEIMAGE';
let selectedTocId = '_SELECTEDTOCID_';
let doubleClickTime = _DOUBLECLICKTIME_;
let useLolight = true;
let weAreStandalone = true;
</script>
<script>
	// Call fn when ready.
	function ready(fn) {
	  if (document.readyState != 'loading'){
	    fn();
	  } else {
	    document.addEventListener('DOMContentLoaded', fn);
	  }
	}

	function getRandomInt(min, max) {
  		return Math.floor(Math.random() * (max - min + 1) + min);
		}
</script>
<script>
function loadAndShowHint(hintContents, obj, e, tipwidth, isAnImage, shouldDecode) {
	hintContents = loadCachedImages(hintContents); // popup_image_cache.js
	showhint(hintContents, obj, e, tipwidth, isAnImage, shouldDecode);
}
</script>
DONEIT

	my $ctrlSPath = encode_utf8($filePath);
	$ctrlSPath =~ s!%!%25!g;
	$ctrlSPath =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
	# For JS <img src="707788g4.png" id="tocShrinkExpand" style="top: 10.3906px;">
	# in showHideTOC.js#addTocToggle().
	my $b64ToggleImage = '';
	ImageBase64('707788g4.png', '', \$b64ToggleImage);
	$b64ToggleImage =~ s!\n!!g; # JS doesn't like the \n inside the image string
	$topJS =~ s!_PATH_!$filePath!g;
	$topJS =~ s!_ENCODEDPATH_!$ctrlSPath!g;
	$topJS =~ s!_B64TOGGLEIMAGE!$b64ToggleImage!g;
	# Hilight class for table of contents selected element - see also non_cm_test.css
	# and cm_viewer.css.
	$topJS =~ s!_SELECTEDTOCID_!tocitup!; 
	# Double click time.
	my $dtime = DoubleClickTime();
	$topJS =~ s!_DOUBLECLICKTIME_!$dtime!;

	$$contents_R .= $topJS;
	

	# JavaScript files, inlined.
	$$contents_R .= InlineJavaScriptForFile('debounce.js');
	$$contents_R .= InlineJavaScriptForFile('tooltip.js');
	$$contents_R .= InlineJavaScriptForFile('isW.js');
	$$contents_R .= InlineJavaScriptForFile('mark.min.js');
	$$contents_R .= InlineJavaScriptForFile('wordAtInsertionPt.js');
	$$contents_R .= InlineJavaScriptForFile('LightRange.min.js');
	$$contents_R .= InlineJavaScriptForFile('commonEnglishWords.js');
	$$contents_R .= InlineJavaScriptForFile('glossstubs.js');
	$$contents_R .= InlineJavaScriptForFile('showHideTOC.js');
	$$contents_R .= InlineJavaScriptForFile('viewerStart.js');
	#$$contents_R .= InlineJavaScriptForFile('viewerLinks.js');
	$$contents_R .= InlineJavaScriptForFile('indicator.js');
	$$contents_R .= InlineJavaScriptForFile('toggle.js');
	$$contents_R .= InlineJavaScriptForFile('scrollTOC.js');
	$$contents_R .= InlineJavaScriptForFile('dragTOC.js');
	$$contents_R .= InlineJavaScriptForFile('lolight-1.4.0.min.js');
	$$contents_R .= InlineJavaScriptForFile('viewer_hover_inline_images.js');
	$$contents_R .= InlineJavaScriptForFile('popup_image_cache.js');

	my $optionalJavaScriptFileName = 'im_gloss.js';
	if (OptionalCustomJSforGlossExists($optionalJavaScriptFileName))
		{
		$$contents_R .= InlineJavaScriptForFile($optionalJavaScriptFileName);
		}

	# Add the JS image cache.
	my $imgCache = GetImageCache(); # gloss.pm#GetImageCache()
	$$contents_R .= "\n<script>" . $imgCache . "\n</script>\n";
	$$contents_R .= "</body></html>\n";
	}

sub InlineCssForFile {
	my ($fileName) = @_;
	my $result = '';
	my $contents = ReadTextFileWide($CSS_DIR . $fileName);
	if (defined($contents) && $contents ne '')
		{
		$result = "<style>\n$contents\n</style>\n";
		}
	else
		{
		Output("Error, could not load CSS file |$fileName|\n");
		}
		
	return($result);
	}

sub InlineJavaScriptForFile {
	my ($fileName) = @_;
	my $result = '';
	my $contents = ReadTextFileWide($JS_DIR . $fileName);
	if (defined($contents) && $contents ne '')
		{
		$result = "<script type=\"text/javascript\">\n$contents\n</script>\n";
		}
	else
		{
		Output("Error, could not load JavaScript file |$fileName|\n");
		}
		
	return($result);
	}

# "<img src=\"data:image/png;base64,$enc64\" (optional width height) />";
sub ImageLinkQuoted {
	my ($fileName, $contextDir, $linkR, $width, $height) = @_;
	$width ||= '';
	$height ||= '';
	$$linkR = '';
	my $enc64 = '';
	ImageBase64($fileName, $contextDir, \$enc64);
	

	if ($enc64 ne '')
		{
		$width = " width='$width'"  unless ($width eq '');
		$height = " height='$height'"  unless ($height eq '');
		my $imgType = 'png';
		if ($fileName =~ m!\.(jpg|jpeg)$!i)
			{
			$imgType = 'jpeg';
			}
		elsif ($fileName =~ m!\.gif$!i)
			{
			$imgType = 'gif';
			}
		elsif ($fileName =~ m!\.webp$!i)
			{
			$imgType = 'webp';
			}
		$$linkR = "<img src=&quot;data:image/$imgType;base64,$enc64&quot;$width$height  />";
		}
	else
		{
		Output("Warning, could not retrieve image |$fileName|\n");
		}
	}

# "<img src=\"data:image/png;base64,$enc64\" (optional width height) />";
# This simpler variant of ImageLinkQuoted() is used for 'hoverleft.png' and 'hoverright.png' above.
sub ImageLink {
	my ($fileName, $contextDir, $linkR, $width, $height) = @_;
	$width ||= '';
	$height ||= '';
	$$linkR = '';
	my $enc64 = '';
	ImageBase64($fileName, $contextDir, \$enc64);
	
	
	if ($enc64 ne '')
		{
		$width = " width='$width'"  unless ($width eq '');
		$height = " height='$height'"  unless ($height eq '');
		my $imgType = 'png';
		if ($fileName =~ m!\.(jpg|jpeg)$!i)
			{
			$imgType = 'jpeg';
			}
		elsif ($fileName =~ m!\.gif$!i)
			{
			$imgType = 'gif';
			}
		#$result = "<img src=\"data:image/$imgType;base64,$enc64\"$width$height  />";
		$$linkR = "<img src=\"data:image/$imgType;base64,$enc64\"$width$height  />";
		}
	else
		{
		Output("Warning, could not retrieve image |$fileName|\n");
		}
	}

# Load and return the base 64 contents of an image, for inlining.
sub ImageBase64 {
	my ($fileName, $contextDir, $encContentsR) = @_;
	$$encContentsR = '';
	
	my $filePath = '';
	if (FileOrDirExistsWide($fileName) == 1)
		{
		$filePath = $fileName;
		}
	elsif (FileOrDirExistsWide($IMAGES_DIR . $fileName) == 1)
		{
		$filePath = $IMAGES_DIR . $fileName;
		}
	elsif ($COMMON_IMAGES_DIR ne '' && FileOrDirExistsWide($COMMON_IMAGES_DIR . $fileName) == 1)
		{
		$filePath = $COMMON_IMAGES_DIR . $fileName;
		}
	elsif (FileOrDirExistsWide($contextDir . $fileName) == 1)
		{
		$filePath = $contextDir . $fileName;
		}
	elsif (FileOrDirExistsWide($contextDir . 'images/' . $fileName) == 1)
		{
		$filePath = $contextDir . 'images/' . $fileName;
		}

	$$encContentsR = encode_base64(ReadBinFileWide($filePath));
	}

{ ##### Glossary load, evaluate, and add entries for terms when seen in text.
my $GlossaryFileName;
my $GlossaryHtmlName;
my $GlossaryPath;
my %Definition;
my %DefinitionSeenInDocument;

# Glossary hint insertion is modelled in part after AddInternalLinksToLine() above.
my $line;
my $len;
	
# These replacements are more easily done in reverse order to avoid throwing off the start/end.
my @repStr;			# new link, eg <a href="#Header_within_doc">#Header within doc</a>
my @repLen;			# length of substr to replace in line, eg length('#Header within doc')
my @repStartPos;	# where header being replaced starts, eg zero-based positon of '#' in '#Header within doc'

sub ClearDocumentGlossaryTermsSeen {
	%DefinitionSeenInDocument = ();
}

# Load glossary entries from glossary.txt. Note the txt file is not converted to HTML here
# (it's converted later by ConvertTextToHTML() if present in @listOfFilesToConvert).
sub LoadGlossary {
	my ($context) = @_;
	my $glossaryFileName = CVal('GLOSSARY_FILE_NAME');
	my $filePath = $context . $glossaryFileName;
	
	if (FileOrDirExistsWide($filePath) != 1)
		{
		return;
		}
	
	my $octets;
	if (!LoadTextFileContents($filePath, \$octets))
		{
		Output("Error, could not load |$filePath|!\n");
		return;
		}
	$GlossaryFileName = $glossaryFileName;
	$GlossaryPath = $filePath;
	$GlossaryHtmlName = $GlossaryFileName;
	$GlossaryHtmlName =~ s!\.\w+$!.html!;
	
	my @lines = split(/\n/, $octets);
	
	my @currentTerms;
	for (my $i = 0; $i < @lines; ++$i)
		{
		# Skip comment lines, they start with '##' (but not one or more than two #'s).
		if ($lines[$i] =~ m!^##($|[^#])!)
			{
			; # skip
			}
		# match up to ':' but not '\:'.
		elsif ($lines[$i] =~ m!^\s*(.+?[^\\]):!)
		#elsif ($lines[$i] =~ m!^\s*([^:]+)\:!)
			{
			my $term = $1;
			$term =~ s!\*!!g;
			# Make entry in %Definition for lowercase version of term.
			#$currentTerm = lc($term);
			@currentTerms = split(/,\s*/, lc($term));
			my $entry = $lines[$i];
			chomp($entry);
			# For display, remove '\' from '\:'.
			$entry =~ s!\\:!:!g;

			# OUT - this was bad, left in as a reminder.
			###$entry = &HTML::Entities::encode($entry);
			###$entry =~ s!\&#39;!\&#8216;!g;

			#$Definition{$currentTerm} = "<p>$entry</p>";
			for (my $j = 0; $j < @currentTerms; ++$j)
				{
				$Definition{$currentTerms[$j]} = "<p>$entry</p>";
				}
			}
		elsif (@currentTerms != 0)
			{
			my $entry = $lines[$i];
			chomp($entry);
			# For display, remove '\' from '\:'.
			$entry =~ s!\\:!:!g;

			if ($entry ne '')
				{
				###$entry = &HTML::Entities::encode($entry);
				###$entry =~ s!\&#39;!\&#8216;!g;
				#$Definition{$currentTerm} .= "<p>$entry</p>";
				for (my $j = 0; $j < @currentTerms; ++$j)
					{
					$Definition{$currentTerms[$j]} .= "<p>$entry</p>";
					}
				}
			}
		}
	}

sub IsGlossaryPath {
	my ($filePath) = @_;
	my $result = (defined($GlossaryPath) && $filePath eq $GlossaryPath) ? 1: 0;
	
	return($result);
	}

sub AddGlossaryHints {
	my ($txtR, $context) = @_;
	
	# Init variables with "Glossary loading" scope.
	$line = $$txtR;
	$len = length($line);
	@repStr = ();		# new link, eg <a href="#Header_within_doc">#Header within doc</a>
	@repLen = ();		# length of substr to replace in line, eg length('#Header within doc')
	@repStartPos = ();	# where header being replaced starts, eg zero-based positon of '#' in '#Header within doc'

	EvaluateGlossaryCandidates($context);

	# Do all reps in reverse order at end.
	my $numReps = @repStr;
	if ($numReps)
		{
		for (my $i = $numReps - 1; $i >= 0; --$i)
			{
			# substr($line, $pos, $srcLen, $repString);
			substr($line, $repStartPos[$i], $repLen[$i], $repStr[$i]);
			}
		$$txtR = $line;
		}
	
	}

# Loop over the words on a line. Look for one to four-word glossary entries.
# I will come back and fine tune to pick up extra characters etc.For starters,
# just \w and hyphen.
# Note  @repStr replacments are created in a second pass, since they involve regex's that
# might mess up the regex variables if done in while loops that use regex's to match words.
# @repStartPos entries can be out of ascending order here due to making several passes
# looking for entries one..four words long. So results are sorted.
# Do just one glossary entry per line for any particular glossary term.
sub EvaluateGlossaryCandidates {
	my ($context) = @_;
	
	my @startPosSeen; # Track glosses to avoid doubling up - longest wins.
	my @endPosSeen; # Length of a matched term, also indexed by $startPos
	my $posIndex = 0;
	my %DefinitionSeenOnLine;
	
	my @wordStartPos;
	my @wordEndPos;
	GetLineWordStartsAndEnds($line, \@wordStartPos, \@wordEndPos);
	my $numWordStarts = @wordStartPos;
	
	# Four-word matches down to one-word matches:
	my $nWords = 4;
	
	while ($nWords >= 1)
		{
		my $nWordsMinusOne = $nWords - 1;
		my $i = 0;
		while ($i < $numWordStarts)
			{
			if ($i < $numWordStarts - $nWordsMinusOne)
				{
				my $startPos = $wordStartPos[$i];				# beginning of match
				my $endPos = $wordEndPos[$i + $nWordsMinusOne];	# pos of char after end of match
				my $len = $endPos - $startPos;
				my $words = substr($line, $wordStartPos[$i], $len);
				my $term = lc($words);	# glossary terms are lower case in %Definition
				if (defined($Definition{$term}) && !RangeOverlapsExistingAnchor($startPos, $endPos))
					{
					# Skip if current term formed part of a previous term.
					my $overlapped = 0;
					for (my $j = 0; $j < $posIndex; ++$j)
						{
						if ($startPos >= $startPosSeen[$j] && $endPos <= $endPosSeen[$j])
							{
							$overlapped = 1;
							last;
							}
						}
					
					if (!$overlapped && !defined($DefinitionSeenOnLine{$term}))
						{
						my $definitionAlreadySeen = (defined($DefinitionSeenInDocument{$term})) ? 1 : 0;
						my $replacementHint = GetReplacementHint($term, $words, $definitionAlreadySeen, $context);
						my $repLength = length($words);
						my $repStartPosition = $startPos;
						push @repStr, $replacementHint;
						push @repLen, $repLength;
						push @repStartPos, $repStartPosition;			
						$startPosSeen[$posIndex] = $startPos;
						$endPosSeen[$posIndex++] = $startPos + $repLength;
						$DefinitionSeenInDocument{$term} = 1;
						$DefinitionSeenOnLine{$term} = 1;
						}
					
					$i += $nWords;
					}
				else
					{
					++$i;
					}
				}
			else
				{
				last;
				}
			}
		
		--$nWords;
		}
		
	SortGlossaryResultsForOneLine();
	}

# Sort @repStartPos, @repLen, and @repStr in ascending order by @repStartPos.
sub SortGlossaryResultsForOneLine {
	my $numReps = @repStartPos;
	if (!$numReps)
		{
		return;
		}
	
	my @idx = sort {$repStartPos[$a] <=> $repStartPos[$b]} 0..$#repStartPos;
	@repStr = @repStr[@idx];
	@repLen = @repLen[@idx];
	@repStartPos = @repStartPos[@idx];
	}

# Find start and end positions of words in line.
sub GetLineWordStartsAndEnds {
	my ($line, $startA, $endA) = @_;
	
	while ($line =~ m!([\w'-]+)!g)
		{
		my $startPos = $-[1];	# beginning of match
		my $endPos = $+[1];		# one past last matching character
		push @$startA, $startPos;
		push @$endA, $endPos;
		}
	}

# Return the full glossary definition, in an anchor element.
# If the entry is just an image, put in the image as the hint.
# If the entry has synonyms, remove them from the term being defined and show them
# as "Alt: " in a new paragraph at the bottom of the hint.
sub GetReplacementHint {
	my ($term, $originalText, $definitionAlreadySeen, $context) = @_;
	my $host = undef;
	my $port = undef;
	my $VIEWERNAME = undef;
	my $class = $definitionAlreadySeen ? 'glossary term-seen': 'glossary';
	my $gloss = $Definition{$term};
	my $result = '';

	# If the $gloss is just an image name, pull in the image as content of showhint() popup,
	# otherwise apply GLoss (IntraMine's Markdown variant for intranet use).
	my $glossaryImagePath = ImageNameFromGloss($gloss);
	if ($glossaryImagePath ne '')
		{
		my $bin64Img = '';
		ImageLinkQuoted($glossaryImagePath, $context, \$bin64Img);
		$bin64Img =~ s!\n!!g; # JS doesn't like \n inside the image string
		if ($bin64Img ne '')
			{
			$result = "<a class='$class' href=\"#\" onmouseOver=\"showhint('$bin64Img', this, event, '500px', true);\">$originalText</a>";
			}
		else
			{
			$result = $originalText;
			}
		}
	else
		{
		my $glossed = '';
		# If a glossary entry has synonyms, show just the relevant one at start of the
		# $gloss entry, and show other synonyms in a new para at bottom of the entry.
		if ($gloss =~ m!^<p>(.+?[^\\]):!)
		#if ($gloss =~ m!^<p>([^:]+)\:!)
			{
			my $terms = $1;
			$terms =~ s!\*!!g;
			my $termShown = '';
			
			my @synonyms = split(/,\s*/, $terms);
			my $numSynonymsTotal = @synonyms;
			my $altList = '';
			$gloss =~ s!^<p>([^:]+):\s*!!; # Strip terms from start, up to just before ':'
			$gloss =~ s!\<p>!!g;
			$gloss =~ s!\</p>!\n!g;
			chomp($gloss); # Get rid of trailing blank line.

			if ($numSynonymsTotal > 1)
				{
				# Show term at start of gloss, then definition. Follow with synonyms.
				my @otherSynonyms;
				for (my $i = 0; $i < $numSynonymsTotal; ++$i)
					{
					my $lcTermFromGloss = lc($synonyms[$i]);
					if ($lcTermFromGloss eq $term)
						{
						$termShown = ucfirst($synonyms[$i]);
						}
					else
						{
						push @otherSynonyms, $synonyms[$i];
						}
					}
				
				$altList = "\nAlt: " . join(', ', @otherSynonyms);
				#$gloss .= $altList;
				}
			else
				{
				$termShown = ucfirst($synonyms[0]);
				}

			# Apply Gloss to the glossary entry (sorry about that);
			Gloss("**$termShown**: " . $gloss . $altList, $host, $port, \$glossed, 0, $IMAGES_DIR, $COMMON_IMAGES_DIR, $context, undef, undef);

			$glossed =~ s!&amp;#8216;!'!g;
			$glossed =~ s!&amp;quot;!"!g;

			$glossed = uri_escape_utf8($glossed);

			# Spurious LF's, stomp them with malice.
			$glossed =~ s!\%0A!!g;
			$gloss = $glossed;
			}
		
		$result = "<a class='$class' href=\"#\" onmouseover=\"loadAndShowHint('$gloss', this, event, '600px', false, true);\">$originalText</a>";
		}
	
	return($result);
	}

# If a glossary entry looks like 
# <p>Term: "image name.png".</p>
# or
# <p class='valigntop'><span class='inlinespan'>term: </span>"image name.png"</p>
# then treat it as a image and return
# the image name. Else return ''.
sub ImageNameFromGloss {
	my ($gloss) = @_;
	my $result = '';
	
	if ( $gloss =~ m!^\<p\>[^:]+\:\s*\&quot\;([^\>]+)\&quot\;\.?\</p\>$!i
	|| $gloss =~ m!^\<p\>[^:]+\:\s*\"([^\>]+)\"\.?\</p\>$!i
	|| $gloss =~ m!^\<p[^\>]+\>[^:]+\:\s*\</span\>\&quot\;(.+?)\&quot\;\.?\</p\>$!i
	|| $gloss =~ m!^\<p[^\>]+\>[^:]+\:\s*\</span\>\"(.+?)\"\.?\</p\>$!i)
	# if ( $gloss =~ m!^\<p\>[^:]+\:\s*\&quot\;([^\>]+)\&quot\;\.?\</p\>$!i
	#   || $gloss =~ m!^\<p[^\>]+\>[^:]+\:\s*\</span\>\&quot\;(.+?)\&quot\;\.?\</p\>$!i )
		{
		my $imageName = $1;
		if ($imageName =~ m!\.(\w+)$!)
			{
			my $extProper = $1;
			if (IsImageExtensionNoPeriod($extProper))
				{
				$result = $imageName;
				}
			}
		}
	
	return($result);
	}

sub AnchorForGlossaryTerm {
	my ($term) = @_;
	
	$term =~ s!&nbsp;!_!g;
	$term =~ s!['"]!!g;
	$term =~ s!\&#\d+;!!g; # eg &#9755;
	$term =~ s!\s!_!g;
	$term =~ s!\-!_!g;
	
	return($term);
	}

# Is $startPos or $endPos inside an <a>...</a> element?
# Also skip if $startPos in inside the opener of <h1 2 or 3.
sub RangeOverlapsExistingAnchor {
	my ($startPos, $endPos) = @_;
	my $insideExistingAnchor = 0;
	
	# Is there an anchor on the line?
	if (index($line, '<a') > 0)
		{
		# Does any anchor overlap?
		my $pos = 0;
		my $nextPos = 0;
		while (($nextPos = index($line, '<a', $pos)) >= 0)
			{
			my $aStart = $nextPos;
			my $aEnd = index($line, '</a>', $nextPos);
			if ($aEnd > 0)
				{
				if ( ($startPos >= $aStart && $startPos <= $aEnd)
				  || ($endPos >= $aStart && $endPos <= $aEnd) )
					{
					$insideExistingAnchor = 1;
					last;
					}
				}
			else # should not happen, like, ever.
				{
				last;
				}
			$pos = $aEnd + 1;
			}
		}
		
	if (!$insideExistingAnchor && index($line, '<h') > 0)
		{
		my $startH = index($line, '<h');
		my $endH = index($line, '>', $startH + 1);
		if ($startPos > $startH && $startPos < $endH)
			{
			$insideExistingAnchor = 1;
			}
		}
	
	return($insideExistingAnchor);
	}

# For glossary.txt only, add anchors for defined terms.
sub AddGlossaryAnchor {
	my ($txtR) = @_;
	
	# Init variables with "Glossary loading" scope.
	$line = $$txtR;
	$len = length($line);
	
	# Typical line start for defined term:
	# <tr><td n='21'></td><td>Strawberry Perl: 
	if ($line =~ m!^(.+?<td>\s*)([^:]+)\:(.*)$!)
		{
		my $pre = $1;
		my $post = $3;
		my $term = $2;
		my $originalText = $term;
		$term = lc($term);
		$term =~ s!\*!!g;
		my $anchorText = AnchorForGlossaryTerm($term);
		my $rep = "<h2 id=\"$anchorText\"><strong>$originalText</strong>:</h2>";
#		my $rep = "<a id=\"$anchorText\"><strong>$originalText</strong>:</a>";
		$$txtR = $pre . $rep . $post;
		}
	}
} ##### Glossary loading and hash of glossary entries

} ##### gloss_to_html scope to hide variables

use ExportAbove;
return 1;
