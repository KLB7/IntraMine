# intramine_glossary.pm: load and retrieve glossary definitions from glossary files.
# Hints are shown in response to onmouseover, using tooltip.js#showhint().
# See IntraMine's Documentation/Glossary popups.txt for usage.

package intramine_glossary;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use utf8;
use URI::Escape;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use win_wide_filepaths;
use ext;
use gloss;

my $IMAGES_DIR;
my $COMMON_IMAGES_DIR;

my $callbackFullPath;
my $callbackFullDirectoryPath;

my %GlossaryModDates; 		# $GlossaryModDates{glossary file path} = mod date for file as string.
my %Definition;				# $Definition{'term'} = 'definition';
# For standalone .txt files in a folder that has a glossary.txt file at the same
# level, use that glossary instead of entries from the glossary_master.txt files.
my %StandaloneDefinition; # $StandaloneDefinition{$context}{term} = definition;
my %ContextCheckedForGlossary; # $ContextCheckedForGlossary{$context} exists if checked.
my %DefinitionSeenInDocument; # Not implemented here, might re-instate.

my $haveRefToText; 	# For CodeMirror we get the text not a ref, and this is 0.
my $line;			# Full text of a single line.
my $len;			# Length of $line.
	
# In non-CodeMirror views where the text is directly altered, replacements are
# more easily done in reverse order to avoid throwing off the start/end.
# For CodeMirror the @repStr etc entries are passed back without altering the text.
my @repStr;			# new link, eg <a href="#Header_within_doc">#Header within doc</a>
my @repLen;			# length of substr to replace in line, eg length('#Header within doc')
my @repStartPos;	# where header being replaced starts, eg zero-based positon of '#' in '#Header within doc'
my @repLinkType; 	# For CodeMirror, 'glossary' is the only type here.

sub ClearDocumentGlossaryTermsSeen {
	%DefinitionSeenInDocument = ();
}

# Multiple glossary files are supported. They must all have the same name
# (default glossary_master.txt). All glossary entries are loaded into the
# same %Definition hash, and all are used by AddGlossaryHints() below
# when putting glossary hints in the text of a file.
sub LoadAllGlossaries {
	my ($allpaths, $imagesDir, $commonImagesDir, $theFullPathCallback, $theFullDirectoryPathCallback) = @_;
	$IMAGES_DIR = $imagesDir;
	$COMMON_IMAGES_DIR = $commonImagesDir;
	$callbackFullPath = $theFullPathCallback;
	$callbackFullDirectoryPath = $theFullDirectoryPathCallback;

	my @paths;
	if ($allpaths =~ m!\|!) # more than one candidate full path
		{
		@paths = split(/\|/, $allpaths);
		}
	else
		{
		push @paths, $allpaths;
		}
	
	for (my $i = 0; $i < @paths; ++$i)
		{
		LoadGlossary($paths[$i]);
		}

	my $numDefs = keys %Definition;
	#print("$numDefs glossary terms loaded.\n");
}

# Load glossary entries for file glossary.txt in the $context folder
# into the hash $StandaloneDefinition{$context}.
sub LoadStandaloneGlossary {
	my ($path, $context) = @_;
	my $glossaryPath = $context . "glossary.txt";

	LoadGlossary($glossaryPath, $context);
	}

