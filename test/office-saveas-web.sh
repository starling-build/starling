#!/usr/bin/env bash
# Web parity 4 (docs/plans/web-parity.md section 4): Save As and Save through the browser's file pickers.
# Real pickers open native dialogs a script cannot answer, so stand-ins (PRELOAD) hand back files in the
# page's private file storage (the origin private file system), which take the same writes. Word must:
# ask for a place on the first Save and write the document there, write back to it on the next Save
# without asking, and save a file opened through the open picker back to itself. Nothing is downloaded.
#
#   test/office-saveas-web.sh [STAGE]   (default .stage-web-OfficeApp, from
#                                        build/web-app.sh OfficeApp --package apps/OfficeApp)
# Env: CHROME (default /snap/bin/chromium), HTTP_PORT (8613), PORT (DevTools, 9613).
set -u
cd "$(dirname "$0")/.."
STAGE=${1:-.stage-web-OfficeApp}
[ -f "$STAGE/app.wasm" ] || { echo "no $STAGE/app.wasm: build/web-app.sh OfficeApp --package apps/OfficeApp"; exit 2; }
export CHROME=${CHROME:-/snap/bin/chromium}
HTTP_PORT=${HTTP_PORT:-8613}
export PORT=${PORT:-9613} URL=http://127.0.0.1:$HTTP_PORT/
# A snap Chromium cannot read /data or /tmp: its profile and downloads live under ~/snap.
WORK=$(mktemp -d "$HOME/snap/chromium/common/office-saveas-XXXXXX")
export CHROME_PROFILE=$WORK/profile PICKERS=1 PRELOAD=$WORK/pickers.js
cat > "$PRELOAD" <<'JS'
// Stand-in pickers: every place is a file in the origin private file system, named as suggested.
window.__picks = [];
window.showSaveFilePicker = async (options = {}) => {
  window.__picks.push(options.suggestedName + ' ' + (options.types || []).map((t) => Object.values(t.accept).flat().join('')).join(','));
  return (await navigator.storage.getDirectory()).getFileHandle(options.suggestedName, { create: true });
};
window.showOpenFilePicker = async () => [await (await navigator.storage.getDirectory()).getFileHandle('Document1.docx')];
JS
python3 build/tools/web-serve.py "$STAGE" "$HTTP_PORT" > "$WORK/serve.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -rf "$WORK"' EXIT
sleep 1

PICKS='JSON.stringify(window.__picks)'
FILE='(async () => { try { const f = await (await (await navigator.storage.getDirectory()).getFileHandle("Document1.docx")).getFile();
  const b = new Uint8Array(await f.arrayBuffer()); let s = ""; for (const x of b) s += String.fromCharCode(x); return btoa(s); } catch (e) { return "none"; } })()'
drive() { timeout 180 node build/tools/web-drive.mjs downloads "$WORK/downloads" "$@" 2>&1 | grep -E '^eval:|Error' ; }
# The text of the saved file (word/document.xml's runs), from an "eval:" line holding it in base64.
saved() { python3 -c '
import base64, io, json, re, sys, zipfile
line = sys.argv[1]
try:
    z = zipfile.ZipFile(io.BytesIO(base64.b64decode(json.loads(line[len("eval: "):]))))
    print("".join(re.findall(r"<w:t[^>]*>([^<]*)</w:t>", z.read("word/document.xml").decode())))
except Exception as e:
    print("unreadable:", e)' "$1"; }
fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }

# 1. Save asks for a place (Word's own format first) and writes there; the next Save writes again, unasked.
one=$(drive settle Document1 click 700 450 type "First words" chord ctrl s wait 2000 eval "$PICKS" eval "$FILE" \
      type " and more" chord ctrl s wait 2000 eval "$PICKS" eval "$FILE" eval 'starling.debug("name")')
echo "$one" | cut -c1-120 | sed 's/^/  tab 1: /'
mapfile -t ev < <(echo "$one" | grep '^eval:')
echo "  tab 1 saved: $(saved "${ev[3]:-}" | cut -c1-80)"
check "Save asked for a place once, .docx first" '[[ "${ev[0]}" == *"Document1.docx .docx,"* && "${ev[2]}" == "${ev[0]}" ]]'
check "the first Save wrote the file" '[[ "$(saved "${ev[1]}")" == *"First words"* ]]'
check "the second Save wrote it again" '[[ "$(saved "${ev[3]}")" == *"First words and more"* ]]'
check "the document took the file's name" '[[ "${ev[4]}" == *"Document1.docx"* ]]'

# 2. A new tab opens that file through the open picker; Save writes back to it without asking.
two=$(drive settle Document1 chord ctrl o settle Document1.docx click 700 450 chord ctrl Home type "Reopened " \
      chord ctrl s wait 2000 eval "$PICKS" eval "$FILE")
echo "$two" | cut -c1-120 | sed 's/^/  tab 2: /'
mapfile -t ev < <(echo "$two" | grep '^eval:')
echo "  tab 2 saved: $(saved "${ev[1]:-}" | cut -c1-80)"
check "Save did not ask for a place" '[[ "${ev[0]}" == "eval: \"[]\"" ]]'
t2=$(saved "${ev[1]}")
check "Save wrote back to the opened file" '[[ "$t2" == "Reopened "* && "$t2" == *"First words and more"* ]]'
check "nothing was downloaded" '[ -z "$(ls -A "$WORK/downloads" 2>/dev/null)" ]'
exit $fail
