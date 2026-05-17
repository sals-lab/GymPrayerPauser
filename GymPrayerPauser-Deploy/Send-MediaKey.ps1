# ============================================================================
# GymPrayerPauser - Send media play/pause keystroke
# Fires VK_MEDIA_PLAY_PAUSE (0xB3) via keybd_event. Works system-wide for
# Spotify, Apple Music, YouTube in browser, and any app that registers the
# media keys (which is virtually all of them on Windows).
#
# Called by each per-prayer scheduled task. Can also be run manually for
# testing:
#   powershell.exe -ExecutionPolicy Bypass -File C:\GymPrayerPauser\Send-MediaKey.ps1 -Reason Manual-Test
# ============================================================================

param(
    [string]$Reason = 'Manual'
)

$InstallDir = 'C:\GymPrayerPauser'
$LogFile    = Join-Path $InstallDir 'log.txt'
$SkipFile   = Join-Path $InstallDir 'skip-today.flag'

function Write-Log {
    param([string]$Message)
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    "$ts  $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

# Honor the "skip today" override if it's dated today.
# A stale flag (from a previous day) is auto-cleaned so it can't accidentally
# disable tomorrow's pauses.
if (Test-Path $SkipFile) {
    $flagDate = (Get-Item $SkipFile).LastWriteTime.Date
    if ($flagDate -eq (Get-Date).Date) {
        Write-Log "SKIPPED [$Reason] - skip-today.flag is active"
        exit 0
    } else {
        try { Remove-Item $SkipFile -Force -ErrorAction Stop } catch {}
        Write-Log "Cleared stale skip-today.flag from $($flagDate.ToString('yyyy-MM-dd'))"
    }
}

try {
    Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GymMediaKey {
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    public const byte VK_MEDIA_PLAY_PAUSE = 0xB3;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public static void Toggle() {
        keybd_event(VK_MEDIA_PLAY_PAUSE, 0, 0, UIntPtr.Zero);
        keybd_event(VK_MEDIA_PLAY_PAUSE, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }
}
'@
    [GymMediaKey]::Toggle()
    Write-Log "Sent VK_MEDIA_PLAY_PAUSE [$Reason]"
} catch {
    Write-Log "ERROR sending media key [$Reason]: $_"
    exit 1
}
