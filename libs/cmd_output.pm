# cmd_output.pm: open, close, write to a file. The script using this
# package can write to the file, and a different script can read
# from it.
# Mainly for use with intramine_commandserver.pl and intramine_reindex.pl
# and in general when Run as administrator is needed (which can start
# a new process and in doing so disconnect output from a cmd console).

package cmd_output;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use utf8;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use win_wide_filepaths;

my $CmdOutputPath = '';


sub InitCmdOutput {
	my ($cmdOutputPath) = @_;
	$CmdOutputPath = $cmdOutputPath;
	MakeDirWide($CmdOutputPath);
	DeleteFileWide($CmdOutputPath);
	}

sub WriteToOutput {
	my ($msg) = @_;

	return(AppendToTextFileWide($CmdOutputPath, $msg));
	}

sub WriteDoneAndCloseOutput {
	my $result = WriteToOutput('***A-L-L***D-O-N-E***');
	CloseCmdOutput();
	return($result);
	}

# Does nothing at the moment, file is closed between writes.
sub CloseCmdOutput {
	return(1);
	}



use ExportAbove;
return 1;
