# elasticsearcher.pm: full text search using Elasticsearch.
# Used in intramine_search.pl.
# (For initial index building see elasticsearch_init_index.pl and elastic_indexer.pl).

package elasticsearcher;

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

sub new { # make a new elasticsearcher instance
	my ($proto, $indexName, $FULL_ACCESS_STR, $numHits) = @_;
	my $class = ref($proto) || $proto;
	my $self  = {};
	
	$self->{INDEX_NAME} = $indexName;
	$self->{FULL_ACCESS_STR} = $FULL_ACCESS_STR;	# Not used
	$self->{RAWHITS} = $numHits; 					# Over 100 can slow the search down.
	
# Sniffing is not currently supported (Dec 2018)
	my $e = Search::Elasticsearch->new(
			nodes    => 'localhost:9200'
#			nodes    => '192.168.1.132:9200'
#			,cxn_pool => 'Sniff'
		); 
    $self->{SEARCHER} = $e;
		
	bless ($self, $class);
	return $self;
    }


# GetSearchResults(): call Elasticsearch to retrieve documents matching $rawquery.
# GetWordHits() use Elasticsearch to retrieve documents where all words in the query are found.
# GetPhraseHits() match words supplied as a phrase.
# Both content and title of documents are searched.
# Searches can be restricted by folder and extension.
# FormatHitResults() formats hits as HTML, with best Elasticsearch score first. Some context
# is provided for the hits, and there are links on the document titles.
sub GetSearchResults {
	my ($self, $rawquery, $remote, $alllowEditing, $useAppForEditing, $extA, 
		$allExtensionsSelected, $folderSearchFilterName, $dir, $numHitsR, $numFilesR) = @_;
	my $result = '';
	my $e = $self->{SEARCHER};
	my $rawResults;
	my $matchExactPhrase = 0;

	# TEST ONLY
	# my $info = $e->info();
	# my $vnumber = $info->{version}->{number};
	# print("$vnumber\n");
	
	# For colons add quotes to force phrase match if there aren't any yet.
	if (index($rawquery, ':') > 0)
		{
		if ($rawquery !~ m!^['"]!)
			{
			$rawquery = '"' . $rawquery . '"';
			}
		}
	# likewise force exact match if phrase looks like "this.that". No spaces please.
	elsif (index($rawquery, '.') > 0 && index($rawquery, ' ') < 0)
		{
		if ($rawquery !~ m!^['"]!)
			{
			$rawquery = '"' . $rawquery . '"';
			}
		}
	
	# Trim query, strip quotes if present.
	my $query = $rawquery;
	$query =~ s!^ +!!;
	$query =~ s! +$!!;
	if ($query =~ m!^['"]!)
		{
		$query =~ s!^['"]+!!;
		$query =~ s!['"]+$!!;
		$matchExactPhrase = 1;
		}
	
	my $titleField = 'title';
	if ($query =~ m!\.(\w+)$!)
		{
		$titleField = 'title^2'; # ^2 boosts score x 2.
		}
	
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
	
	# That leaves non-breaking spaces, tabs, and CRLFs to deal with. Note tab and CRLF can't
	# be entered in the original search query.
	# Allow searching for non-breaking space.
	$query =~ s! *\&nbsp; *! __S_ !g;
	# DO NOT allow searching for CRLF.
	$query =~ s!__P_!!gi;
	# Tabs: only if there's more text in the search string, at least three consecutive letters.
	if ($query =~ m!__T_!i && $query !~ m![A-Aa-z][A-Aa-z][A-Aa-z]!)
		{
		$query =~ s!__T_!!gi;
		}
		
	my $numHits = 0;
	my $numFiles = 0;
	if ($matchExactPhrase)
		{
		$numHits = GetPhraseHits($self, $query, $extA, $allExtensionsSelected,
								 $folderSearchFilterName, $dir, $e, $titleField, \$rawResults);
		#$numHits = $numHitsH->{'value'}; # for Elasticearch 7 up
		if ($numHits)
			{
			$numFiles = FormatHitResults($rawResults, $query, $self->{RAWHITS}, $remote, $alllowEditing,
							 $useAppForEditing, $matchExactPhrase, $extA, \$result);
			}
		} # quoted, exact phrase
	else 	# not quoted, words in any order in one document
		{
		$numHits = GetWordHits($self, $query, $extA, $allExtensionsSelected,
							   $folderSearchFilterName, $dir, $e, $titleField, \$rawResults);
		#$numHits = $numHitsH->{'value'}; # for Elasticearch 7 up
		if ($numHits)
			{
			$numFiles = FormatHitResults($rawResults, $query, $self->{RAWHITS}, $remote, $alllowEditing,
							 $useAppForEditing, $matchExactPhrase, $extA, \$result);
			}
		} 	# not quoted, words in any order in one document
	
	if (!$numHits)
		{
		$result = '<p>No results found.</p>';
		}
	
	$$numHitsR = $numHits;
	$$numFilesR = $numFiles;
	
	return $result;
	}

# Use Elasticsearch to retrieve documents where all words in the query are found.
# Return num hits.
# Four cases, depending on $allExtensionsSelected T/F, $dir eq 'ALL' T/F.
# 1. $allExtensionsSelected && $dir eq 'ALL': no filter needed.
# 2. !$allExtensionsSelected && $dir eq 'ALL': filter on ext
# 3. $allExtensionsSelected && $dir ne 'ALL': filter on $folderSearchFilterName => $dir (as array)
# 4. !$allExtensionsSelected && $dir ne 'ALL': filter on $folderSearchFilterName for list of
#     $dir plus extension, for all extensions in $extA.
sub GetWordHits {
	my ($self, $query, $extA, $allExtensionsSelected, $folderSearchFilterName, $dir, $e,
		$titleField, $rawResultsR) = @_;
	
	# 1. $allExtensionsSelected && $dir eq 'ALL': no filter needed.
	if ($allExtensionsSelected && $dir eq 'ALL')
		{
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
		        					operator => 'and',
		        					fields => ['content', $titleField],
		        					query => $query
		        				}
		        			}
		        		}
		        	},
		        	
		            size => $self->{RAWHITS} * 20,
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
		}
	# 2. !$allExtensionsSelected && $dir eq 'ALL': filter on ext
	elsif (!$allExtensionsSelected && $dir eq 'ALL')
		{
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
		        					operator => 'and',
		        					fields => ['content', $titleField],
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
		        	
		            size => $self->{RAWHITS} * 20,
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
		}
	# 3. $allExtensionsSelected && $dir ne 'ALL': filter on $folderSearchFilterName => $dir (as array)
	elsif ($allExtensionsSelected && $dir ne 'ALL')
		{
		my @dirs;
		push @dirs, $dir;
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
		        					operator => 'and',
		        					fields => ['content', $titleField],
		        					query => $query
		        				}
		        			},
			        		filter => {
			        			terms => {
			        				$folderSearchFilterName => \@dirs
			        			}
			        		}
		        		}
		        	},
		        	
		            size => $self->{RAWHITS} * 20,
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
		}
	# 4. !$allExtensionsSelected && $dir ne 'ALL': filter on $folderSearchFilterName for list of
	#     $dir plus extension, for all extensions in $extA.
	else
		{
		my @dirs;
		for (my $i = 0; $i < @$extA; ++$i)
			{
			push @dirs, $dir . $extA->[$i];
			}
		
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
		        					operator => 'and',
		        					fields => ['content', $titleField],
		        					query => $query
		        				}
		        			},
			        		filter => {
			        			terms => {
			        				$folderSearchFilterName => \@dirs
			        			}
			        		}
		        		}
		        	},
		        	
		            size => $self->{RAWHITS} * 20,
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
		}
		
	return($$rawResultsR->{'hits'}{'total'}{'value'});
	}

