# WORK IN PROGRESS, not useful yet.
# toc_local.pm: generate a Table of Contents, and get lists of CSS and JS files,
# for a source file.
#
# perl -c C:\perlprogs\IntraMine\libs\toc_local.pm

use strict;
use warnings;
use utf8;
use Encode;
use Encode::Guess;
use HTML::Entities;
use URI::Escape;
use Text::Tabs;
$tabstop = 4;
use Syntax::Highlight::Perl::Improved ':BASIC';  # ':BASIC' or ':FULL' - FULL
use Time::HiRes qw ( time );
use Win32::Process; # for calling Exuberant ctags.exe
use JSON::MaybeXS qw(encode_json);
use Text::MultiMarkdown; # for .md files
use Path::Tiny qw(path);
use Pod::Simple::HTML;
use lib path($0)->absolute->parent->child('libs')->stringify;
use common;
use win_wide_filepaths;
use ext; # for ext.pm#IsTextExtensionNoPeriod() etc.

# GetCMToc: Get Table of Contents Etc for a source file.
# => $filePath
# <= $toc_R: the Table of Contents
# <= $customCSS_R: CSS for CodeMirror display, codemirror.css etc
# <= $customJS_R: CodeMirror JavaScript, codemirror.js etc.
sub GetCMToc {
	my ($filePath, $toc_R, $customCSS_R, $customJS_R) = @_;
	my $result = 0;	# 1 if Table of Contents generated, 0 if not.
	
	# Processing depends on the file extension, most are handled by
	# exuberant CTags but some are custom.
	# Note not all extensions are supported, eg .pdf, .docx. Only extensions
	# that can be edited with CodeMirror are here. Some, such as .md,
	# can be edited with CM but don't support a Table of Contents.
	
	# (Numbers below are from intramine_viewer.pl#GetContentBasedOnExtension)
	# 2. pure custom with TOC: pl, pm, pod, txt, log, bat, cgi, t.
	if ($filePath =~ m!\.(p[lm]|cgi|t)$!i)
		{
		
		}
	elsif ($filePath =~ m!\.pod$!i)
		{
		
		}
	elsif ($filePath =~ m!\.(txt|log|bat)$!i)
		{
		
		}
	# 3.1 go: CodeMirror for the main view with a custom Table of Contents
	elsif ($filePath =~ m!\.go$!i)
		{
		
		}
	# 3.2 CM with TOC, ctag support: cpp, js, etc, and now including .css
	elsif (IsSupportedByCTags($filePath))
		{
		
		}
	# 4. CM, no TOC: textile, out, other uncommon formats not supported by ctags.
	else
		{
		
		}
	
	return($result);
	}

