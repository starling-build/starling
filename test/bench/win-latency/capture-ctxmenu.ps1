# Context-menu latency capture: right-click on a file row -> menu pixels.
#
# The Start-menu sibling of this (capture-menu.ps1) taps a key; a context menu
# needs a POINTER on a row, which brings two constraints that shape the whole
# script:
#
#   - The row has to be found, not assumed. Explorer only selects a row where
#     the NAME column is drawn -- a click near the window's right edge or on
#     the navigation pane opens its BACKGROUND menu instead, and a background
#     menu timed against an item menu is two different questions compared.
#     Both file managers draw a yellow folder glyph at the left of the name,
#     so the glyph locates a row and the name sits just right of it.
#   - The pointer must be SETTLED before each rep. Right-clicking 300ms after
#     moving measures the hover work still in flight (the row highlight, the
#     chrome's own hover slot) on top of the menu, which inflates both
#     contenders and hides the difference. 700ms of rest, every rep.
#
# Everything else follows capture-menu.ps1: ddagrab at 30fps, a sync marker
# flipped white synchronously at the instant of injection, and a QPC stamp per
# rep so the video's timeline can be calibrated against the wall clock.
param(
  [string]$Label = "ours",
  [int]$Reps = 20,
  [int]$WinX = 98, [int]$WinY = 98, [int]$WinW = 2106, [int]$WinH = 1431
)
$ErrorActionPreference='Continue'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class CM {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint m, UIntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr GetWindowLongPtrW(IntPtr h, int i);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr SetWindowLongPtrW(IntPtr h, int i, IntPtr v);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  public struct RECT { public int L, T, R, B; }
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  public static IntPtr FirstOfClass(string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, p) => {
      if (!IsWindowVisible(h)) return true;
      var c = new StringBuilder(256); GetClassNameW(h, c, 256);
      if (c.ToString() != cls) return true;
      found = h; return false;
    }, IntPtr.Zero);
    return found;
  }
  // Our file explorer is a VIEW in the shell process: an app-surface window,
  // told apart from the desktop surface by not being full screen.
  // Anything else visible gets minimized before a capture. A window left
  // over from earlier work -- a terminal an "Open in Terminal" verb started,
  // say -- sits over the listing, and the row finder then reports that a file
  // manager showing 27 items has no rows in it.
  public static int ClearScreen(IntPtr keep) {
    // Skip the whole PROCESS the target belongs to, not just the window.
    // Hosted in the shell, the file explorer's siblings are the dock and the
    // desktop -- and the dock's window is TITLED ("Starling Dock"), so a
    // title-based skip minimizes the shell's own chrome. A minimized host has
    // no popups: the pre-flight then reports that a right-click opens no
    // menu, which reads as a shell bug rather than as the harness closing the
    // thing it was about to measure.
    uint keepPid; GetWindowThreadProcessId(keep, out keepPid);
    int n = 0;
    EnumWindows((h, p) => {
      if (h == keep || !IsWindowVisible(h)) return true;
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid == keepPid) return true;
      var t = new StringBuilder(256); GetWindowTextW(h, t, 256);
      if (t.ToString().Length == 0) return true;
      var c = new StringBuilder(256); GetClassNameW(h, c, 256);
      var cls = c.ToString();
      if (cls == "Shell_TrayWnd" || cls == "Progman" || cls == "WorkerW") return true;
      ShowWindow(h, 6); n++;                               // SW_MINIMIZE
      return true;
    }, IntPtr.Zero);
    return n;
  }

  public static IntPtr Surface(uint want) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, p) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid != want) return true;
      var c = new StringBuilder(256); GetClassNameW(h, c, 256);
      if (c.ToString() != "StarlingSurfaceView") return true;
      RECT r; GetWindowRect(h, out r);
      if (r.R - r.L > 3000) return true;
      found = h; return false;
    }, IntPtr.Zero);
    return found;
  }
}
'@
[void][CM]::SetProcessDpiAwarenessContext([IntPtr](-4))

