# Screenshot each terminal mid-stream, so the round rests on something other
# than the clock.
#
#   verify-render.ps1 [-Seconds 25]
#
# Why it exists: a window that never composited finishes its stream FASTER
# than one that draws it, so a blank terminal reads as a win. The
# ../terminal-windows-readpath-2026-08-11/ round hit exactly that artifact,
# and every round since has been asked to prove pixels. This streams
# 04_sgr_truecolor on a loop in each terminal in turn and grabs the screen
# while it is mid-stream.
#
# The capture is DPI-aware on purpose: without SetProcessDPIAware this
# process sees a virtualised 1920x1080 desktop and the grab comes back
# downscaled from the real 3840x2160.
param(
    [int]$Seconds = 25,
    [string]$BenchDir = 'C:\bench',
    [string]$OutDir = 'C:\bench\shots'
)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$pv = Get-AppxPackage Microsoft.WindowsTerminalPreview -EA SilentlyContinue
$WT_EXE = if ($pv) { Join-Path $pv.InstallLocation 'WindowsTerminal.exe' } else { '' }

Add-Type -AssemblyName System.Drawing
$dpi = @'
using System; using System.Runtime.InteropServices;
public class DpiAware { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
'@
if (-not ('DpiAware' -as [type])) { Add-Type -TypeDefinition $dpi -Language CSharp }
$null = [DpiAware]::SetProcessDPIAware()

# The in-terminal side: stream truecolor on a loop until killed.
$streamer = Join-Path $BenchDir 'h\_streamloop.ps1'
@(
    'param([string]$BenchDir = ''C:\bench'')'
    '. (Join-Path $PSScriptRoot ''bench-lib.ps1'')'
    'Start-Sleep -Seconds 3'
    '$deadline = (Get-Date).AddSeconds(300)'
    'while ((Get-Date) -lt $deadline) { Write-Corpus "$BenchDir\04_sgr_truecolor.txt" }'
) | Out-File -Encoding ascii $streamer

function Kill-Terms {
    Get-Process TerminalApp -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    foreach ($p in @(Get-Process WindowsTerminal -EA SilentlyContinue)) {
        $path = try { $p.Path } catch { '' }
        if ($path -eq $WT_EXE) { Stop-Process -Id $p.Id -Force -EA SilentlyContinue }
    }
    Start-Sleep -Seconds 2
}

function Shoot($name) {
    $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size)
    $p = Join-Path $OutDir "$name.png"
    $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    "shot $p  $($b.Width)x$($b.Height)"
}
Add-Type -AssemblyName System.Windows.Forms

$runner = "powershell -NoProfile -ExecutionPolicy Bypass -File $streamer -BenchDir $BenchDir"

foreach ($kind in @('ours', 'wt')) {
    Kill-Terms
    if ($kind -eq 'ours') {
        $env:STARLING_WINDOW_W = '1952'
        $env:STARLING_WINDOW_H = '1394'
        $env:STARLING_DEV_SHELL = $runner
        Start-Process 'C:\dist\TerminalApp\TerminalApp.exe'
    } else {
        Start-Process $WT_EXE -ArgumentList "--size 120,40 $runner"
    }
    Start-Sleep -Seconds $Seconds
    Shoot $kind
}
Kill-Terms
