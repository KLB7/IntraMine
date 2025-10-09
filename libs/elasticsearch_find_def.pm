# elasticsearch_find_def.pm: retrieve links for files that contain
# definitions of functions, and sometimes structs/classes.
# An outline of the whole process:
# Viewer or Editor, user selects a word or short phrase in a source file.
# go2def.js asks the Linker for a list of links to show in a showhint popup.
# The Linker's Definitions() sub calls GetDefinitionHits() here.
# which first calls Elasticsearch to find files containing the word.
# If found, universal ctags is called to generate definition summaries
# for each file.
# Those with definitions are packaged up as links and returned.
# As a last resort, any hits found for the word or phrase are returned.
# See also intramine_linker.pl#Go2().

package elasticsearch_find_def;

use strict;
use warnings;
use utf8;
use HTML::Entities;
use Carp;
use FileHandle;
use Text::Tabs;
$tabstop = 4;
use Search::Elasticsearch;
use Encode;
use Encode::Guess;
use URI::Escape;

use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
#use lib ".";
use common;
use toc_local;
use ext;

# Some languages introduce a function with a keyword.
# The keyword is prepended to the Elasticsearch query
# to narrow down found files to those containing definitions.
# (For other languages, no keyword is added.)
my %DefinitionKeyForExtension;
# Perl: pl,pm,cgi,t,not pod
$DefinitionKeyForExtension{'pl'}  = 'sub';
$DefinitionKeyForExtension{'pm'}  = 'sub';
$DefinitionKeyForExtension{'cgi'} = 'sub';
$DefinitionKeyForExtension{'t'}   = 'sub';
# JavaScript: just js
$DefinitionKeyForExtension{'js'} = 'function';
# Go: just go
$DefinitionKeyForExtension{'go'} = 'func';
# Fortran: $extensionsForLanguage{'Fortran'} = 'f,for,f77,f90,f95, f03';
$DefinitionKeyForExtension{'f'}   = 'function|subroutine';
$DefinitionKeyForExtension{'for'} = 'function|subroutine';
$DefinitionKeyForExtension{'f77'} = 'function|subroutine';
$DefinitionKeyForExtension{'f90'} = 'function|subroutine';
$DefinitionKeyForExtension{'f95'} = 'function|subroutine';
$DefinitionKeyForExtension{'f03'} = 'function|subroutine';
# Basic: vb, vbs
$DefinitionKeyForExtension{'vb'}  = 'sub|function';
$DefinitionKeyForExtension{'vbs'} = 'sub|function';
# Python: BUILD,bzl,py,pyw
$DefinitionKeyForExtension{'BUILD'} = 'def';
$DefinitionKeyForExtension{'bzl'}   = 'def';
$DefinitionKeyForExtension{'py'}    = 'def';
$DefinitionKeyForExtension{'pyw'}   = 'def';

# Some languages such as C / C++ have header and implementation extensions.
# Search implementation first, then headers if nothing found.
# Actually C and C++ are the only ones I could find.
my %HeaderExtForLanguage;
my %ImpExtForLanguage;
$HeaderExtForLanguage{'C/C++'} = 'hpp,h,hh,hxx';
$ImpExtForLanguage{'C/C++'}    = 'cpp,cc,c,cxx';
my %LanguageForHeaderExt;
$LanguageForHeaderExt{'hpp'} = 'C/C++';
$LanguageForHeaderExt{'h'}   = 'C/C++';
$LanguageForHeaderExt{'hh'}  = 'C/C++';
$LanguageForHeaderExt{'hxx'} = 'C/C++';
$LanguageForHeaderExt{'cpp'} = 'C/C++';
$LanguageForHeaderExt{'cc'}  = 'C/C++';
$LanguageForHeaderExt{'c'}   = 'C/C++';
$LanguageForHeaderExt{'cxx'} = 'C/C++';

my @PreferredExtensions;

# Make a new elasticsearch_find_def instance,
# init universal ctags.
sub new {
	my ($proto, $indexName, $numHits, $maxShownHits, $host, $port_listen, $VIEWERNAME, $LogDir,
		$ctags_dir,            $HashHeadingRequireBlankBefore,
		$preferredExtensionsA, $monitorCallback)
		= @_;
	my $class = ref($proto) || $proto;
	my $self  = {};

	$self->{INDEX_NAME} = $indexName;
	$self->{RAWHITS}    = $numHits;           # Over 100 can slow the search down.
	$self->{SHOWNHITS}  = $maxShownHits;
	$self->{HOST}       = $host;
	$self->{PORT}       = $port_listen;
	$self->{VIEWERNAME} = $VIEWERNAME;
	$self->{MONITOR}    = $monitorCallback;

	@{$self->{FULLPATHS}} = ();
	@{$self->{PATHQUERY}} = ();
	%{$self->{PATHSEEN}}  = ();

	InitMonitor($monitorCallback);

	@PreferredExtensions = @$preferredExtensionsA;

	# Sniffing is not currently supported (Dec 2018)
	my $e = Search::Elasticsearch->new(
		nodes => 'localhost:9200'
			#			nodes    => '192.168.1.132:9200'
			#			,cxn_pool => 'Sniff'
	);
	$self->{SEARCHER} = $e;

	InitTocLocal($LogDir . 'temp/tempctags',
		$port_listen, $LogDir, $ctags_dir, $HashHeadingRequireBlankBefore);

	bless($self, $class);
	return $self;
}

