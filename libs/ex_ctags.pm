# ex_ctagsex_ctags.pm: interface to universal ctags with support for table of contents
# for various languages. See toc_local.pm for example usage. 

package ex_ctags;
require Exporter;
use Exporter qw(import);

use strict;
use warnings;
use utf8;
use Win32::Process; # for calling Universal ctags.exe
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use win_wide_filepaths;

{ ##### Universal Ctags Support
# Ctags is used to generate a list of tags and their locations in
# a source file, which in turn is used to generate a table of contents.

my $port_listen;
my $LogDir;
my $CtagsOutputFilePathBase;
my $CtagsOutputFilePath;
my $CTAGS_DIR;
my $CTAGS_EXE;
my %SupportedExtension; # eg $SupportedExtension{'cpp'} = 'C++';

sub InitExCtags {
	my ($firstPartOfPath, $portListen, $logDir, $ctags_dir) = @_;
	$port_listen = $portListen;
	$LogDir = $logDir;
	my $port = $port_listen;
	$CtagsOutputFilePathBase = $firstPartOfPath . '_' . $port;
	#$CTAGS_DIR = CVal('CTAGS_DIR');
	$CTAGS_DIR = $ctags_dir;
	$CTAGS_DIR =~ s!\\!/!g;
	$CTAGS_DIR =~ s!/$!!g;
	$CTAGS_EXE = $CTAGS_DIR . '/ctags.exe';

	if (!(-f $CTAGS_EXE))
		{
		die("ex_ctags.pm InitCtags error, terminating, could not find universal ctags.exe in |$CTAGS_DIR|! Did you set CTAGS_DIR in /data/intramine_config.txt?");
		}
	GetCTagSupportedTypes();
	}

# eg $SupportedExtension{'cpp'} = 'C++';
sub GetCTagSupportedTypes {
	my $theTypes = <<'FINIS';
Ada      *.adb *.ads *.Ada *.ada
Ant      *.ant
Asciidoc *.asc *.adoc *.asciidoc *.asc *.adoc *.asciidoc
Asm  *.A51 *.29k *.29K *.68k *.68K *.86k *.86K *.88k *.88K *.68s *.68S *.86s *.86S *.88s *.88S *.68x *.68X *.86x *.86X *.88x *.88X *.x86 *.x68 *.x88 *.X86 *.X68 *.X88 *.asm *.ASM
Asp      *.asp *.asa
Autoconf *.ac
AutoIt   *.au3 *.AU3 *.aU3 *.Au3
Automake *.am
Awk      *.awk *.gawk *.mawk
Basic    *.bas *.bi *.bb *.pb
BETA     *.bet
Clojure  *.clj *.cljs *.cljc
CMake    *.cmake
C        *.c
C++      *.c++ *.cc *.cp *.cpp *.cxx *.h *.h++ *.hh *.hp *.hpp *.hxx *.inl
CSS      *.css
C#       *.cs
Ctags    *.ctags
Cobol    *.cbl *.cob *.CBL *.COB
CUDA     *.cu *.cuh
D        *.d *.di
Diff     *.diff *.patch
DTD      *.dtd *.mod
DTS      *.dts *.dtsi
DosBatch *.bat *.cmd
Eiffel   *.e
Elm      *.elm
Erlang   *.erl *.ERL *.hrl *.HRL
Falcon   *.fal *.ftd
Flex     *.as *.mxml
Fortran  *.f *.for *.ftn *.f77 *.f90 *.f95 *.f03 *.f08 *.f15
Fypp     *.fy
Gdbinit  .gdbinit *.gdb
Go       *.go
Haskell       *.hs
HTML     *.htm *.html
Iniconf  *.ini *.conf
ITcl     *.itcl
Java     *.java
JavaProperties *.properties
JavaScript *.js *.jsx
JSON     *.json
Julia     *.jl
LdScript *.lds *.scr *.ld
Lisp     *.cl *.clisp *.el *.l *.lisp *.lsp
Lua      *.lua
M4       *.m4 *.spt
Man      *.1 *.2 *.3 *.4 *.5 *.6 *.7 *.8 *.9 *.3pm *.3stap *.7stap
Make     *.mak *.mk
Markdown *.md *.markdown
MatLab   *.m
Myrddin  *.myr
ObjectiveC *.mm *.m *.h
OCaml    *.ml *.mli *.aug
Pascal   *.p *.pas
Perl     *.pl *.pm *.ph *.plx *.perl
Perl6    *.p6 *.pm6 *.pm *.pl6
PHP      *.php *.php3 *.php4 *.php5 *.php7 *.phtml
Pod      *.pod
Protobuf *.proto
PuppetManifest *.pp
Python   *.py *.pyx *.pxd *.pxi *.scons *.wsgi
QemuHX   *.hx
R        *.r *.R *.s *.q
REXX     *.cmd *.rexx *.rx
Robot    *.robot
RpmSpec  *.spec
ReStructuredText *.rest *.reST *.rst
Ruby     *.rb *.ruby
Rust     *.rs
Scheme   *.SCM *.SM *.sch *.scheme *.scm *.sm
Sh       *.sh *.SH *.bsh *.bash *.ksh *.zsh *.ash
SLang    *.sl
SML      *.sml *.sig
SQL      *.sql
SystemdUnit *.unit *.service *.socket *.device *.mount *.automount *.swap *.target *.path *.timer *.snapshot *.scope *.slice *.time
Tcl      *.tcl *.tk *.wish *.exp
Tex      *.tex
TTCN     *.ttcn *.ttcn3
TypeScript  *.ts
Vera     *.vr *.vri *.vrh
Verilog  *.v
SystemVerilog *.sv *.svh *.svi
VHDL     *.vhdl *.vhd
Vim      *.vim *.vba
WindRes  *.rc
YACC     *.y
YumRepo  *.repo
Zephir   *.zep
DBusIntrospect *.xml
Glade    *.glade
Maven2   pom.xml *.pom *.xml
PlistXML *.plist
RelaxNG  *.rng
SVG      *.svg
XSLT     *.xsl *.xslt
Yaml     *.yml
FINIS

	my @typeLines = split(/\n/, $theTypes);
	my $numTypes = @typeLines;
	for (my $i = 0; $i < $numTypes; ++$i)
		{
		my @typeExt = split(/ +/, $typeLines[$i]);
		my $lang = $typeExt[0];
		my $numEntries = @typeExt;
		for (my $j = 1; $j < $numEntries; ++$j)
			{
			my $ext = lc($typeExt[$j]);
			$ext =~ s!^\*\.!!;
			$SupportedExtension{$ext} = $lang;
			}
		}
	}

sub IsSupportedByCTags {
	my ($filePath) = @_;
	my $result = 0;
	if ($filePath =~ m!\.(\w+)$!)
		{
		my $fileExt = lc($1);
		if (defined($SupportedExtension{$fileExt}))
			{
			$result = 1;
			}
		}
	
	return($result);
	}

# Call Universal Ctags to generate ctags for $dir . $fileName, to a temp file that only
# one instance of this server uses. Wait until done, then return path to the ctags temp file.
# LIMITATION this does not work as quickly as it could if $fileName or $dir contain "unicode" characters,
# since an entire temp copy of the file is made, with a plain ascii name. A better workaround would be
# to use Win32::API to import CreateProcessW, but I'm just not up to it today. Sorry.
sub MakeCtagsForFile {
	my ($dir, $fileName, $errorMsgR) = @_;
	my $result = '';
	my $tempFilePath = '';
	my $tempDir = '';
	my $proc;
	
	# Trouble with "wide" file names. Towards a workaround, copy the file being processed to
	# something temp with a "narrow" name.
	my $haveWideName = 0;
	if ($fileName =~ m![^\x00-\x7f]! || $dir =~ m![^\x00-\x7f]!)
	# WRONG if ($fileName =~ m![\x80-\xFF]! || $dir =~ m![\x80-\xFF]!)
		{
		$haveWideName = 1;
		}
	
	if ($haveWideName)
		{
		my $ext = '';
		if ($fileName =~ m!\.(\w+)$!)
			{
			$ext = $1;
			}
		my $randomInteger = random_int_between(1001, 60000);
		$tempFilePath = 'temp_code_copy_' . $port_listen . time . $randomInteger . ".$ext";
		$tempDir = $LogDir . 'temp/';
		#print("Copying |$dir$fileName| to |$tempDir$tempFilePath|\n");
		if (CopyFileWide($dir . $fileName, $tempDir . $tempFilePath, 0))
			{
			#print("Making ctags\n");
			my $randomInteger2 = random_int_between(1001, 60000);
			$CtagsOutputFilePath = $CtagsOutputFilePathBase . time . $randomInteger2 . '.txt';
			# -numeric -unsorted tags, using -f output path.
			my $didit = Win32::Process::Create($proc, $CTAGS_EXE, " --quiet=yes -n -u -f \"$CtagsOutputFilePath\" \"$tempFilePath\"", 0, 0, $tempDir);
			if (!$didit)
				{
				my $status = Win32::FormatMessage( Win32::GetLastError() );
				$$errorMsgR = "MakeCtagsForFile Error |$status|, could not run $CTAGS_EXE!";
				return($result);
				}
			$proc->Wait(INFINITE);
			$result = $CtagsOutputFilePath;
			#unlink($tempFilePath); too soon, sometimes - for unlink see GetCTagsTOCForFile();
			}
		}
	else
		{
		my $randomInteger = random_int_between(1001, 60000);
		$CtagsOutputFilePath = $CtagsOutputFilePathBase . time . $randomInteger . '.txt';
		# -numeric -unsorted tags, using -f output path.
		my $didit = Win32::Process::Create($proc, $CTAGS_EXE, " --quiet=yes -n -u -f \"$CtagsOutputFilePath\" \"$fileName\"", 0, 0, $dir);
		if (!$didit)
			{
			my $status = Win32::FormatMessage( Win32::GetLastError() );
			$$errorMsgR = "MakeCtagsForFile Error |$status|, could not run $CTAGS_EXE!";
			return($result);
			}
		$proc->Wait(INFINITE);
		$result = $CtagsOutputFilePath;
		}
	
	return($result, $tempDir . $tempFilePath);
	}

# Call universal ctags, output piped back to $$resultR with backticks.
# Oddly the default output is not STDOUT, the "-f -" is needed for that.
sub GetCtagsString {
	my ($filePath, $resultR) = @_;
	my $ctagsArgs = " -f - --quiet=yes -n -u \"$filePath\"";
	$$resultR = `$CTAGS_EXE $ctagsArgs`;
	}

#http://ctags.sourceforge.net/FORMAT
#PropertyGetterSetter	qqmljsast_p.h	682;"	c	namespace:QQmlJS::AST
#PropertyGetterSetter	qqmljsast_p.h	696;"	f	class:QQmlJS::AST::PropertyGetterSetter
#tagname}<Tab>{tagfile}<Tab>{tagaddress
#tagname tab sourcefile tab \d+ not-tab tab c or f tab not-colon to the end for 'f' is the owning class, ignore trailer if 'c'
# - technically that not-tab is ;"
# - there can be other "kinds" besides c or f, ignore them
# - mind you, need to check struct, and <template> files
# That incoherent preamble was brought to you by caffeine.
# Ahem: go through a ctags file and pick out entries that declare classes and methods. Poke
# those into hashes, indexed by line number.
# (In progress, individual language are being addressed in order to
# generate more accurate tables of contents.)
sub LoadCtags {
	my ($filePath, $tagStringR, $classEntryForLineH, $structEntryForLineH, $methodEntryForLineH, $functionEntryForLineH, $errorMsgR) = @_;
	my $itemCount = 0;
	$$errorMsgR = '';

	my @lines = split(/\n/, $$tagStringR);
	my $numLines = @lines;
	
	# Per-language regex's to extract tags:
	if ($filePath =~ m!\.ts$!i)
		{
		$itemCount = LoadTypeScriptTags(\@lines, $classEntryForLineH, $structEntryForLineH, $methodEntryForLineH, $functionEntryForLineH);
		}
	elsif ($filePath =~ m!\.java$!i)
		{
		$itemCount = LoadJavaTags(\@lines, $classEntryForLineH, $structEntryForLineH, $methodEntryForLineH, $functionEntryForLineH);
		}
	elsif ($filePath =~ m!\.rs$!i)
		{
		$itemCount = LoadRustTags(\@lines, $classEntryForLineH, $structEntryForLineH, $methodEntryForLineH, $functionEntryForLineH);
		}
	elsif ($filePath =~ m!\.(rb|ruby)$!i)
		{
		$itemCount = LoadRubyTags(\@lines, $classEntryForLineH, $structEntryForLineH, $methodEntryForLineH, $functionEntryForLineH);
		}
	elsif ($filePath =~ m!\.cs$!i)
		{
		$itemCount = LoadCSharpTags(\@lines, $classEntryForLineH, $structEntryForLineH, $methodEntryForLineH, $functionEntryForLineH);
		}
	elsif ($filePath =~ m!\.jl$!i)
		{
		$itemCount = LoadJuliaTags(\@lines, $classEntryForLineH, $structEntryForLineH, $methodEntryForLineH, $functionEntryForLineH);
		}
	else # Default class/struct/function handling
		{
		for (my $i = 0; $i < $numLines; ++$i)
			{
			# selectUrl\tqfiledialog.cpp\t1085;"\tf\tclass:QFileDialog\ttyperef:typename:void
			if ($lines[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([csf])\t[^:]+:([^\t]+)\t[^\t]+$!)
				{
				my $tagname = $1;
				my $lineNumber = $2;
				my $kind = $3;
				my $owner = $4;
				if ($kind eq 'c')
					{
					$classEntryForLineH->{"$lineNumber"} = $tagname;
					++$itemCount;
					}
				elsif ($kind eq 's')
					{
					$structEntryForLineH->{"$lineNumber"} = $tagname;
					++$itemCount;
					}
				elsif ($kind eq 'f')
					{
					$methodEntryForLineH->{"$lineNumber"} = $owner . '::' . $tagname;
					# Experiment, put methods in the $classEntryForLineH hash, to group
					# methods under the owning class/interface. This doesn't work
					# for C++, there is typically no owning class entry in the .cpp file.
					#$classEntryForLineH->{"$lineNumber"} = $owner . '::' . $tagname;
					++$itemCount;
					}
				# else $kind eq 'e' for enum etc - ignore
				}
			# qt_tildeExpansion\tqfiledialog.cpp\t1100;"\tf\ttyperef:typename:Q_AUTOTEST_EXPORT QString
			elsif ($lines[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([csf])!) # no class or namespace specifier
				{
				my $tagname = $1;
				my $lineNumber = $2;
				my $kind = $3;
				if ($kind eq 'c')
					{
					$classEntryForLineH->{"$lineNumber"} = $tagname;
					++$itemCount;
					}
				elsif ($kind eq 's')
					{
					$structEntryForLineH->{"$lineNumber"} = $tagname;
					++$itemCount;
					}
				elsif ($kind eq 'f')
					{
					# A small nuisance, don't list nested functions (eg in JavaScript) separately.
					# A regular entry ends in 'f', a nested entry is followed by 'function:'.
					if ($lines[$i] !~ m!\t+f\t+function\:!)
						{
						#$topScopeFunctionName = $tagname;
						$methodEntryForLineH->{"$lineNumber"} = $tagname;
						}
					# This is out mainly because the ctags parser returns nested functions before
					# the enclosing function, and seems to miss some nested functions too.
	#				else
	#					{
	#					$methodEntryForLineH->{"$lineNumber"} = "$topScopeFunctionName.$tagname";
	#					$methodNameForLineH->{"$lineNumber"} = $tagname;
	#					# TEST ONLY codathon
	#					print("N: |$lines[$i]|\n");
	#					}
						
					++$itemCount;
					}
				# else $kind eq 'e' for enum etc - ignore
				}
			}
		}
	
	return($itemCount);
	}

# Get tag hashes of class/interface/method/function entries from lines in a TypeScript
# file. Note struct is ignored.
# Return count of all tags.
sub LoadTypeScriptTags {
	my ($linesA, $classEntryForLineH, $structEntryForLineH, 
		$methodEntryForLineH, $functionEntryForLineH) = @_;
	my $itemCount = 0;
	my $numLines = @{$linesA};
	
	for (my $i = 0; $i < $numLines; ++$i)
		{
		# Eg (function, function, class, method, interface):
		# isDeclarationFileInJSOnlyNonConfiguredProject	session.ts	23;"	f	namespace:ts.server
		# formatMessage	session.ts	130;"	f	namespace:ts.server
		# MultistepOperation	session.ts	166;"	c	namespace:ts.server
		# immediate	session.ts	188;"	m	class:ts.server.MultistepOperation
		# PendingErrorCheck	session.ts	113;"	i	namespace:ts.server
		if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cfmi])\t([^\t]+)$!
			|| $linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cfmi])$!)
		#if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cfmi])\t([^\t]+)$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			my $owner = defined($4)? $4: '';

			if ($kind eq 'c' || $kind eq 'i')
				{
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'm')
				{
				my $class = $owner;
				my $lastPeriodPos = rindex($class, '.');
				if ($lastPeriodPos >= 0)
					{
					$class = substr($class, $lastPeriodPos + 1);
					}
				my $lastColonPos = rindex($class, ':');
				if ($lastColonPos >= 0)
					{
					$class = substr($class, $lastColonPos + 1);
					}
				# Revision, put methods in the $classEntryForLineH hash, to group
				# methods under the owning class/interface.
				#$methodEntryForLineH->{"$lineNumber"} = $class . '::' . $tagname;
				$classEntryForLineH->{"$lineNumber"} = $class . '::' . $tagname;
				}
			elsif ($kind eq 'f')
				{
				$functionEntryForLineH->{"$lineNumber"} = $tagname;
				}
			++$itemCount;
			}
		}
	
	return($itemCount);
	}

