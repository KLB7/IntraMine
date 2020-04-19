# intramine_linker.pl: pass in plain text, and get back either:
# text with links - see NonCmLinks()
# or a JSON summary of the links that can be used to create an overlay for CodeMirror
# - see CmLinks().
# File and web links are handled, "internal" links within a document are handled
# in intramine_viewer.pl.
# FullPathForPartial() will return its best guess at a full path, given a partial path.
#
# This server is a "second level" server without any displayed interface, and all calls
# to retrieve links are done with JavaScript in the Viewer and Files servers.
# In the Viewer service's front end JavaScript:
# - To trace CodeMirror autolinks, start with cmAutoLinks.js#addAutoLinks(), which ends up
# calling back to CmLinks() via "req=cmLinks".
# - To trace non-CodeMirror (mainly .txt and Perl) autolinks, start with autoLinks.js#addAutoLinks(),
#  which ends up calling back to NonCmLinks() via "req=nonCmLinks".
# In the Files service's front end JavaScript:
# - FullPathForPartial() is called by files.js#openAutoLink(), via "req=autolink".

# perl C:\perlprogs\mine\intramine_linker.pl

use strict;
use warnings;
use utf8;
use FileHandle;
use Encode;
use Encode::Guess;
use HTML::Entities;
use URI::Escape;
use Text::Tabs;
$tabstop = 4;
use Syntax::Highlight::Perl::Improved ':BASIC';  # ':BASIC' or ':FULL' - FULL doesn't seem to do much
use Time::HiRes qw ( time );
use Win32::Process; # for calling Exuberant ctags.exe
use JSON::MaybeXS qw(encode_json);
use Text::MultiMarkdown; # for .md files
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;
use reverse_filepaths;
use pod2thml_intramine;
use win_wide_filepaths;
use docx2txt;
use ext; # for ext.pm#IsTextExtensionNoPeriod() etc.

Encode::Guess->add_suspects(qw/iso-8859-1/);

$|  = 1;

my $PAGENAME = '';
my $SHORTNAME = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

# Need for linking, to call the Viewer to open files.
my $VIEWERNAME = CVal('VIEWERSHORTNAME');

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

# Actions. Respond to requests for links, from CodeMirror views, text views, and Files.
my %RequestAction;
$RequestAction{'signal'} = \&HandleBroadcastRequest; 	# signal = anything, but for here specifically signal=reindex
$RequestAction{'req|cmLinks'} = \&CmLinks; 		# req=cmLinks... - linking for CodeMirror files
$RequestAction{'req|nonCmLinks'} = \&NonCmLinks; 		# req=nonCmLinks... - linking for non-CodeMirror files
$RequestAction{'req|autolink'} = \&FullPathForPartial; 	# req=autolink&partialpath=...
$RequestAction{'/test/'} = \&SelfTest;				# Ask this server to test itself.

# Over to swarmserver.pm. The callback sub loads in a hash of full paths for partial paths,
# which can take some time.
MainLoop(\%RequestAction, undef, undef, \&callbackInitDirectoryFinder);

################### subs

# Generic 'signal' handler, here we are especially interested in 'signal=reindex'. Which means for
# us here that new files have come along, so incorporate them into full path and partial path
# lists, for putting in file links with AddFileWebAndFileLinksToLine() etc.
# See reverse_filepaths.pm#LoadIncrementalDirectoryFinderLists().
# The list of new files is in C:/fwws/fullpaths2.log.
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
		}

	return('OK');	# Returned value is ignored by broadcaster - this is more of a "UDP" than "TCP" approach to communicating.
	}

# Load list of all files and directories, and create a hash holding lists of all
# corresponding known full paths for partial paths, for autolinks.
sub callbackInitDirectoryFinder {
	my $FileWatcherDir = CVal('FILEWATCHERDIRECTORY');
	my $fullFilePathListPath = $FileWatcherDir . CVal('FULL_PATH_LIST_NAME'); # .../fullpaths.out
	
	my $filePathCount = InitDirectoryFinder($fullFilePathListPath); # reverse_filepaths.pm#InitDirectoryFinder()	
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

# For each link, respond JSON for:
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
# Get links for all local file, image, and web links in $formH->{'text'}.
# Links are added on demand for visible lines only.
# Invoked by xmlHttpRequest in autoLinks.js#requestLinkMarkup().
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
		GetLinksForText($formH, $dir, $ext, $clientIsRemote, $allowEditing, \$result);
		}
	
	return($result);
	}

