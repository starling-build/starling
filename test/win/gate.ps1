# The Windows shell gate.
#
# What this checks is everything a session is broken WITHOUT, and nothing that
# is merely nice: the shell's own processes, the strip it reserves, the
# wallpaper, and the three things a user does to a window -- minimize it, get
# it back, and launch an app that only works because explorer is alive.
#
# It runs INSIDE the logged-in session (see run-gate.sh, which schedules it as
# an interactive task). SSH lands in session 0, which has no desktop: every
# window call here would answer about a desktop nobody is looking at.
#
# Leaves the machine as it found it -- the probe window is destroyed, the file
# explorer goes back to the visibility it had, and the packaged app used for
# the launch check is closed.

param(
    # Where a failure screenshot lands. Downscaled on this side on purpose: a
    # full 4K PNG is ~16MB and has no business crossing the wire for a gate.
    [string]$FailShot = "C:\dist\gate-fail.png"
)

$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

Add-Type @'
using System;using System.Text;using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct WNDCLASSW {
  public uint style; public IntPtr lpfnWndProc; public int cbClsExtra, cbWndExtra;
  public IntPtr hInstance, hIcon, hCursor, hbrBackground;
  [MarshalAs(UnmanagedType.LPWStr)] public string lpszMenuName;
  [MarshalAs(UnmanagedType.LPWStr)] public string lpszClassName;
}
[StructLayout(LayoutKind.Sequential)] public struct MSG { public IntPtr hwnd; public uint msg; public IntPtr w, l; public uint time; public int x, y; }
// The shell's own activation route for packaged apps. Declared here because
// PowerShell cannot cast a raw COM object to an interface it does not know.
[ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IApplicationActivationManager {
  [PreserveSig] int ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId,
                                        [MarshalAs(UnmanagedType.LPWStr)] string arguments,
                                        int options, out uint processId);
}
public class Gate {
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr GetModuleHandleW(string m);
  [DllImport("kernel32.dll")] public static extern IntPtr GetProcAddress(IntPtr h, string n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern ushort RegisterClassW(ref WNDCLASSW c);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr CreateWindowExW(uint ex, string cls, string name, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr p);
  [DllImport("user32.dll")] public static extern bool DestroyWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string c, string n);
  [DllImport("user32.dll")] public static extern bool SystemParametersInfoW(uint a, uint b, ref RECT r, uint f);
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, IntPtr e);
  [DllImport("user32.dll")] public static extern bool PeekMessageW(out MSG m, IntPtr h, uint a, uint b, uint r);
  [DllImport("user32.dll")] public static extern bool TranslateMessage(ref MSG m);
  [DllImport("user32.dll")] public static extern IntPtr DispatchMessageW(ref MSG m);

  public static void Chord(byte second) {
    keybd_event(0x5B,0,0,IntPtr.Zero); keybd_event(second,0,0,IntPtr.Zero);
    System.Threading.Thread.Sleep(60);
    keybd_event(second,0,2,IntPtr.Zero); keybd_event(0x5B,0,2,IntPtr.Zero);
  }
  // A real overlapped window of our own, so the minimize check tests what
  // Windows does to an ordinary app rather than to one of our surfaces.
  public static IntPtr Probe() {
    var wc = new WNDCLASSW();
    wc.lpfnWndProc = GetProcAddress(GetModuleHandleW("user32.dll"), "DefWindowProcW");
    wc.hInstance = GetModuleHandleW(null);
    wc.lpszClassName = "StarlingGateProbe";
    RegisterClassW(ref wc);
    IntPtr h = CreateWindowExW(0, "StarlingGateProbe", "Starling gate probe",
                               0x00CF0000, 300, 300, 900, 600,
                               IntPtr.Zero, IntPtr.Zero, GetModuleHandleW(null), IntPtr.Zero);
    ShowWindow(h, 5);
    return h;
  }
  public static void Pump(int ms) {
    var end = DateTime.Now.AddMilliseconds(ms); MSG m;
    while (DateTime.Now < end) {
      while (PeekMessageW(out m, IntPtr.Zero, 0, 0, 1)) { TranslateMessage(ref m); DispatchMessageW(ref m); }
      System.Threading.Thread.Sleep(10);
    }
  }
  public static int Activate(string aumid, out uint pid) {
    pid = 0;
    Type t = Type.GetTypeFromCLSID(new Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C"));
    if (t == null) return unchecked((int)0x80040154);
    var mgr = (IApplicationActivationManager)Activator.CreateInstance(t);
    return mgr.ActivateApplication(aumid, null, 0, out pid);
  }
  // Two of them on purpose. PowerShell marshals $null as "" for a string
  // argument -- a trap this tree has paid for before -- so a caller that means
  // "any class" and writes $null silently asks for a window whose class name
  // is the empty string, and finds nothing. There is no way to write that
  // wrong if the overload exists.
  public static IntPtr Find(string title) { return Find(title, null); }
  public static IntPtr Find(string title, string cls) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h,p) => {
      var t = new StringBuilder(512); GetWindowTextW(h, t, 512);
      if (t.ToString() != title) return true;
      if (cls != null) {
        var c = new StringBuilder(256); GetClassNameW(h, c, 256);
        if (c.ToString() != cls) return true;
      }
      found = h; return false;
    }, IntPtr.Zero);
    return found;
  }
  /// The full-monitor surface the shell draws the wallpaper into.
  public static IntPtr DesktopSurface(int monitorW, int monitorH) {
    IntPtr found = IntPtr.Zero;
    var pids = new System.Collections.Generic.HashSet<int>();
    foreach (var p in System.Diagnostics.Process.GetProcessesByName("WinShellBar")) pids.Add(p.Id);
    EnumWindows((h,p) => {
      if (!IsWindowVisible(h)) return true;
      var c = new StringBuilder(256); GetClassNameW(h, c, 256);
      if (c.ToString() != "StarlingSurfaceView") return true;
      RECT r; GetWindowRect(h, out r);
      if ((r.R - r.L) < monitorW || (r.B - r.T) < monitorH) return true;
      found = h; return false;
    }, IntPtr.Zero);
    return found;
  }
}
'@

