# Terminal benchmark runner - runs INSIDE the terminal under test (Windows).
# Mirrors test/bench/run-bench.sh: per-workload wall via Stopwatch, terminal
# CPU via TotalProcessorTime deltas, grid recorded so nothing is trusted.
# Pure ASCII on purpose (see windows-powershell-authoring notes).
param(
    [string]$Label = "term",
    [string]$ProcName = "TerminalApp",
    [int]$Reps = 3
)
$ErrorActionPreference = 'Continue'
$out = "C:\bench\res-$Label.txt"
$size = $Host.UI.RawUI.WindowSize
"# $Label proc=$ProcName grid=$($size.Height)x$($size.Width)" | Out-File -Encoding ascii $out

function TermCpu {
    $p = Get-Process -Name $ProcName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) { return $p.TotalProcessorTime.TotalSeconds } else { return 0 }
}

$files = Get-ChildItem C:\bench\0*.txt, C:\bench\10_binary.txt | Sort-Object Name
foreach ($f in $files) {
    $null = [System.IO.File]::ReadAllBytes($f.FullName)   # warm cache
    for ($r = 1; $r -le $Reps; $r++) {
        Write-Host -NoNewline ([char]27 + "[0m" + [char]27 + "[r" + [char]27 + "[?1049l" + [char]27 + "[2J" + [char]27 + "[H")
        Start-Sleep -Milliseconds 700
        $c0 = TermCpu
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        cmd /c type $f.FullName
        $sw.Stop()
        $c1 = TermCpu
        $name = $f.BaseName
        $line = "{0} {1} {2:N3} {3:N2}" -f $name, $r, $sw.Elapsed.TotalSeconds, ($c1 - $c0)
        Add-Content -Encoding ascii $out $line
    }
}
$p = Get-Process -Name $ProcName -ErrorAction SilentlyContinue | Select-Object -First 1
if ($p) { Add-Content -Encoding ascii $out ("rss_kb " + [int]($p.WorkingSet64 / 1024)) }
Add-Content -Encoding ascii $out "DONE"
Start-Sleep 3