{ ##### Monitor, for feedback to the "Mon" service
my $monitorCallback;

sub InitMonitor {
	my ($callback) = @_;
	$monitorCallback = $callback;
}

sub Monitor {
	my ($msg) = @_;
	if (defined($monitorCallback))
		{
		$monitorCallback->($msg);
		}
}
}    ##### Monitor, for feedback to the "Mon" service

# See intramine_linker.pl#Go2.
sub Instances {
	my ($self, $rawquery, $fullPath) = @_;
	my $result = '';

	# Having real trouble with a '%' in the search query, but searching
	# for Perl hash names such as %hashName is wanted.
	# intramine_search.js#searchSubmit() converts % to ____PC____
	# and we convert it back here. It's the only way I've found
	# that works, after spending too long on the problem.
	$rawquery =~ s!____PC____!%!;

	@{$self->{FULLPATHS}} = ();
	@{$self->{PATHQUERY}} = ();
	%{$self->{PATHSEEN}}  = ();

	my @wantedExt;
	GetExtensionsForDefinition($fullPath, \@wantedExt);
	my $numExtensions = @wantedExt;
	if ($numExtensions == 0)
		{
		return ('<p>nope</p>');
		}

	my $definitionKeyword = DefKeyForPath($fullPath);
	if ($definitionKeyword eq '')
		{
		# If extension is supported by universal ctags we can continue
		# the hard way (use ctags to find files with definitions).
		if (HasCtagsSupport($self, $fullPath))
			{
			$result = GetCtagsDefinitionLinks($self, $rawquery, \@wantedExt, $fullPath);
			}
		}

	# if ($result ne '' && $result ne '<p>nope</p>')
	# 	{
	# 	return ($result);
	# 	}

	my @keywords;
	my $numHits;
	my $numFiles;

	if ($definitionKeyword ne '')
		{
		if (index($definitionKeyword, '|') > 0)
			{
			@keywords = split(/\|/, $definitionKeyword);
			}
		else
			{
			push @keywords, $definitionKeyword;
			}

		for (my $i = 0 ; $i < @keywords ; ++$i)
			{
			my $query = $keywords[$i] . ' ' . $rawquery;
			$numHits  = 0;
			$numFiles = 0;
			$result =
				GetDefinitionLinks($self, $query, \@wantedExt, \$numHits, \$numFiles, $fullPath);
			if (NumHitsSoFar($self) > 0)
				{
				last;
				}
			}
		}


	# Faint hope: perhaps the selected term is defined in some other
	# language? We'll try .js and .css. Maybe .pl, .pm.
	if (NumHitsSoFar($self) == 0)
		{
		$numHits  = 0;
		$numFiles = 0;
		$result =
			GetDefinitionLinksInOtherLanguages($self, $rawquery, \@wantedExt, \$numHits,
			\$numFiles);
		}

	# Last hope: accept any hits anywhere.
	my $putDividerBefore = -1;
	if (!HitLimitReached($self))
		{
		my $dividerWanted = 0;
		my $numSoFar      = NumHitsSoFar($self);
		if ($numSoFar > 0)
			{
			$dividerWanted = 1;
			}
		my $numDefinitionsAdded = 0;
		$result = GetAnyLinks($self, $rawquery, $fullPath, 1, \$numDefinitionsAdded);
		if ($dividerWanted)
			{
			my $numAfterGetAny   = NumHitsSoFar($self);
			my $totalDefinitions = $numSoFar + $numDefinitionsAdded;
			if ($numAfterGetAny > $numSoFar && $numAfterGetAny > $totalDefinitions)
				{
				$putDividerBefore = $numSoFar + $numDefinitionsAdded;
				}
			}
		}

	FormatFullPathsResults($self, $self->{HOST}, $self->{PORT}, $self->{VIEWERNAME},
		$putDividerBefore, \$result);

	if ($result eq '')
		{
		$result = '<p>nope</p>';
		}

	return ($result);
}

# Determine language based on $fullPath extension, then
# push all extensions for the corresponding language.
sub GetExtensionsForDefinition {
	my ($fullPath, $wantedExtA) = @_;
	if ($fullPath =~ m!\.(\w+)$!)
		{
		my $ext   = lc($1);
		my $langH = LanguageForExtensionHashRef();
		if (defined($langH->{$ext}))
			{
			my $languageName   = $langH->{$ext};
			my $extsForLan     = ExtensionsForLanguageHashRef();
			my $rawExtensions  = $extsForLan->{$languageName};
			my @extForLanguage = split(/,/, $rawExtensions);
			for (my $i = 0 ; $i < @extForLanguage ; ++$i)
				{
				# Some such as pod should be skipped.
				if ($extForLanguage[$i] ne 'pod')
					{
					push @{$wantedExtA}, $extForLanguage[$i];
					}
				}
			}
		}
}

