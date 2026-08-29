#!/usr/bin/env bash
# Photograph real Windows 11 chrome, to tune the Linux desktop's Fluent style
# against something other than memory.
#
#   test/win/capture-reference.sh [outdir]
#   STARLING_WIN_HOST=user@host test/win/capture-reference.sh
#
# Same shape as run-gate.sh and for the same reason: ssh lands in session 0,
# which has no desktop, so the capture runs as an interactive scheduled task
# in the logged-in session and this waits for it.
#
# It only looks — Start and Quick Settings are opened and closed again, and no
# setting on that machine is changed. The point is a picture of Windows as it
# ships.
set -uo pipefail

HOST="${STARLING_WIN_HOST:-starling@192.168.68.56}"
REMOTE_DIR='C:\dist'
TASK="StarlingWinShot"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${1:-$HOME/tmp/win11-ref}"
TIMEOUT_SECONDS="${STARLING_REF_TIMEOUT:-180}"

say() { printf '%s\n' "$*"; }
# ssh on this box prints a post-quantum advisory on every connection.
quiet() { grep -v 'post-quantum\|store now\|may need to be upgraded' || true; }

runner_vbs=$(mktemp "${TMPDIR:-/tmp}/starling-ref-runner.XXXXXX.vbs")
cat > "$runner_vbs" <<'VBS'
Set sh = CreateObject("WScript.Shell")
rc = sh.Run("cmd /c powershell -NoProfile -ExecutionPolicy Bypass -File C:\dist\capture-winshell.ps1 > C:\dist\ref.log 2>&1", 0, True)
Set fso = CreateObject("Scripting.FileSystemObject")
Set f = fso.CreateTextFile("C:\dist\ref.done")
f.WriteLine rc
f.Close
VBS

say "── copying the capture script to $HOST"
scp -q "$HERE/capture-winshell.ps1" "$HOST:$REMOTE_DIR/capture-winshell.ps1" \
  || { say "scp failed"; exit 2; }
scp -q "$runner_vbs" "$HOST:$REMOTE_DIR/ref-run.vbs" || { say "scp failed"; exit 2; }
rm -f "$runner_vbs"

ssh "$HOST" 'del /q C:\dist\ref.done C:\dist\ref.log 2>nul & rmdir /s /q C:\dist\ref 2>nul' >/dev/null 2>&1
ssh "$HOST" "schtasks /create /tn $TASK /ru starling /it /sc once /st 00:00 /tr \"wscript.exe C:\\dist\\ref-run.vbs\" /f" >/dev/null 2>&1 \
  || { say "could not register the task"; exit 2; }

say "── capturing (up to ${TIMEOUT_SECONDS}s)"
ssh "$HOST" "schtasks /run /tn $TASK" >/dev/null 2>&1 || { say "could not start the task"; exit 2; }

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if ssh "$HOST" 'if exist C:\dist\ref.done (echo YES) else (echo NO)' 2>/dev/null | quiet | grep -q YES; then
    break
  fi
  sleep 4
done

log=$(ssh "$HOST" 'type C:\dist\ref.log' 2>/dev/null | quiet)
if [ -z "$log" ]; then
  say "no output — is anyone logged in on that machine?"
  exit 2
fi
printf '%s\n' "$log"

mkdir -p "$OUT"
if scp -q "$HOST:C:/dist/ref/*" "$OUT/" 2>/dev/null; then
  say "── captures in $OUT"
  ls -1 "$OUT"
else
  say "nothing came back from C:\\dist\\ref"
  exit 2
fi

ssh "$HOST" "schtasks /delete /tn $TASK /f" >/dev/null 2>&1
