# Wait for the workstation to be unlocked, then run the short round.
#
# The 08-16 full round was measured with the session locked and nobody knew
# until afterwards, because nothing in the harness looked. This waits for
# LogonUI to go away -- the only reliable in-session signal that the secure
# desktop is gone -- and only then starts measuring. It gives up rather than
# waiting forever, so an unattended box does not leave a process parked for a
# day.
param(
    [int]$MaxWaitMinutes = 180,
    [string]$BenchDir = 'C:\bench'
)
$ErrorActionPreference = 'Continue'
$log = Join-Path $BenchDir 'run-when-unlocked.log'
function Log($m) { Add-Content -Encoding ascii $log ("{0}Z {1}" -f ([DateTime]::UtcNow.ToString('HH:mm:ss')), $m) }

Log "waiting for unlock (max $MaxWaitMinutes min)"
$deadline = (Get-Date).AddMinutes($MaxWaitMinutes)
while ((Get-Date) -lt $deadline) {
    if (-not (Get-Process LogonUI -EA SilentlyContinue)) {
        Log 'UNLOCKED -- settling 20 s, then running the short round'
        # Let whatever the person did to unlock (and any shell redraw that
        # followed) finish before the first leg starts.
        Start-Sleep -Seconds 20
        & (Join-Path $PSScriptRoot 'bench-long.ps1') -Short -BenchDir $BenchDir
        Log 'short round finished'
        exit 0
    }
    Start-Sleep -Seconds 10
}
Log 'GAVE UP -- still locked at deadline'
exit 1
