# The Windows LONG round orchestrator: ours vs Windows Terminal, one sitting.
#
# Runs as a scheduled task in the INTERACTIVE session (see setup-task.ps1),
# not over SSH -- an ssh session's children die with the session, and this
# takes hours. Poll C:\bench\bench-long.log from outside to watch it.
#
# Order is ours/wt back to back per test, never all of one side then all of
# the other: this box drifts a few percent over hours, in different
# directions per workload, which the 08-12 round established the hard way.
#
#   onset   20 blocks per side   -- throttling probe, must be flat
#   suite   10 workloads, >=120 s each
#   bigcat  500 MB ascii + unicode, 3 reps
#   doom    DOOM-Fire, 150 000 frames, 3 reps
param(
    [string]$BenchDir = 'C:\bench',
    [int]$Frames = 150000,
    [string]$Only = '',
    # Smoke runs use a 2-block onset: it exercises the entire leg path
    # (launch, grid check, stream, done-key, kill) in about a minute a side,
    # which is the cheapest way to find a harness bug that would otherwise
    # surface three hours in.
    [int]$OnsetBlocks = 20,
    # Short round: ~8 minutes end to end instead of 1h45m. Every leg keeps its
    # shape -- same ten workloads, same reps-per-leg structure, same grid
    # check, same ours/wt alternation -- only the volumes shrink. Use it for
    # verification passes and for anything where a 2-hour round is the reason
    # the check does not get run at all.
    #
    # Budget, from this box's measured per-rep times: suite ~3.7 min, DOOM
    # ~2.0, bigcat ~0.7, onset ~0.3, per-leg launch and settle ~1.3.
    [switch]$Short,
    # Stream with the console on UTF-8 (chcp 65001) instead of whatever code
    # page the session inherited. The corpora are UTF-8 bytes, so without this
    # the console host reinterprets them and the unicode workloads measure
    # throughput on mojibake -- which is what every archived Windows round
    # did. Opt-in, because numbers are only comparable within one setting.
    [switch]$Utf8
)
if ($Short) {
    if (-not $PSBoundParameters.ContainsKey('Frames')) { $Frames = 10000 }
    if (-not $PSBoundParameters.ContainsKey('OnsetBlocks')) { $OnsetBlocks = 5 }
}
$ErrorActionPreference = 'Continue'
$H = Join-Path $BenchDir 'h'
# Back to 40 rows: this box is a real 4K panel (3840x2160 at 200% scale), so
# Windows Terminal fits 40x120 with room to spare -- the 39 of the fresh-VM
# round was a 1280x800 clamp, not a preference. Both sides verified at 40x120
# before the round (probe2.ps1 for ours, wt --size 120,40 for WT).
$GRID = '40x120'
$log = Join-Path $BenchDir 'bench-long.log'

function Log($m) {
    $line = "{0}Z {1}" -f ([DateTime]::UtcNow.ToString('HH:mm:ss')), $m
    Add-Content -Encoding ascii $log $line
}

# Windows 11 hosts console applications in WINDOWS TERMINAL by default, so
# this orchestrator's own powershell is itself running inside a
# WindowsTerminal.exe when it is launched from the scheduled task. A blanket
# `Get-Process WindowsTerminal | Stop-Process` therefore kills the script's own
# host, and the run dies silently after the first log line -- which is exactly
# what happened, and only under the task: over ssh there is no such host, so
# the same code ran fine and the bug looked like a task-registration problem.
#
# So: snapshot the WindowsTerminal pids that existed BEFORE the round started,
# and never kill those. TerminalApp has no such hazard.
# WINDOWS TERMINAL PREVIEW, not the 1.24 stable every earlier round measured,
# and the reason is process isolation rather than preference.
#
# WT 1.24 hosts every window in ONE process. `wt.exe`, `wt -w new`, `wt -w -1`
# and even the packaged WindowsTerminal.exe launched by full path all hand off
# to the process that is already running, so on a box where the operator's own
# shell is a Windows Terminal, the benchmark's WT window lands INSIDE it: its
# CPU delta carries whatever that shell was doing, and its RSS is the shared
# working set of every window in the process. The 08-15 VM never saw this --
# there the pre-existing WT was pid 4544 and the measured leg got pid 2092.
#
# Preview is a separate package with a separate process, so it isolates
# cleanly with no restart. The cost is that it is 1.25.1912.0 against the
# 1.24.11911.0 of the earlier rounds: WITHIN this round ours-vs-WT is a fair
# comparison, ACROSS rounds the WT column is a different build.
$script:WT_EXE = ''
$pv = Get-AppxPackage Microsoft.WindowsTerminalPreview -EA SilentlyContinue
if ($pv) { $script:WT_EXE = Join-Path $pv.InstallLocation 'WindowsTerminal.exe' }

