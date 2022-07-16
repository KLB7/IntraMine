# IntraMine

*Fast search and real autolinking for your Windows local drives and NAS.*

*Search results: 125,000 files searched for "FindFileWide", results in 0.09 seconds. No restriction on directory or language.*
![Search](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/Search1.png)

*Some "FindFileWide" search hits in a file, seen with IntraMine's Viewer. The hits are in pink, in the text and down the scrollbar. A click on "allEntries" has highlighted all instances in green, in the text and down the scrollbar. There are automatically generated links to a subroutine in another file, a specific line in another file, and subroutines within the same file.*
![FindFileWide in a file](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/2020-05-04%2016_22_47-win_wide_filepaths.pm.png)

IntraMine is a Windows intranet service suite offering:
 - fast system-wide search, with five-second index update when you change a file
 - automatic linking for all source and text and image file mentions, with minimal overhead (often none)
 - a really nice file Viewer to browse your files, and see search hits in full context (plus automatic linking)
 - image hovers in your source and text files
 - Gloss, a markdown variant for intranet use that takes advantage of autolinking and minimizes "computer friendly" overhead
 - scalable services - write your own IntraMine service, with or without a front end, and run multiple instances that can talk to other services
 - Search, Viewer, and Linker service support for 137 programming languages, as well as plain text.

Anyone can install and use IntraMine on a Windows box, but if you know a little Perl it will cut down installation cursing by approximately 30%.

## What's in the box
### Fast system-wide search
IntraMine uses [Elasticsearch](https://www.elastic.co/what-is/elasticsearch) to provide near-instant search of all your source and text files (which could easily number half a million these days), with index updates in five seconds. Search results show links to matching files, with a bit of context around the first hit in each file to give you a better assessment. You can limit searches by language or directory, but there's no need to do that for speed. A picture is above.
 
### A truly nice Viewer
View the contents of any source or text file, with search hits highlighted in the text and down the scrollbar if you came from a Search results link.

The Viewer has standard display features such as syntax highlighting, line numbers, and an automatically generated table of contents[^1] down the left. And some extras such as automatic linking, image hovers, and selection highlighting (again in the text and down the scrollbar). There's a picture up top.

[CodeMirror](https://codemirror.net/) is used as the basis for most displays, with custom views for .txt and Perl files. Gloss (IntraMine's markdown variant) is fully applied to .txt files, and autolinking is applied to all source and text files (except .md).

### Autolinks
So, you're writing a comment or typing in a log file and you want a link to some other file, say "files.cpp": how do you signal your intent if there are several "files.cpp" files floating around? If you wanted a friend to be able to uniquely identify the correct file, you would add just enough directory names to make the reference unique, not caring about directories left out or even the correct order, because your friend is brilliant. And you would expect them to pick the "closest" matching file in the file system, relative to the one you're typing in, if your provided path is too short to be unique. That's what IntraMine's autolinking does.

For example, if the path fragment project51/files.cpp is enough to identify P:\Cpp\OtherProjects\Project51\src\files.cpp uniquely, that's all you need to type to get the correct link. To provide a link that goes directly to the updateFile() method in files.cpp, you could type project51/files.cpp#updateFile, or project51/files.cpp#updateFile() if you want to make it clear it's a method, or "project51/files.cpp#updateFile()" to make it stand out more in the source. If you're typing in a document in the Project51 folder then files.cpp is all you need to link to project51/src/files.cpp, since autolinking will pick the files.cpp that's closest to the document where you've done the typing (your "context").

Autolinking is applied to any source or text file viewed with IntraMine's Viewer, which is invoked when you click on any link on the Search or Files page. Or any link within a file.

Autolinking also links up web links, and internal class and function names and (quoted) heading mentions. There's a minimum of "computer friendly" baggage, so for example you don't have to put quotes around a web link, unless you want the link to stand out more in the original text.

A local or NAS file must be in a location that's been indexed for searching in order for autolinking to work. But if a folder has interesting files in it, you should probably index it. You'll discover how to index folders as you go through the installation.

As of March 2022, IntraMine's built-in Editor also displays autolinks for file or web mentions.

### Image hovers
While using IntraMine's Viewer, pause your mouse over an image name and the image pops up. This works in source and text files, no extra typing required, so you can painlessly use screenshots and whiteboard grabs, or UML diagrams for example. You're invited to experiment. There are some examples in IntraMine's [documentation](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/contents.html).

### Gloss
Gloss is a minimal memorable markdown variant specialized for intranet use (autolinks, auto table of contents, simple tables, and the other usual stuff you would want for in-house documentation). It's implemented by IntraMine's Viewer, and most of it can be used with the included gloss2html.pl program which produces completely standalone HTML versions of your Gloss-marked text documents. All of IntraMine's documentation was generated with gloss2html.pl.

Here's how to do a simple table in a .txt file with Gloss:
 - type TABLE at the beginning of a line, followed by an optional caption
 - put headings on the next line and data on the following lines, separating cells by one or more tabs
 - and the table ends when there's a line without tabs.

### Write your own service
For Windows Perl developers, write your own IntraMine services based on the examples provided and then run as many of each as you need as separate processes, concentrating on your callbacks, and JavaScript if needed. Two example services are provided, one static and one RESTful, in addition to 15 or so other services that actually do things.

### Free as in free
If you see a use for IntraMine's autolinking algorithms etc in your own work, go right ahead: all original work is covered by an UNLICENSE. (Some software included with or used by IntraMine, such as Perl, CodeMirror and Elasticsearch, is covered by separate license agreements.)

## Requirements
 - Windows 10 / 11.
 - Strawberry Perl 5 version 30 or later (install instructions are included).
 - 3-4 GB of RAM for IntraMine (including Elasticsearch)
 - your own source and text files that can change should be attached directly to your IntraMine PC using SATA or USB (locally attached storage). NAS files can be indexed for search and autolinking, but changes to them won't be detected, so that's fine for library files but not your own work.

## Bugs?
If you spot a bug, please do the kindness of sending an email describing it to klb7 at intramine.info. Requests to collaborate on IntraMine are welcome, drop me a line.

## Limitations and a heads-up
IntraMine is for use only on an intranet, and provides no security on its own. If your intranet isn't locked down reasonably well, you might want to pass.

IntraMine's services need to all run on the same PC, and adding/stopping/starting services is not automatic, though it can be done manually on the fly. This works well enough because the load on IntraMine is typically relatively light and predictable, unless your team is huge. And also because it's a viable option to have one instance of IntraMine running on each developer's PC, especially when everyone has a separate personal copy of source files.

And I feel bound to mention that installation of IntraMine requires a bit of time to wade through. Roughly an hour. Not a lot of typing, mostly just waiting while things install. And then there's your first index build, which might take another hour. Put up with the one-time nuisance and you'll have many shiny new toys to play with.

## I'd like more details before diving in please
See [the documentation](https://htmlpreview.github.io/?https://github.com/KLB7/IntraMine/blob/master/Documentation/contents.html).

## How to get started
Clone or fork or download the .zip for IntraMine, and open the included Documentation/contents.html in your browser. You'll see an "Installing and running IntraMine" section near the top.

After installing IntraMine and starting it up, point your browser to http://localhost:81/Search. (Or whatever port you choose if you can't use 81).

Enjoy!
-KLB7 at intramine.info

[^1]: A table of contents is currently generated automatically for: Plain text (Gloss), Perl, Pod, C / C++, Go, JavaScript, CSS, Clojure, Erlang, OCaml, PHP, Python, Ruby, TypeScript, Rust, Java, C#, VBScript(.vb), VB.NET(.vbs), Haskell.

