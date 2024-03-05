# intramine_linker.pl: IntraMine's autolinker (in combination with reverse_filepaths.pm).
# Pass in plain text containing mentions of other files, and get back either:
# text with links - see NonCmLinks()
# or a JSON summary of the links that can be used to create an overlay for CodeMirror
# - see CmLinks().
# File and web links are handled, "internal" links within a document are done
# in intramine_viewer.pl.
# FullPathForPartial() will return its best guess at a full path, given a single partial path
# (use when there is no relevant "context").
#
# Links suported here:
# - FLASH links: if you type just a file name in a text file or a source file,
#    IntraMine will link it to the closest known instance of that file, from amongst
#    all the files of interest to you. Links to locations within files are also
#    supported, such as "Linker.html#What the Linker does differently" or
#    reverse_filepaths.pm#FullPathInContextNS().
# - web links: http(s), eg https://www.google.com
# - Perl module links eg "use X::Y;"
#
# A "partial path" is a file name with extension) preceded by zero or more directory
# names, in any order, not necessariy consecutive, with slashes after each directory name
# (and of course a drive name can be supplied). For example, if
# C:/projects/project51/src/run.cpp
# is the desired path, then the partial path could be
# run.cpp or projects/run.cpp or C:/run.cpp or project51/projects.cpp etc.
#
# FLASH links also use the notion of "context directory", the location of the file
# mentioning the partial path. You might for example be writing
# in project51/docs/Log_Sept_20201.txt and type in "run.cpp": if there are several
# run.cpp files in your indexed folders, then the run.cpp closest to the Log_Sept_20201.txt
# will be chosen for the link - in the above example, that would be project51/src/run.cpp.

# This server is a second level server without any displayed interface, and all calls
# to retrieve links are done with JavaScript in the Viewer and Files servers.
# In the Viewer service's front end JavaScript:
# - To trace CodeMirror autolinks, start with cmAutoLinks.js#addAutoLinks(), which ends up
# calling back to CmLinks() via "req=cmLinks".
# - To trace non-CodeMirror (mainly .txt and Perl) autolinks, start with autoLinks.js#addAutoLinks(),
#  which ends up calling back to NonCmLinks() via "req=nonCmLinks".
# In the Files service's front end JavaScript:
# - FullPathForPartial() is called by files.js#openAutoLink(), via "req=autolink".

# perl C:\perlprogs\intramine\intramine_linker.pl

use strict;
use warnings;
use utf8;
use FileHandle;
use Encode;
use Encode::Guess;
use HTML::Entities;
use URI::Escape;
use Time::HiRes qw ( time );
use JSON::MaybeXS qw(encode_json);
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;
use reverse_filepaths;
use win_wide_filepaths;
use ext; # for ext.pm#IsTextExtensionNoPeriod() etc.
use intramine_glossary;

Encode::Guess->add_suspects(qw/iso-8859-1/);

$|  = 1;

my $PAGENAME = '';
my $SHORTNAME = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

# For calling a service by its Short name.
my $VIEWERNAME = CVal('VIEWERSHORTNAME');
my $EDITORNAME = CVal('EDITORSHORTNAME');
my $OPENERNAME = CVal('OPENERSHORTNAME');
my $FILESNAME = CVal('FILESSHORTNAME');
my $VIDEONAME = CVal('VIDEOSHORTNAME');

# Common locations for images.
my $IMAGES_DIR = FullDirectoryPath('IMAGES_DIR');
my $COMMON_IMAGES_DIR = CVal('COMMON_IMAGES_DIR');
if (FileOrDirExistsWide($COMMON_IMAGES_DIR) != 2)
	{
	#print("No common images dir, setting \$COMMON_IMAGES_DIR to ''\n");
	$COMMON_IMAGES_DIR = '';
	}
# Edit control.
my $UseAppForLocalEditing = CVal('USE_APP_FOR_EDITING');
my $UseAppForRemoteEditing = CVal('USE_APP_FOR_REMOTE_EDITING');
my $AllowLocalEditing = CVal('ALLOW_LOCAL_EDITING');
my $AllowRemoteEditing = CVal('ALLOW_REMOTE_EDITING');

my $kLOGMESSAGES = 0;			# 1 == Log Output() messages
my $kDISPLAYMESSAGES = 0;		# 1 == print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print.
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);

Output("Starting $SHORTNAME on port $port_listen\n\n");

# Actions. Respond to requests for links, from CodeMirror views, text views, and the Files page.
my %RequestAction;
$RequestAction{'signal'} = \&HandleBroadcastRequest;	# signal=reindex or folderrenamed
$RequestAction{'req|cmLinks'} = \&CmLinks; 				# req=cmLinks... - linking for CodeMirror files
$RequestAction{'req|nonCmLinks'} = \&NonCmLinks; 		# req=nonCmLinks... - linking for non-CodeMirror files
$RequestAction{'req|autolink'} = \&FullPathForPartial; 	# req=autolink&partialpath=...
$RequestAction{'/test/'} = \&SelfTest;					# Ask this server to test itself.

# Over to swarmserver.pm. The callback sub loads in a hash of full paths for partial paths,
# which can take some time.
MainLoop(\%RequestAction, undef, undef, \&callbackInitPathsAndGlossary);

################### subs

# Generic 'signal' handler, 'signal=reindex' means that
# new files have come along, so incorporate them into full path and partial path
# lists, for putting in file links with AddFileWebAndFileLinksToLine() etc.
# See reverse_filepaths.pm#LoadIncrementalDirectoryFinderLists().
# The list of new files is in C:/fwws/fullpaths2.log.
# 'signal=folderrenamed' means a folder has been renamed (and so potentially
# many full paths could change).
sub HandleBroadcastRequest {
	my ($obj, $formH, $peeraddress) = @_;
	if (defined($formH->{'signal'}))
		{
		if ($formH->{'signal'} eq 'reindex')
			{
			Output("Reindexing.\n");
			# Load list of new file paths.
			my $FileWatcherDir = CVal('FILEWATCHERDIRECTORY');
			my $fullFilePathListPath = $FileWatcherDir . CVal('FULL_PATH_LIST_NAME'); # .../fullpaths.out
			LoadIncrementalDirectoryFinderLists($fullFilePathListPath);
			}
		elsif ($formH->{'signal'} eq 'folderrenamed')
			{
			Output("Folder renamed, doing maintenance.\n");
			# An arbitrary number of files could have new paths. This is hard to handle.
			# For now, just re-init all the paths. This puts the Linker(s) out of action for
			# a bit, but if two or more instances of this Linker are running then they will
			# be taken out of service for maintenance one at a time.
			# See also intramine_main.pl#BroadcastSignal()
			# and  intramine_main.pl#HandleMaintenanceSignal().
			print("Linker on port <$port_listen> is pausing to reload changed paths due to folder rename.\n");
			print("  On this server instance only, new read-only views will not be available,\n");
			print("  and autolinks will not be shown in CodeMirror views after scrolling.\n");
			print("  Other Linker instances running will not be affected, and Main will redirect\n");
			print("  requests for links to avoid this Linker while it's busy.\n");
			print("Reloading...\n");
			
			my $startTime = time;
			ReinitDirFinder();
			RequestBroadcast('signal=backinservice&sender=Linker&respondingto=folderrenamed');
			my $endTime = time;
			my $elapsedSecs = int($endTime - $startTime + 0.5);
			print("Linker on port $port_listen is back. Update took $elapsedSecs s.\n");
			}
		elsif ($formH->{'signal'} eq 'glossaryChanged')
			{
			my $filePath = defined($formH->{'path'}) ? $formH->{'path'} : 'BOGUS PATH';
			#print("Glossary changed seen: |$filePath|\n");
			LoadGlossary($filePath);
			}
		}

	return('OK');	# Returned value is ignored by broadcaster - this is more of a "UDP" than "TCP" approach to communicating.
	}

# Load list of all files and directories, and create a hash holding lists of all
# corresponding known full paths for partial paths, for autolinks.
# Also load all glossary entries.
sub callbackInitPathsAndGlossary {
	my $FileWatcherDir = CVal('FILEWATCHERDIRECTORY');
	my $fullFilePathListPath = $FileWatcherDir . CVal('FULL_PATH_LIST_NAME'); # .../fullpaths.out
	
	# reverse_filepaths.pm#InitDirectoryFinder()
	my $filePathCount = InitDirectoryFinder($fullFilePathListPath);

	LoadAllGlossaryFiles();
	}

sub LoadAllGlossaryFiles {
	my $glossaryFileName = lc(CVal('GLOSSARYFILENAME'));
	if ($glossaryFileName eq '')
		{
		print("WARNING, GLOSSARYFILENAME not found in data/intramine_config_4.txt. No glossaries loaded.\n");
		}
	my $paths = GetAllPathsForFileName($glossaryFileName);
	if ($paths ne '')
		{
		print("Loading glossaries...\n");
		LoadAllGlossaries($paths, $IMAGES_DIR, $COMMON_IMAGES_DIR,
			\&FullPathInContextNS, \&BestMatchingFullDirectoryPath);
		}
	else
		{
		print("No files called $glossaryFileName were found, no glossaries loaded.\n");
		}
	}
	
