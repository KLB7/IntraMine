 echo off
for %%i in ("%~dp0..") do set "folder=%%~fi"
echo -----------COPY THE LINE BELOW-------------
echo Unblock-File -Path "%folder%\bats\foldermonitor.ps1"
echo -----------COPY THE LINE ABOVE-------------
echo and then Paste into your PowerShell window.
pause