# Get tag hashes of class/interface/method entries for a Java file.
# Return count of all tags.
sub LoadJavaTags {
	my ($linesA, $classEntryForLineH, $structEntryForLineH, 
		$methodEntryForLineH, $functionEntryForLineH) = @_;
	my $itemCount = 0;
	my $numLines = @{$linesA};
	
	for (my $i = 0; $i < $numLines; ++$i)
		{
		# Trailing scope.
		# ResponseContext	Transport.java	154;"	c	interface:Transport
		# getNetworkMessageSize	Header.java	40;"	m	class:Header
		# Connection	Transport.java	92;"	i	interface:Transport
		# getNode	Transport.java	96;"	m	interface:Transport.Connection
		if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cmi])\t([^\t]+)$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			my $owner = $4;
			
			# Strip "interface" or "class" from start of $owner.
			my $colonPos = index($owner, ':');
			if ($colonPos > 0)
				{
				$owner = substr($owner, $colonPos + 1);
				}

			if ($kind eq 'c' || $kind eq 'i')
				{
				if ($owner ne '')
					{
					$tagname = $owner . '.' . $tagname;
					}
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'm')
				{
				# Put in $class hash, prepend $owner so methods will sort with
				# owner.
				# NOTE using '#' as separator between $owner and $tagname.
				if ($owner ne '')
					{
					$tagname = $owner . '#' . $tagname;
					}
				
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		# No trailing scope.
		# Header	Header.java	20;"	c
		# Transport	Transport.java	35;"	i
		# (I suspect all methods have a trailing scope.)
		elsif ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cfmi])$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			
			if ($kind eq 'c' || $kind eq 'i')
				{
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'm')
				{
				$methodEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		++$itemCount;
		}
	
	return($itemCount);
	}

