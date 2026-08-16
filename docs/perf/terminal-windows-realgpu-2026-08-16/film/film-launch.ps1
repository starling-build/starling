# Launch both terminals side by side, verify identical grids, film the race.
#
#   film-launch.ps1 [-Probe]
#
# The real-hardware port of ../terminal-windows-fresh-2026-08-15/film/
# film-launch.ps1, which was written for a 1280x800 VM. What changed:
#
#   - the rival is Windows Terminal PREVIEW, launched by full path. `wt.exe`
#     hands the command to whatever Windows Terminal is already running and
#     exits, so on a box where the operator's own shell is a Windows Terminal
#     there is no new process AND no new window to position -- the race would
#     open as a tab inside the session driving it. Preview is a separate
#     package with a separate process. Same reason the round uses it.
#   - the desktop is 3840x2160 at 200% scale. This script is DPI-unaware, so
#     every USER32 coordinate below is in the virtualised 1920x1080 space,
#     while ours is sized in DEVICE pixels through STARLING_WINDOW_W/H. The
#     two are a factor of 2 apart and mixing them up puts the window off
#     screen.
#   - windows are POSITIONED but never RESIZED (SWP_NOSIZE). The 08-15 script
#     passed a size to SetWindowPos, which silently changes the grid it just
#     verified.
#   - ffmpeg captures the whole desktop and scales to 1080p on the way out,
#     rather than grabbing a fixed rectangle: gdigrab's idea of the desktop
#     size depends on the DPI awareness of the ffmpeg build, and a hardcoded
#     -video_size gets a quarter of the screen when that guess is wrong.
param(
    [switch]$Probe,
    # Device pixels for ours: 100 cols x 16 px + 32 chrome, 50 rows x 34.9 + 38.
    [int]$OursW = 1632,
    [int]$OursH = 1783,
    [int]$WtCols = 100,
    [int]$WtRows = 50,
    [string]$Grid = '50x100',
    [int]$FilmSeconds = 95,
    # Minimise this window while filming and restore it afterwards. It is the
    # console running the harness, and the desktop capture would otherwise
    # show it behind the two terminals for the whole video.
    [int]$HideWindowPid = 0,
    [string]$FilmDir = 'C:\film',
    [string]$BenchDir = 'C:\bench'
)
$ErrorActionPreference = 'Continue'
$log = Join-Path $FilmDir 'launch.txt'
"start $(Get-Date -Format HH:mm:ss)" | Set-Content -Encoding ascii $log
function L($m) { Add-Content -Encoding ascii $log $m; $m }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class FW {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  public static System.Collections.Generic.List<IntPtr> ForPid(uint want) {
    var res = new System.Collections.Generic.List<IntPtr>();
    EnumWindows((h,l) => { uint p; GetWindowThreadProcessId(h, out p);
      if (p==want && IsWindowVisible(h)) res.Add(h);
      return true; }, IntPtr.Zero);
    return res; }
  public static System.Collections.Generic.List<IntPtr> AllVisible() {
    var res = new System.Collections.Generic.List<IntPtr>();
    EnumWindows((h,l) => { if (IsWindowVisible(h)) res.Add(h); return true; }, IntPtr.Zero);
    return res; }
}
"@

$pv = Get-AppxPackage Microsoft.WindowsTerminalPreview -EA SilentlyContinue
if (-not $pv) { L 'FATAL: Windows Terminal Preview not installed'; return }
$WT_EXE = Join-Path $pv.InstallLocation 'WindowsTerminal.exe'
L "wt exe $WT_EXE ($($pv.Version))"

# A Preview left over from an earlier probe MUST die before the snapshot
# below, or it is recorded as pre-existing, never killed, and the next launch
# opens the race as a second window inside it -- unpositionable, and sharing
# the process whose cost the film is about.
foreach ($p in @(Get-Process WindowsTerminal -EA SilentlyContinue)) {
    $path = try { $p.Path } catch { '' }
    if ($path -eq $WT_EXE) { Stop-Process -Id $p.Id -Force -EA SilentlyContinue }
}
Start-Sleep -Seconds 2

