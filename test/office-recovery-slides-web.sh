#!/usr/bin/env bash
# Web parity 2 for Slides (docs/plans/web-parity.md section 4): AutoSave's recovery copy of a deck in a
# browser tab. Opens a deck, adds a slide, waits for AutoSave to copy it into the page's storage (IndexedDB),
# closes the browser, starts a new one on the same profile: the tab starts in Writer, which must hand the deck
# to Slides, unsaved. Then Save (a download) must delete the copy.
#
#   test/office-recovery-slides-web.sh [STAGE]   (default .stage-web-OfficeApp, from
#                                          build/web-app.sh OfficeApp --package apps/OfficeApp)
# Env: CHROME (default /snap/bin/chromium), HTTP_PORT (8612), PORT (DevTools, 9612).
set -u
cd "$(dirname "$0")/.."
STAGE=${1:-.stage-web-OfficeApp}
[ -f "$STAGE/app.wasm" ] || { echo "no $STAGE/app.wasm: build/web-app.sh OfficeApp --package apps/OfficeApp"; exit 2; }
export CHROME=${CHROME:-/snap/bin/chromium}
HTTP_PORT=${HTTP_PORT:-8612}
export PORT=${PORT:-9612} URL=http://127.0.0.1:$HTTP_PORT/
# A snap Chromium cannot read /data or /tmp: its profile and downloads live under ~/snap.
WORK=$(mktemp -d "$HOME/snap/chromium/common/office-recovery-slides-XXXXXX")
export CHROME_PROFILE=$WORK/profile
python3 build/tools/web-serve.py "$STAGE" "$HTTP_PORT" > "$WORK/serve.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -rf "$WORK"' EXIT
sleep 1

DECK=test/corpus/pptx/decks/oox-tdf154074_freeConnector.pptx
[ -f "$DECK" ] || { echo "no $DECK (test/tools/corpus-cache.sh restore)"; exit 2; }
cp "$DECK" "$WORK/Talk.pptx"
ROWS='new Promise(done => { const q = indexedDB.open("starling-office"); q.onsuccess = () => {
  const db = q.result; if (!db.objectStoreNames.contains("recovery")) return done([]);
  const all = db.transaction("recovery").objectStore("recovery").getAll();
  all.onsuccess = () => done(all.result.map(r => r.kind + " " + r.name)); }; })'
drive() { timeout 180 node build/tools/web-drive.mjs "$@" 2>&1 | grep -E '^eval:|Error' ; }
fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }

# 1. A first tab opens a deck (Writer hands it to Slides), adds a slide (Home > New Slide), and waits
#    for AutoSave (2 s after the last change).
one=$(drive wait 12000 click 700 400 chord ctrl o wait 1500 setfile "$WORK/Talk.pptx" settle Talk.pptx \
      eval 'starling.debug("name")' click 178 149 wait 4000 eval "$ROWS" shot "$WORK/tab1.png")
echo "$one" | sed 's/^/  tab 1: /'
check "an edit to the deck leaves a pptx row" '[[ "$one" == *"pptx Talk.pptx"* ]]'

# 2. A new browser on the same profile starts in Writer, which hands the deck's copy to Slides: unsaved, by name.
two=$(drive settle Talk.pptx eval 'starling.debug("name")' eval 'starling.debug("status")' eval "$ROWS" \
      shot "${SHOT:-$WORK/tab2.png}")
echo "$two" | sed 's/^/  tab 2: /'
check "the next tab restored the deck in Slides" '[[ "$two" == *"eval: \"Talk.pptx\""* ]]'
check "it says the deck is restored and unsaved" '[[ "$two" == *"Restored unsaved changes to Talk.pptx"* ]]'
check "the row is now the new tab's (one row)" '[ "$(echo "$two" | grep -c "pptx Talk.pptx")" = 1 ]'

# 3. Save (a download) deletes the row.
three=$(drive downloads "$WORK/downloads" settle Talk.pptx chord ctrl s wait 1500 eval "$ROWS")
echo "$three" | sed 's/^/  tab 3: /'
check "Save downloads the deck" 'ls "$WORK/downloads" | grep -q "Talk.pptx"'
check "Save deletes the row" '[[ "$three" == *"eval: []"* ]]'
exit $fail
