# Uninstaller for GymPrayerPauser. Invoked by uninstall.bat.

$ErrorActionPreference = 'Continue'

$InstallDir = 'C:\GymPrayerPauser'

Write-Host ''
Write-Host '=== GymPrayerPauser uninstaller ==='
Write-Host ''

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

if (Test-Path $InstallDir) {
    try {
        Remove-Item -Recurse -Force -Path $InstallDir -ErrorAction Stop
        Write-Host "Removed folder: $InstallDir"
    } catch {
        Write-Host "WARN: failed to remove $InstallDir - $_"
    }
} else {
    Write-Host "Folder $InstallDir not present."
}

Write-Host ''
Write-Host '=== Uninstall complete ==='