# Match words supplied as a phrase, in order.
# Return num hits.
# As for GetWordHits above, four cases, depending on $allExtensionsSelected T/F, $dir eq 'ALL' T/F.
# 1. $allExtensionsSelected && $dir eq 'ALL': no filter needed.
# 2. !$allExtensionsSelected && $dir eq 'ALL': filter on ext
# 3. $allExtensionsSelected && $dir ne 'ALL': filter on $folderSearchFilterName => $dir (as array)
# 4. !$allExtensionsSelected && $dir ne 'ALL': filter on $folderSearchFilterName for list of
#     $dir plus extension, for all extensions in $extA.
# For matching phrases in more than one field at once, eg ['content', $titleField], see
# https://stackoverflow.com/questions/30020178/executing-a-multi-match-phrase-query-in-elastic-search
sub GetPhraseHits {
	my ($self, $query, $extA, $allExtensionsSelected, $folderSearchFilterName, $dir, $e,
		$titleField, $rawResultsR) = @_;
	
	# 1. $allExtensionsSelected && $dir eq 'ALL': no filter needed.
	if ($allExtensionsSelected && $dir eq 'ALL')
		{
		$$rawResultsR = $e->search(
	#			index => $self->{INDEX_NAME},
				index => "_all",
				filter_path => [ 'hits.total', 'hits.hits._score', 'hits.hits._source.path',
								  'hits.hits._source.displaypath', 'hits.hits._source.content',
								  'hits.hits._source.moddate', 'hits.hits._source.size', 'hits.hits._source.np_full_title',
								  'hits.hits.highlight.content', 'hits.hits._source.title', 'hits.hits.highlight.title',
								  'hits.hits._source.full_title', 'hits.hits.highlight.full_title' ],
		        body  => {
		        	
		        	query => {
		        		bool => {
		        			must => {
		        				multi_match => {
		        					type => 'phrase',
		        					fields => ['content', $titleField],
		        					query => $query
		        				}
		        			}
		        		}
		        	},
		        	
		            size => $self->{RAWHITS} * 20,
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
		}
	# 2. !$allExtensionsSelected && $dir eq 'ALL': filter on ext
	elsif (!$allExtensionsSelected && $dir eq 'ALL')
		{
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
		        					fields => ['content', $titleField],
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
		        	
		            size => $self->{RAWHITS} * 20,
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
		}
	# 3. $allExtensionsSelected && $dir ne 'ALL': filter on $folderSearchFilterName => $dir (as array)
	elsif ($allExtensionsSelected && $dir ne 'ALL')
		{
		my @dirs;
		push @dirs, $dir;
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
		        					fields => ['content', $titleField],
		        					query => $query
		        				}
		        			},
			        		filter => {
			        			terms => {
			        				$folderSearchFilterName => \@dirs
			        			}
			        		}
		        		}
		        	},
		        	
		            size => $self->{RAWHITS} * 20,
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
		}
	# 4. !$allExtensionsSelected && $dir ne 'ALL': filter on $folderSearchFilterName for list of
	#     $dir plus extension, for all extensions in $extA.
	else
		{
		my @dirs;
		for (my $i = 0; $i < @$extA; ++$i)
			{
			push @dirs, $dir . $extA->[$i];
			}
		
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
		        					fields => ['content', $titleField],
		        					query => $query
		        				}
		        			},
			        		filter => {
			        			terms => {
			        				$folderSearchFilterName => \@dirs
			        			}
			        		}
		        		}
		        	},
		        	
		            size => $self->{RAWHITS} * 20,
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
		}

	return($$rawResultsR->{'hits'}{'total'}{'value'});
	}

