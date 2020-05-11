# IntraMine

*Instant search and real autolinking for your Windows intranet.*

*Search results: 296,000 files searched for "FindFileWide", results in 0.07 seconds. No restriction on directory or language.*
![Search](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/2019-10-23%2014_30_47-Full%20Text%20Search.png)

*Some "FindFileWide" search hits in a file, seen with IntraMine's Viewer. The hits are in pink, in the text and down the scrollbar. A click on "allEntries" has highlighted all instances in green, in the text and down the scrollbar. There are automatically generated links to a subroutine in another file, a specific line in another file, and subroutines within the same file.*
![FindFileWide in a file](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/2020-05-04%2016_22_47-win_wide_filepaths.pm.png)


IntraMine is a Windows intranet service suite aimed mainly at Strawberry Perl developers. Because you deserve nice things too. Mind, anyone can install and use it on a Windows box, but if you know a little Perl it will cut down installation cursing by approximately 30%. IntraMine's Search, Viewer, and Linker services support 137 programming languages, as well as plain text.


## What's in the box
### Fast system-wide search
IntraMine uses Elasticsearch to provide one-second search of all your source and text files (which could easily number half a million these days), with index updates in five seconds. Search results show links to matching files, with a bit of context around the first hit in each file to give you a better assessment. You can limit searches by language or directory, but there's no need to do that for speed. There's a picture up top.
 
### A truly nice Viewer
See your search hits highlighted in a file, or the contents of any source or text file, complete with autolinks. And the usual syntax highlighting (mostly provided by CodeMirror). There's a picture up top.

### Autolinks
Autolinks appear on every reasonable thing when using IntraMine's Viewer, mostly with no extra typing. For example, if I type ctags extensions for viewer.txt somewhere, shouldn't that just become a link? There's only one file on my whole system called ctags extensions for viewer.txt. And don't make me put quotes or brackets around it.

IntraMine introduces link detection algorithms that can automatically link to source and text and image files on your local and NAS storage, as well as jumps to headings, classes, and methods in the same file or in other files.

Type main.cpp, and you get a link to the one nearest the file where you're typing. You wanted the one in the project51 folder on your Z drive, and there's only one project51 folder anywhere, and only one main.cpp inside it? Type project51/main.cpp and you have the link, even if the full path is Z:\Cpp\OtherProjects\Project51\src\main.cpp. No quotes are needed for a simple file link, even if the file name or path contains spaces. Type "project51/main.cpp#updateFile()" and you have a direct link to that method, one click away. The quotes and hash tag are needed here, but that's as complicated as it gets (the parentheses after updateFile are optional).

Autolinking can be made near perfect, armed with the master list of all full paths for files of interest that IntraMine will maintain for you (built when you index files of interest), and the concepts of "the closest one to my context" and "only necessary parts of the path."

### Image hovers
While using IntraMine's Viewer, pause your mouse over the image name and the image pops up. This works in source and text files, no extra typing required. So you can painlessly use screenshots and whiteboard grabs, or UML diagrams for example. You're invited to experiment.

### Gloss
Gloss is a minimal memorable markdown variant specialized for intranet use (autolinks, auto table of contents, simple tables). All of it is available under IntraMine's Viewer, and most of it (with obvious limits on file linking) can be used with the included gloss2html.pl program which produces completely standalone HTML versions of your Gloss-marked text documents. All of IntraMine's documentation was generated that way.

Here's how to do a simple table in Gloss:
 - type TABLE at the beginning of a line, followed by an optional caption
 - put headings on the next line and data on the following lines, separating cells by one or more tabs
 - and the table ends when there's a line without tabs.

### Write your own service
For Windows Perl developers, write your own IntraMine services based on the examples provided and then run as many of each as you need as separate processes, concentrating on your callbacks and JavaScript.

### Free as in free
Use IntraMine's autolinking approach etc for your own IDE: all original work is covered by an UNLICENSE.

## Requirements
 - Windows 10.
 - Strawberry Perl 5 version 30 or later (install instructions are included).
 - 3-4 GB of RAM for IntraMine (including Elasticsearch)
 - your source and text files that can change should be attached directly to your IntraMine PC using SATA or USB (locally attached storage). NAS files can be indexed for search and autolinking, but changes to them won't be detected.

For more see [the documentation](http://intramine.info), where among other things you'll find complete installation instructions.

## Bugs?
If you spot a bug above the minor cosmetic level, please do the kindness of sending an email describing it to klb7 at intramine.info. Pull requests for new features are not supported at this time - unless you want to collaborate on IntraMine and handle them yourself, in which case drop me a line.

## Warnings oh gosh
IntraMine is for use only on a intranet, and provides absolutely no security on its own. If your intranet isn't locked down reasonably well, you might want to pass.

IntraMine's services need to run on the same PC, and adding/stopping/starting services is not automatic, though it can be done on the fly. This works because the load on an intranet is relatively light and predictable, compared with the web. And also because it's a viable option to have one instance of IntraMine running on each developer's PC, especially when each has a separate personal copy of source files checked out.

And I feel bound to mention that installation of IntraMine, though thoroughly documented, requires a bit of time to wade through. Probably more than an hour. Not a lot of typing, mostly just waiting while things install one by one. Put up with the one-time nuisance and you'll have many shiny new toys to play with in the end.

## How to get started
Clone or fork or download the .zip for IntraMine, and open the included Documentation/contents.html in your browser. You'll see an "Installing" section near the top.

After installing IntraMine and starting it up, point your browser to http://localhost:81/Search.

If that gets you excited, read the rest of the documentation.
