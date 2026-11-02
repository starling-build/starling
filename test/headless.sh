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
cleanup() { [ -n "$pid" ] && kill "$pid" 2>/dev/null; sleep 0.3; rm -rf "$RT"; }
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
echo "all headless checks passed"
