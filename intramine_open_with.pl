# intramine_open_with.pl: answer xmlhttprequest for text file opening in 'edit' mode.
# Call notepad++ (or whatever app is set in intramin_config.txt) to open a text file,
# return OK or an error message.
# See "Documentation/Editing documents.html" for details on configuring IntraMine to use your preferred editor, or
# IntraMine's own editor (or prevent all editing through IntraMine).
# NOTE requests only come here when a preferred app has been specified as the editor of choice.
# If IntraMine's Editor has been specified, that's handled in JavaScript directly and
# this service isn't called. See eg viewerLinks.js#editWithIntraMine().
#
# See also Documentation/Opener.html.
#

# perl C:\perlprogs\mine\intramine_open_with.pl 81 43125

use strict;
use warnings;
use utf8;
use FileHandle;
#use Encode qw/encode decode/;
use URI::Escape;
use IO::Socket;
use IO::Select;
use IO::Socket::Timeout;
use Win32::Process;
use Win32;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;

binmode(STDOUT, ":encoding(UTF-8)");
Win32::SetConsoleCP(65001);

#binmode(STDOUT, ":utf8");
$| = 1;

my $PAGENAME    = '';
my $SHORTNAME   = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

my $kLOGMESSAGES     = 0;    # 1 == Log Output() messages
my $kDISPLAYMESSAGES = 0;    # 1 == print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print.
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);
Output("Starting $SHORTNAME on port $port_listen\n\n");

# Text editor. See data/intramine_config.txt bottom for "OPENER_..." options. NOTE you might have to
# change the path in intramine_config.txt to match your system. Eg for Eclipse,
# OPENER_ECLIPSE	C:/javascript-2018-12/eclipse/eclipse.exe
# your version of Eclipse is probably somewhere else.
# Canned options, listed in data/intramine_config.txt (see 'LOCAL_OPENER_APP'):
#OPENER_NOTEPADPP	%ProgramFiles(x86)%/Notepad++/notepad++.exe
# NoteTab works best if you start it manually before using with IntraMine.
#OPENER_NOTETAB	%ProgramFiles(x86)%/NoteTab Light/NoteTab.exe
#OPENER_ECLIPSE	C:/javascript-2018-12/eclipse/eclipse.exe
#OPENER_KOMODO	%ProgramFiles(x86)%/ActiveState Komodo Edit 9/komodo.exe
# VS Code also works best if you start it manually before using with IntraMine.
#OPENER_VISUALSTUDIOCODE	%LOCALAPPDATA%/Programs/Microsoft VS Code/Code.exe
# Best to start Atom by hand also before using with IntraMine.
#OPENER_ATOM	%LOCALAPPDATA%/atom/atom.exe
# Remote text editor ('REMOTE_OPENER_APP'): path for app to use on remote PCs
# (not the IntraMine box itself).
# Options are similar to those for text editor above, note they are paths to apps on the
# remote PC, not the IntraMine PC.
###############################################################
my $WhichLocalEditor     = CVal('LOCAL_OPENER_APP');
my $TextEditorPath       = CVal($WhichLocalEditor);
my $WhichRemoteEditor    = CVal('REMOTE_OPENER_APP');
my $RemoteTextEditorPath = CVal($WhichRemoteEditor);
my $LocalPdfEditor       = CVal('LOCAL_OPENER_PDF');
my $LocalWordEditor      = CVal('LOCAL_OPENER_WORD_DOCX');
###############################################################
$TextEditorPath       =~ s!/!\\!g;
$RemoteTextEditorPath =~ s!/!\\!g;

# Port for remote open requests.
my $RemoteOpenPort = CVal('INTRAMINE_FIRST_SWARM_SERVER_PORT');


# Load up remote directory names for directories on the IntraMine box
# from intramine_config.xt. We look for lines like
# C:/Qt<tab>\\DESKTOP-D4KOMRV\wsqt
# where "C:/Qt" is a directory on the IntraMine box, and
# \\DESKTOP-D4KOMRV\wsqt is \\the host-name\share-name to use for remote access.
LoadRemoteMappings();

my %RequestAction;
$RequestAction{'req|open'} = \&OpenTheFile;    # req=open $formH->{'file'}
#$RequestAction{'req|id'} = \&Identify; # req=id

# Over to swarmserver.pm.
MainLoop(\%RequestAction);

