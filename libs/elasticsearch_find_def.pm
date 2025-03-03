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
# See also intramine_linker.pl#Definitions().

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

use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
#use lib ".";
use common;
use toc_local;
use ext;

# Some languages introduce a funtions with a keyword.
# The keyword is prepended to the Elasticsearch query
# to narrow down found files to those containing definitions.
# (For other languages, no keyword is added.)
my %DefinitionKeyForExtension;
# Perl: pl,pm,cgi,t,not pod
$DefinitionKeyForExtension{'pl'} = 'sub';
$DefinitionKeyForExtension{'pm'} = 'sub';
$DefinitionKeyForExtension{'cgi'} = 'sub';
$DefinitionKeyForExtension{'t'} = 'sub';
# JavaScript: just js
$DefinitionKeyForExtension{'js'} = 'function';
# Go: just go
$DefinitionKeyForExtension{'go'} = 'func';
# Fortran: $extensionsForLanguage{'Fortran'} = 'f,for,f77,f90,f95, f03';
$DefinitionKeyForExtension{'f'} = 'function|subroutine';
$DefinitionKeyForExtension{'for'} = 'function|subroutine';
$DefinitionKeyForExtension{'f77'} = 'function|subroutine';
$DefinitionKeyForExtension{'f90'} = 'function|subroutine';
$DefinitionKeyForExtension{'f95'} = 'function|subroutine';
$DefinitionKeyForExtension{'f03'} = 'function|subroutine';
# Basic: vb, vbs
$DefinitionKeyForExtension{'vb'} = 'sub|function';
$DefinitionKeyForExtension{'vbs'} = 'sub|function';
# Python: BUILD,bzl,py,pyw
$DefinitionKeyForExtension{'BUILD'} = 'def';
$DefinitionKeyForExtension{'bzl'} = 'def';
$DefinitionKeyForExtension{'py'} = 'def';
$DefinitionKeyForExtension{'pyw'} = 'def';

# Some languages such as C / C++ have header and implementation extensions.
# Search implementation first, then headers if nothing found.
# Actually C and C++ are the only ones I could find.
my %HeaderExtForLanguage;
my %ImpExtForLanguage;
$HeaderExtForLanguage{'C/C++'} = 'hpp,h,hh,hxx';
$ImpExtForLanguage{'C/C++'} = 'cpp,cc,c,cxx';
my %LanguageForHeaderExt;
$LanguageForHeaderExt{'hpp'} = 'C/C++';
$LanguageForHeaderExt{'h'} = 'C/C++';
$LanguageForHeaderExt{'hh'} = 'C/C++';
$LanguageForHeaderExt{'hxx'} = 'C/C++';
$LanguageForHeaderExt{'cpp'} = 'C/C++';
$LanguageForHeaderExt{'cc'} = 'C/C++';
$LanguageForHeaderExt{'c'} = 'C/C++';
$LanguageForHeaderExt{'cxx'} = 'C/C++';

my @PreferredExtensions;

# Make a new elasticsearch_find_def instance,
# init universal ctags.
sub new {
	my ($proto, $indexName, $numHits, $maxShownHits, $host, $port_listen, $VIEWERNAME, $LogDir, $ctags_dir, $HashHeadingRequireBlankBefore, $preferredExtensionsA) = @_;
	my $class = ref($proto) || $proto;
	my $self  = {};
	
	$self->{INDEX_NAME} = $indexName;
	$self->{RAWHITS} = $numHits; 			# Over 100 can slow the search down.
	$self->{SHOWNHITS} = $maxShownHits;
	$self->{HOST} = $host;
	$self->{PORT} = $port_listen;
	$self->{VIEWERNAME} = $VIEWERNAME;

	@PreferredExtensions = @$preferredExtensionsA;
	
# Sniffing is not currently supported (Dec 2018)
	my $e = Search::Elasticsearch->new(
			nodes    => 'localhost:9200'
#			nodes    => '192.168.1.132:9200'
#			,cxn_pool => 'Sniff'
		); 
    $self->{SEARCHER} = $e;

	InitTocLocal($LogDir . 'temp/tempctags', $port_listen, $LogDir, $ctags_dir, $HashHeadingRequireBlankBefore);
	
	bless ($self, $class);
	return $self;
    }

