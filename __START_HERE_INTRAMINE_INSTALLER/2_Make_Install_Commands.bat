echo off
for %%i in ("%~dp0..") do set "folder=%%~fi"
echo -----------COPY THE FIVE LINES BELOW-------------
echo Unblock-File -Path "%folder%\bats\foldermonitor.ps1"
echo Unblock-File -Path "%folder%\__START_HERE_INTRAMINE_INSTALLER\installer.ps1"
echo Unblock-File -Path "%folder%\__START_HERE_INTRAMINE_INSTALLER\uninstaller.ps1"
echo cd "%folder%\__START_HERE_INTRAMINE_INSTALLER"
echo .\installer.ps1
echo -----------COPY THE FIVE LINES ABOVE-------------
echo and then Paste into your PowerShell window.
pause
