# The 10-workload suite, run from INSIDE the terminal under test.
#
#   bench-in-terminal-long.ps1 -Label ours|wt [-Runs 1]
#
# Used as the terminal's shell (STARLING_DEV_SHELL for TerminalApp) or as
# wt.exe's command. The Windows counterpart of the macOS
# bench-in-terminal-long.sh, with two differences that matter:
#
#   - CPU is the terminal PLUS its console host (see bench-lib.ps1).
#   - each workload is REPEATED so the leg runs minutes rather than seconds,
#     and the whole repeat block is timed as one measurement. Repeat counts
#     target >=120 s on the slower side, taken from the controlled 08-12
#     medians in ../terminal-windows-main-2026-08-12/.
param(
    [string]$Label = 'term',
    [int]$Runs = 1,
    # Calibration: force this many reps for every workload instead of the
    # table below. The table has to be derived from measurements taken with
    # THIS harness -- the 08-12 medians it was first built from were taken
    # through `cmd /c type`, which turned out to be the thing setting the
    # pace, so they overstate every workload by an order of magnitude.
    [int]$ForceReps = 0,
    [string]$BenchDir = 'C:\bench'
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'bench-lib.ps1')

# name -> reps, targeting >=120 s on the SLOWER side.
#
# Derived from a calibration leg run by THIS harness on 2026-08-14 (1 rep per
# workload, both terminals, verified 40x120), NOT from the 08-12 medians. That
# matters: those were taken through `cmd /c type`, which is itself the
# bottleneck -- 03_sgr_fg measured 18.36 s there and 1.15 s here off the same
# file. Reusing them would have made every leg 15x longer than intended and,
# worse, sized the round against the writer instead of the terminals.
# NOT $REPS: PowerShell variables are case-insensitive, so $REPS and the
# loop's own $reps are ONE variable. The first workload's assignment
# overwrote this table with an integer, every later ContainsKey() threw on
# it, the failed assignment left $reps holding the previous value, and all
# ten workloads silently ran 437 reps -- a 45-minute leg that looked
# plausible and measured the wrong thing. sdk/tools/stage-windows.ps1
# documents the same trap for $zip/$Zip.
$WORKLOAD_REPS = @{
    '01_light_cells' = 437
    '02_dense_cells' = 1334
    '03_sgr_fg' = 105
    '04_sgr_truecolor' = 139
    '05_unicode' = 300
    '06_cursor_motion' = 2000
    '07_alt_screen' = 586
    '08_scroll_region' = 123
    '09_long_lines' = 1250
    '10_binary' = 12
}

# The window is created at a default size and resized a moment later.
# Recording the grid immediately races that resize -- on macOS ghostty
# transiently read 17x49 and a GOOD leg got killed by the watchdog. Settle.
Start-Sleep -Seconds 3

$term = Find-Terminal
if (-not $term) {
    "bench-in-terminal: could not find the terminal process" | Out-File -Encoding ascii "$BenchDir\meta-$Label.txt"
    Start-Sleep 900
    exit 1
}

# Record what CPU was attributed to, so a report cannot silently measure the
# wrong process.
$hostPids = (Get-TermCpuMap $term.Pid).Keys | Sort-Object
@(
    "label $Label"
    "terminal_pid $($term.Pid)"
    "terminal_comm $($term.Name)"
    "cpu_pids $($hostPids -join ',')"
    "grid $(Get-Grid)"
) | Out-File -Encoding ascii "$BenchDir\meta-$Label.txt"

# The table has to survive the loop. Assert it up front and record the plan
# in the result file, so a leg that ran the wrong repeat counts is obvious in
# the data instead of only in a ratio that looks a bit off.
if ($WORKLOAD_REPS -isnot [hashtable]) {
    "FATAL: WORKLOAD_REPS is $($WORKLOAD_REPS.GetType().Name), not a hashtable" |
        Out-File -Encoding ascii "$BenchDir\res-$Label-1.txt"
    Start-Sleep 900
    exit 1
}

$files = Get-ChildItem "$BenchDir\0*.txt", "$BenchDir\10_binary.txt" | Sort-Object Name

for ($run = 1; $run -le $Runs; $run++) {
    $out = "$BenchDir\res-$Label-$run.txt"
    "# $Label grid=$(Get-Grid) pid=$($term.Pid)" | Out-File -Encoding ascii $out
    $plan = ($files | ForEach-Object { $n = $_.BaseName
             $v = if ($ForceReps -gt 0) { $ForceReps } elseif ($WORKLOAD_REPS.ContainsKey($n)) { $WORKLOAD_REPS[$n] } else { 1 }
             "$n=$v" }) -join ' '
    Add-Content -Encoding ascii $out "# plan $plan"
    foreach ($f in $files) {
        $name = $f.BaseName
        $reps = if ($ForceReps -gt 0) { $ForceReps }
                elseif ($WORKLOAD_REPS.ContainsKey($name)) { $WORKLOAD_REPS[$name] } else { 1 }
        $null = [System.IO.File]::ReadAllBytes($f.FullName)   # warm the cache
        Reset-Term
        Start-Sleep -Milliseconds 700
        $c0 = Get-TermCpuMap $term.Pid
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        for ($r = 0; $r -lt $reps; $r++) { Write-Corpus $f.FullName }
        $sw.Stop()
        $c1 = Get-TermCpuMap $term.Pid
        Reset-Term
        $cpu = Sum-CpuDelta $c0 $c1
        $line = "{0} {1:N3} {2:N2} {3}" -f $name, $sw.Elapsed.TotalSeconds, $cpu, $reps
        Add-Content -Encoding ascii $out $line
    }
    Add-Content -Encoding ascii $out ("rss_kb " + (Get-TermRssKb $term.Pid))
    Add-Content -Encoding ascii $out ("grid_after " + (Get-Grid))
}

# Hold the terminal open; the orchestrator kills it once the done-key lands.
Start-Sleep 900
