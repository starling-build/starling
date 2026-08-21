#!/usr/bin/env python3
"""Click (or move) the pointer inside a libvirt Windows guest, from the host.

    wclick.py X Y [-d DOMAIN] [--double] [--right] [--move-only]

QEMU's HMP mouse_move/mouse_button is the obvious route and does not work
here: with a SPICE vdagent in the guest the agent owns absolute-pointer
routing and the monitor's synthetic events go nowhere (keys, by contrast,
inject fine). So the click is made INSIDE the guest -- SetCursorPos +
SendInput from a PowerShell running in the interactive session via the same
hidden scheduled-task pattern wshot.py uses. Physical pixels, session-DPI
aware (the injecting process is made DPI-aware first).
"""
import argparse, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from winrun import run

PS = r'''
$dir='C:\st'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
$cap = @'
$sig = @"
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint data, UIntPtr extra);
"@
$u = Add-Type -MemberDefinition $sig -Name U -Namespace W -PassThru
[void]$u::SetProcessDpiAwarenessContext([IntPtr](-4))
[void]$u::SetCursorPos(@X@, @Y@)
Start-Sleep -Milliseconds 120
@CLICKS@
Set-Content -Path C:\st\wclick.done -Value ok
'@
Set-Content -Path "$dir\wclick-run.ps1" -Value $cap
Remove-Item "$dir\wclick.done" -Force -ErrorAction SilentlyContinue
$vbs = 'CreateObject("Wscript.Shell").Run "cmd /c powershell -NoProfile -ExecutionPolicy Bypass -File C:\st\wclick-run.ps1 > C:\st\wclick.log 2>&1", 0, True'
Set-Content -Path "$dir\wclick.vbs" -Value $vbs
cmd /c "schtasks /delete /tn WClick /f >nul 2>&1"
cmd /c "schtasks /create /tn WClick /ru Administrator /it /rl HIGHEST /sc once /st 00:00 /tr `"wscript //B $dir\wclick.vbs`" /f >nul 2>&1"
cmd /c "schtasks /run /tn WClick >nul 2>&1"
$deadline=(Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline -and -not (Test-Path "$dir\wclick.done")) { Start-Sleep -Milliseconds 300 }
cmd /c "schtasks /delete /tn WClick /f >nul 2>&1"
if (Test-Path "$dir\wclick.done") { "clicked" } else { "TIMED OUT"; Get-Content "$dir\wclick.log" -EA SilentlyContinue }
'''

def main():
    p = argparse.ArgumentParser()
    p.add_argument("x", type=int); p.add_argument("y", type=int)
    p.add_argument("-d", "--domain", default="win11-gpu")
    p.add_argument("--double", action="store_true")
    p.add_argument("--right", action="store_true")
    p.add_argument("--move-only", action="store_true")
    a = p.parse_args()

    if a.move_only:
        clicks = ""
    else:
        down, up = ("0x0008", "0x0010") if a.right else ("0x0002", "0x0004")
        one = (f"$u::mouse_event({down},0,0,0,[UIntPtr]::Zero); "
               f"Start-Sleep -Milliseconds 60; "
               f"$u::mouse_event({up},0,0,0,[UIntPtr]::Zero)")
        clicks = one + ("; Start-Sleep -Milliseconds 120; " + one if a.double else "")
    ps = PS.replace("@X@", str(a.x)).replace("@Y@", str(a.y)).replace("@CLICKS@", clicks)
    code, out, err = run(a.domain, ps, timeout=40)
    print(out.strip() or err.strip())
    sys.exit(0 if "clicked" in out else 1)

if __name__ == "__main__":
    main()