# GetDefinitionLinks(): call Elasticsearch to retrieve documents matching $rawquery.
# Match words supplied as a phrase.
# Only content is searched, a file name mention becomes a FLASH link in IntraMine.
# No restriction on folder, sometimes restrictions on extensions.
sub GetDefinitionLinks {
	my ($self, $rawquery, $extA, $numHitsR, $numFilesR, $fullPath) = @_;
	$fullPath = lc($fullPath);
	$fullPath =~ s!\\!/!g;
	my $result = '';
	my $e      = $self->{SEARCHER};
	my $rawResults;

	my $numHits  = 0;
	my $numFiles = 0;
	$numHits = GetDefinitionHits($self, $rawquery, $extA, $e, \$rawResults);

	if ($numHits)
		{
		my @rawFullPaths;
		GetHitFullPaths($rawResults, \@rawFullPaths, $fullPath, $self->{SHOWNHITS});
		my @otherRawFullPaths;

		for (my $i = 0 ; $i < @rawFullPaths ; ++$i)
			{
			my $fixedFullPath = lc(&HTML::Entities::encode($rawFullPaths[$i]));
			if ($fixedFullPath ne $fullPath)
				{
				push @otherRawFullPaths, $rawFullPaths[$i];
				}
			}

		my $numRemaining = @otherRawFullPaths;
		if ($numRemaining)
			{
			RememberPaths($self, \@otherRawFullPaths, $rawquery);
			#FormatFullPathsResults($rawquery, $self->{SHOWNHITS}, $self->{HOST}, $self->{PORT},
			#	$self->{VIEWERNAME}, \@otherRawFullPaths, \$result);
			}
		else
			{
			$result = '<p>nope</p>';
			}
		}
	else
		{
		$result = '<p>nope</p>';
		}

	$$numHitsR  = $numHits;
	$$numFilesR = $numFiles;

	return $result;
}

# If a definition search turns up nothing, maybe the term selected
# was in a different language. So try looking for JavaScript
# or CSS definitions etc, we might get lucky. Especially if
# the query is in a .txt file.
sub GetDefinitionLinksInOtherLanguages {
	my ($self, $rawquery, $extA, $numHitsR, $numFilesR) = @_;
	my $result = '';
	my $e      = $self->{SEARCHER};
	my @otherExtensions;
	my $numFound = 0;

	if ($extA->[0] ne "js")
		{
		push @otherExtensions, 'js';
		}
	if ($extA->[0] ne "css")
		{
		push @otherExtensions, 'css';
		}

	# Perl
	if ($extA->[0] ne "pl" && $extA->[0] ne "pm")
		{
		push @otherExtensions, 'pl';
		push @otherExtensions, 'pm';
		}

	# C/C++
	if ($extA->[0] ne "cpp" && $extA->[0] ne "c" && $extA->[0] ne "h")
		{
		push @otherExtensions, 'cpp';
		push @otherExtensions, 'h';
		push @otherExtensions, 'c';
		}

	# Python bzl,py,pyw
	if ($extA->[0] ne "bzl" && $extA->[0] ne "py" && $extA->[0] ne "pyw")
		{
		push @otherExtensions, 'bzl';
		push @otherExtensions, 'py';
		push @otherExtensions, 'pyw';
		}

	# Java
	if ($extA->[0] ne "bzl")
		{
		push @otherExtensions, 'java';
		}

	# C#
	if ($extA->[0] ne "cs")
		{
		push @otherExtensions, 'cs';
		}

	# Go
	if ($extA->[0] ne "go")
		{
		push @otherExtensions, 'go';
		}


	$result = GetCtagsResultsForExtensions($self, $rawquery, \@otherExtensions, $e, \$numFound, '');

	if ($numFound == 0)
		{
		$result = '<p>nope</p>';
		}

	return ($result);
}

