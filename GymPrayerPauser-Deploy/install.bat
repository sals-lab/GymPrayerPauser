@echo off
REM ==========================================================================
REM GymPrayerPauser installer
REM Right-click this file and choose "Run as administrator".
REM ==========================================================================

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo This installer must be Run as Administrator.
    echo Right-click install.bat and choose "Run as administrator".
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
set RC=%ERRORLEVEL%

echo.
if %RC% neq 0 (
    echo Install failed with exit code %RC%.
) else (
    echo Install finished successfully.
)
pause
exit /b %RC%
