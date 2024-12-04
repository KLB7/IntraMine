# intramine_EM.pl: convert Perl code on clipboard into a sub (or "method")
# This is an IntraMine service. To run it, add the following line
# 1	EM					EM			intramine_EM.pl
# (without the leading # and space)
# to your data/serverlist.txt file and restart IntraMine.
# This service is intended to replace extract_method.pl: this version can
# be used from anywhere on your intranet, and it doesn't need Tk installed.
#
# In the code below, subs starting with lowercase are from the original
# program, subs starting with Uppercase have been added to turn it
# into an IntraMine service.
#
# For the original on which this is based, see
# http://www.bofh.org.uk/2006/09/21/crossing-the-rubicon-again
# by Piers Cawley and Jesse Vincent.
#
# See also Documentation/EM.html.
#
# My syntax check (your path will probably be different):
# perl -c C:/perlprogs/IntraMine/intramine_EM.pl

use strict;
use warnings;
use utf8;
use Encode qw/encode decode/;
use URI::Escape;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use swarmserver;

$|  = 1;

my $PAGENAME = '';
my $SHORTNAME = '';
my $server_port = '';
my $port_listen = '';
SSInitialize(\$PAGENAME, \$SHORTNAME, \$server_port, \$port_listen);

my $kLOGMESSAGES = 0;			# 1 == Log Output() messages, and print to console window
my $kDISPLAYMESSAGES = 0;		# 1 == just print messages from Output() to console window
# Log is at logs/IntraMine/$SHORTNAME $port_listen datestamp.txt in the IntraMine folder.
# Use the Output() sub for routine log/print. See swarmserver.pm#Output().
StartNewLog($kLOGMESSAGES, $kDISPLAYMESSAGES);
Output("Starting $SHORTNAME on port $port_listen\n\n");

my $APINAME = 'extract_method';
my %RequestAction;
# Always put a 'req|main' action if your service responds to user requests with an HTML page.
# req=main: OurPage() returns HTML for our page
$RequestAction{'req|main'} = \&OurPage;
# /dialog/: returns dialog to set how variables are passed to the new sub
# (by value, by reference, or omit if they are in a wider scope).
$RequestAction{'/dialog/'} = \&ShowExtractMethodDialog;

# /extract/: extract the final sub with corrected parameter passing.
$RequestAction{'/extract/'} = \&CreateNewMethod;

# What to do with new sub's arguments:
my $kByValue = 'By value';
my $kByReference = 'By reference';
my $kOmit = 'Omit this one';
my $kReturn = 'Return this one'; # not implemented - hurts my head

# Appended to param names (only scalars passed by value aren't altered):
my $kArraySuffix = '_A';
my $kHashSuffix = '_H';
my $kScalarSuffix = '_R';	# R for Reference

# Marking the end of inferred sub parameters:
my $PARAM_GUARD = '#PARAM_END';

# Over to swarmserver.pm#MainLoop(), listening for requests.
MainLoop(\%RequestAction);

########## subs

# Respond to http://192.168.1.132:43141/EM/?req=main
# (numbers will vary)
# with HTML page consisting in the main of
#  - texarea to paste Perl code that wants extracting
#  - dialog for setting parameter pass type and sub name
#  - texareas for example sub call and extracted sub.
sub OurPage {
	my ($obj, $formH, $peeraddress) = @_;
	
	my $theBody = <<'FINIS';
<!doctype html>
<html><head>
<meta http-equiv="content-type" content="text/html; charset=utf-8">
<title>Extract Method</title>
<link rel="stylesheet" type="text/css" href="main.css" />
<link rel="stylesheet" type="text/css" href="forms.css" />
<link rel="stylesheet" type="text/css" href="tooltip.css" />
<link rel="stylesheet" type="text/css" href="extract_method.css" />
</head>
<body>
_TOPNAV_
<div id="scrollAdjustedHeight">
<h1>Extract Method (for Perl code)</h1>
<div id="container">
<p id='errorid'>&nbsp;</p>
<div>
<ol>
<li>Copy some Perl code that you want to turn into a separate sub.</li>
<li>Paste your code in the box just below.</li>
<li>Set how parameters should be passed and new sub name in the dialog that appears.</li>
<li>Click the "Extract" button.</li>
<li>Copy your new sub or example call from the results at bottom.</li>
</ol>
</div>
<div class="textareaLabel">Paste your Perl code here:</div>
<textarea id="textarea_source" name="textarea_source" spellcheck="false" placeholder="Paste here" rows="5" oninput="onPaste();"></textarea>
<div id='dialogDiv'></div>
<div class="textareaLabel">Example call:</div>
<textarea id="final_sub_name" name="final_sub_name" spellcheck="false" rows="1"></textarea>
<div class="textareaLabel">Your new sub:</div>
<textarea id="extracted_method" name="extracted_method" spellcheck="false" rows="20"></textarea>
</div>
</div>
<script>
let thePort = '_THEPORT_';
let apiName = '_APINAME_';
let errorID = 'errorid';
let contentID = '_CONTENTID_';
</script>
<script src="intramine_config.js"></script>
<script src="spinner.js"></script>
<script src="websockets.js"></script>
<script src="restart.js"></script>
<script src="topnav.js"></script>
<script src="todoFlash.js"></script>
<script src="chatFlash.js"></script>
<script src="tooltip.js"></script>
<script src="lolight-1.4.0.min.js"></script>
<script src="extract_method.js"></script>
</body></html>
FINIS

	my $topNav = TopNav($PAGENAME);		# The top navigation bar, with our page name highlighted
	$theBody =~ s!_TOPNAV_!$topNav!;

	$theBody =~ s!_THEPORT_!$port_listen!; # our port
	$theBody =~ s!_APINAME_!$APINAME!;
	
	$theBody =~ s!_D_SHORTNAME_!$SHORTNAME!;
	$theBody =~ s!_D_OURPORT_!$port_listen!;
	$theBody =~ s!_D_MAINPORT_!$server_port!;
	
	my $contentID = 'scrollAdjustedHeight';
	$theBody =~ s!_CONTENTID_!$contentID!g;
	
	# Put in main IP, main port (def. 81), and our Short name (DBX) for JavaScript.
	# swarmserver.pm#PutPortsAndShortnameAtEndOfBody()
	PutPortsAndShortnameAtEndOfBody(\$theBody);
	
	# Make the Status light flash for this server.
	ReportActivity($SHORTNAME);
	
	return($theBody);
	}