# Called by intramine_linker.pl#Definitions() as a last resort,
# look for any file containing the $rawquery, return links if found.
sub GetAnyLinks {
	my ($self, $rawquery, $fullPath, $doDefinitions, $numDefinitionsAddedR) = @_;
	$$numDefinitionsAddedR = 0;
	$fullPath              = lc($fullPath);
	$fullPath =~ s!\\!/!g;

	# TEST ONLY, show message on the "Mon" page.
	my $chattyHere = 0;
	if ($rawquery =~ m!getanylinks!i)
		{
		#$chattyHere = 1;
		#my $hitsSoFar = NumHitsSoFar($self);
		#Monitor("GetAnyLinks top, hits so far |$hitsSoFar|\n");
		}

	my $e          = $self->{SEARCHER};
	my $rawResults = '';
	my $result     = '';

	# First try preferred extensions. If no hits, try ALL extensions.
	my $numHits = 0;
	if ($doDefinitions)
		{
		$numHits = GetDefinitionHits($self, $rawquery, \@PreferredExtensions, $e, \$rawResults);
		if ($numHits)
			{
			my @rawFullPaths;
			GetHitFullPaths($rawResults, \@rawFullPaths, $fullPath, $self->{SHOWNHITS});
			my @otherRawFullPaths;

			for (my $i = 0 ; $i < @rawFullPaths ; ++$i)
				{
				my $fixedFullPath = lc(&HTML::Entities::encode($rawFullPaths[$i]));
				if ($fixedFullPath ne $fullPath)
					{
					# if ($chattyHere)
					# 	{
					# 	Monitor("Pushing |$rawFullPaths[$i]| to \@otherRawFullPaths\n");
					# 	}
					push @otherRawFullPaths, $rawFullPaths[$i];
					}
				}

			my @winnowedFullPaths;
			my @notWinnowedFullPaths;
			my $numRemaining =
				WinnowFullPathsUsingCtags($rawquery, \@otherRawFullPaths, \@winnowedFullPaths,
				\@notWinnowedFullPaths);

			if ($numRemaining)
				{
				if ($chattyHere)
					{
					my $numdefs  = @winnowedFullPaths;
					my $numOther = @notWinnowedFullPaths;
					Monitor("Picked up $numdefs defs and $numOther nondefs.\n");
					}
				my $numBeforeAdding = NumHitsSoFar($self);
				RememberPaths($self, \@winnowedFullPaths, $rawquery);
				my $numAfterAdding = NumHitsSoFar($self);
				$$numDefinitionsAddedR += $numAfterAdding - $numBeforeAdding;
				RememberPaths($self, \@notWinnowedFullPaths, $rawquery);
				#FormatFullPathsResults($rawquery, $self->{SHOWNHITS}, $self->{HOST}, $self->{PORT},
				#	$self->{VIEWERNAME}, \@winnowedFullPaths, \$result);
				}
			else
				{
				my $notWinnowed = @notWinnowedFullPaths;
				if ($notWinnowed)
					{
					RememberPaths($self, \@otherRawFullPaths, $rawquery);
					}
				}
			}
		}

	if (!HitLimitReached($self))
		#if ($result eq '' || $result eq '<p>nope</p>')
		{
		if ($chattyHere)
			{
			Monitor("Last gasp, about to call GetAnyHits\n");
			}
		my $numHits = GetAnyHits($self, $rawquery, $e, \$rawResults);
		if ($numHits)
			{
			my @rawFullPaths;
			GetHitFullPaths($rawResults, \@rawFullPaths, $fullPath, $self->{SHOWNHITS});
			my @otherRawFullPaths;

			for (my $i = 0 ; $i < @rawFullPaths ; ++$i)
				{
				my $fixedFullPath = lc(&HTML::Entities::encode($rawFullPaths[$i]));
				if ($fixedFullPath ne $fullPath)
					{
					push @otherRawFullPaths, $rawFullPaths[$i];
					}
				}


			my @winnowedFullPaths;
			my @notWinnowedFullPaths;
			my $numRemaining =
				WinnowFullPathsUsingCtags($rawquery, \@otherRawFullPaths, \@winnowedFullPaths,
				\@notWinnowedFullPaths);

			if ($numRemaining)
				{
				if ($chattyHere)
					{
					my $numdefs  = @winnowedFullPaths;
					my $numOther = @notWinnowedFullPaths;
					Monitor("GetAnyHits picked up $numdefs defs and $numOther nondefs.\n");
					}
				my $numBeforeAdding = NumHitsSoFar($self);
				RememberPaths($self, \@winnowedFullPaths, $rawquery);
				my $numAfterAdding = NumHitsSoFar($self);
				$$numDefinitionsAddedR += $numAfterAdding - $numBeforeAdding;
				RememberPaths($self, \@notWinnowedFullPaths, $rawquery);
				#FormatFullPathsResults($rawquery, $self->{SHOWNHITS}, $self->{HOST}, $self->{PORT},
				#	$self->{VIEWERNAME}, \@winnowedFullPaths, \$result);
				}
			else
				{
				RememberPaths($self, \@otherRawFullPaths, $rawquery);
				#FormatFullPathsResults($rawquery, $self->{SHOWNHITS}, $self->{HOST}, $self->{PORT},
				#	$self->{VIEWERNAME}, \@otherRawFullPaths, \$result);
				}
			}
		else
			{
			$result = '<p>nope</p>';
			}
		}

	return ($result);
}

# Call Elasticsearch to match words in $query as an exact match.
# Extensions are limited by $extA.
# Return num hits.
sub GetDefinitionHits {
	my ($self, $query, $extA, $e, $rawResultsR) = @_;

	# Hack for stifled periods such as "jsonResult.arr": such non-English periods are
	# converted to ' __D_ ' when indexing, so do the same sub here when searching.
	# This also applies to file extensions, title 'gloss.txt' is indexed as 'gloss __D_ txt'.
	$query =~ s!(\w)\.(\w)!$1 __D_ $2!g;
	# Dollar signs are converted to '__DS_' for indexing, so sub that here for searching.
	# And similarly for '~' and '%' and '@'.
	$query =~ s!\$([A-Za-z])!__DS_$1!g;
	$query =~ s!\~([A-Za-z])!__L_$1!g;
	$query =~ s!\%([A-Za-z])!__PC_$1!g;
	$query =~ s!\@([A-Za-z])!__AT_$1!g;


	$$rawResultsR = $e->search(
		#			index => $self->{INDEX_NAME},
		index       => "_all",
		filter_path => [
			'hits.total',                   'hits.hits._score',
			'hits.hits._source.path',       'hits.hits._source.displaypath',
			'hits.hits._source.content',    'hits.hits._source.moddate',
			'hits.hits._source.size',       'hits.hits.highlight.content',
			'hits.hits._source.title',      'hits.hits.highlight.title',
			'hits.hits._source.full_title', 'hits.hits.highlight.full_title'
		],
		body => {

			query => {
				bool => {
					must => {
						multi_match => {
							type   => 'phrase',
							fields => ['content'],
							query  => $query
						}
					},
					filter => {
						terms => {
							ext => $extA
						}
					}
				}
			},

			size      => $self->{RAWHITS} * 5,
			highlight => {
				pre_tags  => ['<strong>'],
				post_tags => ['</strong>'],
				fields    => {
					content => {
						fragment_size       => 100,
						number_of_fragments => 1,
						no_match_size       => 150    #, force_source => 'true'
					}
				}
			}
		}
	);

	return ($$rawResultsR->{'hits'}{'total'}{'value'});
}

