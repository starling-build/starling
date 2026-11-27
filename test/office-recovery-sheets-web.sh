#!/usr/bin/env bash
# Web parity 2 for Sheets (docs/plans/web-parity.md section 4): AutoSave's recovery copy of a workbook in a
# browser tab. Opens a workbook, types into a cell, waits for AutoSave to copy it into the page's storage
# (IndexedDB), closes the browser, starts a new one on the same profile: the tab starts in Writer, which must
# hand the workbook to Sheets, unsaved, with the typed cell. Then Save (a download) must delete the copy.
#
#   test/office-recovery-sheets-web.sh [STAGE]   (default .stage-web-OfficeApp, from
#                                          build/web-app.sh OfficeApp --package apps/OfficeApp)
# Env: CHROME (default /snap/bin/chromium), HTTP_PORT (8613), PORT (DevTools, 9613).
set -u
cd "$(dirname "$0")/.."
STAGE=${1:-.stage-web-OfficeApp}
[ -f "$STAGE/app.wasm" ] || { echo "no $STAGE/app.wasm: build/web-app.sh OfficeApp --package apps/OfficeApp"; exit 2; }
export CHROME=${CHROME:-/snap/bin/chromium}
HTTP_PORT=${HTTP_PORT:-8613}
export PORT=${PORT:-9613} URL=http://127.0.0.1:$HTTP_PORT/
# A snap Chromium cannot read /data or /tmp: its profile and downloads live under ~/snap.
WORK=$(mktemp -d "$HOME/snap/chromium/common/office-recovery-sheets-XXXXXX")
export CHROME_PROFILE=$WORK/profile
python3 build/tools/web-serve.py "$STAGE" "$HTTP_PORT" > "$WORK/serve.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -rf "$WORK"' EXIT
sleep 1

BOOK=test/corpus/xlsx/books/59746_NoRowNums.xlsx
[ -f "$BOOK" ] || { echo "no $BOOK (test/tools/corpus-cache.sh restore)"; exit 2; }
cp "$BOOK" "$WORK/Budget.xlsx"
ROWS='new Promise(done => { const q = indexedDB.open("starling-office"); q.onsuccess = () => {
  const db = q.result; if (!db.objectStoreNames.contains("recovery")) return done([]);
  const all = db.transaction("recovery").objectStore("recovery").getAll();
  all.onsuccess = () => done(all.result.map(r => r.kind + " " + r.name)); }; })'
drive() { timeout 180 node build/tools/web-drive.mjs "$@" 2>&1 | grep -E '^eval:|Error' ; }
fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }

# 1. A first tab opens a workbook (Writer hands it to Sheets), types into the active cell and commits it, and
#    waits for AutoSave (2 s after the last change).
one=$(drive wait 12000 click 700 400 chord ctrl o wait 1500 setfile "$WORK/Budget.xlsx" settle Budget.xlsx \
      eval 'starling.debug("name")' type recovered42 press Enter wait 4000 eval "$ROWS" shot "$WORK/tab1.png")
echo "$one" | sed 's/^/  tab 1: /'
check "an edit to the workbook leaves an xlsx row" '[[ "$one" == *"xlsx Budget.xlsx"* ]]'

# 2. A new browser on the same profile starts in Writer, which hands the copy to Sheets: unsaved, by name,
#    with the typed cell.
two=$(drive settle Budget.xlsx eval 'starling.debug("name")' eval 'starling.debug("status")' eval "$ROWS" \
      eval 'starling.debug("sheet").includes("recovered42")' shot "${SHOT:-$WORK/tab2.png}")
echo "$two" | sed 's/^/  tab 2: /' | cut -c1-200
check "the next tab restored the workbook in Sheets" '[[ "$two" == *"eval: \"Budget.xlsx\""* ]]'
check "it says the workbook is restored and unsaved" '[[ "$two" == *"Restored unsaved changes to Budget.xlsx"* ]]'
check "the typed cell came back" '[[ "$two" == *"eval: true"* ]]'
check "the row is now the new tab's (one row)" '[ "$(echo "$two" | grep -c "xlsx Budget.xlsx")" = 1 ]'

# 3. Save (a download) deletes the row.
three=$(drive downloads "$WORK/downloads" settle Budget.xlsx chord ctrl s wait 1500 eval "$ROWS")
echo "$three" | sed 's/^/  tab 3: /'
check "Save downloads the workbook" 'ls "$WORK/downloads" | grep -q "Budget.xlsx"'
check "Save deletes the row" '[[ "$three" == *"eval: []"* ]]'
exit $fail
