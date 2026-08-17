# DOOM-Fire-Zig at long-round frame counts, run INSIDE the terminal.
#
#   doomfire-long.ps1 -Label ours|wt [-Reps 3] [-Frames 150000]
#
# The upstream program renders until a keypress; the BENCH patch stops after
# DOOMFIRE_FRAMES frames and reports on STDERR, so stdout -- the byte stream
# the terminal renders -- is untouched and both terminals are asked for
# exactly the same work.
#
# Unlike ../terminal-windows-published-2026-08-12/doomfire.ps1 this counts the
# console host's CPU alongside the terminal's, which is the whole point of the
# round: on Windows the host is doing a large share of the work and attributing
# it to nobody makes our efficiency look better than it is.
param(
    [string]$Label = 'term',
    [int]$Reps = 3,
    [int]$Frames = 150000,
    # Accepted for symmetry with the other runners and deliberately unused:
    # DOOM-fire-zig calls SetConsoleOutputCP(CP_UTF8) itself at startup, so
    # this leg is already UTF-8 in both modes and setting it here would only
    # obscure that.
    [switch]$Utf8,
    [string]$BenchDir = 'C:\bench'
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'bench-lib.ps1')

$bin = 'C:\doomfire\DOOM-fire.exe'
Start-Sleep -Seconds 3
$term = Find-Terminal
$out = "$BenchDir\doom-$Label.txt"
if (-not $term) {
    "no terminal found" | Out-File -Encoding ascii $out
    Start-Sleep 900
    exit 1
}
"# $Label grid=$(Get-Grid) pid=$($term.Pid) frames=$Frames" | Out-File -Encoding ascii $out

for ($r = 1; $r -le $Reps; $r++) {
    Reset-Term
    Start-Sleep -Seconds 1
    $c0 = Get-TermCpuMap $term.Pid
    # cmd does the redirection so stderr lands in the file while stdout still
    # goes to the terminal, exactly as the bash harness does it.
    cmd /c "set DOOMFIRE_FRAMES=$Frames&& `"$bin`" 2>> `"$out`""
    $c1 = Get-TermCpuMap $term.Pid
    Reset-Term
    Add-Content -Encoding ascii $out ("  cpu_s {0:N2}" -f (Sum-CpuDelta $c0 $c1))
}
Add-Content -Encoding ascii $out ("rss_kb " + (Get-TermRssKb $term.Pid))
Add-Content -Encoding ascii $out ("grid_after " + (Get-Grid))
Start-Sleep 900

