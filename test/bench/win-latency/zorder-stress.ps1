param([int]$Cycles = 12)
$ErrorActionPreference='Continue'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class ZX {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public struct RECT { public int L,T,R,B; }
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  public static List<string> Classes() {
    var l = new List<string>();
    EnumWindows((h,p) => {
      if (!IsWindowVisible(h)) return true;
      RECT r; GetWindowRect(h, out r);
      if ((r.R-r.L) < 120 || (r.B-r.T) < 80) return true;
      var c=new StringBuilder(200); GetClassNameW(h,c,200);
      l.Add(c.ToString()); return true;
    }, IntPtr.Zero);
    return l;
  }
}
'@
[void][ZX]::SetProcessDpiAwarenessContext([IntPtr](-4))
$bad = 0; $checks = 0
function Assert($label) {
  $z = [ZX]::Classes()
  $app  = $z.IndexOf("Notepad")
  $desk = $z.IndexOf("StarlingSurfaceView")
  $script:checks++
  if ($app -ge 0 -and $desk -ge 0 -and $app -gt $desk) {
    $script:bad++
    Write-Host ("  {0,-32} BAD  app z={1} desktop z={2}  [{3}]" -f $label,$app,$desk,($z -join ","))
  } else {
    Write-Host ("  {0,-32} ok   app z={1} desktop z={2}" -f $label,$app,$desk)
  }
}
for ($c = 1; $c -le $Cycles; $c++) {
  # every third cycle, restart the shell -- what the supervisor does on a crash
  if ($c % 4 -eq 0) {
    Write-Host "  -- shell restart --"
    $sup = Get-CimInstance Win32_Process -Filter "Name='WinShellBar.exe'" | Where-Object { $_.CommandLine -match '--session' }
    if ($sup) { Stop-Process -Id $sup.ProcessId -Force -EA SilentlyContinue }
    Start-Sleep 1
    Get-Process WinShellBar -EA SilentlyContinue | Stop-Process -Force
    Start-Sleep 3
    schtasks /end /tn StarSession 2>&1 | Out-Null
    Start-Sleep 1
    schtasks /run /tn StarSession 2>&1 | Out-Null
    Start-Sleep 22
  }
  Start-Process C:\Windows\System32\notepad.exe | Out-Null
  Start-Sleep 3
  Assert "cycle $c launch"
  Get-Process notepad -EA SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 1200
  # relaunch immediately after the close -- the desktop is foreground here
  Start-Process C:\Windows\System32\notepad.exe | Out-Null
  Start-Sleep 3
  Assert "cycle $c relaunch-after-close"
  Get-Process notepad -EA SilentlyContinue | Stop-Process -Force
  Start-Sleep -Milliseconds 900
}
Write-Host "=== $bad of $checks checks found the app hidden behind the desktop ==="