# Do a syntax check on the $code to cook up declarations
# for any missing variables (scalar, array, hash),
# guess at the best way to pass them (value, reference, omit)
# and send back a dialog to the web page that will allow
# adjusting the parameter pass-by and setting the sub name.
sub ShowExtractMethodDialog {
	my ($obj, $formH, $peeraddress) = @_;
	
	# Make the Status light flash for this server.
	ReportActivity($SHORTNAME);
	
	my $code = $formH->{'contents'};
	
	# Clean out some variables.
	init();
	
	# Promote any initial comment lines to the top of the new sub.
	my ($codeExComments, $topComments) = cut_top_comments($code);
	
	# Do the basic extraction, all args passed by value at this stage.
	my $extracted = extract_method($codeExComments, 0);
	
	# Examine scalars, to determine whether default should be pass
	# by value or pass by reference.
	set_scalar_defaults($extracted, 0); # 0 == no decode

	# Show dialog to override whether parameters should be passed
	# by value or reference, or omitted. Optionally rename the sub.
	return(ExtractDialog($extracted));
	}

# Repeatedly check syntax of Perl code, add variable declarations
# until syntax errors go away.
# NOTE if there are errors besides
#   Global symbol "(.*)" requires explicit package name
# then most likely garbage code will be returned.
sub extract_method {
	my $code = shift;
	my $decode = shift; # Set to 1 in second pass done by CreateNewMethod().

	my $LogDir = FullDirectoryPath('LogDir');
	my $randomInteger = random_int_between(1001, 60000);
	my $kTempCodePath = $LogDir . 'temp/emcode' . time . $randomInteger . '.txt';
	$kTempCodePath =~ m!^(.+)(/|\\)[^\\/]+$!;
	my $directoryOnPath = $1;
	mkpath($directoryOnPath);

	write_temporary_file($kTempCodePath, $code);
	my $err	 = 1;
	my @args = ();
	
	
	my $loopLimiter = 0; # anti-lock breaking
	my $loopMax = 100;
	while ($err && ++$loopLimiter <= $loopMax)
		{
		$err = 0;
		open( my $perl, "-|", 'perl -c -CSDA ' . $kTempCodePath . ' 2>&1' )
			|| die $@;
		while ( my $item = <$perl> )
			{
			if ( $item
				=~ /Global symbol "(.*)" requires explicit package name/ )
				{
				$err = 1;
				push @args, $1 unless (grep {$1 eq $_} @args);
				}
			}
		write_temporary_file($kTempCodePath, $code, @args);
		}
	
	unlink($kTempCodePath);
	
	if ($loopLimiter >= $loopMax)
		{
		return("Error, way too many parameters required!\n");
		}
	elsif ($err)
		{
		return("Error, could not extract!\n");
		}
	else
		{
		return codegen($code,'final', $decode, @args);
		}
	}

# Write code, with declarations for additional needed paramters
# (@args) to a temporary file, for a syntax check.
sub write_temporary_file {
	my $tempPath = shift;
	my $code = shift;
	my @args = (@_);
	my $ret = codegen($code, 'test', 0, @args);
	
	my $fileH = new FileHandle("> $tempPath")
			or die("FILE ERROR could not make $tempPath!");
	binmode($fileH, ":utf8");
	print $fileH "$ret";
	close($fileH);
	}

