#!/usr/bin/env bash
# Web parity 3 (docs/plans/web-parity.md section 4): Recent files in a browser tab.
# A first browser saves a new document (a download) and opens another through the picker: the page keeps
# both. A second browser on the same profile lists them on File > Home; a third clicks one and gets it back.
#
#   test/office-recent-web.sh [STAGE]   (default .stage-web-OfficeApp, from
#                                        build/web-app.sh OfficeApp --package apps/OfficeApp)
# Env: CHROME (default /snap/bin/chromium), HTTP_PORT (8612), PORT (DevTools, 9612).
set -u
cd "$(dirname "$0")/.."
STAGE=${1:-.stage-web-OfficeApp}
[ -f "$STAGE/app.wasm" ] || { echo "no $STAGE/app.wasm: build/web-app.sh OfficeApp --package apps/OfficeApp"; exit 2; }
export CHROME=${CHROME:-/snap/bin/chromium}
HTTP_PORT=${HTTP_PORT:-8612}
export PORT=${PORT:-9612} URL=http://127.0.0.1:$HTTP_PORT/
# A snap Chromium cannot read /data or /tmp: its profile, downloads and the file it opens live under ~/snap.
WORK=$(mktemp -d "$HOME/snap/chromium/common/office-recent-XXXXXX")
export CHROME_PROFILE=$WORK/profile
cp apps/OfficeApp/Tests/OfficeAppTests/Fixtures/textedit.docx "$WORK/Minutes.docx"
python3 build/tools/web-serve.py "$STAGE" "$HTTP_PORT" > "$WORK/serve.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -rf "$WORK"' EXIT
sleep 1

ROWS='new Promise(done => { const q = indexedDB.open("starling-office-recent"); q.onsuccess = () => {
  const db = q.result; if (!db.objectStoreNames.contains("recent")) return done("");
  const all = db.transaction("recent").objectStore("recent").getAll();
  all.onsuccess = () => done(all.result.sort((a, b) => b.time - a.time).map(r => r.name).join(",")); }; })'
CONTROLS='starling.debug("controls")'
drive() { timeout 180 node build/tools/web-drive.mjs "$@" 2>&1 | grep -E '^eval:|Error' ; }
# The centre of the control labelled $2 in a controls dump $1 ("kind<TAB>x<TAB>y<TAB>label" lines, JSON-quoted).
at() { printf '%s' "$1" | sed 's/"$//; s/\\t/\t/g; s/\\n/\n/g' | awk -F'\t' -v l="$2" '$4 == l { print $2, $3; exit }'; }
fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }

# 1. Type and save a new document (a download), then open Minutes.docx through the picker.
one=$(drive downloads "$WORK/downloads" settle Document1 click 700 450 type "Saved in a tab" chord ctrl s wait 1500 \
      chord ctrl o setfile "$WORK/Minutes.docx" settle Minutes.docx dump layout "$WORK/opened.txt" \
      eval "$ROWS" eval "$CONTROLS")
echo "$one" | grep -F -v '\t' | sed 's/^/  tab 1: /'
check "the page keeps both, newest first" '[[ "$one" == *"eval: \"Minutes.docx,Document1.docx\""* ]]'
file=$(at "$(echo "$one" | grep -F '\t' | tail -1)" File)
check "found File on the ribbon" '[ -n "$file" ]'

# 2. A new browser on the same profile: File > Home lists them.
two=$(drive settle Document1 click $file wait 1000 eval "$CONTROLS")
minutes=$(at "$two" Minutes.docx)
check "Home lists Minutes.docx" '[ -n "$minutes" ]'
check "Home lists Document1.docx" '[ -n "$(at "$two" Document1.docx)" ]'

# 3. A third: clicking it reopens the kept copy, as it was opened.
three=$(drive settle Document1 click $file wait 1000 click $minutes settle Minutes.docx dump layout "$WORK/reopened.txt" \
        eval 'starling.debug("name")')
echo "$three" | sed 's/^/  tab 3: /'
check "Minutes.docx reopened" '[[ "$three" == *"eval: \"Minutes.docx\""* ]]'
check "with the same text" '[ -s "$WORK/opened.txt" ] && cmp -s "$WORK/opened.txt" "$WORK/reopened.txt"'
exit $fail
