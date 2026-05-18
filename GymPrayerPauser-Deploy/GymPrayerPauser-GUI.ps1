# ============================================================================
# GymPrayerPauser - Status GUI
# A tiny WinForms window for non-technical users:
#   - Today's prayer schedule (with status per prayer)
#   - Friendly translated activity log
#   - Refresh + Uninstall buttons
# Launched from the Desktop shortcut "Gym Prayer Pauser".
# ============================================================================

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$InstallDir   = 'C:\GymPrayerPauser'
$LogFile      = Join-Path $InstallDir 'log.txt'
$UninstallBat = Join-Path $InstallDir 'uninstall.bat'
$MediaScript  = Join-Path $InstallDir 'Send-MediaKey.ps1'
$ScheduleScript = Join-Path $InstallDir 'Schedule-PrayerPauses.ps1'
$ConfigFile   = Join-Path $InstallDir 'config.json'
$Prayers      = @('Fajr','Dhuhr','Asr','Maghrib','Isha')

$DefaultDurations = @{ Fajr = 25; Dhuhr = 20; Asr = 20; Maghrib = 20; Isha = 20 }
$DefaultOffset    = 0

function Read-Config {
    $cfg = @{
        PauseDurations    = @{}
        AthanOffsetMinutes = $DefaultOffset
    }
    foreach ($p in $Prayers) { $cfg.PauseDurations[$p] = $DefaultDurations[$p] }
    if (Test-Path $ConfigFile) {
        try {
            $raw = Get-Content $ConfigFile -Raw | ConvertFrom-Json
            foreach ($p in $Prayers) {
                $v = $raw.PauseDurations.$p
                if ($null -ne $v) { $cfg.PauseDurations[$p] = [int]$v }
            }
            if ($null -ne $raw.AthanOffsetMinutes) {
                $cfg.AthanOffsetMinutes = [int]$raw.AthanOffsetMinutes
            }
        } catch {}
    }
    return $cfg
}

function Save-Config {
    param([hashtable]$Config)
    $obj = [ordered]@{
        AthanOffsetMinutes = [int]$Config.AthanOffsetMinutes
        PauseDurations     = [ordered]@{}
    }
    foreach ($p in $Prayers) { $obj.PauseDurations[$p] = [int]$Config.PauseDurations[$p] }
    $obj | ConvertTo-Json -Depth 5 | Out-File -FilePath $ConfigFile -Encoding UTF8 -Force
}

# ---------- data helpers ----------------------------------------------------

function Get-TodaysSchedule {
    $rows = @()
    $now  = Get-Date
    foreach ($p in $Prayers) {
        $pauseTask  = Get-ScheduledTask -TaskName "GymPrayerPauser_${p}_Pause"  -ErrorAction SilentlyContinue
        $resumeTask = Get-ScheduledTask -TaskName "GymPrayerPauser_${p}_Resume" -ErrorAction SilentlyContinue

        $pauseTime = $null
        $resumeTime = $null
        if ($pauseTask  -and $pauseTask.Triggers.Count  -gt 0) {
            try { $pauseTime  = [datetime]::Parse($pauseTask.Triggers[0].StartBoundary)  } catch {}
        }
        if ($resumeTask -and $resumeTask.Triggers.Count -gt 0) {
            try { $resumeTime = [datetime]::Parse($resumeTask.Triggers[0].StartBoundary) } catch {}
        }

        $status = if (-not $pauseTime) {
            'Done (or not scheduled)'
        } elseif ($resumeTime -and $resumeTime -lt $now) {
            'Done'
        } elseif ($pauseTime -lt $now -and (-not $resumeTime -or $resumeTime -gt $now)) {
            'Paused now'
        } else {
            'Upcoming'
        }

        $rows += [PSCustomObject]@{
            Prayer   = $p
            PauseAt  = if ($pauseTime)  { $pauseTime.ToString('h:mm tt') }  else { '-' }
            ResumeAt = if ($resumeTime) { $resumeTime.ToString('h:mm tt') } else { '-' }
            Status   = $status
        }
    }
    return $rows
}

