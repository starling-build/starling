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
    [int]$OnsetBlocks = 20
)
$ErrorActionPreference = 'Continue'
$H = Join-Path $BenchDir 'h'
# 39 rows, not the 40 of the win11 round: Windows Terminal cannot make a
# 40-row window fit this box's 1280x800 panel (it clamps to 39, which the
# broken watchdog below used to hide), and both sides must do identical work.
# Ours is sized to match rather than the other way round.
$GRID = '39x120'
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
$script:preexistingWT = @()
function Snapshot-Terms {
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
    $wt = (Get-Command wt.exe -EA SilentlyContinue).Source
    if ($wt) { $paths += $wt }
    $pkg = Get-AppxPackage Microsoft.WindowsTerminal -EA SilentlyContinue
    if ($pkg) {
        $exe = Join-Path $pkg.InstallLocation 'WindowsTerminal.exe'
        if (Test-Path $exe) { $paths += $exe }
    }
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
        'suite'  { $runner_ps = 'bench-in-terminal-long.ps1'; $sargs = "-Label $label -Runs 1";    $result = "$BenchDir\res-$label-1.txt";    $doneKey = 'grid_after';  $timeout = 3600 }
        'bigcat' { $runner_ps = 'bigcat500-win.ps1';          $sargs = "-Label $label -Reps 3";    $result = "$BenchDir\bigcat500-$label.txt"; $doneKey = 'grid_after'; $timeout = 3000 }
        'doom'   { $runner_ps = 'doomfire-long.ps1';          $sargs = "-Label $label -Reps 3 -Frames $Frames"; $result = "$BenchDir\doom-$label.txt"; $doneKey = 'grid_after'; $timeout = 2400 }
    }
    Kill-Terms
    Remove-Item $result -Force -EA SilentlyContinue
    Remove-Item "$BenchDir\meta-$label.txt", "$BenchDir\meta-calib-$label.txt" -Force -EA SilentlyContinue
    Log "=== $test/$kind attempt $attempt ==="

    $runner = "powershell -NoProfile -ExecutionPolicy Bypass -File $H\$runner_ps $sargs -BenchDir $BenchDir"
    if ($kind -eq 'ours') {
        $env:STARLING_WINDOW_W = '976'
        $env:STARLING_WINDOW_H = '688'
        $env:STARLING_DEV_SHELL = $runner
        Start-Process 'C:\dist\TerminalApp\TerminalApp.exe'
    } else {
        Start-Process 'wt.exe' -ArgumentList "--size 120,39 $runner"
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
Log "BENCH-LONG START frames=$Frames grid=$GRID"
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
