# Launch both terminals tiled to halves, verify identical grids, film the race.
#   film-launch.ps1 [-Probe] [-OursW 632] [-OursH 762] [-WtCols 78] [-WtRows 43]
param(
    [switch]$Probe,
    [int]$OursW = 632,
    [int]$OursH = 762,
    [int]$WtCols = 78,
    [int]$WtRows = 43,
    [int]$FilmSeconds = 80,
    [string]$FilmDir = 'C:\film'
)
$ErrorActionPreference = 'Continue'
$log = Join-Path $FilmDir 'launch.txt'
"start $(Get-Date -Format HH:mm:ss)" | Set-Content -Encoding ascii $log
function L($m) { Add-Content -Encoding ascii $log $m }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
"@

# This script runs as a scheduled task, and on Windows 11 a task's console
# host IS WindowsTerminal — so a blanket kill takes out our own host and the
# task dies with 0xC000013A and one line of log. Snapshot the pids that
# existed before we started and never touch those. (bench-long.ps1 learned
# this the same way.)
$preWT = @(Get-Process WindowsTerminal -EA SilentlyContinue | ForEach-Object { $_.Id })
L "pre-existing WindowsTerminal (never killed): $($preWT -join ',')"
Get-Process TerminalApp -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
foreach ($p in @(Get-Process WindowsTerminal -EA SilentlyContinue)) {
    if ($preWT -notcontains $p.Id) { Stop-Process -Id $p.Id -Force -EA SilentlyContinue }
}
# Kill stale runners by command line. A previous probe's race.ps1 survives
# inside a window this script now treats as pre-existing (so never kills), and
# it keeps writing grid-<label> five times a second — the next run's runner
# then dies on "the process cannot access the file ... used by another
# process" and no grid is ever published.
$stale = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
           Where-Object { $_.CommandLine -like '*race.ps1*' })
foreach ($sp in $stale) { Stop-Process -Id $sp.ProcessId -Force -EA SilentlyContinue }
L "killed $($stale.Count) stale race.ps1 runner(s)"
Remove-Item (Join-Path $FilmDir 'grid-*') -Force -EA SilentlyContinue
Start-Sleep -Seconds 2
Remove-Item (Join-Path $FilmDir 'GO'), (Join-Path $FilmDir 'grid-*'), (Join-Path $FilmDir 'done-*'), (Join-Path $FilmDir 'times-*') -Force -EA SilentlyContinue

# Windows Terminal windows are found by class, not pid: `wt.exe` hands the
# command to an existing instance and exits, so there is often no new process
# to find — and with one process hosting several windows, MainWindowHandle is
# the wrong window anyway.
function Get-WtWindows {
    $res = @()
    $h = [W]::GetWindow([W]::GetDesktopWindow(), 5)   # GW_CHILD
    while ($h -ne [IntPtr]::Zero) {
        $sb = New-Object System.Text.StringBuilder 256
        [void][W]::GetClassName($h, $sb, 256)
        if ($sb.ToString() -eq 'CASCADIA_HOSTING_WINDOW_CLASS' -and [W]::IsWindowVisible($h)) { $res += $h }
        $h = [W]::GetWindow($h, 2)                    # GW_HWNDNEXT
    }
    return $res
}

$runner = 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\film\race.ps1'

# --- ours, left half -------------------------------------------------------
$env:STARLING_WINDOW_W = "$OursW"
$env:STARLING_WINDOW_H = "$OursH"
$env:STARLING_DEV_SHELL = "$runner -Label ours -Name `"STARLING TERMINAL`""
Start-Process 'C:\dist\TerminalApp\TerminalApp.exe'
Start-Sleep -Seconds 10
$ours = Get-Process TerminalApp -EA SilentlyContinue | Select-Object -First 1
if ($ours) { [void][W]::SetWindowPos($ours.MainWindowHandle, [IntPtr]::Zero, 0, 0, 640, 800, 0x0040) }
L "ours pid=$($ours.Id)"

# --- Windows Terminal, right half -----------------------------------------
$preWin = @(Get-WtWindows)
L "pre-existing wt windows: $($preWin.Count)"
Start-Process 'wt.exe' -ArgumentList "--window new --size $WtCols,$WtRows $runner -Label wt -Name `"WINDOWS TERMINAL`""
Start-Sleep -Seconds 10
$wtWin = @(Get-WtWindows) | Where-Object { $preWin -notcontains $_ } | Select-Object -First 1
if ($wtWin) { [void][W]::SetWindowPos($wtWin, [IntPtr]::Zero, 640, 0, 640, 800, 0x0040) }
L "wt hwnd=$wtWin"

Start-Sleep -Seconds 4
$g1 = (Get-Content (Join-Path $FilmDir 'grid-ours') -EA SilentlyContinue)
$g2 = (Get-Content (Join-Path $FilmDir 'grid-wt')   -EA SilentlyContinue)
L "grids: ours=$g1 wt=$g2  match=$($g1 -eq $g2)"

if ($Probe) { L 'probe only, not filming'; return }
if ($g1 -ne $g2) { L 'GRID MISMATCH - refusing to film'; return }

# --- film ------------------------------------------------------------------
$mp4 = Join-Path $FilmDir 'race-raw.mp4'
Remove-Item $mp4 -Force -EA SilentlyContinue
$ff = Start-Process 'C:\film\ffmpeg.exe' -PassThru -WindowStyle Hidden -ArgumentList @(
  '-y','-f','gdigrab','-framerate','30','-offset_x','0','-offset_y','0',
  '-video_size','1280x800','-i','desktop','-t',"$FilmSeconds",
  '-c:v','libx264','-preset','veryfast','-crf','20','-pix_fmt','yuv420p', "`"$mp4`"")
L "ffmpeg pid=$($ff.Id)"
Start-Sleep -Seconds 3

New-Item -ItemType File -Path (Join-Path $FilmDir 'GO') -Force | Out-Null
L "GO at $(Get-Date -Format HH:mm:ss.fff)"

$deadline = (Get-Date).AddSeconds($FilmSeconds + 20)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    if ((Test-Path (Join-Path $FilmDir 'done-ours')) -and (Test-Path (Join-Path $FilmDir 'done-wt'))) {
        L "both done at $(Get-Date -Format HH:mm:ss.fff)"
        break
    }
}
# ffmpeg stops itself at -t; wait it out so the mp4 is finalised.
$ff.WaitForExit(($FilmSeconds + 40) * 1000) | Out-Null
L "times ours: $(Get-Content (Join-Path $FilmDir 'times-ours') -EA SilentlyContinue)"
L "times wt:   $(Get-Content (Join-Path $FilmDir 'times-wt')   -EA SilentlyContinue)"
L "mp4: $([math]::Round((Get-Item $mp4 -EA SilentlyContinue).Length/1MB,1)) MB"
L 'done'
