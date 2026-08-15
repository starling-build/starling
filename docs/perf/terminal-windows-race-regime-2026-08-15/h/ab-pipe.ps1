# A/B the ConPTY output-pipe buffer on the 500 MB cats, ours vs ours vs wt.
#
# The pipe size is fixed when the pty opens, so the A/B granularity is one
# LAUNCH per config, alternating within each round rather than config blocks
# (this box drifts a few percent over a sitting, in different directions).
#   p4     = STARLING_CONPTY_PIPE_KB=4     (the old 4 KB default, explicit)
#   p1024  = 1 MB (the new in-code default, set explicitly anyway)
#   p4096  = 4 MB
#   wt     = Windows Terminal, same runner
param(
    [string]$BenchDir = 'C:\bench',
    [int]$Rounds = 2,
    [int]$Reps = 3
)
$ErrorActionPreference = 'Continue'
$H = Join-Path $BenchDir 'h'
$GRID = '39x120'
$log = Join-Path $BenchDir 'ab-pipe.log'

function Log($m) {
    $line = "{0}Z {1}" -f ([DateTime]::UtcNow.ToString('HH:mm:ss')), $m
    Add-Content -Encoding ascii $log $line
}

$script:preexistingWT = @(Get-Process WindowsTerminal -EA SilentlyContinue | ForEach-Object { $_.Id })

function Kill-Terms {
    Get-Process TerminalApp -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
    foreach ($p in @(Get-Process WindowsTerminal -EA SilentlyContinue)) {
        if ($script:preexistingWT -notcontains $p.Id) {
            Stop-Process -Id $p.Id -Force -EA SilentlyContinue
        }
    }
    Start-Sleep -Seconds 2
}

function Run-Leg($label, $pipeKb) {
    $result = "$BenchDir\bigcat500-$label.txt"
    Kill-Terms
    Remove-Item $result -Force -EA SilentlyContinue
    Log "=== $label ==="
    $runner = "powershell -NoProfile -ExecutionPolicy Bypass -File $H\bigcat500-win.ps1 -Label $label -Reps $Reps -BenchDir $BenchDir"
    if ($pipeKb -ge 0) {
        $env:STARLING_WINDOW_W = '976'
        $env:STARLING_WINDOW_H = '688'
        $env:STARLING_DEV_SHELL = $runner
        $env:STARLING_CONPTY_PIPE_KB = "$pipeKb"
        Start-Process 'C:\dist\TerminalApp\TerminalApp.exe'
        Remove-Item Env:STARLING_CONPTY_PIPE_KB -EA SilentlyContinue
    } else {
        Start-Process 'wt.exe' -ArgumentList "--size 120,39 $runner"
    }
    $gridSeen = ''
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Seconds 2
        if (Test-Path $result) {
            $hdr = (Get-Content $result -TotalCount 1 -EA SilentlyContinue)
            if ($hdr -match 'grid=([0-9]+x[0-9]+)') { $gridSeen = $Matches[1]; break }
        }
    }
    if ($gridSeen -ne $GRID) {
        Log "  BAD GRID '$gridSeen' (want $GRID)"
        Kill-Terms
        return $false
    }
    Log "  grid ok, streaming"
    $deadline = (Get-Date).AddSeconds(600)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        $body = if (Test-Path $result) { Get-Content $result -EA SilentlyContinue } else { @() }
        if ($body -match 'grid_after') { Log "  done"; Kill-Terms; return $true }
    }
    Log "  TIMEOUT"
    Kill-Terms
    return $false
}

Log "AB-PIPE START rounds=$Rounds reps=$Reps exe=$((Get-Item C:\dist\TerminalApp\TerminalApp.exe).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
for ($r = 1; $r -le $Rounds; $r++) {
    foreach ($cfg in @(@('p4', 4), @('p1024', 1024), @('p4096', 4096), @('wt', -1))) {
        $label = "{0}-r{1}" -f $cfg[0], $r
        $ok = $false
        for ($a = 1; $a -le 2 -and -not $ok; $a++) { $ok = Run-Leg $label $cfg[1] }
        if (-not $ok) { Log "!!! $label FAILED" }
    }
}
Log "AB-PIPE-DONE"
