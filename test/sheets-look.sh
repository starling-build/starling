#!/bin/bash
# Look at Sheets without touching the screen: open a file in a window that
# stays behind everything and never takes focus (STARLING_WINDOW_BACKGROUND),
# photograph that window by its id, and quit. Safe while another session or
# a person is using the machine — no clicks, no keys, no activation.
#
#   test/sheets-look.sh file.xlsx out.png [seconds]
#
# OFFICE_APP picks the binary (default apps/OfficeApp/.build/debug/OfficeApp).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${OFFICE_APP:-$ROOT/apps/OfficeApp/.build/debug/OfficeApp}"
IN="$1"; OUT="$2"; WAIT="${3:-5}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true' EXIT
cat > "$TMP/winid.swift" <<'SWIFT'
import CoreGraphics
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
    if let b = w[kCGWindowBounds as String] as? [String: Double], (b["Width"] ?? 0) > 200 {
        print(w[kCGWindowNumber as String] as! Int); break
    }
}
SWIFT
swiftc -O -o "$TMP/winid" "$TMP/winid.swift" 2>/dev/null
STARLING_WINDOW_BACKGROUND=1 "$APP" "$IN" >/dev/null 2>&1 &
PID=$!
sleep "$WAIT"
ID="$("$TMP/winid" "$PID")"
[ -n "$ID" ] || { echo "no window for pid $PID" >&2; exit 1; }
screencapture -x -o -l "$ID" "$OUT"
echo "$OUT"
