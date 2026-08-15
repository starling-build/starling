# Throttling onset probe -- the Windows counterpart of the macOS onset.sh.
#
#   onset.ps1 -Label ours|wt [-Blocks 20]
#
# On macOS this round's first attempt produced garbage because App Nap
# engaged after almost exactly 27 s of sustained streaming and collapsed the
# leg ~12x. Windows has its own version of that hazard -- EcoQoS / power
# throttling, which the scheduler applies to processes whose windows are not
# in the foreground -- so the same probe has to run here BEFORE any long leg
# is believed.
#
# Method: stream the same block repeatedly and print the wall time of each.
# A flat series means no throttling engaged. A step change partway through is
# the cliff, and every number taken after it is worthless.
param(
    [string]$Label = 'term',
    [int]$Blocks = 20,
    [string]$BenchDir = 'C:\bench'
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'bench-lib.ps1')

Start-Sleep -Seconds 3
$term = Find-Terminal
$out = "$BenchDir\onset-$Label.txt"
if (-not $term) { "no terminal found" | Out-File -Encoding ascii $out; Start-Sleep 900; exit 1 }
"# $Label grid=$(Get-Grid) pid=$($term.Pid) blocks=$Blocks" | Out-File -Encoding ascii $out

$f = "$BenchDir\03_sgr_fg.txt"
$elapsed = 0.0
for ($i = 1; $i -le $Blocks; $i++) {
    Reset-Term
    $c0 = Get-TermCpuMap $term.Pid
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Corpus $f
    $sw.Stop()
    $c1 = Get-TermCpuMap $term.Pid
    $elapsed += $sw.Elapsed.TotalSeconds
    Add-Content -Encoding ascii $out ("block {0} {1:N3} cum {2:N1} cpu {3:N2}" -f `
        $i, $sw.Elapsed.TotalSeconds, $elapsed, (Sum-CpuDelta $c0 $c1))
}
Reset-Term

# Flag the cliff rather than leaving it for a human to spot in a column of
# numbers: the check that matters is late-vs-early, not any single block.
$rows = Get-Content $out | Select-String '^block ' | ForEach-Object { [double]($_.Line -split '\s+')[2] }
if ($rows.Count -ge 6) {
    $early = ($rows[0..2] | Measure-Object -Average).Average
    $late = ($rows[-3..-1] | Measure-Object -Average).Average
    $ratio = if ($early -gt 0) { $late / $early } else { 0 }
    Add-Content -Encoding ascii $out ("early {0:N3} late {1:N3} ratio {2:N2}" -f $early, $late, $ratio)
    if ($ratio -gt 1.5) { Add-Content -Encoding ascii $out "VERDICT THROTTLED" }
    else { Add-Content -Encoding ascii $out "VERDICT flat" }
}
Add-Content -Encoding ascii $out "onset_done"
Start-Sleep 900