# Never touch a Windows Terminal that is not ours to kill -- on this box one
# of them is hosting the session running this script.
$preWT = @(Get-Process WindowsTerminal -EA SilentlyContinue | ForEach-Object { $_.Id })
L "pre-existing WindowsTerminal (never killed): $($preWT -join ',')"
Get-Process TerminalApp -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
foreach ($p in @(Get-Process WindowsTerminal -EA SilentlyContinue)) {
    if ($preWT -notcontains $p.Id) { Stop-Process -Id $p.Id -Force -EA SilentlyContinue }
}
# A previous run's race.ps1 can survive inside a window this run now treats as
# pre-existing, and it keeps rewriting grid-<label> five times a second; the
# new runner then dies on "used by another process" and no grid ever appears.
# Excluding THIS process is not paranoia: a caller that mentions race.ps1 on
# its own command line (`Copy-Item ...\race.ps1 ...; & film-launch.ps1 ...`)
# matches here, and the script kills itself -- exit 255, two lines of log, no
# film. Same trap as `pkill -f` matching its own `bash -c` line.
$stale = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -EA SilentlyContinue |
           Where-Object { $_.CommandLine -like '*race.ps1*' -and $_.ProcessId -ne $PID })
foreach ($sp in $stale) { Stop-Process -Id $sp.ProcessId -Force -EA SilentlyContinue }
L "killed $($stale.Count) stale race.ps1 runner(s)"
Start-Sleep -Seconds 2
foreach ($f in @('GO', 'done-ours', 'done-wt', 'times-ours', 'times-wt', 'grid-ours', 'grid-wt')) {
    [System.IO.File]::Delete((Join-Path $FilmDir $f))
}

# Windows Terminal windows are found by class, not by pid: one process can host
# several windows, so MainWindowHandle is the wrong window.
function Get-WtWindows {
    $res = @()
    $h = [FW]::GetWindow([FW]::GetDesktopWindow(), 5)   # GW_CHILD
    while ($h -ne [IntPtr]::Zero) {
        $sb = New-Object System.Text.StringBuilder 256
        [void][FW]::GetClassName($h, $sb, 256)
        if ($sb.ToString() -eq 'CASCADIA_HOSTING_WINDOW_CLASS' -and [FW]::IsWindowVisible($h)) { $res += $h }
        $h = [FW]::GetWindow($h, 2)                     # GW_HWNDNEXT
    }
    return $res
}

$SWP_NOSIZE = 0x0001
$SWP_SHOWWINDOW = 0x0040
$runner = "powershell -NoProfile -ExecutionPolicy Bypass -File $FilmDir\race.ps1 -FilmDir $FilmDir -BenchDir $BenchDir"

# --- ours, left ------------------------------------------------------------
$env:STARLING_WINDOW_W = "$OursW"
$env:STARLING_WINDOW_H = "$OursH"
$env:STARLING_DEV_SHELL = "$runner -Label ours -Name `"STARLING TERMINAL`""
Start-Process 'C:\dist\TerminalApp\TerminalApp.exe'
Start-Sleep -Seconds 10
$ours = Get-Process TerminalApp -EA SilentlyContinue | Select-Object -First 1
if ($ours -and $ours.MainWindowHandle -ne [IntPtr]::Zero) {
    [void][FW]::SetWindowPos($ours.MainWindowHandle, [IntPtr]::Zero, 40, 40, 0, 0, $SWP_NOSIZE -bor $SWP_SHOWWINDOW)
}
L "ours pid=$($ours.Id)"

# --- Windows Terminal Preview, right ---------------------------------------
$preWin = @(Get-WtWindows)
Start-Process $WT_EXE -ArgumentList "--size $WtCols,$WtRows $runner -Label wt -Name `"WINDOWS TERMINAL`""
Start-Sleep -Seconds 10
$wtWin = @(Get-WtWindows) | Where-Object { $preWin -notcontains $_ } | Select-Object -First 1
if ($wtWin) {
    [void][FW]::SetWindowPos($wtWin, [IntPtr]::Zero, 970, 40, 0, 0, $SWP_NOSIZE -bor $SWP_SHOWWINDOW)
}
L "wt hwnd=$wtWin"

Start-Sleep -Seconds 5
$g1 = (Get-Content (Join-Path $FilmDir 'grid-ours') -EA SilentlyContinue)
$g2 = (Get-Content (Join-Path $FilmDir 'grid-wt')   -EA SilentlyContinue)
L "grids: ours=$g1 wt=$g2 want=$Grid match=$($g1 -eq $g2)"

if ($Probe) { L 'probe only, not filming'; return }
if ($g1 -ne $g2)   { L 'GRID MISMATCH - refusing to film'; return }
if ($g1 -ne $Grid) { L "GRID $g1 IS NOT THE TARGET $Grid - refusing to film"; return }

