REM test_run_stopstart_filewatcher.bat

@echo off&setlocal
for %%i in ("%~dp0..") do set "folder=%%~fi"
perl %folder%\test\test_stopstart_filewatcher.pl