$script:preexistingWT = @()
function Snapshot-Terms {
    # Any Preview still running from a probe MUST die before the snapshot:
    # snapshotted pids are never killed, and a surviving Preview would be the
    # process every later leg attached to -- one accumulating process measured
    # as three fresh ones.
    foreach ($p in @(Get-Process WindowsTerminal -EA SilentlyContinue)) {
        $path = try { $p.Path } catch { '' }
        if ($path -eq $script:WT_EXE) { Stop-Process -Id $p.Id -Force -EA SilentlyContinue }
    }
    Start-Sleep -Seconds 2
    $script:preexistingWT = @(Get-Process WindowsTerminal -EA SilentlyContinue | ForEach-Object { $_.Id })
    Log "pre-existing WindowsTerminal pids (never killed): $($script:preexistingWT -join ',')"
}
function Kill-Terms {
    Get-Process TerminalApp -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    foreach ($p in @(Get-Process WindowsTerminal -EA SilentlyContinue)) {
        if ($script:preexistingWT -notcontains $p.Id) {
            Stop-Process -Id $p.Id -Force -EA SilentlyContinue
        }
    }
    Start-Sleep -Seconds 2
}

# The Windows analogue of macOS's NSAppSleepDisabled: a per-executable opt-out
# from power throttling / EcoQoS. Applied to BOTH terminals, so neither is
# being throttled while the other is not -- the symmetry is the point, and the
# onset leg is what verifies it actually took.
function Disable-Throttling {
    $paths = @('C:\dist\TerminalApp\TerminalApp.exe')
    # NOT the wt.exe app-execution alias: it is a 0-byte reparse point and
    # powercfg fails on it with 0x780 ("the file cannot be accessed by the
    # system"). The packaged exe below is the process that actually runs.
    if ($script:WT_EXE -and (Test-Path $script:WT_EXE)) { $paths += $script:WT_EXE }
    foreach ($p in $paths) {
        $r = powercfg /powerthrottling disable /path "$p" 2>&1
        Log "powerthrottling disable '$p' -> $r"
    }
}