sub GetLinksForText {
	my ($formH, $dir, $ext, $clientIsRemote, $allowEditing, $resultR) = @_;
	my $text = $formH->{'text'};
	#my $firstLineNum = $formH->{'first'};
	#my $lastLineNum = $formH->{'last'};
	my $serverAddr = ServerAddress();
	
	AddWebAndFileLinksToVisibleLines($text, $dir, $ext, $serverAddr, $server_port,
								$clientIsRemote, $allowEditing, $resultR);
	}

# Get best full file path matching 'partialpath'. See reverse_filepaths.pm#FullPathInContextNS().
# This is actually called by the Files page, see files.js#openAutoLinkWithPort().
# The request is handled by this program because reverse_filepaths.pm can take two minutes
# to load up a full list of file names and directories, and because one hopes no one will
# run the Files page without the Search page and supporting Linker service (this program).
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

my $haveRefToText; # For CodeMirror we get the text not a ref, and this is 0.
my $line;
my $revLine;
my $contextDir;
my $len;

# Replacements for discovered links: For text files where replacement is done directly
# in the text, these replacements are more easily done in reverse order to avoid throwing off
# the start/end. For CodeMirror files, reps are done in the JavaScript (using $linksA).
my @repStr;
my @repLen;
my @repStartPos;
my @repLinkType; # For CodeMirror, 'file', 'web', 'image'
my @linkIsPotentiallyTooLong; # For unquoted links to text headers, we grab 100 chars, which might be too much.

my $longestSourcePath;
my $bestVerifiedPath;

