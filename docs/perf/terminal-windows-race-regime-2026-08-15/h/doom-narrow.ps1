# DOOM-Fire at the race grid (43x76), ours vs Windows Terminal, alternating.
param([string]$BenchDir = 'C:\bench', [int]$Frames = 30000, [int]$Reps = 2)
$ErrorActionPreference = 'Continue'
$H = Join-Path $BenchDir 'h'
$GRID = '43x76'
$log = Join-Path $BenchDir 'doom-narrow.log'
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
function Wait-Header($result) {
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 2
        if (Test-Path $result) {
            $hdr = (Get-Content $result -TotalCount 1 -EA SilentlyContinue)
            if ($hdr -match 'grid=([0-9]+x[0-9]+)') { return $Matches[1] }
        }
    }
    return ''
}

# Discover the window width that yields exactly 76 columns at 43 rows.
$oursW = 0
foreach ($w in @(620, 618, 622, 616, 624)) {
    Kill-Terms
    $probe = "$BenchDir\doom-nprobe.txt"
    Remove-Item $probe -Force -EA SilentlyContinue
    $env:STARLING_WINDOW_W = "$w"
    $env:STARLING_WINDOW_H = '762'
    $env:STARLING_DEV_SHELL = "powershell -NoProfile -ExecutionPolicy Bypass -File $H\doomfire-long.ps1 -Label nprobe -Frames 1 -Reps 1 -BenchDir $BenchDir"
    Start-Process 'C:\dist\TerminalApp\TerminalApp.exe'
    $g = Wait-Header $probe
    Log "probe w=$w grid=$g"
    if ($g -eq $GRID) { $oursW = $w; break }
}
Kill-Terms
if ($oursW -eq 0) { Log 'NO WIDTH FOUND'; Log 'DOOM-NARROW-DONE'; return }

foreach ($r in 1..2) {
    foreach ($kind in @('ours', 'wt')) {
        $label = "n$kind-r$r"
        $result = "$BenchDir\doom-$label.txt"
        $ok = $false
        for ($a = 1; $a -le 2 -and -not $ok; $a++) {
            Kill-Terms
            Remove-Item $result -Force -EA SilentlyContinue
            Log "=== $label attempt $a ==="
            $runner = "powershell -NoProfile -ExecutionPolicy Bypass -File $H\doomfire-long.ps1 -Label $label -Frames $Frames -Reps $Reps -BenchDir $BenchDir"
            if ($kind -eq 'ours') {
                $env:STARLING_WINDOW_W = "$oursW"
                $env:STARLING_WINDOW_H = '762'
                $env:STARLING_DEV_SHELL = $runner
                Start-Process 'C:\dist\TerminalApp\TerminalApp.exe'
            } else {
                Start-Process 'wt.exe' -ArgumentList "--window new --size 76,43 $runner"
            }
            $g = Wait-Header $result
            if ($g -ne $GRID) { Log "  BAD GRID '$g'"; continue }
            Log '  grid ok, streaming'
            $deadline = (Get-Date).AddSeconds(600)
            while ((Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 5
                $body = if (Test-Path $result) { Get-Content $result -EA SilentlyContinue } else { @() }
                if ($body -match 'grid_after') { Log '  done'; $ok = $true; break }
            }
            if (-not $ok) { Log '  TIMEOUT' }
        }
        Kill-Terms
        if (-not $ok) { Log "!!! $label FAILED" }
    }
}
Log 'DOOM-NARROW-DONE'
