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
$Prayers      = @('Fajr','Dhuhr','Asr','Maghrib','Isha')

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
$form.Size          = New-Object System.Drawing.Size(580, 670)
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
$grid.Size                   = New-Object System.Drawing.Size(530, 195)
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
$grid.Columns[0].Width = 110
$grid.Columns[1].Width = 130
$grid.Columns[2].Width = 130
$grid.Columns[3].Width = 155
$form.Controls.Add($grid)

# --- Recent Activity --------------------------------------------------------

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text       = 'Recent Activity'
$lblLog.Font       = $titleFont
$lblLog.ForeColor  = $colorAccent
$lblLog.AutoSize   = $true
$lblLog.Location   = New-Object System.Drawing.Point(20, 290)
$form.Controls.Add($lblLog)

$logBox = New-Object System.Windows.Forms.ListBox
$logBox.Location    = New-Object System.Drawing.Point(20, 325)
$logBox.Size        = New-Object System.Drawing.Size(530, 230)
$logBox.Font        = $monoFont
$logBox.BorderStyle = 'FixedSingle'
$logBox.IntegralHeight = $false
$form.Controls.Add($logBox)

# --- Buttons ----------------------------------------------------------------

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text     = 'Refresh'
$btnRefresh.Font     = $labelFont
$btnRefresh.Location = New-Object System.Drawing.Point(20, 575)
$btnRefresh.Size     = New-Object System.Drawing.Size(120, 40)
$btnRefresh.BackColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
$btnRefresh.FlatStyle = 'Flat'
$btnRefresh.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200,200,200)
$form.Controls.Add($btnRefresh)

$btnTest = New-Object System.Windows.Forms.Button
$btnTest.Text     = 'Test Pause'
$btnTest.Font     = $labelFont
$btnTest.Location = New-Object System.Drawing.Point(150, 575)
$btnTest.Size     = New-Object System.Drawing.Size(120, 40)
$btnTest.BackColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
$btnTest.FlatStyle = 'Flat'
$btnTest.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(200,200,200)
$form.Controls.Add($btnTest)

$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Text      = 'Uninstall'
$btnUninstall.Font      = $labelFont
$btnUninstall.Location  = New-Object System.Drawing.Point(430, 575)
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
