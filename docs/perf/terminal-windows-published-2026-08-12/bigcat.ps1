# Ghostty's published `time cat 150MB` tests, run INSIDE the terminal under
# test. Windows port of docs/perf/terminal-vs-ghostty-2026-08-04/bigcat.sh.
#
# Records wall AND the terminal's own CPU per repetition, like the original:
# their post reports wall only, and CPU is what says whether a win is
# efficiency or parallelism.
param(
    [string]$Label = 'term',
    [string]$ProcName = 'TerminalApp',
    [int]$Reps = 2
)
$ErrorActionPreference = 'Continue'
$dir = 'C:\bench150'
$out = "C:\bench150\bigcat-$Label.txt"
$size = $Host.UI.RawUI.WindowSize
"# $Label proc=$ProcName grid=$($size.Height)x$($size.Width)" |
    Out-File -Encoding ascii $out

function TermCpu {
    $p = Get-Process -Name $ProcName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) { return $p.TotalProcessorTime.TotalSeconds } else { return 0 }
}
function ResetTerm {
    Write-Host -NoNewline ([char]27 + "[0m" + [char]27 + "[r" + [char]27 +
                           "[?1049l" + [char]27 + "[2J" + [char]27 + "[H")
}

foreach ($f in @('ascii_150mb', 'unicode_150mb')) {
    $null = [System.IO.File]::ReadAllBytes("$dir\$f.txt")   # warm cache, untimed
    for ($r = 1; $r -le $Reps; $r++) {
        ResetTerm
        Start-Sleep -Milliseconds 700
        $c0 = TermCpu
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        cmd /c type "$dir\$f.txt"
        $sw.Stop()
        $c1 = TermCpu
        ResetTerm
        Add-Content -Encoding ascii $out (
            "{0} {1} {2:N3} {3:N2}" -f $f, $r, $sw.Elapsed.TotalSeconds, ($c1 - $c0))
    }
}
$p = Get-Process -Name $ProcName -ErrorAction SilentlyContinue | Select-Object -First 1
if ($p) { Add-Content -Encoding ascii $out ("rss_kb " + [int]($p.WorkingSet64 / 1024)) }
Add-Content -Encoding ascii $out 'DONE'
Start-Sleep 3
