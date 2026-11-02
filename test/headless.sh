#!/usr/bin/env bash
# Headless desktop smoke test — no display, no seat, no root, no uinput.
#
#   test/headless.sh [STAGE_DIR]        (default: ./.stage — run build/stage.sh first)
#
# Starts `DesktopShellApp --rdp` with the RDP listener off, then drives it
# through the operator socket (docs/plans/headless-desktop.md) and checks:
#   1. the socket is a unix socket, mode 0600, owned by us        (security)
#   2. a screenshot is a real PNG of the negotiated size and is not blank
#   3. an app launches and shows up in the window list
#   4. typed text reaches it and changes the pixels                (input path)
# Skips (exit 0, says why) when the staged tree or the apps it needs are missing.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ST="${1:-${STARLING_STAGE:-$REPO/.stage}}"
[ -x "$ST/lib/DesktopShellApp" ] || { echo "SKIPPED: no staged tree at $ST (build/stage.sh)"; exit 0; }
[ -x "$ST/lib/apps/TerminalApp" ] || [ -e "$ST/lib/apps/TerminalApp" ] || { echo "SKIPPED: TerminalApp not staged"; exit 0; }

RT="$(mktemp -d "${TMPDIR:-/tmp}/starling-headless.XXXXXX")"
chmod 700 "$RT"
LOG="$RT/shell.log"
DRIVE="$REPO/build/headless-drive.py"
pid=""
# The multi-desktop tool must only ever see the test's own desktops.
export STARLING_STAGE="$ST" STARLING_HEADLESS_BASE="$RT/hd"
export REPO_BUILD="$REPO/build"
cleanup() { [ -n "$pid" ] && { python3 "$DRIVE" -s "$RT/starling-operator.sock" quit >/dev/null 2>&1; sleep 0.5; kill "$pid" 2>/dev/null; }; python3 "$REPO/build/headless-desktops.py" stop-all >/dev/null 2>&1; sleep 0.3; rm -rf "$RT"; }
trap cleanup EXIT
fail() { echo "FAIL: $*"; echo "--- shell log tail:"; tail -15 "$LOG"; exit 1; }

( cd "$ST/lib" && exec env -u DISPLAY -u WAYLAND_DISPLAY \
    LD_LIBRARY_PATH="$ST/lib" XDG_RUNTIME_DIR="$RT" \
    FLUTTER_ENGINE_OUT="$ST/share" STARLING_DATA_DIR="$ST/share" \
    FLUTTER_APPS_DIR="$ST/lib/apps" STARLING_CHILD_HOST_GL=1 \
    STARLING_APP_RUN="$ST/bin/app-run" STARLING_RDP_SIZE=1280x720 \
    STARLING_HEADLESS_NO_RDP=1 LP_NUM_THREADS=2 \
    ./DesktopShellApp --rdp ) >"$LOG" 2>&1 &
pid=$!

SOCK="$RT/starling-operator.sock"
for _ in $(seq 100); do [ -S "$SOCK" ] && break; sleep 0.2; done
[ -S "$SOCK" ] || fail "operator socket never appeared"

# 1. permissions: a socket, 0600, ours.
[ "$(stat -c %a "$SOCK")" = 600 ] || fail "socket mode is $(stat -c %a "$SOCK"), want 600"
[ "$(stat -c %u "$SOCK")" = "$(id -u)" ] || fail "socket owner is not us"
echo "  ok    operator socket is 0600 and ours"

d() { python3 "$DRIVE" -s "$SOCK" "$@"; }

# 2. screenshot
d "shot $RT/a.png" >/dev/null || fail "shot failed"
python3 - "$RT/a.png" <<'EOF' || fail "screenshot is not a plausible 1280x720 PNG"
import struct, sys, zlib
b = open(sys.argv[1], "rb").read()
assert b[:8] == b"\x89PNG\r\n\x1a\n", "bad signature"
w, h = struct.unpack(">II", b[16:24])
assert (w, h) == (1280, 720), (w, h)
# IDAT inflates to a full frame, and the frame is not one flat colour
i, idat = 8, b""
while i < len(b):
    n, t = struct.unpack(">I4s", b[i:i+8])
    if t == b"IDAT": idat += b[i+8:i+8+n]
    i += 12 + n
raw = zlib.decompress(idat)
assert len(raw) == (w*4+1)*h, len(raw)
assert len(set(raw[1::997])) > 16, "frame looks blank"
EOF
echo "  ok    screenshot: valid 1280x720 PNG with content"

# 3. launch + window list
d "launch terminal" >/dev/null || fail "launch failed"
for _ in $(seq 40); do
    d windows 2>/dev/null | grep -q '"app": "terminal"' && break; sleep 0.5
done
d windows | grep -q '"app": "terminal"' || fail "terminal window never appeared"
echo "  ok    launch: terminal is in the window list"

