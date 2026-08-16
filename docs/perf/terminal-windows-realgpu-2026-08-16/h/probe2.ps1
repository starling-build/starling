# Second-generation grid probe: solve for the cell from two measurements, then
# try the neighbourhood. The stock probe-grid.ps1 hardcodes 8-9 x 17-19 cell
# candidates, which are 100%-scale numbers; this box is a 4K panel at 200%, so
# the cell is ~16 x 34 device pixels and none of those candidates can match.
param(
    [string]$Target = '40x120',
    [string]$BenchDir = 'C:\bench',
    [int[]]$W = @(),
    [int[]]$H = @()
)
$ErrorActionPreference = 'Continue'
$log = "$BenchDir\probe2.log"
$probe = "$BenchDir\h\_gridprobe.ps1"

@(
    'Start-Sleep -Seconds 3'
    '$s = $Host.UI.RawUI.WindowSize'
    ('"grid $($s.Height)x$($s.Width)" | Out-File -Encoding ascii ' + "'$BenchDir\gridprobe.txt'")
    'Start-Sleep 600'
) | Out-File -Encoding ascii $probe

# NOT $w/$h: PowerShell variables are case-insensitive, so the loop's $w and
# the script's -W parameter would be ONE variable -- the same trap bench-lib
# and stage-windows.ps1 both document. It cost a probe pass here too.
function Try-Size([int]$px, [int]$py) {
    Get-Process TerminalApp -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    Start-Sleep -Seconds 2
    Remove-Item "$BenchDir\gridprobe.txt" -Force -EA SilentlyContinue
    $env:STARLING_WINDOW_W = "$px"
    $env:STARLING_WINDOW_H = "$py"
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

"probe2 start target=$Target" | Out-File -Encoding ascii $log
foreach ($cand_w in $W) {
    foreach ($cand_h in $H) {
        $g = Try-Size $cand_w $cand_h
        Add-Content -Encoding ascii $log "${cand_w}x${cand_h} -> $g"
        if ($g -eq $Target) {
            Add-Content -Encoding ascii $log "MATCH $cand_w $cand_h"
            "MATCH $cand_w $cand_h" | Out-File -Encoding ascii "$BenchDir\grid-size.txt"
            Add-Content -Encoding ascii $log 'probe_done'
            exit 0
        }
    }
}
Add-Content -Encoding ascii $log 'NO MATCH'
Add-Content -Encoding ascii $log 'probe_done'
