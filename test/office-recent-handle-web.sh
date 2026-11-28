#!/usr/bin/env bash
# Web parity 3 and 4 (docs/plans/web-parity.md section 4): Recent keeps the file's handle, so a document, a deck
# or a workbook reopened from Recent in a later tab saves back to the same file without asking for a place.
# Tab 1 saves a new document through the save picker; tabs 2 and 3 open a deck and a csv through the open
# picker. A new browser on the same profile then reopens each from File > Home and saves it: nothing may be
# downloaded, no place may be asked for, and each file must hold the edit.
# Real pickers open native dialogs a script cannot answer, so stand-ins (PRELOAD) hand back files in the page's
# private file storage (the origin private file system), whose handles go into IndexedDB as real ones do. (Its
# handles are always granted, so the browser's permission prompt itself is not shown here.)
#
#   test/office-recent-handle-web.sh [STAGE]   (default .stage-web-OfficeApp, from
#                                               build/web-app.sh OfficeApp --package apps/OfficeApp)
# Env: CHROME (default /snap/bin/chromium), HTTP_PORT (8615), PORT (DevTools, 9615).
set -u
cd "$(dirname "$0")/.."
STAGE=${1:-.stage-web-OfficeApp}
[ -f "$STAGE/app.wasm" ] || { echo "no $STAGE/app.wasm: build/web-app.sh OfficeApp --package apps/OfficeApp"; exit 2; }
DECK=test/corpus/pptx/decks/oox-tdf154074_freeConnector.pptx
[ -f "$DECK" ] || { echo "no $DECK (test/tools/corpus-cache.sh restore)"; exit 2; }
export CHROME=${CHROME:-/snap/bin/chromium}
HTTP_PORT=${HTTP_PORT:-8615}
export PORT=${PORT:-9615} URL=http://127.0.0.1:$HTTP_PORT/
# A snap Chromium cannot read /data or /tmp: its profile and downloads live under ~/snap.
WORK=$(mktemp -d "$HOME/snap/chromium/common/office-recent-handle-XXXXXX")
export CHROME_PROFILE=$WORK/profile PICKERS=1 PRELOAD=$WORK/pickers.js
{
  echo "const files = { 'Talk.pptx': '$(base64 -w0 "$DECK")', 'Book.csv': '$(printf 'one,two\n' | base64 -w0)' };"
  cat <<'JS'
// The files the open picker offers, put into the private file system once; window.__open names the one it picks.
// The save picker always places Note.docx.
window.__picks = [];
window.__ready = (async () => {
  const dir = await navigator.storage.getDirectory();
  for (const [name, b64] of Object.entries(files)) {
    try { await dir.getFileHandle(name); continue; } catch (e) {}
    const w = await (await dir.getFileHandle(name, { create: true })).createWritable();
    await w.write(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))); await w.close();
  }
})();
window.showOpenFilePicker = async () => {
  await window.__ready;
  return [await (await navigator.storage.getDirectory()).getFileHandle(window.__open)];
};
window.showSaveFilePicker = async (options = {}) => {
  window.__picks.push(options.suggestedName);
  return (await navigator.storage.getDirectory()).getFileHandle('Note.docx', { create: true });
};
JS
} > "$PRELOAD"
python3 build/tools/web-serve.py "$STAGE" "$HTTP_PORT" > "$WORK/serve.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -rf "$WORK"' EXIT
sleep 1

PICKS='JSON.stringify(window.__picks)'
# The Recent rows that keep a handle, by name.
HANDLES='new Promise(done => { const q = indexedDB.open("starling-office-recent"); q.onsuccess = () => {
  const all = q.result.transaction("recentBytes").objectStore("recentBytes").getAll();
  all.onsuccess = () => done(all.result.filter(r => r.handle).map(r => r.name).sort().join(",")); }; })'
CONTROLS='starling.debug("controls")'
file() { echo "(async () => { try { const f = await (await (await navigator.storage.getDirectory()).getFileHandle(\"$1\")).getFile();
  const b = new Uint8Array(await f.arrayBuffer()); let s = \"\"; for (const x of b) s += String.fromCharCode(x); return btoa(s); } catch (e) { return \"none\"; } })()"; }
