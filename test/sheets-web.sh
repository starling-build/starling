#!/bin/bash
# Sheets in the browser, end to end: serve the staged web build started
# with --sheets, open the karma fixture through the page's picker, type
# into a cell, save (a download), and read the download back natively.
# Needs a staged web build (build/web-app.sh OfficeApp --package
# apps/OfficeApp [--debug]) and a native OfficeApp for the read-back
# (OFFICE_APP, default apps/OfficeApp/.build/debug/OfficeApp).
#
#   test/sheets-web.sh [OUTDIR]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$ROOT/.stage-web-OfficeApp"
APP="${OFFICE_APP:-$ROOT/apps/OfficeApp/.build/debug/OfficeApp}"
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT/dl"
[ -f "$STAGE/index.html" ] || { echo "no staged web build at $STAGE" >&2; exit 1; }
# A copy of the stage, started as Sheets, on its own port.
rm -rf "$OUT/stage"; cp -R "$STAGE" "$OUT/stage"
sed -i '' 's|args: \[[^]]*\],|args: ["--sheets"],|' "$OUT/stage/index.html"
PORT=8139
pkill -f "web-serve.py $OUT/stage" 2>/dev/null || true
python3 "$ROOT/build/tools/web-serve.py" "$OUT/stage" $PORT >"$OUT/serve.log" 2>&1 &
SERVE=$!
trap 'kill $SERVE 2>/dev/null || true; pkill -f "remote-debugging-port=${DEVTOOLS:-9334}" 2>/dev/null || true' EXIT
sleep 2
FIX="$ROOT/apps/OfficeApp/Tests/OfficeAppTests/Fixtures/karma_performance.xlsx"
URL="http://127.0.0.1:$PORT/" PORT="${DEVTOOLS:-9334}" W=1400 H=900 node "$ROOT/build/tools/web-drive.mjs" \
  wait 15000 shot "$OUT/01-blank.png" \
  chord ctrl o wait 1500 setfile "$FIX" wait 12000 shot "$OUT/02-opened.png" \
  click 328 330 type 42 press Enter wait 500 \
  downloads "$OUT/dl" chord ctrl s wait 6000 shot "$OUT/03-saved.png" >"$OUT/drive.log" 2>&1 || true
DL="$OUT/dl/karma_performance.xlsx"
if [ ! -s "$DL" ]; then echo "✘ no download landed (see $OUT/drive.log)"; exit 1; fi
# Reads back natively, with the edit in it.
"$APP" --xlsx-roundtrip "$DL" "$OUT/readback.xlsx" >"$OUT/readback.log" 2>&1 || { echo "✘ the download does not read back"; cat "$OUT/readback.log"; exit 1; }
if unzip -p "$DL" xl/worksheets/sheet1.xml | grep -q '<c r="E4"[^>]*><v>42</v>'; then
  echo "✔ sheets in the browser: opened, edited (E4=42), downloaded, reads back ($(wc -c <"$DL" | tr -d ' ') bytes)"
else
  echo "✘ the download lacks the edit (E4=42)"; exit 1
fi
echo "$OUT"
