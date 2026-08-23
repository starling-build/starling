param(
  [string]$Label = "fp",
  [string]$Exe = "C:\fp\FPilot.exe",
  [string]$CmdArgs = "",
  [string]$ProcName = "FPilot",
  [int]$Reps = 6
)
$ErrorActionPreference='Continue'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class LB {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [StructLayout(LayoutKind.Sequential)] public struct STARTUPINFO {
    public int cb; public IntPtr r1, r2, r3; public int dwX, dwY, dwXSize, dwYSize,
      dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
    public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
  }
  [StructLayout(LayoutKind.Sequential)] public struct PROCESS_INFORMATION {
    public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId;
  }
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool CreateProcessW(string app, string cmd, IntPtr pa, IntPtr ta,
      bool inherit, uint flags, IntPtr env, string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowLongW(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern int SetWindowLongW(IntPtr h, int i, int v);
}
'@
[void][LB]::SetProcessDpiAwarenessContext([IntPtr](-4))

$MARK_X = 60; $MARK_Y = 60; $MARK_S = 160
$out    = "C:\st\launch-$Label.mkv"
$stamps = "C:\st\launch-$Label-stamps.txt"
Remove-Item $out,$stamps -Force -EA SilentlyContinue
[void][LB]::SetCursorPos(3500, 900)

# Exactly what our shell does for its own surfaces: CreateProcessW with
# CREATE_NO_WINDOW. Identical for both contenders, so the trigger is not part
# of the difference being measured.
function Launch {
  $si = New-Object LB+STARTUPINFO
  $si.cb = [System.Runtime.InteropServices.Marshal]::SizeOf($si)
  $pi = New-Object LB+PROCESS_INFORMATION
  $cmd = if ($CmdArgs) { "`"$Exe`" $CmdArgs" } else { "`"$Exe`"" }
  $ok = [LB]::CreateProcessW($Exe, $cmd, [IntPtr]::Zero, [IntPtr]::Zero, $false,
                             0x08000000, [IntPtr]::Zero, (Split-Path $Exe), [ref]$si, [ref]$pi)
  if ($ok) { [void][LB]::CloseHandle($pi.hThread); [void][LB]::CloseHandle($pi.hProcess) }
  return $ok
}
function KillIt { Get-Process $ProcName -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue }

# Anything left over from a previous bench sits on top of the window being
# measured and the screen then never changes -- which reads as "it never
# launched" rather than "it launched underneath". Start from a bare desktop.
function ClearDesktop {
  Get-CimInstance Win32_Process -Filter "Name='WinShellBar.exe'" |
    Where-Object { $_.CommandLine -match '--files|--settings' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue }
  Get-Process FPilot,explorer -EA SilentlyContinue |
    Where-Object { $_.ProcessName -eq 'FPilot' } | Stop-Process -Force -EA SilentlyContinue
}
ClearDesktop

KillIt; Start-Sleep 1
for ($w = 0; $w -lt 2; $w++) { [void](Launch); Start-Sleep -Milliseconds 4000; KillIt; Start-Sleep -Milliseconds 1200 }
Start-Sleep 2

$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'; $form.StartPosition = 'Manual'
$form.Location = New-Object System.Drawing.Point($MARK_X, $MARK_Y)
$form.Size = New-Object System.Drawing.Size($MARK_S, $MARK_S)
$form.TopMost = $true; $form.ShowInTaskbar = $false
$form.BackColor = [System.Drawing.Color]::Black
$form.Show(); $form.Refresh(); [System.Windows.Forms.Application]::DoEvents()
# WS_EX_NOACTIVATE. The marker must never hold the FOREGROUND: while it does,
# Windows refuses to activate the app being launched, the new window stays
# below our full-screen shell surface, and the capture records a bare desktop
# while GetWindowRect and IsWindowVisible both cheerfully say the window is
# there. That cost an hour and two wrong conclusions.
$ex = [LB]::GetWindowLongW($form.Handle, -20)
[void][LB]::SetWindowLongW($form.Handle, -20, $ex -bor 0x08000000)
Start-Sleep -Milliseconds 800

$dur = 4 + $Reps * 9
$ff = Start-Process -FilePath "ffmpeg" -PassThru -WindowStyle Hidden -ArgumentList @(
  "-y","-hide_banner","-loglevel","info",
  "-f","lavfi","-i","ddagrab=output_idx=0:framerate=30:draw_mouse=0",
  "-vf","hwdownload,format=bgra","-fps_mode","passthrough",
  "-c:v","libx264","-preset","ultrafast","-crf","20","-pix_fmt","yuv420p",
  "-t","$dur", $out
) -RedirectStandardError "C:\st\launch-$Label-ff.log"
Start-Sleep 3

$freq = [double][System.Diagnostics.Stopwatch]::Frequency
$lines = @()
for ($i = 1; $i -le $Reps; $i++) {
  $form.BackColor = [System.Drawing.Color]::White
  $form.Refresh(); [System.Windows.Forms.Application]::DoEvents()
  $t = [System.Diagnostics.Stopwatch]::GetTimestamp()
  $ok = Launch
  $lines += ("rep {0} qpc_ms {1:F3} launched={2}" -f $i, ($t * 1000.0 / $freq), $ok)
  Start-Sleep -Milliseconds 4500
  if ($i -eq 1) {
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.X,$b.Y,0,0,$bmp.Size)
    $bmp.Save("C:\st\launch-$Label-rep1.png"); $g.Dispose(); $bmp.Dispose()
  }
  $up = Get-Process $ProcName -EA SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  $lines += ("      rep {0} window={1} title='{2}'" -f $i,
             ($null -ne $up), $(if ($up) { $up.MainWindowTitle } else { "" }))
  KillIt
  Start-Sleep -Milliseconds 1200
  $form.BackColor = [System.Drawing.Color]::Black
  $form.Refresh(); [System.Windows.Forms.Application]::DoEvents()
  Start-Sleep -Milliseconds 2500
}
$ff.WaitForExit(30000) | Out-Null
$form.Close()
$lines | Out-File $stamps -Encoding ascii
"label=$Label exe=$Exe reps=$Reps"
if (Test-Path $out) { "video: $([Math]::Round((Get-Item $out).Length/1MB,1)) MB" } else { "NO VIDEO" }
(Get-Content "C:\st\launch-$Label-ff.log" -EA SilentlyContinue | Select-String "^frame=" | Select-Object -Last 1) -replace '\s+',' '
$lines | ForEach-Object { "  $_" }