# Completely reload list of all files and directories. Called by HandleBroadcastRequest() above.
sub ReinitDirFinder {
	my $FileWatcherDir = CVal('FILEWATCHERDIRECTORY');
	my $fullFilePathListPath = $FileWatcherDir . CVal('FULL_PATH_LIST_NAME'); # .../fullpaths.out
	my $filePathCount = ReinitDirectoryFinder($fullFilePathListPath); # reverse_filepaths.pm#ReinitDirectoryFinder()
	}

# For all files where the view is generated by CodeMirror ("CodeMirror files").
# Get links for all local file, image, and web links in $formH->{'text'}.
# Links are added on demand for visible lines only.
# Invoked by xmlHttpRequest in cmAutoLinks.js#requestLinkMarkup().
#	request.open('get', 'http://' + mainIP + ':' + linkerPort + '/?req=cmLinks'
#			+ '&remote=' + remoteValue + '&allowEdit=' + allowEditValue + '&useApp=' + useAppValue
#			+ '&text=' + encodeURIComponent(visibleText) + '&peeraddress=' + encodeURIComponent(peeraddress)
#			+ '&path=' + encodeURIComponent(thePath) + '&first=' + firstVisibleLineNum + '&last='
#			+ lastVisibleLineNum);
# See CmGetLinksForText() just below.
sub CmLinks {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = 'nope';
	
	if (defined($formH->{'text'}) && defined($formH->{'path'})
	&&  defined($formH->{'first'}) && defined($formH->{'last'}))
		{
		my $dir = lc(DirectoryFromPathTS($formH->{'path'}));
		my $clientIsRemote = (defined($formH->{'remote'})) ? $formH->{'remote'}: '0';
		my $allowEditing = (defined($formH->{'allowEdit'})) ? $formH->{'allowEdit'}: '0';
		CmGetLinksForText($formH, $dir, $clientIsRemote, $allowEditing, \$result);
		}
		
	return($result);
	}

# For each link, respond with JSON for:
#  - line/col of start of match in text
#  - text in match to be marked up as link (determines line/col of end of match in text also)
#  - type of link: 'web', 'file', 'image'
#  - appropriate content for <a> element for linked file
sub CmGetLinksForText {
	my ($formH, $dir, $clientIsRemote, $allowEditing, $resultR) = @_;
	my $text = $formH->{'text'};
	my $firstLineNum = $formH->{'first'};
	my $lastLineNum = $formH->{'last'};
	my $json = ''; 	# JSON string for this replaces $$resultR if $numLinksFound
	my @links; 		# This array holds (object) contents of what in JS will be resp.arr[].
	my $serverAddr = ServerAddress();
	
	AddWebAndFileLinksToVisibleLinesForCodeMirror($text, $firstLineNum, $dir, \@links, $serverAddr,
										$server_port, $clientIsRemote, $allowEditing);
	
	my $numLinksFound = @links;
	if ($numLinksFound)
		{
		my %arrHash;
		$arrHash{'arr'} = \@links;
		$json = \%arrHash;
		#####$$resultR = uri_escape_utf8(encode_json($json));
		$$resultR = encode_json($json);
		}
	}

# For non-CodeMirror files.
# Add links for all local file, image, and web links in $formH->{'text'}.
# Links are added on demand for visible lines only.
# Invoked by xmlHttpRequest in autoLinks.js#requestLinkMarkup().
# As opposed to CodeMirror views, links are inserted directly in the returned text.
sub NonCmLinks {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = 'nope';
	
	if (defined($formH->{'text'}) && defined($formH->{'path'})
	&&  defined($formH->{'first'}) && defined($formH->{'last'}))
		{
		my $dir = lc(DirectoryFromPathTS($formH->{'path'}));
		my ($baseName, $ext) = FileNameProperAndExtensionFromFileName($formH->{'path'});
		$ext = lc($ext);
		my $clientIsRemote = (defined($formH->{'remote'})) ? $formH->{'remote'}: '0';
		my $allowEditing = (defined($formH->{'allowEdit'})) ? $formH->{'allowEdit'}: '0';
		my $shouldInline = (defined($formH->{'shouldInline'})) ? $formH->{'shouldInline'}: '0';
		GetLinksForText($formH, $dir, $ext, $clientIsRemote, $allowEditing, $shouldInline, \$result);
		}
	
	return($result);
	}

sub GetLinksForText {
	my ($formH, $dir, $ext, $clientIsRemote, $allowEditing, $shouldInline, $resultR) = @_;
	my $text = $formH->{'text'};
	#my $firstLineNum = $formH->{'first'};
	#my $lastLineNum = $formH->{'last'};
	my $serverAddr = ServerAddress();
	
	AddWebAndFileLinksToVisibleLines($text, $dir, $ext, $serverAddr, $server_port,
								$clientIsRemote, $allowEditing, $shouldInline, $resultR);
	}

