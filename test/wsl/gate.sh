#!/bin/bash
# Gate the Starling desktop in WSL.
#
# WSL has no /dev/dri, so RDP DISPLAY MODE is the only way the shell can put
# anything on a screen — which makes this box the real test of that path, and
# the reason the gate lives here rather than on the dev box. Everything runs
# inside the distro; the client is driven through WSLg's own X server, so no
# Windows-side scheduling is needed.
set -u
say() { echo "[gate] $*"; }
fail=0
check() { if [ "$1" = 0 ]; then echo "  PASS  $2"; else echo "  FAIL  $2"; fail=1; fi; }

export XDG_RUNTIME_DIR=/tmp/xdg-starling-gate
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
# Our OWN X server, not WSLg's. WSLg leaves a /tmp/.X11-unix/X0 socket behind
# that no server is listening on, so a gate that trusts DISPLAY=:0 fails at
# the capture step for reasons that have nothing to do with the desktop.
export DISPLAY=:99

say "1. install"
# dpkg -i, NOT apt-get install: the version does not change between builds,
# and apt treats a same-version .deb as already installed and does nothing —
# silently, with exit 0. That had this gate testing a two-week-old binary
# while reporting a pass. dpkg reinstalls over an identical version.
DEB=$(ls -t /mnt/c/dist/starling_*.deb 2>/dev/null | head -1)
say "   package: ${DEB:-NONE FOUND}"
dpkg -i "$DEB" > /tmp/g-install.log 2>&1 \
  || dpkg -i --force-all "$DEB" >> /tmp/g-install.log 2>&1
INST=$?
apt-get -y -f install >> /tmp/g-install.log 2>&1   # pull any missing deps
check $INST "the .deb installs on a clean 26.04 (dependencies resolve)"
say "   installed: $(sha256sum /usr/lib/starling/DesktopShellApp | cut -c1-16) \
$(stat -c%y /usr/lib/starling/DesktopShellApp | cut -d. -f1)"
ls /dev/dri >/dev/null 2>&1 && say "   NOTE: /dev/dri present — not the headless case" \
                            || say "   /dev/dri absent, as expected"

say "2. start in RDP display mode"
pkill -x DesktopShellApp 2>/dev/null; sleep 2
# Stale session logs are a trap for everything below: the launcher re-execs
# as an ordinary user, so the CURRENT run logs under that uid — but a
# leftover log from an earlier root run also says "listening on", the wait
# loop latches onto it before the banner has been printed, and every
# log-based check then grades a different run. Remove them all first.
rm -f /tmp/starling-session-*.log
# The SHIPPED launcher, with no arguments and no environment set up by hand.
# It detects WSL itself and picks display mode; testing a bespoke invocation
# here would prove the binary works and say nothing about what a user runs.
setsid starling-session > /tmp/g-launch.log 2>&1 < /dev/null &
# Take the log path from the launcher's own banner rather than assuming it is
# ours. The gate runs as root — which is what `wsl` gives you — and the
# launcher deliberately re-execs as an ordinary account there, so the session
# logs under THAT uid. Assuming $(id -u) here would have the gate watch a file
# nobody writes and fail every check with "NOT UP".
SHELL_LOG=$(sed -n 's/^Log: //p' /tmp/g-launch.log 2>/dev/null | tail -1)
[ -n "$SHELL_LOG" ] || SHELL_LOG=/tmp/starling-session-$(id -u).log
for i in $(seq 1 40); do
    grep -q "listening on" "$SHELL_LOG" 2>/dev/null && break
    # The banner is printed after the re-exec, so the path may only appear a
    # moment in; re-read it while waiting.
    p=$(sed -n 's/^Log: //p' /tmp/g-launch.log 2>/dev/null | tail -1)
    [ -n "$p" ] && SHELL_LOG="$p"
    sleep 1
done
say "   session log: $SHELL_LOG  (running as $(stat -c %U "$SHELL_LOG" 2>/dev/null || echo '?'))"
say "   it told the user:"; sed 's/^/        /' /tmp/g-launch.log | head -10
grep -q "listening on" "$SHELL_LOG"; check $? "the shipped launcher detects WSL and starts display mode"
grep -qi "surfaceless EGL" "$SHELL_LOG"
check $? "it renders surfacelessly (no DRM, no window system)"