# Call Elasticsearch to match words in $query as an exact match.
# Like above but no restriction on extensions.
# This is the "last resort" search.
sub GetAnyHits {
	my ($self, $query, $e, $rawResultsR) = @_;

	# Hack for stifled periods such as "jsonResult.arr": such non-English periods are
	# converted to ' __D_ ' when indexing, so do the same sub here when searching.
	# This also applies to file extensions, title 'gloss.txt' is indexed as 'gloss __D_ txt'.
	$query =~ s!(\w)\.(\w)!$1 __D_ $2!g;
	# Dollar signs are converted to '__DS_' for indexing, so sub that here for searching.
	# And similarly for '~' and '%' and '@'.
	$query =~ s!\$([A-Za-z])!__DS_$1!g;
	$query =~ s!\~([A-Za-z])!__L_$1!g;
	$query =~ s!\%([A-Za-z])!__PC_$1!g;
	$query =~ s!\@([A-Za-z])!__AT_$1!g;

	$$rawResultsR = $e->search(
		#			index => $self->{INDEX_NAME},
		index       => "_all",
		filter_path => [
			'hits.total',                   'hits.hits._score',
			'hits.hits._source.path',       'hits.hits._source.displaypath',
			'hits.hits._source.content',    'hits.hits._source.moddate',
			'hits.hits._source.size',       'hits.hits.highlight.content',
			'hits.hits._source.title',      'hits.hits.highlight.title',
			'hits.hits._source.full_title', 'hits.hits.highlight.full_title'
		],
		body => {

			query => {
				bool => {
					must => {
						multi_match => {
							type   => 'phrase',
							fields => ['content'],
							query  => $query
						}
					}
				}
			},

			size      => $self->{RAWHITS} * 5,
			highlight => {
				pre_tags  => ['<strong>'],
				post_tags => ['</strong>'],
				fields    => {
					content => {
						fragment_size       => 400,
						number_of_fragments => 1,
						no_match_size       => 150    #, force_source => 'true'
					}
				}
			}
		}
	);

	return ($$rawResultsR->{'hits'}{'total'}{'value'});
}

# NOT CURRENTLY USED.
# FormatDefinitionResults($rawResults, $rawquery, $self->{SHOWNHITS}, $extA, \$result);
# Return HTML formatted search hit results.
sub FormatDefinitionResults {
	my ($rawResults, $query, $maxNumHits, $host, $port, $viewerName, $extA, $resultR) = @_;
	my %fullPathSeen;    # Avoid showing the same file twice.
	my $hitCounter = 0;

	my $numHits = $rawResults->{'hits'}{'total'}{'value'};

	if (defined($numHits) && $numHits > 0)
		{
		$$resultR = "";

		$query =~ s!^\S+\s+!!;    # Strip "sub " or whatnot
		my $definitionName = $query;
		$definitionName = '#' . $definitionName;

		for my $hit (@{$rawResults->{'hits'}->{'hits'}})
			{
			my $path = $hit->{'_source'}->{'displaypath'};

			my $displayedPath = $path;

			if ($path ne '')
				{
				if ($hitCounter < $maxNumHits)
					{
					$path = encode_utf8($path);
					$path =~ s!\\!/!g;
					my $lcpath = lc($path);

					if (!defined($fullPathSeen{$lcpath}))
						{
						++$hitCounter;
						$fullPathSeen{$lcpath} = 1;
						$displayedPath = encode_utf8($displayedPath . $definitionName);
						# Replace / with \ in path, some apps still want that.
						$displayedPath =~ s!/!\\!g;
						$displayedPath =~ m!([^\\]+)$!;

						$path =~ s!%!%25!g;
						$path =~ s!\+!\%2B!g;

						my $searchItems = '&searchItems=' . &HTML::Entities::encode($query);

						my $pathWithSearchItems = $path . $searchItems . $definitionName;

						my $anchor =
"<a href=\"http://$host:$port/$viewerName/?href=$pathWithSearchItems\" onclick=\"openView(this.href, '$viewerName'); return false;\"  target=\"_blank\">$displayedPath</a>";

						my $entry = "<p>$anchor</p>\n";

						$$resultR .= $entry;
						}    # if (!defined($fullPathSeen{$path}))
					}
				}    # if ($path ne '')
			}    # for my $hit (@{ $rawResults->{'hits'}->{'hits'} } )
		if ($$resultR eq '')
			{
			$$resultR = "<p>nope</p>";
			}
		else
			{
			$$resultR = '<div>' . $$resultR . "</div>\n";
			}
		}    # if (defined($numHits)...

	return ($hitCounter);
}

