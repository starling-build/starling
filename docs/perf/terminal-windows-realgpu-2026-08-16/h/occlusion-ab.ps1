# Does an occluded window change what a terminal costs?
#
#   occlusion-ab.ps1 -Label wt -Reps 10
#
# Runs the same workload twice in a fresh terminal: once with the terminal
# left in the foreground, once with a full-screen window raised over it a few
# seconds in. Windows Terminal is expected to stop drawing when DWM tells it
# it is fully occluded, which makes it stream FASTER -- an artifact that looks
# exactly like a win. The 08-16 round hit it: one leg measured WT 10-36%
# faster than five other runs of the same thing, ours unaffected.
#
# The occluder is the operator's own console window, maximised. Nothing is
# closed or minimised, so the session driving this is untouched.
param(
    [string]$Label = 'wt',
    [string]$Workload = '08_scroll_region',
    [int]$Reps = 10,
    [string]$BenchDir = 'C:\bench',
    [int]$OccluderPid = 0
)
$ErrorActionPreference = 'Continue'

$src = @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class Occ {
 public delegate bool EnumProc(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
 public static IntPtr Biggest(uint want) {
   IntPtr best = IntPtr.Zero; int area = 0;
   EnumWindows((h,l) => { uint p; GetWindowThreadProcessId(h, out p);
     if (p==want && IsWindowVisible(h)) { RECT r; GetWindowRect(h, out r);
       int a = (r.R-r.L)*(r.B-r.T); if (a>area) { area=a; best=h; } }
     return true; }, IntPtr.Zero);
   return best; }
 public static void Raise(IntPtr h) { ShowWindow(h, 3); SetForegroundWindow(h); }  // 3 = SW_SHOWMAXIMIZED
}
'@
if (-not ('Occ' -as [type])) { Add-Type -TypeDefinition $src -Language CSharp }

$pv = Get-AppxPackage Microsoft.WindowsTerminalPreview -EA SilentlyContinue
$WT_EXE = if ($pv) { Join-Path $pv.InstallLocation 'WindowsTerminal.exe' } else { '' }

function Kill-Terms {
    Get-Process TerminalApp -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    foreach ($p in @(Get-Process WindowsTerminal -EA SilentlyContinue)) {
        $path = try { $p.Path } catch { '' }
        if ($path -eq $WT_EXE) { Stop-Process -Id $p.Id -Force -EA SilentlyContinue }
    }
    Start-Sleep -Seconds 2
}

foreach ($mode in @('foreground', 'occluded')) {
    Kill-Terms
    $out = "$BenchDir\curve-$Label-$mode.txt"
    [System.IO.File]::Delete($out)
    $runner = "powershell -NoProfile -ExecutionPolicy Bypass -File $BenchDir\h\rep-curve.ps1 " +
              "-Label $Label-$mode -Workload $Workload -Reps $Reps -BenchDir $BenchDir"
    if ($Label -eq 'ours') {
        $env:STARLING_WINDOW_W = '1952'
        $env:STARLING_WINDOW_H = '1394'
        $env:STARLING_DEV_SHELL = $runner
        Start-Process 'C:\dist\TerminalApp\TerminalApp.exe'
    } else {
        Start-Process $WT_EXE -ArgumentList "--size 120,40 $runner"
    }
    if ($mode -eq 'occluded') {
        # Let the terminal come up and start streaming, then bury it.
        Start-Sleep -Seconds 6
        $h = [Occ]::Biggest([uint32]$OccluderPid)
        if ($h -ne [IntPtr]::Zero) { [Occ]::Raise($h); "raised occluder over $Label" }
        else { "WARNING: no occluder window found for pid $OccluderPid" }
    }
    $dl = (Get-Date).AddSeconds(400)
    while ((Get-Date) -lt $dl) {
        Start-Sleep -Seconds 3
        $b = Get-Content $out -EA SilentlyContinue
        if ($b -match 'curve_done') { break }
    }
    $rows = @(Get-Content $out -EA SilentlyContinue | Select-String '^rep ' |
              ForEach-Object { [double]($_.Line -split '\s+')[2] })
    if ($rows.Count) {
        $m = ($rows | Measure-Object -Average).Average
        "{0,-12} {1,-11} reps={2} mean={3:N3} s/rep" -f $Label, $mode, $rows.Count, $m
    } else {
        "{0,-12} {1,-11} NO DATA" -f $Label, $mode
    }
}
Kill-Terms
