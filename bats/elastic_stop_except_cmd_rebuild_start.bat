REM stop intramine server (except command server), update Elasticsearch indexes, start intramine again.
REM Get our parent folder, eg parent of C:\stuff\bats\testcallperl.bat is C:\stuff
@echo off&setlocal
for %%i in ("%~dp0..") do set "folder=%%~fi"
intramain_stop.bat && perl %folder%\elastic_indexer.pl && START_INTRAMINE.bat