# 4. typing changes the pixels
sleep 3
d "shot $RT/b.png" >/dev/null || fail "shot b failed"
d "type echo headless-ok" "key enter" "sleep 2" "shot $RT/c.png" >/dev/null || fail "typing failed"
cmp -s "$RT/b.png" "$RT/c.png" && fail "typing changed nothing on screen"
echo "  ok    typed text reaches the terminal and repaints it"

# 5. window management: move, resize, minimize, focus, close, wait-for-gone
d "winmove terminal 200 150" "resize terminal 640 420" >/dev/null || fail "winmove/resize failed"
d windows | python3 -c '
import json, sys
w = [x for x in json.load(sys.stdin) if x["app"] == "terminal"][0]
x, y, ww, hh = w["rect"]
assert abs(x - 200) < 2 and abs(y - 150) < 2, w["rect"]
assert abs(ww - 640) < 2, w["rect"]
' || fail "window did not move/resize to the requested rect"
echo "  ok    winmove and resize take effect"
d "minimize terminal" >/dev/null || fail "minimize failed"
winflag() { d windows | python3 -c 'import json,sys; print(str([w for w in json.load(sys.stdin) if w["app"]=="terminal"][0][sys.argv[1]]).lower())' "$1"; }
[ "$(winflag minimized)" = true ] || fail "window not minimised"
d "focus terminal" >/dev/null || fail "focus failed"
[ "$(winflag minimized)" = false ] || fail "focus did not restore"
echo "  ok    minimize and focus"
d "close terminal" "waitwin terminal gone 5" >/dev/null || fail "close / wait-for-gone failed"
d windows | grep -q '"app": "terminal"' && fail "terminal still listed after close"
echo "  ok    close, and wait-for-gone returns"
# 6. clipboard round trip (needs wl-clipboard; skipped, with the reason, without)
if [ -x /usr/bin/wl-copy ] && [ -x /usr/bin/wl-paste ]; then
    d "clip headless-clip-ok" >/dev/null || fail "clipboard set failed"
    [ "$(d clip)" = "headless-clip-ok" ] || fail "clipboard did not read back what was set"
    echo "  ok    clipboard round trip"
else
    echo "  skip  clipboard round trip (apt install wl-clipboard)"
fi
# 7. events: a subscriber hears a window open and close without polling
python3 "$DRIVE" -s "$SOCK" "events 60" > "$RT/events.out" &
evpid=$!
for _ in $(seq 50); do grep -q subscribed "$RT/events.out" && break; sleep 0.2; done
grep -q subscribed "$RT/events.out" || fail "event subscription never acknowledged"
d "launch settings" >/dev/null || fail "launch settings failed"
d "waitwin settings open 15" "close settings" "waitwin settings gone 5" >/dev/null || fail "settings open/close failed"
sleep 1.5; kill "$evpid" 2>/dev/null; wait "$evpid" 2>/dev/null
grep -q '"event": "window_opened".*"app": "settings"\|"app": "settings".*"event": "window_opened"' "$RT/events.out" || { cat "$RT/events.out"; grep "watch:" "$LOG"; fail "no window_opened event for settings"; }
grep -q '"event": "window_closed".*"app": "settings"\|"app": "settings".*"event": "window_closed"' "$RT/events.out" || fail "no window_closed event for settings"
echo "  ok    events: window_opened and window_closed are pushed"
# 8. density: four desktops side by side, each driven, then stopped with nothing left over
HD="$REPO/build/headless-desktops.py"
python3 "$HD" start-n 4 --size 1280x720 >/dev/null || fail "could not start 4 desktops"
for n in 1 2 3 4; do
    s="$(python3 "$HD" socket d$n)"
    [ "$(stat -c %a "$s")" = 600 ] || fail "d$n socket is not 0600"
    [ "$(stat -c %a "$(dirname "$s")")" = 700 ] || fail "d$n runtime dir is not 0700"
    python3 "$DRIVE" -s "$s" "launch terminal" "waitwin terminal open 30" "sleep 2" "shot $RT/d$n.png" >/dev/null \
        || fail "could not drive d$n"
done
cmp -s "$RT/d1.png" "$RT/d2.png" && echo "  note  d1 and d2 look identical (same scene, expected)"
out="$(python3 "$HD" stop-all)"
echo "$out" | grep -q straggler && fail "stop left stragglers: $out"
python3 - "$RT/hd" <<'EOF2' || fail "processes survived stop-all"
import importlib, os, sys
sys.path.insert(0, os.path.join(os.environ["REPO_BUILD"]))
hd = importlib.import_module("headless-desktops")
left = [p for n in os.listdir(sys.argv[1]) for p in hd.members(os.path.join(sys.argv[1], n))]
assert not left, left
EOF2
echo "  ok    four desktops: each driven, stopped cleanly, nothing left behind"
echo "all headless checks passed"
