# IntraMine
IntraMine is an intranet service suite aimed mainly at Strawberry Perl Windows developers. Because you deserve nice things too. Mind, anyone can install and use it on a Windows box, but if you know a little Perl it will cut down installation cursing by approximately 30%.

An attempt has been made to address the following:

 - local file Search could be nicer, in particular it could show a complete view of hit documents with the hits marked
 - Perl for Windows lacks an easy approach to multiprocessing
 - autolinking for local files is very limited in all editors
 - images are too hard to use in source and text files - so they aren't
 - most markdown approaches are not as minimal, memorable, mimetic, or automatic as one might wish for, when it comes to in-house documentation.

I had some notions, so I set out to do a demo to address those issues. My nefarious intent is to incite someone to incorporate IntraMine's approach to autolinking and image handling in their own editor. But since no one really wants a raw demo, I spent some extra time (years) polishing it up to the point where I hope you find it pleasant and useful.

## What's in the box
 - Elasticsearch-based one second search of all your source and text files (which could easily number more than half a million these days), with no-load index updates in five seconds.
 - a truly nice Viewer to see your search hits in context
 - autolinks on everything in all file views, mostly with no extra typing
 - Gloss, a superautomatic minimal memorable markdown variant specialized for intranet use (autolinks, auto TOC, simple tables)
 - image hovers, so images actually become useful. Pause your mouse over the image name and the image pops up. Works in source and text files, zero extra typing required.
 - for Perl developers, write your own IntraMine services based on the examples provided and then run as many of each as you need as separate processes, concentrating on your callbacks and JavaScript. IntraMine's main "round robin redirect" service won't be a bottleneck.
 - use IntraMine's autolinking approach etc for your own IDE, all original work is covered under an UNLICENSE.

## Requirements
 - Windows 10.
 - Strawberry Perl 5 version 30 or later (install instructions are included).
 - 3-4 GB of RAM for IntraMine (including Elasticsearch)
 - your source and text files that can change should be attached directly to your IntraMine PC using SATA or USB (locally attached storage). NAS files can be indexed for search and autolinking, but changes to them won't be detected.

For more see [the documentation](http://intramine.info), where among other things you'll find complete installation instructions.

## What's different about an intranet
Since IntraMine is for intranet use only, opportunities arise to simplify some things, and enhance others:

 - IntraMine doesn't do full the full microservices thing. In particular, all IntraMine services for a single instance need to run on the same PC (you can have multiple instances of IntraMine though, running on different PCs). And adding/stopping/starting services is not automatic, though it can be done on the fly.
 - IntraMine's interprocess communications aren't quite fully RESTful. The one big omission is that there's no HATEOAS mechanism. But it's the intranet, so if the fellow superstar next to you writes a new IntraMine service, you can just lean over and ask "Got an API for that?"
 - autolinking can be made near perfect, armed with the list of all full paths for files of interest that IntraMine will maintain for you, and the concepts of "the closest one to my context" and "only needed parts of the path".
 - images can be easy to use, and become first class citizens.

## Metablather
All original work is covered under an UNLICENSE. On the off chance that you see something you like, use it.

## Bugs?
If you spot a bug above the minor cosmetic level, please send an email describing it to klb7@intramine.info. Pull requests for new features are not supported at this time - unless you want to collaborate on IntraMine and handle them yourself, in which case drop me a line.

## Warning
IntraMine is for use only on a intranet, and provides absolutely no security on its own. If your intranet isn't locked down reasonably well, and you have proprietary files that no one else must see or you don't do regular backups of your important files, you might want to pass.

## How to get started
Clone or download the .zip for IntraMine, and open the included Documentation/contents.html in your browser.



*Search results: 296,000 files searched for "FindFileWide", results in 0.07 seconds. No restriction on directory or language.*
![Search](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/2019-10-23%2014_30_47-Full%20Text%20Search.png)

*FindFileWide search hits, seen with IntraMine's Viewer. The hits are in pink, in the text and down the scrollbar. A click on "allEntries" has highlighted all instances in green, in the text and down the scrollbar. There are automatically generated links to a subroutine in another file, a specific line in another file, and subroutines within the same file.*
![FindFileWide in a file](https://github.com/KLB7/IntraMine/blob/master/Documentation/images/2020-05-04%2016_22_47-win_wide_filepaths.pm.png)