# Run syntax checks on the $code and add variable
# declarations until the errors go away. Return $code
# with declarations added.
sub codegen {
	my $code = shift;
	my $mode = shift;
	my $decode = shift;
	my @args = (@_);
	
	# Took me two days to catch on that I needed this decode().
	# Unicode for Perl under Windows makes my eyes bleed.
	if ($decode)
		{
		my @decodedArgs;
		for (my $i = 0; $i < @args; ++$i)
			{
			push @decodedArgs, decode('UTF-8',$args[$i]);
			}
		@args = @decodedArgs;
		}
	
	my $selforthis_signature = qr/^(\$self|\$this)$/;
	my ($class_obj) = grep { $_ =~ /$selforthis_signature/ } @args;
	my @params = grep { $_ !~ /$selforthis_signature/ } @args;
	my $method_body = generate_signature( $class_obj, \@params, $code );
	my $subname = 'mysub_' . int( rand(1000) );
	
	set_default_sub_name($subname);
	
	my $invocation;
	if ($class_obj)
		{
		$invocation = $class_obj . "->" . $subname;
		}
	else
		{
		$invocation = $subname;
		}
	my $ret = "$invocation("
		. join( ', ', map { $_ =~ /^(\%|\@)/ ? '\\' . $_ : $_ } @params )
		. ");\n";
	$ret .= "sub $subname {"
		. ( $mode eq 'test' ? "use strict;\nuse utf8;\n" : '' )
		. $method_body . "\t}";
	return $ret;
	}

sub generate_signature { 
   my $class_obj = shift;
   my @params = @{(shift)};
   my $code = shift;

	my $ret	 = join(
		"\n",
		( $class_obj ? '  my '.$class_obj." = shift;" :""),
		map {
			my $var = $_;
			if ( $var =~ /^(\%|\@)(.*)$/)
				{
				my $sigil = $1;
				my $name =	$2;
				"\tmy ".$var." = ".$sigil."{(shift)};";
				}
			else
				{
				"\tmy $var = shift;";
				}
			}  @params
		)
		. "\n$PARAM_GUARD\n\n"
		. $code;
	return $ret;
	}

sub do_process_lines {
	my ($match_fn, $action_fn, $lines_R, $numLines, $idx_R, $finalText_R) = @_;
	my $idx = $$idx_R;
	while ($idx < $numLines && $match_fn->($lines_R, $idx))
		{
		$action_fn->($lines_R, $idx, $finalText_R);
		++$idx;
		}
	$$idx_R = $idx;
	}

sub action_copy {
	my ($lines_R, $idx, $finalText_R) = @_;
	$$finalText_R .= "$lines_R->[$idx]\n";
	}

sub do_copy_lines {
	my ($match_fn, $lines_R, $numLines, $idx_R, $finalText_R) = @_;
	do_process_lines($match_fn, \&action_copy, $lines_R, $numLines, $idx_R, $finalText_R);
	}

sub copy_any {
	my ($lines_R, $idx) = @_;
	return 1;
	}

