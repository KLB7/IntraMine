# gloss2html.pl: see "gloss2html.pl for standalone Gloss files.txt" for more details.

# Convert Gloss files to self-contained HTML. Your Gloss files should have a .txt
# extension, and they will be converted to standalone .html versions.
# Supply a single file path to a Gloss .txt file, or a folder holding all of your
# Gloss files, as an argument to this program. If you want images to be expanded (rather
# than popping up if you hover over a link) supply a second argument of -i or -inline.
# A Gloss file is just a .txt file that uses Gloss for markup, see also Documentation/Gloss.txt for
# additional details. Gloss is a Markdown variant emphasizing minimal overhead, and autolinks.
# "Self contained" means all CSS, JavaScript and even images are jammed into the HTML file,
# leaving no dependencies on other files. See StartHtmlFile() for inlined CSS files,
# and EndHtmlFile() for inlined JS files.
#
#
# How to run
# At a command prompt enter
# perl path/to/gloss2html.pl path two-optional-args
# path: full path to the file or folder you want to convert.
# Optional args:
# -i or -inline: if supplied, images will be shown fully. If not supplied, images
#  will pop up when you hover over a link;
# -h or -hoverGIFs: if supplied, all "gif" images will be "hover" style even if you specify -inline.
# (only .gif is affected)
# Example runline, convert all of IntraMine's text documentation:
# perl C:\perlprogs\IntraMine\gloss2html.pl "C:\perlprogs\IntraMine\Documentation" -i -h
#  (note your paths will likely be different)
#
#
# Your Context folder
#####################
# The folder holding the single file you want to convert, or the folder you supply if
# you want to convert all Gloss files in a folder, is called the "context" folder below.

# Before running
################
# Create a context folder holding the one or more Gloss .txt files that you want to convert.
# Also create an /images/ subfolder if you will have images in your files. If you mention an image
# in your Gloss file, drop a copy of the image in the /images/ subfolder.
#
# Gloss features you can use
###########################
# You can use all of Gloss in your file, except for some restrictions on linking. And most of
# Gloss's automatic features will be there too: a collapsible Table of Contents down the left side,
# highlighting of any word you click or phrase you select in the text itself and in the
# scrollbar, automatic linking (with some restrictions), and image hovers.
# As far as linking goes, you can link to other Gloss files in your Context folder, and images
# in either the Context folder or the Context/images/ subfolder. To link to another Gloss
# file or an image, just mention its name, no partial path is needed. You can put the name in
# quotes if you like. Quotes are optional, even if the file name contains spaces.
# All http:// and https:// links are ok to use.
# You can link to headers in the normal Gloss way, both to headers within a file and to
# headers in another Gloss file in your Context folder. For header links within the same
# file, double quotes *are* needed. For links to other files, including links to a specific
# header in another file, the quotes aren't technically needed, but for readability in the
# original text things do look better if you put those links in double quotes too.
# For all links to other Gloss files, you can use .txt or .html for the extension. For example,
# if you want to link to another Gloss file called "Installing This Thing.txt" you can refer to
# it that way or as "Installing This Thing.html". The quotes aren't needed for file links.
# In both cases the link will be to the HTML version.
# To link to a header, eg "Final steps" in that file, you could use
# "Install instructions.html#Final steps" or "Install instructions.txt#Final steps". The
# quotes aren't needed with such header links, but it's best to use them - otherwise the
# underline for the link will run on into following text, which is unsightly (although the
# link will still work).
# NOTE you should prefer putting internal header mentions in "double quotes", because that's the
# only form that IntraMine's Viewer supports. It used to support #hash mentions, but that proved
# too slow. Here, speed doesn't matter as much.
# All of Gloss's other markup will work: headings, lists, tables etc.
#
# Gloss features that won't work in self-contained HTML files
############################################################
# As mentioned, file linking is restricted to other Gloss files in your Context folder,
# and to the /images/ subfolder. A mention of any file that isn't in your Context folder won't
# produce a link.
# NOTE: A link to another file in your Context folder will be generated only if
# the file name has a .txt or .html or .png/.jpg/.jpeg/.gif/.webp extension.
#
# Additional image locations
############################
# Although the /images/ subfolder is the best location for your images, you can also
# pull in images from IntraMine's /images_for_web_server/ folder, and more importantly
# from your "common" images folder, which by default is C:/Common/Images/.

