REM Run as administrator! Enter full path in console window.
REM Use this bat to incrementally add a directory to be indexed by Elasticsearch, and
REM have it optionally monitored for changes. File paths will also be pulled
REM for all directories, for use in Auto Links.
REM data/searchdirectories.txt lists directories, and whether to index or monitor them.
REM See Documentation/Elasticsearch indexing.txt for details.
REM Completely stop IntraMine, build list of folders for File Watcher to monitor (with a stop/start), update Elasticsearch indexes (NO init), start IntraMine again.
REM Get our parent folder, eg parent of C:\stuff\bats\testcallperl.bat is C:\stuff
@echo off&setlocal
for %%i in ("%~dp0..") do set "folder=%%~fi"
%folder%\bats\STOP_INTRAMINE.bat && perl %folder%\make_filewatcher_config.pl && perl %folder%\elastic_indexer.pl && %folder%\bats\START_INTRAMINE.bat