function Format-LogLine {
    param([string]$line)
    if ($line -notmatch '^(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s+(.+)$') {
        return $null
    }
    $stamp = [datetime]::Parse("$($matches[1]) $($matches[2])")
    $body  = $matches[3].Trim()
    $today = (Get-Date).Date
    $when  = if ($stamp.Date -eq $today)               { 'Today' }
             elseif ($stamp.Date -eq $today.AddDays(-1)) { 'Yesterday' }
             else                                       { $stamp.ToString('ddd MMM d') }
    $time  = $stamp.ToString('h:mm tt')

    $friendly = $null
    if     ($body -match 'Sent VK_MEDIA_PLAY_PAUSE \[(\w+)-Pause\]')   { $friendly = "Paused for $($matches[1])" }
    elseif ($body -match 'Sent VK_MEDIA_PLAY_PAUSE \[(\w+)-Resume\]')  { $friendly = "Resumed after $($matches[1])" }
    elseif ($body -match 'Sent VK_MEDIA_PLAY_PAUSE \[Manual')          { $friendly = 'Manual test pause' }
    elseif ($body -match 'SKIPPED.*skip-today')                        { $friendly = 'Skipped (skip-today is on)' }
    elseif ($body -match 'Daily schedule rebuild starting')            { $friendly = "Rebuilding today's schedule..." }
    elseif ($body -match 'Daily schedule rebuild complete')            { $friendly = "Today's schedule ready" }
    elseif ($body -match "Fetched today's times")                      { $friendly = 'Got prayer times from the internet' }
    elseif ($body -match 'Falling back to cached')                     { $friendly = "Internet down - using yesterday's times" }
    elseif ($body -match '^ERROR')                                     { $friendly = "Problem: $body" }
    elseif ($body -match '^FATAL')                                     { $friendly = "Problem: $body" }
    # Filter out noisy lines a non-technical user doesn't need:
    elseif ($body -match '^Scheduled ')                                { return $null }
    elseif ($body -match '^Removed old task')                          { return $null }
    elseif ($body -match '^Running as user')                           { return $null }
    elseif ($body -match 'AthanOffsetMinutes')                         { return $null }
    elseif ($body -match '^Skipping ')                                 { return $null }
    elseif ($body -match '^Cleared stale skip')                        { return $null }

    if (-not $friendly) { return $null }
    return "{0,-9} {1,-9}  {2}" -f $when, $time, $friendly
}

function Get-RecentLog {
    param([int]$Max = 40)
    if (-not (Test-Path $LogFile)) {
        return @('(No activity recorded yet.)')
    }
    $raw = Get-Content $LogFile -Tail 500
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($l in $raw) {
        $t = Format-LogLine $l
        if ($t) { $out.Add($t) }
    }
    if ($out.Count -eq 0) {
        return @('(No activity recorded yet.)')
    }
    $arr = $out.ToArray()
    [array]::Reverse($arr)
    return $arr | Select-Object -First $Max
}

# ---------- form ------------------------------------------------------------

$colorBg       = [System.Drawing.Color]::White
$colorAccent   = [System.Drawing.Color]::FromArgb(30, 100, 180)
$colorMuted    = [System.Drawing.Color]::FromArgb(120, 120, 120)
$colorActive   = [System.Drawing.Color]::FromArgb(255, 248, 200)
$colorDanger   = [System.Drawing.Color]::FromArgb(200, 70, 70)

$titleFont = New-Object System.Drawing.Font('Segoe UI', 14, [System.Drawing.FontStyle]::Bold)
$labelFont = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$bodyFont  = New-Object System.Drawing.Font('Segoe UI', 10)
$monoFont  = New-Object System.Drawing.Font('Consolas',  10)

$form = New-Object System.Windows.Forms.Form
$form.Text          = 'Gym Prayer Pauser'
$form.Size          = New-Object System.Drawing.Size(720, 780)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox   = $false
$form.BackColor     = $colorBg
$iconPath = Join-Path $InstallDir 'app.ico'
if (Test-Path $iconPath) {
    try { $form.Icon = New-Object System.Drawing.Icon($iconPath) } catch {}
}

