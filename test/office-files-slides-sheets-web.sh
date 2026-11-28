#!/usr/bin/env bash
# Web parity 3 and 4 for Slides and Sheets (docs/plans/web-parity.md section 4): a deck or a workbook opened
# through the browser's picker keeps its file handle, and Save writes back to that file, as Word's does.
# A tab starts in Writer; its Open hands a deck to Slides and a workbook to Sheets, with the handle.
# Real pickers open native dialogs a script cannot answer, so stand-ins (PRELOAD) hand back files in the
# page's private file storage (the origin private file system), which take the same writes. Nothing may be
# downloaded and no place may be asked for.
#
#   test/office-files-slides-sheets-web.sh [STAGE]   (default .stage-web-OfficeApp, from
#                                                     build/web-app.sh OfficeApp --package apps/OfficeApp)
# Env: CHROME (default /snap/bin/chromium), HTTP_PORT (8614), PORT (DevTools, 9614), SHOT (a screenshot path).
set -u
cd "$(dirname "$0")/.."
STAGE=${1:-.stage-web-OfficeApp}
[ -f "$STAGE/app.wasm" ] || { echo "no $STAGE/app.wasm: build/web-app.sh OfficeApp --package apps/OfficeApp"; exit 2; }
DECK=test/corpus/pptx/decks/oox-tdf154074_freeConnector.pptx
[ -f "$DECK" ] || { echo "no $DECK (test/tools/corpus-cache.sh restore)"; exit 2; }
export CHROME=${CHROME:-/snap/bin/chromium}
HTTP_PORT=${HTTP_PORT:-8614}
export PORT=${PORT:-9614} URL=http://127.0.0.1:$HTTP_PORT/
# A snap Chromium cannot read /data or /tmp: its profile and downloads live under ~/snap.
WORK=$(mktemp -d "$HOME/snap/chromium/common/office-files-XXXXXX")
export CHROME_PROFILE=$WORK/profile PICKERS=1 PRELOAD=$WORK/pickers.js
{
  echo "const files = { 'Talk.pptx': '$(base64 -w0 "$DECK")', 'Book.csv': '$(printf 'one,two\n' | base64 -w0)' };"
  cat <<'JS'
// The files the open picker offers, put into the private file system once; window.__open names the one it picks.
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
  return (await navigator.storage.getDirectory()).getFileHandle(options.suggestedName, { create: true });
};
JS
} > "$PRELOAD"
python3 build/tools/web-serve.py "$STAGE" "$HTTP_PORT" > "$WORK/serve.log" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -rf "$WORK"' EXIT
sleep 1

PICKS='JSON.stringify(window.__picks)'
file() { echo "(async () => { try { const f = await (await (await navigator.storage.getDirectory()).getFileHandle(\"$1\")).getFile();
  const b = new Uint8Array(await f.arrayBuffer()); let s = \"\"; for (const x of b) s += String.fromCharCode(x); return btoa(s); } catch (e) { return \"none\"; } })()"; }
drive() { timeout 180 node build/tools/web-drive.mjs downloads "$WORK/downloads" "$@" 2>&1 | grep -E '^eval:|Error' ; }
# The bytes of a file from an "eval:" line holding them in base64.
decode() { python3 -c 'import base64, json, sys; sys.stdout.buffer.write(base64.b64decode(json.loads(sys.argv[1][len("eval: "):])))' "$1"; }
slides() { decode "$1" > "$WORK/deck.pptx" 2>/dev/null
  python3 -c 'import re, sys, zipfile
try: print(sum(1 for n in zipfile.ZipFile(sys.argv[1]).namelist() if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)))
except Exception: print(-1)' "$WORK/deck.pptx"; }
fail=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
before=$(python3 -c 'import re, sys, zipfile; print(sum(1 for n in zipfile.ZipFile(sys.argv[1]).namelist() if re.fullmatch(r"ppt/slides/slide\d+\.xml", n)))' "$DECK")

# 1. Writer's Open picks a deck: Slides opens it, Home > New Slide adds one, Save writes the picked file.
one=$(drive wait 12000 eval 'window.__open = "Talk.pptx"' click 700 400 chord ctrl o settle Talk.pptx \
      click 178 149 wait 500 chord ctrl s wait 2500 eval "$PICKS" eval "$(file Talk.pptx)" \
      shot "${SHOT:-$WORK/slides.png}")
echo "$one" | cut -c1-120 | sed 's/^/  slides: /'
mapfile -t ev < <(echo "$one" | grep '^eval:')
check "Slides' Save did not ask for a place" '[[ "${ev[1]:-}" == "eval: \"[]\"" ]]'
n=$(slides "${ev[2]:-eval: \"\"}")
echo "  slides: the picked deck had $before slides, the file now has $n"
check "Save wrote the new slide back to the picked deck" '[ "$n" = $((before + 1)) ]'

# 2. A new tab: Writer's Open picks a csv; Sheets opens it, a new A1 is typed, Save writes the csv back.
two=$(drive wait 12000 eval 'window.__open = "Book.csv"' click 700 400 chord ctrl o settle Book.csv \
      type changed press Enter chord ctrl s wait 2500 eval "$PICKS" eval "$(file Book.csv)" \
      shot "${SHOT2:-$WORK/sheets.png}")
echo "$two" | cut -c1-120 | sed 's/^/  sheets: /'
mapfile -t ev < <(echo "$two" | grep '^eval:')
check "Sheets' Save did not ask for a place" '[[ "${ev[1]:-}" == "eval: \"[]\"" ]]'
text=$(decode "${ev[2]:-eval: \"\"}" 2>/dev/null | head -c 200)
echo "  sheets: the file now reads: $(echo "$text" | head -1)"
check "Save wrote the edit back to the picked csv" '[[ "$text" == "changed,two"* ]]'
check "nothing was downloaded" '[ -z "$(ls -A "$WORK/downloads" 2>/dev/null)" ]'
exit $fail