# GetDefinitionLinks(): call Elasticsearch to retrieve documents matching $rawquery.
# Match words supplied as a phrase.
# Only content is searched, a file name mention becomes a FLASH link in IntraMine.
# No restriction on folder, sometimes restrictions on extensions.
# FormatDefinitionResults() formats hits as HTML, with best Elasticsearch score first.
sub GetDefinitionLinks {
	my ($self, $rawquery, $extA, $numHitsR, $numFilesR) = @_;
	my $result = '';
	my $e = $self->{SEARCHER};
	my $rawResults;
	
	my $numHits = 0;
	my $numFiles = 0;
	# TEST ONLY
	#print("Calling GetDefinitionHits for |$rawquery|\n");
	$numHits = GetDefinitionHits($self, $rawquery, $extA, $e, \$rawResults);
	if ($numHits)
		{
		$numFiles = FormatDefinitionResults($rawResults, $rawquery, $self->{SHOWNHITS}, $self->{HOST}, $self->{PORT}, $self->{VIEWERNAME}, $extA, \$result);
		}
	else
		{
		$result = '<p>nope</p>';
		}
	
	$$numHitsR = $numHits;
	$$numFilesR = $numFiles;
	
	return $result;
	}

# If a definition search turns up nothing, maybe the term selected
# was in a different language. So try looking for JavaScript
# or CSS definitions, we might get lucky.
sub GetDefinitionLinksInOtherLanguages {
	my ($self, $rawquery, $extA, $numHitsR, $numFilesR) = @_;
	my $result = '';
	my $e = $self->{SEARCHER};
	my $rawResults;
	#my $numHits = 0;
	#my $numFiles = 0;
	my $numFound = 0;

	if ($extA->[0] ne "js")
		{
		my @jsExtension;
		push @jsExtension, 'js';
		$result = GetCtagsResultsForExtensions($self, $rawquery, \@jsExtension, $e, \$numFound);
		}
	if ($numFound == 0 && $extA->[0] ne "css")
		{
		my @cssExtension;
		push @cssExtension, 'css';
		$result = GetCtagsResultsForExtensions($self, $rawquery, \@cssExtension, $e, \$numFound);
		}

	if ($numFound == 0)
		{
		$result = '<p>nope</p>';
		}
	
	return($result);
	}

# Called by intramine_linker.pl#Definitions() as a last resort,
# look for any file containing the $rawquery, return links if found.
sub GetAnyLinks {
	my ($self, $rawquery, $fullPath) = @_;
	$fullPath = lc($fullPath);
	$fullPath =~ s!\\!/!g;

	my $e = $self->{SEARCHER};
	my $rawResults = '';
	my $result = '';

	# First try preferred extensions. If no hits, try ALL extensions.
	my $numHits = GetDefinitionHits($self, $rawquery, \@PreferredExtensions, $e, \$rawResults);
	if ($numHits)
		{
		my @rawFullPaths;
		GetHitFullPaths($rawResults, \@rawFullPaths);
		my @otherRawFullPaths;
		for (my $i = 0; $i < @rawFullPaths; ++$i)
			{
			if (lc($rawFullPaths[$i]) ne $fullPath)
				{
				push @otherRawFullPaths, $rawFullPaths[$i];
				}
			}

		my @winnowedFullPaths;
		my $numRemaining = WinnowFullPathsUsingCtags($rawquery, \@otherRawFullPaths, \@winnowedFullPaths);
		
		if ($numRemaining)
			{
			FormatFullPathsResults($rawquery,  $self->{SHOWNHITS}, $self->{HOST}, $self->{PORT}, $self->{VIEWERNAME}, \@winnowedFullPaths, \$result);
			}
		else
			{
			$result = '<p>nope</p>';
			}
		}

	if ($result eq '' || $result eq '<p>nope</p>')
		{
		my $numHits = GetAnyHits($self, $rawquery, $e, \$rawResults);
		if ($numHits)
			{
			my @rawFullPaths;
			GetHitFullPaths($rawResults, \@rawFullPaths);
			my @otherRawFullPaths;

			for (my $i = 0; $i < @rawFullPaths; ++$i)
				{
				if (lc($rawFullPaths[$i]) ne $fullPath)
					{
					push @otherRawFullPaths, $rawFullPaths[$i];
					}
				}

			my @winnowedFullPaths;
			my $numRemaining = WinnowFullPathsUsingCtags($rawquery, \@otherRawFullPaths, \@winnowedFullPaths);
			
			if ($numRemaining)
				{
				FormatFullPathsResults($rawquery,  $self->{SHOWNHITS}, $self->{HOST}, $self->{PORT}, $self->{VIEWERNAME}, \@winnowedFullPaths, \$result);
				}
			else
				{
				FormatFullPathsResults($rawquery,  $self->{SHOWNHITS}, $self->{HOST}, $self->{PORT}, $self->{VIEWERNAME}, \@otherRawFullPaths, \$result);
				}
			}
		else
			{
			$result = '<p>nope</p>';
			}
		}

	return($result);
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
				index => "_all",
				filter_path => [ 'hits.total', 'hits.hits._score', 'hits.hits._source.path',
								  'hits.hits._source.displaypath', 'hits.hits._source.content',
								  'hits.hits._source.moddate', 'hits.hits._source.size',
								  'hits.hits.highlight.content', 'hits.hits._source.title', 'hits.hits.highlight.title',
								  'hits.hits._source.full_title', 'hits.hits.highlight.full_title' ],
		        body  => {
		        	
		        	query => {
		        		bool => {
		        			must => {
		        				multi_match => {
		        					type => 'phrase',
		        					fields => ['content'],
		        					query => $query
		        				}
		        			},
			        		filter => {
			        			terms => {
			        				ext => $extA
			        			}
			        		}
		        		}
		        	},
		        	
		            size => $self->{RAWHITS} * 5,
					highlight => {
						pre_tags => ['<strong>'],
						post_tags => ['</strong>'],
						fields => {
							content => {
								fragment_size => 100, number_of_fragments => 1, no_match_size => 150#, force_source => 'true'
							}
						}
					}
		        }
			);

	return($$rawResultsR->{'hits'}{'total'}{'value'});
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
				index => "_all",
				filter_path => [ 'hits.total', 'hits.hits._score', 'hits.hits._source.path', 
								  'hits.hits._source.displaypath', 'hits.hits._source.content',
								  'hits.hits._source.moddate', 'hits.hits._source.size',
								  'hits.hits.highlight.content', 'hits.hits._source.title', 'hits.hits.highlight.title',
								  'hits.hits._source.full_title', 'hits.hits.highlight.full_title' ],
		        body  => {
		        	
		        	query => {
		        		bool => {
		        			must => {
		        				multi_match => {
		        					type => 'phrase',
		        					fields => ['content'],
		        					query => $query
		        				}
		        			}
		        		}
		        	},
		        	
		            size => $self->{RAWHITS} * 5,
					highlight => {
						pre_tags => ['<strong>'],
						post_tags => ['</strong>'],
						fields => {
							content => {
								fragment_size => 400, number_of_fragments => 1, no_match_size => 150#, force_source => 'true'
							}
						}
					}
		        }
			);

	return($$rawResultsR->{'hits'}{'total'}{'value'});
	}
