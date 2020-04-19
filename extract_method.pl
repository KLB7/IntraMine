# extract_method.pl: "Extract Method" refactoring for Perl, a variation on
# http://www.bofh.org.uk/2006/09/21/crossing-the-rubicon-again
# by Piers Cawley and Jesse Vincent.
# tldr; select Perl code somewhere, Copy it, run this program, Paste into an editor. You get
# a sub for the copied code, and an example call.
#
# This version passes arrays and hashes by reference, and also passes scalars
# by reference if they are set in the body of the new sub.
# And it has a dialog that allows forcing any parameter to be passed
# by value or reference, or omitted altogether (handy for globals).
#
# This is not perfect, partly because the context for the new sub is unknown.
# It's just meant to take most of the pain out of extracting a sub.
# Especially watch out for any plain "return;" statements - you'll only be returning from the new
# sub, not the sub it was called from, so some tuning will be needed. Eg you can return a 0
# or 1 from the new sub, and check that when it's called.
# If the goal of the new sub is to set a variable, you'll find it's passed by reference. You
# might want to rework that, to return the variable instead.
#
# Modules needed from PPM or CPAN:
# Tk::BrowseEntry
#
# Windows
# -------
# The clipboard is used for input and output.
# Setting up:
# - $kTempCodePath just below wants to make a file in C:\temp\, so change that if
#		you'd prefer some other location
# And now, for a typical run:
# - Copy the perl code that will become your new sub
# - run this program (which takes input from the clipboard under Windows)
# - name your sub and tweak your param handling in the dialog that comes up
# - Paste the results in an editor: you get your new sub, preceded by a call line for it.
#
# Unix/Linux
# ----------
# STDIN/OUT is used for input and output.
# Setting up:
# - add a shebang line at the top if you need it
# - see Piers Cawley's article
#	 (http://www.bofh.org.uk/2006/09/21/crossing-the-rubicon-again
#	 and especially https://fsck.com/~jesse/extract)
#	 for details. But basically
# - name your sub and tweak your param handling in the dialog that comes up
# - and you should get your new sub, preceded by a call line for it.
#
# Here's my command line under Windows:
# perl C:\perlprogs\mine\extract_method.pl
#
# Syntax check:
# perl -c C:\perlprogs\mine\extract_method.pl

use warnings;
use strict;
use File::Path;
use FileHandle;

my $kWINDOWS;
BEGIN {
	# 1 == Windows, 0 == Linux or other
	$kWINDOWS = ($^O =~ m!win!i)? 1: 0;				
	if ($kWINDOWS == 1)
		{
		use Win32::Clipboard;
		}
	}
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
#use em_dialog;
use ArgYouMeant;

select((select(STDOUT), $|=1)[0]);
#print("Test hello hello from em.\n");

# Sometimes the "Extract Sub Particulars" dialog doesn't come to the front under Windows. For these
# cases, pass "1" to this program and it will nudge the user to look for the dialog.
my $beChatty = shift @ARGV;
$beChatty ||= 0;

my $kTempCodePath = $kWINDOWS ? 'C:/temp/extractmethodcode.txt' : '/tmp/extractmethodcode.txt';

# What to do with new sub's arguments:
my $kByValue = 'By value';
my $kByReference = 'By reference';
my $kOmit = 'Omit this one';
my $kReturn = 'Return this one'; # not implemented - hurts my head

# Appended to param names (only scalars passed by value aren't altered):
my $kArraySuffix = '_A';
my $kHashSuffix = '_H';
my $kScalarSuffix = '_R';	# R for Reference

my $CLIP = '';
my $code = '';

if ($kWINDOWS)
	{
	$CLIP = Win32::Clipboard();
	$code = $CLIP->Get();
	}
else
	{
	$code =join('',<STDIN>);
	}

# Promote any initial comment lines to the top of the new sub.
my ($codeExComments, $topComments) = cut_top_comments($code);

# Do the basic extraction, all args passed by value at this stage.
my $extracted = extract_method($codeExComments);

# Examine scalars, to determine whether default should be pass
# by value or pass by reference.
set_scalar_defaults($extracted);

# Show dialog to override whether parameters should be passed
# by value or reference, or omitted. Optionally rename the sub.
show_extract_dialog($extracted);

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

if ($kWINDOWS)
	{
	$CLIP->Set($finalExtracted);
	if ($beChatty)
		{
		print("Done. Your new sub is now on your clipboard, along with a call for it.\n");
		}
	}
else
	{
	print $finalExtracted;
	}

###### subs

