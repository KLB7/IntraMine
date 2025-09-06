# LogFile.pm: write a log, optional clear. Log is optionally closed after
# each write.

# use LogFile;
# my $log = new LogFile("c:/alog.txt"); # clear it
# my $log = new LogFile("c:/alog.txt", 'no'); # don't clear it
# $log->Log("Something happened.\n");

package LogFile;
use strict;
use warnings;
use utf8;
use Carp;
use FileHandle;

# my $log = new LogFile(path, clear, echo, leave_open);
# path: full path to log file
# clear: 'no...' to not clear, anything without 'no' to clear on first open [default is to clear]
# echo: 1 to print copy of messages [default is no echo]
# leave open: 1 to leave open [default is close after every write]
# Record the log file's full path. Ensure log opens or die. Clear the log file if asked.
# Start the log off with a time stamp.
sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self  = {};
	$self->{PATH}      = shift || 'c:/defaultlogfile999.txt';
	$self->{CLEAR}     = shift || 'yes';
	$self->{ECHO}      = shift || 0;
	$self->{LEAVEOPEN} = shift || 0;
	$self->{ISOPEN}    = 0;
	$self->{LOGH}      = '';
	##my $logH;

	$self->{LEAVEOPEN} = 0 unless ($self->{LEAVEOPEN} =~ m!yes|leave open|1!i);
	$self->{ECHO}      = 0 unless ($self->{ECHO}      =~ m!yes|1!i);

	my $now = NiceToday();
	if ($self->{CLEAR} =~ /no|0/i)
		{
		$self->{LOGH} = FileHandle->new(">> $self->{PATH}")
			or confess("LogFile: $self->{PATH} would not open!");
		my $logH = $self->{LOGH};
		print $logH "Time stamp: $now\n";
		}
	else
		{
		$self->{LOGH} = FileHandle->new("> $self->{PATH}")
			or confess("LogFile: $self->{PATH} would not open!");
		my $logH = $self->{LOGH};
		print $logH "Last cleared: $now\n";
		}

	if (!$self->{LEAVEOPEN})
		{
		close($self->{LOGH});
		}
	else
		{
		$self->{ISOPEN} = 1;
		}

	bless($self, $class);
	return $self;
}

sub DESTROY {
	my $self = shift;
	if ($self->{ISOPEN})
		{
		close($self->{LOGH});
		$self->{ISOPEN} = 0;
		}
}

# Open, add to log file, close. Note newlines are not added.
sub Log {
	my $self = shift;
	my $text = shift;
	if (!$self->{ISOPEN})
		{
		$self->{LOGH} = FileHandle->new(">> $self->{PATH}")
			or confess("LogFile Log: DED, $self->{PATH} would not open!");
		}
	my $logH = $self->{LOGH};
	print $logH "$text";

	if (!$self->{LEAVEOPEN})
		{
		close($self->{LOGH});
		$self->{ISOPEN} = 0;
		}
	else
		{
		$self->{ISOPEN} = 1;
		}

	if ($self->{ECHO})
		{
		print "$text";
		}
}

# Default for LEAVEOPEN is 0 - set to 1 to not close file between writes.
sub LeaveOpen {
	my $self = shift;
	if (@_)
		{
		$self->{LEAVEOPEN} = shift;
		}
	return $self->{LEAVEOPEN};
}

# Set ECHO to STDOUT on/off with ->Echo(1)/Echo(0).
sub Echo {
	my $self = shift;
	if (@_)
		{
		$self->{ECHO} = shift;
		}
	return $self->{ECHO};
}

sub Path {
	my $self = shift;
	return ($self->{PATH});
}

# Nicely formatted date/time.
sub NiceToday {
	my ($sec, $min, $hr, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
	sprintf("%04d/%02d/%02d %02d:%02d:%02d", $year + 1900, $mon + 1, $mday, $hr, $min, $sec);
}

1;

