#!/bin/bash
# Play an input script into Sheets (apps/OfficeApp/Sources/OfficeApp/
# ScriptedInput.swift) in a window that never takes focus, and collect
# its pictures. Touches no other app: the events go straight into the
# framework, and the window stays behind everything.
#
#   test/sheets-script.sh test/scripts/sheets-editing.txt [OUTDIR]
#
# OFFICE_APP picks the binary. Prints OUTDIR; read the pictures.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${OFFICE_APP:-$ROOT/apps/OfficeApp/.build/debug/OfficeApp}"
SCRIPT="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUT="${2:-$(mktemp -d)}"
mkdir -p "$OUT"
OFFICE_SCRIPT="$SCRIPT" OFFICE_SCRIPT_OUT="$OUT" STARLING_WINDOW_BACKGROUND=1 "$APP" --sheets >"$OUT/log.txt" 2>&1 &
PID=$!
for _ in $(seq 1 120); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
kill "$PID" 2>/dev/null || true
echo "$OUT"