# --- Today's schedule -------------------------------------------------------

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text       = "Today's Prayer Schedule"
$lblTitle.Font       = $titleFont
$lblTitle.ForeColor  = $colorAccent
$lblTitle.AutoSize   = $true
$lblTitle.Location   = New-Object System.Drawing.Point(20, 15)
$form.Controls.Add($lblTitle)

$lblDate = New-Object System.Windows.Forms.Label
$lblDate.Text      = (Get-Date).ToString('dddd, MMMM d, yyyy')
$lblDate.Font      = $bodyFont
$lblDate.ForeColor = $colorMuted
$lblDate.AutoSize  = $true
$lblDate.Location  = New-Object System.Drawing.Point(22, 45)
$form.Controls.Add($lblDate)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location               = New-Object System.Drawing.Point(20, 75)
$grid.Size                   = New-Object System.Drawing.Size(670, 195)
$grid.AllowUserToAddRows     = $false
$grid.AllowUserToDeleteRows  = $false
$grid.AllowUserToResizeRows  = $false
$grid.AllowUserToResizeColumns = $false
$grid.ReadOnly               = $true
$grid.RowHeadersVisible      = $false
$grid.SelectionMode          = 'FullRowSelect'
$grid.MultiSelect            = $false
$grid.BackgroundColor        = $colorBg
$grid.BorderStyle            = 'FixedSingle'
$grid.EnableHeadersVisualStyles = $false
$grid.ColumnHeadersDefaultCellStyle.Font      = $labelFont
$grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(240,240,240)
$grid.ColumnHeadersDefaultCellStyle.ForeColor = [System.Drawing.Color]::Black
$grid.ColumnHeadersHeight    = 32
$grid.DefaultCellStyle.Font  = $bodyFont
$grid.DefaultCellStyle.SelectionBackColor = [System.Drawing.Color]::FromArgb(220, 235, 250)
$grid.DefaultCellStyle.SelectionForeColor = [System.Drawing.Color]::Black
$grid.RowTemplate.Height     = 30
$grid.ColumnCount = 4
$grid.Columns[0].Name = 'Prayer'
$grid.Columns[1].Name = 'Pause At'
$grid.Columns[2].Name = 'Resume At'
$grid.Columns[3].Name = 'Status'
$grid.Columns[0].Width = 130
$grid.Columns[1].Width = 170
$grid.Columns[2].Width = 170
$grid.Columns[3].Width = 195
$form.Controls.Add($grid)

# --- Pause Durations (settings) --------------------------------------------

$lblSettings = New-Object System.Windows.Forms.Label
$lblSettings.Text       = 'Pause Durations (minutes)'
$lblSettings.Font       = $titleFont
$lblSettings.ForeColor  = $colorAccent
$lblSettings.AutoSize   = $true
$lblSettings.Location   = New-Object System.Drawing.Point(20, 285)
$form.Controls.Add($lblSettings)

$pnlSettings = New-Object System.Windows.Forms.Panel
$pnlSettings.Location    = New-Object System.Drawing.Point(20, 320)
$pnlSettings.Size        = New-Object System.Drawing.Size(670, 85)
$pnlSettings.BorderStyle = 'FixedSingle'
$pnlSettings.BackColor   = [System.Drawing.Color]::FromArgb(250, 250, 252)
$form.Controls.Add($pnlSettings)

$spinners = @{}
$startCfg = Read-Config
$xPos = 18
foreach ($p in $Prayers) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text     = $p
    $lbl.Font     = $labelFont
    $lbl.AutoSize = $true
    $lbl.Location = New-Object System.Drawing.Point($xPos, 8)
    $pnlSettings.Controls.Add($lbl)

    $spn = New-Object System.Windows.Forms.NumericUpDown
    $spn.Location  = New-Object System.Drawing.Point($xPos, 32)
    $spn.Size      = New-Object System.Drawing.Size(72, 30)
    $spn.Minimum   = 1
    $spn.Maximum   = 240
    $spn.Value     = [int]$startCfg.PauseDurations[$p]
    $spn.Font      = $bodyFont
    $pnlSettings.Controls.Add($spn)
    $spinners[$p] = $spn

    $xPos += 90
}