# Do P method, f function, i interface, s struct.
# Return count of all tags.
sub LoadRustTags {
	my ($linesA, $classEntryForLineH, $structEntryForLineH, 
		$methodEntryForLineH, $functionEntryForLineH) = @_;
	my $itemCount = 0;
	my $numLines = @{$linesA};
	
	for (my $i = 0; $i < $numLines; ++$i)
		{
		#Tag examples
		# Plugin	plugin.rs	21;"	i
		# name	plugin.rs	23;"	P	interface:Plugin
		# Builder	plugin.rs	136;"	s
		# get_menu_ids	tray.rs	23;"	f
		# Trailing scope.
		if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([iPsf])\t([^\t]+)$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			my $owner = $4;
			
			# Strip "interface" or "class" from start of $owner.
			my $colonPos = index($owner, ':');
			if ($colonPos > 0)
				{
				$owner = substr($owner, $colonPos + 1);
				}

			if ($kind eq 's' || $kind eq 'i')
				{
				if ($owner ne '')
					{
					$tagname = $owner . '.' . $tagname;
					}
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'P' || $kind eq 'f')
				{
				# Put in $class hash, prepend $owner so methods will sort with
				# owner.
				# NOTE using '#' as separator between $owner and $tagname.
				if ($owner ne '')
					{
					$tagname = $owner . '#' . $tagname;
					}
				
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		# No trailing scope.
		elsif ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([iPsf])$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			
			if ($kind eq 's' || $kind eq 'i')
				{
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'P' || $kind eq 'f')
				{
				$methodEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		++$itemCount;
		}
	
	return($itemCount);
	}

# Do S singletonMethod, c class, f method, m module. Note ctags doesn't always give
# an owning class or object for a singleton, so those are listed
# as unowned methods at the bottom of the TOC.
# Return count of all tags.
sub LoadRubyTags {
	my ($linesA, $classEntryForLineH, $structEntryForLineH, 
		$methodEntryForLineH, $functionEntryForLineH) = @_;
	my $itemCount = 0;
	my $numLines = @{$linesA};
	
	for (my $i = 0; $i < $numLines; ++$i)
		{
		# Tag examples:
		# wheels	vehicle.rb	16;"	S
		# Floor	floor.rb	2;"	c	module:RubyWarrior
		# initialize	floor.rb	6;"	f	class:RubyWarrior.Floor
		if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([fcSm])\t([^\t]+)$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			my $owner = $4;
			
			# Strip "module" or "class" from start of $owner.
			my $colonPos = index($owner, ':');
			if ($colonPos > 0)
				{
				$owner = substr($owner, $colonPos + 1);
				}

			if ($kind eq 'c' || $kind eq 'S')
				{
				if ($owner ne '')
					{
					# For S, separate $owner and $tagname with '#'
					if ($kind eq 'S')
						{
						$tagname = $owner . '#' . $tagname;
						}
					else
						{
						$tagname = $owner . '.' . $tagname;
						}
					}
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'm')
				{
				if ($owner ne '')
					{
					$tagname = $owner . '.' . $tagname;
					}
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'f')
				{
				# Put in $class hash, prepend $owner so methods will sort with
				# owner.
				# NOTE using '#' as separator between $owner and $tagname.
				if ($owner ne '')
					{
					$tagname = $owner . '#' . $tagname;
					}
				
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		# No trailing scope. (Orphan S singletons show up here.)
		elsif ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([fcSm])$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			
			if ($kind eq 'c')
				{
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'm')
				{
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'f' || $kind eq 'S')
				{
				$methodEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		++$itemCount;
		}
		
	return($itemCount);
	}

# Get tag hashes of c class, m method, p property, s struct, i interface entries for a C# file.
# Return count of all tags.
sub LoadCSharpTags {
	my ($linesA, $classEntryForLineH, $structEntryForLineH, 
		$methodEntryForLineH, $functionEntryForLineH) = @_;
	my $itemCount = 0;
	my $numLines = @{$linesA};
	
	for (my $i = 0; $i < $numLines; ++$i)
		{
		# Trailing scope. C# entries sometimes have a trailing "\tfile:".
		if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cmpsi])\t([^\t]+)((\t\w+\:)?)$!)
		#if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cmpsi])\t([^\t]+)$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			my $owner = $4;
			
			# Strip "interface:" or "class:" from start of $owner.
			my $colonPos = index($owner, ':');
			if ($colonPos > 0)
				{
				$owner = substr($owner, $colonPos + 1);
				}

			if ($kind eq 'c' || $kind eq 'i' || $kind eq 's')
				{
				if ($owner ne '')
					{
					$tagname = $owner . '.' . $tagname;
					}
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'm' || $kind eq 'p')
				{
				# Put in $class hash, prepend $owner so methods will sort with
				# owner.
				# NOTE using '#' as separator between $owner and $tagname.
				if ($owner ne '')
					{
					$tagname = $owner . '#' . $tagname;
					}
				
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		# No trailing scope.
		# Header	Header.java	20;"	c
		# Transport	Transport.java	35;"	i
		# (I suspect all methods have a trailing scope.)
		elsif ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([cmpsi])$!)
			{
			my $tagname = $1;
			my $lineNumber = $2;
			my $kind = $3;
			
			if ($kind eq 'c' || $kind eq 'i' || $kind eq 's')
				{
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'm' || $kind eq 'p')
				{
				$methodEntryForLineH->{"$lineNumber"} = $tagname;
				}
			}
		++$itemCount;
		}
	
	return($itemCount);
	}

# Get tag hashes of n module s struct f function entries for a Julia file.
# Some functions can belong to modules such as Base that are not present
# in the file - dummy entries are inserted for Base etc if needed.
# Note a '!' can be part of a function name.
# Return count of all tags.
sub LoadJuliaTags {
	my ($linesA, $classEntryForLineH, $structEntryForLineH, 
		$methodEntryForLineH, $functionEntryForLineH) = @_;
	my $itemCount = 0;
	my $numLines = @{$linesA};
	
	my $module = ''; # The module name for the file.
	
	for (my $i = 0; $i < $numLines; ++$i)
		{
		if ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([nsf])\t([^\t]+)((\t\w+\:)?)$!)
			{
			my $tagname = $1; 		# NOTE may include '!'
			my $lineNumber = $2;
			my $kind = $3;
			my $owner = $4;
			
			# Strip "module:" from start of $owner.
			my $colonPos = index($owner, ':');
			if ($colonPos > 0)
				{
				$owner = substr($owner, $colonPos + 1);
				}

			if ($kind eq 'n')
				{
				if ($owner ne '')
					{
					$tagname = $owner . '.' . $tagname;
					}
				$classEntryForLineH->{"$lineNumber"} = $tagname;				
				}
			elsif ($kind eq 's')
				{
				if ($owner ne '')
					{
					$tagname = $owner . '.' . $tagname;
					}
				$structEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 'f')
				{
				$classEntryForLineH->{"$lineNumber"} = $owner . '#' . $tagname;
				}
			}
		elsif ($linesA->[$i] =~ m!^([^\t]+)\t[^\t]+\t(\d+)[^\t]+\t([nsf])$!)
			{
			my $tagname = $1; 		# NOTE may include '!'
			my $lineNumber = $2;
			my $kind = $3;
			
			if ($kind eq 'n')
				{
				$module = $tagname;
				$classEntryForLineH->{"$lineNumber"} = $tagname;
				}
			elsif ($kind eq 's')
				{
				# No owner: use $module if there is one.
				my $owner = ($module ne '') ? "$module." : '';
				$structEntryForLineH->{"$lineNumber"} = $tagname . $owner;
				}
			elsif ($kind eq 'f')
				{
				# No owner: use $module if there is one.
				my $owner = ($module ne '') ? "$module#" : '';
				$classEntryForLineH->{"$lineNumber"} = $owner . $tagname;
				}
			}
		++$itemCount;
		}
		
	# In Julia a function can be defined for a module that is not itself
	# defined in the current file. If a module is not defined, poke in
	# an entry for it so that functions can be grouped under it - but
	# the missing module itself will be disabled in the table of contents.
	my %missingModules;
	foreach my $lineNum (keys %{$classEntryForLineH})
		{
		my $value = $classEntryForLineH->{$lineNum};
		my $octoPos = index($value, '#');
		if ($octoPos > 0)
			{
			my $ownerName = substr($value, 0, $octoPos);
			if (!defined($missingModules{$ownerName}) && $ownerName ne $module)
				{
				$missingModules{$ownerName} = 'a' . $lineNum;
				}
			}
		}
	
	foreach my $missingModule (keys %missingModules)
		{
		my $lineNum = $missingModules{$missingModule};
		$classEntryForLineH->{"$lineNum"} = $missingModule;
		}
	
	return($itemCount);
	}

