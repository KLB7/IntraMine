chcp 65001
@echo off&setlocal
call STOP_INTRAMINE.bat
timeout /t 10 /NOBREAK
call START_INTRAMINE.bat
