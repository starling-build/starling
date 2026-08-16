# Time EVERY repetition of one workload, from inside the terminal under test.
#
#   rep-curve.ps1 -Label ours|wt [-Workload 08_scroll_region] [-Reps 60]
#
# The suite runner times a whole repeat block as one measurement, which is
# what a round wants but hides the shape inside it. This box found Windows
# Terminal costing ~1.48 s per repetition over a 10-rep leg and ~2.50 s over
# a 123-rep leg, with ours flat at ~1.48 either way -- and ruled out
# cumulative-bytes-since-launch (a fresh process reproduces it), memory
# (RSS 88-107 MB), CPU clock (flat at 79.6% of nominal through a 5 min leg),
# and the lock screen (<=5%). So the decay is inside the terminal, and the
# per-repetition curve is what says whether it is a gradual slide or a step.
#
# No Reset-Term between repetitions on purpose: resetting would change the
# workload being measured. The stream is continuous, exactly as in a leg.
param(
    [string]$Label = 'term',
    [string]$Workload = '08_scroll_region',
    [int]$Reps = 60,
    [string]$BenchDir = 'C:\bench'
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'bench-lib.ps1')

Start-Sleep -Seconds 3
$term = Find-Terminal
$out = "$BenchDir\curve-$Label.txt"
if (-not $term) { "no terminal found" | Out-File -Encoding ascii $out; Start-Sleep 900; exit 1 }

$f = "$BenchDir\$Workload.txt"
"# $Label grid=$(Get-Grid) pid=$($term.Pid) workload=$Workload reps=$Reps" |
    Out-File -Encoding ascii $out
$null = [System.IO.File]::ReadAllBytes($f)
Reset-Term
Start-Sleep -Milliseconds 700

for ($r = 1; $r -le $Reps; $r++) {
    $c0 = Get-TermCpuMap $term.Pid
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Corpus $f
    $sw.Stop()
    $c1 = Get-TermCpuMap $term.Pid
    Add-Content -Encoding ascii $out ("rep {0} {1:N3} {2:N2}" -f $r, $sw.Elapsed.TotalSeconds, (Sum-CpuDelta $c0 $c1))
}
Reset-Term
Add-Content -Encoding ascii $out ("rss_kb " + (Get-TermRssKb $term.Pid))
Add-Content -Encoding ascii $out ("grid_after " + (Get-Grid))
Add-Content -Encoding ascii $out 'curve_done'
Start-Sleep 900