[void][Gate]::SetProcessDpiAwarenessContext([IntPtr](-4))

$script:passed = 0
$script:failed = 0
$script:failures = @()

# A check returns $true, or a string saying what it saw. Anything else is a
# failure too -- a check that cannot answer has not passed.
function Check($name, [scriptblock]$body) {
    $result = $null
    try { $result = & $body } catch { $result = "threw: " + $_.Exception.Message }
    if ($result -is [bool] -and $result) {
        "  PASS  $name"
        $script:passed++
    } else {
        $detail = if ($null -eq $result) { "no answer" } else { "$result" }
        "  FAIL  $name"
        "          $detail"
        $script:failed++
        $script:failures += $name
    }
}

function Shot($path) {
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
    $small = New-Object System.Drawing.Bitmap 1280, 720
    $sg = [System.Drawing.Graphics]::FromImage($small)
    $sg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $sg.DrawImage($bmp, 0, 0, 1280, 720)
    $small.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $sg.Dispose(); $small.Dispose(); $g.Dispose(); $bmp.Dispose()
}

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
"Starling Windows gate -- screen $($screen.Width)x$($screen.Height)"
"exe " + (Get-FileHash 'C:\dist\Starling\WinShellBar.exe' -Algorithm SHA256 -EA SilentlyContinue).Hash.Substring(0,16)
""

# ── the session itself ───────────────────────────────────────────────────────

Check "the five session processes are running" {
    $cmds = @(Get-CimInstance Win32_Process -Filter "Name='WinShellBar.exe'" |
              ForEach-Object { $_.CommandLine })
    $missing = @()
    foreach ($role in '--session','--oneview','--notifications','--banners','--run') {
        if (-not ($cmds | Where-Object { $_ -match [regex]::Escape($role) })) { $missing += $role }
    }
    $dupes = @()
    foreach ($role in '--session','--oneview') {
        $n = @($cmds | Where-Object { $_ -match [regex]::Escape($role) }).Count
        if ($n -gt 1) { $dupes += "$role x$n" }
    }
    if ($missing.Count -eq 0 -and $dupes.Count -eq 0) { return $true }
    "missing: $($missing -join ', ')  duplicated: $($dupes -join ', ')"
}

Check "explorer is alive as a service, and owns no chrome" {
    # Packaged apps of the CoreWindow generation need it running; the user must
    # never see it. Both halves, or the check is worthless.
    $n = (Get-Process explorer -EA SilentlyContinue | Measure-Object).Count
    if ($n -lt 1) { return "explorer is not running: packaged apps will not launch" }
    $prog = [Gate]::FindWindowW("Progman", $null)
    $tray = [Gate]::FindWindowW("Shell_TrayWnd", $null)
    $progVisible = ($prog -ne [IntPtr]::Zero) -and [Gate]::IsWindowVisible($prog)
    $trayVisible = ($tray -ne [IntPtr]::Zero) -and [Gate]::IsWindowVisible($tray)
    if (-not $progVisible -and -not $trayVisible) { return $true }
    "explorer chrome on screen -- desktop: $progVisible  taskbar: $trayVisible"
}