# Load glossary entries from glossary_master.txt. Called by
# LoadAllGlossaries() above, and by
# intramine_linker.pl#HandleBroadcastRequest() in response to
# a signal received from intramine_filewatcher.pl#BroadcastGlossaryFilesChangedOrNew().
# If $context is defined, load $StandaloneDefinition{$context}, otherwise
# load into %Definition.
# If $forceInit is defined, clean out the hash. Applies only to $StandaloneDefinition{$context.
sub LoadGlossary {
	my ($filePath, $context, $forceInit) = @_;
	
	if (FileOrDirExistsWide($filePath) != 1)
		{
		return;
		}
	
	my $octets;
	if (!LoadTextFileContents($filePath, \$octets))
		{
		print("Error, could not load |$filePath|!\n");
		return;
		}
	
	SetGlossaryModDate($filePath);

	my $definitionHashRef;
	if (defined($context))
		{
		if (defined($forceInit) || !defined($StandaloneDefinition{$context}))
			{
			%{$StandaloneDefinition{$context}} = ();
			#$StandaloneDefinition{$context}{'absolutely utterly completely bogus term'} = 'oink';
			}
		$definitionHashRef = $StandaloneDefinition{$context};
		}
	else
		{
		$definitionHashRef = \%Definition;
		}

	
	my @lines = split(/\n/, $octets);
	
	my @currentTerms;
	for (my $i = 0; $i < @lines; ++$i)
		{
		# Skip comment lines, they start with '##' (but not one or more than two #'s).
		if ($lines[$i] =~ m!^##($|[^#])!)
			{
			; # skip
			}
		elsif ($lines[$i] =~ m!^\s*([^:]+)\:!)
			{
			my $term = $1;
			$term =~ s!\*!!g;
			@currentTerms = split(/,\s*/, lc($term));
			my $entry = $lines[$i];
			chomp($entry);

			$entry =~ s!\&#39;!\&#8216;!g;
			
			for (my $j = 0; $j < @currentTerms; ++$j)
				{
				$definitionHashRef->{$currentTerms[$j]} = "<p>$entry</p>";
				}
			}
		elsif (@currentTerms != 0) # Skip top lines without colons
			{
			my $entry = $lines[$i];
			chomp($entry);
			if ($entry ne '')
				{
				$entry =~ s!\&#39;!\&#8216;!g;
				for (my $j = 0; $j < @currentTerms; ++$j)
					{
					$definitionHashRef->{$currentTerms[$j]} .= "<p>$entry</p>";
					}
				}
			}
		}
	}

sub SetGlossaryModDate {
	my ($filePath) = @_;
	$filePath = lc($filePath);
	my $modTime = GetFileModTimeWide($filePath);
	if (defined($modTime))
		{
		$GlossaryModDates{$filePath} = $modTime;
		}
	}

sub GlossaryIsNewOrChanged {
	my ($filePath) = @_;
	$filePath = lc($filePath);
	my $result = 1;

	my $modTime = GetFileModTimeWide($filePath);
	if (defined($modTime) && defined($GlossaryModDates{$filePath}))
		{
		if ($modTime eq $GlossaryModDates{$filePath})
			{
			$result = 0;
			}
		}
	
	return($result);
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

sub IsGlossaryPath {
	my ($filePath) = @_;
	$filePath = lc($filePath);
	my $result = 0;

	if (defined($GlossaryModDates{$filePath}))
		{
		$result = 1;
		}
	return($result);
	}

sub AddGlossaryHints {
	my ($txtR, $path, $host, $port, $VIEWERNAME, $currentLineNumber, $linksA) = @_;
	# Note $currentLineNumber, $linksA are set only for CodeMirror ($haveRefToText == 0).

	if (ref($txtR) eq 'SCALAR') # REFERENCE to a scalar, so doing text
		{
		$haveRefToText = 1;
		$line = $$txtR;
		}
	else # not a ref, so doing CodeMirror
		{
		$haveRefToText = 0;
		$line = $txtR;
		}

	
	# Init variables with module scope.
	#$line = $$txtR;
	$len = length($line);
	@repStr = ();		# new link, eg <a href="#Header_within_doc">#Header within doc</a>
	@repLen = ();		# length of substr to replace in line, eg length('#Header within doc')
	@repStartPos = ();	# where header being replaced starts, eg zero-based positon of '#' in '#Header within doc'
	@repLinkType = (); # For CodeMirror, the "type" of link (file image dir etc)

	my $context = DirectoryFromPathTS($path);

	# As a special case,
	# Use $StandaloneDefinition{$context} instead of \%Definition if we have a
	# .txt file and $StandaloneDefinition{$context} is defined.
	# Otherwise use the default %Definition glossary.
	my $definitionHashRef;
	if ($path =~ m!\.txt$!i)
		{
		if(!defined($StandaloneDefinition{$context}))
			{
			# Have we looked for a glossary?
			if (!defined($ContextCheckedForGlossary{$context})
			  || $ContextCheckedForGlossary{$context} != 1)
				{
				# Pass the path to the glossary file, not the file being viewed.
				LoadStandaloneGlossary($path, $context);
				$ContextCheckedForGlossary{$context} = 1;
				}
			}
		if(defined($StandaloneDefinition{$context}))
			{
			$definitionHashRef = $StandaloneDefinition{$context};
			}
		else
			{
			$definitionHashRef = \%Definition;
			}
		}
	else
		{
		$definitionHashRef = \%Definition;
		}

	my $linksArg = ($haveRefToText) ? undef: $linksA;
	EvaluateGlossaryCandidates($definitionHashRef, $context, $host, $port, $VIEWERNAME, $linksArg, $currentLineNumber);

	# Do all reps in reverse order for non-CodeMirror.
	my $numReps = @repStr;
	if ($numReps)
		{
		if ($haveRefToText)
			{
			for (my $i = $numReps - 1; $i >= 0; --$i)
				{
				# substr($line, $pos, $srcLen, $repString);
				substr($line, $repStartPos[$i], $repLen[$i], $repStr[$i]);
				}
			$$txtR = $line;
			}
		else # CodeMirror
			{
			for (my $i = 0; $i < $numReps; ++$i)
				{
				if ($repLen[$i] > 0)
					{
					my $nextLinkPos = @$linksA;
					$linksA->[$nextLinkPos]{'lineNumInText'} = $currentLineNumber;
					$linksA->[$nextLinkPos]{'columnInText'} = $repStartPos[$i];
					$linksA->[$nextLinkPos]{'textToMarkUp'} = substr($line, $repStartPos[$i], $repLen[$i]);
					$linksA->[$nextLinkPos]{'linkType'} = $repLinkType[$i];
					$linksA->[$nextLinkPos]{'linkPath'} = $repStr[$i];
					}
				}
			}
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
	my ($definitionHashRef, $context, $host, $port, $VIEWERNAME, $linksA, $currentLineNumber) = @_;
	my $haveLinksA = (defined($linksA)) ? 1 : 0;

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
				if (defined($definitionHashRef->{$term}) && !RangeOverlapsExistingAnchor($startPos, $endPos))
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
						# Skip if term is inside a FLASH link.
						my $insideLink = 0;
						my $repLength = length($words);
						my $repStartPosition = $startPos;

						if ($haveLinksA)
							{
							# Don't put the popup if we are inside a FLASH link.
							my $nextLinkPos = @$linksA;
							if ($repLength > 0 && $nextLinkPos > 0)
								{
								for (my $j = 0; $j < $nextLinkPos; ++$j)
									{
									my $lineNum = $linksA->[$j]{'lineNumInText'};
									if ($lineNum == $currentLineNumber)
										{
										my $previousStartPos = $linksA->[$j]{'columnInText'};
										if ($previousStartPos <= $repStartPosition)
											{
											my $previousRepLen = length($linksA->[$j]{'textToMarkUp'});
											if ($previousStartPos + $previousRepLen >= $repStartPosition)
												{
												$insideLink = 1;
												last;
												}
											}
										}
									}
								}
							}

						if (!$insideLink)
							{
							my $definitionAlreadySeen = 0;
							###my $definitionAlreadySeen = (defined($DefinitionSeenInDocument{$term})) ? 1 : 0;
							my $replacementHint = GetReplacementHint($definitionHashRef, $term, $words, $definitionAlreadySeen, $context, $host, $port, $VIEWERNAME);
							push @repStr, $replacementHint;
							push @repLen, $repLength;
							push @repStartPos, $repStartPosition;
							if (!$haveRefToText)
								{
								push @repLinkType, 'glossary';
								}
							$startPosSeen[$posIndex] = $startPos;
							$endPosSeen[$posIndex++] = $startPos + $repLength;
							###$DefinitionSeenInDocument{$term} = 1;
							$DefinitionSeenOnLine{$term} = 1;
							}
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
	my $numLinkTypes = @repLinkType;
	if ($numLinkTypes)
		{
		@repLinkType = @repLinkType[@idx];
		}
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
	my ($definitionHashRef, $term, $originalText, $definitionAlreadySeen, $context, $host, $port, $VIEWERNAME) = @_;
	my $class = $definitionAlreadySeen ? 'glossary term-seen': 'glossary';
	my $gloss = $definitionHashRef->{$term}; # 'This is a gloss. This is only gloss. In the event of a real gloss this would be interesting.'
	my $result = '';
	
	# If the $gloss is just an image name, put in the image path as content of showhint() popup,
	# otherwise it's a text popup using the $gloss verbatim.
	my $glossaryImageName = ImageNameFromGloss($gloss);
	my $glossaryImagePath = FullPathForImageFileName($glossaryImageName, $context);

	if ($glossaryImagePath ne '')
		{
		my $imagePath = "http://$host:$port/$VIEWERNAME/$glossaryImagePath";
		if ($haveRefToText)
			{
			$imagePath =~ s!%!%25!g;
			$imagePath =~ s!\+!\%2B!g;
			}
		else # CodeMirror
			{
			$imagePath =~ s!\\!/!g;
			}
		$result = "<a class='$class' href=\"#\" onmouseOver=\"showhint('<img src=&quot;$imagePath&quot;>', this, event, '600px', true, true);\">$originalText</a>";
		}
	else
		{
		my $glossed = '';
		# If a glossary entry has synonyms, show just the relevant one at start of the
		# $gloss entry, and show other synonyms in a new para at bottom of the entry.
		if ($gloss =~ m!^<p>([^:]+)\:!)
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
			Gloss("**$termShown**: " . $gloss . $altList, $host, $port, \$glossed, 0, $IMAGES_DIR, $COMMON_IMAGES_DIR, $context, $callbackFullPath, $callbackFullDirectoryPath);
			$glossed = uri_escape_utf8($glossed);

			# Spurious LF's, stomp them with malice.
			$glossed =~ s!\%0A!!g;
			$gloss = $glossed;
			}
		
		$result = "<a class='$class' href=\"#\" onmouseover=\"showhint('$gloss', this, event, '600px', false, true);\">$originalText</a>";
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
	
	if ( $gloss =~ m!^<p>[^:]+:\s*\&quot;([^>]+)\&quot;\.?</p>$!i
		|| $gloss =~ m!^<p>[^:]+:\s*"([^">]+)"\.?</p>$!i
	  	|| $gloss =~ m!^<p[^>]+>[^:]+:\s*</span>&quot;(.+?)&quot;\.?</p>$!i
		|| $gloss =~ m!^<p[^>]+>[^:]+:\s*</span>"(.+?)"\.?</p>$!i )
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

sub FullPathForImageFileName {
	my ($fileName, $contextDir) = @_;
	
	my $filePath = '';
	if (FileOrDirExistsWide($IMAGES_DIR . $fileName) == 1)
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

	return($filePath);
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
# (This doesn't work with CodeMirror views, anchors aren't in the text.
# However, only "cosmetic" problems result from an overlap, all the
# links and popups still work, and it would be a nightmare to fix,
# so I'm leaving it as-is.)
# Added later, stay out of <img src='$imagePath'> elements too.
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
		
	if (!$insideExistingAnchor && index($line, '<img') > 0)
		{
		# Does any img overlap?
		my $pos = 0;
		my $nextPos = 0;
		while (($nextPos = index($line, '<img', $pos)) >= 0)
			{
			my $aStart = $nextPos;
			my $aEnd = index($line, '>', $nextPos);
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

use ExportAbove;
1;
