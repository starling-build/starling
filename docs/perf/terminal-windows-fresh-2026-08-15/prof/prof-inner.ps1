# Runs INSIDE the terminal under test. Snapshots per-process CPU either side
# of each cat, so attribution needs no clock alignment between two scripts.
param([string]$Out = 'C:\prof', [int]$Reps = 2, [string]$BenchDir = 'C:\bench')
. (Join-Path $BenchDir 'h\bench-lib.ps1')

function CpuSnap {
    $m = @{}
    foreach ($n in @('TerminalApp','WindowsTerminal','OpenConsole','conhost','powershell')) {
        foreach ($p in @(Get-Process $n -EA SilentlyContinue)) {
            $m["$($p.ProcessName)#$($p.Id)"] = $p.TotalProcessorTime.TotalSeconds
        }
    }
    return $m
}

Start-Sleep -Seconds 3
[IO.File]::WriteAllText((Join-Path $Out 'go'), (Get-Grid))
$res = @()
foreach ($kind in @('ascii','unicode')) {
    $f = Join-Path $BenchDir "big500-$kind.bin"
    for ($r = 1; $r -le $Reps; $r++) {
        Reset-Term
        Start-Sleep -Milliseconds 800
        $c0 = CpuSnap
        $sw = [Diagnostics.Stopwatch]::StartNew()
        Write-Corpus $f
        $sw.Stop()
        $c1 = CpuSnap
        $wall = $sw.Elapsed.TotalSeconds
        $parts = @()
        $tot = 0.0
        foreach ($k in ($c1.Keys | Sort-Object)) {
            $d = $c1[$k] - $(if ($c0.ContainsKey($k)) { $c0[$k] } else { 0 })
            if ($d -gt 0.05) {
                $parts += ("{0} {1:N2}s/{2:N2}c" -f $k, $d, ($d / $wall))
                $tot += $d
            }
        }
        $res += ("{0} {1} wall {2:N3} totcpu {3:N2} ({4:N2} cores) :: {5}" -f `
                 $kind, $r, $wall, $tot, ($tot / $wall), ($parts -join ' | '))
        [IO.File]::WriteAllText((Join-Path $Out 'res'), ($res -join "`n"))
        Start-Sleep -Milliseconds 800
    }
}
[IO.File]::WriteAllText((Join-Path $Out 'done'), '1')
Start-Sleep -Seconds 300
