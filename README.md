# IntraMine

*Fast search, easy linking, and glossary popups for your Windows source and text files.*

Please note IntraMine must be installed on a PC running Windows 10/11. And the files you want to monitor for changes (to keep your search index and links up to date) must be on drives directly attached to the same PC, though library files can be on NAS.

## In brief

IntraMine is a service suite for developers that is designed to speed up code comprehension and make creation and reading of in-house documentation easier. Access is through your browser, via your intranet on a port of your choosing. The goal is to give you a preview of features that could well end up in your IDE, but many years have gone into making IntraMine useful in its own right.

Here are the main novelties:

* **sub-second search** over hundreds of thousands of files, even without specifying a directory or language or extension (but you can).
* **FLASH links**, for local and network attached storage, type the file name and you have a link to the file you want: for a name like main.cpp, the "closest" one, and in general the theoretical minimum of typing is required.
* **glossary popup definitions** that display in all source and text files when viewed with IntraMine using the Viewer or Editor. Definitions can be richly styled, with images, links, lists, tables etc. Defined words or phrases have a subtle dotted underline, and pausing the cursor over them pops up the definition. Any serious project needs a glossary - why not have one that's easiest to use?
* **Gloss**, a minimal memorable Markdown variant for your intranet which is tuned for creating in-house documentation, including log files and the source for standalone HTML.
* **image hovers**: pause your cursor over an image name to see popup screenshots, whiteboard captures, sketches, UML drawings etc. This one is starting to catch on.

IntraMine also includes:

* a decent **Viewer** (read only) for source and text files supporting all of the above.
* an **Editor** that's very nice for text files such as logs or the source of standalone HTML docs, showing FLASH links and glossary popups, with optional restore if you close without saving.
* **gloss2html.pl** for converting Gloss-styled text to standalone HTML files. Resulting files are eminently suitable for in-house documentation, with styling, a table of contents, glossary popups so you don't have to constantly re-define terms or refer to another document, and almost all Gloss markdown is available (FLASH links are limited to the same folder).


## Some pictures

_Search results: 125,000 files searched for "FindFileWide", results in 0.09 seconds. No restriction on directory or language._
![Search](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/Search1.png)


_Some "FindFileWide" search hits in a file, seen with IntraMine's Viewer. The hits are in pink, in the text and down the scroll bar. A click on "allEntries" has highlighted all instances in green, in the text and down the scroll bar. There are automatically generated links to a subroutine in another file (intramine_filetree.pl#GetDirsAndFiles()), a specific line in another file (elastic_indexer.pl#101), and a subroutine within the same file (FindFileWide())._
![FindFileWide in a file](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/2020-05-04%2016_22_47-win_wide_filepaths.pm.png)


_A simple glossary popup. The cursor is paused over "FLASH link". Links in the definition are functional._
![Simple glossary popup](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/FLASH_pop.png)


_A glossary popup showing off. This is the popup for "Gloss", IntraMine's markdown for intranet use._
![Fancy glossary popup](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/gloss1.png)

## Some details

