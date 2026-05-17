# Installer for GymPrayerPauser. Invoked by install.bat (which handles UAC).

$ErrorActionPreference = 'Stop'

$InstallDir = 'C:\GymPrayerPauser'
$SrcDir     = Split-Path -Parent $PSCommandPath
$MasterTask = 'GymPrayerPauser_Daily'

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

foreach ($f in @('Schedule-PrayerPauses.ps1','Send-MediaKey.ps1','README.txt')) {
    $src = Join-Path $SrcDir $f
    if (-not (Test-Path $src)) { throw "Missing file in deploy folder: $f" }
    Copy-Item -Path $src -Destination $InstallDir -Force
    Write-Host "Copied $f"
}

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

Write-Host "Master task registered."
Write-Host ''
Write-Host "Running schedule once now to set up today's pauses..."

& powershell.exe -ExecutionPolicy Bypass -File $schedScript

Write-Host ''
Write-Host '=== Install complete ==='
Write-Host "Log file : $InstallDir\log.txt"
Write-Host "Read     : $InstallDir\README.txt"
Write-Host ''
Write-Host 'Currently scheduled prayer tasks:'
Get-ScheduledTask | Where-Object { $_.TaskName -like 'GymPrayerPauser_*' } |
    Sort-Object TaskName |
    Format-Table TaskName, State -AutoSize