# Offset spinner
$lblOff = New-Object System.Windows.Forms.Label
$lblOff.Text     = 'Athan offset'
$lblOff.Font     = $labelFont
$lblOff.AutoSize = $true
$lblOff.Location = New-Object System.Drawing.Point(490, 8)
$pnlSettings.Controls.Add($lblOff)

$spnOffset = New-Object System.Windows.Forms.NumericUpDown
$spnOffset.Location  = New-Object System.Drawing.Point(490, 32)
$spnOffset.Size      = New-Object System.Drawing.Size(72, 30)
$spnOffset.Minimum   = -60
$spnOffset.Maximum   = 60
$spnOffset.Value     = [int]$startCfg.AthanOffsetMinutes
$spnOffset.Font      = $bodyFont
$pnlSettings.Controls.Add($spnOffset)

# Save button (inside the settings panel)
$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text      = 'Save && Apply'
$btnSave.Font      = $labelFont
$btnSave.Location  = New-Object System.Drawing.Point(580, 28)
$btnSave.Size      = New-Object System.Drawing.Size(80, 38)
$btnSave.BackColor = $colorAccent
$btnSave.ForeColor = [System.Drawing.Color]::White
$btnSave.FlatStyle = 'Flat'
$btnSave.FlatAppearance.BorderColor = $colorAccent
$pnlSettings.Controls.Add($btnSave)

# --- Recent Activity --------------------------------------------------------

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text       = 'Recent Activity'
$lblLog.Font       = $titleFont
$lblLog.ForeColor  = $colorAccent
$lblLog.AutoSize   = $true
$lblLog.Location   = New-Object System.Drawing.Point(20, 420)
$form.Controls.Add($lblLog)

$logBox = New-Object System.Windows.Forms.ListBox
$logBox.Location    = New-Object System.Drawing.Point(20, 455)
$logBox.Size        = New-Object System.Drawing.Size(670, 195)
$logBox.Font        = $monoFont
$logBox.BorderStyle = 'FixedSingle'
$logBox.IntegralHeight = $false
$form.Controls.Add($logBox)

# --- Bottom buttons ---------------------------------------------------------

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text     = 'Refresh'
$btnRefresh.Font     = $labelFont
$btnRefresh.Location = New-Object System.Drawing.Point(20, 670)
$btnRefresh.Size     = New-Object System.Drawing.Size(120, 40)
$btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
$btnRefresh.FlatStyle = 'Flat'
$btnRefresh.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200,200,200)
$form.Controls.Add($btnRefresh)

$btnTest = New-Object System.Windows.Forms.Button
$btnTest.Text     = 'Test Pause'
$btnTest.Font     = $labelFont
$btnTest.Location = New-Object System.Drawing.Point(150, 670)
$btnTest.Size     = New-Object System.Drawing.Size(120, 40)
$btnTest.BackColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
$btnTest.FlatStyle = 'Flat'
$btnTest.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200,200,200)
$form.Controls.Add($btnTest)

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text      = 'Uninstall'
$btnUninstall.Font      = $labelFont
$btnUninstall.Location  = New-Object System.Drawing.Point(570, 670)
$btnUninstall.Size      = New-Object System.Drawing.Size(120, 40)
$btnUninstall.BackColor = $colorDanger
$btnUninstall.ForeColor = [System.Drawing.Color]::White
$btnUninstall.FlatStyle = 'Flat'
$btnUninstall.FlatAppearance.BorderColor = $colorDanger
$form.Controls.Add($btnUninstall)

# ---------- behaviour -------------------------------------------------------

