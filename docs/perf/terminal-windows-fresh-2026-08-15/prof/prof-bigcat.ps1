# Process-level profile of the 500 MB cats: who burns CPU, and who is idle.
#   prof-bigcat.ps1            ours, repaints on
#   prof-bigcat.ps1 -NoRepaint ours, repaints suppressed (parse-only)
#   prof-bigcat.ps1 -Wt        Windows Terminal
param([switch]$NoRepaint, [switch]$Wt, [int]$Reps = 2, [string]$Out = 'C:\prof')
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Path $Out -Force | Out-Null
Remove-Item "$Out\go", "$Out\done", "$Out\res", "$Out\timeline", "$Out\samples.csv", "$Out\err" -Force -EA SilentlyContinue
$slotKb = (Get-Content C:\prof\SLOTKB -EA SilentlyContinue)
$slots  = (Get-Content C:\prof\SLOTS  -EA SilentlyContinue)
# Absent knob files mean "let the build decide" — not "force 64", which
# silently re-measured the old default and looked like the fix had no effect.
$ringTag = if ($slotKb -or $slots) { "ring=$(if($slotKb){$slotKb}else{'def'})KBx$(if($slots){$slots}else{'def'})" } else { 'ring=build-default' }
$tag = if ($Wt) { 'wt' } elseif ($NoRepaint) { "ours-norepaint $ringTag" } else { "ours $ringTag" }
[IO.File]::WriteAllText("$Out\tag", $tag)

$preWT = @(Get-Process WindowsTerminal -EA SilentlyContinue | ForEach-Object { $_.Id })
Get-Process TerminalApp -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
foreach ($p in @(Get-Process WindowsTerminal -EA SilentlyContinue)) {
    if ($preWT -notcontains $p.Id) { Stop-Process -Id $p.Id -Force -EA SilentlyContinue }
}
$stale = @(Get-CimInstance Win32_Process -Filter 'Name="powershell.exe"' -EA SilentlyContinue |
           Where-Object { $_.CommandLine -like '*prof-inner*' })
foreach ($sp in $stale) { Stop-Process -Id $sp.ProcessId -Force -EA SilentlyContinue }
Start-Sleep -Seconds 2

$runner = "powershell -NoProfile -ExecutionPolicy Bypass -File C:\prof\prof-inner.ps1 -Reps $Reps"
if ($Wt) {
    Start-Process 'wt.exe' -ArgumentList "--window new --size 120,39 $runner"
} else {
    $env:STARLING_WINDOW_W = '976'
    $env:STARLING_WINDOW_H = '688'
    $env:STARLING_PTY_BYTES = '1'
    if ($slotKb) { $env:STARLING_TERM_SLOT_KB = $slotKb } else { Remove-Item Env:\STARLING_TERM_SLOT_KB -EA SilentlyContinue }
    if ($slots)  { $env:STARLING_TERM_SLOTS   = $slots }  else { Remove-Item Env:\STARLING_TERM_SLOTS -EA SilentlyContinue }
    if ($NoRepaint) { $env:STARLING_BENCH_NOREPAINT = '1' } else { Remove-Item Env:\STARLING_BENCH_NOREPAINT -EA SilentlyContinue }
    $env:STARLING_DEV_SHELL = $runner
    Start-Process 'C:\dist\TerminalApp\TerminalApp.exe' -RedirectStandardError "$Out\err"
}

# Wait for the inner runner to announce itself.
for ($i = 0; $i -lt 60; $i++) { Start-Sleep -Seconds 1; if (Test-Path "$Out\go") { break } }
if (-not (Test-Path "$Out\go")) { [IO.File]::WriteAllText("$Out\samples.csv", 'no go'); return }

# Track the terminal, its console hosts, and the writer.
$term = if ($Wt) { Get-Process WindowsTerminal -EA SilentlyContinue | Where-Object { $preWT -notcontains $_.Id } | Select-Object -First 1 }
        else { Get-Process TerminalApp -EA SilentlyContinue | Select-Object -First 1 }
$rows = New-Object System.Collections.Generic.List[string]
$rows.Add('t_ms,name,pid,cpu_s')
$sw = [Diagnostics.Stopwatch]::StartNew()
while (-not (Test-Path "$Out\done") -and $sw.Elapsed.TotalSeconds -lt 240) {
    $ids = @()
    if ($term) { $ids += $term.Id }
    foreach ($n in @('OpenConsole','conhost')) {
        foreach ($p in @(Get-Process $n -EA SilentlyContinue)) { $ids += $p.Id }
    }
    foreach ($p in @(Get-CimInstance Win32_Process -Filter 'Name="powershell.exe"' -EA SilentlyContinue |
                     Where-Object { $_.CommandLine -like '*prof-inner*' })) { $ids += [int]$p.ProcessId }
    foreach ($id in ($ids | Select-Object -Unique)) {
        $p = Get-Process -Id $id -EA SilentlyContinue
        if ($p) { $rows.Add(("{0:N0},{1},{2},{3:N4}" -f $sw.Elapsed.TotalMilliseconds, $p.ProcessName, $p.Id, $p.TotalProcessorTime.TotalSeconds)) }
    }
    Start-Sleep -Milliseconds 100
}
[IO.File]::WriteAllLines("$Out\samples.csv", $rows)
