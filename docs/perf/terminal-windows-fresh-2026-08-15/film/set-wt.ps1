# Pin Windows Terminal's cell metrics for the race.
#
# Round-tripping WT's own settings.json does not work: it is JSONC and
# ConvertTo-Json throws PSInvalidCastException on it. So write a minimal
# settings file — WT fills in every default we do not name — after keeping a
# copy of the original beside it.
#
# Values come from files, not parameters: schtasks mangles quoted arguments
# (a padding of "19,0,19,0" arrived as `19,0,19,0\ /f`).
$FontSize = [double](Get-Content C:\film\WTFONT -EA SilentlyContinue)
$Padding  = (Get-Content C:\film\WTPAD -EA SilentlyContinue)
if ($FontSize -le 0) { $FontSize = 12 }
if (-not $Padding) { $Padding = "0" }

$dir = "C:\Users\Administrator\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
$p   = Join-Path $dir 'settings.json'
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
"fontSize=$FontSize padding=$Padding written" | Set-Content -Encoding ascii C:\film\wtset.txt