function MoveTo($x, $y) { [void][CM]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 250 }
function LeftClick($x, $y) {
  MoveTo $x $y
  [CM]::mouse_event(2,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 40
  [CM]::mouse_event(4,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 350
}
function RightPress { [CM]::mouse_event(8,0,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 20; [CM]::mouse_event(16,0,0,0,[UIntPtr]::Zero) }

# --- the window under test -------------------------------------------------
if ($Label -eq "ours") {
  $pid2 = (Get-CimInstance Win32_Process -Filter "Name='WinShellBar.exe'" |
           Where-Object { $_.CommandLine -match '--oneview' } | Select-Object -First 1).ProcessId
  $h = [CM]::Surface([uint32]$pid2)
  if ($h -eq [IntPtr]::Zero -or -not [CM]::IsWindowVisible($h)) {
    # Win+E, not the dock's tile: the tile moves when the pins change, and a
    # missed click leaves the window HIDDEN while GetWindowRect still answers.
    [CM]::keybd_event(0x5B,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 70
    [CM]::keybd_event(0x45,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 70
    [CM]::keybd_event(0x45,0,2,[UIntPtr]::Zero); [CM]::keybd_event(0x5B,0,2,[UIntPtr]::Zero)
    Start-Sleep 4
    $h = [CM]::Surface([uint32]$pid2)
  }
} else {
  # Always open the folder we mean. An Explorer window left over from earlier
  # work is showing whatever folder it was showing -- or Home, whose tiles
  # look nothing like a listing -- and adopting it silently measures a
  # different screen.
  $old = [CM]::FirstOfClass('CabinetWClass')
  while ($old -ne [IntPtr]::Zero) {
    [void][CM]::PostMessageW($old, 0x0010, [UIntPtr]::Zero, [IntPtr]::Zero)  # WM_CLOSE
    Start-Sleep -Milliseconds 600
    $next = [CM]::FirstOfClass('CabinetWClass')
    if ($next -eq $old) { break }
    $old = $next
  }
  Start-Process explorer.exe -ArgumentList 'C:\Users\starling'
  $h = [IntPtr]::Zero
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 500
    $h = [CM]::FirstOfClass('CabinetWClass')
    if ($h -ne [IntPtr]::Zero) { break }
  }
  Start-Sleep 2
}
if ($h -eq [IntPtr]::Zero) { "NO WINDOW for $Label"; exit 1 }
"minimized $([CM]::ClearScreen($h)) other windows"
Start-Sleep 1
[void][CM]::MoveWindow($h, $WinX, $WinY, $WinW, $WinH, $true)
Start-Sleep -Milliseconds 900
[void][CM]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 600
$r = New-Object CM+RECT; [void][CM]::GetWindowRect($h, [ref]$r)

# --- find a row by its folder glyph ---------------------------------------
$bmp = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$rows = @{}
for ($y = 250; $y -lt ($r.B - $r.T - 200); $y += 3) {
  for ($x = 120; $x -lt 1600; $x += 3) {
    $px = $bmp.GetPixel($x, $y)
    if ($px.R -gt 225 -and $px.G -gt 165 -and $px.G -lt 235 -and $px.B -lt 120) {
      if (-not $rows.ContainsKey($y)) { $rows[$y] = $x } elseif ($x -lt $rows[$y]) { $rows[$y] = $x }
    }
  }
}
$g.Dispose(); $bmp.Dispose()
if ($rows.Count -eq 0) {
  $shot = New-Object System.Drawing.Bitmap ($r.R - $r.L), ($r.B - $r.T)
  $sg = [System.Drawing.Graphics]::FromImage($shot)
  $sg.CopyFromScreen($r.L, $r.T, 0, 0, $shot.Size)
  $shot.Save("C:\st\ctx-$Label-norow.png"); $sg.Dispose(); $shot.Dispose()
  "NO ROW ICON FOUND for $Label -- window saved to C:\st\ctx-$Label-norow.png"
  exit 1
}
$ys = $rows.Keys | Sort-Object
$midY = $ys[[int]($ys.Count / 2)]
$CLICK_X = $r.L + $rows[$midY] + 110      # the name, just right of the glyph
$CLICK_Y = $r.T + $midY

# --- geometry: the crop is anchored on the POINTER ------------------------
# Both panes then show the same region relative to the click, at the same
# scale, which is what makes the two menus comparable on screen -- the rows
# they sit on are at different heights in the two file managers.
$CROP_X = [int](($CLICK_X - 220) / 2) * 2
$CROP_Y = [int](($CLICK_Y - 160) / 2) * 2
$CROP_W = 1400; $CROP_H = 1120
$MARK_S = 120
$MARK_X = $CLICK_X - 200                  # left of the menu, inside the crop
$MARK_Y = $CLICK_Y + 620
$out    = "C:\st\ctx-$Label.mkv"
$stamps = "C:\st\ctx-$Label-stamps.txt"
Remove-Item $out, $stamps -Force -EA SilentlyContinue

# HOW THE MENU IS DISMISSED between reps, which is not a detail: the menu
# opens at the pointer and extends down and to the RIGHT, roughly 660x820, so
# a click at the window's bottom strip lands INSIDE it and invokes whatever
# row is there. That is how a run ends up with a stack of Properties dialogs
# behind the file manager, each rep starting from a different state than the
# last. Escape if the app takes it (checked in pre-flight, not assumed), and
# otherwise a click ABOVE the pointer, which is listing in both file managers
# and never under the menu.
$DISMISS_X = $CLICK_X + 100; $DISMISS_Y = $CLICK_Y - 250
$USE_ESC = $false
function Dismiss {
  if ($USE_ESC) {
    [CM]::keybd_event(0x1B,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 30
    [CM]::keybd_event(0x1B,0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 350
  } else {
    LeftClick $DISMISS_X $DISMISS_Y
  }
}

# --- warm up, unrecorded --------------------------------------------------
# Steady state is what both are built for. Both keep their handlers loaded --
# Explorer because it is the shell, ours because the shell warms them at
# startup -- so a cold first menu would measure DLL loading, not the menu.
LeftClick $CLICK_X $CLICK_Y
for ($w = 0; $w -lt 3; $w++) {
  MoveTo $CLICK_X $CLICK_Y
  Start-Sleep -Milliseconds 700
  RightPress
  Start-Sleep -Milliseconds 1400
  Dismiss
  Start-Sleep -Milliseconds 500
}

# --- the sync marker ------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'; $form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point($MARK_X, $MARK_Y)
$form.Size = New-Object System.Drawing.Size($MARK_S, $MARK_S)
$form.TopMost = $true; $form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::Black
$form.Show(); $form.Refresh()
[System.Windows.Forms.Application]::DoEvents()
# WS_EX_NOACTIVATE, and the foreground handed straight back.
#
# A marker that takes activation is not a passive instrument: the file
# manager loses focus, and OUR right-click then opened no menu at all -- the
# capture recorded twenty reps of a listing with nothing happening, and the
# analyzer reported "0 reps detected" over a marker signal that was perfectly
# fine. Explorer happens to answer a right-click while unfocused; we do not,
# and a capture rig must not decide that for either of them.
$mh = $form.Handle
$ex = [int64][CM]::GetWindowLongPtrW($mh, -20)          # GWL_EXSTYLE
[void][CM]::SetWindowLongPtrW($mh, -20, [IntPtr]($ex -bor 0x08000000))  # WS_EX_NOACTIVATE
[void][CM]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 800

# PRE-FLIGHT: prove a menu actually appears before recording anything. The
# region signature is what the analyzer reads, so check the same pixels.
function MenuPatch {
  $b = New-Object System.Drawing.Bitmap 40, 40
  $gg = [System.Drawing.Graphics]::FromImage($b)
  $gg.CopyFromScreen(($CLICK_X + 120), ($CLICK_Y + 260), 0, 0, $b.Size)
  $sum = 0
  foreach ($x in 6,20,34) { foreach ($y in 6,20,34) { $c = $b.GetPixel($x,$y); $sum += ($c.R + $c.G + [int]$c.B) } }
  $gg.Dispose(); $b.Dispose()
  return $sum
}
MoveTo $CLICK_X $CLICK_Y
Start-Sleep -Milliseconds 700
$before = MenuPatch
RightPress
Start-Sleep -Milliseconds 1200
$after = MenuPatch
if ([Math]::Abs($after - $before) -lt 60) {
  "PRE-FLIGHT FAILED for $Label -- right-click produced no menu (patch $before -> $after)"
  $form.Close()
  exit 1
}
# Does Escape close it? Ask, rather than assume: the two file managers are
# different programs and only one of them is ours.
[CM]::keybd_event(0x1B,0,0,[UIntPtr]::Zero); Start-Sleep -Milliseconds 30
[CM]::keybd_event(0x1B,0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 600
$afterEsc = MenuPatch
if ([Math]::Abs($afterEsc - $before) -lt 60) { $USE_ESC = $true }
if (-not $USE_ESC) { LeftClick $DISMISS_X $DISMISS_Y }
Start-Sleep -Milliseconds 500
"pre-flight ok: menu patch $before -> $after, escape closes it: $USE_ESC"

$dur = 6 + $Reps * 5
$ff = Start-Process -FilePath "ffmpeg" -PassThru -WindowStyle Hidden -ArgumentList @(
  "-y","-hide_banner","-loglevel","info",
  "-f","lavfi","-i","ddagrab=output_idx=0:framerate=30:draw_mouse=0:video_size=$($CROP_W)x$($CROP_H):offset_x=$($CROP_X):offset_y=$($CROP_Y)",
  "-vf","hwdownload,format=bgra","-fps_mode","passthrough",
  "-c:v","libx264","-preset","ultrafast","-crf","18","-pix_fmt","yuv420p",
  "-t","$dur", $out
) -RedirectStandardError "C:\st\ctx-$Label-ff.log"
Start-Sleep 3

$freq = [double][System.Diagnostics.Stopwatch]::Frequency
$lines = @()
for ($i = 1; $i -le $Reps; $i++) {
  MoveTo $CLICK_X $CLICK_Y
  Start-Sleep -Milliseconds 700          # settled: see the header
  $form.BackColor = [System.Drawing.Color]::White
  $form.Refresh()
  [System.Windows.Forms.Application]::DoEvents()
  $t = [System.Diagnostics.Stopwatch]::GetTimestamp()
  RightPress
  $lines += ("rep {0} qpc_ms {1:F3}" -f $i, ($t * 1000.0 / $freq))
  Start-Sleep -Milliseconds 1800
  $form.BackColor = [System.Drawing.Color]::Black
  $form.Refresh()
  [System.Windows.Forms.Application]::DoEvents()
  Dismiss
  Start-Sleep -Milliseconds 700
}
$ff.WaitForExit(30000) | Out-Null
$form.Close()
$lines | Out-File $stamps -Encoding ascii

"label=$Label reps=$Reps"
"window=$($r.L),$($r.T)-$($r.R),$($r.B)  row glyph +$($rows[$midY]),+$midY  click=$CLICK_X,$CLICK_Y"
"crop=${CROP_W}x${CROP_H}+${CROP_X}+${CROP_Y}  marker=$MARK_X,$MARK_Y,$MARK_S"
"marker in crop at $($MARK_X - $CROP_X),$($MARK_Y - $CROP_Y)  click in crop at $($CLICK_X - $CROP_X),$($CLICK_Y - $CROP_Y)"
if (Test-Path $out) { $i2 = Get-Item $out; "video: $($i2.FullName) $([Math]::Round($i2.Length/1MB,1)) MB" } else { "NO VIDEO" }
(Get-Content "C:\st\ctx-$Label-ff.log" -EA SilentlyContinue | Select-String "^frame=" | Select-Object -Last 1) -replace '\s+',' '
