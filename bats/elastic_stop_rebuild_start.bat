REM COMPLETELY stop intramine server, update Elasticsearch indexes, start intramine again.
REM Get our parent folder, eg parent of C:\stuff\bats\testcallperl.bat is C:\stuff
@echo off&setlocal
for %%i in ("%~dp0..") do set "folder=%%~fi"
STOP_INTRAMINE.bat && perl %folder%\elastic_indexer.pl && START_INTRAMINE.bat