# FormatDefinitionResults($rawResults, $rawquery, $self->{SHOWNHITS}, $extA, \$result);
# Return HTML formatted search hit results.
sub FormatDefinitionResults {
	my ($rawResults, $query, $maxNumHits, $host, $port, $viewerName, $extA, $resultR) = @_;
	my %fullPathSeen; # Avoid showing the same file twice.
	my $hitCounter = 0;

	my $numHits = $rawResults->{'hits'}{'total'}{'value'};

	if (defined($numHits) && $numHits > 0)
		{
		$$resultR = "";

		$query =~ s!^\S+\s+!!; # Strip "sub " or whatnot
		my $definitionName = $query;
		$definitionName = '#' . $definitionName;
		
		for my $hit (@{ $rawResults->{'hits'}->{'hits'} } )
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

						my $anchor = "<a href=\"http://$host:$port/$viewerName/?href=$pathWithSearchItems\" onclick=\"openView(this.href, '$viewerName'); return false;\"  target=\"_blank\">$displayedPath</a>";

						my $entry = "<p>$anchor</p>\n";

						$$resultR .= $entry;
						} # if (!defined($fullPathSeen{$path}))
					}
				} # if ($path ne '')
			} # for my $hit (@{ $rawResults->{'hits'}->{'hits'} } )
		if ($$resultR eq '')
			{
			$$resultR = "<p>nope</p>";
			}
		else
			{
			$$resultR = '<div>' . $$resultR . "</div>\n";
			}
		} # if (defined($numHits)...
		
	return($hitCounter);
	}

# Do a search for $rawquery. Call universal ctags to generate
# a list of defined terms for each found file, winnow to
# exclude those that don't have a definition in the ctags output.
# return links as per FormatDefinitionResults just above.
sub GetCtagsDefinitionLinks {
	my ($self, $rawquery, $extA) = @_;
	my $result = '<p>nope</p>';
	my $numExtensions = @$extA;
	if (!$numExtensions)
		{
		return($result);
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
		@impExt = split(/,/, $ImpExtForLanguage{$language});
		#print("Imp: |@impExt|\n");
		$result = GetCtagsResultsForExtensions($self, $rawquery, \@impExt, $e, \$numFound);
		if ($result eq '' || $result eq '<p>nope</p>' || $numFound < $self->{SHOWNHITS})
			{
			if ($result eq '' || $result eq '<p>nope</p>')
				{
				$result = '';
				}
			my $headerResult = GetCtagsResultsForExtensions($self, $rawquery, \@headerExt, $e, \$numFound);
			if ($headerResult ne '' && $headerResult ne '<p>nope</p>')
				{
				$result .= $headerResult;
				}
			}
		}
	else
		{
		$result = GetCtagsResultsForExtensions($self, $rawquery, $extA, $e, \$numFound);
		}

	return($result);
	}