# Using the resulting HTML files
################################
# Output is one or more .html files, which you can copy anywhere.
# There is no need to copy the /images/ subfolder, all images are inlined in the HTML.
# The original .txt files aren't needed either, of course.
# If you keep your copy of converted HTML files in one folder, then all of their
# links will still work, no matter where you put the folder.

# A suggestion, use the ".txt" versions of file names when referring to other Gloss files in
# your context folder. This program will convert them to the ".html" version. But
# IntraMine won't, so when you're reviewing a .txt Gloss file with IntraMine you'll get an
# Edit link to the ".txt" version, and can click on it if you want to edit the mentioned
# file. When someone views the .html version, they'll get a link to the ".html" version even though
# the file mention in the original text is to the ".txt" version, so your readers will always
# see the correct HTML link. Gah, I need English lessons, help.

# [This program is a stripped-down version of intramine_viewer.pl subs for producing
# text views with links, see intramine_viewer.pl#GetPrettyTextContents() and
# intramine_linker.pl#GetLinksForText().]
#
# Special features
##################
# Table of contents: if you're converting several documents in a folder, you might want a
# table of contents listing all of them, perhaps with section headings.
# For details see "gloss2html.pl for standalone Gloss files.txt#Adding a table of contents file"
# Note you can have a simple look or an "antique" look as described there.
#
# A glossary: if you have special words or phrases that could benefit from a definition
# shown in the document, you can add a glossary without much effort. Terms defined in
# the glossary will show a popup definition when the cursor is paused over the term,
# and terms receive a subtle underline.
# For details see "gloss2html.pl for standalone Gloss files.txt#Adding a glossary"

# Usage examples
# Example cmd lines for a whole folder, and for one file (change the paths!):
# perl C:\perlprogs\IntraMine\gloss2html.pl "C:\perlprogs\IntraMine\Documentation"
# perl C:\perlprogs\IntraMine\gloss2html.pl "C:\perlprogs\IntraMine\Documentation\gloss.txt"
# perl C:\perlprogs\IntraMine\gloss2html.pl "C:\perlprogs\IntraMine\Documentation\Read Me First.txt"
# With images inlined:
# CURRENTLY USED TO GENERATE INTRAMINE'S HTML DOCUMENTATION:
# perl C:\perlprogs\IntraMine\gloss2html.pl "C:\perlprogs\IntraMine\Documentation" -i -h
#
# perl C:\perlprogs\IntraMine\gloss2html.pl -inline "C:\perlprogs\IntraMine\Documentation\gloss.txt"
#
# For txt docs in the _INSTALLER folder:
# perl C:\perlprogs\IntraMine\gloss2html.pl "C:\perlprogs\IntraMine\__START_HERE_INTRAMINE_INSTALLER\1 READ ME FIRST how to install IntraMine.txt" -i -h

# Syntax check:
# perl -c C:\perlprogs\mine\gloss2html.pl

use strict;
use warnings;
use Path::Tiny qw(path);
use lib path($0)->absolute->parent->child('libs')->stringify;
use gloss_to_html;


my $firstArg  = shift @ARGV;
my $secondArg = shift @ARGV;
$secondArg ||= '';
my $thirdArg = shift @ARGV;
$thirdArg ||= '';
die "Please supply a folder or file path!\n" if (not defined $firstArg);

my @args;
push @args, $firstArg;
push @args, $secondArg;
push @args, $thirdArg;

my $fileOrDir    = '';
my $inlineImages = 0;
my $hoverGIFS    = 0;

for (my $i = 0 ; $i < @args ; ++$i)
	{
	if ($args[$i] =~ m!^\-i!)
		{
		$inlineImages = 1;
		}
	elsif ($args[$i] =~ m!^\-h!)
		{
		$hoverGIFS = 1;
		}
	elsif ($args[$i] ne '')
		{
		$fileOrDir = $args[$i];
		}
	}

print("Path to convert: |$fileOrDir|\n");
print("  Inline images: |$inlineImages|\n");
print("     Hover gifs: |$hoverGIFS|\n");

# gloss_to_html.pm#ConvertGlossToHTML() does all the work.
# "undef" as the last argument basically means use print()
# for feedback. If defined, it should send a WebSockets message.
# See intramine_glosser.pl for an example.
ConvertGlossToHTML($fileOrDir, $inlineImages, $hoverGIFS, undef);
