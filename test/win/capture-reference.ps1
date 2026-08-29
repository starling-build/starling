# Capture real Windows 11 chrome, at native resolution, as the reference the
# Linux desktop's Fluent style is tuned against.
#
# Run through test/win/capture-reference.sh, which puts it in the logged-in
# session -- ssh lands in session 0, where there is no desktop to photograph.
#
# It only LOOKS. Start and Quick Settings are opened and closed again, and
# nothing about the machine's configuration is touched: the point is a picture
# of Windows as it actually ships, not a machine set up to look good.

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# DPI AWARENESS FIRST, before anything asks how big the screen is.
#
# PowerShell is DPI-unaware, so on this 3840x2160 panel at 200% Windows tells
# it the virtual screen is 1920x1080 and CopyFromScreen then copies the
# top-left 1920x1080 PHYSICAL pixels -- a quarter of the desktop, reported as
# the whole of it. The first run of this looked like a Windows with no taskbar
# and Start jammed against the right edge; both were simply outside the
# quadrant. Declaring awareness has to happen before the first screen query,
# which is why it is at the top of the file rather than beside the capture.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Dpi {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int v);
}
"@
try { [Dpi]::SetProcessDpiAwareness(2) | Out-Null } catch { }
try { [Dpi]::SetProcessDPIAware() | Out-Null } catch { }

$out = "C:\dist\ref"
New-Item -ItemType Directory -Force -Path $out | Out-Null

# The Win key, which SendKeys cannot reach. Quick Settings is Win+A and Start
# has Ctrl+Esc as an equivalent, but pressing the real key is closer to what a
# user does and avoids Ctrl+Esc's differences.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Keys {
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte k, byte scan, uint flags, IntPtr extra);
    public const byte VK_LWIN = 0x5B, VK_ESC = 0x1B, VK_A = 0x41, VK_D = 0x44;
    public const uint KEYUP = 0x0002;
    public static void Tap(byte k) {
        keybd_event(k, 0, 0, IntPtr.Zero);
        keybd_event(k, 0, KEYUP, IntPtr.Zero);
    }
    public static void WinPlus(byte k) {
        keybd_event(VK_LWIN, 0, 0, IntPtr.Zero);
        keybd_event(k, 0, 0, IntPtr.Zero);
        keybd_event(k, 0, KEYUP, IntPtr.Zero);
        keybd_event(VK_LWIN, 0, KEYUP, IntPtr.Zero);
    }
}
"@

# NATIVE resolution, unlike the gate's screenshots: this is measured from, so
# a downscale would blur exactly the edges and colours being sampled.
function Grab($name) {
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
    $bmp.Save("$out\$name.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    "  captured $name"
}

"windows 11 reference capture"
"  screen: $([System.Windows.Forms.SystemInformation]::VirtualScreen)"
$scale = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
"  primary bounds: $scale"

# What the DPI actually is, because every metric below is in device pixels and
# Windows' own sizes are in points.
$dpi = (Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name AppliedDPI -ErrorAction SilentlyContinue).AppliedDPI
if (-not $dpi) { $dpi = 96 }
"  applied dpi: $dpi  (scale $([math]::Round($dpi / 96.0, 2))x)"

# The theme Windows is actually in, so the sample is labelled correctly.
$personalize = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'
$appsLight = (Get-ItemProperty $personalize -Name AppsUseLightTheme -ErrorAction SilentlyContinue).AppsUseLightTheme
$sysLight = (Get-ItemProperty $personalize -Name SystemUsesLightTheme -ErrorAction SilentlyContinue).SystemUsesLightTheme
"  apps theme: $(if ($appsLight -eq 1) {'light'} else {'dark'}); system theme: $(if ($sysLight -eq 1) {'light'} else {'dark'})"

# The wallpaper, so the same picture can be put behind our own chrome -- Mica
# is a function of it, and comparing two desktops over different pictures
# compares the pictures.
$wall = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name WallPaper -ErrorAction SilentlyContinue).WallPaper
"  wallpaper: $wall"
if ($wall -and (Test-Path $wall)) { Copy-Item $wall "$out\wallpaper$([System.IO.Path]::GetExtension($wall))" -Force }

# Clear the screen first. A window left over from an earlier run sits behind
# Start and Quick Settings, and then what is sampled "through" the acrylic is
# that window rather than the wallpaper -- which is the whole measurement.
# Win+D shows the desktop; every capture below wants the same clean backdrop.
[Keys]::WinPlus([Keys]::VK_D)
Start-Sleep -Milliseconds 1200
Grab "desktop"

# Start.
[Keys]::Tap([Keys]::VK_LWIN)
Start-Sleep -Milliseconds 1400
Grab "start"
[Keys]::Tap([Keys]::VK_ESC)
Start-Sleep -Milliseconds 900

# Quick Settings (Win+A) -- the flyout our control centre stands in for.
[Keys]::WinPlus([Keys]::VK_A)
Start-Sleep -Milliseconds 1400
Grab "quicksettings"
[Keys]::Tap([Keys]::VK_ESC)
Start-Sleep -Milliseconds 900

# A File Explorer window: the caption, the window fill, and what Mica looks
# like on a real window rather than on a bar.
Start-Process explorer.exe
Start-Sleep -Milliseconds 2500
Grab "explorer-window"

# Put the machine back as it was found. An Explorer window left open is not a
# large sin, but the NEXT run then samples Start's acrylic against a white
# window instead of the wallpaper and quietly measures the wrong thing.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string n);
    [DllImport("user32.dll")] public static extern IntPtr PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    public const uint WM_CLOSE = 0x0010;
}
"@
for ($i = 0; $i -lt 8; $i++) {
    $h = [Win]::FindWindow("CabinetWClass", $null)
    if ($h -eq [IntPtr]::Zero) { break }
    [Win]::PostMessage($h, [Win]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Start-Sleep -Milliseconds 400
}
"  closed the explorer windows this run opened"

"done"