# Called in response to the %RequestAction req=autolink&partialpath=...
# Get best full file path matching 'partialpath'. See reverse_filepaths.pm#FullPathInContextNS().
# This is actually called by the Files page, see files.js#openAutoLinkWithPort().
# Note there is no "context" folder for the provided partial path, so a directory name
# will be needed more often. Eg "main.cpp" might be adequate in a log file when linking to
# the closest instance of main.cpp, but when using the File page's Open dialog then something
# more like project51/main.cpp will be needed.
sub FullPathForPartial {
	my ($obj, $formH, $peeraddress) = @_;
	my $result = 'nope';
	
	if (defined($formH->{'partialpath'}))
		{
		my $partialPath = $formH->{'partialpath'};
		$partialPath =~ s!\\!/!g;
		my $contextDir = '';
		$result = FullPathInContextNS($partialPath, $contextDir);
		
		if ($result eq '') # Special handling for images
			{
			if ($partialPath =~ m!\.(\w\w?\w?\w?\w?\w?\w?)(\#|$)!)
				{
				my $extProper = $1;
				if (IsImageExtensionNoPeriod($extProper))
					{
					my $trimmedCurrentPath = $partialPath;
					$trimmedCurrentPath =~ s!^/!!;
					
					if (FileOrDirExistsWide($IMAGES_DIR . $trimmedCurrentPath) == 1)
						{
						$result = $IMAGES_DIR . $trimmedCurrentPath;
						}
					elsif ($COMMON_IMAGES_DIR ne '' && FileOrDirExistsWide($COMMON_IMAGES_DIR . $trimmedCurrentPath) == 1)
						{
						$result = $COMMON_IMAGES_DIR . $trimmedCurrentPath;
						}
					}
				}
			}
		}
	
	if ($result eq '')
		{
		$result = 'nope';
		}
	my $encodedResult = encode_utf8($result);
	return($encodedResult);
	}

{ ##### AutoLink
my $host;
my $port;
my $clientIsRemote;
my $allowEditing;

my $haveRefToText; 	# For CodeMirror we get the text not a ref, and this is 0.
my $line;			# Full text of a single line being autolinked
my $revLine;		# $line reversed (used to search backwards from a file extension)
my $contextDir;		# The directory path to the file wanting links
my $len;			# Length of $line.

# In non-CodeMirror files there are <mark> tags around Search highlights.
# We need a version of the line of text that's been stripped of <mark> tags
# for spotting links. $revLine can just be stripped of <mark>s since it's
# only used to spot links. Basically, we need to spot links in the stripped
# version of the line but do the replacements in the original line.
my $lineIsStripped; # 1 means <mark> tags have been removed from $strippedLine.
my $strippedLine;
my $strippedLen;


# Replacements for discovered links: For text files where replacement is done directly
# in the text, these replacements are more easily done in reverse order to avoid throwing off
# the start/end. For CodeMirror files, reps are done in the JavaScript (using $linksA).
my @repStr;			# Replacement for original text, or overlay text to put over original
my @repLen;			# Length of original text to be replaced (not length of repStr)
my @repStartPos;	# Start position of replacement in original text
my @repLinkType; 	# For CodeMirror, 'file', 'web', 'image'
my @linkIsPotentiallyTooLong; # For unquoted links to text headers, we grab 100 chars, which might be too much.

my $longestSourcePath; 	# Longest linkable path identified in original text
my $bestVerifiedPath;	# Best full path corresponding to $longestSourcePath

my $shouldInlineImages; # True = use img element, false = use showhint().

# AddWebAndFileLinksToLine: look for file and web address mentions, turn them into links.
# Does the promised "autolinking", so no quotes etc are needed around file names even if
# the file name contains spaces, and directories in the path are needed only if the file name isn't unique
# and the file being mentioned isn't the "closest" one, where distance is measured as the number
# of directory moves up and down from the referring file to the file being mentioned. So eg
# mentioning main.cpp is fine if the referring file is proj51/docs/design.txt and the file wanted
# is proj51/src/main.cpp, but if the referring file is somewhere outside the proj51 folder then
# it should be mentioned as eg proj51/main.cpp. See Gloss.txt for more about links.
# One exception, quotes are needed to link to a header within a document. Picking one of my own
# docs as an example, IntraMine Jan 2019.txt becomes a link, but to link to a header within it
# quotes are needed: eg "IntraMine Jan 2019.txt#Editor/Opener links in CodeMirror views".
# OK the quotes aren't really needed, but your resulting links will look better if you use them,
# since without the quotes an arbitrary 100 characters will be grabbed as the potential
# header string, leaving it to the receiving end to figure out which header is meant.
# Adn that leads to a very long underlined link, which looks a bit ugly.
sub AddWebAndFileLinksToLine {
	my ($txtR, $theContextDir, $theHost, $thePort, $theClientIsRemote, $shouldAllowEditing,
		$shouldInline, $currentLineNumber, $linksA) = @_;
	
	if (ref($txtR) eq 'SCALAR') # REFERENCE to a scalar, so doing text
		{
		$haveRefToText = 1;
		$line = $$txtR;
		}
	else # not a ref (at least it shouldn't be), so doing CodeMirror
		{
		$haveRefToText = 0;
		$line = $txtR;
		}
	
	# Init some of the remaining variables with AutoLink scope.
	# (For $revLine and $strippedLine see EvaluateLinkCandidates just below.)
	$contextDir = $theContextDir;	# Path of directory for file containing the text in $txtR
	$len = length($line);
	$host = $theHost;
	$port = $thePort;
	$clientIsRemote = $theClientIsRemote;
	$allowEditing = $shouldAllowEditing;
	@repStr = ();
	@repLen = ();
	@repStartPos = ();
	@repLinkType = ();
	@linkIsPotentiallyTooLong = ();

	$shouldInlineImages = $shouldInline;
	
	# Look for all of: single or double quoted text, a potential file extension, or a url.
	EvaluateLinkCandidates();
	
	my $numReps = @repStr;
	if ($numReps)
		{
		if ($haveRefToText)
			{
			DoTextReps($numReps, $txtR);
			} # text
		else # CodeMirror
			{
			DoCodeMirrorReps($numReps, $currentLineNumber, $linksA);
			} # CodeMirror
		} # $numReps
	}

# Look for all of: single or double quoted text, a potential file extension, or a url.
# Or (added later), a [text](href) with _LB_ for '[', _RP_ for ')' etc as found in POD files.
sub EvaluateLinkCandidates {
	my $previousEndPos = 0;
	my $previousRevEndPos = $len;
	my $haveGoodMatch = 0; # check-back distance is not adjusted if there is no good current match.
	my $hadGoodMatch = 0; # Don't advance $startPos if there was previous match.
	
	# Collect positions of quotes and HTML tags (start and end of both start and end tags).
	# And <mark> tags, which can interfere with links.
	GetTagAndQuotePositions($line);
	$lineIsStripped = LineHasMarkTags(); # Stripping <mark> tags happens next.

	# If $line has <mark> tags, create a version stripped of those, for spotting links
	# without having to use a monstrous regex.
	if ($lineIsStripped)
		{
		$strippedLine = $line;
		$strippedLine =~ s!(</?mark[^>]*>)!!g;
		$strippedLen = length($strippedLine);
		$revLine = scalar reverse($strippedLine);
		}
	else
		{
		$strippedLine = $line;
		$strippedLen = $len;
		$revLine = scalar reverse($line);
		}
	
	# while see quotes or a potential file .extension, or http(s)://
	# or [text](href) with _LB_ for '[', _RP_ for ')' etc. Those are from POD files only.
	while ($strippedLine =~ m!((_LB_.+?_RB__LP_.+?_RP_)|(\"([^"]+)\.\w+([#:][^"]+)?\")|(\'([^']+)\.\w+([#:][^']+)?\')|(\"[^"]+\")|(\'[^']+\')|\.(\w\w?\w?\w?\w?\w?\w?)([#:][A-Za-z0-9_:~]+)?|((https?://([^\s)<\"](?\!ttp:))+)))!g)
		{
		my $startPos = $-[0];	# this does include the '.', beginning of entire match
		my $endPos = $+[0];		# pos of char after end of entire match
		my $captured = $1;		# double-quoted chunk, or extension (plus any anchor), or url or [text](href)
		my $haveTextHref = (index($captured, '_LB_') == 0);
		my $textHref = ($haveTextHref) ? $captured : '';
		my $haveDirSpecifier = 0;
		
		# $9, $10: (\"[^"]+\")|(\'[^']+\')
		# These are checked for after other quote patterns, and if triggered
		# we're dealing with a potential directory specifier.
		if (defined($9) || defined($10))
			{
			$haveDirSpecifier = 1;
			}

		
		my $haveQuotation = ((index($captured, '"') == 0) || (index($captured, "'") == 0));
		my $badQuotation = 0;
		my $insideID = 0;
		my $quoteChar = '';
		my $hasPeriod = (index($captured, '.') >= 0);

		if ($haveQuotation || $haveDirSpecifier)
			{
			# Check for non-word or BOL before first quote, non-word or EOL after second.
			if ($startPos > 0)
				{
				my $charBefore = substr($strippedLine, $startPos - 1, 1);
				# Reject if char before first quote is a word char or '='
				# (as in class="...", as found in syntax highlighting etc).
				# For '=', don't mark as bad if $captured contains a '.'
				# (hinting that there might be a file extension in there).
				if ($charBefore !~ m!\W|! || ($charBefore eq '=' && !$hasPeriod))
					{
					$badQuotation = 1;
					}
				else
					{
					# Check we aren't inside a generated header id such as
					# <h3 id="gloss2html.pl#AddWebAndFileLinksToLine()_refactor"...
					if ($haveRefToText)
						{
						if ($startPos >= 7)
							{
							if (substr($strippedLine, $startPos - 3, 3) eq "id=")
								{
								$badQuotation = 1;
								$insideID = 1;
								}
							}
						elsif ($startPos >= 5) # Perl line numbers, <td n="1">
							{
							if (substr($strippedLine, $startPos - 2, 2) eq "n=")
								{
								$badQuotation = 1;
								$insideID = 1;
								}
							}
						}
					}
				}
			if ($endPos < $strippedLen)
				{
				my $charAfter = substr($strippedLine, $endPos, 1);
				# Reject if char after is a word char or '>'
				# (as in class="quoted">).
				if ($charAfter !~ m!\W! || ($charAfter eq '>' && !$hasPeriod))
					{
					$badQuotation = 1;
					}
				}

			# Skip quotes that are inside HTML tags.
			# Is quote at $startPos at a bad position? Skip.
			# Is quote at $endPos at a bad position? Reset to next good position, or skip.
			if (!$hasPeriod)
				{
				if (IsBadQuotePosition($startPos))
					{
					$badQuotation = 1;
					}
				elsif (IsBadQuotePosition($endPos-1))
					{
					my $nextGoodQuotePos = NextGoodQuotePosition($endPos-1);
					if ($nextGoodQuotePos >= 0)
						{
						$endPos = $nextGoodQuotePos + 1;
						}
					else
						{
						$badQuotation = 1;
						}
					}
				}
			
			if (!$badQuotation && !$haveDirSpecifier)
				{
				# Trim quotes and pick up $quoteChar.
				$quoteChar =  substr($captured, 0, 1);
				$captured = substr($captured, 1);
				$captured = substr($captured, 0, length($captured) - 1);
				}
			}
		
		if ($badQuotation)
			{
			if ($insideID)
				{
				pos($strippedLine) = $endPos;
				}
			else
				{
				pos($strippedLine) = $startPos + 1;
				}
			}
		else
			{
			my $haveURL = (!$haveTextHref && index($captured, 'http') == 0);
			my $anchorWithNum = (!$haveQuotation && !$haveURL && !$haveTextHref && defined($12)) ? $12 : ''; # includes '#'
			# Need to sort out actual anchor if we're dealing with a quoted chunk.
			if ($haveQuotation && !$haveURL && !$haveTextHref)
				{
				my $hashPos = index($captured, '#');
				if ($hashPos < 0)
					{
					$hashPos = index($captured, ':');
					}

				if ($hashPos >= 0)
					{
					my $quotePos = index($captured, '"', $hashPos);
					if ($quotePos != $hashPos + 1)
						{
						$anchorWithNum = substr($captured, $hashPos); # includes '#'
						}
					}

				#if ($captured =~ m!(\#[^"]+)!)
				#	{
				#	$anchorWithNum = $1; # includes '#'
				#	}
				}
			my $url = $haveURL ? $captured : '';
			my $extProper = (!$haveQuotation && !$haveURL && !$haveTextHref && !$haveDirSpecifier) ? substr($captured, 1) : '';
			# Get file extension if it's a quoted chunk (many won't have an extension).
			if ($haveQuotation && !$haveURL && !$haveTextHref)
				{
				my $foundExtension = ExtensionBeforeHashOrEnd($captured);
				if ($foundExtension ne '')
				#if ($captured =~ m!\.(\w\w?\w?\w?\w?\w?\w?)(\#|$)!)
					{
					$extProper = $foundExtension;
					#$extProper = $1;
					}
				}
			if ($anchorWithNum ne '' && !$haveURL && !$haveQuotation && !$haveTextHref)
				{
				my $pos = index($extProper, '#');
				if ($pos < 0)
					{
					$pos = index($extProper, ':');
					}
				$extProper = substr($extProper, 0, $pos);
				}
			
			# "$haveTextExtension" includes docx|pdf
			my $haveTextExtension = (!$haveURL && !$haveTextHref && IsTextDocxPdfExtensionNoPeriod($extProper));
			my $haveImageExtension = $haveTextExtension ? 0 : (!$haveURL && !$haveTextHref && IsImageExtensionNoPeriod($extProper));
			my $haveVideoExtension = (!$haveURL && !$haveTextHref && IsVideoExtensionNoPeriod($extProper));
			my $haveGoodExtension = ($haveTextExtension || $haveImageExtension || $haveVideoExtension); # else URL or [text](href)
			
			my $linkIsMaybeTooLong = 0;
			
			# Potentially a text file mention or an image.
			if ($haveGoodExtension)
				{
				# Skip video link if client is remote, no way yet to handle that.
				if (!($haveVideoExtension && $clientIsRemote))
					{
					# At the last minute, suppress #anchorWithNum if it has a leading
					# space or tab.
					if (index($anchorWithNum, ' ') == 1 || index($anchorWithNum, "\t") == 1)
						{
						$anchorWithNum = '';
						}
					$haveGoodMatch = RememberTextOrImageOrVideoFileMention($startPos,
							$previousRevEndPos, $captured, $extProper,
							$haveQuotation, $haveTextExtension, $haveImageExtension,
							$haveVideoExtension, $quoteChar, $anchorWithNum);
					}
				} # if known extensions
			elsif ($haveURL)
				{
				# Skip first char if quoted.
				if ($haveQuotation)
					{
					++$startPos;
					}
				RememberUrl($startPos, $haveQuotation, $quoteChar, $url);
				$haveGoodMatch = 1;
				}
			elsif ($haveTextHref)
				{
				RememberTextHref($startPos, $textHref);
				$haveGoodMatch = 1;
				}
			elsif ($haveDirSpecifier)
				{
				$haveGoodMatch = RememberDirMention($startPos, $captured);
				}
			
			if ($haveGoodMatch)
				{
				$previousEndPos = $endPos;
				$previousRevEndPos = $strippedLen - $previousEndPos - 1; # Limit backwards extent of 2nd and subsequent searches.
				$haveGoodMatch = 0;
				}
			elsif (!$haveGoodMatch && $haveQuotation)
				{
				pos($strippedLine) = $startPos + 1;
				}
			}
		} # while another extension or url matched
	}

# Good extension if period followed by up to 7 word chars
# and then end of string or a  '#'. I tried to replace this
# with a loop and substr(), but it got too complicated.
# 	if ($captured =~ m!\.(\w\w?\w?\w?\w?\w?\w?)(\#|$)!)
# 		$extProper = $1;
sub ExtensionBeforeHashOrEnd {
	my ($captured) = @_;
	my $result = '';
	
	if ($captured =~ m!\.(\w\w?\w?\w?\w?\w?\w?)([#:]|$)!)
		{
		$result = $1;
		}
	return($result);
	}

# If we can find a valid file mention looking backwards from $startPos, remember its details
# in @repStr, @repLen etc. We go for the longest valid path.
# We're searching backwards for the file name and directories when an extension has
# been spotted.
sub RememberTextOrImageOrVideoFileMention {
	my ($startPos, $previousRevEndPos, $captured, $extProper, $haveQuotation,
		$haveTextExtension, $haveImageExtension, $haveVideoExtension, $quoteChar, $anchorWithNum) = @_;
	my $linkIsMaybeTooLong = 0;
	
	# To allow for spaces in #anchors where file#anchor hasn't been quoted, grab the
	# 100 chars following '#' here, and sort it out on the other end when going to
	# the anchor. Only for txt files. This looks ugly in the view, alas.
	if ($extProper eq 'txt' && !$haveQuotation && $anchorWithNum ne '')
		{
		my $anchorPosOnLine = $startPos;
		$anchorPosOnLine = index($strippedLine, '#', $startPos);
		if ($anchorPosOnLine < 0)
			{
			$anchorPosOnLine = index($strippedLine, ':', $startPos);
			}
		$anchorWithNum = substr($strippedLine, $anchorPosOnLine, 100);
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
		my $pathToCheck = $captured;
		my $pos = index($pathToCheck, '#');
		if ($pos < 0)
			{
			$pos = index($pathToCheck, ':');
			}
		if ($pos > 0)
			{
			$pathToCheck = substr($pathToCheck, 0, $pos);
			}
		
		my $verifiedPath = FullPathInContextNS($pathToCheck, $contextDir); # reverse_filepaths.pm		
		if ($verifiedPath ne '')
			{
			$longestSourcePath = $pathToCheck;
			$bestVerifiedPath = $verifiedPath;
			$doingQuotedPath = 1;
			}
		}
	
	my $revPos = $strippedLen - $startPos - 1 + 1; # extra +1 there to skip '.' before the extension proper.
	
	# Extract the substr to search.
	my $revStrToSearch = substr($revLine, $revPos, $previousRevEndPos - $revPos + 1);
	
	# Good break points for hunt are [\\/ ], and [*?"<>|\t] end the hunt.
	# For image files only, we look in a couple of standard places for just the file name.
	# This can sometimes be expensive, but we look at the standard locations only until
	# either a slash is seen or a regular mention is found.
	my $checkStdImageDirs = ($haveImageExtension || $haveVideoExtension) ? 1 : 0;
	my $commonDirForImageName = ''; # Set if image found one of the std image dirs
	my $imageName = ''; 			# for use if image found in one of std image dirs
	
	GetLongestGoodPath($doingQuotedPath, $checkStdImageDirs, $revStrToSearch, $fileTail,
					\$imageName, \$commonDirForImageName);
	
	my $haveGoodMatch = 0;
	if ($longestSourcePath ne '' || $commonDirForImageName ne '')
		{
		my $linkType = 'file'; # For CodeMirror
		my $usingCommonImageLocation = 0;
		if ($longestSourcePath eq '')
			{
			$longestSourcePath = $imageName;
			$usingCommonImageLocation = 1;
			}
		my $repString = '';

		my $repLength = length($longestSourcePath) + $anchorLength;
		if ($haveQuotation)
			{
			$repLength += 2; # for the quotes
			}
		
		my $repStartPosition = ($haveQuotation) ? $startPos : $startPos - $repLength + $periodPlusAfterLength;

		# We are using the "stripped" line here, so recover the start position and length of text
		# to be replaced by adding back the <mark> tags, for use at the displayed link text.
		($repStartPosition, $repLength) = CorrectedPositionAndLength($repStartPosition, $repLength);
		my $displayTextForAnchor = substr($line, $repStartPosition, $repLength);
		
		if ($haveTextExtension)
			{
			GetTextFileRep($haveQuotation, $quoteChar, $extProper, $longestSourcePath,
							$anchorWithNum, $displayTextForAnchor, \$repString);
			}
		else # image or video extension
			{
			# For CodeMirror
			if ($haveVideoExtension)
				{
				$linkType = 'video'; 
				}
			else
				{
				$linkType = 'image'; 
				}
			GetImageFileRep($haveQuotation, $quoteChar, $usingCommonImageLocation,
							$imageName, $displayTextForAnchor, $haveVideoExtension, \$repString);
			}
			
		push @repStr, $repString;
		push @repLen, $repLength;
		push @repStartPos, $repStartPosition;
		push @linkIsPotentiallyTooLong, $linkIsMaybeTooLong;
		if (!$haveRefToText)
			{
			push @repLinkType, $linkType;
			}
		$haveGoodMatch = 1;
		}
	
	return($haveGoodMatch);
	}

# If $captured text in quotes can be associated with a full directory path
# by reverse_filepaths.pm#BestMatchingFullDirectoryPath(),
# push a link for it into @repStr etc.
sub RememberDirMention {
	my ($startPos, $captured) = @_;
	my $repLength = length($captured);

	# Adjust position and length of URL as displayed to include any <mark> tags that were stripped.
	($startPos, $repLength) = CorrectedPositionAndLength($startPos, $repLength);

	# Re-get $captured directory for display (including any <mark> elements).
	my $displayedDir = substr($line, $startPos, $repLength); # was = $url;
	$repLength = length($displayedDir);
	my $haveGoodMatch = 0;
	
	my $trimmedDirPath = $captured;
	# Trim quotes
	$trimmedDirPath = substr($trimmedDirPath, 1);
	$trimmedDirPath = substr($trimmedDirPath, 0, -1);
	# Change \ to /.
	$trimmedDirPath =~ s!\\!/!g;
	# Remove any starting or trailing slashes.
	$trimmedDirPath =~ s!^/!!;
	$trimmedDirPath =~ s!/$!!;
	# Lower case
	$trimmedDirPath = lc($trimmedDirPath);
	
	my $directoryPath = BestMatchingFullDirectoryPath($trimmedDirPath, $contextDir);
	
	if ($directoryPath ne '')
		{
		my $linkType = 'directory'; # For CodeMirror
		my $repString = "<a href=\"$directoryPath\" onclick=\"openDirectory(this.href); return false;\">$displayedDir</a>";
		
		push @repStr, $repString;
		push @repLen, $repLength;
		push @repStartPos, $startPos;
		push @linkIsPotentiallyTooLong, 0;
		if (!$haveRefToText)
			{
			push @repLinkType, $linkType;
			}
		$haveGoodMatch = 1;
		}
	
	return($haveGoodMatch);
	}

# Keep looking backwards a word at a time, calling FullPathInContextNS() and noting
# $bestVerifiedPath and $longestSourcePath until beginning of line or double quote is seen.
# The longest good path if any is left in $longestSourcePath.
sub GetLongestGoodPath {
	my ($doingQuotedPath, $checkStdImageDirs, $revStrToSearch, $currentPath,
		$imageNameR, $commonDirForImageNameR) = @_;
	my $trimmedCurrentPath = $currentPath;
	my $slashSeen = 0; 				# stop checking standard locs for image if a dir slash is seen
	my $checkToEndOfLine = 0;
	my $currentRevPos = ($doingQuotedPath) ? -1: 0;
	my $prevSubRevPos = 0;
	my $revStrLength = length($revStrToSearch);
	
	if (!$revStrLength)
		{
		#print("EARLY RETURN, \$revStrToSearch is empty.\n");
		return;
		}
	
	# Look for next space or slash or end in the reversed str. We don't go into this loop
	# if balanced quotes around path have been found just above.
	while ($currentRevPos >= 0 || $checkToEndOfLine)
		{
		if ($checkToEndOfLine)
			{
			$currentRevPos = $strippedLen;
			}
		else
			{
			if ($revStrToSearch =~ m!^.{$prevSubRevPos}.*?([ \t/\\,\(<>:|?])!s)
				{
				$currentRevPos = $-[1];
					
				if ($currentRevPos >= 0)
					{
					my $charSeen = $1;
					# Check for a second slash in $revStrToSearch, signalling a
					# \\host\share... or //host/share... location.
					if ($charSeen eq "/" || $charSeen eq "\\")
						{
						$slashSeen = 1;
						if ($currentRevPos < $strippedLen - 1
							&& substr($revStrToSearch, $currentRevPos + 1, 1) eq $charSeen)
							{
							++$currentRevPos;
							}
						}
					# Pick up drive letter (if any) when see a ':' before line start.
					elsif ($charSeen eq ":")
						{
						if ($currentRevPos < $strippedLen - 1)
							{
							++$currentRevPos;
							}
						}
					}
				}
			else
				{
				$currentRevPos = -1;
				}
			}
		
		if ($currentRevPos >= 0) 
			{
			my $numChars = $currentRevPos - $prevSubRevPos + 1;
			#print("|$revStrLength| |$currentRevPos| |$prevSubRevPos| |$numChars|\n");
			if ($prevSubRevPos + $numChars > $revStrLength - 1)
				{
				$numChars = $revStrLength - $prevSubRevPos;
				# Drop out after this check.
				$currentRevPos = -1;
				}

			# Drop out if there are no more chars to check.
			if ($numChars <= 0)
				{
				last;
				}
			# Pick up next reversed term, including space etc if any.
			my $nextRevTerm = substr($revStrToSearch, $prevSubRevPos, $numChars);
			
			# Drop out if we see a double quote.
			if (index($nextRevTerm, '"') >= 0)
				{
				last;
				}
			
			# Reversing puts the matched space etc if any at beginning of $nextTerm.
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

			my $verifiedPath = '';
			# I know this is a bit awkward, but we want to skip illegal file name characters
			# and it's best to avoid a nested regex.
			if (index($trimmedCurrentPath, '<') < 0
				&& index($trimmedCurrentPath, '>') < 0 && index($trimmedCurrentPath, '|') < 0
				&& index($trimmedCurrentPath, '?') < 0)
				{
				# See reverse_filepaths.pm#FullPathInContextNS().
				$verifiedPath = FullPathInContextNS($trimmedCurrentPath, $contextDir);
				}

			if ($verifiedPath ne '')
				{
				$longestSourcePath = $trimmedCurrentPath; 	# This is in the original text
				$bestVerifiedPath = $verifiedPath;			# This is the corresponding full path
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

# Make viewer and editor links for $bestVerifiedPath, put them in $$repStringR.
sub GetTextFileRep {
	my ($haveQuotation, $quoteChar, $extProper, $longestSourcePath,
		$anchorWithNum, $displayTextForAnchor, $repStringR) = @_;
	
	my $editLink = '';
	my $viewerPath = $bestVerifiedPath;
	my $editorPath = $bestVerifiedPath;
	$viewerPath =~ s!\\!/!g;
	if ($haveRefToText)
		{
		$viewerPath =~ s!%!%25!g;
		$viewerPath =~ s!\+!\%2B!g;
		}
	
	$editorPath =~ s!\\!/!g;
	$editorPath =~ s!%!%25!g;
	$editorPath =~ s!\+!\%2B!g;
	
	my $displayedLinkName = $displayTextForAnchor;
	
	if ($allowEditing)
		{
		if (!$clientIsRemote || $extProper !~ m!docx|pdf!i)
			{
			$editLink = "<a href='$editorPath' class='canedit' onclick=\"editOpen(this.href); return false;\">"
					. "<img class='edit_img' src='edit1.png' width='17' height='12'>" . '</a>';
			}
		}
	
	# Change leading ':' to '#' in $anchorWithNum.
	if (index($anchorWithNum, ':') == 0)
		{
		$anchorWithNum = '#' . substr($anchorWithNum, 1);
		}
	# For C++, shorten constructor/destructor anchors.
	if ($extProper eq 'cpp' || $extProper eq 'cxx' ||
		$extProper eq 'hpp' || $extProper eq 'h' ||
		$extProper eq 'hh' || $extProper eq 'hxx')
		{
		$anchorWithNum = ShortenedClassAnchor($anchorWithNum);
		}
	
	my $viewerLink = "<a href=\"http://$host:$port/$VIEWERNAME/?href=$viewerPath$anchorWithNum\" onclick=\"openView(this.href, $VIEWERNAME); return false;\"  target=\"_blank\">$displayedLinkName</a>";
	$$repStringR = "$viewerLink$editLink";
	}

# "C" being a class name, remove "C::" from #C::C or #C::C() or #C::~C or #C::C().
# Leave other anchors alone.
sub ShortenedClassAnchor {
	my ($anchorWithNum) = @_;
	my $firstColonPos = index($anchorWithNum, ':');
	
	if ($firstColonPos > 0)
		{
		my $secondColonPos = index($anchorWithNum, ':', $firstColonPos + 1);
		if ($secondColonPos == $firstColonPos + 1)
			{
			my $firstWord = substr($anchorWithNum, 1, $firstColonPos - 1);
			my $secondWord = substr($anchorWithNum, $secondColonPos + 1);
			my $parensPos = index($secondWord, '(');
			if ($parensPos > 0)
				{
				$secondWord = substr($secondWord, 0, length($secondWord) - 2);
				}
			my $secondWordToTest = $secondWord;
			if (index($secondWordToTest, '~') == 0)
				{
				$secondWordToTest = substr($secondWordToTest, 1);
				}
			
			if ($firstWord eq $secondWordToTest)
				{
				$anchorWithNum = '#' . $secondWord;
				}
			}
		}
		
	return($anchorWithNum);
	}

# Do up a view/hover link for image in $bestVerifiedPath, put that in $$repStringR.
sub GetImageFileRep {
	my ($haveQuotation, $quoteChar, $usingCommonImageLocation, $imageName, $displayTextForAnchor, $haveVideoExtension, $repStringR) = @_;
	my $serviceName = ($haveVideoExtension) ? $VIDEONAME : $VIEWERNAME;
	if ($haveRefToText)
		{
		$bestVerifiedPath =~ s!%!%25!g;
		$bestVerifiedPath =~ s!\+!\%2B!g;
		}
	else
		{
		$bestVerifiedPath =~ s!\\!/!g;
		}
	
	my $fullPath = $bestVerifiedPath;
	my $imagePath = "http://$host:$port/$serviceName/$fullPath";
	my $originalPath = $usingCommonImageLocation ? $imageName : $longestSourcePath;

	my $displayedLinkName = $displayTextForAnchor;
	
	my $leftHoverImg = "<img src='http://$host:$port/hoverleft.png' width='17' height='12'>"; # actual width='32' height='23'>";
	my $rightHoverImg = "<img src='http://$host:$port/hoverright.png' width='17' height='12'>";

	if ($haveRefToText) # "text", not CM
		{
		if ($shouldInlineImages && !$haveVideoExtension)
			{
			my $imgPath = "http://$host:$port/$fullPath";
			$$repStringR = "<img src='$imgPath'>";
			}
		else
			{
			if ($haveVideoExtension)
				{
				if (!$clientIsRemote)
					{
					$$repStringR = "<a href=\"http://$host:$port/$serviceName/?href=$fullPath\" onclick=\"openView(this.href, '$serviceName'); return false;\"  target=\"_blank\">$displayedLinkName</a>";
					}
				}
			else
				{
				$$repStringR = "<a href=\"http://$host:$port/$serviceName/?href=$fullPath\" onclick=\"openView(this.href, '$serviceName'); return false;\"  target=\"_blank\" onmouseover=\"showhint('<img src=&quot;$imagePath&quot;>', this, event, '500px', true);\">$leftHoverImg$displayedLinkName$rightHoverImg</a>";
				}
			}
		}
	else # CodeMirror
		{
		$imagePath =~ s!%!%25!g;
		my $imageOpenHref = "http://$host:$port/$serviceName/?href=$fullPath";
		if ($haveVideoExtension)
			{
			if (!$clientIsRemote)
				{
				$$repStringR = "<a href=\"$imageOpenHref\" target='_blank'>$displayedLinkName</a>";
				}
			}
		else
			{
			$$repStringR = "<a href=\"$imageOpenHref\" target='_blank' onmouseover=\"showhint('<img src=&quot;$imagePath&quot;>', this, event, '500px', true);\">$leftHoverImg$displayedLinkName$rightHoverImg</a>";
			}
		}

	}

# Push url details onto @repStr, @repLen etc.
# One exception, if $url is too short to be real then skip it.
sub RememberUrl {
	my ($startPos, $haveQuotation, $quoteChar, $url) = @_;

	my $linkIsMaybeTooLong = 0;
	my $repLength = length($url);

	# Adjust position and length of URL to include any <mark> tags that were stripped.
	($startPos, $repLength) = CorrectedPositionAndLength($startPos, $repLength);

	# Re-get $url for display (including any <mark> elements).
	my $displayedURL = substr($line, $startPos, $repLength); # was = $url;
	$repLength = length($displayedURL);

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
		
	# Skip this one if it's too short to be a real url. http://a.b is the shortest I think, len 10.
	if (length($url) < 10)
		{
		return;
		}
	
	if ($haveQuotation)
		{
		$displayedURL = $quoteChar . $displayedURL . $quoteChar;
		$repLength += 2;
		--$startPos;
		}

	my $repString = "<a href='$url' target='_blank'>$displayedURL</a>";
	
	push @repStr, $repString;
	push @repLen, $repLength;
	push @repStartPos, $startPos;
	push @linkIsPotentiallyTooLong, $linkIsMaybeTooLong;
	if (!$haveRefToText) # CodeMirror
		{
		push @repLinkType, 'web';
		}
	}

# For [text](href) links, present in POD text only.
# We want the href from the (stripped) $textHref as passed in,
# and the display text from the corrected version of $textHref.
# Text comes in here as _LB_ text proper _RB_,
# href as _LP_ href proper _RP_.
sub RememberTextHref {
	my ($startPos, $textHref) = @_;
	my $repLength = length($textHref);

	# First extract a good href.
	my $leftIdx = index($textHref, '_LP_');
	$leftIdx += length('_LP_');
	my $rightIdx = index($textHref, '_RP_');
	my $href = substr($textHref, $leftIdx, $rightIdx - $leftIdx);

	# "$href" can in fact be an href or an id, and starts with "href="
	# or "id=", which needs removing.
	my $attrName = 'href';
	if (index($href, 'href=') == 0)
		{
		$href = substr($href, 5);
		}
	elsif (index($href, 'id=') == 0)
		{
		$href = substr($href, 3);
		$attrName = 'id';
		}
	# else treat as an href, without the leading 'href=';

	# Adjust position and length of URL to include any <mark> tags that were stripped.
	($startPos, $repLength) = CorrectedPositionAndLength($startPos, $repLength);

	# Get display text from the corrected version of $textHref.
	my $correctTextHref = substr($line, $startPos, $repLength);
	$leftIdx = index($correctTextHref, '_LB_');
	$leftIdx += length('_LB_');
	$rightIdx = index($correctTextHref, '_RB_');
	my $displayedText = substr($correctTextHref, $leftIdx, $rightIdx - $leftIdx);

	# Leave out target='_blank' if it's an internal link (href starts with '#')
	# or an id.
	my $isInternal = (index($href, '#') == 0 || $attrName eq 'id');

	my $repString = ($isInternal) ? "<a $attrName='$href'>$displayedText</a>"
					: "<a $attrName='$href' target='_blank'>$displayedText</a>";

	push @repStr, $repString;
	push @repLen, $repLength;
	push @repStartPos, $startPos;
	push @linkIsPotentiallyTooLong, 0;
	if (!$haveRefToText) # CodeMirror (not needed at present, CM doesn't see this sort of thing)
		{
		push @repLinkType, 'web';
		}
	}

# Non-CodeMirror, replacements of file/url mentions with links are done straight in the text.
# Do all reps in reverse order for text, so as to not throw off positions.
sub DoTextReps {
	my ($numReps, $txtR) = @_;
	
	for (my $i = $numReps - 1; $i >= 0; --$i)
		{
		if ($i > 0 && $linkIsPotentiallyTooLong[$i-1])
			{
			# Avoid overlap of replacements.
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
			if (RepIsInsideAnchorOrImage($repStartPos[$i], $repLen[$i]))
				{
				$repLen[$i] = 0;
				}
			}
		}
		
	# Second pass, just do the replacements.
	for (my $i = $numReps - 1; $i >= 0; --$i)
		{
		if ($repLen[$i] > 0)
			{
			# substr($line, $pos, $srcLen, $repString);
			substr($line, $repStartPos[$i], $repLen[$i], $repStr[$i]);
			}
		}
	
	$$txtR = $line;
	}

# Links for CodeMirror files are done in JavaScript. Here we supply details such as
# line/column of start of link, the text to mark up, and the actual link. The links are
# overlaid on the text rather than replacing the text.
# See CmLinks() above.
sub DoCodeMirrorReps {
	my ($numReps, $currentLineNumber, $linksA) = @_;

	for (my $i = 0; $i < $numReps; ++$i)
		{
		# Avoid overlap of replacements.
		if ($i < $numReps - 1 && $linkIsPotentiallyTooLong[$i])
			{
			if ($repStartPos[$i] + $repLen[$i] >= $repStartPos[$i+1])
				{
				my $amtToLeave = $repStartPos[$i+1] - $repStartPos[$i] - 1;
				$repLen[$i] = $amtToLeave;
				if ($repLen[$i] > 0)
					{
					# Need to shorten text inside $repStr, <a...>this text</a>
					if ($repStr[$i] =~ m!^(\<a([^>]+)\>)(.+)$!)
						{
						my $anchorStart = $1;
						my $remainder = $3;
						my $anchorEndPos = rindex($remainder, "</a>");
						if ($anchorEndPos > 0)
							{
							my $anchortext = substr($remainder, 0, $anchorEndPos);
							$remainder =~ s!\<span class\=\"noshow\"\>\<\/span\>!!g;
							$remainder = substr($remainder, 0, $amtToLeave);
							# Put $repStr[$i] back together.
							$repStr[$i] = $anchorStart . $remainder . "</a>";
							}
						}
					}
				}
			}
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
	
# If there is '<a' but not '</a>' before, in that order, then we are in an anchor.
# If there is '<img' before but not also '>' before, in that order, then we are in an img.
sub RepIsInsideAnchorOrImage {
	my ($startPos, $len) = @_;
	my $endPos = $startPos + $len - 1;
	my $result = (PositionIsInsideAnchorOrImage($startPos) || PositionIsInsideAnchorOrImage($endPos));
	return($result);
	}
	
sub PositionIsInsideAnchorOrImage {
	my ($startPos) = @_;
	my $result = 0;
	
	# Anchor check:
	my $hitPos = 0;
	my $anchorOpenPos = -1;
	while (($hitPos = index($line, '<a', $hitPos)) >= 0)
		{
		if ($hitPos <= $startPos)
			{
			$anchorOpenPos = $hitPos;
			++$hitPos;
			}
		else
			{
			last;
			}
		}
	
	if ($anchorOpenPos >= 0)
		{
		$hitPos = $anchorOpenPos;
		my $anchorClosePos = -1;
		if (($hitPos = index($line, '</a>', $hitPos)) >= 0)
			{
			if ($hitPos <= $startPos)
				{
				$anchorClosePos = $hitPos;
				}
			}
			
		if ($anchorClosePos < 0 || $anchorClosePos < $anchorOpenPos)
			{
			$result = 1;
			}
		}
	
	if (!$result)
		{
		$hitPos = 0;
		my $imageOpenPos = -1;
		while (($hitPos = index($line, '<img', $hitPos)) >= 0)
			{
			if ($hitPos <= $startPos)
				{
				$imageOpenPos = $hitPos;
				++$hitPos;
				}
			else
				{
				last;
				}
			}
			
		if ($imageOpenPos >= 0)
			{
			$hitPos = $imageOpenPos;
			my $imageClosePos = -1;
			if (($hitPos = index($line, '>', $hitPos)) >= 0)
				{
				if ($hitPos <= $startPos)
					{
					$imageClosePos = $hitPos;
					}
				}
				
			if ($imageClosePos < 0 || $imageClosePos < $imageOpenPos)
				{
				$result = 1;
				}
			}
		}
		
	return($result);
	}
} ##### AutoLink

{ ##### HTML tag, quote, and <mark> positions.
my @htmlTagStartPos;
my @htmlTagEndPos;
my $numHtmlTags;
my @quotePos;
my $numQuotes;
my %badQuotePosition;

my @markStartPos;
my @markLength;
my @isMarkStart; # <mark...> gets 1, </mark> gets 0.

sub GetTagAndQuotePositions {
	my ($line) = @_;
	
	@htmlTagStartPos = ();
	@htmlTagEndPos = ();
	@quotePos = ();
	%badQuotePosition = ();

	GetHtmlStartsAndEnds($line);
	$numHtmlTags = @htmlTagStartPos;

	GetQuotePositions($line);
	$numQuotes = @quotePos;

	# Identify "bad" quote positions, the ones inside HTML tags.
	GetBadQuotePositions();

	# Find starts and length of <mark...> and </mark>.
	GetMarkStartsAndLengths($line);
	}
	
# Find start and end positions of HTML start/end tags on line.
sub GetHtmlStartsAndEnds {
	my ($line) = @_;
	
	while ($line =~ m!(<.+?>)!g)
		{
		my $startPos = $-[1];		# beginning of match
		my $endPos = $+[1] - 1;		# one past last matching character without the -1
		push @htmlTagStartPos, $startPos;
		push @htmlTagEndPos, $endPos;
		}
	}

sub GetQuotePositions {
	my ($line) = @_;
	
	while ($line =~ m!(")!g)
		{
		my $startPos = $-[1];	# beginning of match
		push @quotePos, $startPos;
		}
	}

# Identify "bad" quote positions, the ones inside HTML tags.
sub GetBadQuotePositions {
	
	for (my $i = 0; $i < $numQuotes; ++$i)
		{
		my $isBadPos = 0;
		my $quotePos = $quotePos[$i];
		for (my $j = 0; $j < $numHtmlTags; ++$j)
			{
			if ($quotePos >= $htmlTagStartPos[$j] && $quotePos <= $htmlTagEndPos[$j])
				{
				$isBadPos = 1;
				last;
				}
			}
		
		if ($isBadPos)
			{
			$badQuotePosition{$quotePos} = 1;
			}
		}
	}

sub NextGoodQuotePosition {
	my ($badPos) = @_;
	my $nextGoodPos = -1;
	
	for (my $i = 0; $i < $numQuotes; ++$i)
		{
		if ($badPos < $quotePos[$i] && !defined($badQuotePosition{$quotePos[$i]}))
			{
			$nextGoodPos = $quotePos[$i];
			last;
			}
		}
	return($nextGoodPos);
	}

sub IsBadQuotePosition {
	my ($pos) = @_;
	my $result = defined($badQuotePosition{$pos}) ? 1 : 0;
	return($result);
	}

sub InsideHtmlTag {
	my ($pos) = @_;
	my $result = 0;

	for (my $j = 0; $j < $numHtmlTags; ++$j)
		{
		if ($pos >= $htmlTagStartPos[$j] && $pos <= $htmlTagEndPos[$j])
			{
			$result = 1;
			last;
			}
		}
	
	return($result);
	}

# Find starts and length of <mark...> and </mark>,
# and whether it's a start or end tag.
sub GetMarkStartsAndLengths {
	my ($line) = @_;

	@markStartPos = ();
	@markLength = ();
	@isMarkStart = ();
	
	while ($line =~ m!(</?mark[^>]*>)!g)
		{
		my $startPos = $-[1];	# beginning of match
		my $endPos = $+[1];		# one past last matching character
		push @markStartPos, $startPos;
		push @markLength, $endPos - $startPos;
		my $markStr = $1;
		my $isMarkStarter = 1;
		if (index($markStr, '</') == 0)
			{
			$isMarkStarter = 0;
			}
		push @isMarkStart, $isMarkStarter;
		}
	}

# Correct for missing <mark...> and </mark>
# as found in @markStartPos /@ markLength.
sub CorrectedPositionAndLength {
	my ($startPos, $repLength) = @_;
	my $correctedStartPos = $startPos;
	my $originalEndPos = $startPos + $repLength;

	# Correct the start position by adding back lengths of
	# preceding marks.
	# And add back lengths of removed <mark> tags that were originally
	# in the stripped text.
	# We have to correct the position of each mark by removing
	# length of all preceding marks before comparing with the
	# (already stripped) $startPos and $originalEndPos.
	for (my $i = 0; $i < @markStartPos; ++$i)
		{
		my $deflatedPosition = $markStartPos[$i];
		if ($i > 0)
			{
			my $pi = $i - 1;
			while ($pi >= 0 )
				{
				$deflatedPosition -= $markLength[$pi];
				--$pi;
				}
			}

		if ($deflatedPosition < $startPos)
			{
			$correctedStartPos += $markLength[$i];
			}
		
		if ($deflatedPosition >= $startPos && $deflatedPosition <= $originalEndPos)
			{
			if ($deflatedPosition < $originalEndPos || !$isMarkStart[$i])
				{
				$repLength += $markLength[$i];
				}
			}
		}

	return($correctedStartPos, $repLength);
	}

# Valid after calling GetTagAndQuotePositions() above.
sub LineHasMarkTags {
	my $numTags = @markStartPos;
	my $result = ($numTags > 0);
	return($result);
	}
} ##### HTML tag, quote, and <mark> positions.

# Get links (except internal headers) for a range of lines in a CodeMirror view.
# Called by CmGetLinksForText().
sub AddWebAndFileLinksToVisibleLinesForCodeMirror {
	my ($text, $firstLineNum, $contextDir, $linksA, $host, $port,
		$clientIsRemote, $allowEditing) = @_;
	my @lines = split(/\n/, $text);
	#my $doingCM = 1;
	for (my $counter = 0; $counter < @lines; ++$counter)
		{
		my $currentLineNumber = $firstLineNum + $counter;
		AddWebAndFileLinksToLine($lines[$counter], $contextDir, $host, $port,
					$clientIsRemote, $allowEditing, '0', $currentLineNumber, $linksA);

		AddGlossaryHints($lines[$counter], $contextDir, $host, $port, $VIEWERNAME, $currentLineNumber, $linksA);
		}
	}

# Get links, for non-CodeMirror (txt pl etc) files.
sub AddWebAndFileLinksToVisibleLines {
	my ($text, $dir, $ext, $serverAddr, $server_port,
		$clientIsRemote, $allowEditing, $shouldInline, $resultR) = @_;
	my @lines = split(/\n/, $text);
	
	if (IsTextFileExtension($ext) || IsPodExtension($ext))
		{
		for (my $counter = 0; $counter < @lines; ++$counter)
			{
			AddModuleLinkToText(\${lines[$counter]}, $dir, $serverAddr, $server_port, $clientIsRemote, $allowEditing);
			}
		}
	elsif(IsPerlExtension($ext))
		{
		for (my $counter = 0; $counter < @lines; ++$counter)
			{
			if ($lines[$counter] =~ m!(use|import)\s*</span>!)
				{
				AddModuleLinkToPerl(\${lines[$counter]}, $dir, $serverAddr, $server_port, $clientIsRemote, $allowEditing);
				}
			}
		}

	for (my $counter = 0; $counter < @lines; ++$counter)
		{
		AddWebAndFileLinksToLine(\${lines[$counter]}, $dir, $serverAddr, $server_port, 
								$clientIsRemote, $allowEditing, $shouldInline);
		AddGlossaryHints(\${lines[$counter]}, $dir, $serverAddr, $server_port, $VIEWERNAME);
		}

	#$$resultR = join("\n", @lines);
	$$resultR = encode_utf8(join("\n", @lines));
	}

sub WebLink {
	my ($url, $host, $port, $linkName) = @_; # $linkName is optional, == $url if not supplied.
	$linkName ||= $url;
	my $result = "<a href='$url' target='_blank'>$linkName</a>";
	return($result);
	}

# ext.pm#313 $popularExtensionsForLanguage{'Plain Text'} = 'txt,text,conf,def,list,log';
# We just do txt, log, bat for linking.
sub IsTextFileExtension {
	my ($ext) = @_;
	return($ext eq ".txt" || $ext eq ".log" || $ext eq ".bat");
	#return($ext =~ m!\.(txt|log|bat)$!);
	}

# ext.pm#239 $extensionsForLanguage{'Perl Pod'} = 'pod';
sub IsPodExtension {
	my ($ext) = @_;
	return($ext eq ".pod");
	#return($ext =~ m!^\.pod$!);
	}

# ext.pm#312 $popularExtensionsForLanguage{'Perl'} = 'pl,pm,cgi,t,pod';
# (pod is treated separately.)
sub IsPerlExtension {
	my ($ext) = @_;
	return($ext eq ".pl" || $ext eq ".pm" || $ext eq ".cgi" || $ext eq ".t");
	#return($ext =~ m!\.(p[lm]|cgi|t)$!);
	}

# Turn 'use Package::Module;' into a link to cpan. One wrinkle, if it's a local-only module
# then link directly to the module. (This relies on user having indexed the module while
# setting up full text search, but I can't think of a better way.)
sub AddModuleLinkToText {
	my ($txtR, $dir, $host, $port, $clientIsRemote, $allowEditing) = @_;

	# Worth looking only if "use " or "import " appears in the text.
	if (index($$txtR, "use ") < 0 && index($$txtR, "import ") < 0)
		{
		return;
		}

	# Make a version of $$txtR with <mark> tags removed, remember where they are.
	GetMarkStartsAndLengths($$txtR);
	my $hasMarks = LineHasMarkTags();
	my $strippedline = $$txtR;
	if ($hasMarks)
		{
		$strippedline =~ s!(</?mark[^>]*>)!!g;
		}


	# Collect replacement string for the module links, apply them in reverse at the end.
	my @reps;
	my @repsPositions;
	my @repLength;
	my $foundAModule = 0;

	# Look for use X::Y, import X::Y, use local_module etc. Some spurious matches
	# are happening in text files, but not I hope too many.
	while ($strippedline =~ m!^((\s*(use|import)\s+)(\w[0-9A-Za-z_:]+)(;| \"| qw| \'))|((.+?(use|import)\s+)([a-zA-Z][0-9A-Za-z_:]+)(;| \"| qw| \'))!g)
#	while ($strippedline =~ m!^((\s*(use|import)\s+)(\w[0-9A-Za-z_:]+);)|((.+?(use|import)\s+)([a-zA-Z][0-9A-Za-z_:]+);)!g)
		{
		my $mid;
		my $midPos;
		my $midLength;
		if (defined($4))
			{
			$mid = $4; # the full module name eg "This", or "This::That"
			$midPos = $-[4];
			$midLength = $+[4] - $midPos;
			}
		else
			{
			$mid = $9; # the full module name eg "This", or "This::That"
			$midPos = $-[9];
			$midLength = $+[9] - $midPos;
			}
		
		# Avoid doing a single colon, such as use C:/folder. Also skip if an apostrophe
		# follows the $mid module name.
		if (!(index($mid, ":") > 0 && index($mid, "::") < 0)
		  && !(substr($strippedline, $midPos + $midLength, 1) eq "'"))
			{
			# Get original text for $mid, with <mark> tags included.
			($midPos, $midLength) = CorrectedPositionAndLength($midPos, $midLength);
			my $displayMid = substr($$txtR, $midPos, $midLength);
			
			$mid = ModuleLink($mid, $displayMid, $dir, $host, $port, $clientIsRemote, $allowEditing);
			#$textCopy = substr($$txtR, 0, $midPos) . $mid . substr($$txtR, $midPos + $midLength);
			push @reps, $mid;
			push @repsPositions, $midPos;
			push @repLength, $midLength;
			$foundAModule = 1;
			}
		}

	# Apply replacements to $$txtR in reverse order to preserve positions.
	my $numReps = @reps;
	if ($numReps)
		{
		for (my $i = $numReps - 1; $i >= 0; --$i)
			{
			$$txtR = substr($$txtR, 0, $repsPositions[$i]) . $reps[$i] . substr($$txtR, $repsPositions[$i] + $repLength[$i]);
			}
		}
	}

# Turn 'use Package::Module;' into a link to cpan. One wrinkle, if it's a local-only module
# then link directly to the module. (This relies on user having indexed the module while
# setting up full text search, but I can't think of a better way.)
# Another wrinkle, if see "use base qw(Top::Next);" then try to link to /Top/Next.pm.
# Typical "use" with qw: "use base           qw(Text::Markdown);" is seen as
# <span class="Keyword">use</span> <span class="Package">
# base</span>           <span class="Quote">qw(</span><span class="String">Text::Markdown</span>
# <span class="Quote">)</span><span class="Symbol">;</span>
# TODO this picks up the occasional spurious "use" mention, though not very often.
sub AddModuleLinkToPerl {
	my ($txtR, $dir, $host, $port, $clientIsRemote, $allowEditing) = @_;
		
	# Worth looking only if "use" appears in the text.
	if (index($$txtR, "use") < 0)
		{
		return;
		}

	# Make a version of $$txtR with <mark> tags removed, remember where they are.
	GetMarkStartsAndLengths($$txtR);
	my $hasMarks = LineHasMarkTags();
	my $strippedline = $$txtR;
	if ($hasMarks)
		{
		$strippedline =~ s!(</?mark[^>]*>)!!g;
		}
	
	my $modulePartialPath = '';
	my $displayedModuleName = '';
	my $dispPosition;
	my $dispLength;
	my $pre = '';
	my $post = '';
	
	if ($strippedline =~ m!^(.*?use\s*</span>\s*<span class=['"]Package['"]>)(base\s*)(</span>\s*<span class=['"]Quote['"]>qw\(</span><span class=['"]String['"]>)([^<]+)(</span><span class=['"]Quote['"]>\)</span><span class=['"]Symbol['"]>;</span>.*?)$!)
		{
		$pre = $1;
		my $base = $2;
		my $intermediate = $3;
		$modulePartialPath = $4;
		$post = $5;
		$displayedModuleName = $base;
		$dispPosition = $-[2];
		$dispLength = $+[2] - $dispPosition;
		
		$post = $intermediate . $modulePartialPath . $post;
		}

	elsif ( $strippedline =~ m!^(.*?use\s*</span>\s*<span class=['"]Package['"]>)([^<]+)(</span>.*?)$!
	  || $$txtR =~ m!(.*?import\s*</span>\s*<span class=['"]Bareword['"]>)([^<]+)(</span>.*?)$! )
		{
		$pre = $1;
		$modulePartialPath = $2;
		$post = $3;
		$displayedModuleName = $modulePartialPath;
		$dispPosition = $-[2];
		$dispLength = $+[2] - $dispPosition;
		}
		
	if ($pre ne '')
		{
		($dispPosition, $dispLength) = CorrectedPositionAndLength($dispPosition, $dispLength);
		$displayedModuleName = substr($$txtR, $dispPosition, $dispLength);
		my $mid = ModuleLink($modulePartialPath, $displayedModuleName, $dir, $host, $port, $clientIsRemote, $allowEditing);
		$$txtR = substr($$txtR, 0, $dispPosition) . $mid . substr($$txtR, $dispPosition + $dispLength);
		}
	}

# Return links to metacpan and to source for a Perl module mention.
sub ModuleLink {
	my ($srcTxt, $displayText, $dir, $host, $port, $clientIsRemote, $allowEditing) = @_;
	my $result = '';
	
	my $isCustom = 0;
	my $modulePartialPath = $srcTxt . '.pm';
	if (index($srcTxt, '::') > 0)
		{
		$modulePartialPath =~ s!::!/!g;
		}

	my $fullPath = FullPathInContextTrimmed($modulePartialPath, $dir); # reverse_filepaths.pm#FullPathInContextTrimmed()
	if ($fullPath ne '')
		{
		if ($fullPath !~ m!/perl(64)?/!i)
			{
			$isCustom = 1;
			}
		}
	
	if ($isCustom)
		{
		# Link to file, follow with edit link.
		my $editLink = '';
		if ($allowEditing)
			{
			$editLink = " <a href='' class='canedit' onclick=\"editOpen('$fullPath'); return false;\">"
						. "<img src='edit1.png' width='17' height='12' />" . '</a>';
			}
		my $viewerLink = "<a href=\"http://$host:$port/$VIEWERNAME/?href=$fullPath\" onclick=\"openView(this.href, $VIEWERNAME); return false;\"  target=\"_blank\">$displayText</a>";
		$result = "$viewerLink$editLink";
		}
	else # path not found, or path found but in main Perl or Perl64 folder
		{
		#
		my $docsLink = "<a href='https://metacpan.org/pod/$srcTxt' target='_blank'><img src='metacpan-icon.png' /></a>";
		
		# Link to file if possible, follow with meta-cpan link.
		if ($fullPath ne '')
			{
			my $viewerLink = "<a href=\"http://$host:$port/$VIEWERNAME/?href=$fullPath\" onclick=\"openView(this.href, $VIEWERNAME); return false;\"  target=\"_blank\">$displayText</a>";
			$result = "$viewerLink$docsLink";
			}
		else # just tack on a meta-cpan link - but ONLY if module name starts with [A-Z].
			{
			my $firstChar = substr($srcTxt, 0, 1);
			my $ordVal = ord($firstChar);
			if ($ordVal >= 65 && $ordVal <= 90)
				{
				$result = $displayText . $docsLink;
				}
			else
				{
				$result = $displayText;
				}
			}
		}
	
	return($result);
	}

# Return HTML link for a link mention in a Pod file.
sub PodLink {
	my ($srcTxt, $dir, $host, $port, $clientIsRemote, $allowEditing) = @_;
	my $result = '';
	
	# Separate displayed text from name.
	my $text;
	my $name;
	my $pos;
	if (($pos = index($srcTxt, '|')) > 0)
		{
		$text = substr($srcTxt, 0, $pos);
		$name = substr($srcTxt, $pos+1);
		}
	else
		{
		$text = $srcTxt;
		$name = $srcTxt;
		}
	
	# Is it one of them hyperlink things?
	if (index($name, 'http') == 0)
		{
		#$result = WebLink($name, $host, $port, $text);
		}
	else
		{
		# Tweak, for something like "See Bit::Vector::Overload(3)" strip the (3).
		$name =~ s!\s*\(\d+\)\s*$!!;
		$result = ModuleLink($name, $text, $dir, $host, $port, $clientIsRemote, $allowEditing);
		}
	
	return($result);
	}
