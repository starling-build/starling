#!/usr/bin/env bash
# Web parity: the system clipboard carries formatting both ways. A paste from another app (here the page itself
# puts HTML on the clipboard, as a browser or mail app copying bold text would) must arrive formatted, not as
# plain text; and a copy from Word must offer HTML beside the plain text, so another app pastes it formatted too.
#
#   test/office-clipboard-web.sh [STAGE]   (default .stage-web-OfficeApp, from
#                                           build/web-app.sh OfficeApp --package apps/OfficeApp)
# Env: CHROME (default /snap/bin/chromium), HTTP_PORT (8617), PORT (DevTools, 9617).
set -u
cd "$(dirname "$0")/.."
STAGE=${1:-.stage-web-OfficeApp}
[ -f "$STAGE/app.wasm" ] || { echo "no $STAGE/app.wasm: build/web-app.sh OfficeApp --package apps/OfficeApp"; exit 2; }
export CHROME=${CHROME:-/snap/bin/chromium}
HTTP_PORT=${HTTP_PORT:-8617}
export PORT=${PORT:-9617} URL=http://127.0.0.1:$HTTP_PORT/ CLIPBOARD=1
# A snap Chromium cannot read /data or /tmp: its profile and downloads live under ~/snap.
WORK=$(mktemp -d "$HOME/snap/chromium/common/office-clipboard-XXXXXX")
export CHROME_PROFILE=$WORK/profile
python3 build/tools/web-serve.py "$STAGE" "$HTTP_PORT" > "$WORK/serve.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -rf "$WORK"' EXIT
sleep 1

PUT='navigator.clipboard.write([new ClipboardItem({
  "text/html": new Blob(["<p>plain <b>Qzb1</b></p>"], {type: "text/html"}),
  "text/plain": new Blob(["plain Qzb1"], {type: "text/plain"})})]).then(() => "put")'
TYPES='navigator.clipboard.read().then(items => items.flatMap(i => i.types).sort().join(","))'

fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
out=$(timeout 300 node build/tools/web-drive.mjs downloads "$WORK/downloads" settle Document1 click 700 450 \
  eval "$PUT" chord ctrl v wait 1500 chord ctrl s wait 2500 \
  chord ctrl a chord ctrl c wait 1500 eval "$TYPES" 2>&1 | grep -E '^eval:|Error')
echo "$out" | sed 's/^/  /'
docx=$(ls "$WORK"/downloads/*.docx 2>/dev/null | head -1)
check "Save downloaded the document" '[ -n "$docx" ]'
# The pasted word in a bold run: <w:r><w:rPr>...<w:b/>...</w:rPr><w:t>Qzb1</w:t>.
check "the HTML paste kept the bold" '[ -n "$docx" ] && unzip -p "$docx" word/document.xml |
  python3 -c "import re,sys; x=sys.stdin.read(); sys.exit(0 if re.search(r\"<w:r>(?:(?!</w:r>).)*<w:b/>(?:(?!</w:r>).)*Qzb1\", x) else 1)"'
types=$(echo "$out" | tail -1)
check "a copy offers HTML beside the plain text" '[[ "$types" == *text/html* && "$types" == *text/plain* ]]'
exit $fail