# Return HTML table rows holding formatted search hit results.
sub FormatHitResults {
	my ($rawResults, $query, $maxNumHits, $remote, $alllowEditing, $useAppForEditing, $matchExactPhrase, $extA, $resultR) = @_;
	my %fullPathSeen; # Avoid showing the same file twice.
	my $hitCounter = 0;

	my $numHits = $rawResults->{'hits'}{'total'}{'value'};
	
	if (defined($numHits) && $numHits > 0)
		{
		my $quoteChar = ($matchExactPhrase) ? '"': '';
		# With a RESTful approach (abandoned for now):
		#my $searchItems = '/?searchItems=' . &HTML::Entities::encode($quoteChar . $query . $quoteChar);
		# With the non-RESTful "href=path&searchItems=..." approach:
		my $searchItems = '&searchItems=' . &HTML::Entities::encode($quoteChar . $query . $quoteChar);
		$$resultR = "<table id='elasticSearchResultsTable'>\n";
		
		for my $hit (@{ $rawResults->{'hits'}->{'hits'} } )
			{
			my $score = sprintf( "%0.3f", $hit->{'_score'} );
			my $mtime = $hit->{'_source'}->{'moddate'};
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
						$displayedPath = encode_utf8($displayedPath);
						# Replace / with \ in path, some apps still want that.
						$displayedPath =~ s!/!\\!g;
						$displayedPath =~ m!([^\\]+)$!;
						my $title = $1;

						my $excerptArr = $hit->{'highlight'}->{'content'}; # This is an array ref
						if (!defined($excerptArr) || $excerptArr eq '')
							{
							if (defined($hit->{'highlight'}->{'title'}) && $hit->{'highlight'}->{'title'} ne '')
								{
								$excerptArr = $hit->{'highlight'}->{'title'};
								}
							}
						
						my @fixedLines;
						_DecodeWhitespace(\@fixedLines, $excerptArr);
						my $excerptRaw = join("", @fixedLines);
						$excerptRaw =~ s!  !&nbsp;&nbsp;!g;
						my $excerpt = _GetEncodedExcerpt($excerptRaw);
						
						
						$path =~ s!%!%25!g;
						$path =~ s!\+!\%2B!g;
						
						my $pathWithSearchItems = $path . $searchItems;
						my $anchor = "<a href='$pathWithSearchItems' onclick = \"viewerOpenAnchor(this.href); return false;\" class='canopen' target='_blank'>$title</a>";
						my $editAnchor = '';
						$path =~ /\.([^.]+)$/;
				   		my $ext = $1;
				   		
						if ($alllowEditing && (!$remote || $ext !~ m!^(docx|pdf)!i))
							{
							$editAnchor = "<a href='$path' onclick = \"editOpen(this.href); return false;\">&nbsp;&nbsp;<img src='edit1.png' width='17' height='12' /></a>";
							}
						
						# Wrap up $editAnchor in a span, for optional removal later.
						$editAnchor = "<span class='editAnchor'>$editAnchor</span>";
						my $niceTimeStamp = _FileStampTimeForHumans($mtime);
						my $fileSize = _FileSizeString($hit->{'_source'}->{'size'});
						
	
						# Put a place to break in $displayedPath if it's very long, to avoid sideways scroll.
						my $longestPathSegmentLength = 90;
						$displayedPath = _StringWithBreaks($longestPathSegmentLength, $displayedPath);
						
						# Apologies for this line. Link, time stamp, file size, score, file path.
						# And excerpt, way out there at the end.
						my $entry = "<tr class='oneResult'><td><p class='hitsummary'><strong><span class='resultAnchors'>$anchor$editAnchor</span></strong>&nbsp;&nbsp;<span class='resultTime'>$niceTimeStamp</span>&nbsp;&nbsp; <span class='resultSize'>$fileSize</span>&nbsp;&nbsp; Score: <span class='resultScore'>$score</span> &nbsp;&nbsp;<span class='resultPath'>$displayedPath</span></p>\n<div class='excerpt'>$excerpt</div></td></tr>\n";
						$$resultR .= $entry;
						} # if (!defined($fullPathSeen{$path}))
					}
				} # if ($path ne '')
			} # for my $hit (@{ $rawResults->{'hits'}->{'hits'} } )
		if ($$resultR eq '')
			{
			$$resultR = "<p>No results found for selected extension(s) @$extA.</p>";
			}
		else
			{
			$$resultR .= "</table>\n";
			}
		} # if (defined($numHits)...
		
	return($hitCounter);
	}