# CSS tags are a mess from the perspective of using them as anchors: there can be several
# defined on one line, characters such as space hash '>' and comma are used. The approach here
# is to replace a run of all but comma with underscores for the actual anchor, trimming off any initial
# period or hash. If there are several tags separated by commas, separate entries are made for
# each (all with the same line number).
# Examples of 	original tab 		vs 				tagEntry for lineNumber:
# 				.form-container h2					form_container_h2
# 				.todo-task > .task-header			todo_task_task-header
#				.first, .second						first|second
sub LoadCssCtags {
	my ($lcCssFileName, $tagStringR, $tagEntryForLineH, $tagDisplayedNameForLineH, $errorMsgR) = @_;
	my $itemCount = 0;
	$$errorMsgR = '';

	my @lines = split(/\n/, $$tagStringR);
	my $numLines = @lines;
	
	for (my $i = 0; $i < $numLines; ++$i)
		{
		if ($lines[$i] =~ m!^(.+?)\s+.+?$lcCssFileName\s+(\d+);!i)
		# if ($lines[$i] =~ m!^(.+?)\s+$lcCssFileName\s+(\d+);!i)
			{
			my $displayedTagname = $1;
			my $lineNumber = $2;
			
			if (index($displayedTagname, ",") > 0) # multiple tags, separate entries for linenum by '|'
				{
				my @tags = split(/,\s*/, $displayedTagname);
				for (my $j = 0; $j < @tags; ++$j)
					{
					$displayedTagname = $tags[$j];
					my $tagname = $displayedTagname;
					$tagname =~ s!^[^A-Za-z0-9_]+!!;
					$tagname =~ s![^A-Za-z0-9_]+!_!g;
					if (defined($tagEntryForLineH->{"$lineNumber"}))
						{
						$tagEntryForLineH->{"$lineNumber"} .= "|$tagname";
						$tagDisplayedNameForLineH->{"$lineNumber"} .= "|$displayedTagname";
						}
					else
						{
						$tagEntryForLineH->{"$lineNumber"} = $tagname;
						$tagDisplayedNameForLineH->{"$lineNumber"} = $displayedTagname;
						}
					}
				}
			else # single tag, but can be multiple entries for the same line number
				{
				my $tagname = $displayedTagname;
				$tagname =~ s!^[^A-Za-z0-9_]+!!;
				$tagname =~ s![^A-Za-z0-9_]+!_!g;
				
				if (defined($tagEntryForLineH->{"$lineNumber"}))
					{
					$tagEntryForLineH->{"$lineNumber"} .= "|$tagname";
					$tagDisplayedNameForLineH->{"$lineNumber"} .= "|$displayedTagname";
					}
				else
					{
					$tagEntryForLineH->{"$lineNumber"} = $tagname;
					$tagDisplayedNameForLineH->{"$lineNumber"} = $displayedTagname;
					}
				}
			}
		}

	$itemCount = keys %$tagDisplayedNameForLineH; # Approximate, but good enough.

	return($itemCount);
	}
} ##### Universal Ctags Support

use ExportAbove;
1;
