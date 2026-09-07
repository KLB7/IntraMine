@echo off
setlocal enabledelayedexpansion

:: echo Scanning system for Strawberry Perl...
:: echo =======================================

:: 1. Check if 'perl' is available in the current %PATH% and isolate its root directory
where perl >nul 2>&1
if %errorlevel% equ 0 (
    for /f "delims=" %%i in ('where perl') do (
        set "PERL_EXE=%%i"
        :: Check if the path contains "strawberry"
        echo !PERL_EXE! | findstr /i "strawberry" >nul
        if !errorlevel! equ 0 (
            :: Navigate up two directories from \perl\bin\perl.exe or \bin\perl.exe
            for %%A in ("!PERL_EXE!") do set "BIN_DIR=%%~dpA"
            for %%A in ("!BIN_DIR!..") do set "ROOT_DIR=%%~fA"
            :: If it was inside \perl\bin, we need to go up one more level
            if exist "!ROOT_DIR!\perl" (
                set "STRAWBERRY_PATH=!ROOT_DIR!"
            ) else (
                for %%A in ("!ROOT_DIR!..") do set "STRAWBERRY_PATH=%%~fA"
            )
            set "SOURCE=System PATH environment variable"
            goto FOUND
        )
    )
)

:: 2. Check Windows Registry for the MSI installer location
:: Check 64-bit/Standard registry path
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\StrawberryPerl" /v "InstallLocation" 2^>nul') do (
    set "STRAWBERRY_PATH=%%B"
    set "SOURCE=Windows Registry"
    goto FOUND
)

:: Check 32-bit registry redirection path (Wow6432Node) just in case
for /f "tokens=2,*" %%A in ('reg query "HKLM\SOFTWARE\Wow6432Node\StrawberryPerl" /v "InstallLocation" 2^>nul') do (
    set "STRAWBERRY_PATH=%%B"
    set "SOURCE=Windows Registry (32-bit node)"
    goto FOUND
)

:: 3. Fallback to checking the default hardcoded directory
if exist "C:\Strawberry\" (
    set "STRAWBERRY_PATH=C:\Strawberry"
    set "SOURCE=Default C:\Strawberry Fallback"
    goto FOUND
)

:NOT_FOUND
:: echo [ERROR] Strawberry Perl could not be detected automatically.
exit /b 1

:FOUND
:: Strip trailing backslashes if present
if "%STRAWBERRY_PATH:~-1%"=="\" set "STRAWBERRY_PATH=%STRAWBERRY_PATH:~0,-1%"

:: echo Strawberry Perl detected!
:: echo Path:   %STRAWBERRY_PATH%
:: echo Source: %SOURCE%
set "hoedownpath=%STRAWBERRY_PATH%\site\lib\Text\Markdown\Hoedown.pm"
IF EXIST %hoedownpath% goto FOUND_HOEDOWN
goto NO_HOEDOWN

:FOUND_HOEDOWN
:: echo hoedown exists
exit /b 10

:NO_HOEDOWN
:: echo hoedown does NOT exist
exit /b 20

:: echo =======================================

endlocal & set "STRAWBERRY_PATH=%STRAWBERRY_PATH%"
