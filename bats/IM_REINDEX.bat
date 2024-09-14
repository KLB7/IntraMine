@echo off&setlocal
for %%i in ("%~dp0..") do set "folder=%%~fi"
perl %folder%\ri.pl -addTestDoc
