# Uninstaller for GymPrayerPauser. Invoked by uninstall.bat.

$ErrorActionPreference = 'Continue'

$InstallDir   = 'C:\GymPrayerPauser'
$ShortcutName = 'Gym Prayer Pauser.lnk'

Write-Host ''
Write-Host '=== GymPrayerPauser uninstaller ==='
Write-Host ''

# 1. Remove scheduled tasks
$tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName -like 'GymPrayerPauser_*' }

if ($tasks) {
    foreach ($t in $tasks) {
        try {
            Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false -ErrorAction Stop
            Write-Host "Removed task: $($t.TaskName)"
        } catch {
            Write-Host "WARN: failed to remove $($t.TaskName) - $_"
        }
    }
} else {
    Write-Host 'No GymPrayerPauser_* scheduled tasks found.'
}

# 2. Remove Desktop shortcuts (current user + public)
$candidatePaths = @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) $ShortcutName),
    (Join-Path (Join-Path $env:PUBLIC 'Desktop') $ShortcutName)
)
foreach ($lnk in $candidatePaths) {
    if (Test-Path $lnk) {
        try {
            Remove-Item $lnk -Force -ErrorAction Stop
            Write-Host "Removed shortcut: $lnk"
        } catch {
            Write-Host "WARN: failed to remove $lnk - $_"
        }
    }
}

# 3. Remove install folder. Make sure we are NOT inside it first.
try { Set-Location -Path $env:USERPROFILE -ErrorAction SilentlyContinue } catch {}

if (Test-Path $InstallDir) {
    try {
        Remove-Item -Recurse -Force -Path $InstallDir -ErrorAction Stop
        Write-Host "Removed folder: $InstallDir"
    } catch {
        Write-Host "WARN: failed to remove $InstallDir - $_"
        Write-Host '       Some files may be in use. Try again after closing the GUI window.'
    }
} else {
    Write-Host "Folder $InstallDir not present."
}

Write-Host ''
Write-Host '=== Uninstall complete ==='