# Do a search for $rawquery. Call universal ctags to generate
# a list of defined terms for each found file, winnow to
# exclude those that don't have a definition in the ctags output.
# return links as per FormatDefinitionResults just above.
sub GetCtagsDefinitionLinks {
	my ($self, $rawquery, $extA, $fullPath) = @_;
	my $result        = '<p>nope</p>';
	my $numExtensions = @$extA;
	if (!$numExtensions)
		{
		return ($result);
		}
	my $e = $self->{SEARCHER};

	my $numFound = 0;

	# As a special case the language in question might have header
	# and implementation extensions. If so, search implementation
	# first and then headers only if fewer than max good hits.
	my $firstExtension = $extA->[0];
	my @headerExt;
	my @impExt;
	if (defined($LanguageForHeaderExt{$firstExtension}))
		{
		my $language = $LanguageForHeaderExt{$firstExtension};
		@headerExt = split(/,/, $HeaderExtForLanguage{$language});
		@impExt    = split(/,/, $ImpExtForLanguage{$language});
		#print("Imp: |@impExt|\n");
		$result =
			GetCtagsResultsForExtensions($self, $rawquery, \@impExt, $e, \$numFound, $fullPath);
		if ($result eq '' || $result eq '<p>nope</p>' || $numFound < $self->{SHOWNHITS})
			{
			if ($result eq '' || $result eq '<p>nope</p>')
				{
				$result = '';
				}
			my $headerResult =
				GetCtagsResultsForExtensions($self, $rawquery, \@headerExt, $e, \$numFound,
				$fullPath);
			if ($headerResult ne '' && $headerResult ne '<p>nope</p>')
				{
				$result .= $headerResult;
				}
			}
		}
	else
		{
		$result = GetCtagsResultsForExtensions($self, $rawquery, $extA, $e, \$numFound, $fullPath);
		}

	return ($result);
}

sub GetCtagsResultsForExtensions {
	my ($self, $rawquery, $extA, $e, $numFoundR, $fullPath) = @_;
	$fullPath = lc($fullPath);
	$fullPath =~ s!\\!/!g;
	my $rawResults   = '';
	my $result       = '';
	my $numHits      = GetDefinitionHits($self, $rawquery, $extA, $e, \$rawResults);
	my $numRemaining = 0;

	if ($numHits)
		{
		my @rawFullPaths;
		GetHitFullPaths($rawResults, \@rawFullPaths, $fullPath, $self->{SHOWNHITS});

		my @otherRawFullPaths;
		for (my $i = 0 ; $i < @rawFullPaths ; ++$i)
			{
			my $fixedFullPath = lc(&HTML::Entities::encode($rawFullPaths[$i]));
			if ($fixedFullPath ne $fullPath)
				{
				push @otherRawFullPaths, $rawFullPaths[$i];
				}
			}

		my @winnowedFullPaths;
		$numRemaining =
			WinnowFullPathsUsingCtags($rawquery, \@otherRawFullPaths, \@winnowedFullPaths, undef);

		if (!$numRemaining)
			{
			$numHits = 0;
			}
		else
			{
			RememberPaths($self, \@winnowedFullPaths, $rawquery);
			#FormatFullPathsResults($rawquery, $self->{SHOWNHITS}, $self->{HOST}, $self->{PORT},
			#	$self->{VIEWERNAME}, \@winnowedFullPaths, \$result);
			}
		}

	if (!$numHits)
		{
		$result = '<p>nope</p>';
		}

	$$numFoundR = $numRemaining;

	return ($result);
}

sub GetHitFullPaths {
	my ($rawResults, $rawFullPathsA, $fullPath, $shownHits) = @_;

	for my $hit (@{$rawResults->{'hits'}->{'hits'}})
		{
		my $path = $hit->{'_source'}->{'displaypath'};
		push @$rawFullPathsA, $path;
		}

	# Sort full paths by proximity to $fullPath (the file
	# where the query was selected). I'm leaving the code
	# in, but the sort is turned off at the moment,
	# I can't find a good use for it.
	my $sortByProxmity = 0;
	if ($sortByProxmity)
		{
		SortThePaths($rawFullPathsA, $fullPath, $shownHits);
		}
}

sub SortThePaths {
	my ($rawFullPathsA, $fullPath, $shownHits) = @_;
	my $lastSlashPos = rindex($fullPath, "/");
	if ($lastSlashPos <= 0)
		{
		return;
		}
	my $contextDir = substr($fullPath, 0, $lastSlashPos);
	my $numEntries = @$rawFullPathsA;
	if ($numEntries <= 1)
		{
		return;
		}

	# Make a lowercase properly backslashed version of the raw full paths.
	my @lcPaths;
	my $numToSort     = $numEntries;
	my $sortShownOnly = 1;
	if ($sortShownOnly && $numToSort > $shownHits)
		{
		$numToSort = $shownHits;
		}
	for (my $i = 0 ; $i < $numToSort ; ++$i)
		{
		my $path = lc($rawFullPathsA->[$i]);
		$path =~ s!\\!/!g;
		push @lcPaths, $path;
		}

	my @idx = sort {FolderComp($lcPaths[$b], $lcPaths[$a], $contextDir)} 0 .. $#lcPaths;
	for (my $i = 0 ; $i < $numToSort ; ++$i)
		{
		$rawFullPathsA->[$i] = $lcPaths[$idx[$i]];
		}

	#@{$rawFullPathsA} = @{$rawFullPathsA}[@idx]; # if doing all paths
}