sub extract_method {
	my $code = shift;
	write_file($code);
	my $err	 = 1;
	my @args = ();
	
	$kTempCodePath =~ m!^(.+)(/|\\)[^\\/]+$!;
	my $directoryOnPath = $1;
	mkpath($directoryOnPath);
	
	my $loopLimiter = 0; # anti-lock breaking
	while ($err && ++$loopLimiter <= 100)
		{
		$err = 0;
		open( my $perl, "-|", 'perl -c ' . $kTempCodePath . ' 2>&1' )
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
		write_file($code, @args);
		}
	if ($err)
		{
		return("Error, could not extract!\n");
		}
	else
		{
		return codegen($code,'final',@args);
		}
	}

# Requires IO::All, which at the moment (March 2019) isn't included in standard modules
# supplied with ActivePerl.
#sub xwrite_file {
#	my $code = shift;
#	my @args = (@_);
#	codegen($code, 'test', @args) > io($kTempCodePath);
#	}
	
# This version of write_file uses FileHandle, which is included with ActivePerl out of the box.
sub write_file {
	my $code = shift;
	my @args = (@_);
	my $ret = codegen($code, 'test', @args);
	
	my $fileH = FileHandle->new("> $kTempCodePath")
			or die("FILE ERROR could not make $kTempCodePath!");
	print $fileH "$ret";
	close($fileH);
	}

sub codegen {
	my $code = shift;
	my $mode = shift;
	my @args = (@_);

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
		. ( $mode eq 'test' ? "use strict;\n" : '' )
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
		. "\n\n"
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
	my $result = ($lines_R->[$idx] !~ m!^\tmy!);
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
	while ($idx < $numLines && $lines[$idx] =~ m!^\tmy!)
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
my %RunParticulars;
my $SubName;

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
	my ($rawText) = @_;
	my $finalText = '';
	
	my @lines = split(/\n/, $rawText);
	my $numLines = @lines;
	my $idx = 0;
	
	my %scalarArgName;
	my %refNameForScalar;
	
	while ($idx < $numLines && $lines[$idx] !~ m!^\tmy!)
		{
		++$idx;
		}
		
	while ($idx < $numLines && $lines[$idx] =~ m!^\tmy!)
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
	for ( ; $idx < $numLines; ++$idx)
		{
		foreach my $scalarArg (keys %scalarArgName)
			{
			if (   $lines[$idx] =~ m!$scalarArg\s*[.+/*%|&-]?\=[^~]!
				|| $lines[$idx] =~ m!(\+\+|\-\-)$scalarArg\b!
				|| $lines[$idx] =~ m!$scalarArg(\+\+|\-\-)!
				|| $lines[$idx] =~ m!$scalarArg\s*\=~\s*s!
				|| $lines[$idx] =~ m!\\$scalarArg\b! )
				{
				$refNameForScalar{$scalarArg}  = $scalarArgName{$scalarArg} . $kScalarSuffix;
				}
			}
		}

	# set the default handling for the scalar arguments.
	foreach my $scalarArg (keys %scalarArgName)
		{
		if (defined($refNameForScalar{$scalarArg}))
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
			my $copyLine = "\tmy $arg = @" . $shouldPassByValue{$arg} . ";\n";
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

# Dialog to set pass by value or reference or omit for each parameter.
# If there's nothing to set, the dialog is not shown.
sub show_extract_dialog {
	my ($rawText) = @_;

	my @ArgType = ($kByValue, $kByReference, $kOmit);
	
	my @lines = split(/\n/, $rawText);
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
		
	my $numArgs = keys %SubArgs;
	
	if ($numArgs)
		{
		if ($kWINDOWS && $beChatty)
			{
			print("Please visit the \"Extract Sub Particulars\" dialog now (it might not be in front.)\n");
			}
		# Show a nice dialog.
		# Tkx: my $SD = em_dialog->new('Extract Sub Particulars');
		# Tk:
		my $SD = ArgYouMeant->new('Extract Sub Particulars');
		$SD->AddNote("Set sub name, and fine-tune parameter passing. Results to clipboard.");
		
		# OK, we're cheating a bit by storing the sub name in %SubArgs....
		$SD->AddVar("Sub Name:", \$SubName, $SD->String());
		
		my $numParamsSoFar = 0;
		my $newColumnAtThisIndex = ($numArgs >= 20)? int($numArgs/2): -1;
		foreach my $arg (sort keys %SubArgs)
			{
			if ($numParamsSoFar++ == $newColumnAtThisIndex)
				{
				$SD->NewColumn();
				}
			$SD->AddListVariable(substr($arg, 1), \$SubArgs{$arg}, \@ArgType);
			}
		
		$SD->DoDialog();
		}
	}
} ##### Scope for %SubArgs etc.
