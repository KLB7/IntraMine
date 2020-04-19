REM Get our parent folder, eg parent of C:\stuff\bats\testcallperl.bat is C:\stuff
@echo off&setlocal
for %%i in ("%~dp0..") do set "folder=%%~fi"
perl %folder%\echo1.pl %1 %2 %3 %4