############## subs
# Call preferred editing app to open the file path supplied in $formH->{'file'}.
sub OpenTheFile {
	my ($obj, $formH, $peeraddress) = @_;

	# Originating peer address is $formH->{'clientipaddress'}. This is required.
	my $clientIPAddress = defined($formH->{'clientipaddress'}) ? $formH->{'clientipaddress'} : '';
	if ($clientIPAddress eq '')
		{
		# TEST ONLY
		Monitor("clientipaddress NOT SET");
		return ("MAINTENANCE ERROR, \"$formH->{'clientipaddress'} is NOT SET.");
		}

	my $serverAddr     = ServerAddress();
	my $clientIsRemote = 0;

	# If client is on the server then peeraddress can be either 127.0.0.1 or $serverAddr:
	# if client is NOT on the server then peeraddress is not 127.0.0.1 and differs from $serverAddr.
	if ($clientIPAddress ne '127.0.0.1' && $clientIPAddress ne $serverAddr)
		{
		$clientIsRemote = 1;
		}

	my $status   = 'OK';
	my $filepath = defined($formH->{'file'}) ? $formH->{'file'} : '';
	$filepath =~ s!\\!/!g;

	Output("OpenTheFile \$filepath: |$filepath|\n");

	if ($clientIsRemote)
		{
		RemoteOpenFile($clientIPAddress, $filepath, \$status);
		}
	else
		{
		LocalOpenFile($filepath, \$status);
		}

	if ($status ne 'OK')
		{
		Output("OpenTheFile ERROR: |$status|\n");
		}

	return ($status);
}

# Fire off a temporary batch file to open the file with path $filepath.
# This is called only for requests made on the IntraMine server box.
sub LocalOpenFile {
	my ($filepath, $statusR) = @_;

	my $ext = '';
	if ($filepath =~ m!\.(\w+)$!)
		{
		$ext = lc($1);
		}

	# Double up any % signs to avoid interpolation in the batch file.
	$filepath =~ s!\%!\%\%!g;
	# Reverse the slashes to all '\', some apps like that better. Eg Word and Eclipse.
	$filepath =~ s!/!\\!g;

	my $batPath;

	if ($ext =~ m!docx?!)
		{
		$batPath = GetTempBatPathForFile($LocalWordEditor, $filepath);
		}
	elsif ($ext =~ m!pdf!)
		{
		$batPath = GetTempBatPathForFile($LocalPdfEditor, $filepath);
		}
	else
		{
		# Eg
		# $batPath = GetTempBatPathForFile("%ProgramFiles(x86)%\\Notepad++\\notepad++.exe", $filepath);
		$batPath = GetTempBatPathForFile($TextEditorPath, $filepath);
		}

	my $openresult = system(1, "\"$batPath\">nul 2>&1");
	if ($openresult == -1)
		{
		# TEST ONLY
		#Monitor("Could not open |$filepath|");
		$$statusR = "Could not open |$filepath|";
		}
	# TEST ONLY
	#Monitor("batpath was |$batPath|");
}

# Send request to $clientIPAddress:$RemoteOpenPort to please open remote version of $filepath
# using $RemoteTextEditorPath. We expect a PowerShell server IntraMine-Remote.ps1 (copied over
# from your IntraMine bats/ folder) to be running on the remote PC.
# For more see IM_CONFIG.
# Require a good response, or it didn't happen.
sub RemoteOpenFile {
	my ($clientIPAddress, $filepath, $statusR) = @_;
	my $remoteEditor = $RemoteTextEditorPath;

	if ($remoteEditor eq '')
		{
		$$statusR = "ERROR no value for REMOTE_OPENER_APP found in intramine_config.txt";
		return;
		}

	# Put remote \\host-name\share\ in place of Drive:/folders... to come up with the file
	# path from the perspective of the remove PC making the Open request. The entries
	# for this mapping are near the bottom of data/intramine_config.txt. Again, there's
	# more about this in IM_CONFIG.
	my $remotePath = RemotePathForIntraMinePath($filepath);
	if ($remotePath eq '')
		{
		$$statusR = "ERROR no remote mapping found in intramine_config.txt for |$filepath|";
		return;
		}

	my $remotePort = $RemoteOpenPort;

	RequestRemoteOpen($clientIPAddress, $remotePort, $remoteEditor, $remotePath, $statusR);
}

