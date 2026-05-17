@echo off
REM ==========================================================================
REM GymPrayerPauser uninstaller
REM Right-click this file and choose "Run as administrator".
REM ==========================================================================

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo.
    echo This uninstaller must be Run as Administrator.
    echo Right-click uninstall.bat and choose "Run as administrator".
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
pause
