REM RUN AS ADMINISTRATOR! Enter full path in console window.
REM this will stop intramine server, build list of folders for File Watcher to monitor (with a stop/start), INIT and update Elasticsearch indexes using data/search_directories.txt, and start intramine again.
REM Warning, running this will replace your Elasticsearch index with a completely rebuilt one.
REM First get our parent folder, eg parent of C:\stuff\bats\testcallperl.bat is C:\stuff
@echo off&setlocal
for %%i in ("%~dp0..") do set "folder=%%~fi"
%folder%\bats\STOP_INTRAMINE.bat && perl %folder%\make_filewatcher_config.pl && perl %folder%\elasticsearch_init_index.pl && perl %folder%\elastic_indexer.pl -addTestDoc && %folder%\bats\START_INTRAMINE.bat
