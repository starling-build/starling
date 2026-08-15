# One narrow-grid (43x76) profiled cat leg; config read from C:\prof\CONFIG:
#   ours | ours-nr (repaints suppressed) | wt
param([string]$Out = 'C:\prof')
$ErrorActionPreference = 'Continue'
$cfg = (Get-Content "$Out\CONFIG" -EA SilentlyContinue)
if (-not $cfg) { $cfg = 'ours' }
Remove-Item "$Out\go", "$Out\done", "$Out\res", "$Out\err", "$Out\LEGDONE" -Force -EA SilentlyContinue
$preWT = @(Get-Process WindowsTerminal -EA SilentlyContinue | ForEach-Object { $_.Id })
Get-Process TerminalApp -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
foreach ($p in @(Get-Process WindowsTerminal -EA SilentlyContinue)) {
    if ($preWT -notcontains $p.Id) { Stop-Process -Id $p.Id -Force -EA SilentlyContinue }
}
$stale = @(Get-CimInstance Win32_Process -Filter 'Name="powershell.exe"' -EA SilentlyContinue |
           Where-Object { $_.CommandLine -like '*prof-inner*' })
foreach ($sp in $stale) { Stop-Process -Id $sp.ProcessId -Force -EA SilentlyContinue }
Start-Sleep -Seconds 2
$runner = "powershell -NoProfile -ExecutionPolicy Bypass -File $Out\prof-inner.ps1 -Reps 3"
if ($cfg -eq 'wt') {
    Start-Process 'wt.exe' -ArgumentList "--window new --size 76,43 $runner"
} else {
    $env:STARLING_WINDOW_W = '632'
    $env:STARLING_WINDOW_H = '762'
    if ($cfg -eq 'ours-nr') { $env:STARLING_BENCH_NOREPAINT = '1' }
    else { Remove-Item Env:\STARLING_BENCH_NOREPAINT -EA SilentlyContinue }
    $env:STARLING_DEV_SHELL = $runner
    Start-Process 'C:\dist\TerminalApp\TerminalApp.exe'
    Remove-Item Env:\STARLING_BENCH_NOREPAINT -EA SilentlyContinue
}
for ($i = 0; $i -lt 400; $i++) { Start-Sleep -Seconds 1; if (Test-Path "$Out\done") { break } }
Copy-Item "$Out\res" "$Out\res-$cfg.txt" -Force -EA SilentlyContinue
Copy-Item "$Out\go" "$Out\grid-$cfg.txt" -Force -EA SilentlyContinue
Get-Process TerminalApp -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
foreach ($p in @(Get-Process WindowsTerminal -EA SilentlyContinue)) {
    if ($preWT -notcontains $p.Id) { Stop-Process -Id $p.Id -Force -EA SilentlyContinue }
}
[IO.File]::WriteAllText("$Out\LEGDONE", $cfg)
