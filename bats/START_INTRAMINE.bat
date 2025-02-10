chcp 65001
@echo off&setlocal
for %%i in ("%~dp0..") do set "folder=%%~fi"
perl %folder%\intramine_main.pl