# AddWebAndFileLinksToLine: look for file and web address mentions, turn them into links.
# Does the promised "auto linking", so no quotes etc are needed around file names even if
# the file name contains spaces, and a partial path is needed only if the file name isn't unique
# and the file being mentioned isn't the "closest" one, where distance is measured as the number
# of directory moves up and down from the referring file to the file being mentioned. So eg
# mentioning main.cpp is fine if the referring file is proj51/docs/design.txt and the file wanted
# is proj51/src/main.cpp, but if the referring file is somewhere outside the proj51 folder then
# it should be mentioned as proj51/src/main.cpp. See Gloss.txt for more about links.
# One exception, quotes are needed to link to a header within a document. Picking one of my own
# docs as an example, IntraMine Jan 2019.txt becomes a link, but to link to a header within it
# quotes are needed: eg "IntraMine Jan 2019.txt#Editor/Opener links in CodeMirror views".
# OK the quotes aren't really needed, but your resulting links will look better if you use them,
# since without the quotes an arbitrary 100 characters will be grabbed as the potential
# header string, leaving it to the receiving end to figure out which header is meant.
sub AddWebAndFileLinksToLine {
	my ($txtR, $theContextDir, $theHost, $thePort, $theClientIsRemote, $shouldAllowEditing,
		$currentLineNumber, $linksA) = @_;
	
	if (ref($txtR) eq 'SCALAR') # ref to a SCALAR, so doing text
		{
		if ($$txtR !~ m!\.\w! && $$txtR !~ m!http!)
			{
			return;
			}
		$haveRefToText = 1;
		$line = $$txtR;
		}
	else # not a ref (at least it shouldn't be), so doing CodeMirror
		{
		# Return if nothing on the line looks roughly like a link.
		if ($txtR !~ m!\.\w! && $txtR !~ m!http!)
			{
			return;
			}
		$haveRefToText = 0;
		$line = $txtR;
		}
	
	# And init all the remaining variables with AutoLink scope.
	$revLine = scalar reverse($line);
	$contextDir = $theContextDir;
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
sub EvaluateLinkCandidates {
	my $previousEndPos = 0;
	my $previousRevEndPos = $len;
	my $haveGoodMatch = 0; # check-back distance is not adjusted if there is no good current match.
	my $hadGoodMatch = 0; # Don't advance $startPos if there was previous match.
	
	# Collect positions of quotes and HTML tags (start and end of both start and end tags).
	GetHtmlTagAndQuotePositions($line);
	
	# while see quotes or a potential file .extension, or http(s)://
	while ($line =~ m!((\"(.+?)\.\w+(#[^"]+)?\")|(\'([^']+)\.\w+(#[^']+)?\')|\.(\w\w?\w?\w?\w?\w?\w?)(\#[A-Za-z0-9_:]+)?|((https?://([^\s)<\"](?\!ttp:))+)))!g)
#	while ($line =~ m!((\"([^"]+)\.\w+(#[^"]+)?\")|(\'([^']+)\.\w+(#[^']+)?\')|\.(\w\w?\w?\w?\w?\w?\w?)(\#[A-Za-z0-9_:]+)?|((https?://([^\s)<\"](?\!ttp:))+)))!g)
		{
		my $startPos = $-[0];	# this does include the '.', beginning of entire match
		my $endPos = $+[0];		# pos of char after end of entire match
		my $ext = $1;			# double-quoted chunk, or extension (plus any anchor), or url
		
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
					if ($haveRefToText && $startPos >= 7)
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

			# Skip quotes that are inside HTML tags.
			# Is quote at $startPos at a bad position? Skip.
			# Is quote at $endPos at a bad position? Reset to next good position, or skip.
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
			
			if (!$badQuotation)
				{
				# Trim quotes and pick up $quoteChar.
				$quoteChar =  substr($ext, 0, 1);
				$ext = substr($ext, 1);
				$ext = substr($ext, 0, length($ext) - 1);
				}
			}
		
		if ($badQuotation)
			{
			pos($line) = $startPos + 1;
			}
		else
			{
			my $haveURL = (index($ext, 'http') == 0);
			my $anchorWithNum = (!$haveQuotation && !$haveURL && defined($9)) ? $9 : ''; # includes '#'
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
			my $haveGoodExtension = ($haveTextExtension || $haveImageExtension); # else URL
			
			my $linkIsMaybeTooLong = 0;
			
			# Potentially a text file mention or an image.
			if ($haveGoodExtension)
				{
				$haveGoodMatch = RememberTextOrImageFileMention($startPos, $previousRevEndPos, $ext, $extProper,
							$haveQuotation, $haveTextExtension, $haveImageExtension, $quoteChar, $anchorWithNum);
				} # if known extensions
			elsif ($haveURL)
				{
				RememberUrl($startPos, $haveQuotation, $quoteChar, $url);
				$haveGoodMatch = 1;
				}
			
			if ($haveGoodMatch)
				{
				$previousEndPos = $endPos;
				$previousRevEndPos = $len - $previousEndPos - 1; # Limit backwards extent of 2nd and subsequent searches.
				$haveGoodMatch = 0;
				}
			elsif (!$haveGoodMatch && $haveQuotation)
				{
				pos($line) = $startPos + 1;
				}
			}
		} # while another extension or url matched
	}


# If we can find a valid file mention looking backwards from $startPos, remember its details
# in @repStr, @repLen etc.
sub RememberTextOrImageFileMention {
	my ($startPos, $previousRevEndPos, $ext, $extProper, $haveQuotation,
		$haveTextExtension, $haveImageExtension, $quoteChar, $anchorWithNum) = @_;
	my $linkIsMaybeTooLong = 0;
	
	# To allow for spaces in #anchors where file#anchor hasn't been quoted, grab the
	# 100 chars following '#' here, and sort it out on the other end when going to
	# the anchor. Only for txt files.
	if ($extProper eq 'txt' && !$haveQuotation && $anchorWithNum ne '')
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
		
		my $verifiedPath = FullPathInContextNS($pathToCheck, $contextDir);
		if ($verifiedPath ne '')
			{
			$longestSourcePath = $pathToCheck;
			$bestVerifiedPath = $verifiedPath;
			$doingQuotedPath = 1;
			}
		}
	
	my $revPos = $len - $startPos - 1 + 1; # extra +1 there to skip '.' before the extension proper.
	
	# Extract the substr to search.
	# (Note to self, using ^.{}... might be faster.)
	my $revStrToSearch = substr($revLine, $revPos, $previousRevEndPos - $revPos + 1);
	
	# Good break points for hunt are [\\/ ], and [*?"<>|\t] end the hunt.
	# For image files only, we look in a couple of standard places for just the file name.
	# This can sometimes be expensive, but we look at the standad locations only until
	# either a slash is seen or a regular mention is found.
	my $checkStdImageDirs = ($haveImageExtension) ? 1 : 0;
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
		
		if ($haveTextExtension)
			{
			GetTextFileRep($haveQuotation, $quoteChar, $extProper, $longestSourcePath,
							$anchorWithNum, \$repString);
			}
		else # currently only image extension
			{
			$linkType = 'image'; # For CodeMirror
			GetImageFileRep($haveQuotation, $quoteChar, $usingCommonImageLocation,
							$imageName, \$repString);
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
	
	if (!length($revStrToSearch))
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
			$currentRevPos = $len;
			}
		else
			{
			if ($revStrToSearch =~ m!^.{$prevSubRevPos}.*?([ \t/\\,\(>])!s)
				{
				$currentRevPos = $-[1];
					
				if ($currentRevPos >= 0)
					{
					my $charSeen = $1;
					if ($charSeen eq "/" || $charSeen eq "\\")
						{
						$slashSeen = 1;
						# Check for a second slash in $revStrToSearch, signalling a
						# \\host\share... or //host/share... location.
						if ($currentRevPos < $len - 1
							&& substr($revStrToSearch, $currentRevPos + 1, 1) eq $charSeen)
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
			my $trimmedNextTerm = substr($nextTerm, $trimOffset); # trim space etc at start, unless checking to end
			$trimmedCurrentPath = $trimmedNextTerm . $currentPath;
			$currentPath = $nextTerm . $currentPath;
			
			# See reverse_filepaths.pm#FullPathInContextNS().
			my $verifiedPath = FullPathInContextNS($trimmedCurrentPath, $contextDir);
			
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

# Cook up viewer and editor links for $bestVerifiedPath, put them in $$repStringR.
sub GetTextFileRep {
	my ($haveQuotation, $quoteChar, $extProper, $longestSourcePath,
		$anchorWithNum, $repStringR) = @_;
	
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
	
	my $displayedLinkName = $longestSourcePath . $anchorWithNum;
	if ($haveQuotation)
		{
		$displayedLinkName = $quoteChar . $displayedLinkName . $quoteChar;
		}
	
	if ($allowEditing)
		{
		if (!$clientIsRemote || $extProper !~ m!docx|pdf!i)
			{
			$editLink = "<a href='$editorPath' class='canedit' onclick=\"editOpen(this.href); return false;\">"
					. "<img class='edit_img' src='edit1.png' width='17' height='12'>" . '</a>';
			}
		}
	
	my $viewerLink = "<a href=\"http://$host:$port/$VIEWERNAME/?href=$viewerPath$anchorWithNum\" onclick=\"openView(this.href); return false;\"  target=\"_blank\">$displayedLinkName</a>";
	$$repStringR = "$viewerLink$editLink";
	}

# Do up a view/hover link for image in $bestVerifiedPath, put that in $$repStringR.
sub GetImageFileRep {
	my ($haveQuotation, $quoteChar, $usingCommonImageLocation, $imageName, $repStringR) = @_;
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
	my $imagePath = "http://$host:$port/$VIEWERNAME/$fullPath";
	my $originalPath = $usingCommonImageLocation ? $imageName : $longestSourcePath;
	my $displayedLinkName = $originalPath;
	if ($haveQuotation)
		{
		$displayedLinkName = $quoteChar . $displayedLinkName . $quoteChar;
		}
	my $leftHoverImg = "<img src='http://$host:$port/hoverleft.png' width='17' height='12'>"; # actual width='32' height='23'>";
	my $rightHoverImg = "<img src='http://$host:$port/hoverright.png' width='17' height='12'>";
	if ($haveRefToText)
		{
		$$repStringR = "<a href=\"http://$host:$port/$VIEWERNAME/?href=$fullPath\" onclick=\"openView(this.href); return false;\"  target=\"_blank\" onmouseover=\"showhint('<img src=&quot;$imagePath&quot;>', this, event, '500px', true);\">$leftHoverImg$displayedLinkName$rightHoverImg</a>";
		}
	else
		{
		$imagePath =~ s!%!%25!g;
		my $imageOpenHref = "http://$host:$port/$VIEWERNAME/?href=$fullPath";
		$$repStringR = "<a href=\"$imageOpenHref\" target='_blank' onmouseover=\"showhint('<img src=&quot;$imagePath&quot;>', this, event, '500px', true);\">$leftHoverImg$displayedLinkName$rightHoverImg</a>";
		}
	}

# Push url details onto @repStr, @repLen etc.
# One exception, if $url is too short to be real then skip it.
sub RememberUrl {
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
		
	# Skip this one if it's too short to be a real url. http://a.b is the shortest I think, len 10.
	if (length($url) < 10)
		{
		return;
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
	if (!$haveRefToText) # CodeMirror
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
		
	# Second pass, just do the replacments.
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

{ ##### HTML tag and quote positions
my @htmlTagStartPos;
my @htmlTagEndPos;
my $numHtmlTags;
my @quotePos;
my $numQuotes;
my %badQuotePosition;

sub GetHtmlTagAndQuotePositions {
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
	}
	
# Find start and end positions of HTML start/end tags on line.
sub GetHtmlStartsAndEnds {
	my ($line) = @_;
	
	while ($line =~ m!(</[^>]+>)!g)
		{
		my $startPos = $-[1];	# beginning of match
		my $endPos = $+[1];		# one past last matching character
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
} ##### HTML tag and quote positions

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
					$clientIsRemote, $allowEditing, $currentLineNumber, $linksA);
		}
	}

sub AddWebAndFileLinksToVisibleLines {
	my ($text, $dir, $ext, $serverAddr, $server_port,
		$clientIsRemote, $allowEditing, $resultR) = @_;
	my @lines = split(/\n/, $text);
	
	if (IsTextFileExtension($ext))
		{
		for (my $counter = 0; $counter < @lines; ++$counter)
			{
			AddModuleLinkToText(\${lines[$counter]}, $dir, $serverAddr, $server_port, $clientIsRemote, $allowEditing);
			}
		}
	elsif (IsPodExtension($ext))
		{
		for (my $counter = 0; $counter < @lines; ++$counter)
			{
			while ($lines[$counter] =~ m!^(.*?)<l>(.+?)</l>(.*)$!)
				{
				my $pre = $1;
				my $link = $2;
				my $post = $3;
				$link = PodLink($link, $dir, $serverAddr, $server_port, $clientIsRemote);
				$lines[$counter] = $pre . $link . $post;
				}
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
	
	#my $doingCM = 0;
	for (my $counter = 0; $counter < @lines; ++$counter)
		{
		AddWebAndFileLinksToLine(\${lines[$counter]}, $dir, $serverAddr, $server_port, 
								$clientIsRemote, $allowEditing);
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
sub IsTextFileExtension {
	my ($ext) = @_;
	return($ext =~ m!\.(txt|log|bat)$!);
#	return($ext =~ m!^\.(txt|text|conf|def|list|log)$!);
	}

# ext.pm#239 $extensionsForLanguage{'Perl Pod'} = 'pod';
sub IsPodExtension {
	my ($ext) = @_;
	return($ext =~ m!^\.pod$!);
	}

# ext.pm#312 $popularExtensionsForLanguage{'Perl'} = 'pl,pm';
sub IsPerlExtension {
	my ($ext) = @_;
	return($ext =~ m!\.(p[lm]|cgi|t)$!);
	}

# Turn 'use Package::Module;' into a link to cpan. One wrinkle, if it's a local-only module
# then link directly to the module. (This relies on user having indexed the module while
# setting up full text search, but I can't think of a better way.)
sub AddModuleLinkToText {
	my ($txtR, $dir, $host, $port, $clientIsRemote, $allowEditing) = @_;

	# The regex for module/package name here isn't perfect, just good enough. Unfortunately, in a text
	# file the word "use" pops up quite often, so it's better to restrict linking to cases where "use"
	# starts the line or it's followed by something that really looks like a package name (an uppercase
	# letter will do).
	if ( $$txtR =~ m!^(\s*(use|import)\s+)(\w[0-9A-Za-z_:]+)(.+?)$!
	  || $$txtR =~ m!^(.+?(use|import)\s+)([A-Z][0-9A-Za-z_:]+)(.+?)$! )
		{
		my $pre = $1;
		my $mid = $3; # the full module name eg "This", or "This::That"
		my $post = $4;
		
		# Avoid doing a single colon, such as use C:/folder. Also skip if an apostrophe
		# follows the $mid module name.
		if (!(index($mid, ":") > 0 && index($mid, "::") < 0)
		  && !(substr($post, 0, 1) eq "'"))
			{
			$mid = ModuleLink($mid, $dir, $host, $port, $clientIsRemote, $allowEditing);
			$$txtR = $pre . $mid . $post;
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
# (Note this should be called before wrapping in tr/td elements.)
# TODO this picks up the occasional spurious "use" mention, though not very often.
sub AddModuleLinkToPerl {
	my ($txtR, $dir, $host, $port, $clientIsRemote, $allowEditing) = @_;
	
	my $modulePartialPath = '';
	my $displayedModuleName = '';
	my $pre = '';
	my $post = '';
	
	if ($$txtR =~ m!^(.*?use\s*</span>\s*<span class=['"]Package['"]>)(base\s*)(</span>\s*<span class=['"]Quote['"]>qw\(</span><span class=['"]String['"]>)([^<]+)(</span><span class=['"]Quote['"]>\)</span><span class=['"]Symbol['"]>;</span>.*?)$!)
		{
		$pre = $1;
		my $base = $2;
		my $intermediate = $3;
		$modulePartialPath = $4;
		$post = $5;
		$displayedModuleName = $base;
		
		$post = $intermediate . $modulePartialPath . $post;
		}

	elsif ( $$txtR =~ m!^(.*?use\s*</span>\s*<span class=['"]Package['"]>)([^<]+)(</span>.*?)$!
	  || $$txtR =~ m!(.*?import\s*</span>\s*<span class=['"]Bareword['"]>)([^<]+)(</span>.*?)$! )
		{
		$pre = $1;
		$modulePartialPath = $2;
		$post = $3;
		$displayedModuleName = $modulePartialPath;
		}
		
	if ($pre ne '')
		{
		my $mid = ModuleLink($modulePartialPath, $dir, $host, $port, $clientIsRemote, $allowEditing, $displayedModuleName);
		$$txtR = $pre . $mid . $post;
		}
	}

# Return links to metacpan and to source for a Perl module mention.
sub ModuleLink {
	my ($srcTxt, $dir, $host, $port, $clientIsRemote, $allowEditing, $linkName) = @_;
	$linkName ||= $srcTxt;
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
		my $viewerLink = "<a href=\"http://$host:$port/$VIEWERNAME/?href=$fullPath\" onclick=\"openView(this.href); return false;\"  target=\"_blank\">$linkName</a>";
		$result = "$viewerLink$editLink";
		}
	else # path not found, or path found but in main Perl or Perl64 folder
		{
		my $docsLink = "<a href='https://metacpan.org/pod/$srcTxt' target='_blank'><img src='metacpan-icon.png' /></a>";
		
		# Link to file if possible, follow with meta-cpan link.
		if ($fullPath ne '')
			{
			my $viewerLink = "<a href=\"http://$host:$port/$VIEWERNAME/?href=$fullPath\" onclick=\"openView(this.href); return false;\"  target=\"_blank\">$linkName</a>";
			$result = "$viewerLink$docsLink";
			}
		else # just tack on a meta-cpan link
			{
			$result = $srcTxt . $docsLink;
			}
		}
	
	return($result);
	}

# Return HTML link for a link mention in a Pod file.
sub PodLink {
	my ($srcTxt, $dir, $host, $port, $clientIsRemote) = @_;
	my $result = '';
	
	#print("PodLink: |$srcTxt|\n");
	
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
		$result = WebLink($name, $host, $port, $text);
		}
	else
		{
		# Tweak, for something like "See Bit::Vector::Overload(3)" strip the (3).
		$name =~ s!\s*\(\d+\)\s*$!!;
		$result = ModuleLink($name, $dir, $host, $port, $clientIsRemote, $text);
		}
	
	return($result);
	}
