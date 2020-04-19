# elasticsearch_bulk_indexer.pm: add files to Elasticsearch index, a bunch at a time
# with a bulk indexer. Tested with elasticsearch-6.5.1, 6.8.0.
# Used for example in elastic_indexer.pl, which indexes all files in a list of directories.
# NOTE this should not (yet) be used with Elasticsearch 7.

package elasticsearch_bulk_indexer;

use strict;
use warnings;
use utf8;
use FileHandle;
use File::Find;
use XML::LibXML;
use HTML::Parser;
use Search::Elasticsearch;
use Text::Unidecode;
use Encode;
use Encode::Guess;
use File::Slurp;
use Path::Tiny qw(path);
#use lib path($0)->absolute->parent->child('libs')->stringify;
use lib ".";
use common;
use win_wide_filepaths;

Encode::Guess->add_suspects(qw/iso-8859-1/);

my $TextFromXML; # or HTML

# Make a new elasticsearch_bulk_indexer instance
sub new {
	my ($proto, $esIndexName, $esTextIndexType, $maxFileSizeKB) = @_;
	my $class = ref($proto) || $proto;
	my $self  = {};
	$self->{ES_INDEXNAME} = $esIndexName;
	$self->{ES_TEXTINDEXTYPE} = $esTextIndexType;
	# $maxFileSizeKB <= 0 means no limit. See data/intramine_config.txt ELASTICSEARCH_MAXFILESIZE_KB
	# (Limiting to at most the default 800 is strongly recommended.)
	$self->{MAXFILESIZE_KB} = defined($maxFileSizeKB) ? $maxFileSizeKB: 0;
	
	# Connect to cluster on this PC port 9200.
	# Note Sniff is not currently supported (Dec 2018)
	my $e = Search::Elasticsearch->new(
		nodes    => 'localhost:9200'
#		,cxn_pool => 'Sniff'
	);
	$self->{E} = $e;
	
	$self->{BULK} = $e->bulk_helper(
		index   => $esIndexName,
		type    => $esTextIndexType
	);
	$TextFromXML = '';
	
	bless ($self, $class);
	return $self;
    }

