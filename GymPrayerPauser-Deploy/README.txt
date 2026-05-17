GymPrayerPauser
================
Automatically pauses music/video on this Windows PC at each of the five
daily prayer times for Kuwait City, then resumes playback after a
configurable number of minutes.


HOW IT WORKS
------------
* A master Windows Task Scheduler job ("GymPrayerPauser_Daily") runs every
  day at 00:05.
* It fetches today's prayer times from the Aladhan API (method 9, Kuwait
  Ministry of Awqaf) and writes 10 one-shot scheduled tasks for today:
  Pause + Resume for each of Fajr, Dhuhr, Asr, Maghrib, Isha.
* At each pause and resume time, the system sends the standard Windows
  "Play/Pause" media key. Spotify, Apple Music, YouTube in any browser,
  VLC, etc. all respond to it.
* All actions are logged to:  C:\GymPrayerPauser\log.txt
* If the internet is down at 00:05, the script falls back to yesterday's
  cached prayer times (off by 1-2 minutes at most).


INSTALL
-------
1. Copy the whole "GymPrayerPauser-Deploy" folder onto the gym PC
   (USB stick is fine). Put it anywhere - Desktop is easiest.
2. Make sure the gym PC is logged in as the regular daily-use Windows
   account. Tasks run inside the logged-in user session - that's what
   lets the media keys reach Spotify / the browser.
3. Right-click  install.bat  and choose  "Run as administrator".
4. When it finishes you should see a list of scheduled tasks ending in
   _Pause / _Resume, and  C:\GymPrayerPauser\log.txt  will exist with
   "Daily schedule rebuild complete".

That's it. Leave the PC logged in. The schedule rebuilds itself every
night at 00:05.


UNINSTALL
---------
Right-click  uninstall.bat  and choose  "Run as administrator".
Removes all GymPrayerPauser_* scheduled tasks and deletes
C:\GymPrayerPauser\.


CHANGING PAUSE DURATIONS OR THE ATHAN OFFSET (no reinstall needed)
------------------------------------------------------------------
1. Open  C:\GymPrayerPauser\Schedule-PrayerPauses.ps1  in Notepad
   (right-click -> Edit, or open Notepad as admin and File -> Open).
2. Near the top you'll see:

       $PauseDurations = @{
           Fajr    = 25
           Dhuhr   = 20
           Asr     = 20
           Maghrib = 20
           Isha    = 20
       }
       $AthanOffsetMinutes = 0

   - Change a duration (in minutes) to whatever you want.
   - $AthanOffsetMinutes shifts ALL prayer pause times by +/- N minutes.
     For example, set it to -2 if your local mosque starts the Athan two
     minutes before the calculated time.
3. Save the file.
4. To apply the change to TODAY immediately, open PowerShell and run:

       powershell.exe -ExecutionPolicy Bypass -File C:\GymPrayerPauser\Schedule-PrayerPauses.ps1

   Otherwise the change takes effect automatically at 00:05 tonight.


SKIP TODAY (e.g. gym event, special class)
------------------------------------------
Create an empty file called  skip-today.flag  inside the install folder.
Both Pause and Resume actions will see it and do nothing, for today only.

Easiest way - open Command Prompt (no admin needed) and run:

    type nul > C:\GymPrayerPauser\skip-today.flag

The flag only counts as "today" based on the file's modified date, so it
auto-expires at midnight. (If a stale flag is still around the next day,
the pause script deletes it on first run.)

To CANCEL the skip before the day is over, just delete the file:

    del C:\GymPrayerPauser\skip-today.flag


MANUAL TEST PAUSE (verify everything works on the gym PC)
---------------------------------------------------------
The simplest test: start any music (Spotify, YouTube, whatever), then
open Command Prompt or PowerShell and run:

    powershell.exe -ExecutionPolicy Bypass -File C:\GymPrayerPauser\Send-MediaKey.ps1 -Reason Manual-Test

Music should pause. Run it again to resume. Check
C:\GymPrayerPauser\log.txt to confirm an entry like:

    2026-05-17 14:32:01  Sent VK_MEDIA_PLAY_PAUSE [Manual-Test]

To test the FULL scheduling pipeline (a fake prayer two minutes from
now), open an admin Command Prompt and run (replace HH:MM with a time
~2 minutes ahead):

    schtasks /Create /TN "GymPrayerPauser_Test_Pause" /TR "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\GymPrayerPauser\Send-MediaKey.ps1 -Reason Test-Pause" /SC ONCE /ST HH:MM /F

Then watch your music. After confirming, delete it:

    schtasks /Delete /TN "GymPrayerPauser_Test_Pause" /F


WHERE TO LOOK / AUDIT
---------------------
* Log file:    C:\GymPrayerPauser\log.txt
  Every action (fetch, schedule, pause, resume, skip, error) gets a
  timestamped line. Open it any time in Notepad.

* Today's cached prayer times:  C:\GymPrayerPauser\prayer-cache.json

* Scheduled tasks list (PowerShell):

      Get-ScheduledTask | Where-Object { $_.TaskName -like 'GymPrayerPauser_*' } | Format-Table TaskName,State

  You should see "GymPrayerPauser_Daily" plus 10 per-prayer tasks
  (Fajr_Pause, Fajr_Resume, Dhuhr_Pause, ...) - minus any that have
  already fired today.

* Last result of the daily task:

      Get-ScheduledTaskInfo -TaskName GymPrayerPauser_Daily


TROUBLESHOOTING
---------------
"Nothing happens at the prayer time."
  - Was the PC awake and logged in? Interactive media keys only work
    inside an active user session.
  - Check log.txt for a "Sent VK_MEDIA_PLAY_PAUSE" line at that time.
    If it's there, the script fired correctly and the issue is in
    whatever media app you're using - try a manual test with the same
    app.

"Times are off by a minute or two."
  - The API can drift slightly day to day, and the local mosque may not
    match the calculated Athan exactly. Use $AthanOffsetMinutes to nudge
    everything by +/- a few minutes.

"Master task isn't running at 00:05."
  - The PC must be on and the user logged in. The task is set with
    "Start when available", so if the PC was off it will run on the next
    login - but only once a day. You can also right-click the task in
    Task Scheduler and choose Run to rebuild today's schedule any time.

"I changed the script but nothing changed."
  - The script is read fresh every time the master task runs, so changes
    take effect at the next 00:05. To apply immediately, manually run:
        powershell.exe -ExecutionPolicy Bypass -File C:\GymPrayerPauser\Schedule-PrayerPauses.ps1
