# elasticsearch_init_index.pl: create Elasticsearch "intramine" index.
# DESTROY any existing 'intramine' index and create a new empty one.
# Run elastic_indexer.pl after this to fill the index, after adjusting the
# dir list for indexing (data/search_directories.txt).
#
# FIRST TIME?
# WARNING DESTROYS ANY EXISTING "intramine" index! AND also the corresponding list of full paths
# in all indexed directories, used for file linking.
# So you should run this once after installing IntraMine, and thereafter only when you've made
# a big change to your installed source files such as adding thousands of files.
#
# First stop IntraMine if it is running.
# Also install and start Elasticsearch before running this program.
# Run this program.
# Edit data/search_directories.txt to list the directories you want indexed.
# Run  elastic_indexer.pl to build the Elasticsearch index.
# As described in the installation docs you will also want to set up File Watcher
# to monitor the directories you have indexed, and that will enable near-real-time
# updating of your Elasticsearch index.
# Then, at last, you're ready to run IntraMine with full search capabilities.
# A couple of batch files make things a lot easier, and you should use them instead
# of running this program directly:
# For completely rebuilding the Elasticsearch index,
# bats/IM_INIT_INDEX.bat (as Administrator) will:
# - stop IntraMine if it's runnning
# - configure and restart File Watcher to monitor requested folders
# - run this program to delete Elasticsearch's index and IntraMine's full path list
# - run elastic_indexer.pl to build a new Elasticsearch index and full path list
# - and start IntraMine
# To add a directory for indexing,
# bats/IM_ADD_INDEX.bat will:
# - stop IntraMine if it's runnning
# - configure and restart File Watcher to monitor requested folders
# - (NOT call this program)
# - run elastic_indexer.pl to build a new Elasticsearch index and full path list
# - and start IntraMine
#
# A note on shards and replicas
# Out of the box, we're set up to create an index with 5 shards and 0 replica. The replica
# won't actually exist unless you bother to not only set ELASTICSEARCH_NUMSHARDS to 1 but also
# create a second instance of Elasticsearch on another computer and set everything up properly.
# You'll find some notes on that in Elasticsearch with replicas.txt, but I've tried it out and
# there's really nothing gained by setting up a second Elasticsearch node, IntraMine's needs
# aren't that heavy.
# If you do experiment, you can set 'number_of_shards' and 'number_of_replicas' using the
# corresponding settings 'ELASTICSEARCH_NUMSHARDS' and 'ELASTICSEARCH_NUMREPLICAS' respectively
# as found in data\intramine_config.txt. The default values are 5 and 0.
# If you do plan on firing up additional Elasticsearch nodes you will probably want to set
# ELASTICSEARCH_NUMREPLICAS to the number of additional computers that will run Elasticsearch.
# Note if you decide to change the number_of_shards later you should run this
# program again, and rebuild your indexes afterwards.
#
#
# The Elasticsearch index created here is set up to use
# char_filter=icu_normalizer&tokenizer=icu_tokenizer&filter=icu_folding
# See http://search.cpan.org/dist/Tutorial-Elastic-Search-With-Perl-First-Steps-Cheat-Sheet-0.01/lib/Tutorial/Elastic/Search/With/Perl/First/Steps/Cheat/Sheet.pm
# (but note in Elasticsearch 6.X "->create_index" becomes  "->indices->create"
# and "settings" is replaced by "body".)
#
# Command line (update path if your copy of IntraMine isn't in "C:\perlprogs\mine\"):
# perl C:\perlprogs\mine\elasticsearch_init_index.pl

use strict;
use utf8;
use FileHandle;
use Win32::RunAsAdmin qw(force);
use File::Find;
use Path::Tiny qw(path);
use Search::Elasticsearch;
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use intramine_config;
use reverse_filepaths;

# Unbuffer output, in case we are being called from the Intramine Cmd page.
select((select(STDOUT), $| = 1)[0]);

LoadConfigValues();                            # intramine_config.pm
my $esIndexName     = CVal('ES_INDEXNAME');    # default 'intramine'
my $esTextIndexType = CVal('ES_TEXTTYPE');     # default 'text'
if ($esIndexName eq '' || $esTextIndexType eq '')
	{
	die("ERROR, intramine_config.pm could not find values for ES_INDEXNAME and ES_TEXTTYPE!");
	}

my $numShards = CVal('ELASTICSEARCH_NUMSHARDS') + 0;

# See Documentation/Elasticsearch with replicas.txt.
my $numReplicas = CVal('ELASTICSEARCH_NUMREPLICAS') + 0;

# Delete file(s) holding list of full paths to all files in indexed directories.
my $FileWatcherDir       = CVal('FILEWATCHERDIRECTORY');
my $fullFilePathListPath = $FileWatcherDir . CVal('FULL_PATH_LIST_NAME');    # .../fullpaths.out
DeleteFullPathListFiles($fullFilePathListPath);                              # reverse_filepaths.pm

my $e = Search::Elasticsearch->new(nodes => "localhost:9200");

my $response = '';

# Delete IntraMine's Elasticsearch index if it exists.
if ($e->indices->exists(index => $esIndexName))
	{
	$response = $e->indices->delete(index => $esIndexName);
	ShowResponse($response, "$esIndexName index deletion");
	sleep(10);
	}
else
	{
	print("$esIndexName does not exist (yet).\n");
	}

# Create a new empty Elasticsearch index for IntraMine.
$response = $e->indices->create(
	index => $esIndexName,
	body  => {
		settings => {
			number_of_shards     => $numShards,      # default 5
			number_of_replicas   => $numReplicas,    # default 0
			auto_expand_replicas => 'false',         # prevents autocreating unwanted replica(s)
			"analysis"           => {
				"analyzer" => {
					"index_analyzer" => {
						"char_filter" => "icu_normalizer",
						"tokenizer"   => "icu_tokenizer",
						"filter"      => "icu_folding"
					}
				}
			}
		}
	}
);

# For Elasticsearch 6.5.1, this worked fine: it doesn't have the "settings" wrapper.
#$response = $e->indices->create(
#	index      => $esIndexName,
#	"body" => {
#       number_of_shards 	=> $numShards,			# default 5
#       number_of_replicas 	=> $numReplicas,		# default 0
#       auto_expand_replicas	=> 'false',				# prevents autocreating unwanted replica(s)
#		"analysis" => {
#			"analyzer" => {
#				"index_analyzer" => {
#					"char_filter" 	=> "icu_normalizer",
#					"tokenizer" 	=> "icu_tokenizer",
#					"filter"    	=> "icu_folding"
#				}
#			}
#		}
#	}
#);
ShowResponse($response, "$esIndexName index creation");

print("Done Elasticsearch index init.\n");

###############
sub ShowResponse {
	my ($response, $title) = @_;

	print("\n\n$title response:\n-----\n");
	foreach my $key (sort keys %$response)
		{
		print("$key: $response->{$key}\n");
		}
	print("-----\n");
}
