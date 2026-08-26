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
    # Where the screenshot lands. Downscaled on this side on purpose: a full
    # 4K PNG is ~16MB and has no business crossing the wire for a gate.
    # Written on every run, pass or fail -- it is the record of what the gate
    # was looking at, and the only thing that can answer "but does it LOOK
    # right", which no check here claims to.
    [string]$Screenshot = "C:\dist\gate-shot.png"
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
  [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int size);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
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
  // Same trap from the other side: "a window of THIS CLASS, any title" spelt
  // FindWindowW("Progman", $null) asks for a window whose TITLE is "", and
  // Progman's is "Program Manager" -- so it answered zero every time and the
  // check it fed could not fail. Nothing here may pass $null to FindWindowW.
  public static IntPtr FindClass(string cls) { return FindWindowW(cls, null); }
  // Explorer's own desktop or taskbar, visible on screen -- the thing the user
  // must never see once we are the shell. Keyed on the OWNING PROCESS, because
  // Shell_TrayWnd is a class this shell takes for itself.
  public static string ExplorerChromeVisible() {
    var sb = new StringBuilder();
    EnumWindows((h,p) => {
      if (!IsWindowVisible(h)) return true;
      var c = new StringBuilder(64); GetClassNameW(h, c, 64);
      string cls = c.ToString();
      if (cls != "Progman" && cls != "Shell_TrayWnd" && cls != "Shell_SecondaryTrayWnd") return true;
      int pid; GetWindowThreadProcessId(h, out pid);
      string pn = ""; try { pn = System.Diagnostics.Process.GetProcessById(pid).ProcessName; } catch { return true; }
      if (!pn.Equals("explorer", StringComparison.OrdinalIgnoreCase)) return true;
      if (sb.Length > 0) sb.Append(", ");
      sb.Append(cls);
      return true;
    }, IntPtr.Zero);
    return sb.ToString();
  }
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
  /// Every window that is minimized and STILL ON SCREEN -- which is what a
  /// title-bar stub is. Exact where a pixel diff of the desktop cannot be:
  /// another app repainting behind the check is indistinguishable from a stub
  /// appearing, and on this box that is exactly what fooled it once.
  public static string IconicOnScreen(int screenW, int screenH) {
    var sb = new StringBuilder();
    EnumWindows((h,p) => {
      if (!IsIconic(h)) return true;
      // A stub is DRAWN. Two kinds of minimized window sit at plausible
      // coordinates without ever appearing: DWM's own notification window,
      // which is not visible at all, and a suspended packaged app, which is
      // cloaked -- present to every window API, painted by nobody. Counting
      // either one makes the check cry wolf on a perfectly clean desktop.
      if (!IsWindowVisible(h)) return true;
      int cloaked = 0;
      DwmGetWindowAttribute(h, 14, out cloaked, 4);
      if (cloaked != 0) return true;
      RECT r; GetWindowRect(h, out r);
      if (r.R <= 0 || r.B <= 0 || r.L >= screenW || r.T >= screenH) return true;
      var t = new StringBuilder(256); GetWindowTextW(h, t, 256);
      var c = new StringBuilder(256); GetClassNameW(h, c, 256);
      sb.AppendFormat("{0} [{1}] at ({2},{3}); ", t.ToString(), c.ToString(), r.L, r.T);
      return true;
    }, IntPtr.Zero);
    return sb.ToString();
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

$script:skipped = 0
function Skip($name, $why) {
    "  SKIP  $name"
    "          $why"
    $script:skipped++
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

# ── looking at the screen ────────────────────────────────────────────────────
#
# The two worst bugs this shell has had were invisible to every window API and
# obvious in a screenshot: a black screen with a dock on it (every handle
# present and correct, nothing drawing a wallpaper), and title-bar stubs left
# sitting above the dock (real windows, in the right place, that should not
# have been on screen at all). So the gate looks.
#
# The measurements are deliberately coarse -- "is there variety here", "did
# this band change" -- because a gate that asserts exact pixels fails on a new
# wallpaper and teaches everyone to ignore it.

function Grab($x, $y, $w, $h) {
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size $w, $h))
    $g.Dispose()
    return $bmp
}

