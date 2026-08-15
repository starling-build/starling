# Find the TerminalApp window size that yields the round's grid.
#
#   probe-grid.ps1 [-Target 40x120]
#
# Runs as the interactive scheduled task. Ours sizes its window in PIXELS
# (STARLING_WINDOW_W/H) and the grid falls out of the cell metrics; Windows
# Terminal is told the grid directly (--size cols,rows). So the two are only
# comparable once this has found the pixel size that lands ours on the same
# grid, and that size moves whenever the cell does -- 960x620 was 40x120 for
# the 08-11 round and is 35x118 now, because the atlas snaps the cell to whole
# device pixels.
#
# Deliberately a probe rather than arithmetic: the chrome is not a documented
# constant, and a round that assumes it silently benchmarks two different
# grids, which is the single mistake the 08-11 report had to retract.
param(
    [string]$Target = '40x120',
    [string]$BenchDir = 'C:\bench'
)
$ErrorActionPreference = 'Continue'
$log = "$BenchDir\probe-grid.log"
$probe = "$BenchDir\h\_gridprobe.ps1"

# The in-terminal side: report the grid and go away.
@(
    'Start-Sleep -Seconds 3'
    '$s = $Host.UI.RawUI.WindowSize'
    ('"grid $($s.Height)x$($s.Width)" | Out-File -Encoding ascii ' + "'$BenchDir\gridprobe.txt'")
    'Start-Sleep 600'
) | Out-File -Encoding ascii $probe

$rows, $cols = $Target -split 'x'
$rows = [int]$rows; $cols = [int]$cols

function Try-Size([int]$W, [int]$H) {
    Get-Process TerminalApp -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep -Seconds 2
    Remove-Item "$BenchDir\gridprobe.txt" -Force -EA SilentlyContinue
    $env:STARLING_WINDOW_W = "$W"
    $env:STARLING_WINDOW_H = "$H"
    $env:STARLING_DEV_SHELL = "powershell -NoProfile -ExecutionPolicy Bypass -File $probe"
    Start-Process 'C:\dist\TerminalApp\TerminalApp.exe'
    for ($i = 0; $i -lt 25; $i++) {
        Start-Sleep -Seconds 1
        if (Test-Path "$BenchDir\gridprobe.txt") {
            $g = (Get-Content "$BenchDir\gridprobe.txt" -TotalCount 1) -replace 'grid ', ''
            Get-Process TerminalApp -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
            return $g.Trim()
        }
    }
    Get-Process TerminalApp -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    return 'timeout'
}

"probe start target=$Target" | Out-File -Encoding ascii $log

# One measurement, then solve for the chrome and jump straight to the answer;
# a couple of neighbours after it, because the cell may be fractional and the
# floor can land either side.
$g0 = Try-Size 960 620
Add-Content -Encoding ascii $log "960x620 -> $g0"
if ($g0 -match '^([0-9]+)x([0-9]+)$') {
    $r0 = [int]$Matches[1]; $c0 = [int]$Matches[2]
    $cellW = 960.0 / $c0
    $cellH = 620.0 / $r0
    # refine: assume chrome is the remainder after whole cells
    foreach ($cw in @(8, 9)) {
        foreach ($ch in @(17, 18, 19)) {
            $chromeW = 960 - ($c0 * $cw)
            $chromeH = 620 - ($r0 * $ch)
            if ($chromeW -lt 0 -or $chromeH -lt 0) { continue }
            $W = ($cols * $cw) + $chromeW
            $H = ($rows * $ch) + $chromeH
            $g = Try-Size $W $H
            Add-Content -Encoding ascii $log "${W}x${H} (cell ${cw}x${ch}) -> $g"
            if ($g -eq $Target) {
                Add-Content -Encoding ascii $log "MATCH $W $H"
                "MATCH $W $H" | Out-File -Encoding ascii "$BenchDir\grid-size.txt"
                Add-Content -Encoding ascii $log 'probe_done'
                exit 0
            }
        }
    }
}
Add-Content -Encoding ascii $log 'NO MATCH'
Add-Content -Encoding ascii $log 'probe_done'
