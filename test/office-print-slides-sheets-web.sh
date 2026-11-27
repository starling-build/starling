#!/usr/bin/env bash
# Web parity 1 for Slides and Sheets (docs/plans/web-parity.md section 4): File > Print in a
# browser tab. Starts the page as Slides, then as Sheets, presses Ctrl+P and Enter (the dialog's
# Print), and reads window.starlingPrinted: the PDF the page handed to the browser's print
# (name, size in bytes, and whether a hidden frame or a new tab printed it).
#
#   test/office-print-slides-sheets-web.sh [STAGE]   (default .stage-web-OfficeApp, from
#                                                     build/web-app.sh OfficeApp --package apps/OfficeApp)
# Env: CHROME (default /snap/bin/chromium), HTTP_PORT (8615), PORT (DevTools, 9615).
set -u
cd "$(dirname "$0")/.."
STAGE=${1:-.stage-web-OfficeApp}
[ -f "$STAGE/app.wasm" ] || { echo "no $STAGE/app.wasm: build/web-app.sh OfficeApp --package apps/OfficeApp"; exit 2; }
export CHROME=${CHROME:-/snap/bin/chromium}
HTTP_PORT=${HTTP_PORT:-8615}
export PORT=${PORT:-9615} URL=http://127.0.0.1:$HTTP_PORT/
# A snap Chromium cannot read /data or /tmp: its profile lives under ~/snap.
WORK=$(mktemp -d "$HOME/snap/chromium/common/office-print-XXXXXX")
SERVER=
trap '[ -n "$SERVER" ] && kill $SERVER 2>/dev/null; rm -rf "$WORK"' EXIT
drive() { timeout 180 node build/tools/web-drive.mjs "$@" 2>&1 | grep -E '^eval:|Error' ; }
fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }

for app in slides sheets; do
  # A copy of the stage, started as this app.
  rm -rf "$WORK/stage"; cp -R "$STAGE" "$WORK/stage"
  sed -i "s|args: \[[^]]*\],|args: [\"--$app\"],|" "$WORK/stage/index.html"
  python3 build/tools/web-serve.py "$WORK/stage" "$HTTP_PORT" > "$WORK/serve.log" 2>&1 &
  SERVER=$!
  sleep 1
  export CHROME_PROFILE=$WORK/profile-$app
  if [ $app = sheets ]; then edit=(click 200 300 type "Printed from a tab" press Enter); else edit=(); fi
  out=$(drive wait 12000 "${edit[@]}" chord ctrl p wait 4000 press Enter wait 6000 eval 'window.starlingPrinted ?? null')
  echo "$out" | sed "s/^/  $app: /"
  check "$app: Print hands the browser a PDF" '[[ "$out" == *"\"name\":\""*".pdf\""* ]]'
  size=$(echo "$out" | grep -o '"size":[0-9]*' | cut -d: -f2)
  check "$app: the PDF is not empty (${size:-0} bytes)" '[ "${size:-0}" -gt 500 ]'
  kill $SERVER 2>/dev/null; wait $SERVER 2>/dev/null; SERVER=
done
exit $fail