# How many DIFFERENT colours a region has, sampled on a grid and quantized.
# A blank window, a black screen and a solid fill all answer 1-3; anything
# actually drawn answers dozens.
function ColourVariety($bmp, $step = 8) {
    $seen = New-Object 'System.Collections.Generic.HashSet[int]'
    for ($y = 0; $y -lt $bmp.Height; $y += $step) {
        for ($x = 0; $x -lt $bmp.Width; $x += $step) {
            $c = $bmp.GetPixel($x, $y)
            # 5 bits a channel: tolerant of dithering and of compression, still
            # far more than a blank surface can produce.
            $seen.Add((($c.R -shr 3) -shl 10) -bor (($c.G -shr 3) -shl 5) -bor ($c.B -shr 3)) | Out-Null
        }
    }
    return $seen.Count
}

# What SHARE of a region is a single flat colour.
#
# The companion to ColourVariety, and the one that catches a packaged app that
# opened but never drew. Such a window is not blank in the colour-variety
# sense: ApplicationFrameHost puts up an empty white frame with the APP'S ICON
# in the middle, and the icon alone answers ~270 distinct colours -- far past
# any "dozens means it drew" threshold. Measured on the box, frame interiors:
#
#   Calculator, opened and never drawn   274 colours, 99.1% one white
#   Settings,   opened and never drawn   260 colours, 98.1% one white
#   a CLOAKED frame (wallpaper behind)  6889 colours,  0.2% dominant
#
# So variety says "drawn" for all three and share separates them. A real UI
# has edges everywhere and cannot be one flat colour; 90% leaves room for a
# light-themed app with a lot of background and still fails the ~99% frames
# above by a wide margin. (No positive reference was available when this was
# written -- nothing on that box renders -- so the threshold is set from the
# failure side, deliberately loose.)
function DominantShare($bmp, $step = 8) {
    $counts = @{}
    $n = 0
    for ($y = 0; $y -lt $bmp.Height; $y += $step) {
        for ($x = 0; $x -lt $bmp.Width; $x += $step) {
            $c = $bmp.GetPixel($x, $y)
            $k = (($c.R -shr 3) -shl 10) -bor (($c.G -shr 3) -shl 5) -bor ($c.B -shr 3)
            $counts[$k] = 1 + $counts[$k]
            $n++
        }
    }
    if ($n -eq 0) { return 1.0 }
    $top = 0
    foreach ($v in $counts.Values) { if ($v -gt $top) { $top = $v } }
    return $top / $n
}

function MeanBrightness($bmp, $step = 8) {
    $sum = 0.0; $n = 0
    for ($y = 0; $y -lt $bmp.Height; $y += $step) {
        for ($x = 0; $x -lt $bmp.Width; $x += $step) {
            $c = $bmp.GetPixel($x, $y)
            $sum += ($c.R + $c.G + $c.B) / 3.0
            $n++
        }
    }
    if ($n -eq 0) { return 0 }
    return [math]::Round($sum / $n, 1)
}

# The share of sampled pixels that differ between two grabs of the same
# region. The oracle for "something appeared here that should not have".
function ChangedFraction($a, $b, $step = 4, $tolerance = 24) {
    $diff = 0; $n = 0
    for ($y = 0; $y -lt $a.Height -and $y -lt $b.Height; $y += $step) {
        for ($x = 0; $x -lt $a.Width -and $x -lt $b.Width; $x += $step) {
            $p = $a.GetPixel($x, $y); $q = $b.GetPixel($x, $y)
            $n++
            if ([math]::Abs($p.R - $q.R) -gt $tolerance -or
                [math]::Abs($p.G - $q.G) -gt $tolerance -or
                [math]::Abs($p.B - $q.B) -gt $tolerance) { $diff++ }
        }
    }
    if ($n -eq 0) { return 0 }
    return [math]::Round($diff / [double]$n, 4)
}

