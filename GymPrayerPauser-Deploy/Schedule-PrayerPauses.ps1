# ============================================================================
# GymPrayerPauser - Daily scheduler
# Fetches today's prayer times for Kuwait City and registers Windows
# Task Scheduler jobs to pause/resume media at each prayer.
#
# Runs once per day at 00:05 via the master task "GymPrayerPauser_Daily",
# and can also be run manually any time to rebuild today's schedule.
# ============================================================================

# ---------- DEFAULTS (used only if config.json is missing or invalid) -------
# Day-to-day tuning is done via the GUI (Desktop icon -> Save & Apply),
# which writes to C:\GymPrayerPauser\config.json. This script reads that file
# every time it runs. The values below are just safety fallbacks.

$PauseDurations = @{
    Fajr    = 25
    Dhuhr   = 20
    Asr     = 20
    Maghrib = 20
    Isha    = 20
}
$AthanOffsetMinutes = 0

# Aladhan API: method=9 is Kuwait (Ministry of Awqaf).
$ApiUrl = 'http://api.aladhan.com/v1/timingsByCity?city=Kuwait%20City&country=Kuwait&method=9'

# ---------- (do not edit below unless you know what you're doing) -----------

$InstallDir = 'C:\GymPrayerPauser'
$LogFile    = Join-Path $InstallDir 'log.txt'
$CacheFile  = Join-Path $InstallDir 'prayer-cache.json'
$ConfigFile = Join-Path $InstallDir 'config.json'
$TaskPrefix = 'GymPrayerPauser_'
$MasterTask = 'GymPrayerPauser_Daily'
$Prayers    = @('Fajr','Dhuhr','Asr','Maghrib','Isha')

