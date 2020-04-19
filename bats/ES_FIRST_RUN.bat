REM Run as administrator!
REM Run this to build your first Elasticsearch index, as described in
REM Elasticsearch indexing.txt.
REM This will stop intramine server, build list of folders for File Watcher
REM to monitor (with a stop/start), then INIT and update Elasticsearch indexes.
REM Warning, running this will replace your Elasticsearch index with a completely rebuilt one.
REM Get our parent folder, eg parent of C:\stuff\bats\testcallperl.bat is C:\stuff
@echo off&setlocal
for %%i in ("%~dp0..") do set "folder=%%~fi"
%folder%\bats\STOP_INTRAMINE.bat && perl %folder%\make_filewatcher_config.pl && perl %folder%\elasticsearch_init_index.pl && perl %folder%\elastic_indexer.pl -addTestDoc
