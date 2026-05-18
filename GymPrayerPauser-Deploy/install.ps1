# Installer for GymPrayerPauser. Invoked by install.bat (which handles UAC).

$ErrorActionPreference = 'Stop'

$InstallDir = 'C:\GymPrayerPauser'
$SrcDir     = Split-Path -Parent $PSCommandPath
$MasterTask = 'GymPrayerPauser_Daily'
$ShortcutName = 'Gym Prayer Pauser.lnk'

Write-Host ''
Write-Host '=== GymPrayerPauser installer ==='
Write-Host "Source : $SrcDir"
Write-Host "Target : $InstallDir"
Write-Host "User   : $env:USERDOMAIN\$env:USERNAME"
Write-Host ''

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "Created $InstallDir"
}

$filesToCopy = @(
    'Schedule-PrayerPauses.ps1',
    'Send-MediaKey.ps1',
    'GymPrayerPauser-GUI.ps1',
    'uninstall.ps1',
    'uninstall.bat',
    'README.txt'
)
foreach ($f in $filesToCopy) {
    $src = Join-Path $SrcDir $f
    if (-not (Test-Path $src)) { throw "Missing file in deploy folder: $f" }
    Copy-Item -Path $src -Destination $InstallDir -Force
    Write-Host "Copied $f"
}

# --- Generate a custom app icon (blue circle with white pause bars) --------
$iconPath = Join-Path $InstallDir 'app.ico'
try {
    Add-Type -AssemblyName System.Drawing
    $size = 64
    $bmp = New-Object System.Drawing.Bitmap($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $bgBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(30, 100, 180))
    $g.FillEllipse($bgBrush, 1, 1, $size - 2, $size - 2)
    $fgBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $barW = 9; $barH = 30; $gap = 8
    $cx = $size / 2; $cy = $size / 2
    $g.FillRectangle($fgBrush, ($cx - $gap/2 - $barW), ($cy - $barH/2), $barW, $barH)
    $g.FillRectangle($fgBrush, ($cx + $gap/2),         ($cy - $barH/2), $barW, $barH)
    $g.Dispose()
    $hIcon = $bmp.GetHicon()
    $icon  = [System.Drawing.Icon]::FromHandle($hIcon)
    $fs    = [System.IO.File]::Create($iconPath)
    $icon.Save($fs)
    $fs.Close()
    $bmp.Dispose()
    Write-Host "Generated app icon at $iconPath"
} catch {
    Write-Host "WARN: could not generate icon ($_). Will fall back to a built-in icon."
}

# --- Enable wake timers in the active power plan (so tasks can wake the PC)-
try {
    $sub  = '238c9fa8-0aad-41ed-83f4-97be242c8f20'  # Sleep
    $set  = 'bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d'  # Allow wake timers
    & powercfg /SETACVALUEINDEX SCHEME_CURRENT $sub $set 1 | Out-Null
    & powercfg /SETDCVALUEINDEX SCHEME_CURRENT $sub $set 1 | Out-Null
    & powercfg /SETACTIVE SCHEME_CURRENT | Out-Null
    Write-Host 'Enabled "Allow wake timers" in the current power plan.'
} catch {
    Write-Host "WARN: could not enable wake timers ($_). Tasks may not wake the PC from sleep."
}

# --- Register the master daily task with WakeToRun -------------------------
Write-Host ''
Write-Host "Registering master task '$MasterTask' (daily 00:05)..."

$schedScript = Join-Path $InstallDir 'Schedule-PrayerPauses.ps1'
$arguments   = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$schedScript`""

$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
$trigger   = New-ScheduledTaskTrigger -Daily -At '00:05'
$settings  = New-ScheduledTaskSettingsSet `
                -AllowStartIfOnBatteries `
                -DontStopIfGoingOnBatteries `
                -StartWhenAvailable `
                -WakeToRun `
                -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
$principal = New-ScheduledTaskPrincipal `
                -UserId "$env:USERDOMAIN\$env:USERNAME" `
                -LogonType Interactive `
                -RunLevel Highest

Register-ScheduledTask `
    -TaskName  $MasterTask `
    -Action    $action `
    -Trigger   $trigger `
    -Settings  $settings `
    -Principal $principal `
    -Force | Out-Null

Write-Host 'Master task registered.'

# --- Create Desktop shortcut to the GUI -------------------------------------
try {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $shortcutPath = Join-Path $desktop $ShortcutName
    $guiScript = Join-Path $InstallDir 'GymPrayerPauser-GUI.ps1'

    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($shortcutPath)
    $sc.TargetPath       = 'powershell.exe'
    $sc.Arguments        = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$guiScript`""
    $sc.WorkingDirectory = "$env:USERPROFILE"
    if (Test-Path $iconPath) {
        $sc.IconLocation = "$iconPath,0"
    } else {
        $sc.IconLocation = "$env:SystemRoot\System32\imageres.dll,109"
    }
    $sc.Description = 'Gym Prayer Pauser - status and controls'
    $sc.Save()
    Write-Host "Created Desktop shortcut: $shortcutPath"

    # Also drop one in the All Users desktop so any account on the PC sees it.
    try {
        $publicDesktop = Join-Path $env:PUBLIC 'Desktop'
        if (Test-Path $publicDesktop) {
            $publicShortcut = Join-Path $publicDesktop $ShortcutName
            $sc2 = $ws.CreateShortcut($publicShortcut)
            $sc2.TargetPath       = 'powershell.exe'
            $sc2.Arguments        = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$guiScript`""
            $sc2.WorkingDirectory = "$env:USERPROFILE"
            $sc2.IconLocation     = $sc.IconLocation
            $sc2.Description      = 'Gym Prayer Pauser - status and controls'
            $sc2.Save()
            Write-Host "Created Public Desktop shortcut: $publicShortcut"
        }
    } catch {
        Write-Host "WARN: could not create Public Desktop shortcut ($_)."
    }
} catch {
    Write-Host "WARN: could not create Desktop shortcut ($_)."
}

# --- Run today's schedule once now ------------------------------------------
Write-Host ''
Write-Host "Running schedule once now to set up today's pauses..."
& powershell.exe -ExecutionPolicy Bypass -File $schedScript

Write-Host ''
Write-Host '=== Install complete ==='
Write-Host "Log file : $InstallDir\log.txt"
Write-Host "Read     : $InstallDir\README.txt"
Write-Host "GUI      : double-click 'Gym Prayer Pauser' on the Desktop"
Write-Host ''
Write-Host 'Currently scheduled tasks:'
Get-ScheduledTask | Where-Object { $_.TaskName -like 'GymPrayerPauser_*' } |
    Sort-Object TaskName |
    Format-Table TaskName, State -AutoSize
