# Pin Windows Terminal Preview's cell metrics for the race.
#
# Two changes from ../terminal-windows-fresh-2026-08-15/film/set-wt.ps1: the
# package is WindowsTerminalPreview (this round's rival, for the process
# isolation reason in the report) and the user is the logged-in one rather
# than Administrator.
#
# Round-tripping WT's own settings.json does not work: it is JSONC and
# ConvertTo-Json throws PSInvalidCastException on it. So write a minimal
# settings file -- WT fills in every default we do not name -- after keeping a
# copy of the original beside it.
#
# fontSize 10 rather than the default 12 is chosen so WT's cell lands near
# ours (8 x 17.45 logical px at this box's 200% scale), which makes the two
# windows about the same size on screen at the same grid. The grid is what
# has to match for fairness; the pixel size is so the film is not visually
# lopsided.
param(
    [double]$FontSize = 10,
    [string]$Padding = "0"
)
$ErrorActionPreference = 'Stop'

$dir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState'
if (-not (Test-Path $dir)) { throw "set-wt: no Preview LocalState at $dir -- launch it once first" }
$p = Join-Path $dir 'settings.json'
if ((Test-Path $p) -and -not (Test-Path "$p.orig")) { Copy-Item $p "$p.orig" -Force }

$json = @"
{
    "`$help": "https://aka.ms/terminal-documentation",
    "`$schema": "https://aka.ms/terminal-profiles-schema",
    "defaultProfile": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
    "profiles": {
        "defaults": {
            "fontSize": $FontSize,
            "padding": "$Padding",
            "scrollbarState": "hidden",
            "antialiasingMode": "grayscale"
        },
        "list": [
            {
                "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
                "name": "Windows PowerShell",
                "commandline": "powershell.exe",
                "hidden": false
            }
        ]
    }
}
"@
Set-Content -Encoding utf8 $p $json
"fontSize=$FontSize padding=$Padding written to $p"
