param(
    [ValidateSet('ours', 'wt')][string]$Mode = 'ours',
    [string]$Label = 'doomprof',
    [int]$Frames = 6000,
    # Diagnostic: suppress all repaints (TerminalView.swift honours this) to
    # separate consume+parse cost from render cost. Draws nothing — never a
    # performance number, only a decomposition.
    [switch]$NoRepaint
)
$ErrorActionPreference = 'Continue'
$rel = 'C:\src\starling-main\apps\TerminalApp\.build\x86_64-unknown-windows-msvc\release'
$term = if ($Mode -eq 'ours') { 'TerminalApp' } else { 'WindowsTerminal' }

# Inner driver: one long DOOM run so there is a steady window to sample.
$inner = @()
$inner += 'Write-Host -NoNewline ([char]27 + "[0m" + [char]27 + "[r" + [char]27 + "[?1049l" + [char]27 + "[2J" + [char]27 + "[H")'
$inner += 'Start-Sleep 3'
$inner += '"GO" | Out-File -Encoding ascii C:\doomfire\prof-go.txt'
$inner += "cmd /c `"set DOOMFIRE_FRAMES=$Frames&& C:\doomfire\DOOM-fire.exe 2>> C:\doomfire\prof-$Label.err`""
$inner += '"END" | Out-File -Encoding ascii C:\doomfire\prof-done.txt'
$inner += 'Start-Sleep 5'
Set-Content -Encoding ascii C:\doomfire\profinner.ps1 $inner

$runner = 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\doomfire\profinner.ps1'
$cmd = @()
$cmd += '@echo off'
if ($Mode -eq 'ours') {
    $cmd += "set STARLING_DEV_SHELL=$runner"
    $cmd += 'set STARLING_WINDOW_W=960'
    $cmd += 'set STARLING_WINDOW_H=620'
    if ($NoRepaint) { $cmd += 'set STARLING_BENCH_NOREPAINT=1' }
    $cmd += 'start "" ' + "$rel\TerminalApp.exe"
} else {
    $cmd += "start `"`" wt --size 120,40 $runner"
}
Set-Content -Encoding ascii C:\src\run-terminal.cmd $cmd

Remove-Item C:\doomfire\prof-go.txt, C:\doomfire\prof-done.txt, "C:\doomfire\prof-$Label.err" -Force -ErrorAction SilentlyContinue
Stop-Process -Name TerminalApp, WindowsTerminal -Force -ErrorAction SilentlyContinue
Start-Sleep 2
schtasks /run /tn StarlingRunTerminal | Out-Null

for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep 1
    if (Test-Path C:\doomfire\prof-go.txt) { break }
}
if (-not (Test-Path C:\doomfire\prof-go.txt)) { Write-Output 'NO GO'; exit 1 }

$names = @($term, 'OpenConsole', 'conhost', 'DOOM-fire')
function Snap {
    $h = @{}
    foreach ($n in $names) {
        $t = 0.0
        foreach ($p in (Get-Process -Name $n -ErrorAction SilentlyContinue)) {
            try { $t += $p.TotalProcessorTime.TotalSeconds } catch {}
        }
        $h[$n] = $t
    }
    return $h
}
function ThreadSnap {
    $h = @{}
    $p = Get-Process -Name $term -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) {
        foreach ($t in $p.Threads) {
            try { $h["$($t.Id)"] = $t.TotalProcessorTime.TotalSeconds } catch {}
        }
    }
    return $h
}

$a = Snap; $ta = ThreadSnap
$t0 = Get-Date
while (-not (Test-Path C:\doomfire\prof-done.txt)) {
    Start-Sleep -Milliseconds 300
    if (((Get-Date) - $t0).TotalSeconds -gt 300) { break }
}
$b = Snap; $tb = ThreadSnap
$wall = ((Get-Date) - $t0).TotalSeconds

$out = @()
$out += "# $Label mode=$Mode frames=$Frames wall=$([math]::Round($wall,2))"
foreach ($n in $names) { $out += ("CPU {0} {1:N2}" -f $n, ($b[$n] - $a[$n])) }
$out += '# per-thread CPU of the terminal (top 8), seconds'
$deltas = @()
foreach ($k in $tb.Keys) {
    $d = $tb[$k] - $(if ($ta.ContainsKey($k)) { $ta[$k] } else { 0 })
    if ($d -gt 0.01) { $deltas += [pscustomobject]@{ tid = $k; cpu = $d } }
}
foreach ($d in ($deltas | Sort-Object cpu -Descending | Select-Object -First 8)) {
    $out += ("THREAD {0} {1:N2}  ({2:N0}% of wall)" -f $d.tid, $d.cpu, (100 * $d.cpu / $wall))
}
$out += ("THREADS_BUSY " + $deltas.Count)
if (Test-Path "C:\doomfire\prof-$Label.err") { $out += (Get-Content "C:\doomfire\prof-$Label.err" -Raw).Trim() }
$out += 'DONE'
Set-Content -Encoding ascii "C:\doomfire\prof-$Label.txt" $out
$out | Write-Output
Stop-Process -Name TerminalApp, WindowsTerminal -Force -ErrorAction SilentlyContinue
