# IntraMine

*Fast search, easy linking, and glossary popups for your Windows source and text files.*


## Correction

IntraMine uses a PowerShell script (bats/foldermonitor.ps1) to speed up file change detection and handle file/folder renames. If you installed IntraMine before August 8 2024 and didn't use the *QUICK INSTALL* there's a chance that foldermonitor.ps1 is blocked from running. To fix that please download the latest IntraMine and see [Unblocking foldermonitor](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/Unblocking%20foldermonitor.html).

## Overview

IntraMine provides browser-accessed Editor, Viewer, and Search services on your intranet that are designed to ease the creation and reading of in-house documentation, and speed up code comprehension. It's for Windows only.

Here are the five top novelties.

Rich [**glossary popups**](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/Glossary%20popups.html) mean you don't have to worry about using a term before it's defined, or interrupt the flow to provide an intrusive paragraph or long comment: hovering over a defined term shows the definition, complete with rich text, tables, images, and clickable links. They're available in all text and source files when using the Viewer or Editor.

[**FLASH links**](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/Gloss.html#Links)[^1] are typically as simple as typing main.go and it becomes the link you want: from a list of all full paths of interest to you, it's the main.go that's nearest to the file where you're typing. You can even link directly to a function, class, or heading, such as main.go#worker() or "IntraMine May 4 2024.txt#Installer stage tracking". Available for all indexed files when using the Viewer or Editor.

IntraMine introduces [**Gloss**](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/Gloss.html), a minimal memorable Markdown variant for your intranet which is tuned for creating in-house documentation, including development logs and the source for fully standalone HTML. Gloss includes FLASH links and glossary popups. And image hovers, which are starting to catch on. And styled text, headings, a synchronized auto-generated table of contents[^2], selection and search result highlighting in the text and down the scroll bar, line numbers, switch from hover images to inlined with one click, a massive English spell checker, and more. Such as unforgettably simple [tables](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/Gloss.html#Tables).

For wider distribution of your documents IntraMine includes [**gloss2html.pl**](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/gloss2html.pl%20for%20standalone%20Gloss%20files.html), a script that converts Gloss-styled text to fully standalone HTML with almost all Gloss features. These are self-contained HTML documents, not MTH, and no support folder is needed.

And you'll have [**sub-second search**](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/Search.html) over up to half a million source and text files, even without specifying a directory or language or extension (but you can).

If you like IntraMine (and you might, it's been under development for more than eight years) pester your favorite IDE's developers and they might add enough of IntraMine's features that you won't need it any more.

## Installation

Grab a copy of IntraMine, open the IntraMine/__START_HERE_INTRAMINE_INSTALLER/ folder and double-click on "1 READ ME FIRST how to install IntraMine.html". You'll be guided through enabling PowerShell, generating the needed install commands by double-clicking on a batch file, and then running the installer by pasting those commands into a PowerShell window. The installer will first ask you to enter a list of folders that are of interest to you, for searching and for building a full paths list, after which you'll be asked to do a couple of small things along the way. At the end IntraMine will be running and you'll see instructions on how to access, stop, and restart IntraMine.

What's installed? [Strawberry Perl](https://strawberryperl.com) with [some modules](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/IntraMine%20initial%20install.html#One%20by%20one), [Elasticsearch](https://www.elastic.co/), [Universal ctags](https://github.com/universal-ctags), and [File Watcher Utilities](https://sourceforge.net/projects/fwutilities).

## Some pictures

_Search results: 125,000 files searched for "FindFileWide", results in 0.09 seconds. No restriction on directory or language. Clicking a link opens the Viewer, clicking on a little pencil icon opens the Editor._
![Search](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/Search1.png)


_Some search hits for "FindFileWide" in a file, seen with IntraMine's Viewer. The hits are in pink, in the text and down the scroll bar. A click on "allEntries" has highlighted all instances in green, in the text and down the scroll bar. There are automatically generated links to a subroutine in another file (intramine_filetree.pl#GetDirsAndFiles()), a specific line in another file (elastic_indexer.pl#101), and a subroutine within the same file (FindFileWide())._
![FindFileWide in a file](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/2020-05-04%2016_22_47-win_wide_filepaths.pm.png)


_A simple glossary popup. The cursor is paused over "FLASH link". Links in the definition are functional._
![Simple glossary popup](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/FLASH_pop.png)


_A glossary popup showing off. This is the popup for "Gloss", IntraMine's Markdown for intranet use._
![Fancy glossary popup](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/gloss1.png)


## Free as in free
If you see a use for IntraMine's FLASH link algorithms etc in your own work, go right ahead: all original work is covered by an UNLICENSE. (Some software included with or used by IntraMine, such as Perl, CodeMirror and Elasticsearch, is covered by separate license agreements.)

## Requirements

 - Windows 10 / 11.
 - IPv4 must be enabled on the PC where IntraMine is installed (this is overwhelmingly the default). IPv6 can be enabled or disabled as you wish.
 - Strawberry Perl 5 version 30 or later (install instructions are included). The "Quick Install" will install version 3.8.
 - roughly 4 GB of RAM for IntraMine (including Elasticsearch).
 - your own source and text files that can change should be attached directly to your IntraMine PC using SATA or USB (locally attached storage). NAS files can be indexed for search and FLASH linking, but changes to them won't be detected, so that's fine for library files but not your own work.
 - IntraMine is for use only on an intranet, and provides no security on its own. If your intranet isn't locked down reasonably well, you might want to pass.

## I'd like more details before diving in please

See [the documentation](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/contents.html).

When you're happy, jump to the [**installation instructions**](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/__START_HERE_INTRAMINE_INSTALLER/1%20READ%20ME%20FIRST%20how%20to%20install%20IntraMine.html).

## Bugs?

If you spot a bug, please do the kindness of sending an email describing it to klb42@proton.me.

Enjoy!

[^1]: Fast Local Automatic Source and text Hyperlinks. Yes, adding "links" is redundant. By the way, with IntraMine you wouldn't have to bounce down and up to read a footnote: instead you'd see an in-context explanation in a popup. I will resist the temptation to call it an ICE pop.

[^2]: A table of contents is currently generated automatically for: Plain text (Gloss), Perl, Pod, C / C++, Go, JavaScript, CSS, Clojure, Erlang, OCaml, PHP, Python, Ruby, TypeScript, Rust, Java, C#, VBScript(.vb), VB.NET(.vbs), Haskell, Julia, Fortran, COBOL.
