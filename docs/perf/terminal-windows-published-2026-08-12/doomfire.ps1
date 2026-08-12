# DOOM-Fire-Zig throughput test, run INSIDE the terminal under test.
# Windows port of docs/perf/terminal-vs-ghostty-2026-08-04/doomfire.sh.
#
# The upstream program renders until a keypress; the BENCH patch stops it after
# DOOMFIRE_FRAMES frames and reports on STDERR, so stdout — the byte stream the
# terminal actually renders — is untouched and every terminal is asked for
# exactly the same work. Grid must match across terminals: the fire is
# width x (height*2).
param(
    [string]$Label = 'term',
    [string]$ProcName = 'TerminalApp',
    [int]$Reps = 3,
    [int]$Frames = 600
)
$ErrorActionPreference = 'Continue'
$bin = 'C:\doomfire\DOOM-fire.exe'
$out = "C:\doomfire\doom-$Label.txt"
$size = $Host.UI.RawUI.WindowSize
"# $Label proc=$ProcName grid=$($size.Height)x$($size.Width) frames=$Frames" |
    Out-File -Encoding ascii $out

function TermCpu {
    $p = Get-Process -Name $ProcName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) { return $p.TotalProcessorTime.TotalSeconds } else { return 0 }
}
function ResetTerm {
    Write-Host -NoNewline ([char]27 + "[0m" + [char]27 + "[r" + [char]27 +
                           "[?1049l" + [char]27 + "[2J" + [char]27 + "[H")
}

for ($r = 1; $r -le $Reps; $r++) {
    ResetTerm
    Start-Sleep 1
    $c0 = TermCpu
    # cmd does the redirection so stderr lands in the file while stdout still
    # goes to the terminal, exactly as the bash harness does it.
    cmd /c "set DOOMFIRE_FRAMES=$Frames&& `"$bin`" 2>> `"$out`""
    $c1 = TermCpu
    ResetTerm
    Add-Content -Encoding ascii $out ("  cpu_s {0:N2}" -f ($c1 - $c0))
}
ResetTerm
Add-Content -Encoding ascii $out 'DONE'
Start-Sleep 3
