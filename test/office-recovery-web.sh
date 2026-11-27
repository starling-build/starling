#!/usr/bin/env bash
# Web parity 2 (docs/plans/web-parity.md section 4): AutoSave's recovery copy in a browser tab.
# Types into Word, waits for AutoSave to copy the document into the page's storage (IndexedDB),
# closes the browser, starts a new one on the same profile: the text must be back and unsaved.
# Last, a tab hidden within AutoSave's 2-second pause writes its row at once (the page-hide flush).
# Then Save (a download) must delete the copy.
#
#   test/office-recovery-web.sh [STAGE]   (default .stage-web-OfficeApp, from
#                                          build/web-app.sh OfficeApp --package apps/OfficeApp)
# Env: CHROME (default /snap/bin/chromium), HTTP_PORT (8611), PORT (DevTools, 9611).
set -u
cd "$(dirname "$0")/.."
STAGE=${1:-.stage-web-OfficeApp}
[ -f "$STAGE/app.wasm" ] || { echo "no $STAGE/app.wasm: build/web-app.sh OfficeApp --package apps/OfficeApp"; exit 2; }
export CHROME=${CHROME:-/snap/bin/chromium}
HTTP_PORT=${HTTP_PORT:-8611}
export PORT=${PORT:-9611} URL=http://127.0.0.1:$HTTP_PORT/
# A snap Chromium cannot read /data or /tmp: its profile and downloads live under ~/snap.
WORK=$(mktemp -d "$HOME/snap/chromium/common/office-recovery-XXXXXX")
export CHROME_PROFILE=$WORK/profile
python3 build/tools/web-serve.py "$STAGE" "$HTTP_PORT" > "$WORK/serve.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -rf "$WORK"' EXIT
sleep 1

TEXT="Recovered by the next tab"
ROWS='new Promise(done => { const q = indexedDB.open("starling-office"); q.onsuccess = () => {
  const db = q.result; if (!db.objectStoreNames.contains("recovery")) return done([]);
  const all = db.transaction("recovery").objectStore("recovery").getAll();
  all.onsuccess = () => done(all.result.map(r => r.kind + " " + r.name + " " + r.bytes.byteLength)); }; })'
drive() { timeout 180 node build/tools/web-drive.mjs "$@" 2>&1 | grep -E '^eval:|Error' ; }
fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }

# 1. A first tab: type, let AutoSave run (2 s after the last key), read the page's rows.
one=$(drive settle Document1 click 700 450 type "$TEXT" wait 4000 eval "$ROWS")
echo "$one" | sed 's/^/  tab 1: /'
check "an edit leaves a recovery row" '[[ "$one" == *"docx Document1.docx"* ]]'

# 2. A new browser on the same profile: the closed tab's row is offered and restored.
# (A fresh start is "Document1"; the restored copy keeps the name it would save under.)
two=$(drive settle Document1.docx eval 'starling.debug("name")' \
      dump layout "$WORK/layout.txt" eval "$ROWS")
echo "$two" | sed 's/^/  tab 2: /'
check "the next tab restored the copy" '[[ "$two" == *"eval: \"Document1.docx\""* ]]'
check "the text is back" 'grep -q "$TEXT" "$WORK/layout.txt"'
check "the row is now the new tab's (one row)" '[ "$(echo "$two" | grep -c "docx Document1.docx")" = 1 ]'

# 3. Save (a download) deletes the row.
three=$(drive downloads "$WORK/downloads" wait 9000 chord ctrl s wait 1500 eval "$ROWS")
echo "$three" | sed 's/^/  tab 3: /'
check "Save downloads the document" 'ls "$WORK/downloads" | grep -q "Document1.docx"'
check "Save deletes the row" '[[ "$three" == *"eval: []"* ]]'

# 4. A tab closed within the 2-second pause: hiding the page writes the copy at once.
# (pagehide is what a closing tab fires; the row must be there 300 ms later, long before AutoSave.)
four=$(drive settle Document1 click 700 450 type "Hidden at once" wait 300 \
       eval 'window.dispatchEvent(new PageTransitionEvent("pagehide")), 1' wait 300 eval "$ROWS")
echo "$four" | sed 's/^/  tab 4: /'
check "hiding the page writes the row before the pause" '[[ "$four" == *"docx Document1.docx"* ]]'
exit $fail