# Add one document. HTML is parsed, other file types are just inhaled as-is.
# $fileSizeBytesR is optional, set to file size if defined. Files larger than
# $self->{MAXFILESIZE_KB} are skipped if it's > 0.
# Empty files are indexed,the 'content' field will be empty but file name wil be searchable.
sub AddDocumentToIndex {
	my ($self, $fileName, $progPath, $fileSizeBytesR) = @_;
	my $displayPath = $progPath;
	$progPath = lc($progPath);
	my $isParsed = 0; # For XML and HTML
	my $contents = '';
	my $result = 0; # assume failure
	
	my $size = GetFileSizeWide($progPath);
	
	if (defined($fileSizeBytesR))
		{
		$$fileSizeBytesR = $size;
		}
	
	# Skip file if it's larger than max wanted size.
	my $filesizeKB = $size / 1000;
	if ($self->{MAXFILESIZE_KB} > 0 && $filesizeKB > $self->{MAXFILESIZE_KB})
		{
		# Early return, skip file because it's too big and would slow down searching.
		return($result);
		}
	
	if ($progPath =~ m!\.xml$!i)
		{
		# I can't find an appropriate XML parser, so we just inhale all words "meta" or not.
		$contents = ReadTextFileDecodedWide($progPath);
		# Try to help the tokenizer.
		$contents =~ s![\[\]</>='"]+! !g;
		}
	elsif ($progPath =~ m!\.html?$!i)
		{
		$isParsed = 1;
		$TextFromXML = '';
		my $fh = GetExistingReadFileHandleWide($progPath);
		
		my $p = HTML::Parser->new(
						api_version		=> 3,
						text_h			=> [\&texth, "text"]
						);

		$p->utf8_mode(1);
		$p->parse_file($fh);
		close($fh);
		}
	else
		{
		$contents = ReadTextFileDecodedWide($progPath);
		}
			
		
	my $content = '';
	if ($isParsed)
		{
		# Elasticsearch is croaking if there's an out of range Unicode character, so
		# we just skip the whole file if one is encountered.
		eval { $content = decode("UTF-8", $TextFromXML); };
		if ($@)
			{
			print("Bad character encountered\n");
			$content = '';
			}
		}
	else
		{
		$content = $contents;
		}
		
	# Preserve newlines and tabs, non-breaking spaces, and non-English periods,
	# and for Perl and JS preserve '$', '~', '%', and '@' as part of a word.
	# see elasticsearcher.pm for restoration of those.
	$content =~ s!\&nbsp;! __S_ !g;
	$content =~ s!\t! __T_ !g;
	$content =~ s!\n! __P_ !g;
	$content =~ s!(\w)\.(\w)!$1 __D_ $2!g;
	$content =~ s!\$([A-Za-z])!__DS_$1!g;
	$content =~ s!\~([A-Za-z])!__L_$1!g;
	$content =~ s!\%([A-Za-z])!__PC_$1!g;
	$content =~ s!\@([A-Za-z])!__AT_$1!g;
	
	# Regretfully, we must skip files that exceed one million bytes in the $content, at
	# least for now (ES v 6.8). The substitutions done just above for "\n" etc can increase
	# a 650 KB file by roughly 180 KB, so default max file size is 700 KB.
	if (length($content) > 1000000)
		{
		return($result);
		}
	
	# To search subdirectories we need fields in the index for each directory "level" for a file.
	# The "level" is just a count of the slashes in the path. Partial paths start at C:/
	# (level 1, in $partialPaths[1] and goes in folder1)
	# and then march down: eg
	# C:/Strawberry/ in $partialPaths[2], goes in folder2
	# C:/Strawberry/perl/ in $partialPaths[3], goes in folder3, etc.
	# When searching, if files in C:/Strawberry/ and all subdirectories are wanted, we filter
	# the search to match "C:/Strawberry/" in the "folder2" field. If subdirs are not wanted,
	# we will just match on the "allfolders" index field.
	# Currently there are 32 levels, which is crazy deep and "should not" be exceeded ever.
	my @partialPaths;
	GetPartialPathsForFullPath($progPath, 34, \@partialPaths);
	
	MakeElasticsearchIndexEntry($self, $fileName, $progPath, $displayPath, \@partialPaths,
								$size, $content);
	
	$result = 1;
	return($result);
	}

sub MakeElasticsearchIndexEntry {
	my ($self, $fileName, $progPath, $displayPath, $partialPathsA, $size, $content) = @_;
	$progPath =~ m!\.(\w+)$!;
	my $ext = $1;
	$ext ||= 'NONE';
	my $id = _ElasticsearchIdForPath($progPath);
	my $title = $fileName;
	#$title =~ s!\.(\w+)$!!; # Don't index extension for the title field.
	# Convert '.' to search-friendly ' __D_ ' in title, as with $content above.
	$title =~ s!(\w)\.(\w)!$1 __D_ $2!g;
	# Note 'title' is used in searches, 'full_title' is just used in display.
	
	my $mtime = GetFileModTimeWide($progPath);
	$mtime ||= 0;

	# Add to the ES index. $response is ignored.
	my $response = $self->{BULK}->index({
		id      => $id,
		source	=> {
			title   	=> $title,
			full_title	=> $fileName,
			path 		=> $progPath,
			displaypath	=> $displayPath,
			allfolders	=> $partialPathsA->[0], # the full dir path down to the file
			folder1		=> $partialPathsA->[1],
			folder2		=> $partialPathsA->[2],
			folder3		=> $partialPathsA->[3],
			folder4		=> $partialPathsA->[4],
			folder5		=> $partialPathsA->[5],
			folder6		=> $partialPathsA->[6],
			folder7		=> $partialPathsA->[7],
			folder8		=> $partialPathsA->[8],
			folder9		=> $partialPathsA->[9],
			folder10	=> $partialPathsA->[10],
			folder11	=> $partialPathsA->[11],
			folder12	=> $partialPathsA->[12],
			folder13	=> $partialPathsA->[13],
			folder14	=> $partialPathsA->[14],
			folder15	=> $partialPathsA->[15],
			folder16	=> $partialPathsA->[16],
			folder17	=> $partialPathsA->[17],
			folder18	=> $partialPathsA->[18],
			folder19	=> $partialPathsA->[19],
			folder20	=> $partialPathsA->[20],
			folder21	=> $partialPathsA->[21],
			folder22	=> $partialPathsA->[22],
			folder23	=> $partialPathsA->[23],
			folder24	=> $partialPathsA->[24],
			folder25	=> $partialPathsA->[25],
			folder26	=> $partialPathsA->[26],
			folder27	=> $partialPathsA->[27],
			folder28	=> $partialPathsA->[28],
			folder29	=> $partialPathsA->[29],
			folder30	=> $partialPathsA->[30],
			folder31	=> $partialPathsA->[31],
			folder32	=> $partialPathsA->[32],
			allfoldersExt	=> $partialPathsA->[0] . $ext, # the full dir path down to the file plus extension
			folderExt1		=> $partialPathsA->[1] . $ext,
			folderExt2		=> $partialPathsA->[2] . $ext,
			folderExt3		=> $partialPathsA->[3] . $ext,
			folderExt4		=> $partialPathsA->[4] . $ext,
			folderExt5		=> $partialPathsA->[5] . $ext,
			folderExt6		=> $partialPathsA->[6] . $ext,
			folderExt7		=> $partialPathsA->[7] . $ext,
			folderExt8		=> $partialPathsA->[8] . $ext,
			folderExt9		=> $partialPathsA->[9] . $ext,
			folderExt10		=> $partialPathsA->[10] . $ext,
			folderExt11		=> $partialPathsA->[11] . $ext,
			folderExt12		=> $partialPathsA->[12] . $ext,
			folderExt13		=> $partialPathsA->[13] . $ext,
			folderExt14		=> $partialPathsA->[14] . $ext,
			folderExt15		=> $partialPathsA->[15] . $ext,
			folderExt16		=> $partialPathsA->[16] . $ext,
			folderExt17		=> $partialPathsA->[17] . $ext,
			folderExt18		=> $partialPathsA->[18] . $ext,
			folderExt19		=> $partialPathsA->[19] . $ext,
			folderExt20		=> $partialPathsA->[20] . $ext,
			folderExt21		=> $partialPathsA->[21] . $ext,
			folderExt22		=> $partialPathsA->[22] . $ext,
			folderExt23		=> $partialPathsA->[23] . $ext,
			folderExt24		=> $partialPathsA->[24] . $ext,
			folderExt25		=> $partialPathsA->[25] . $ext,
			folderExt26		=> $partialPathsA->[26] . $ext,
			folderExt27		=> $partialPathsA->[27] . $ext,
			folderExt28		=> $partialPathsA->[28] . $ext,
			folderExt29		=> $partialPathsA->[29] . $ext,
			folderExt30		=> $partialPathsA->[30] . $ext,
			folderExt31		=> $partialPathsA->[31] . $ext,
			folderExt32		=> $partialPathsA->[32] . $ext,
			content 	=> $content,
			moddate 	=> $mtime,
			size 		=> $size,
            ext 		=> $ext
			}
		});
	}

sub Flush {
	my ($self) = @_;
	$self->{BULK}->flush;
	}

# Update path and id for an existing Elasticsearch index entry.
# Since the path is the unique id identifying the document, it's simplest to null out
# the document's index fields and then re-index it under the new id corresponding to the new path.
# This approach leaves a small stub in the index, but the stub won't match any searches.
# If the id doesn't change, there won't even be a stub.
sub UpdatePath {
	my ($self, $fileName, $oldpath, $newpath) = @_;
	
	DeletePathFromIndex($self, $oldpath);
	AddDocumentToIndex($self, $fileName, $newpath);
	}

sub DeletePathFromIndex {
	my ($self, $oldpath) = @_;
	my $oldid = _ElasticsearchIdForPath($oldpath);
	
	# "Kill" the old index entry. $response is ignored.
	my $response = $self->{BULK}->index({
		id      => $oldid,
		source	=> {
			title   	=> '',
			full_title	=> '',
			path 		=> '',
			displaypath	=> '',
			allfolders	=> '',
			folder1		=> '',
			folder2		=> '',
			folder3		=> '',
			folder4		=> '',
			folder5		=> '',
			folder6		=> '',
			folder7		=> '',
			folder8		=> '',
			folder9		=> '',
			folder10	=> '',
			folder11	=> '',
			folder12	=> '',
			folder13	=> '',
			folder14	=> '',
			folder15	=> '',
			folder16	=> '',
			folder17	=> '',
			folder18	=> '',
			folder19	=> '',
			folder20	=> '',
			folder21	=> '',
			folder22	=> '',
			folder23	=> '',
			folder24	=> '',
			folder25	=> '',
			folder26	=> '',
			folder27	=> '',
			folder28	=> '',
			folder29	=> '',
			folder30	=> '',
			folder31	=> '',
			folder32	=> '',
			allfoldersExt	=> 	'',
			folderExt1		=> '',
			folderExt2		=> '',
			folderExt3		=> '',
			folderExt4		=> '',
			folderExt5		=> '',
			folderExt6		=> '',
			folderExt7		=> '',
			folderExt8		=> '',
			folderExt9		=> '',
			folderExt10		=> '',
			folderExt11		=> '',
			folderExt12		=>'',
			folderExt13		=> '',
			folderExt14		=> '',
			folderExt15		=> '',
			folderExt16		=> '',
			folderExt17		=> '',
			folderExt18		=> '',
			folderExt19		=> '',
			folderExt20		=> '',
			folderExt21		=> '',
			folderExt22		=> '',
			folderExt23		=> '',
			folderExt24		=> '',
			folderExt25		=> '',
			folderExt26		=> '',
			folderExt27		=> '',
			folderExt28		=> '',
			folderExt29		=> '',
			folderExt30		=> '',
			folderExt31		=> '',
			folderExt32		=> '',

			content 	=> '',
			moddate 	=> 0,
			size 		=> 0,
            ext 		=> 'NONE'
			}
		});
	}

# HTML text extraction, for HTML::Parser.
sub texth
	{
	my ($text) = @_;
	$TextFromXML .= $text;
	}

# Extract partial paths of all lengths from $progPath.
# $pathsA->[0] is the full encoded path. [1] [2] etc are progressively longer paths,
# where array entry [1] has one forward slash, [2] has two, etc.
# After the slashes run out, all remaining entries are set to ''.
# $progPath should be full path to file, lc() with only '/' slashes.
sub GetPartialPathsForFullPath {
	my ($progPath, $maxDepth, $pathsA) = @_;
	my $path = DirectoryFromPathTS($progPath); # strip file name, keep trailing slash
	my $encodedPath = $path;
	$encodedPath =~ s![^A-Za-z0-9_]!_!g;
	my $largestSlashCount = $path =~ tr!/!!;
	
	$pathsA->[0] = $encodedPath;
	
	for (my $i = 1; $i < $maxDepth; ++$i)
		{
		$pathsA->[$i] = '';
		}
	
	my $slashPos = -1;
	while (($slashPos = rindex($path, "/")) > 1)
		{
		my $slashCount = $path =~ tr!/!!;
		my $currentEncPath = $path;
		$currentEncPath =~ s![^A-Za-z0-9_]!_!g;
		$pathsA->[$slashCount] = $currentEncPath;
		# Remove the trailing slash,
		$path = substr($path, 0, $slashPos);
		# and remove the dir too.
		my $previousSlashPos = rindex($path, "/");
		if ($previousSlashPos > 1)
			{
			$path = substr($path, 0, $previousSlashPos + 1);
			}
		}
	}

# Lowercase, periods and underscores replaced by '_', and "unicode" replaced with
# rough ASCII equivalents.
sub _ElasticsearchIdForPath {
	my ($path) = @_;
	$path = lc($path);
	$path =~ s!\\!/!g;
	$path = unidecode($path);
	$path =~ s![./]!_!g;
	
	return($path);
	}


return 1;
