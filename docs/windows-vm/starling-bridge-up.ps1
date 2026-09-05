# starling-bridge-up.ps1 — build (if needed) and start the seamless helper in
# the INTERACTIVE session of a Windows guest. Run through the guest agent:
#
#     winput.py -d win11-dbus starling-bridge.cs C:\starling-bridge.cs
#     winrun.py -d win11-dbus --file starling-bridge-up.ps1
#
# Both halves matter. guest-exec lands in session 0, which has no windows and
# no desktop, so the helper cannot simply be started from here — it has to go
# through a scheduled task marked interactive-only (/it), which runs it as the
# logged-on user in session 1. And csc.exe is on every Windows install, so the
# guest compiles the helper itself: nothing to sign, nothing to copy but the
# source. Idempotent: an exe newer than its source is not rebuilt, and a
# helper already running is left alone (the port takes one client).

$src = "C:\starling-bridge.cs"
$exe = "C:\starling-bridge.exe"
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

if (!(Test-Path $src)) { "no $src — copy it in with winput.py first"; exit 1 }
if (!(Test-Path $csc)) { "no csc.exe at $csc"; exit 1 }

$build = !(Test-Path $exe) -or ((Get-Item $src).LastWriteTime -gt (Get-Item $exe).LastWriteTime)
if ($build) {
    Get-Process starling-bridge -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 300
    # UIA (semantic_tree/perform_action) uses System.Windows.Automation, which
    # lives in UIAutomationClient/UIAutomationTypes, and its BoundingRectangle
    # is a System.Windows.Rect from WindowsBase. These are in-box assemblies
    # but not in csc's search path, and their GAC folder names carry a
    # version hash — so resolve each to its real location rather than hardcode
    # a path that differs across Windows builds.
    $refs = @("System.Drawing.dll")
    foreach ($n in @("UIAutomationClient","UIAutomationTypes","WindowsBase")) {
        $a = [System.Reflection.Assembly]::LoadWithPartialName($n)
        if ($a -eq $null) { "MISSING assembly $n"; exit 1 }
        $refs += $a.Location
    }
    $rargs = $refs | ForEach-Object { "/r:$_" }
    $out = & $csc /nologo /target:winexe @rargs /out:$exe $src 2>&1
    if (!(Test-Path $exe) -or ($LASTEXITCODE -ne 0)) { "BUILD FAILED"; $out | Select-Object -Last 8; exit 1 }
    "built " + (Get-Item $exe).Length + " bytes"
} else {
    "exe is current"
}

if (Get-Process starling-bridge -ErrorAction SilentlyContinue) {
    "helper already running"
    exit 0
}

# /it: only while that user is logged on, no password. /ru is the autologon
# account. /sc once /st 00:00 is the shape of a task that is only ever /run.
schtasks /create /tn StarlingBridge /tr $exe /sc once /st 00:00 /ru Administrator /it /f | Out-Null
schtasks /run /tn StarlingBridge | Out-Null
Start-Sleep 2
if (Get-Process starling-bridge -ErrorAction SilentlyContinue) { "helper started in the interactive session" }
else { "helper did not start (is anyone logged on?)"; exit 1 }