drive() { timeout 300 node build/tools/web-drive.mjs downloads "$WORK/downloads" "$@" 2>&1 | grep -E '^eval:|Error' ; }
# The centre of the control labelled $2 in a controls dump $1 ("kind<TAB>x<TAB>y<TAB>label" lines, JSON-quoted).
at() { printf '%s' "$1" | sed 's/"$//; s/\\t/\t/g; s/\\n/\n/g' | awk -F'\t' -v l="$2" '$4 == l { print $2, $3; exit }'; }
# The bytes of a file from an "eval:" line holding them in base64.
decode() { python3 -c 'import base64, json, sys; sys.stdout.buffer.write(base64.b64decode(json.loads(sys.argv[1][len("eval: "):])))' "$1"; }
slides() { decode "$1" > "$WORK/deck.pptx" 2>/dev/null
  python3 -c 'import re, sys, zipfile
try: print(sum(1 for n in zipfile.ZipFile(sys.argv[1]).namelist() if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)))
except Exception: print(-1)' "$WORK/deck.pptx"; }
docxText() { decode "$1" > "$WORK/note.docx" 2>/dev/null
  python3 -c 'import re, sys, zipfile
try: print("".join(re.findall(r"<w:t[^>]*>([^<]*)</w:t>", zipfile.ZipFile(sys.argv[1]).read("word/document.xml").decode())))
except Exception: print("?")' "$WORK/note.docx"; }
fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
before=$(python3 -c 'import re, sys, zipfile; print(sum(1 for n in zipfile.ZipFile(sys.argv[1]).namelist() if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)))' "$DECK")

# 1. Three tabs put a file with a handle on Recent: a document saved through the save picker, a deck and a csv
#    opened through the open picker (Writer hands them on to Slides and Sheets).
drive settle Document1 click 700 450 type "Qzx1" chord ctrl s wait 2500 > /dev/null
drive wait 12000 eval 'window.__open = "Talk.pptx"' click 700 400 chord ctrl o settle Talk.pptx wait 1000 > /dev/null
one=$(drive wait 12000 eval 'window.__open = "Book.csv"' click 700 400 chord ctrl o settle Book.csv wait 1000 eval "$HANDLES")
echo "$one" | sed 's/^/  tab 1-3: /'
check "Recent keeps a handle for all three" '[[ "$one" == *"eval: \"Book.csv,Note.docx,Talk.pptx\""* ]]'

# 2. A new browser: File > Home lists them.
two=$(drive settle Document1 click 700 450 eval "$CONTROLS")
filebutton=$(at "$(echo "$two" | tail -1)" File)
two=$(drive settle Document1 click $filebutton wait 1000 eval "$CONTROLS")
note=$(at "$two" Note.docx); talk=$(at "$two" Talk.pptx); book=$(at "$two" Book.csv)
check "Home lists Note.docx, Talk.pptx and Book.csv" '[ -n "$note" ] && [ -n "$talk" ] && [ -n "$book" ]'

# 3. Each reopens from Recent and saves back in place. (A reopened file moves to the top of Recent, so each
#    row is looked up again just before it is clicked.)
row() { at "$(drive settle Document1 click $filebutton wait 1000 eval "$CONTROLS")" "$1"; }
note=$(row Note.docx)
word=$(drive settle Document1 click $filebutton wait 1000 click $note settle Note.docx click 700 450 \
       type "Qzx2" chord ctrl s wait 2500 eval "$PICKS" eval "$(file Note.docx)")
mapfile -t ev < <(echo "$word" | grep '^eval:')
text=$(docxText "${ev[1]:-eval: \"\"}")
echo "  word: Note.docx now reads: $(echo "$text" | grep -o "Qzx[0-9]" | tr "\n" " ")"
check "Word's Save from Recent did not ask for a place" '[[ "${ev[0]:-}" == "eval: \"[]\"" ]]'
check "Word's Save wrote the edit back to Note.docx" '[[ "$text" == *Qzx1* && "$text" == *Qzx2* ]]'

talk=$(row Talk.pptx)
deck=$(drive settle Document1 click $filebutton wait 1000 click $talk settle Talk.pptx \
       click 178 149 wait 500 chord ctrl s wait 2500 eval "$PICKS" eval "$(file Talk.pptx)")
echo "$deck" | cut -c1-120 | sed 's/^/  slides: /'
mapfile -t ev < <(echo "$deck" | grep '^eval:')
n=$(slides "${ev[1]:-eval: \"\"}")
echo "  slides: Talk.pptx had $before slides, now $n"
check "Slides' Save from Recent did not ask for a place" '[[ "${ev[0]:-}" == "eval: \"[]\"" ]]'
check "Slides' Save wrote the new slide back to Talk.pptx" '[ "$n" = $((before + 1)) ]'

book=$(row Book.csv)
sheet=$(drive settle Document1 click $filebutton wait 1000 click $book settle Book.csv \
        type changed press Enter chord ctrl s wait 2500 eval "$PICKS" eval "$(file Book.csv)")
mapfile -t ev < <(echo "$sheet" | grep '^eval:')
csv=$(decode "${ev[1]:-eval: \"\"}" 2>/dev/null | head -1)
echo "  sheets: Book.csv now reads: $csv"
check "Sheets' Save from Recent did not ask for a place" '[[ "${ev[0]:-}" == "eval: \"[]\"" ]]'
check "Sheets' Save wrote the edit back to Book.csv" '[[ "$csv" == "changed,two"* ]]'
check "nothing was downloaded" '[ -z "$(ls -A "$WORK/downloads" 2>/dev/null)" ]'
exit $fail
