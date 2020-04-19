REM Get our parent folder, eg parent of C:\stuff\bats\testcallperl.bat is C:\stuff
REM Test IntraMine (start, exec tests, quit all servers and show test results).
REM Only servers with Count > 0 in data/serverlist_for_testing.txt will be tested.
@echo off&setlocal
for %%i in ("%~dp0..") do set "folder=%%~fi"
perl %folder%\intramine_main.pl -t
