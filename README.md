# IntraMine

*Fast search and real autolinking for your Windows intranet.*

*Search results: 296,000 files searched for "FindFileWide", results in 0.07 seconds. No restriction on directory or language.*
![Search](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/2019-10-23%2014_30_47-Full%20Text%20Search.png)

*Some "FindFileWide" search hits in a file, seen with IntraMine's Viewer. The hits are in pink, in the text and down the scrollbar. A click on "allEntries" has highlighted all instances in green, in the text and down the scrollbar. There are automatically generated links to a subroutine in another file, a specific line in another file, and subroutines within the same file.*
![FindFileWide in a file](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/2020-05-04%2016_22_47-win_wide_filepaths.pm.png)

IntraMine is a Windows intranet service suite offering:
 - fast system-wide search, with five-second index update when you change a file
 - automatic linking for all source and text and image file mentions, with minimal overhead (often none)
 - a really nice file Viewer to browse your files, and see search hits in full context (plus automatic linking)
 - image hovers in your source and text files.
 - Gloss, a markdown variant for intranet use that takes advantage of autolinking and minimizes "computer friendly" overhead
 - scalable services - write your own IntraMine service, with or without a front end, and run multiple instances that can talk to other services
 - Search, Viewer, and Linker service support for 137 programming languages, as well as plain text.

Anyone can install and use IntraMine on a Windows box, but if you know a little Perl it will cut down installation cursing by approximately 30%.

## What's in the box
### Fast system-wide search
IntraMine uses [Elasticsearch](https://www.elastic.co/what-is/elasticsearch) to provide near-instant search of all your source and text files (which could easily number half a million these days), with index updates in five seconds. Search results show links to matching files, with a bit of context around the first hit in each file to give you a better assessment. You can limit searches by language or directory, but there's no need to do that for speed. A picture is above.
 
### A truly nice Viewer
View the contents of any source or text file, with search hits highlighted in the text and down the scrollbar if you came from a Search results link.

The Viewer has standard display features such as syntax highlighting, line numbers, and an automatically generated table of contents, but its main reason for being is to show off automatic linking. There's a picture up top.

[CodeMirror](https://codemirror.net/) is used as the basis for most displays, with custom views for .txt and Perl files.

### Autolinks
Autolinks appear on every reasonable thing when using IntraMine's Viewer, mostly with no extra typing. IntraMine introduces link detection algorithms that can automatically link to source and text and image files on your local and NAS storage, as well as jumps to headings, classes, and methods in the same file or in other files.

You need only supply enough of the path to a file to make it unambiguous, with the understanding that if there's a choice then the "closest" file wins. For example, if the path fragment project51/main.cpp is enough to identify P:\Cpp\OtherProjects\Project51\src\main.cpp uniquely, that's all you need to type in your source or text file. To provide a link that goes directly to the updateFile() method, you could type project51/main.cpp#updateFile, or project51/main.cpp#updateFile() if you want to make it clear it's a method, or "project51/main.cpp#updateFile()" to make it stand out more in the source. If you're typing in a document in the Project51 folder then main.cpp is all you need to link to project51/src/main.cpp, since autolinking will pick the main.cpp that's closest to the document where you've done the typing (your "context").

The upshot is autolinking can be easy and accurate, armed with the master list of all full paths for files of interest that IntraMine will maintain for you (built when you index folders of interest), and the concepts of "the closest one to my context" and "only necessary parts of the path."

### Image hovers
While using IntraMine's Viewer, pause your mouse over an image name and the image pops up. This works in source and text files, no extra typing required, so you can painlessly use screenshots and whiteboard grabs, or UML diagrams for example. You're invited to experiment. There are some examples in IntraMine's [documentation](http://intramine.info/contents.html).

### Gloss
Gloss is a minimal memorable markdown variant specialized for intranet use (autolinks, auto table of contents, simple tables, and the other usual stuff you would want for in-house documentation). It's implemented by IntraMine's Viewer, and most of it can be used with the included gloss2html.pl program which produces completely standalone HTML versions of your Gloss-marked text documents. All of IntraMine's documentation was generated with gloss2html.pl.

Here's how to do a simple table in Gloss:
 - type TABLE at the beginning of a line, followed by an optional caption
 - put headings on the next line and data on the following lines, separating cells by one or more tabs
 - and the table ends when there's a line without tabs.

### Write your own service
For Windows Perl developers, write your own IntraMine services based on the examples provided and then run as many of each as you need as separate processes, concentrating on your callbacks and JavaScript. Two example services are provided, one static and one RESTful, in addition to 15 or so other services that actually do things.

### Free as in free
If you see a use for IntraMine's autolinking algorithms etc in your own work, go right ahead: all original work is covered by an UNLICENSE. (Some software included with or used by IntraMine, such as Perl, CodeMirror and Elasticsearch, is covered by separate license agreements.)

## Requirements
 - Windows 10.
 - Strawberry Perl 5 version 30 or later (install instructions are included).
 - 3-4 GB of RAM for IntraMine (including Elasticsearch)
 - your own source and text files that can change should be attached directly to your IntraMine PC using SATA or USB (locally attached storage). NAS files can be indexed for search and autolinking, but changes to them won't be detected, so that's fine for library files but not your own work.

## Bugs?
If you spot a bug above the minor cosmetic level, please do the kindness of sending an email describing it to klb7 at intramine.info. Pull requests for new features are not supported at this time - unless you want to collaborate on IntraMine and handle them yourself, in which case drop me a line.

## Limitations and a heads up
IntraMine is for use only on a intranet, and provides absolutely no security on its own. If your intranet isn't locked down reasonably well, you might want to pass.

IntraMine's services need to run on the same PC, and adding/stopping/starting services is not automatic, though it can be done on the fly. This works because the load on IntraMine will be relatively light and predictable, unless your team is huge. And also because it's a viable option to have one instance of IntraMine running on each developer's PC, especially when everyone has a separate personal copy of source files checked out.

And I feel bound to mention that installation of IntraMine, though thoroughly documented to death and partway into the afterlife, requires a bit of time to wade through. Roughly an hour. Not a lot of typing, mostly just waiting while things install one by one. And then there's your first index build, which might take another hour. Put up with the one-time nuisance and you'll have many shiny new toys to play with.

## I'd like more details before diving in please
See [the documentation](http://intramine.info).

## How to get started
Clone or fork or download the .zip for IntraMine, and open the included Documentation/contents.html in your browser. You'll see an "Installing and running IntraMine" section near the top.

After installing IntraMine and starting it up, point your browser to http://localhost:81/Search.

If that gets you interested, skim through the rest of the documentation. Maybe write your own IntraMine service?