# Count of documents indexed in primary index.
sub Count {
	my ($self) = @_;
	my $e = $self->{SEARCHER};
	my $result = $e->count(index => $self->{INDEX_NAME});
	return($result->{'count'});
	}

sub ClusterHealth {
	my ($self) = @_;
	my $e = $self->{SEARCHER};
	my $health = $e->cluster->health();
	my $result = (defined($health->{'status'})) ? $health->{'status'}: 'unknown';
	return($result);
	}

# Decode newlines and tabs, and non-breaking spaces. This reverses the encoding done
# in elasticsearch_bulk_indexer.pm#AddDocumentToIndex().
sub _DecodeWhitespace {
	my ($fixedLinesA, $excerptArr) = @_;

	for (my $i = 0; $i < @$excerptArr; ++$i)
		{
		$excerptArr->[$i] =~ s! ?__S_ ?!\&nbsp;!g;
		$excerptArr->[$i] =~ s! ?__T_ ?!\t!g;
		$excerptArr->[$i] =~ s! ?__P_ ?!\n!g;
		$excerptArr->[$i] =~ s! *__D_ *!\.!g;
		$excerptArr->[$i] =~ s!__DS_([A-Za-z])!\$$1!g;
		$excerptArr->[$i] =~ s!__L_([A-Za-z])!\~$1!g;
		$excerptArr->[$i] =~ s!__PC_([A-Za-z])!\%$1!g;
		$excerptArr->[$i] =~ s!__AT_([A-Za-z])!\@$1!g;
		
		# '<' to '&lt;' - otherwise HTML leaks through, we get live search forms
		# etc displaying in the search results.
		$excerptArr->[$i] =~ s!<!&lt;!g;
		# But put the <strong>...</strong> tags back, for hit highlighting.
		$excerptArr->[$i] =~ s!&lt;strong>!<strong>!g;
		$excerptArr->[$i] =~ s!&lt;/strong>!</strong>!g;
		# Tweak, non-English periods come through as '', trim down to just '.'.
		$excerptArr->[$i] =~ s! <strong>.</strong> !\.!g;
		
		my @lines = split(/\n/, $excerptArr->[$i]);
		my @linesWithoutTabs = expand(@lines);
		for (my $j = 0; $j < @linesWithoutTabs; ++$j)
			{
			$lines[$j] = "<p>$linesWithoutTabs[$j]</p>";
			}
		$excerptArr->[$i] = join("", @lines);
		push @$fixedLinesA, $excerptArr->[$i];
		}
	}