Check "the dock reserves its strip" {
    # Not a fixed number: the dock is sized in points and the reservation
    # follows the screen's scale. What must hold is that SOMETHING sensible is
    # reserved at the bottom -- a full-height work area means maximized windows
    # run underneath the dock.
    $wa = New-Object RECT
    [void][Gate]::SystemParametersInfoW(0x0030, 0, [ref]$wa, 0)
    $reserved = $screen.Height - $wa.B
    if ($reserved -ge 60 -and $reserved -le 300) { return $true }
    "work area bottom $($wa.B) of $($screen.Height): $reserved px reserved"
}

Check "the desktop surface is on screen" {
    # The black-screen bug: with explorer's desktop hidden and ours skipping
    # itself, nobody draws a wallpaper and every number still looks right.
    $d = [Gate]::DesktopSurface($screen.Width, $screen.Height)
    if ($d -ne [IntPtr]::Zero) { return $true }
    "no full-screen Starling desktop surface is visible"
}

Check "the shell holds the minimize target" {
    $w = [Gate]::FindWindowW("StarlingTaskmanWindow", $null)
    if ($w -ne [IntPtr]::Zero) { return $true }
    "no taskman window: minimized apps will be left as stubs on the desktop"
}

# ── what a user does to a window ─────────────────────────────────────────────

Check "a minimized window leaves the screen" {
    $h = [Gate]::Probe()
    [Gate]::Pump(700)
    [void][Gate]::ShowWindow($h, 6)   # SW_MINIMIZE
    [Gate]::Pump(1200)
    $r = New-Object RECT
    [void][Gate]::GetWindowRect($h, [ref]$r)
    $parked = $r.L -le -30000
    [void][Gate]::ShowWindow($h, 9)
    [Gate]::Pump(400)
    [void][Gate]::DestroyWindow($h)
    if ($parked) { return $true }
    "minimized to ($($r.L),$($r.T)) -- a title-bar stub is sitting on the desktop"
}

Check "the file explorer opens, minimizes and comes back" {
    $before = [Gate]::Find("Starling Files")
    $wasVisible = ($before -ne [IntPtr]::Zero) -and [Gate]::IsWindowVisible($before)
    if (-not $wasVisible) { [Gate]::Chord(0x45); Start-Sleep 6 }   # Win+E
    $f = [Gate]::Find("Starling Files")
    if ($f -eq [IntPtr]::Zero) { return "Win+E opened no Starling Files window" }
    if (-not [Gate]::IsWindowVisible($f)) { return "the Files window exists but never showed" }
    [void][Gate]::ShowWindow($f, 6)
    Start-Sleep 3
    if (-not [Gate]::IsIconic($f)) { return "the Files window refused to minimize" }
    [Gate]::Chord(0x45)
    Start-Sleep 5
    $back = -not [Gate]::IsIconic($f)
    # Put it back the way it was found.
    if (-not $wasVisible) { [void][Gate]::ShowWindow($f, 0) }
    if ($back) { return $true }
    "Win+E did not bring the minimized Files window back"
}

Check "a packaged app launches, minimizes and comes back" {
    # Calculator is of the CoreWindow generation, which is the one that does
    # not run when explorer is absent. Its window is the frame explorer hosts.
    $aumid = 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App'
    Get-Process CalculatorApp -EA SilentlyContinue | Stop-Process -Force
    Start-Sleep 2
    $pid2 = [uint32]0
    $hr = [Gate]::Activate($aumid, [ref]$pid2)
    Start-Sleep 7
    if ($hr -ne 0) { return ("activation failed hr=0x{0:X8}" -f $hr) }
    $w = [Gate]::Find("Calculator", "ApplicationFrameWindow")
    if ($w -eq [IntPtr]::Zero) { return "activated, but no window ever appeared" }
    if (-not [Gate]::IsWindowVisible($w)) { return "the window exists but is not on screen" }
    [void][Gate]::ShowWindow($w, 6)
    Start-Sleep 3
    $gone = [Gate]::IsIconic($w)
    [void][Gate]::ShowWindow($w, 9)
    [void][Gate]::BringWindowToTop($w)
    [void][Gate]::SetForegroundWindow($w)
    Start-Sleep 3
    $back = -not [Gate]::IsIconic($w)
    Get-Process CalculatorApp -EA SilentlyContinue | Stop-Process -Force
    if ($gone -and $back) { return $true }
    "minimize=$gone restore=$back"
}

""
if ($script:failed -gt 0) {
    Shot $FailShot
    "a screenshot of the failing state is at $FailShot"
    ""
    "GATE FAILED: $($script:passed) passed, $($script:failed) failed -- $($script:failures -join '; ')"
    exit 1
}
"GATE PASSED: $($script:passed) checks"
exit 0
