#!/usr/bin/env bash
# Web parity: shortcuts the browser would steal. A Ctrl chord the app uses (Bold, Save, Print, Find, the Font
# dialog) must be kept from the browser (its default prevented), or Chrome bookmarks the page, saves the page,
# prints the page, opens its own find bar or zooms the page (Ctrl+0) on top of ours; a chord the app does not use
# (Ctrl+4, the browser's fourth tab) must reach the browser. A page-level listener after the app's records what each key down left.
#
#   test/office-shortcuts-web.sh [STAGE]   (default .stage-web-OfficeApp, from
#                                           build/web-app.sh OfficeApp --package apps/OfficeApp)
# Env: CHROME (default /snap/bin/chromium), HTTP_PORT (8616), PORT (DevTools, 9616).
set -u
cd "$(dirname "$0")/.."
STAGE=${1:-.stage-web-OfficeApp}
[ -f "$STAGE/app.wasm" ] || { echo "no $STAGE/app.wasm: build/web-app.sh OfficeApp --package apps/OfficeApp"; exit 2; }
export CHROME=${CHROME:-/snap/bin/chromium}
HTTP_PORT=${HTTP_PORT:-8616}
export PORT=${PORT:-9616} URL=http://127.0.0.1:$HTTP_PORT/
# A snap Chromium cannot read /data or /tmp: its profile and downloads live under ~/snap.
WORK=$(mktemp -d "$HOME/snap/chromium/common/office-shortcuts-XXXXXX")
export CHROME_PROFILE=$WORK/profile PRELOAD=$WORK/keys.js
cat > "$PRELOAD" <<'JS'
// Each Ctrl key down as the page's last listener sees it: "key:prevented".
window.__keys = [];
window.addEventListener('keydown', (e) => {
  if (e.ctrlKey && e.key !== 'Control') window.__keys.push(e.key + ':' + e.defaultPrevented);
});
JS
python3 build/tools/web-serve.py "$STAGE" "$HTTP_PORT" > "$WORK/serve.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -rf "$WORK"' EXIT
sleep 1

fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
out=$(timeout 300 node build/tools/web-drive.mjs downloads "$WORK/downloads" settle Document1 click 700 450 \
  chord ctrl b chord ctrl d wait 1000 press Escape chord ctrl f wait 1000 press Escape click 700 450 \
  chord ctrl p wait 1500 press Escape wait 1000 chord ctrl s wait 2500 chord ctrl 4 chord ctrl 0 \
  eval 'window.__keys.join(" ")' 2>&1 | grep -E '^eval:|Error')
echo "  $out"
keys=${out#eval: }
for k in b d f p s 0; do check "the app keeps Ctrl+$k from the browser" '[[ "$keys" == *" $k:true"* || "$keys" == *"\"$k:true"* ]]'; done
check "Ctrl+4 (not the app's) reaches the browser" '[[ "$keys" == *"4:false"* ]]'
check "Save downloaded the document, not the page" '[ -n "$(ls "$WORK/downloads" 2>/dev/null | grep -i "\.docx$")" ]'
exit $fail