sub _GetEncodedExcerpt {
	my ($excerptRaw) = @_;
	my $excerpt = '';
	
	my $decoder = Encode::Guess->guess($excerptRaw);
	if (ref($decoder))
		{
		my $decoderName = $decoder->name();
		if ($decoderName =~ m!iso-8859-\d+!)
			{
			$excerpt = $excerptRaw;
			}
		else
			{
			if ($decoderName eq 'utf8')
				{
				$excerpt = encode_utf8($excerptRaw);
				}
			else
				{
				$excerpt = $excerptRaw;
				}
			}
		}
	else
		{
		$excerpt = $excerptRaw;
		}
	
	return($excerpt);
	}

# Put a place to break in $displayedPath if it's very long, to avoid sideways scroll.
# Qt is fond of such paths as
#  c:\qt\5.7\src\qtwebengine\src\3rdparty\chromium\third_party\skia\platform_tools\
#    android\third_party\native_app_glue\android_native_app_glue.h
sub _StringWithBreaks {
	my ($longestPathSegmentLength, $displayedPath) = @_;
	
	if (length($displayedPath) > $longestPathSegmentLength)
		{
		# '<span class="noshow"></span>' just signals browser can break line.
		# See main.css.
		my $lineBreaker = '<span class="noshow"></span>';
		my $pathLength = length($displayedPath);
		my $lastPosition = $pathLength;
		while ($lastPosition >= $longestPathSegmentLength)
			{
			--$lastPosition;
			if ($lastPosition > 0)
				{
				$lastPosition = rindex($displayedPath, "\\", $lastPosition);
				}
			}
		if ($lastPosition > 0)
			{
			$displayedPath = substr($displayedPath, 0, $lastPosition + 1) . $lineBreaker .
				substr($displayedPath, $lastPosition + 1);
			}
		}
	
	return($displayedPath);
	}

sub _FileSizeString {
	my ($rawSize) = @_;
	
	my @sizes = qw( B KB MB GB TB PB);
	my $i = 0;
	while ($rawSize > 1000)
		{
		$rawSize = $rawSize / 1000;
		++$i;
		}
	my $fileSize = ($i > 0) ? sprintf("%.1f $sizes[$i]", $rawSize) : $rawSize . " $sizes[0]";
	
	return($fileSize);
	}

sub _FileStampTimeForHumans {
	my ($mtime) = @_;
	my ($sec, $min, $hr, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($mtime);
    $mon += 1;
    if ($year < 1900)
    	{
    	$year += 1900;
    	}
    my $niceDate = sprintf("%04d-%02d-%02d at %02d:%02d", $year,$mon,$mday, $hr,$min);
    return $niceDate;
	}

1;
