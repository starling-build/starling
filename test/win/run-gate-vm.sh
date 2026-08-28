#!/usr/bin/env bash
# Run the Windows shell gate against a libvirt VM, on the INSTALLED package.
#
#   test/win/run-gate-vm.sh                       # domain win11-gate
#   test/win/run-gate-vm.sh -d win11-gate --install dist/StarlingSetup-0.1.0.exe
#
# This is run-gate.sh's counterpart for the honest environment: a machine that
# never built anything. The dev box has the toolchain, an engine checkout and a
# staged tree on it, so it cannot tell you whether the PACKAGE works -- and the
# 2026-08-28 run proved that is not theoretical. Three checks passed on the 4K
# dev box and failed here, none of them for a reason the product was guilty of:
# a dock strip threshold written as a constant instead of scaling with the
# display, a context menu that FLIPS upward on a short screen so it is not
# under the cursor, and a Calculator graded blank because our own window was
# on top of it. All three are fixed; this script is what keeps them fixed.
#
# It differs from run-gate.sh in how it reaches the guest. There is no SSH: the
# QEMU guest agent runs commands as SYSTEM in session 0, which has no desktop,
# so the gate itself goes in through an interactive scheduled task exactly as
# it does over SSH -- and the files go in over HTTP from the host, which is
# 192.168.122.1 on libvirt's default network.
set -uo pipefail

DOMAIN="win11-gate"
INSTALL=""
PORT="${STARLING_VM_HTTP_PORT:-8899}"
HOSTIP="${STARLING_VM_HOST_IP:-192.168.122.1}"
TIMEOUT_SECONDS="${STARLING_GATE_TIMEOUT:-900}"

while [ $# -gt 0 ]; do
  case "$1" in
    -d|--domain) DOMAIN="$2"; shift 2 ;;
    --install)   INSTALL="$2"; shift 2 ;;
    *) echo "unknown argument: $1"; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
WINRUN="$REPO/docs/windows-vm/winrun.py"
say() { printf '%s\n' "$*"; }
guest() { python3 "$WINRUN" -d "$DOMAIN" "$1" 2>&1 | grep -v 'CLIXML\|^<Objs'; }

virsh domstate "$DOMAIN" 2>/dev/null | grep -q running || {
  say "── starting $DOMAIN"
  virsh start "$DOMAIN" >/dev/null 2>&1
  # The agent is the readiness signal; a booted Windows answers in ~90s.
  for _ in $(seq 1 30); do
    sleep 10
    guest '"up"' | grep -q up && break
  done
}
guest '"up"' | grep -q up || { say "the guest agent never answered -- is $DOMAIN booted?"; exit 2; }

# Serve the gate (and optionally the installer) to the guest.
SERVE="$(mktemp -d)"
trap 'rm -rf "$SERVE"; [ -n "${HTTP_PID:-}" ] && kill "$HTTP_PID" 2>/dev/null' EXIT
cp "$HERE/gate.ps1" "$SERVE/"
[ -n "$INSTALL" ] && cp "$INSTALL" "$SERVE/setup.exe"
( cd "$SERVE" && python3 -m http.server "$PORT" --bind "$HOSTIP" >/dev/null 2>&1 ) &
HTTP_PID=$!
sleep 2

if [ -n "$INSTALL" ]; then
  say "── installing $(basename "$INSTALL") in the guest"
  # /Q:A is the quiet install; it must run in the INTERACTIVE session or the
  # per-user install lands in SYSTEM's profile and registers a shell nobody
  # logs in as (docs/WINDOWS-INSTALL.md).
  guest "New-Item -ItemType Directory -Force -Path C:\\dist | Out-Null
Invoke-WebRequest -Uri http://$HOSTIP:$PORT/setup.exe -OutFile C:\\dist\\setup.exe -UseBasicParsing
schtasks /create /tn StarInstall /ru administrator /it /rl HIGHEST /sc once /st 00:00 /tr 'C:\\dist\\setup.exe /Q:A' /f | Out-Null
schtasks /run /tn StarInstall | Out-Null
Start-Sleep 45
'installed: ' + (Test-Path \"\$env:LOCALAPPDATA\\Programs\\Starling\\WinShellBar.exe\")" | tail -1
  say "── rebooting into the installed shell"
  virsh reboot "$DOMAIN" >/dev/null 2>&1
  sleep 60
  for _ in $(seq 1 30); do
    sleep 10
    guest '"up"' | grep -q up && break
  done
  sleep 20
fi

say "── running the gate (up to ${TIMEOUT_SECONDS}s)"
guest "Invoke-WebRequest -Uri http://$HOSTIP:$PORT/gate.ps1 -OutFile C:\\dist\\gate.ps1 -UseBasicParsing
Set-Content C:\\dist\\gate-run.vbs @'
Set sh = CreateObject(\"WScript.Shell\")
rc = sh.Run(\"cmd /c powershell -NoProfile -ExecutionPolicy Bypass -File C:\\dist\\gate.ps1 > C:\\dist\\gate.log 2>&1\", 0, True)
Set fso = CreateObject(\"Scripting.FileSystemObject\")
Set f = fso.CreateTextFile(\"C:\\dist\\gate.done\")
f.WriteLine rc
f.Close
'@
Remove-Item C:\\dist\\gate.done, C:\\dist\\gate.log -Force -EA SilentlyContinue
schtasks /create /tn StarGate /ru administrator /it /rl HIGHEST /sc once /st 00:00 /tr 'wscript.exe C:\\dist\\gate-run.vbs' /f | Out-Null
schtasks /run /tn StarGate | Out-Null
'started'" >/dev/null

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  guest 'if (Test-Path C:\dist\gate.done) { "DONE" } else { "waiting" }' | grep -q DONE && break
  sleep 20
done

log=$(guest 'Get-Content C:\dist\gate.log')
if [ -z "$log" ]; then
  say "the gate produced no output -- is anyone logged on in the guest?"
  exit 2
fi
printf '%s\n' "$log"
printf '%s' "$log" | grep -q "GATE PASSED" && exit 0
exit 1