function Update-View {
    $grid.Rows.Clear()
    foreach ($row in Get-TodaysSchedule) {
        $idx = $grid.Rows.Add($row.Prayer, $row.PauseAt, $row.ResumeAt, $row.Status)
        $r = $grid.Rows[$idx]
        switch ($row.Status) {
            'Done' {
                $r.DefaultCellStyle.ForeColor = $colorMuted
            }
            'Paused now' {
                $r.DefaultCellStyle.BackColor = $colorActive
                $r.DefaultCellStyle.Font      = $labelFont
                $r.DefaultCellStyle.ForeColor = [System.Drawing.Color]::FromArgb(120,80,0)
            }
            'Upcoming' {
                $r.DefaultCellStyle.ForeColor = $colorAccent
                $r.DefaultCellStyle.Font      = $labelFont
            }
            default {
                $r.DefaultCellStyle.ForeColor = $colorMuted
            }
        }
    }

    $logBox.BeginUpdate()
    $logBox.Items.Clear()
    foreach ($l in Get-RecentLog -Max 40) {
        [void]$logBox.Items.Add($l)
    }
    $logBox.EndUpdate()
}

$btnRefresh.Add_Click({ Update-View })

$btnSave.Add_Click({
    # Snapshot the values from the spinners.
    $newCfg = @{
        PauseDurations    = @{}
        AthanOffsetMinutes = [int]$spnOffset.Value
    }
    foreach ($p in $Prayers) {
        $newCfg.PauseDurations[$p] = [int]$spinners[$p].Value
    }

    try {
        Save-Config -Config $newCfg
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not save settings: $_",
            'Error', [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }

    # Re-running the scheduler needs admin (it registers scheduled tasks).
    # Start-Process -Verb RunAs triggers the UAC prompt.
    $applied = $false
    try {
        $proc = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @('-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$ScheduleScript) `
            -Verb RunAs -Wait -PassThru -ErrorAction Stop
        $applied = ($proc.ExitCode -eq 0)
    } catch {
        # Most common cause: user clicked No on the UAC prompt.
        $applied = $false
    }

    Update-View

    if ($applied) {
        [System.Windows.Forms.MessageBox]::Show(
            "Settings saved and applied to today's remaining prayers.",
            'Saved', [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Settings saved.`n`nThey will take effect automatically at midnight. To apply them to TODAY's remaining prayers, click Save & Apply again and accept the admin prompt.",
            'Saved (not applied yet)', [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
})

$btnTest.Add_Click({
    try {
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @('-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$MediaScript,'-Reason','Manual-Test') `
            -WindowStyle Hidden
        Start-Sleep -Milliseconds 400
        Update-View
        [System.Windows.Forms.MessageBox]::Show(
            "Test pause sent.`n`nIf music was playing, it should have paused. Click Test Pause again to resume.",
            'Test', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not send test pause: $_", 'Error',
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$btnUninstall.Add_Click({
    $msg = "This will COMPLETELY REMOVE the Gym Prayer Pauser:" + [Environment]::NewLine + [Environment]::NewLine +
           "  - All scheduled prayer pauses will be deleted" + [Environment]::NewLine +
           "  - The C:\GymPrayerPauser folder will be removed" + [Environment]::NewLine +
           "  - This desktop shortcut will be removed" + [Environment]::NewLine + [Environment]::NewLine +
           "Music will no longer pause automatically at prayer times." + [Environment]::NewLine + [Environment]::NewLine +
           "Are you sure?"
    $answer = [System.Windows.Forms.MessageBox]::Show(
        $msg, 'Confirm Uninstall',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        Start-Process -FilePath $UninstallBat -Verb RunAs -Wait
        [System.Windows.Forms.MessageBox]::Show('Uninstall complete. This window will now close.',
            'Done', [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        $form.Close()
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Could not run uninstaller: $_",
            'Error', [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

# Auto-refresh every 30 seconds so status keeps up.
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30000
$timer.Add_Tick({ Update-View })
$timer.Start()

Update-View
[void]$form.ShowDialog()
$timer.Stop()
