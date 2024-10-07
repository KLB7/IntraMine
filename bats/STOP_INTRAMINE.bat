@echo off&setlocal
for %%i in ("%~dp0..") do set "folder=%%~fi"
perl %folder%\intramine_all_stop.pl 81