# One leg. Returns $true when it produced a result at the right grid.
function Run-Leg($test, $kind, $attempt) {
    $label = $kind
    switch ($test) {
        'onset'  { $runner_ps = 'onset.ps1';                 $sargs = "-Label $label -Blocks $OnsetBlocks"; $result = "$BenchDir\onset-$label.txt";    $doneKey = 'onset_done';  $timeout = 900 }
        'calib'  { $runner_ps = 'bench-in-terminal-long.ps1'; $sargs = "-Label calib-$label -Runs 1 -ForceReps 1"; $result = "$BenchDir\res-calib-$label-1.txt"; $doneKey = 'grid_after'; $timeout = 900 }
        'suite'  { $runner_ps = 'bench-in-terminal-long.ps1'; $sargs = "-Label $label -Runs 1$(if ($Short) { ' -Short' })"; $result = "$BenchDir\res-$label-1.txt";    $doneKey = 'grid_after';  $timeout = 3600 }
        'bigcat' { $runner_ps = 'bigcat500-win.ps1';          $sargs = "-Label $label -Reps $(if ($Short) { 2 } else { 3 })"; $result = "$BenchDir\bigcat500-$label.txt"; $doneKey = 'grid_after'; $timeout = 3000 }
        'doom'   { $runner_ps = 'doomfire-long.ps1';          $sargs = "-Label $label -Reps 3 -Frames $Frames"; $result = "$BenchDir\doom-$label.txt"; $doneKey = 'grid_after'; $timeout = 2400 }
    }
    # One place, so a new test cannot forget it and quietly run the other mode.
    if ($Utf8) { $sargs = "$sargs -Utf8" }

    Kill-Terms
    Remove-Item $result -Force -EA SilentlyContinue
    Remove-Item "$BenchDir\meta-$label.txt", "$BenchDir\meta-calib-$label.txt" -Force -EA SilentlyContinue
    Log "=== $test/$kind attempt $attempt ==="

    $runner = "powershell -NoProfile -ExecutionPolicy Bypass -File $H\$runner_ps $sargs -BenchDir $BenchDir"
    if ($kind -eq 'ours') {
        # Device pixels, and they are ~2x the fresh-VM round's because the cell
        # is: 16 x 34.9 device px at this panel's 200% scale, against 8 x 17.6
        # at 100%. Found by probe2.ps1, not computed -- the chrome is not a
        # documented constant.
        $env:STARLING_WINDOW_W = '1952'
        $env:STARLING_WINDOW_H = '1394'
        $env:STARLING_DEV_SHELL = $runner
        Start-Process 'C:\dist\TerminalApp\TerminalApp.exe'
    } else {
        Start-Process $script:WT_EXE -ArgumentList "--size 120,40 $runner"
    }

    # Early grid check -- the watchdog, folded in. The runners settle 3 s and
    # then write their header, so a wrong grid is known within ~10 s instead
    # of after a 20-40 minute leg.
    # NOTE: this local must NOT be called $grid. PowerShell variables are
    # case-insensitive, so `$grid` and the script's `$GRID` target are ONE
    # variable: the assignment below overwrote the thing it was about to be
    # compared against, `-ne` tested a value against itself, and the grid
    # watchdog could never fail. It silently passed a 39x120 Windows Terminal
    # against our 40x120 for a whole round.
    $gridSeen = ''
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Seconds 2
        if (Test-Path $result) {
            $h = (Get-Content $result -TotalCount 1 -EA SilentlyContinue)
            if ($h -match 'grid=([0-9]+x[0-9]+)') { $gridSeen = $Matches[1]; break }
        }
    }
    if ($gridSeen -ne $GRID) {
        Log "  BAD GRID '$gridSeen' (want $GRID) -- killing after $([int]($i*2))s"
        Kill-Terms
        return $false
    }
    Log "  grid $gridSeen ok, streaming"

    $deadline = (Get-Date).AddSeconds($timeout)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $body = if (Test-Path $result) { Get-Content $result -EA SilentlyContinue } else { @() }
        if ($body -match $doneKey) {
            $gline = @($body | Where-Object { $_ -like 'grid_after *' }) | Select-Object -Last 1
            $after = if ($gline) { ($gline -split '\s+')[1] } else { '' }
            if ($test -ne 'onset' -and $after -and $after.Trim() -ne $GRID) {
                Log "  grid CHANGED mid-leg to '$after' -- discarding"
                Kill-Terms
                return $false
            }
            Log "  done"
            Kill-Terms
            return $true
        }
    }
    Log "  TIMEOUT after $timeout s"
    Kill-Terms
    return $false
}

# --- go ---------------------------------------------------------------------
Log "BENCH-LONG START frames=$Frames grid=$GRID short=$([bool]$Short) onsetblocks=$OnsetBlocks utf8=$([bool]$Utf8)"
Log "workstation locked: $([bool](Get-Process LogonUI -EA SilentlyContinue))"
if (-not $script:WT_EXE -or -not (Test-Path $script:WT_EXE)) {
    Log "FATAL: Windows Terminal Preview not installed -- no rival to measure"
    exit 1
}
Log "wt exe $script:WT_EXE ($((Get-AppxPackage Microsoft.WindowsTerminalPreview).Version))"
Snapshot-Terms
Disable-Throttling

$tests = if ($Only) { @($Only -split ',' | ForEach-Object { $_.Trim() }) } else { @('onset', 'suite', 'bigcat', 'doom') }
foreach ($test in $tests) {
    foreach ($kind in @('ours', 'wt')) {
        $ok = $false
        for ($a = 1; $a -le 3 -and -not $ok; $a++) { $ok = Run-Leg $test $kind $a }
        if (-not $ok) { Log "!!! $test/$kind FAILED after 3 attempts" }
    }
    if ($test -eq 'onset') {
        foreach ($k in @('ours', 'wt')) {
            $v = Select-String -Path "$BenchDir\onset-$k.txt" -Pattern '^VERDICT' -EA SilentlyContinue
            Log "onset $k -> $($v.Line)"
        }
    }
}
Log "BENCH-LONG-DONE"