sub RequestRemoteOpen {
	my ($clientIPAddress, $remotePort, $remoteEditor, $filepath, $statusR) = @_;

	Output("RRO clientIPAddress: |$clientIPAddress|\n");
	Output("     RRO remotePort: |$remotePort|\n");

	my $remote = IO::Socket::INET->new(
		Proto    => 'tcp',                 # protocol
		PeerAddr => "$clientIPAddress",    # Address of server
		PeerPort => "$remotePort",         # port of server (eg 81)
		Timeout  => 2
	) or (($$statusR = "ERROR could not connect to $clientIPAddress:$remotePort") && return);

	IO::Socket::Timeout->enable_timeouts_on($remote);
	$remote->read_timeout(1.0);
	$remote->write_timeout(1.0);

	# Eclipse 2018-12 cannot open a file if forward slashes are used in the path.
	$filepath =~ s!/!\\!g;

	$filepath = uri_escape_utf8($filepath);

	# Send the request, with headers that Chrome would typically supply.
	print $remote "GET /?app=$remoteEditor&path=$filepath HTTP/1.1\n";
	print $remote
"Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3\n";
	print $remote "Accept-Encoding: gzip, deflate\n";
	print $remote "Accept-Language: en-US,en;q=0.9\n";
	print $remote "Cache-Control: max-age=0\n";
	print $remote "Connection: keep-alive\n";
	print $remote "Host: $clientIPAddress:$remotePort\n";
	print $remote "Upgrade-Insecure-Requests: 1\n";
	print $remote
"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.169 Safari/537.36\n\n";

	my $line = <$remote>;
	chomp($line) if (defined($line));
	close $remote;
	my $itWentWell = (defined($line) && $line =~ m!ok!i) ? 1 : 0;

	if (!$itWentWell)
		{
		if (defined($line))
			{
			$$statusR = "ERROR remote open failed with response |$line|";
			}
		else
			{
			$$statusR = "ERROR no response to open request from $clientIPAddress:$remotePort";
			}
		}
}

# $batPath = GetTempBatPathForFile("%ProgramFiles(x86)%\\Notepad++\\notepad++.exe", $filepath); etc.
# Create a temporary .bat file that will open $filepath when run, using the program specified
# in $progPath. This does seem like extra work, but it's the only way I've found to persuade
# Windows to pass along a file path when the path contains unicode characters
# (that's the "chcp 65001" part).
sub GetTempBatPathForFile {
	my ($progPath, $filepath) = @_;
	my $LogDir        = FullDirectoryPath('LogDir');       # ...logs/IntraMine/
	my $randomInteger = random_int_between(1001, 60000);
	my $batPath =
		$LogDir . 'temp/' . 'tempbat' . $port_listen . '_' . time . $randomInteger . '.bat';
	MakeDirectoriesForFile($batPath);

	my $outFileH = FileHandle->new("> $batPath")
		or return ("FILE ERROR could not make |$batPath|!");
	binmode($outFileH, ":utf8");
	print $outFileH "chcp 65001\n";
	print $outFileH "\"$progPath\" \"$filepath\"\n";

	# Self-destruct.
	print $outFileH "del \"%~f0\"\n";
	close($outFileH);

	return ($batPath);
}

{ ##### Remote dir for IntraMine dir
my %RemotePathForLocalPath;    # eg $RemotePathForLocalPath{'c:/qt'} = '\\DESKTOP-D4KOMRV\wsqt';

# Load up remote directory names for directories on the IntraMine box
# from intramine_config.txt. We look for lines like
# C:/Qt<tab>\\DESKTOP-D4KOMRV\wsqt
# (with forward or back slashes)
# where "C:/Qt" is a directory on the IntraMine box, and
# \\DESKTOP-D4KOMRV\wsqt is \\the host-name\share-name to use for remote access.
sub LoadRemoteMappings {
	# Get entire intramine_config.txt as as hash.
	my $configH = ConfigHashRef();

	# Loop through entire config hash looking for likely IntraMine directories as keys.
	foreach my $key (keys %$configH)
		{
		if (LooksLikeIntraMineDirectory($key))
			{
			my $remoteValue = $configH->{$key};
			$key =~ s!\\!/!g;
			$key = lc($key);
			$RemotePathForLocalPath{$key} = $remoteValue;
			}
		}
}

# For remote access, turn eg C:/Qt/folder/file.cpp into //DESKTOP-D4KOMRV/wsqt/folder/file.cpp
# based on the line
# C:/Qt<tab>\\DESKTOP-D4KOMRV\wsqt
# in intramine_config.txt, as loaded by LoadRemoteMappings().
sub RemotePathForIntraMinePath {
	my ($intraminePath) = @_;
	$intraminePath =~ s!\\!/!g;
	$intraminePath = lc($intraminePath);
	my $result = '';

	foreach my $key (keys %RemotePathForLocalPath)
		{
		if ($intraminePath =~ m!^$key!)
			{
			my $remoteValue = $RemotePathForLocalPath{$key};
			$intraminePath =~ s!^$key!$remoteValue!;
			$result = $intraminePath;
			}
		}

	return ($result);
}

# Any string that starts with a letter-colon-forward slash, or _INTRAMINE_ counts.
# It doesn't matter if we pick up too many entries.
sub LooksLikeIntraMineDirectory {
	my ($maybeDir) = @_;
	my $result = 0;

	if ($maybeDir eq '_INTRAMINE_')
		{
		$result = 1;
		}
	else
		{
		$maybeDir =~ s!\\!/!g;
		if ($maybeDir =~ m!^[A-Za-z]\:/!)
			{
			$result = 1;
			}
		}

	return ($result);
}
}    ##### Remote dir for IntraMine dir