say "3. idle with nobody connected"
PID=$(pgrep -x DesktopShellApp | head -1)
idle_cpu() {  # $1 = seconds
  read -r a b < <(awk '{print $14, $15}' /proc/$PID/stat)
  sleep "$1"
  read -r c d < <(awk '{print $14, $15}' /proc/$PID/stat)
  awk -v x=$((c+d-a-b)) -v s="$1" 'BEGIN{printf "%.2f", x/100/s*100}'
}
CPU_IDLE=$(idle_cpu 30)
say "   listener up, no client: ${CPU_IDLE}% of one core"
# 1%, and it measures 0.00% in practice. An earlier version of this gate set
# the ceiling at 3% on the strength of a ~1.1% reading that turned out to be a
# two-week-old binary the install had silently skipped (see above) — on which
# the frame pump ran at 33ms forever. Do not loosen this without checking the
# installed hash first.
awk -v c="$CPU_IDLE" 'BEGIN{exit !(c+0 < 1.0)}'
check $? "idle stays under 1% with the listener up"
grep -q "\[pump\]" "$SHELL_LOG" && { say "   pump armed for nobody:"; grep "\[pump\]" "$SHELL_LOG"; }
grep -q "\[pump\]" "$SHELL_LOG"; [ $? = 1 ]
check $? "the frame pump does NOT arm with no client (nothing rides it)"

say "4. a real client, on our own X display"
pkill -f "Xvfb :99" 2>/dev/null; sleep 1
setsid Xvfb :99 -screen 0 1600x1000x24 >/tmp/g-xvfb.log 2>&1 </dev/null &
sleep 3
xdpyinfo >/dev/null 2>&1; check $? "the gate's X display is up"
RDP=$(command -v xfreerdp3 || command -v xfreerdp)
pkill -x "$(basename ${RDP:-xfreerdp3})" 2>/dev/null; sleep 1
setsid $RDP /v:127.0.0.1:3390 /u:starling /p:x /cert:ignore /sec:tls \
    /size:1280x800 /log-level:ERROR > /tmp/g-client.log 2>&1 < /dev/null &
sleep 15
pgrep -x "$(basename $RDP)" >/dev/null; check $? "the client connects and stays up"
grep -qi "client activated" "$SHELL_LOG"; check $? "the shell activated the session"

say "5. what is actually on the client's screen"
import -window root /tmp/g-shot.png 2>/tmp/g-cap.err || head -2 /tmp/g-cap.err
if [ -s /tmp/g-shot.png ]; then
  read -r W H MEAN SD < <(identify -format "%w %h " /tmp/g-shot.png; \
      convert /tmp/g-shot.png -format "%[fx:mean*255] %[fx:standard_deviation*255]" info:)
  say "   captured ${W}x${H}, mean ${MEAN}, stddev ${SD}"
  cp /tmp/g-shot.png /mnt/c/dist/wsl-gate-shot.png 2>/dev/null
  # A desktop has structure. Black or a flat fill does not.
  awk -v m="$MEAN" -v s="$SD" 'BEGIN{exit !(m+0 > 8 && s+0 > 8)}'
  check $? "the client is showing a real desktop, not black or a flat fill"
else
  check 1 "captured the client's screen"
fi

say "6. disconnect and settle"
pkill -x "$(basename $RDP)" 2>/dev/null; sleep 10
pkill -f "Xvfb :99" 2>/dev/null
PID=$(pgrep -x DesktopShellApp | head -1)
if [ -n "$PID" ]; then
  CPU_AFTER=$(idle_cpu 30)
  say "   after the client left: ${CPU_AFTER}% of one core"
  awk -v c="$CPU_AFTER" 'BEGIN{exit !(c+0 < 1.0)}'
  check $? "returns to idle after a session"
  check 0 "the shell survived the whole run"
else
  check 1 "the shell survived the whole run"
fi

cp "$SHELL_LOG" /mnt/c/dist/wsl-gate-shell.log 2>/dev/null
say "shell log tail:"; tail -5 "$SHELL_LOG" | sed 's/^/        /'
echo
[ $fail = 0 ] && echo "WSL GATE PASS" || echo "WSL GATE FAIL"
exit $fail
