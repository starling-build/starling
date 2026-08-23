param(
  [string]$Label = "ours",
  [int]$Reps = 6,
  [int]$CropX = 900, [int]$CropY = 500, [int]$CropW = 1700, [int]$CropH = 1600,
  [int]$MarkX = 940, [int]$MarkY = 1400
)
$ErrorActionPreference='Continue'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class SB {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
}
'@
[void][SB]::SetProcessDpiAwarenessContext([IntPtr](-4))

# Geometry shared by both configs, so the comparison is like-for-like. Both
# Start menus draw centred (x ~1280..2560, y ~540..2064 at 4K/200%); the
# marker sits LEFT of that, inside the capture, overlapped by neither.
$CROP_X = $CropX; $CROP_Y = $CropY; $CROP_W = $CropW; $CROP_H = $CropH
$MARK_X = $MarkX; $MARK_Y = $MarkY; $MARK_S = 160
$out    = "C:\st\bench-$Label.mkv"
$stamps = "C:\st\bench-$Label-stamps.txt"
Remove-Item $out,$stamps -Force -EA SilentlyContinue

# Pointer parked clear: a hover over dock or taskbar lights a tile and changes
# pixels we are about to diff.
[void][SB]::SetCursorPos(3500, 260)

$VK_LWIN = 0x5B; $VK_ESC = 0x1B
$KEYUP = 0x2; $EXT = 0x1
function Tap([byte]$vk, [uint32]$extra) {
  [SB]::keybd_event($vk, 0, $extra, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 30
  [SB]::keybd_event($vk, 0, ($extra -bor $KEYUP), [UIntPtr]::Zero)
}

# WARM UP before any of this is recorded. Windows keeps StartMenuExperienceHost
# resident and our launcher is parked on purpose, so steady state is what both
# shells are built for -- measuring either cold would be measuring process
# creation, not the menu. Same code warms both.
for ($w = 0; $w -lt 2; $w++) {
  Tap $VK_LWIN $EXT
  Start-Sleep -Milliseconds 1500
  Tap $VK_ESC 0
  Start-Sleep -Milliseconds 1200
}
Start-Sleep 2

# The marker: a topmost borderless window flipped black->white.
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'; $form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point($MARK_X, $MARK_Y)
$form.Size = New-Object System.Drawing.Size($MARK_S, $MARK_S)
$form.TopMost = $true; $form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::Black
$form.Show(); $form.Refresh()
[System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 800

$dur = 4 + $Reps * 5
$ff = Start-Process -FilePath "ffmpeg" -PassThru -WindowStyle Hidden -ArgumentList @(
  "-y","-hide_banner","-loglevel","info",
  "-f","lavfi","-i","ddagrab=output_idx=0:framerate=30:draw_mouse=0:video_size=$($CROP_W)x$($CROP_H):offset_x=$($CROP_X):offset_y=$($CROP_Y)",
  "-vf","hwdownload,format=bgra","-fps_mode","passthrough",
  "-c:v","libx264","-preset","ultrafast","-crf","18","-pix_fmt","yuv420p",
  "-t","$dur", $out
) -RedirectStandardError "C:\st\bench-$Label-ff.log"

Start-Sleep 3

$freq = [double][System.Diagnostics.Stopwatch]::Frequency
$lines = @()

for ($i = 1; $i -le $Reps; $i++) {
  # White marker painted SYNCHRONOUSLY, then the key -- marker and keystroke
  # land in the same composited frame, so t0 is unambiguous. The wall clock is
  # stamped at the same instant: rep spacing in the video is then checked
  # against rep spacing in reality, which calibrates out capture drift.
  $form.BackColor = [System.Drawing.Color]::White
  $form.Refresh()
  [System.Windows.Forms.Application]::DoEvents()
  $t = [System.Diagnostics.Stopwatch]::GetTimestamp()
  Tap $VK_LWIN $EXT
  $lines += ("rep {0} qpc_ms {1:F3}" -f $i, ($t * 1000.0 / $freq))

  Start-Sleep -Milliseconds 2200
  Tap $VK_ESC 0
  Start-Sleep -Milliseconds 400
  $form.BackColor = [System.Drawing.Color]::Black
  $form.Refresh()
  [System.Windows.Forms.Application]::DoEvents()
  Start-Sleep -Milliseconds 2300
}

$ff.WaitForExit(25000) | Out-Null
$form.Close()
$lines | Out-File $stamps -Encoding ascii

"label=$Label reps=$Reps"
"crop=${CROP_W}x${CROP_H}+${CROP_X}+${CROP_Y} marker=$MARK_X,$MARK_Y,$MARK_S"
if (Test-Path $out) { $i2 = Get-Item $out; "video: $($i2.FullName) $([Math]::Round($i2.Length/1MB,1)) MB" } else { "NO VIDEO" }
(Get-Content "C:\st\bench-$Label-ff.log" -EA SilentlyContinue | Select-String "^frame=" | Select-Object -Last 1) -replace '\s+',' '
"--- stamps ---"
$lines | ForEach-Object { "  $_" }
