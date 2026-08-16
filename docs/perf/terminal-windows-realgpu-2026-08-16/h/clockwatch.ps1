# Sample CPU clock while a leg runs, to tell throughput decay apart from
# thermal/power throttling.
#
#   clockwatch.ps1 -Out C:\bench\clock-wt.txt -Seconds 330
#
# '% Processor Performance' is the current clock as a percentage of nominal,
# so >100 is boost and a fall through the leg is the machine giving up clock,
# not the terminal getting slower. Sampled alongside package temperature
# where the driver exposes it.
#
# Why this exists: on this box the long legs came out 70% slower per
# repetition than the short ones for Windows Terminal and identical for ours,
# and WT burns ~2x the CPU. A laptop hitting its sustained power limit would
# produce exactly that, with no difference in either terminal's parser.
param(
    [Parameter(Mandatory = $true)][string]$Out,
    [int]$Seconds = 330,
    [int]$IntervalSeconds = 5
)
$ErrorActionPreference = 'Continue'
"# t_s  proc_perf_pct  cpu_pct  temp_c" | Out-File -Encoding ascii $Out
$sw = [System.Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $perf = try {
        (Get-Counter '\Processor Information(_Total)\% Processor Performance' -EA Stop).CounterSamples[0].CookedValue
    } catch { -1 }
    $cpu = try {
        (Get-Counter '\Processor(_Total)\% Processor Time' -EA Stop).CounterSamples[0].CookedValue
    } catch { -1 }
    $temp = try {
        $t = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -EA Stop |
             Select-Object -First 1 -ExpandProperty CurrentTemperature
        [math]::Round(($t / 10) - 273.15, 1)
    } catch { -1 }
    Add-Content -Encoding ascii $Out ("{0:N0} {1:N1} {2:N1} {3}" -f $sw.Elapsed.TotalSeconds, $perf, $cpu, $temp)
    Start-Sleep -Seconds $IntervalSeconds
}