### Fast system-wide search
[Search](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/Search.html)
IntraMine uses [Elasticsearch](https://www.elastic.co/what-is/elasticsearch) to provide near-instant search of  source and text files that are of interest to you (which could easily number half a million these days), with index updates in five seconds. Search results show links to matching files, with a bit of context around the first hit in each file to give you a better assessment. You can limit searches by language or directory, but there's no need to do that for speed. A picture is above.
 
### A truly nice file Viewer
[Viewer](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/Viewer.html)
View the contents of any source or text file, with search hits highlighted in the text and down the scroll bar if you came from a Search results link.

The Viewer has standard display features such as syntax highlighting, line numbers, and an automatically generated table of contents[^1] down the left. And some extras such as automatic linking (FLASH links, web links, etc), image hovers, and selection highlighting in the text and down the scroll bar. There's a picture up top.

[CodeMirror](https://codemirror.net/) is used as the basis for most displays, with custom views for .txt and Perl files. Gloss (IntraMine's markdown variant) is fully applied to .txt files, and autolinking is applied to all source and text files (except .md).

Glossary popup definitions are available in all source and text files displayed by the Viewer, whether or not the file has been indexed for searching.

### FLASH links
[Links](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/Gloss.html#Links)
For direct attached storage and NAS files, IntraMine implements FLASH links (Fast Local Automatic Source and text Hyperlinks): if you type just a file name such as main.cpp in a text file or a source file, IntraMine will link it to the closest known instance of that file, from amongst all the files of interest to you. Files of interest are contained in the folders that are listed in your data/search_directories.txt file (which you tune up before starting IntraMine the first time). And "closest" means the one that's the fewest number of directory moves up or down away from the file where you're typing. If you want a different instance of a target file, you can add one or more directory names in front of the file name to uniquely identify the one you want: directory names need not be consecutive or in order, and if you need a drive letter put it first.

You can also have links to directories, again with the closest matching instance being selected. Quotes are needed for directory links, but otherwise they work the same way as FLASH links. So to provide a link to the Documentation folder in your project you could type "Documentation" if you're writing in the project, and provide additional directory names if you're writing elsewhere - perhaps "project51/Documentation" if there's only one project51 folder floating around. As with file links, you can leave out intermediate directory names that aren't need to pin down the location, the directory names don't have to be in order, and you can use a drive specifier such as 'c:/project51/change logs', just put it first.

### Image hovers
[Images](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/Gloss.html#Images)
While using IntraMine's Viewer, pause your mouse over an image name and the image pops up. This works in source and text files, no extra typing required, so you can painlessly use screenshots and whiteboard grabs, or UML diagrams for example. Image hovers work best in source files, where displaying the full image would disrupt reading. For documentation, it's often best to display the images fully. The Viewer has a button up top for text files that toggles between hover and full display of images.

### Gloss
[Gloss](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/Gloss.html) is a minimal memorable markdown variant specialized for intranet use (FLASH links, glossary popups, automatic and synchronized table of contents, simple tables, and the other usual stuff you would want for in-house documentation). It's fully implemented by IntraMine's Viewer, and most of it can be used with the included gloss2html.pl program which produces standalone (truly single file) HTML versions of your Gloss-marked text documents. All of IntraMine's documentation was generated with gloss2html.pl.

Here's how to do a simple table in a .txt file with Gloss:
 - type TABLE at the beginning of a line, followed by an optional caption
 - put headings on the next line and data on the following lines, separating cells by one or more tabs
 - and the table ends when there's a line without tabs.

### Glossary popup definitions
[Glossary](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/Glossary%20popups.html)
If your project involves more than just you, a usable glossary isn't just nice to have, it's essential. Now you can have rich popup definitions in all source and text files when displayed with IntraMine's Viewer or Editor. It's easy, see the [glossary_master.txt](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/glossary_master.txt) file at the top of the IntraMine folder for the how-to. The definition format is *term colon definition* and the definition can embrace several paragraphs, until the next paragraph with a colon.

### Write your own service
[Write your own](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/Writing%20your%20own%20IntraMine%20server.html)
For Windows Perl developers, write your own IntraMine services based on the examples provided and then run as many of each as you need as separate processes, concentrating on your callbacks, and JavaScript if needed. Two example services are provided, one static and one RESTful, in addition to 15 or so other services that actually do things.

### Free as in free
If you see a use for IntraMine's FLASH link algorithms etc in your own work, go right ahead: all original work is covered by an UNLICENSE. (Some software included with or used by IntraMine, such as Perl, CodeMirror and Elasticsearch, is covered by separate license agreements.)

## Requirements

 - Windows 10 / 11.
 - IPv4 must be enabled on the PC where IntraMine is installed (this is overwhelmingly the default). IPv6 can be enabled or disabled as you wish
 - Strawberry Perl 5 version 30 or later (install instructions are included)
 - 3-4 GB of RAM for IntraMine (including Elasticsearch)
 - your own source and text files that can change should be attached directly to your IntraMine PC using SATA or USB (locally attached storage). NAS files can be indexed for search and FLASH linking, but changes to them won't be detected, so that's fine for library files but not your own work.

## Limitations and a heads-up

IntraMine is for use only on an intranet, and provides no security on its own. If your intranet isn't locked down reasonably well, you might want to pass.

IntraMine's services need to all run on the same PC, and adding/stopping/starting services is not automatic, though it can be done manually on the fly. This works well enough because the load on IntraMine is typically relatively light and predictable, unless your team is huge. And also because it's a viable option to have one instance of IntraMine running on each developer's PC, especially when everyone has a separate personal copy of source files.

And I feel bound to mention that installation of IntraMine requires a bit of time to wade through, roughly an hour. Not a lot of typing, mostly just waiting while things install. During startup, IntraMine will create your search index, which will likely take a few minutes.

## I'd like more details before diving in please

See [the documentation](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/contents.html).

## Bugs?

If you spot a bug, please do the kindness of sending an email describing it to klb42@proton.me.

## How to get started

Clone or fork or download the .zip for IntraMine, and open the included Documentation/contents.html in your browser. You'll see an "Installing and running IntraMine" section near the top.

After installing IntraMine and starting it up, point your browser to http://localhost:81/Search. (Or whatever port you choose if you can't use 81).

Enjoy!
- klb42@proton.me

[^1]: A table of contents is currently generated automatically for: Plain text (Gloss), Perl, Pod, C / C++, Go, JavaScript, CSS, Clojure, Erlang, OCaml, PHP, Python, Ruby, TypeScript, Rust, Java, C#, VBScript(.vb), VB.NET(.vbs), Haskell, Julia, Fortran, COBOL.
