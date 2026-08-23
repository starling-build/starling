param(
  [string]$Label = "ours",
  [int]$Reps = 6
)
$ErrorActionPreference='Continue'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class FBB {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string c, string n);
  [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
'@
[void][FBB]::SetProcessDpiAwarenessContext([IntPtr](-4))

# Full screen: a launching window can land anywhere, so nothing is cropped
# out. The marker goes top-LEFT and the change-detection region starts at
# x=300, so the marker's own flip can never read as "a window appeared".
$MARK_X = 60; $MARK_Y = 60; $MARK_S = 160
$out    = "C:\st\file-$Label.mkv"
$stamps = "C:\st\file-$Label-stamps.txt"
Remove-Item $out,$stamps -Force -EA SilentlyContinue
[void][FBB]::SetCursorPos(3500, 900)

$VK_LWIN = 0x5B; $VK_E = 0x45; $VK_F4 = 0x73; $VK_ALT = 0x12
$KEYUP = 0x2; $EXT = 0x1

function WinE {
  [FBB]::keybd_event($VK_LWIN, 0, $EXT, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 25
  [FBB]::keybd_event($VK_E, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 25
  [FBB]::keybd_event($VK_E, 0, $KEYUP, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 25
  [FBB]::keybd_event($VK_LWIN, 0, ($EXT -bor $KEYUP), [UIntPtr]::Zero)
}
# Close the FILE MANAGER window by name, never Alt+F4 to whatever has focus.
# Alt+F4 cost a shell: with no Files window up it landed on our own dock, the
# supervisor lost its child, and the desktop went black mid-run.
function CloseFileManager {
  foreach ($cls in @("FlutterSwiftWin32Host", "CabinetWClass")) {
    # [NullString]::Value, NOT $null: PowerShell binds $null to a [string]
    # P/Invoke parameter as an EMPTY STRING, so FindWindowW then hunts for a
    # window with an empty title and finds nothing. That silently closed
    # nothing and left eight Explorer windows stacked up mid-benchmark.
    $name = if ($cls -eq "FlutterSwiftWin32Host") { "Starling Files" } else { [NullString]::Value }
    for ($k = 0; $k -lt 14; $k++) {
      $h = [FBB]::FindWindowW($cls, $name)
      if ($h -eq [IntPtr]::Zero) { break }
      [void][FBB]::PostMessageW($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)   # WM_CLOSE
      Start-Sleep -Milliseconds 350
    }
  }
}
function FileManagerUp {
  return (([FBB]::FindWindowW("FlutterSwiftWin32Host", "Starling Files") -ne [IntPtr]::Zero) -or
          ([FBB]::FindWindowW("CabinetWClass", [NullString]::Value) -ne [IntPtr]::Zero))
}
function KillFiles {
  Get-CimInstance Win32_Process -Filter "Name='WinShellBar.exe'" |
    Where-Object { $_.CommandLine -match '--files' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
}

# Warm the page cache and any per-user state, unrecorded. Each rep still pays
# a full process start for ours -- that is the thing being measured -- but not
# the once-only cost of first-ever touch.
for ($w = 0; $w -lt 2; $w++) {
  WinE; Start-Sleep -Milliseconds 4000
  CloseFileManager; Start-Sleep -Milliseconds 1200
  KillFiles; Start-Sleep -Milliseconds 800
}
Start-Sleep 2

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'; $form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point($MARK_X, $MARK_Y)
$form.Size = New-Object System.Drawing.Size($MARK_S, $MARK_S)
$form.TopMost = $true; $form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::Black
$form.Show(); $form.Refresh()
[System.Windows.Forms.Application]::DoEvents()
Start-Sleep -Milliseconds 800

$dur = 4 + $Reps * 9
$ff = Start-Process -FilePath "ffmpeg" -PassThru -WindowStyle Hidden -ArgumentList @(
  "-y","-hide_banner","-loglevel","info",
  "-f","lavfi","-i","ddagrab=output_idx=0:framerate=30:draw_mouse=0",
  "-vf","hwdownload,format=bgra","-fps_mode","passthrough",
  "-c:v","libx264","-preset","ultrafast","-crf","20","-pix_fmt","yuv420p",
  "-t","$dur", $out
) -RedirectStandardError "C:\st\file-$Label-ff.log"

Start-Sleep 3
$freq = [double][System.Diagnostics.Stopwatch]::Frequency
$lines = @()

for ($i = 1; $i -le $Reps; $i++) {
  $form.BackColor = [System.Drawing.Color]::White
  $form.Refresh()
  [System.Windows.Forms.Application]::DoEvents()
  $t = [System.Diagnostics.Stopwatch]::GetTimestamp()
  WinE
  $lines += ("rep {0} qpc_ms {1:F3}" -f $i, ($t * 1000.0 / $freq))

  Start-Sleep -Milliseconds 4500        # generous: a cold process start
  $lines += ("      window up after rep {0}: {1}" -f $i, (FileManagerUp))
  CloseFileManager
  Start-Sleep -Milliseconds 900
  KillFiles                             # a launch means starting from nothing
  Start-Sleep -Milliseconds 500
  $form.BackColor = [System.Drawing.Color]::Black
  $form.Refresh()
  [System.Windows.Forms.Application]::DoEvents()
  Start-Sleep -Milliseconds 2500
}

$ff.WaitForExit(30000) | Out-Null
$form.Close()
$lines | Out-File $stamps -Encoding ascii

"label=$Label reps=$Reps  marker=$MARK_X,$MARK_Y,$MARK_S  fullscreen 3840x2160"
if (Test-Path $out) { $i2 = Get-Item $out; "video: $($i2.FullName) $([Math]::Round($i2.Length/1MB,1)) MB" } else { "NO VIDEO" }
(Get-Content "C:\st\file-$Label-ff.log" -EA SilentlyContinue | Select-String "^frame=" | Select-Object -Last 1) -replace '\s+',' '
"--- stamps ---"
$lines | ForEach-Object { "  $_" }
