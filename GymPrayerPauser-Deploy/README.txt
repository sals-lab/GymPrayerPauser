Gym Prayer Pauser
=================
Automatically pauses music/video on this Windows PC at each of the five
daily prayer times for Kuwait City, and resumes playback after a few
minutes (configurable per prayer).


WHAT THE GYM STAFF NEEDS TO KNOW
--------------------------------
After installation there is a "Gym Prayer Pauser" icon on the Desktop.
Double-click it to open a small window that shows:

  - Today's prayer schedule (pause time, resume time, status)
  - Pause Durations (minutes) - one number for each prayer, plus an
    "Athan offset" that shifts every prayer by +/- a few minutes. Type
    or click the up/down arrows, then press "Save & Apply".
    Saving needs admin permission (Windows will ask).
  - Recent activity (what the program has done, in plain English)
  - "Refresh"     - reload status now
  - "Test Pause"  - send a play/pause keystroke right now, to confirm
                    music actually pauses on this PC
  - "Uninstall"   - completely remove the program (asks to confirm)

That's it. There's nothing else to click or configure day-to-day.


HOW IT WORKS (FOR THE INSTALLER, NOT THE GYM STAFF)
---------------------------------------------------
* A master Windows scheduled task ("GymPrayerPauser_Daily") runs every
  day at 00:05.
* It fetches today's prayer times from the Aladhan API
  (method 9 - Kuwait Ministry of Awqaf) and writes 10 one-shot
  scheduled tasks for today: Pause + Resume for each of Fajr, Dhuhr,
  Asr, Maghrib, Isha.
* At each pause / resume time the system sends the standard Windows
  Play/Pause media key. Spotify, Apple Music, YouTube in any browser,
  VLC, and most other players respond to it.
* All actions are logged to:  C:\GymPrayerPauser\log.txt
* If the internet is down at 00:05 the script uses yesterday's cached
  prayer times (off by 1-2 minutes at most).


INSTALL
-------
1. Copy the whole deploy folder onto the gym PC (USB stick, or download
   the ZIP from GitHub).
   If you downloaded from the internet, first unblock the files so
   Windows does not warn on every launch. Open PowerShell as
   Administrator and run:

       Get-ChildItem -Path "<the unzipped folder>" -Recurse | Unblock-File

2. Make sure the gym PC is logged in as the regular daily-use Windows
   account. Tasks run inside the logged-in user session - that is what
   lets the media key reach Spotify / the browser.

3. Right-click  install.bat  and choose  "Run as administrator".

When it finishes:
  - A "Gym Prayer Pauser" shortcut appears on the Desktop.
  - C:\GymPrayerPauser\log.txt exists with "Daily schedule rebuild
    complete".
  - The current power plan has "Allow wake timers" turned on so the
    PC can wake up from sleep to run scheduled prayer pauses.


KEEPING THE PC ON
-----------------
Scheduled tasks only fire while a user is logged in. The installer
turns on wake timers, so a sleeping PC can be woken to run a task.
But if the PC is fully powered off, or no one is logged in, nothing
runs.

For a gym PC the safest setup is:
  - Keep one Windows user account permanently logged in (locking the
    screen is fine).
  - Set "Sleep" to "Never" on AC power (Control Panel -> Power Options
    -> Change plan settings).


UNINSTALL
---------
Two options:

  A) Open the GUI from the Desktop icon and click "Uninstall".
     It will prompt for admin permission and then remove everything.

  B) Right-click  uninstall.bat  in the install folder and choose
     "Run as administrator".

Both options remove all GymPrayerPauser_* scheduled tasks, the
C:\GymPrayerPauser folder, and the Desktop shortcut.


CHANGING PAUSE DURATIONS OR THE ATHAN OFFSET
--------------------------------------------
The easy way (recommended for gym staff):

  1. Double-click the "Gym Prayer Pauser" icon on the Desktop.
  2. In the "Pause Durations (minutes)" row, adjust the values for any
     prayer, and optionally the "Athan offset" (e.g. -2 if your mosque
     starts the call to prayer two minutes before the calculated time).
  3. Click "Save & Apply". Windows will ask for admin permission - say
     Yes. Today's remaining prayers get re-scheduled immediately, and
     the new values persist forever (saved in config.json).

If you decline the admin prompt the values are still saved - they'll
take effect at midnight when the daily schedule rebuilds.

The technical way (for admins editing remotely):
  Edit  C:\GymPrayerPauser\config.json  with Notepad. Format:

       {
         "AthanOffsetMinutes": 0,
         "PauseDurations": {
           "Fajr": 25, "Dhuhr": 20, "Asr": 20, "Maghrib": 20, "Isha": 20
         }
       }

  Save the file. Changes take effect at the next 00:05 rebuild, OR
  immediately if you run:

       powershell.exe -ExecutionPolicy Bypass -File C:\GymPrayerPauser\Schedule-PrayerPauses.ps1

  (must be run as administrator)


SKIP TODAY (e.g. gym event, special class)
------------------------------------------
Create an empty file called  skip-today.flag  inside the install folder:

    type nul > C:\GymPrayerPauser\skip-today.flag

Both Pause and Resume actions will see it and do nothing for the rest
of the day. The flag auto-expires at midnight.

Cancel the skip:

    del C:\GymPrayerPauser\skip-today.flag


WHERE TO LOOK / AUDIT
---------------------
* GUI window:   "Gym Prayer Pauser" on the Desktop. Shows today's
                schedule and a human-readable recent-activity log.
* Raw log:      C:\GymPrayerPauser\log.txt
* Cached times: C:\GymPrayerPauser\prayer-cache.json
* Task list (PowerShell):

      Get-ScheduledTask | Where-Object { $_.TaskName -like 'GymPrayerPauser_*' } | Format-Table TaskName,State

  You should see GymPrayerPauser_Daily plus 10 per-prayer tasks
  (Fajr_Pause, Fajr_Resume, ...) - minus any that have already fired
  today.


TROUBLESHOOTING
---------------
"Nothing happens at the prayer time."
  - Was the PC awake and logged in? Open the GUI and check the
    "Recent Activity" list. If there is no "Paused for X" entry near
    the prayer time, the task did not fire (PC asleep / logged out).
  - If the GUI DOES show "Paused for X" but you didn't hear it pause,
    the issue is on the media-app side. Click "Test Pause" in the GUI
    with music playing to confirm.

"Times are off by a minute or two from the local mosque."
  - Use $AthanOffsetMinutes (see "Changing pause durations" above).

"Master task isn't running at 00:05."
  - The PC must be on AND a user must be logged in (locked is fine).
  - The installer turns on wake timers, but Windows can still refuse
    to wake if the laptop lid is closed, hibernation is in use, or
    the BIOS power settings forbid it. For a desktop gym PC this is
    usually not an issue.
  - You can right-click GymPrayerPauser_Daily in Task Scheduler and
    choose Run to rebuild today's schedule manually any time.

"I changed the script but nothing changed."
  - The script is re-read every time the master task runs, so changes
    take effect at the next 00:05. To apply immediately:

       powershell.exe -ExecutionPolicy Bypass -File C:\GymPrayerPauser\Schedule-PrayerPauses.ps1