sub copy_comment {
	my ($lines_R, $idx) = @_;
	my $result = ($lines_R->[$idx] =~ m!^\s*\#!);
	return $result;
	}

sub copy_not_param_declaration {
	my ($lines_R, $idx) = @_;
	my $result = ($lines_R->[$idx] !~ m!^\tmy! && $lines_R->[$idx] ne $PARAM_GUARD);
	return $result;
	}

sub copy_not_sub {
	my ($lines_R, $idx) = @_;
	my $result = ($lines_R->[$idx] !~ m!^sub!);
	return $result;
	}

sub cut_top_comments {
	my ($rawText) = @_;
	my $finalText = '';
	my $topComments = '';
	my @lines = split(/\n/, $rawText);
	my $numLines = @lines;
	my $idx = 0;

	do_copy_lines(\&copy_comment, \@lines, $numLines, \$idx, \$topComments);
	do_copy_lines(\&copy_any, \@lines, $numLines, \$idx, \$finalText);
	return($finalText, $topComments);
	}
	
sub insert_top_comments {
	my ($rawText, $topComments) = @_;
	my $finalText = '';
	my @lines = split(/\n/, $rawText);
	my $numLines = @lines;
	my $idx = 0;
	
	# Invocation, unchanged.
	$finalText .= "$lines[$idx++]\n\n";
	# Top Comments.
	$finalText .= $topComments;
	# sub definition.
	do_copy_lines(\&copy_any, \@lines, $numLines, \$idx, \$finalText);
	
	return $finalText;
	}

sub cleanup_param_decls {
	my ($rawText) = @_;
	my $finalText = '';
	
	my @lines = split(/\n/, $rawText);
	my $numLines = @lines;
	my $idx = 0;
	
	# Invocation, unchanged.
	$finalText .= "$lines[$idx++]\n";
	do_copy_lines(\&copy_not_param_declaration, \@lines, $numLines, \$idx, \$finalText);
	
	# The param decl lines: put in a single "my (params...) = @_;"
	my $newArgLine = "\tmy (";
	my $numArgs = 0;
	while ($idx < $numLines && $lines[$idx] =~ m!^\tmy!
		   && $lines[$idx] ne $PARAM_GUARD)
		{
		if ($lines[$idx] =~ m!^\tmy\s+(\S+)!)
			{
			my $argName = $1;
			if ($numArgs)
				{
				$newArgLine .= ", $argName";
				}
			else
				{
				$newArgLine .= $argName;
				}
			}
		++$numArgs;
		++$idx;
		}
	
	if ($numArgs)
		{
		$newArgLine .= ') = @_;';
		$finalText .= "$newArgLine\n";
		}

	# To the end: copy unchanged.
	do_copy_lines(\&copy_any, \@lines, $numLines, \$idx, \$finalText);
		
	return $finalText;
	}

{ ##### Scope for %SubArgs etc.
my %SubArgs;
my %IsScalarArg;
my $SubName;

sub init {
	%SubArgs = ();
	%IsScalarArg = ();
	$SubName = '';
}

sub set_default_sub_name {
	my ($name) = @_;
	
	$SubName = $name;
	}

sub update_sub_name {
	my ($rawText) = @_;
	my $finalText = '';
	my @lines = split(/\n/, $rawText);
	my $numLines = @lines;
	my $idx = 0;
	
	# Change sub name in the call.
	$lines[$idx] =~ s!\w+\(!$SubName(!;
	$finalText .= "$lines[$idx++]\n";
	# And in the sub line.
	do_copy_lines(\&copy_not_sub, \@lines, $numLines, \$idx, \$finalText);
	if ($idx < $numLines && $lines[$idx] =~ m!^sub!)
		{
		$lines[$idx] =~ s!sub\s+\w+!sub $SubName!;
		$finalText .= "$lines[$idx++]\n";
		}
	do_copy_lines(\&copy_any, \@lines, $numLines, \$idx, \$finalText);
		
	return $finalText;
	}

# Record whether the scalar params should be passed by value or reference.
# By ref is used if the scalar's value is changed in an obvious way.
sub set_scalar_defaults {
	my ($rawText, $decode) = @_;
	my $finalText = '';
	
	my @lines = split(/\n/, $rawText);
	my $numLines = @lines;
	my $idx = 0;
	
	my %scalarArgName;
	my %refNameForScalar;
	my %forceByValue; # If ever see '$$' in front of a var, pass by value.
	
	while ($idx < $numLines && $lines[$idx] !~ m!^\tmy!
		   && $lines[$idx] ne $PARAM_GUARD)
		{
		++$idx;
		}
		
	while ($idx < $numLines && $lines[$idx] =~ m!^\tmy!
		   && $lines[$idx] ne $PARAM_GUARD)
		{
		if ($lines[$idx] =~ m!shift;!)
			{
			$lines[$idx] =~ m!^\tmy\s+(\S+)!;
			my $originalName = $1;
			$scalarArgName{"\\$originalName"} = $originalName;
			$IsScalarArg{"\\$originalName"} = 1;
			}
		++$idx;
		}
	# Detect assignment to scalar arguments. Not perfect.
	# First pass, detect "obvious" references with a double dollar
	# sign, such as $$fileCounter - those should be passed by value
	# since they are already references.
	my $bodyStartingLine = $idx;
	for ($idx = $bodyStartingLine ; $idx < $numLines; ++$idx)
		{
		foreach my $scalarArg (keys %scalarArgName)
			{
			if (   $lines[$idx] =~ m!\$$scalarArg\b!
				|| $lines[$idx] =~ m!\$$scalarArg\s!)
				{
				$forceByValue{$scalarArg} = 1;
				}
			}
		}
	
	# Second pass, set $refNameForScalar{} for scalars that look
	# like they should be passed by reference.
	for ($idx = $bodyStartingLine ; $idx < $numLines; ++$idx)
		{
		foreach my $scalarArg (keys %scalarArgName)
			{
			if (   $lines[$idx] =~ m!$scalarArg\s*[.+/*%|&-]?\=[^~]!
				|| $lines[$idx] =~ m!(\+\+|\-\-)$scalarArg\b!
				|| $lines[$idx] =~ m!$scalarArg(\+\+|\-\-)!
				|| $lines[$idx] =~ m!$scalarArg\s*\=~\s*s!
				|| $lines[$idx] =~ m!\\$scalarArg\b! )
				{
				# Avoid if arg has a double dollar sign in front - this
				# suggests it should be passed by value.
				# For example $$someVar += 1;
				if (!defined($forceByValue{$scalarArg}))
					{
					$refNameForScalar{$scalarArg}  = $scalarArgName{$scalarArg} . $kScalarSuffix;
					}
				}
			}
		}

	# set the default handling for the scalar arguments.
	foreach my $scalarArg (keys %scalarArgName)
		{
		if ( defined($refNameForScalar{$scalarArg})
			&& !defined($forceByValue{$scalarArg}) )
			{
			$SubArgs{$scalarArg} = $kByReference;
			}
		else
			{
			$SubArgs{$scalarArg} = $kByValue;
			}
		}
	}

# $SubArgs{param name} holds by-value, by-ref, or omit
# for each param. By value is the default.
# Change $x to $$xR if by reference.
# Drop param from top-level declarations if should omit.
# Fix up the invocation line completely, for all
# params (scalar array hash).
sub fix_scalar_references {
	my ($rawText) = @_;
	my $finalText = '';
	
	my @lines = split(/\n/, $rawText);
	my $numLines = @lines;
	my $idx = 0;
	
	my %scalarArgName;
	my %refNameForScalar;

	# Set up to change by-value to by-ref as wanted.
	foreach my $arg (sort keys %SubArgs)
		{
		if (defined($IsScalarArg{$arg}))
			{
			my $originalName = substr($arg, 1);
			$scalarArgName{$arg} = $originalName;
			if ($SubArgs{$arg} eq $kByReference)
				{
				$refNameForScalar{$arg}	 = $scalarArgName{$arg} . $kScalarSuffix;
				}
			}
		}
	
	# Keep copy of invocation, we add '\' at end to scalars that become refs
	# and drop any args that aren't wanted.
	my $invocation = $lines[$idx++];
	
	# Output sub etc down to first top-level 'my'.
	do_copy_lines(\&copy_not_param_declaration, \@lines, $numLines, \$idx, \$finalText);
	
	# Declarations: change scalar name if it's becoming a ref to scalar.
	# Or drop it if 'Omit this one' has been selected.
	while ($idx < $numLines && $lines[$idx] =~ m!^\tmy!)
		{
		$lines[$idx] =~ m!^\tmy\s+(\S+)!;
		my $originalName = $1;
		
		if ( !(defined($SubArgs{"\\$originalName"})
			 && $SubArgs{"\\$originalName"} eq $kOmit) )
			{
			foreach my $scalarArg (keys %refNameForScalar)
				{
				$lines[$idx] =~ s!$scalarArg\b!$refNameForScalar{$scalarArg}!;
				}			
			$finalText .= "$lines[$idx]\n";
			}
		++$idx;
		}
	
	# To the end: change scalar name and prepend an extra '$'
	# for the new scalar reference args.
	for ( ; $idx < $numLines; ++$idx)
		{
		foreach my $scalarArg (keys %refNameForScalar)
			{
			if ($lines[$idx] =~ m!\\$scalarArg\b!)
				{
				$lines[$idx] =~ s!\\$scalarArg\b!$refNameForScalar{$scalarArg}!g;
				}
			if ($lines[$idx] =~ m!$scalarArg\b!)
				{
				$lines[$idx] =~ s!$scalarArg\b!\$$refNameForScalar{$scalarArg}!g;
				}
			}
		$finalText .= "$lines[$idx]\n";
		}

	# Add back invocation line with adjusted params.
	$invocation = fix_invocation(\%refNameForScalar, \%scalarArgName, $invocation);
	
	$finalText = "$invocation\n" . $finalText;
	
	return $finalText;
	}

# Fix up invocation by adding '\' before all scalars now passed by reference
# and by deleting arguments where 'Omit this one' was selected.
# Cheating a bit, we take out unwanted array and hash params here too.
sub fix_invocation {
	my ($refNameForScalar_H, $scalarArgName_H, $invocation) = @_;

	foreach my $scalarArg (keys %$refNameForScalar_H)
		{
		$invocation =~ s!$scalarArg\b!\\$scalarArgName_H->{$scalarArg}!;
		}
	
	foreach my $arg (sort keys %SubArgs)
		{
		if ($SubArgs{$arg} eq $kOmit)
			{
			# Delete arg from invocation, and comma-space if any.
			if ($invocation =~ m!([, ]+)\\?$arg!)
				{
				$invocation =~ s!([, ]+)\\?$arg!!;
				}
			else
				{
				$invocation =~ s!\\?$arg([, ]+)?!!;
				}
			}
		}
		
	return $invocation;
	}

# Alter my @x = @{(shift)} to my $xA = shift, similarly %y -> $yH.
# Replace @x/%y with @$xA/@$yH, $x/$y with $xA->/$yH->.
# Replace \@x with $xA, %y with $yH.
# Force all array and hash params to be passed by reference: if
# by value is wanted, use the passed reference to make a local copy.
# (Unwanted array and hash params have already been dropped from
# the invocation line by fix_scalar_references().)
sub fix_array_hash_references {
	my ($rawText) = @_;
	my $finalText = '';
	
	my @lines = split(/\n/, $rawText);
	my $numLines = @lines;
	my $idx = 0;
	
	# Invocation, already fixed up completely by fix_scalar_references.
	$finalText .= "$lines[$idx++]\n";
	
	# sub etc down to first top-level 'my'.
	do_copy_lines(\&copy_not_param_declaration, \@lines, $numLines, \$idx, \$finalText);
	
	# Note any top-level 'my' parm names and alter @ or % declarations to be $ references.
	my %repForName;		# $repForName{'@x'} = '@$xA'; $derefRepForName{'$x'} = '$xA->';
	my %derefRepForName;# $repForName{'%y'} = '%$yH'; $derefRepForName{'$y'} = '$yH->';
	my %repForRefName;	# $repForRefName{'\@x'} = '$xA'; $repForRefName{'\%y'} = '$yH';
	my %shouldPassByValue;
	my %byValueDerefKey;
	my %byValueRefKey;
	
	while ($idx < $numLines && $lines[$idx] =~ m!^\tmy!)
		{
		if ($lines[$idx] =~ m!(\@|\%)\{!)
			{
			$lines[$idx] =~ m!^\tmy\s+(\S+)!;
			my $originalName = $1;
			
			# Skip the 'my' declaration line if param is to be omitted.
			if ( !(defined($SubArgs{"\\$originalName"})
			  && $SubArgs{"\\$originalName"} eq $kOmit) )
				{
				my $newRefName = $originalName;
				my $isArray = ($originalName =~ m!\@!);
				$newRefName =~ s!(\@|\%)!\$!;
				my $leader = ($isArray) ? '@': '%';
				my $trailer = ($isArray) ? $kArraySuffix: $kHashSuffix;
				my $newDerefName = "$newRefName$trailer";
				$newRefName = "$leader$newDerefName";
				my $derefName = $originalName;
				$derefName =~ s!(\@|\%)!\$!;
				
				$repForName{"\\$originalName"} = $newRefName;
				$derefRepForName{"\\$derefName"} = "$newDerefName->";
				$repForRefName{"\\\\$originalName"} = "$newDerefName";
				# Fix the decl line.
				$lines[$idx] = "\tmy $newDerefName = shift;";
				
				# Having done all that work to pass by ref, what if we really
				# wanted pass by value? We'll stuff in a copy of the array or
				# hash using its original name, and not change the name used
				# in the code.
				if (defined($SubArgs{"\\$originalName"})
				  && $SubArgs{"\\$originalName"} eq $kByValue )
					{
					$shouldPassByValue{"\\$originalName"} = $newDerefName;
					$byValueDerefKey{"\\$originalName"} = "\\$derefName";
					$byValueRefKey{"\\$originalName"} = "\\\\$originalName";
					}
				$finalText .= "$lines[$idx++]\n";
				}
			else # just skip along, param isn't wanted
				{
				++$idx;
				}
			}
		else
			{
			$finalText .= "$lines[$idx++]\n";
			}
		}
	
	# Copy arrays and hashes if pass by value wanted (also remove from
	# the replacement hashes).
	my $numKeys = keys %shouldPassByValue;
	if ($numKeys)
		{
		$finalText .= "\n"; # Needed elsewhere when parsing, don't delete.
		foreach my $arg (sort keys %shouldPassByValue)
			{
			my $noSlashArg = substr($arg, 1);
			my $copyLine = "\tmy $noSlashArg = @" . $shouldPassByValue{$arg} . ";\n";
			$finalText .= $copyLine;
			
			delete($repForName{$arg});
			delete($derefRepForName{$byValueDerefKey{$arg}});
			delete($repForRefName{$byValueRefKey{$arg}});
			}
		}
	
	# Replace @x with @$xA or @$xH, $x with $xA-> or $xH->.
	# Unless pass by value was wanted.
	for ( ; $idx < $numLines; ++$idx)
		{
		foreach my $refOriginalName (keys %repForRefName)
			{
			if ($lines[$idx] =~ m!$refOriginalName\b!)
				{
				$lines[$idx] =~ s!$refOriginalName\b!$repForRefName{$refOriginalName}!g;
				}
			}
		foreach my $originalName (keys %repForName)
			{
			if ($lines[$idx] =~ m!$originalName\b!)
				{
				$lines[$idx] =~ s!$originalName\b!$repForName{$originalName}!g;
				}
			}
		foreach my $derefName (keys %derefRepForName)
			{
			if ($lines[$idx] =~ m!$derefName\b!)
				{
				$lines[$idx] =~ s!$derefName\b!$derefRepForName{$derefName}!g;
				}
			}
		$finalText .= "$lines[$idx]\n";
		}
		
	return $finalText;
	}

# Build up a <form> for setting parameter pass type and setting sub name. 
sub ExtractDialog {
	my ($rawText) = @_;
	
	my @ArgType = ($kByValue, $kByReference, $kOmit);
	
	my @lines = split(/\n/, $rawText);
	my $numLines = @lines;
	my $idx = 0;
	
	# Skip down to args.
	while ($idx < $numLines && $lines[$idx] !~ m!^\tmy!
		   && $lines[$idx] ne $PARAM_GUARD)
		{
		++$idx;
		}
	
	# Record arg names. Scalars have already been noted
	# by fix_scalar_references().
	while ($idx < $numLines && $lines[$idx] =~ m!^\tmy!
		   && $lines[$idx] ne $PARAM_GUARD)
		{
		if ($lines[$idx] =~ m!^\tmy\s+(\S+)!)
			{
			my $arg = $1;
			if (!defined($SubArgs{"\\$arg"}))
				{
				my $arrayOrHash = ($arg =~ m!(\@|\%)!);
				$SubArgs{"\\$arg"} = $arrayOrHash ? $kByReference: $kByValue;
				}
			}
		++$idx;
		}
	
	my $numArgs = keys %SubArgs;
	
	my $column = 1;
	my $dlg = StartParamDialog();
	
	# Put params in result, add a field to set sub name
	if ($numArgs)
		{
		$dlg .= StartParams();
		my $numParamsSoFar = 0;
		my $newColumnAtThisIndex = ($numArgs >= 20)? int($numArgs/2): -1;
		foreach my $arg (sort keys %SubArgs)
			{
			if ($numParamsSoFar++ == $newColumnAtThisIndex)
				{
				++$column;
				}
			$dlg .= AddParam($column, $arg, $SubArgs{$arg}, \@ArgType);
			}
		$dlg .= EndParams();
		$dlg .= AddSubName($column, "Sub Name", $SubName);
		}
	else # just the sub name field
		{
		$dlg .= AddSubName($column, "Sub Name:", $SubName);
		}
	
	$dlg .= EndParamDialog();
	
	return($dlg);
	}

sub StartParamDialog {
	my $dialogStart = <<"FINIS";
<form class="form-container" id="ftsform" method="get" action=_ACTION_ onsubmit="paramFormSubmit(this); return false;">
FINIS
	my $serverAddr = ServerAddress();
	my $action = "http://$serverAddr:$port_listen/$SHORTNAME/extract/?rddm=1";
	$dialogStart =~ s!_ACTION_!\'$action\'!;
	
	return($dialogStart);
	}

sub EndParamDialog {
	my $dialogEnd = <<"FINIS";
<div class="toTheRight"><input id="extractButton" class="submit-button" type="submit" value="Extract" /></div>
</form>\n
FINIS
	
	return($dialogEnd);
	}


sub StartParams {
	my $paramStart = "<div id='params'>\n<table class='paramTable'>";
	
	return($paramStart);
	}


sub EndParams {
	my $paramEnd = "</table></div>\n";
	
	return($paramEnd);
	}


sub AddParam {
	my ($column, $varName, $defaultPass, $argTypeA) = @_;
	$varName = substr($varName, 1);
	
	my $param = "<tr><td class='toTheRight'><strong>$varName</strong>:</td><td><select name='$varName' id='$varName'>\n";
	
	my $numOptions = @$argTypeA;
	for (my $i = 0; $i < $numOptions; ++$i)
		{
		if ($argTypeA->[$i] eq $defaultPass)
			{
			$param .= "<option value='$argTypeA->[$i]' selected='selected'>$argTypeA->[$i]</option>\n";
			}
		else
			{
			$param .= "<option value='$argTypeA->[$i]'>$argTypeA->[$i]</option>\n";
			}
		}
	
	$param .= "</select></td></tr>\n";
	
	return($param);
	}


sub AddSubName {
	my ($column, $fieldTitle, $defaultName) = @_;
	my $subName = <<"FINIS";
<p></p><strong>_TITLE_</strong>: <input id="subname" class="form-field" type="text" name="subname" value="_VALUE_" /></div>
FINIS
	$subName =~ s!_TITLE_!$fieldTitle!;
	$subName =~ s!_VALUE_!$defaultName!;
	
	return($subName);
	}

# Respond to '/extract/' request. See also extract_method.js#paramFormSubmit()
# which is called when the param form's "Extract" button is clicked.
# Input: original code in $formH->{'contents'},
# new sub name in $formH->{'PARAM_subname'},
# and pass type for params in $formH->{'PARAM_varname'}
# (eg $formH->{'PARAM_$somevar'} == 'By value').
# This repeats some of the processing above, in particular extract_method(),
# using the original code as passed back to us here when the "Extract"
# button on the web page was clicked. Redundant, but it keeps us
# stateless.
# Returns: example sub call, blank line, extracted sub as one string.
sub CreateNewMethod {
	my ($obj, $formH, $peeraddress) = @_;
	
	# Make the Status light flash for this server.
	ReportActivity($SHORTNAME);
	
	%SubArgs = ();
	%IsScalarArg = ();
	
	my $code = $formH->{'contents'}; # Original code wanting extraction.
	
	# Promote any initial comment lines to the top of the new sub.
	my ($codeExComments, $topComments) = cut_top_comments($code);
	
	# Do the basic extraction, all args passed by value at this stage.
	my $extracted = extract_method($codeExComments, 1);
	
	# Examine scalars, to determine whether default should be pass
	# by value or pass by reference.
	set_scalar_defaults($extracted, 1); # 1 == decode
	
	GetArgNames($extracted);
	
	# Params
	foreach my $key (keys %$formH)
		{
		if ($key =~ m!^PARAM_(.+?)$!)
			{
			my $paramName = $1;
			$paramName = uri_unescape($paramName);
			$paramName = decode('UTF-8',$paramName);
			$paramName = "\\" . $paramName;
			my $passType = $formH->{$key};
			
			if (defined($SubArgs{$paramName}))
				{
				$passType = uri_unescape($passType);
				$passType = decode('UTF-8',$passType);
				$SubArgs{$paramName} = $passType;
				}
			elsif ($key eq 'PARAM_subname')
				{
				my $updatedSubName = $formH->{$key};
				set_default_sub_name($updatedSubName);
				}
			}
		}
	
	# Scalar params, default is by reference if changed in our new sub.
	my $withFixedScalarRefs = fix_scalar_references($extracted);
	
	# Array and hash params, default is pass by reference.
	my $withFixedAHRefs = fix_array_hash_references($withFixedScalarRefs);
	
	# Clean up the param declaration lines at the top of the sub.
	my $withCleanArgLine = cleanup_param_decls($withFixedAHRefs);
	
	# Update the new sub's name, in case it was changed in the dialog.
	my $withSubName = update_sub_name($withCleanArgLine);
	
	# Poke in the new sub's comments just above it.
	my $finalExtracted = insert_top_comments($withSubName, $topComments);
	
	$finalExtracted = RemoveParamGuard($finalExtracted);
	

	$finalExtracted = encode_utf8($finalExtracted);
	
	return($finalExtracted);
	}

# Put entries in %SubArgs for parameters.
# Side note, this sub was extracted by this program:)
sub GetArgNames {
	my ($extracted) = @_;

	my @ArgType = ($kByValue, $kByReference, $kOmit);
	
	my @lines = split(/\n/, $extracted);
	my $numLines = @lines;
	my $idx = 0;
	
	# Skip down to args.
	while ($idx < $numLines && $lines[$idx] !~ m!^\tmy!)
		{
		++$idx;
		}
	
	# Record arg names. Scalars have already been noted
	# by fix_scalar_references().
	while ($idx < $numLines && $lines[$idx] =~ m!^\tmy!)
		{
		if ($lines[$idx] =~ m!^\tmy\s+(\S+)!)
			{
			my $arg = $1;
			
			if (!defined($SubArgs{"\\$arg"}))
				{
				my $arrayOrHash = ($arg =~ m!(\@|\%)!);
				$SubArgs{"\\$arg"} = $arrayOrHash ? $kByReference: $kByValue;
				}
			}
		++$idx;
		}
	}

# Remove the $PARAM_GUARD line. Also remove the following line
# if it is blank and the preceding line doesn't start with "my".
# A bit tedious removing the blank line, but it's The Apple Way:)
sub RemoveParamGuard {
	my ($rawText) = @_;
	my $finalText = '';
	my @lines = split(/\n/, $rawText);
	my $numLines = @lines;
	my $justSawParamGuard = 0;
	
	$finalText = $lines[0];
	for (my $i = 1; $i < $numLines; ++$i)
		{
		if ($lines[$i] ne $PARAM_GUARD)
			{
			# Skip blank line after $PARAM_GUARD
			if ($justSawParamGuard)
				{
				if ($lines[$i] ne '' || $i < 2 || $lines[$i-2] =~ m!^\s*my\s+!)
					{
					$finalText .= "\n$lines[$i]";
					}
				}
			else
				{
				$finalText .= "\n$lines[$i]";
				}
			$justSawParamGuard = 0;
			}
		else
			{
			$justSawParamGuard = 1;
			}
		}
	
	return($finalText);
	}
} ##### Scope for %SubArgs etc.