# The strip the dock reserves, and the band of desktop directly above it --
# where a minimized window's stub would land.
function ReservedHeight() {
    $wa = New-Object RECT
    [void][Gate]::SystemParametersInfoW(0x0030, 0, [ref]$wa, 0)
    return ($screen.Height - $wa.B)
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

# Whether this session hosts a permanent explorer. It should NOT: packaged apps
# are launched by borrowing one for a second and dropping it, so an idle session
# runs none. STARLING_EXPLORER_SERVICE=1 asks for the old arrangement, and then
# the check below is about explorer being invisible rather than absent.
$explorerService = (Get-Process explorer -EA SilentlyContinue | Measure-Object).Count -ge 1

if (-not $explorerService) {
Check "no explorer is running at idle" {
    # The point of the borrow: what used to cost 227 MB permanently now costs
    # a second per launch. If an explorer is sitting here, either the service
    # was asked for or one was borrowed and never handed back -- and a leaked
    # borrow is the failure mode worth catching, because nothing else would
    # ever notice it.
    $n = (Get-Process explorer -EA SilentlyContinue | Measure-Object).Count
    if ($n -eq 0) { return $true }
    "$n explorer process(es) running -- a borrowed one was not handed back"
}
} else {
Check "explorer is alive as a service, and owns no chrome" {
    # Packaged apps of the CoreWindow generation need it running; the user must
    # never see it. Both halves, or the check is worthless.
    $n = (Get-Process explorer -EA SilentlyContinue | Measure-Object).Count
    if ($n -lt 1) { return "explorer is not running: packaged apps will not launch" }
    # EXPLORER's windows, not the first window of those classes: the tray class
    # is one WE own too, so asking FindWindow for it and testing visibility
    # answers a question about our own shell.
    $shown = [Gate]::ExplorerChromeVisible()
    if ($shown -eq "") { return $true }
    "explorer chrome on screen: $shown"
}
}

Check "the dock reserves its strip" {
    # Not a fixed number: the dock is sized in points and the reservation
    # follows the screen's scale. What must hold is that SOMETHING sensible is
    # reserved at the bottom -- a full-height work area means maximized windows
    # run underneath the dock.
    #
    # WAITS, because this is a steady-state question and the gate can arrive
    # mid-startup. After a shell restart with explorer already alive the
    # reservation takes a few seconds to settle, and a gate that judges at
    # second one reports a bug that is gone by the time anyone looks -- which
    # it did, twice, before this loop existed.
    $reserved = 0
    for ($i = 0; $i -lt 15; $i++) {
        $wa = New-Object RECT
        [void][Gate]::SystemParametersInfoW(0x0030, 0, [ref]$wa, 0)
        $reserved = $screen.Height - $wa.B
        if ($reserved -ge 60 -and $reserved -le 300) { return $true }
        Start-Sleep 2
    }
    "after 30s the work area is still $($screen.Height - $reserved) of $($screen.Height): $reserved px reserved"
}

Check "the desktop surface is on screen" {
    # The black-screen bug: with explorer's desktop hidden and ours skipping
    # itself, nobody draws a wallpaper and every number still looks right.
    $d = [Gate]::DesktopSurface($screen.Width, $screen.Height)
    if ($d -ne [IntPtr]::Zero) { return $true }
    "no full-screen Starling desktop surface is visible"
}

Check "there is a wallpaper, not a black screen" {
    # The window handle above can be perfectly correct while nothing is drawn.
    # This is the same bug from the only side that would have caught it: a
    # band across the upper screen, which a wallpaper fills with variety and a
    # dead desktop fills with one colour.
    $band = Grab 0 ([int]($screen.Height * 0.12)) $screen.Width ([int]($screen.Height * 0.25))
    $variety = ColourVariety $band 12
    $bright = MeanBrightness $band 12
    $band.Dispose()
    if ($variety -ge 12) { return $true }
    "only $variety distinct colours up there (brightness $bright) -- that is a blank desktop"
}

Check "the dock is drawn along the bottom" {
    # Its own strip, by the height the reservation says it claimed: opaque and
    # dark, with icons in it -- distinctly not the wallpaper it sits over.
    $reserved = ReservedHeight
    if ($reserved -lt 20) { return "nothing is reserved, so there is no strip to look at" }
    $strip = Grab 0 ($screen.Height - $reserved) $screen.Width $reserved
    $bright = MeanBrightness $strip 6
    $variety = ColourVariety $strip 6
    $strip.Dispose()
    # Dark enough to be the strip rather than wallpaper, varied enough to have
    # icons and a clock in it rather than being a plain black band.
    if ($bright -le 90 -and $variety -ge 8) { return $true }
    "strip brightness $bright, $variety colours -- not the dock"
}

Check "the shell holds the minimize target" {
    $w = [Gate]::FindClass("StarlingTaskmanWindow")
    if ($w -ne [IntPtr]::Zero) { return $true }
    "no taskman window: minimized apps will be left as stubs on the desktop"
}

# ── what a user does to a window ─────────────────────────────────────────────

Check "a minimized window leaves the screen" {
    # Two answers, because they failed independently: where Windows PUT the
    # window, and whether ANY window is left minimized-but-on-screen, which is
    # exactly what a title-bar stub is. The second is deliberately not a pixel
    # diff of the desktop -- another app repainting behind the check reads the
    # same as a stub appearing, and on this box that is what fooled it.
    $h = [Gate]::Probe()
    [Gate]::Pump(700)
    [void][Gate]::ShowWindow($h, 6)   # SW_MINIMIZE
    [Gate]::Pump(1500)

    $r = New-Object RECT
    [void][Gate]::GetWindowRect($h, [ref]$r)
    $parked = $r.L -le -30000
    $stubs = [Gate]::IconicOnScreen($screen.Width, $screen.Height)

    [void][Gate]::ShowWindow($h, 9)
    [Gate]::Pump(400)
    [void][Gate]::DestroyWindow($h)
    [Gate]::Pump(600)

    if (-not $parked) {
        return "minimized to ($($r.L),$($r.T)) -- a title-bar stub is sitting on the desktop"
    }
    if ($stubs.Length -gt 0) {
        return "minimized windows are still on screen: $stubs"
    }
    return $true
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
    if (-not $back) {
        if (-not $wasVisible) { [void][Gate]::ShowWindow($f, 0) }
        return "Win+E did not bring the minimized Files window back"
    }
    # And it has to have PAINTED. A restored surface view that nobody asked
    # for a frame is a white rectangle with a title bar -- the window checks
    # all pass and the user is looking at nothing.
    $r = New-Object RECT
    [void][Gate]::GetWindowRect($f, [ref]$r)
    $shot = Grab ($r.L + 8) ($r.T + 8) ([math]::Max(64, $r.R - $r.L - 16)) ([math]::Max(64, $r.B - $r.T - 16))
    $variety = ColourVariety $shot 10
    $shot.Dispose()
    # Put it back the way it was found.
    if (-not $wasVisible) { [void][Gate]::ShowWindow($f, 0) }
    if ($variety -ge 10) { return $true }
    "it came back but only $variety distinct colours are in it -- a blank window"
}

Check "a packaged app launches, minimizes and comes back" {
    # Calculator is of the CoreWindow generation -- the one that cannot be
    # activated at all unless explorer is running. Launched THROUGH THE SHELL,
    # deliberately: calling Windows' activation API from here would only prove
    # that Windows works. What can regress is the shell's own borrow, and the
    # only way to exercise that is to ask the shell to launch it.
    $aumid = 'Microsoft.WindowsCalculator_8wekyb3d8bbwe!App'
    $exe = (Get-Process WinShellBar -EA SilentlyContinue | Select-Object -First 1).Path
    if (-not $exe) { return "no WinShellBar to launch through" }
    # Start-Process -Wait, NOT the call operator. The shell is a GUI-subsystem
    # binary (so Winlogon never gives it a console window), and PowerShell's `&`
    # does not wait for a GUI-subsystem process or capture its stdout -- it
    # returns instantly with an empty $LASTEXITCODE, which read as "refused" for
    # a launch that in fact succeeded. Start-Process -Wait -PassThru gives a
    # real exit code, and the redirect captures the shell's diagnostic line.
    $so = Join-Path $env:TEMP "starling-gate-launch-out.txt"
    $se = Join-Path $env:TEMP "starling-gate-launch-err.txt"
    $proc = Start-Process -FilePath $exe -ArgumentList '--launch-app', $aumid `
        -Wait -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    $out = ((Get-Content $so, $se -EA SilentlyContinue) -join ' ').Trim()
    if ($proc.ExitCode -ne 0) { return "the shell refused the launch: $out" }

    # Wait for it to be on screen AND PAINTED. A frame with nothing in it is
    # what a UWP app looks like while it starts -- and what it leaves behind
    # if it dies -- so a check that only asks "is there a window" passes on a
    # white rectangle with an icon in the middle.
    $w = [IntPtr]::Zero
    $variety = 0
    $flat = 0.0
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep 1
        # THE FRAME, looked for on every pass rather than keeping whatever
        # turned up first. A packaged app puts up TWO windows with the same
        # title -- its own drawing surface and the frame that hosts it -- and
        # the surface can appear first. Latching onto that one and never
        # looking again is what made this check report "restore=False" about an
        # app that restores perfectly well: only the frame answers a restore
        # from another process, which is exactly what the dock has to do.
        $frame = [Gate]::Find("Calculator", "ApplicationFrameWindow")
        if ($frame -ne [IntPtr]::Zero) { $w = $frame }
        if ($w -eq [IntPtr]::Zero -or -not [Gate]::IsWindowVisible($w)) { continue }
        $r = New-Object RECT
        [void][Gate]::GetWindowRect($w, [ref]$r)
        $shot = Grab ($r.L + 12) ($r.T + 40) ([math]::Max(64, $r.R - $r.L - 24)) ([math]::Max(64, $r.B - $r.T - 60))
        $variety = ColourVariety $shot 10
        $flat = DominantShare $shot 10
        $shot.Dispose()
        # Both have to be true before this counts as drawn: enough colours,
        # AND not one flat fill wearing the app's icon.
        if ($variety -ge 25 -and $flat -lt 0.90) { break }
    }
    # Only now fall back to the app's own window: with no frame at all the
    # checks below SHOULD fail, and this makes them fail about the right thing.
    if ($w -eq [IntPtr]::Zero) { $w = [Gate]::Find("Calculator") }
    if ($w -eq [IntPtr]::Zero) { return "activated, but no window ever appeared" }
    if (-not [Gate]::IsWindowVisible($w)) { return "the window exists but is not on screen" }

    # NOT CLOAKED, and this has to be asked separately from the pixels.
    #
    # A DWM-cloaked window is visible to every window API and painted by
    # nobody: IsWindowVisible is true, GetWindowRect gives real coordinates,
    # and a screen grab of those coordinates returns whatever is BEHIND it --
    # which here is the desktop wallpaper, a photograph, so the colour-variety
    # test below passes with flying colours on a window the user cannot see.
    # That is not hypothetical: every packaged app on the box launched
    # shell-cloaked while this check reported a healthy 12/12, because nothing
    # in it ever asked. Attribute 14 is DWMWA_CLOAKED; 2 is
    # DWM_CLOAKED_SHELL, the value a frame nobody uncloaked carries.
    $cloaked = 0
    [void][Gate]::DwmGetWindowAttribute($w, 14, [ref]$cloaked, 4)
    if ($cloaked -ne 0) {
        return "the frame exists but is DWM-cloaked ($cloaked) -- running, and invisible to the user"
    }

    if ($variety -lt 25) { return "the window is on screen but blank ($variety colours)" }
    if ($flat -ge 0.90) {
        return ("the frame is on screen but the app never drew into it -- " +
                "{0:P0} of it is one flat colour (an empty frame with the app's icon)" -f $flat)
    }

    [void][Gate]::ShowWindow($w, 6)
    Start-Sleep 3
    $gone = [Gate]::IsIconic($w)
    [void][Gate]::ShowWindow($w, 9)
    [void][Gate]::BringWindowToTop($w)
    [void][Gate]::SetForegroundWindow($w)
    Start-Sleep 3
    $back = -not [Gate]::IsIconic($w)

    # CLOSE IT, do not kill it. The frame window belongs to
    # ApplicationFrameHost, not to the app: killing the app process leaves the
    # frame behind as an empty white rectangle over the desktop, which is both
    # untidy and enough to fool the next check that looks at the screen.
    [void][Gate]::PostMessageW($w, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)   # WM_CLOSE
    Start-Sleep 3
    Get-Process CalculatorApp -EA SilentlyContinue | Stop-Process -Force

    if ($gone -and $back) { return $true }
    "minimize=$gone restore=$back"
}

""
Shot $Screenshot
"screenshot: $Screenshot"
""
if ($script:failed -gt 0) {
    "GATE FAILED: $($script:passed) passed, $($script:failed) failed, $($script:skipped) skipped -- $($script:failures -join '; ')"
    exit 1
}
$tail = if ($script:skipped -gt 0) { ", $($script:skipped) skipped" } else { "" }
"GATE PASSED: $($script:passed) checks$tail"
exit 0