function Write-Log {
    param([string]$Message)
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    "$ts  $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

function Remove-OldPrayerTasks {
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue |
        Where-Object { $_.TaskName -like "$TaskPrefix*" -and $_.TaskName -ne $MasterTask }
    foreach ($t in $tasks) {
        try {
            Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false -ErrorAction Stop
            Write-Log "Removed old task: $($t.TaskName)"
        } catch {
            Write-Log "WARN failed to remove $($t.TaskName): $_"
        }
    }
}

function Get-PrayerTimes {
    try {
        $resp = Invoke-RestMethod -Uri $ApiUrl -TimeoutSec 30
        $t = $resp.data.timings
        $timings = [ordered]@{
            Fajr    = $t.Fajr
            Dhuhr   = $t.Dhuhr
            Asr     = $t.Asr
            Maghrib = $t.Maghrib
            Isha    = $t.Isha
        }
        $cache = [ordered]@{
            FetchedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            Timings   = $timings
        }
        $cache | ConvertTo-Json | Out-File -FilePath $CacheFile -Encoding UTF8 -Force
        Write-Log ("Fetched today's times: Fajr={0} Dhuhr={1} Asr={2} Maghrib={3} Isha={4}" -f `
            $timings.Fajr, $timings.Dhuhr, $timings.Asr, $timings.Maghrib, $timings.Isha)
        return $timings
    } catch {
        Write-Log "ERROR fetching prayer times from API: $_"
        if (Test-Path $CacheFile) {
            try {
                $cache = Get-Content $CacheFile -Raw | ConvertFrom-Json
                Write-Log "Falling back to cached times from $($cache.FetchedAt)"
                return @{
                    Fajr    = $cache.Timings.Fajr
                    Dhuhr   = $cache.Timings.Dhuhr
                    Asr     = $cache.Timings.Asr
                    Maghrib = $cache.Timings.Maghrib
                    Isha    = $cache.Timings.Isha
                }
            } catch {
                Write-Log "ERROR reading cache: $_"
            }
        }
        Write-Log 'FATAL: no API and no usable cache - no tasks scheduled today.'
        return $null
    }
}

function ConvertTo-TodayDateTime {
    # Accepts "04:23" or "04:23 (AST)" and returns a DateTime for today.
    param([string]$TimeString)
    $clean = ($TimeString -split '\s')[0]
    $parts = $clean.Split(':')
    $hour   = [int]$parts[0]
    $minute = [int]$parts[1]
    return (Get-Date).Date.AddHours($hour).AddMinutes($minute)
}

function Register-MediaKeyTask {
    param(
        [string]$Prayer,
        [string]$Action,   # 'Pause' or 'Resume'
        [datetime]$When
    )
    if ($When -le (Get-Date)) {
        Write-Log ("Skipping {0} {1} at {2:HH:mm} - already passed" -f $Prayer, $Action, $When)
        return
    }

    $taskName  = "${TaskPrefix}${Prayer}_${Action}"
    $script    = Join-Path $InstallDir 'Send-MediaKey.ps1'
    $reason    = "$Prayer-$Action"
    $arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Reason `"$reason`""

    $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments
    $trigger    = New-ScheduledTaskTrigger -Once -At $When
    $settings   = New-ScheduledTaskSettingsSet `
                    -AllowStartIfOnBatteries `
                    -DontStopIfGoingOnBatteries `
                    -StartWhenAvailable `
                    -WakeToRun `
                    -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    $principal  = New-ScheduledTaskPrincipal `
                    -UserId "$env:USERDOMAIN\$env:USERNAME" `
                    -LogonType Interactive `
                    -RunLevel Highest

    try {
        Register-ScheduledTask `
            -TaskName  $taskName `
            -Action    $taskAction `
            -Trigger   $trigger `
            -Settings  $settings `
            -Principal $principal `
            -Force `
            -ErrorAction Stop | Out-Null
        Write-Log ("Scheduled {0} at {1:HH:mm}" -f $taskName, $When)
    } catch {
        Write-Log "ERROR scheduling $taskName : $_"
    }
}

# ---------- Main ------------------------------------------------------------

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

Write-Log '=== Daily schedule rebuild starting ==='
Write-Log ("Running as user: {0}\{1}" -f $env:USERDOMAIN, $env:USERNAME)

# Load user-editable config (written by the GUI). Falls back to defaults if
# the file is missing or unreadable.
if (Test-Path $ConfigFile) {
    try {
        $cfg = Get-Content $ConfigFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($cfg.PauseDurations) {
            foreach ($p in $Prayers) {
                $v = $cfg.PauseDurations.$p
                if ($null -ne $v) {
                    $iv = [int]$v
                    if ($iv -ge 1 -and $iv -le 240) { $PauseDurations[$p] = $iv }
                }
            }
        }
        if ($null -ne $cfg.AthanOffsetMinutes) {
            $ov = [int]$cfg.AthanOffsetMinutes
            if ($ov -ge -60 -and $ov -le 60) { $AthanOffsetMinutes = $ov }
        }
        Write-Log "Loaded config.json"
    } catch {
        Write-Log "WARN: could not read config.json ($_); using defaults"
    }
} else {
    Write-Log "config.json not found; using defaults"
}

Write-Log ("AthanOffsetMinutes = {0}" -f $AthanOffsetMinutes)
Write-Log ("PauseDurations = Fajr={0} Dhuhr={1} Asr={2} Maghrib={3} Isha={4}" -f `
    $PauseDurations.Fajr, $PauseDurations.Dhuhr, $PauseDurations.Asr, $PauseDurations.Maghrib, $PauseDurations.Isha)

Remove-OldPrayerTasks

$timings = Get-PrayerTimes
if ($null -eq $timings) {
    Write-Log '=== Daily schedule rebuild aborted ==='
    exit 1
}

foreach ($prayer in $Prayers) {
    $rawTime   = $timings[$prayer]
    if ([string]::IsNullOrWhiteSpace($rawTime)) {
        Write-Log "WARN: no time returned for $prayer; skipping"
        continue
    }
    $pauseAt   = (ConvertTo-TodayDateTime $rawTime).AddMinutes($AthanOffsetMinutes)
    $duration  = [int]$PauseDurations[$prayer]
    $resumeAt  = $pauseAt.AddMinutes($duration)

    Register-MediaKeyTask -Prayer $prayer -Action 'Pause'  -When $pauseAt
    Register-MediaKeyTask -Prayer $prayer -Action 'Resume' -When $resumeAt
}

Write-Log '=== Daily schedule rebuild complete ==='
exit 0
