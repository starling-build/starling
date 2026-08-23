#!/usr/bin/env python3
"""Screenshot a libvirt Windows guest from the host, no RDP session needed.

    wshot.py out.png [-d DOMAIN]              # console framebuffer via virsh
    wshot.py out.png [-d DOMAIN] --session    # inside the interactive session

Two modes because they fail in opposite places:

- Default (virsh): one round trip, ~2s. But it shoots the *console* display,
  so it goes black when the guest idles (a keystroke is sent first to wake it)
  and shows the lock screen whenever an RDP connection holds the session --
  Windows allows one interactive session, and RDP steals it from the console.

- --session: runs CopyFromScreen inside the guest as a scheduled task marked
  interactive (/it), so it lands in whatever session is on the real desktop --
  console or RDP alike -- at that session's true resolution and DPI
  (SetProcessDpiAwarenessContext(-4) first, or a scaled desktop yields a
  quarter-frame). The PNG comes back base64 over the agent channel; a 4K
  desktop is ~2-4 MB, well under qemu-ga's output cap. Slower (~10s), never
  blank.
"""
import argparse, base64, subprocess, sys, tempfile, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from winrun import run

SESSION_PS = r'''
$ErrorActionPreference='Stop'
$dir='C:\st'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
$cap = @'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$sig='[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);'
$u=Add-Type -MemberDefinition $sig -Name U -Namespace W -PassThru
[void]$u::SetProcessDpiAwarenessContext([IntPtr](-4))
$b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp=New-Object System.Drawing.Bitmap $b.Width,$b.Height
$g=[System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location,[System.Drawing.Point]::Empty,$b.Size)
$bmp.Save("C:\st\wshot.png",[System.Drawing.Imaging.ImageFormat]::Png)
'@
Set-Content -Path "$dir\wshot-cap.ps1" -Value $cap
# the task must not photograph itself: a console app in an interactive task
# opens a visible window, which lands in the capture. wscript's Run with
# window style 0 launches it with no window at all.
$vbs = 'CreateObject("Wscript.Shell").Run "cmd /c powershell -NoProfile -ExecutionPolicy Bypass -File C:\st\wshot-cap.ps1 > C:\st\wshot-cap.log 2>&1", 0, True'
Set-Content -Path "$dir\wshot-cap.vbs" -Value $vbs
Remove-Item "$dir\wshot.png" -Force -ErrorAction SilentlyContinue
# native stderr must never enter PowerShell's stream machinery: under
# ErrorActionPreference=Stop a redirected stderr line becomes a terminating
# NativeCommandError (the delete of a task that does not exist yet, e.g.).
cmd /c "schtasks /delete /tn WShot /f >nul 2>&1"
# /tr quoting: backtick-escaped quotes around the whole action, caret-escaped
# redirects inside it, so the capture script's own errors land in a log.
# (\" from a PS double-quoted string reaches cmd as literal \" and mangles
# the action -- the task then runs nothing, silently.)
$tr = "wscript //B $dir\wshot-cap.vbs"
cmd /c "schtasks /create /tn WShot /ru $env:GUEST_USER /it /rl HIGHEST /sc once /st 00:00 /tr `"$tr`" /f >nul 2>&1"
cmd /c "schtasks /run /tn WShot >nul 2>&1"
$deadline=(Get-Date).AddSeconds(25)
while ((Get-Date) -lt $deadline -and -not (Test-Path "$dir\wshot.png")) { Start-Sleep -Milliseconds 400 }
Start-Sleep -Milliseconds 400   # let the Save finish
cmd /c "schtasks /delete /tn WShot /f >nul 2>&1"
if (-not (Test-Path "$dir\wshot.png")) { Write-Error "capture never appeared"; exit 1 }
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$dir\wshot.png"))
'''

def main():
    p = argparse.ArgumentParser()
    p.add_argument("out")
    p.add_argument("-d", "--domain", default="win11-gpu")
    p.add_argument("--session", action="store_true",
                   help="capture inside the interactive session (survives RDP console lock)")
    p.add_argument("--user", default="Administrator",
                   help="--session: the logged-in user the task runs as")
    a = p.parse_args()

    if a.session:
        ps = SESSION_PS.replace("$env:GUEST_USER", a.user)
        code, out, err = run(a.domain, ps, timeout=60)
        if code != 0:
            sys.stderr.write(err or out)
            sys.exit(code)
        data = base64.b64decode(out.strip().split()[-1])
        with open(a.out, "wb") as f:
            f.write(data)
    else:
        # wake the display, then shoot; convert ppm -> requested format
        subprocess.run(["sudo", "-n", "virsh", "send-key", a.domain, "KEY_LEFTCTRL"],
                       capture_output=True)
        import time; time.sleep(1.5)
        with tempfile.NamedTemporaryFile(suffix=".ppm", delete=False) as t:
            tmp = t.name
        try:
            r = subprocess.run(["sudo", "-n", "virsh", "screenshot", a.domain, tmp],
                               capture_output=True, text=True)
            if r.returncode != 0:
                sys.stderr.write(r.stderr); sys.exit(1)
            from PIL import Image
            Image.open(tmp).save(a.out)
        finally:
            os.unlink(tmp)
    print(a.out)

if __name__ == "__main__":
    main()
