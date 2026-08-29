# Photograph OUR Windows shell on real Windows, as the reference the Linux
# desktop's Fluent style should match.
#
# Explorer is the thing winshell was tuned against, but winshell is the thing
# the Linux style should LOOK LIKE: same framework, same widgets, same design
# decisions already argued out. Comparing Linux against it compares like with
# like, and any difference is a bug in one of the two rather than a difference
# between operating systems.
#
# NON-INVASIVE ON PURPOSE. By default winshell hides Explorer's taskbar and
# takes over the tray -- appropriate when it is the shell, wrong on a machine
# somebody else is using. Everything here runs with --keep-taskbar --keep-tray
# --no-appbar, so it draws its chrome and reserves nothing. If a run is ever
# killed rather than closed, `WinShellBar.exe --restore-taskbar` puts Explorer
# back; this script calls it on the way out regardless.

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# Before anything asks how big the screen is -- see capture-reference.ps1.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Dpi2 {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("shcore.dll")] public static extern int SetProcessDpiAwareness(int v);
}
"@
try { [Dpi2]::SetProcessDpiAwareness(2) | Out-Null } catch { }
try { [Dpi2]::SetProcessDPIAware() | Out-Null } catch { }

$exe = "C:\dist\starling-winshell-0.1.0-windows-x86_64\WinShellBar.exe"
$out = "C:\dist\ref"
New-Item -ItemType Directory -Force -Path $out | Out-Null

function Grab($name) {
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
    $bmp.Save("$out\$name.png", [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    "  captured $name"
}

function StopShell {
    Get-Process WinShellBar -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 800
}

"starling winshell reference capture"
if (-not (Test-Path $exe)) { "  NOT FOUND: $exe"; exit 2 }

# Anything left from a previous run, before adding another.
StopShell

# The bar. --keep-taskbar so Explorer's stays put, --no-appbar so nothing is
# reserved: this is a photograph, not an installation.
"  starting the bar"
Start-Process -FilePath $exe -ArgumentList @("--keep-taskbar", "--keep-tray", "--no-appbar") `
    -RedirectStandardOutput "$out\bar.out.txt" -RedirectStandardError "$out\bar.err.txt"
Start-Sleep -Seconds 8
$p = Get-Process WinShellBar -ErrorAction SilentlyContinue
if ($p) { "  process alive: pid $($p.Id)" } else { "  PROCESS EXITED -- see bar.out/err" }
# Its own account of what it did. A shell that exits immediately and one that
# runs but draws nothing look identical in a screenshot; the log tells them
# apart, and Start-Process is redirecting it above for exactly that reason.
if (Test-Path "$out\bar.out.txt") {
    "  --- its stdout ---"
    Get-Content "$out\bar.out.txt" -Tail 20 | ForEach-Object { "    $_" }
}
if ((Test-Path "$out\bar.err.txt") -and (Get-Item "$out\bar.err.txt").Length -gt 0) {
    "  --- its stderr ---"
    Get-Content "$out\bar.err.txt" -Tail 20 | ForEach-Object { "    $_" }
}
Grab "ours-bar"

# Start, as its own surface.
StopShell
"  starting the launcher"
Start-Process -FilePath $exe -ArgumentList @("--launcher", "--keep-taskbar", "--keep-tray", "--no-appbar")
Start-Sleep -Seconds 6
Grab "ours-start"

StopShell

# Belt and braces: put Explorer's taskbar and tray back even though nothing
# above should have taken them. A machine left without a taskbar is a much
# worse outcome than a redundant call.
& $exe --restore-taskbar 2>&1 | Out-Null
"  explorer's taskbar confirmed back"

"done"
