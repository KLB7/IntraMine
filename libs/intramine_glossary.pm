# intramine_glossary.pm: load and retrieve glossary definitions from glossary files.
# Used by intramine_linker.pl (which calls AddGlossaryHints()).
# Hints are shown in response to onmouseover, using tooltip.js#showhint().
# Secondary hints are shown within the main hints, in response to CSS hover.
# See IntraMine's Documentation/Glossary popups.txt for usage.

package intramine_glossary;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use Carp 'cluck';
use utf8;
use URI::Escape;
use HTML::Entities;
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

my %GlossaryModDates;    # $GlossaryModDates{glossary file path} = mod date for file as string.
my %Definition;          # $Definition{'term'} = 'definition';
# For standalone .txt files in a folder that has a glossary.txt file at the same
# level, use that glossary instead of entries from the glossary_master.txt files.
my %StandaloneDefinition;         # $StandaloneDefinition{$context}{term} = definition;
my %ContextCheckedForGlossary;    # $ContextCheckedForGlossary{$context} exists if checked.
my %DefinitionSeenInDocument;     # Not implemented here, might re-instate.

sub ClearDocumentGlossaryTermsSeen {
	%DefinitionSeenInDocument = ();
}

# Multiple glossary files are supported. They must all have the same name
# (default glossary_master.txt). All glossary entries are loaded into the
# same %Definition hash, and all are used by AddGlossaryHints() below
# when putting glossary hints in the text of a file.
sub LoadAllGlossaries {
	my ($allpaths, $imagesDir, $commonImagesDir, $theFullPathCallback,
		$theFullDirectoryPathCallback)
		= @_;
	$IMAGES_DIR                = $imagesDir;
	$COMMON_IMAGES_DIR         = $commonImagesDir;
	$callbackFullPath          = $theFullPathCallback;
	$callbackFullDirectoryPath = $theFullDirectoryPathCallback;

	my @paths;
	if ($allpaths =~ m!\|!)    # more than one candidate full path
		{
		@paths = split(/\|/, $allpaths);
		}
	else
		{
		push @paths, $allpaths;
		}

	for (my $i = 0 ; $i < @paths ; ++$i)
		{
		# TEST ONLY
		#print("Loading glossary |$paths[$i]|\n");

		LoadGlossary($paths[$i]);
		}

	my $numDefs = keys %Definition;
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
	my $doingStandaloneGlossary = 0;

	if (FileOrDirExistsWide($filePath) != 1)
		{
		#print("|$filePath| not found.\n");
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
		$doingStandaloneGlossary = 1;
		if (defined($forceInit) || !defined($StandaloneDefinition{$context}))
			{
			%{$StandaloneDefinition{$context}} = ();
			}
		$definitionHashRef = $StandaloneDefinition{$context};
		}
	else
		{
		$definitionHashRef = \%Definition;
		}


	my @lines = split(/\n/, $octets);

	my @currentTerms;
	for (my $i = 0 ; $i < @lines ; ++$i)
		{
		# Skip comment lines, they start with '##' (but not one or more than two #'s).
		if ($lines[$i] =~ m!^##($|[^#])!)
			{
			;    # skip
			}
		# match up to ':' but not '\:'.
		elsif ($lines[$i] =~ m!^\s*(.+?[^\\]):!)
			#elsif ($lines[$i] =~ m!^\s*([^:]+)\:!)
			{
			my $terms = $1;
			$terms =~ s!\*!!g;
			@currentTerms = split(/,\s*/, lc($terms));
			my $entry = $lines[$i];
			chomp($entry);
			# For display, remove '\' from '\:'.
			$entry =~ s!\\:!:!g;

			$entry =~ s!\&#39;!\&#8216;!g;

			for (my $j = 0 ; $j < @currentTerms ; ++$j)
				{
				$definitionHashRef->{$currentTerms[$j]} = "<p>$entry</p>";
				}
			}
		elsif (@currentTerms != 0)    # Skip top lines without colons
			{
			my $entry = $lines[$i];
			chomp($entry);
			# For display, remove '\' from '\:'.
			$entry =~ s!\\:!:!g;

			if ($entry ne '')
				{
				$entry =~ s!\&#39;!\&#8216;!g;
				for (my $j = 0 ; $j < @currentTerms ; ++$j)
					{
					$definitionHashRef->{$currentTerms[$j]} .= "<p>$entry</p>";
					}
				}
			}
		}


	if (!$doingStandaloneGlossary)
		{
		;    #print("|$filePath| glossary loaded.\n");
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

	return ($result);
}

# Get text file as a big string. Returns 1 if successful, 0 on failure.
sub LoadTextFileContents {
	my ($filePath, $octetsR) = @_;

	$$octetsR = ReadTextFileWide($filePath);
	if (!defined($$octetsR))
		{
		return (0);
		}
	my $decoder = Encode::Guess->guess($$octetsR);

	my $eightyeightFired = 0;
	if (ref($decoder))
		{
		my $decoderName = $decoder->name();
		if ($decoderName =~ m!iso-8859-\d+!)
			{
			$$octetsR         = $decoder->decode($$octetsR);
			$eightyeightFired = 1;
			}
		}

	if (!$eightyeightFired)
		{
		$$octetsR = decode_utf8($$octetsR);
		}

	return (1);
}

sub IsGlossaryPath {
	my ($filePath) = @_;
	$filePath = lc($filePath);
	my $result = 0;

	if (defined($GlossaryModDates{$filePath}))
		{
		$result = 1;
		}
	return ($result);
}

sub AddGlossaryHints {
	my ($txtR, $path, $host, $port, $VIEWERNAME, $inPopup, $currentLineNumber, $linksA) = @_;
	# Note $currentLineNumber, $linksA are set only for CodeMirror ($haveRefToText == 0).

	my $line;

	# In non-CodeMirror views where the text is directly altered, replacements are
	# more easily done in reverse order to avoid throwing off the start/end.
	# For CodeMirror the @repStr etc entries are passed back without altering the text.
	my $haveRefToText;             # For CodeMirror we get the text not a ref, and this is 0.
	if (ref($txtR) eq 'SCALAR')    # REFERENCE to a scalar, so doing text
		{
		$haveRefToText = 1;
		$line          = $$txtR;
		}
	else                           # not a ref, so doing CodeMirror
		{
		$haveRefToText = 0;
		$line          = $txtR;
		}

	my @repStr;    # new link, eg <a href="#Header_within_doc">#Header within doc</a>
	my @repLen;    # length of substr to replace in line, eg length('#Header within doc')
	my @repStartPos
		; # where header being replaced starts, eg zero-based positon of '#' in '#Header within doc'
	my @repLinkType;    # For CodeMirror, 'glossary' is the only type here.

	my $context = DirectoryFromPathTS($path);

	# As a special case,
	# Use $StandaloneDefinition{$context} instead of \%Definition if we have a
	# .txt file and $StandaloneDefinition{$context} is defined.
	# Otherwise use the default %Definition glossary.
	my $definitionHashRef;
	if ($path =~ m!\.txt$!i)
		{
		if (!defined($StandaloneDefinition{$context}))
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
		if (defined($StandaloneDefinition{$context}))
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

	my $linksArg = ($haveRefToText) ? undef : $linksA;

	# Special handling for .md, avoid terms inside alt tags.
	# Special handling is needed for Markdown files, skip
	# glossary terms inside alt tags for .md and .markdown.
	my $isMarkdown = 0;

	if ($path =~ m!\.md$!i || $path =~ m!\.markdown$!i)
		{
		$isMarkdown = 1;
		}

	my $numReps;
	if ($inPopup)
		{
		# Secondary popups only, because we're already in a popup.
		$repStr[0]      = $line;
		$repLen[0]      = length($line);
		$repStartPos[0] = 0;
		$numReps        = 1;
		AddSecondaryGlossaryEntries(
			$isMarkdown,    $definitionHashRef, $context,  $host,
			$port,          $VIEWERNAME,        $linksArg, $currentLineNumber,
			$haveRefToText, \@repStr,           \@repLen,  \@repStartPos,
			0
		);
		}
	else
		{
		my %DefinitionSeenOnLine;
		EvaluateGlossaryCandidates(
			$line,              $isMarkdown,    $definitionHashRef, $context,
			$host,              $port,          $VIEWERNAME,        $linksArg,
			$currentLineNumber, $haveRefToText, \@repStr,           \@repLen,
			\@repStartPos,      \@repLinkType,  \%DefinitionSeenOnLine
		);

		$numReps = @repStr;

		# Put glossary popups in the glossary popups.
		for (my $i = 0 ; $i < $numReps ; ++$i)
			{
			if ($repLen[$i] > 0)
				{
				# Avoid putting in a popup for the primary glossary entry.
				#my $termToSkip = lc(substr($line, $repStartPos[$i], $repLen[$i]));

				AddSecondaryGlossaryEntries(
					$isMarkdown,    $definitionHashRef, $context,  $host,
					$port,          $VIEWERNAME,        $linksArg, $currentLineNumber,
					$haveRefToText, \@repStr,           \@repLen,  \@repStartPos,
					$i
				);
				}
			}
		}

	# Do all reps in reverse order for non-CodeMirror.
	if ($numReps)
		{
		if ($haveRefToText)
			{
			for (my $i = $numReps - 1 ; $i >= 0 ; --$i)
				{
				# substr($line, $pos, $srcLen, $repString);
				substr($line, $repStartPos[$i], $repLen[$i], $repStr[$i]);
				}
			$$txtR = $line;
			}
		else    # CodeMirror
			{
			for (my $i = 0 ; $i < $numReps ; ++$i)
				{
				if ($repLen[$i] > 0)
					{
					my $nextLinkPos = @$linksA;
					$linksA->[$nextLinkPos]{'lineNumInText'} = $currentLineNumber;
					$linksA->[$nextLinkPos]{'columnInText'}  = $repStartPos[$i];
					$linksA->[$nextLinkPos]{'textToMarkUp'} =
						substr($line, $repStartPos[$i], $repLen[$i]);
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
	my (
		$line,              $isMarkdown,    $definitionHashRef, $context,
		$host,              $port,          $VIEWERNAME,        $linksA,
		$currentLineNumber, $haveRefToText, $repStrA,           $repLenA,
		$repStartPosA,      $repLinkTypeA,  $definitionSeenOnLineH
	) = @_;
	my $haveLinksA          = (defined($linksA))                                          ? 1 : 0;
	my $doingSecondaryPopup = (defined($currentLineNumber) && $currentLineNumber == -999) ? 1 : 0;

	my @startPosSeen;    # Track glosses to avoid doubling up - longest wins.
	my @endPosSeen;      # Length of a matched term, also indexed by $startPos
	my $posIndex = 0;

	my @wordStartPos;
	my @wordEndPos;
	if ($doingSecondaryPopup)
		{
		GetPcLineWordStartsAndEnds($line, \@wordStartPos, \@wordEndPos);
		}
	else
		{
		GetLineWordStartsAndEnds($line, \@wordStartPos, \@wordEndPos);
		}

	my $altPos = -1;
	# This isn't bulletproof, will fail on a spurious "Alt: ".
	$altPos = rindex($line, 'Alt: ');
	if ($altPos < 0)
		{
		$altPos = rindex($line, 'Alt%3A%20');
		}

	my $numWordStarts = @wordStartPos;

	# Four-word matches down to one-word matches:
	my $nWords = 4;

	while ($nWords >= 1)
		{
		my $nWordsMinusOne = $nWords - 1;
		my $i              = 0;
		while ($i < $numWordStarts)
			{
			if ($i < $numWordStarts - $nWordsMinusOne)
				{
				my $startPos = $wordStartPos[$i];                   # beginning of match
				my $endPos   = $wordEndPos[$i + $nWordsMinusOne];   # pos of char after end of match
				my $len      = $endPos - $startPos;
				my $words         = substr($line, $wordStartPos[$i], $len);
				my $originalWords = $words;
				# For secondaries, replace %3C etc with a single space.
				if ($doingSecondaryPopup)
					{
					# Drop out if we've hit the Alt list at the bottom of the entry.
					if ($altPos > 0 && $startPos >= $altPos)
						{
						last;
						}
					$words =~ s!(\%[0-9A-Fa-f][0-9A-Fa-f])+! !g;
					}
				my $term = lc($words);    # glossary terms are lower case in %Definition
				$term =~ s!\s+! !g;

				if (defined($definitionHashRef->{$term})
					&& !RangeOverlapsExistingAnchor($line, $startPos, $endPos, $doingSecondaryPopup)
					)
					{
					# Skip if current term formed part of a previous term.
					my $overlapped = 0;
					for (my $j = 0 ; $j < $posIndex ; ++$j)
						{
						if ($startPos >= $startPosSeen[$j] && $endPos <= $endPosSeen[$j])
							{
							$overlapped = 1;
							last;
							}
						}

					if (!$overlapped && !defined($definitionSeenOnLineH->{$term}))
						{
						# Skip if term is inside a FLASH link.
						my $insideLink       = 0;
						my $repLength        = length($originalWords);
						my $repStartPosition = $startPos;

						if ($haveLinksA)
							{
							# Don't put the popup if we are inside a FLASH link.
							my $nextLinkPos = @$linksA;
							if ($repLength > 0 && $nextLinkPos > 0)
								{
								for (my $j = 0 ; $j < $nextLinkPos ; ++$j)
									{
									my $lineNum = $linksA->[$j]{'lineNumInText'};
									if ($lineNum == $currentLineNumber)
										{
										my $previousStartPos = $linksA->[$j]{'columnInText'};
										if ($previousStartPos <= $repStartPosition)
											{
											my $previousRepLen =
												length($linksA->[$j]{'textToMarkUp'});
											if ($previousStartPos + $previousRepLen >=
												$repStartPosition)
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
							# Avoid terms inside <img alt="a term"...>, for .md
							# files only.
							my $probablyInsideAlt = 0;
							if ($isMarkdown && index($line, '<img') == 0)
								{
								$probablyInsideAlt = 1;
								}

							if (!$probablyInsideAlt)
								{
								my $definitionAlreadySeen = 0;
								my $replacementHint       = GetReplacementHint(
									$definitionHashRef, $term,
									$words,             $definitionAlreadySeen,
									$context,           $host,
									$port,              $VIEWERNAME,
									$haveRefToText,     $doingSecondaryPopup
								);

								push @{$repStrA},      $replacementHint;
								push @{$repLenA},      $repLength;
								push @{$repStartPosA}, $repStartPosition;
								if (!$haveRefToText)
									{
									push @{$repLinkTypeA}, 'glossary';
									}
								$startPosSeen[$posIndex] = $startPos;
								$endPosSeen[$posIndex++] = $startPos + $repLength;

								# Skip any new "Alt: " terms.
								SkipAltTerms($replacementHint, $definitionSeenOnLineH);
								}
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

	SortGlossaryResultsForOneLine($repStrA, $repLenA, $repStartPosA, $repLinkTypeA);
}

# Poke alt synonymns for a glossary term into %$definitionSeenOnLineH.
# Some of this is probably not needed (but harmless).
sub SkipAltTerms {
	my ($line, $definitionSeenOnLineH) = @_;

	# Pick up the main entry near the start, <strong>Main entry</strong>.
	if ($line =~ m!%3Cstrong%3E(.+?)%3C%2Fstrong%3E! || $line =~ m!<strong>(.+?)</strong>!)
		{
		my $mainEntry = lc($1);
		$definitionSeenOnLineH->{$mainEntry} = 1;
		$mainEntry =~ s!%20! !g;
		$definitionSeenOnLineH->{$mainEntry} = 1;
		}

	# If the popup has been processed, there will be an Alt: at the end
	# followed by synonyms.
	# Skip trailing "Alt: " synonyms, don't put popups on them.
	my $altPos = -1;
	# This isn't bulletproof, will fail on a spurious "Alt: ".
	my $startSkip = 5;    # Length of 'Alt: '
	$altPos = rindex($line, 'Alt: ');
	if ($altPos < 0)
		{
		$altPos    = rindex($line, 'Alt%3A%20');
		$startSkip = 9;                            # Length of 'Alt%3A%20'
		}
	if ($altPos < 0)
		{
		$altPos    = rindex($line, 'alt%3a%20');
		$startSkip = 9;                            # Length of 'Alt%3A%20'
		}

	if ($altPos > 0)
		{
		my $altString = substr($line, $altPos + $startSkip);
		$altString =~ s!%2C!,!gi;
		$altString =~ s!\*!!g;
		$altString =~ s!%2A!!gi;

		my @alts    = split(/,/, $altString);
		my $numAlts = @alts;
		for (my $i = 0 ; $i < @alts ; ++$i)
			{
			my $syn = lc($alts[$i]);        # glossary terms are lower case in %Definition
			if (1 || $i == $numAlts - 1)    # last item
				{
				# Trim '<'' and following (HTML stuff)
				my $anglePos = index($syn, '<');
				if ($anglePos < 0)
					{
					$anglePos = index($syn, '%3c');    # also '<'
					}
				if ($anglePos > 0)
					{
					$syn = substr($syn, 0, $anglePos);
					}
				}
			$syn =~ s!^\s+!!;
			$syn =~ s!\s+$!!;
			$syn =~ s!^(%20)+!!;
			$syn =~ s!(%20)+$!!;
			$definitionSeenOnLineH->{$syn} = 1;
			$syn =~ s!%20! !g;
			$definitionSeenOnLineH->{$syn} = 1;

			# And going the other way, rep space with %20.
			$syn =~ s! !%20!g;
			$definitionSeenOnLineH->{$syn} = 1;
			}
		}
	else
		{
		# Likely we're at the stage before putting in the "Alt:" at the bottom, so
		# look for the raw list of synonyms at the beginning and put them in
		# the $definitionSeenOnLineH hash.
		if ($line =~ m!^\s*(.+?[^\\]):!)
			{
			my $terms = $1;
			$terms =~ s!\*!!g;
			$terms =~ s!%2A!!g;
			my @currentTerms = split(/,/, lc($terms));
			for (my $j = 0 ; $j < @currentTerms ; ++$j)
				{
				my $syn = $currentTerms[$j];
				$syn =~ s!^\s+!!;
				$syn =~ s!\s+$!!;
				$syn =~ s!^(%20)+!!;
				$syn =~ s!(%20)+$!!;
				$definitionSeenOnLineH->{$syn} = 1;

				$syn =~ s!%20! !g;
				$definitionSeenOnLineH->{$syn} = 1;
				# And going the other way, rep space with %20.
				$syn =~ s! !%20!g;
				$definitionSeenOnLineH->{$syn} = 1;
				}
			}
		}

	# One last check, are we in a "pure image" type of glossary entry?
	# Typical pure image entry:
	# <a class='glossary' href="#" onmouseOver="showhint('<img src=&quot;http://192.168.40.8:81/Viewer/C:/perlprogs/IntraMine/images_for_web_server/tenor.gif&quot;>', this, event, '600px', true, true);">CTRL+C</a>
	if ($line =~ m!^<a class='glossary'.+?;">([^<]+)</a>!)
		{
		my $term = lc($1);
		$term =~ s!(\%[0-9A-Fa-f][0-9A-Fa-f])+! !g;
		$term =~ s!\s+! !g;
		$definitionSeenOnLineH->{$term} = 1;
		}
}

# After primary popups have been collected in @$repStrA, go over one particular
# popup $repStrA->[$i] and add secondary popups. Put the secondaries directly  into
# $repStrA->[$i]. Primary popups use showhint(onmouseover='...'), seconary popups
# use a CSS approach with .popup-wrapper and .popup-content to show/hide the popup.
sub AddSecondaryGlossaryEntries {
	my (
		$isMarkdown,    $definitionHashRef, $context,  $host,
		$port,          $VIEWERNAME,        $linksArg, $currentLineNumber,
		$haveRefToText, $repStrA,           $repLenA,  $repStartPosA,
		$i
	) = @_;

	my $line = $repStrA->[$i];
	my @repStrTWO;    # new link, eg <a href="#Header_within_doc">#Header within doc</a>
	my @repLenTWO;    # length of substr to replace in line, eg length('#Header within doc')
	my @repStartPosTWO
		; # where header being replaced starts, eg zero-based positon of '#' in '#Header within doc'
	my @repLinkTypeTWO;    # For CodeMirror, 'glossary' is the only type here.

	my %DefinitionSeenOnLine;
	SkipAltTerms($line, \%DefinitionSeenOnLine);

	# $currentLineNumber of -999 means GetReplacementHint does secondary popup replacement
	EvaluateGlossaryCandidates(
		$line,            $isMarkdown,      $definitionHashRef, $context,
		$host,            $port,            $VIEWERNAME,        $linksArg,
		-999,             $haveRefToText,   \@repStrTWO,        \@repLenTWO,
		\@repStartPosTWO, \@repLinkTypeTWO, \%DefinitionSeenOnLine
	);

	my $numReps = @repStrTWO;
	if ($numReps)
		{
		my $numFirstOderReps = @{$repStrA};
		for (my $j = $numReps - 1 ; $j >= 0 ; --$j)
			{
			# substr($line, $pos, $srcLen, $repString);
			substr($line, $repStartPosTWO[$j], $repLenTWO[$j], $repStrTWO[$j]);
			#my $oldRepLen = length($repStrTWO[$j]);
			}

		$repStrA->[$i] = $line;
		}
}

# Sort @repStartPos, @repLen, and @repStr in ascending order by @repStartPos.
sub SortGlossaryResultsForOneLine {
	my ($repStrA, $repLenA, $repStartPosA, $repLinkTypeA) = @_;
	my $numReps = @$repStartPosA;
	if (!$numReps)
		{
		return;
		}

	my @idx = sort {$repStartPosA->[$a] <=> $repStartPosA->[$b]} 0 .. $#{$repStartPosA};
	@{$repStrA}      = @{$repStrA}[@idx];
	@{$repLenA}      = @{$repLenA}[@idx];
	@{$repStartPosA} = @{$repStartPosA}[@idx];
	my $numLinkTypes = @{$repLinkTypeA};
	if ($numLinkTypes)
		{
		@{$repLinkTypeA} = @{$repLinkTypeA}[@idx];
		}
}

# Find start and end positions of words in line.
sub GetLineWordStartsAndEnds {
	my ($line, $startA, $endA) = @_;

	while ($line =~ m!([\w'-]+)!g)
		{
		my $startPos = $-[1];    # beginning of match
		my $endPos   = $+[1];    # one past last matching character
		push @$startA, $startPos;
		push @$endA,   $endPos;
		}
}

# Find start and end positions of words in line, with % encoding.
sub GetPcLineWordStartsAndEnds {
	my ($line, $startA, $endA) = @_;

	# A wee fudge, replace %3C etc with three spaces.
	$line =~ s!\%[0-9A-Fa-f][0-9A-Fa-f]!   !g;

	while ($line =~ m!([\w'-]+)!g)
		{
		my $startPos = $-[1];    # beginning of match
		my $endPos   = $+[1];    # one past last matching character
		push @$startA, $startPos;
		push @$endA,   $endPos;
		}
}

# Return the full glossary definition, in an anchor element.
# If the entry is just an image, put in the image as the hint.
# If the entry has synonyms, remove them from the term being defined and show them
# as "Alt: " in a new paragraph at the bottom of the hint.
sub GetReplacementHint {
	my (
		$definitionHashRef, $term, $originalText, $definitionAlreadySeen,
		$context,           $host, $port,         $VIEWERNAME,
		$haveRefToText,     $doingSecondaryPopup
	) = @_;
	my $class  = $definitionAlreadySeen ? 'glossary term-seen' : 'glossary';
	my $gloss  = $definitionHashRef->{$term};
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
		else    # CodeMirror
			{
			$imagePath =~ s!\\!/!g;
			}
		if ($doingSecondaryPopup)
			{
			$result =
"<span class=_AMR_quot;popup-wrapper_AMR_quot;>$originalText<span class=_AMR_quot;popup-content_AMR_quot;>___GLOSS_GOES_HERE___</span></span>";
			$result = uri_escape_utf8($result);
			my $imageElement = "<img src=_AMR_quot;$imagePath" . "_AMR_quot; />";
			$result =~ s!___GLOSS_GOES_HERE___!$imageElement!;
			}
		else
			{
			$result =
"<a class='$class' href=\"#\" onmouseOver=\"showhint('<img src=&quot;$imagePath&quot;>', this, event, '600px', true, true);\">$originalText</a>";
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

			my @synonyms         = split(/,\s*/, $terms);
			my $numSynonymsTotal = @synonyms;
			my $altList          = '';
			$gloss =~ s!^<p>([^:]+):\s*!!;    # Strip terms from start, up to just before ':'
			$gloss =~ s!\<p>!!g;
			$gloss =~ s!\</p>!\n!g;
			chomp($gloss);                    # Get rid of trailing blank line.

			if ($numSynonymsTotal > 1)
				{
				# Show term at start of gloss, then definition. Follow with synonyms.
				my @otherSynonyms;
				for (my $i = 0 ; $i < $numSynonymsTotal ; ++$i)
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
				# Add a line.
				$gloss .= "\n";
				}

			# Apply Gloss to the glossary entry (sorry about that);
			Gloss(
				"**$termShown**: " . $gloss . $altList, $host,
				$port,                                  \$glossed,
				1,                                      $IMAGES_DIR,
				$COMMON_IMAGES_DIR,                     $context,
				$callbackFullPath,                      $callbackFullDirectoryPath,
				2,                                      2,
				0
			);

			$glossed = uri_escape_utf8($glossed);

			# Spurious LF's, stomp them with malice.
			$glossed =~ s!\%0A!!g;
			$gloss = $glossed;
			}

		if ($doingSecondaryPopup)
			{
			$result =
"<span class=_AMR_quot;popup-wrapper_AMR_quot;>$originalText<span class=_AMR_quot;popup-content_AMR_quot;>___GLOSS_GOES_HERE___</span></span>";
			# 			$result =
			# "<span class='popup-wrapper'>$originalText<div class='popup-content'>___GLOSS_GOES_HERE___</div></span>";
			$result = uri_escape_utf8($result);
			$result =~ s!___GLOSS_GOES_HERE___!$gloss!;
			}
		else
			{
			$result =
"<a class='$class' href=\"#\" onmouseover=\"showhint('$gloss', this, event, '600px', false, true);\">$originalText</a>";
			}
		}

	return ($result);
}

#Not used here.
sub horribleUnescape {
	my ($text) = @_;

	$text =~ s!_EQR_!\=!g;
	$text =~ s!_DQR_!\"!g;
	$text =~ s!_SQR_!\'!g;
	$text =~ s!_PSR_!\+!g;
	$text =~ s!_PCR_!\%!g;
	$text =~ s!_AMR_!\&!g;
	$text =~ s!_TR_!\t!g;    # true tab, as opposed to \t
	$text =~ s!_BSR_!\\!g;

	return ($text);
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

	if (   $gloss =~ m!^<p>[^:]+:\s*\&quot;([^>]+)\&quot;\.?</p>$!i
		|| $gloss =~ m!^<p>[^:]+:\s*"([^">]+)"\.?</p>$!i
		|| $gloss =~ m!^<p[^>]+>[^:]+:\s*</span>&quot;(.+?)&quot;\.?</p>$!i
		|| $gloss =~ m!^<p[^>]+>[^:]+:\s*</span>"(.+?)"\.?</p>$!i)
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

	return ($result);
}

sub FullPathForImageFileName {
	my ($fileName, $contextDir) = @_;

	my $filePath = '';
	if (FileOrDirExistsWide($fileName) == 1)    # is $fileName a full path
		{
		$filePath = $fileName;
		}
	elsif (defined($IMAGES_DIR) && &FileOrDirExistsWide($IMAGES_DIR . $fileName) == 1)
		{
		$filePath = $IMAGES_DIR . $fileName;
		}
	elsif (defined($COMMON_IMAGES_DIR)
		&& $COMMON_IMAGES_DIR ne ''
		&& FileOrDirExistsWide($COMMON_IMAGES_DIR . $fileName) == 1)
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

	# Welcome to the Twilight Zone. '%' in a path here is not currently
	# supported, so we punt to full glossary popup handling as done by
	# gloss.pm#Gloss(), which does handle '%' properly.
	if (index($filePath, '%') >= 0)
		{
		$filePath = '';
		}
	return ($filePath);
}

sub AnchorForGlossaryTerm {
	my ($term) = @_;

	$term =~ s!&nbsp;!_!g;
	$term =~ s!['"]!!g;
	$term =~ s!\&#\d+;!!g;    # eg &#9755;
	$term =~ s!\s!_!g;
	$term =~ s!\-!_!g;

	return ($term);
}

# Is $startPos or $endPos inside an <a>...</a> element?
# Also skip if $startPos in inside the opener of <h1 2 or 3.
# (This doesn't work with CodeMirror views, anchors aren't in the text.
# However, only "cosmetic" problems result from an overlap, all the
# links and popups still work, and it would be a nightmare to fix,
# so I'm leaving it as-is.)
# Added later, stay out of <img src='$imagePath'> elements too.
sub RangeOverlapsExistingAnchor {
	my ($line, $startPos, $endPos, $doingSecondaryPopup) = @_;

	my $insideExistingAnchor = 0;

	# First, and annoyingly, check if we're in an anchor already without <a being present.
	# Look for |onclick="diffMarkerClicked| and if so $startPos between there and </a> or </td>
	# counts as inside an anchor. Also if no start anchor <a is seen count start of line
	# as beginning of an anchor
	my $onclickPosition = index($line, 'onclick="diffMarkerClicked');
	if ($onclickPosition >= 0 || index($line, '<a') < 0)
		{
		my $endAnchorPosition = index($line, '</a>',  $onclickPosition + 1);
		my $endCellPosition   = index($line, '</td>', $onclickPosition + 1);
		my $endPosition       = -1;
		if ($endAnchorPosition >= 0)
			{
			if ($endCellPosition >= 0)
				{
				if ($endAnchorPosition < $endCellPosition)
					{
					$endPosition = $endAnchorPosition;
					}
				else
					{
					$endPosition = $endCellPosition;
					}
				}
			else
				{
				$endPosition = $endAnchorPosition;
				}
			}
		elsif ($endCellPosition >= 0)
			{
			$endPosition = $endCellPosition;
			}

		if ($onclickPosition < 0 && $endPosition > 0)
			{
			$onclickPosition = 0;
			}

		if (   $endPosition > 0
			&& $onclickPosition > 0
			&& $startPos >= $onclickPosition
			&& $startPos <= $endPosition)
			{
			$insideExistingAnchor = 1;

			# One last check: we want to allow glossary popups in footnote bodies
			# There, the telltale for the first line at least is
			# div id='fnN' where N is an integer 1..up or class _FOOTNOTE_ is present.
			if ($line =~ m!div\s+id=['"]fn\d+['"]! || $line =~ m!class=['"]_FOOTNOTE_['"]!)
				{
				$insideExistingAnchor = 0;
				}
			else
				{
				return ($insideExistingAnchor);    # EARLY RETURN, I am fed up with this problem
				}
			}
		}

	# Is there an anchor on the line? Skip line start if doing a secondary popup
	# (since the "$line" starts with <a class='glossary').
	# We also look for %3Ca (which happens in secondary popups).
	my $anchorStartPosition = ($doingSecondaryPopup) ? 3 : 0;
	if (index($line, '<a', $anchorStartPosition) > 0 || index($line, '%3Ca') > 0)
		{
		# Does any anchor overlap?
		my $pos            = $anchorStartPosition;
		my $nextPos        = index($line, '<a',   $pos);
		my $nextPosPercent = index($line, '%3Ca', $pos);
		$nextPos =
			($nextPosPercent >= 0 && ($nextPos < 0 || $nextPosPercent < $nextPos))
			? $nextPosPercent
			: $nextPos;
		while ($nextPos >= 0)
			{
			my $aStart      = $nextPos;
			my $aEnd        = index($line, '</a>',    $nextPos);
			my $aEndPercent = index($line, '%3C%2Fa', $nextPos);
			#$aEnd = ($aEndPercent < $aEnd) ? $aEndPercent : $aEnd;
			$aEnd =
				($aEndPercent >= 0 && ($aEnd < 0 || $aEndPercent < $aEnd)) ? $aEndPercent : $aEnd;

			if ($aEnd > 0)
				{
				if (   ($startPos >= $aStart && $startPos <= $aEnd)
					|| ($endPos >= $aStart && $endPos <= $aEnd))
					{
					$insideExistingAnchor = 1;
					last;
					}
				}
			else    # should not happen, like, ever.
				{
				$insideExistingAnchor = 1;
				last;
				}

			$pos            = $aEnd + 1;
			$nextPos        = index($line, '<a',   $pos);
			$nextPosPercent = index($line, '%3Ca', $pos);
			$nextPos =
				($nextPosPercent >= 0 && ($nextPos < 0 || $nextPosPercent < $nextPos))
				? $nextPosPercent
				: $nextPos;
			}
		}
	else
		{
		if (!$doingSecondaryPopup)
			{
			my $aEnd = index($line, '</a>');
			if ($aEnd > $startPos)
				{
				$insideExistingAnchor = 1;
				}
			}
		}

	if (!$insideExistingAnchor && index($line, '<img') > 0)
		{
		# Does any img overlap?
		my $pos     = 0;
		my $nextPos = 0;
		while (($nextPos = index($line, '<img', $pos)) >= 0)
			{
			my $aStart = $nextPos;
			my $aEnd   = index($line, '>', $nextPos);
			if ($aEnd > 0)
				{
				if (   ($startPos >= $aStart && $startPos <= $aEnd)
					|| ($endPos >= $aStart && $endPos <= $aEnd))
					{
					$insideExistingAnchor = 1;
					last;
					}
				}
			else    # should not happen, like, ever.
				{
				$insideExistingAnchor = 1;
				last;
				}

			$pos = $aEnd + 1;
			}
		}

	if (!$insideExistingAnchor && index($line, '<h') > 0)
		{
		my $startH = index($line, '<h');
		my $endH   = index($line, '>', $startH + 1);
		if ($startPos > $startH && $startPos < $endH)
			{
			$insideExistingAnchor = 1;
			}
		}

	return ($insideExistingAnchor);
}

use ExportAbove;
1;