sub GetCtagsResultsForExtensions {
	my ($self, $rawquery, $extA, $e, $numFoundR) = @_;
	my $rawResults = '';
	my $result = '';
	my $numHits = GetDefinitionHits($self, $rawquery, $extA, $e, \$rawResults);
	my $numRemaining = 0;

	if ($numHits)
		{
		my @rawFullPaths;
		GetHitFullPaths($rawResults, \@rawFullPaths);

		my @winnowedFullPaths;
		$numRemaining = WinnowFullPathsUsingCtags($rawquery, \@rawFullPaths, \@winnowedFullPaths);

		if (!$numRemaining)
			{
			$numHits = 0;
			}
		else
			{
			FormatFullPathsResults($rawquery,  $self->{SHOWNHITS}, $self->{HOST}, $self->{PORT}, $self->{VIEWERNAME}, \@winnowedFullPaths, \$result);
			}
		}
	
	if (!$numHits)
		{
		$result = '<p>nope</p>';
		}

	$$numFoundR = $numRemaining;

	return($result);
	}

sub GetHitFullPaths {
	my ($rawResults, $rawFullPathsA) = @_;

	for my $hit (@{ $rawResults->{'hits'}->{'hits'} } )
		{
		my $path = $hit->{'_source'}->{'displaypath'};
		push @$rawFullPathsA, $path;
		}
	}

sub WinnowFullPathsUsingCtags {
	my ($rawquery, $rawFullPathsA, $winnowedFullPathsA) = @_;
	my $numRemaining = 0;
	# Generate ctags summary file for each full path.
	my $numRawPaths = @$rawFullPathsA;
	for (my $i = 0; $i < $numRawPaths; ++$i)
		{
		my $filePath = $rawFullPathsA->[$i];
		my $dir = lc(DirectoryFromPathTS($filePath));
		my $fileName = FileNameFromPath($filePath);
		my $errorMsg = '';
		my ($ctagsFilePath, $tempFilePath) = MakeCtagsForFile($dir, $fileName, \$errorMsg);
		# Check summary file for wanted term.
		if ($ctagsFilePath eq '' || length($errorMsg) > 0)
			{
			next;
			}
		my $octets = ReadTextFileDecodedWide($ctagsFilePath, 1);
		if (!defined($octets))
			{
			next;
			}
		my @lines = split(/\n/, $octets);
		my $numLines = @lines;
		for (my $j = 0; $j < $numLines; ++$j)
			{
			if (index($lines[$j], $rawquery) >= 0 && $lines[$j] =~ m!(^|\W)$rawquery(\W|$)!)
				{
				++$numRemaining;
				push @$winnowedFullPathsA, $filePath;
				last;
				}
			}

		# Get rid of the one or two temp files made while getting ctags.
		unlink($ctagsFilePath);
		if ($tempFilePath ne '')
			{
			unlink($tempFilePath);
			}
		}

	return($numRemaining);
	}

sub FormatFullPathsResults {
	my ($rawquery, $maxNumHits, $host, $port, $viewerName, $winnowedFullPathsA, $resultR) = @_;
	my %fullPathSeen; # Avoid showing the same file twice.
	my $numPaths  = @$winnowedFullPathsA;
	my $definitionName = $rawquery;
	$definitionName = '#' . $definitionName;
	my $hitCounter = 0;

	$$resultR = "<div>\n";
	for (my $i = 0; $i < $numPaths; ++$i)
		{
		if ($hitCounter >= $maxNumHits)
			{
			last;
			}
		my $path = $winnowedFullPathsA->[$i];
		my $displayedPath = $path;
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
			
			my $pathWithDefinition = $path . $definitionName;

			my $searchItems = '&searchItems=' . &HTML::Entities::encode($rawquery);

			my $pathWithSearchItems = $path . $searchItems . $definitionName;

			my $anchor = "<a href=\"http://$host:$port/$viewerName/?href=$pathWithSearchItems\" onclick=\"openView(this.href, '$viewerName'); return false;\"  target=\"_blank\">$displayedPath</a>";

			my $entry = "<p>$anchor</p>\n";

			$$resultR .= $entry;
			}
		}

	if ($$resultR eq '')
		{
		$$resultR = "";
		}
	else
		{
		$$resultR .= "</div>\n";
		}
	}

sub DefKeyForPath {
	my ($self, $fullPath) = @_;
	my $result = '';
	if ($fullPath =~ m!\.(\w+)$!)
		{
		my $ext = lc($1);
		$result = (defined($DefinitionKeyForExtension{$ext})) ? $DefinitionKeyForExtension{$ext}: '';
		}

	return($result);
	}

sub HasCtagsSupport {
	my ($self, $fullPath) = @_;
	return(IsSupportedByExuberantCTags($fullPath)); # now universal ctags
}

1;