sub FolderComp {
	my ($first, $second, $contextDir) = @_;
	my $aDistance = LeftOverlapLength($contextDir, $first);
	my $bDistance = LeftOverlapLength($contextDir, $second);
	my $compDist  = $aDistance - $bDistance;
	my $result    = 0;
	if ($compDist < 0)
		{
		$result = -1;
		}
	elsif ($compDist > 0)
		{
		$result = 1;
		}
	else    # Tie
		{
		$result = length($second) - length($first);
		if ($result < 0)
			{
			$result = -1;
			}
		elsif ($result > 0)
			{
			$result = 1;
			}
		else
			{
			$result = $second cmp $first;
			}
		}

	return ($result);
}

# sub LeftOverlapLength {
#     my ($str1, $str2) = @_;

#     # Equalize Lengths
#     if (length $str1 < length $str2) {
#         $str2 = substr $str2, 0, length($str1);
#     } elsif (length $str1 > length $str2) {
#         $str1 = substr $str1, 0, length($str2);
#     }
#     # Reduce on right until match found
#     while ($str1 ne $str2) {
#         chop $str1;
#         chop $str2;
#     	}
# 	}

sub WinnowFullPathsUsingCtags {
	my ($rawquery, $rawFullPathsA, $winnowedFullPathsA, $notWinnowedFullPathsA) = @_;
	my $numRemaining = 0;
	# Generate ctags summary file for each full path.
	my $numRawPaths = @$rawFullPathsA;
	for (my $i = 0 ; $i < $numRawPaths ; ++$i)
		{
		my $filePath = $rawFullPathsA->[$i];

		# Get ctags as a string.
		my $tagString = '';
		GetCtagsString($filePath, \$tagString);

		my @lines = split(/\n/, $tagString);

		my $numLines = @lines;
		my $gottaHit = 0;
		for (my $j = 0 ; $j < $numLines ; ++$j)
			{
			if (index($lines[$j], $rawquery) >= 0 && $lines[$j] =~ m!(^|\W)$rawquery(\W|$)!)
				{
				++$numRemaining;
				push @$winnowedFullPathsA, $filePath;
				$gottaHit = 1;
				last;
				}
			}
		if (!$gottaHit && defined($notWinnowedFullPathsA))
			{
			push @$notWinnowedFullPathsA, $filePath;
			}
		}

	return ($numRemaining);
}

sub NumHitsSoFar {
	my ($self) = @_;
	my $result = @{$self->{FULLPATHS}};

	return ($result);
}

sub HitLimitReached {
	my ($self) = @_;
	my $hits   = @{$self->{FULLPATHS}};
	my $result = 0;
	if ($hits >= $self->{SHOWNHITS})
		{
		$result = 1;
		}

	return ($result);
}

sub RememberPaths {
	my ($self, $pathsA, $query) = @_;
	my $numPaths   = @$pathsA;
	my $hitCounter = @{$self->{FULLPATHS}};

	if ($hitCounter >= $self->{SHOWNHITS})
		{
		return;
		}

	for (my $i = 0 ; $i < $numPaths ; ++$i)
		{
		if ($hitCounter >= $self->{SHOWNHITS})
			{
			last;
			}

		my $path   = $pathsA->[$i];
		my $lcpath = lc(encode_utf8($path));
		if (!defined($self->{PATHSEEN}{$lcpath}))
			{
			++$hitCounter;
			$self->{PATHSEEN}{$lcpath} = 1;
			push @{$self->{FULLPATHS}}, $pathsA->[$i];
			push @{$self->{PATHQUERY}}, $query;
			}
		}
}

# FormatFullPathsResults() formats hits as HTML, with best Elasticsearch score first.
sub FormatFullPathsResults {
	my ($self, $host, $port, $viewerName, $putDividerBefore, $resultR) = @_;
	my $numPaths = @{$self->{FULLPATHS}};
	if ($numPaths == 0)
		{
		return;
		}

	$$resultR = "<div>\n";

	# Experiment, put a background color on definitions.
	my $defColorClassName = "class='go2-def-instance'";

	my $hitCounter = 0;
	my $maxNumHits = $self->{SHOWNHITS};
	for (my $i = 0 ; $i < $numPaths ; ++$i)
		{
		if ($hitCounter >= $maxNumHits)
			{
			last;
			}


		my $path = $self->{FULLPATHS}->[$i];

		$path =~ s!%!%25!g;
		$path =~ s!\+!%2B!g;
		$path = &HTML::Entities::encode($path);

		my $query = $self->{PATHQUERY}->[$i];
		$query =~ s!%!%25!g;
		$query =~ s!^\s+!!;
		my $displayedPath  = $path . '#' . $query;
		my $definitionName = '#' . $query;
		# Replace / with \ in path, some apps still want that.
		$displayedPath =~ s!/!\\!g;
		$displayedPath =~ m!([^\\]+)$!;
		my $isCM = HasCMExtension($path);

		# search Items, encode_utf8 if NOT CodeMirror,
		# use &HTML::Entities::encode for CodeMirror.
		# I have no idea why this works:(
		my $searchItems;
		if ($isCM)
			{
			$searchItems = '&searchItems=' . &HTML::Entities::encode($query);
			}
		else
			{
			$searchItems = '&searchItems=' . encode_utf8($query);
			}

		my $pathWithSearchItems = $path . $searchItems . $definitionName;
		# Horrible hack, having space trouble:
		$pathWithSearchItems =~ s! !__IMSPC__!g;
		my $openViewFuncName = "openView";
		if ($isCM)
			{
			$openViewFuncName = "openView";
			#$openViewFuncName = "openViewEncode";
			}
		my $anchor =
"<a href=\"http://$host:$port/$viewerName/?href=$pathWithSearchItems\" onclick=\"$openViewFuncName(this.href, '$viewerName'); return false;\"  target=\"_blank\">$displayedPath</a>";

		# Add color to defining links.
		my $entry = '';
		if ($putDividerBefore > 0 && $putDividerBefore > $i)
			{
			# $defColorClassName
			$entry = "<p $defColorClassName>$anchor</p>\n";
			}
		else
			{
			$entry = "<p>$anchor</p>\n";
			}

		if ($i == $putDividerBefore)
			{
			$$resultR .= "<hr />\n";
			}

		$$resultR .= $entry;

		++$hitCounter;
		}

	if ($$resultR eq '')
		{
		$$resultR = "";
		}
	else
		{
		$$resultR .= "</div>\n";
		}

	$$resultR = encode_utf8($$resultR);
}

