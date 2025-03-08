@echo off
echo The File Watcher Windows Service needs to be restarted.
echo Please click on this window, press any key and then allow the restart
echo in the resulting User Account Control prompt by clicking 'Yes'.
pause
@echo off&setlocal
for %%i in ("%~dp0..") do set "folder=%%~fi"
perl %folder%\restartFWWS.pl
