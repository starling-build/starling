#!/usr/bin/env bash
# Drive the Windows shell gate from here.
#
#   test/win/run-gate.sh                    # the usual box
#   STARLING_WIN_HOST=user@host test/win/run-gate.sh
#
# The gate itself is gate.ps1 and it has to run INSIDE the logged-in session:
# ssh lands in session 0, which has no desktop, and every window question
# would be answered about a desktop nobody is looking at. So this copies the
# script over, runs it as an interactive scheduled task, and waits for it.
#
# Exit code is the gate's: 0 if every check passed.
set -uo pipefail

HOST="${STARLING_WIN_HOST:-starling@192.168.68.60}"
REMOTE_DIR='C:\dist'
TASK="StarlingGate"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT_SECONDS="${STARLING_GATE_TIMEOUT:-300}"

say() { printf '%s\n' "$*"; }

# The runner. A scheduled task cannot capture output, so the script's stdout
# goes to a log and a sentinel file says when it is finished -- the same shape
# every driving script on this box uses.
runner_vbs=$(mktemp /tmp/starling-gate-runner.XXXXXX.vbs)
cat > "$runner_vbs" <<'VBS'
Set sh = CreateObject("WScript.Shell")
rc = sh.Run("cmd /c powershell -NoProfile -ExecutionPolicy Bypass -File C:\dist\gate.ps1 > C:\dist\gate.log 2>&1", 0, True)
Set fso = CreateObject("Scripting.FileSystemObject")
Set f = fso.CreateTextFile("C:\dist\gate.done")
f.WriteLine rc
f.Close
VBS

say "── copying the gate to $HOST"
scp -q "$HERE/gate.ps1" "$HOST:$REMOTE_DIR/gate.ps1" || { say "scp failed"; exit 2; }
scp -q "$runner_vbs" "$HOST:$REMOTE_DIR/gate-run.vbs" || { say "scp failed"; exit 2; }
rm -f "$runner_vbs"

ssh "$HOST" 'del C:\dist\gate.done C:\dist\gate.log C:\dist\gate-shot.png' >/dev/null 2>&1
ssh "$HOST" "schtasks /create /tn $TASK /ru starling /it /sc once /st 00:00 /tr \"wscript.exe C:\\dist\\gate-run.vbs\" /f" >/dev/null 2>&1 \
  || { say "could not register the task"; exit 2; }

say "── running (up to ${TIMEOUT_SECONDS}s)"
ssh "$HOST" "schtasks /run /tn $TASK" >/dev/null 2>&1 || { say "could not start the task"; exit 2; }

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if ssh "$HOST" 'if exist C:\dist\gate.done (echo YES) else (echo NO)' 2>/dev/null | grep -q YES; then
    break
  fi
  sleep 5
done

log=$(ssh "$HOST" 'type C:\dist\gate.log' 2>/dev/null | grep -v 'post-quantum\|store now\|may need to be upgraded')
if [ -z "$log" ]; then
  say "the gate produced no output -- is anyone logged in on that machine?"
  exit 2
fi
printf '%s\n' "$log"

# Every run leaves a downscaled screenshot; bring it back either way. On a
# pass it is the evidence, on a failure it is the diagnosis, and it is small.
if ssh "$HOST" 'if exist C:\dist\gate-shot.png (echo YES) else (echo NO)' 2>/dev/null | grep -q YES; then
  out="${TMPDIR:-/tmp}/starling-gate-shot.png"
  if scp -q "$HOST:C:/dist/gate-shot.png" "$out" 2>/dev/null; then
    say ""
    say "screenshot: $out"
  fi
fi

if printf '%s' "$log" | grep -q "GATE PASSED"; then
  exit 0
fi
exit 1