# sub FormatFullPathsResults {
# 	my ($rawquery, $maxNumHits, $host, $port, $viewerName, $winnowedFullPathsA, $resultR) = @_;

# 	# THIS SUB IS GOING AWAY.
# 	return;

# 	my %fullPathSeen;    # Avoid showing the same file twice.
# 	my $numPaths = @$winnowedFullPathsA;

# 	# Strip leading white from the query, it's never wanted.
# 	$rawquery =~ s!^\s+!!;
# 	my $originalRawquery = $rawquery;

# 	my $definitionName = $rawquery;
# 	$definitionName = '#' . $definitionName;
# 	my $hitCounter = 0;

# 	$$resultR = "<div>\n";
# 	for (my $i = 0 ; $i < $numPaths ; ++$i)
# 		{
# 		if ($hitCounter >= $maxNumHits)
# 			{
# 			last;
# 			}
# 		my $path          = $winnowedFullPathsA->[$i];
# 		my $displayedPath = $path;
# 		$path =~ s!\\!/!g;
# 		my $lcpath = lc(encode_utf8($path));
# 		if (!defined($fullPathSeen{$lcpath}))
# 			{
# 			++$hitCounter;
# 			$fullPathSeen{$lcpath} = 1;
# 			$displayedPath = $displayedPath . '#' . $originalRawquery;
# 			# Replace / with \ in path, some apps still want that.
# 			$displayedPath =~ s!/!\\!g;
# 			$displayedPath =~ m!([^\\]+)$!;

# 			# search Items, encode_utf8 if NOT CodeMirror,
# 			# use &HTML::Entities::encode for CodeMirror.
# 			# I have no idea why this works:(
# 			my $isCM = HasCMExtension($path);
# 			my $searchItems;
# 			if ($isCM)
# 				{
# 				$searchItems = '&searchItems=' . &HTML::Entities::encode($rawquery);
# 				}
# 			else
# 				{
# 				$searchItems = '&searchItems=' . encode_utf8($rawquery);
# 				}

# 			my $pathWithSearchItems = $path . $searchItems . $definitionName;
# 			# Horrible hack, having space trouble:
# 			$pathWithSearchItems =~ s! !__IMSPC__!g;

# 			my $openViewFuncName = "openView";
# 			if ($isCM)
# 				{
# 				$openViewFuncName = "openViewEncode";
# 				}
# 			my $anchor =
# "<a href=\"http://$host:$port/$viewerName/?href=$pathWithSearchItems\" onclick=\"$openViewFuncName(this.href, '$viewerName'); return false;\"  target=\"_blank\">$displayedPath</a>";

# 			my $entry = "<p>$anchor</p>\n";

# 			$$resultR .= $entry;
# 			}
# 		}

# 	if ($$resultR eq '')
# 		{
# 		$$resultR = "";
# 		}
# 	else
# 		{
# 		$$resultR .= "</div>\n";
# 		}

# 	$$resultR = encode_utf8($$resultR);
# }

# Requires $filePath lowercase
sub HasCMExtension {
	my ($filePath) = @_;
	my $isCM = 1;
	if (   $filePath =~ m!\.pod$!i
		|| $filePath =~ m!\.(txt|log|bat)$!i
		|| $filePath =~ m!\.md$!i)
		{
		$isCM = 0;
		}
	return ($isCM);
}

sub DefKeyForPath {
	my ($fullPath) = @_;
	my $result = '';
	if ($fullPath =~ m!\.(\w+)$!)
		{
		my $ext = lc($1);
		$result =
			(defined($DefinitionKeyForExtension{$ext})) ? $DefinitionKeyForExtension{$ext} : '';
		}

	return ($result);
}

sub HasCtagsSupport {
	my ($self, $fullPath) = @_;
	return (IsSupportedByExuberantCTags($fullPath));    # now universal ctags
}

1;