# --- film ------------------------------------------------------------------
# The film dir's copy FIRST. A shell that started before ffmpeg was installed
# does not have it on PATH, Get-Command returns nothing, and the race then
# runs perfectly with nothing recording it -- which is exactly how the first
# take of this film was lost.
$ffmpeg = Join-Path $FilmDir 'ffmpeg.exe'
if (-not (Test-Path $ffmpeg)) { $ffmpeg = (Get-Command ffmpeg -EA SilentlyContinue).Source }
if (-not $ffmpeg) { L 'FATAL: no ffmpeg'; return }
$mp4 = Join-Path $FilmDir 'race-raw.mp4'
[System.IO.File]::Delete($mp4)
$hidden = @()
if ($HideWindowPid -gt 0) {
    # Everything on screen that is not one of the two racers, not just the
    # operator's console: the first take had an Explorer window behind the
    # terminals for its whole length. Desktop and taskbar are left alone --
    # minimising Progman/WorkerW/Shell_TrayWnd does nothing useful and can
    # leave the shell in a strange state.
    $keep = @()
    if ($ours -and $ours.MainWindowHandle -ne [IntPtr]::Zero) { $keep += $ours.MainWindowHandle }
    if ($wtWin) { $keep += $wtWin }
    $skipClass = @('Shell_TrayWnd', 'Progman', 'WorkerW', 'Windows.UI.Core.CoreWindow')
    foreach ($h in [FW]::AllVisible()) {
        if ($keep -contains $h) { continue }
        $sb = New-Object System.Text.StringBuilder 256
        [void][FW]::GetClassName($h, $sb, 256)
        if ($skipClass -contains $sb.ToString()) { continue }
        $r = New-Object FW+RECT
        [void][FW]::GetWindowRect($h, [ref]$r)
        if (($r.R - $r.L) -lt 200 -or ($r.B - $r.T) -lt 200) { continue }
        if ([FW]::ShowWindow($h, 6)) { $hidden += $h }        # 6 = SW_MINIMIZE
    }
    L "minimised $($hidden.Count) window(s) to clear the desktop"
    Start-Sleep -Seconds 2
    # Re-raise the two racers: minimising the operator's window can hand focus
    # to something else entirely.
    if ($ours -and $ours.MainWindowHandle -ne [IntPtr]::Zero) {
        [void][FW]::SetWindowPos($ours.MainWindowHandle, [IntPtr]::Zero, 40, 40, 0, 0, $SWP_NOSIZE -bor $SWP_SHOWWINDOW)
    }
    if ($wtWin) { [void][FW]::SetWindowPos($wtWin, [IntPtr]::Zero, 970, 40, 0, 0, $SWP_NOSIZE -bor $SWP_SHOWWINDOW) }
}

$ff = Start-Process $ffmpeg -PassThru -WindowStyle Hidden -ArgumentList @(
    # ddagrab (Desktop Duplication, on the GPU) rather than gdigrab. gdigrab
    # BitBlts the whole 3840x2160 desktop through GDI and delivers ~12 fps of
    # a requested 30 on this box, so the video stutters AND the capture burns
    # CPU on the cores being measured. ddagrab holds a true 29 fps at 0.99x.
    # The encoder is the Radeon's own, for the same reason.
    # draw_mouse=0: ddagrab composites the cursor in by default, and the first
    # take has a busy-spinner sitting in the middle of our window throughout.
    '-y', '-f', 'lavfi', '-i', 'ddagrab=framerate=30:draw_mouse=0',
    '-t', "$FilmSeconds",
    '-vf', 'hwdownload,format=bgra,scale=1920:-2:flags=bilinear,format=yuv420p',
    '-c:v', 'h264_amf', '-quality', 'speed', '-b:v', '12M',
    "`"$mp4`"")
L "ffmpeg pid=$($ff.Id)"
Start-Sleep -Seconds 3

New-Item -ItemType File -Path (Join-Path $FilmDir 'GO') -Force | Out-Null
L "GO at $(Get-Date -Format HH:mm:ss.fff)"

$deadline = (Get-Date).AddSeconds($FilmSeconds + 30)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    if ((Test-Path (Join-Path $FilmDir 'done-ours')) -and (Test-Path (Join-Path $FilmDir 'done-wt'))) {
        L "both done at $(Get-Date -Format HH:mm:ss.fff)"
        break
    }
}
$ff.WaitForExit(($FilmSeconds + 60) * 1000) | Out-Null
foreach ($h in $hidden) { [void][FW]::ShowWindow($h, 9) }     # 9 = SW_RESTORE
L "times ours: $(Get-Content (Join-Path $FilmDir 'times-ours') -EA SilentlyContinue)"
L "times wt:   $(Get-Content (Join-Path $FilmDir 'times-wt')   -EA SilentlyContinue)"
L "mp4: $([math]::Round((Get-Item $mp4 -EA SilentlyContinue).Length/1MB,1)) MB"
L 'done'
