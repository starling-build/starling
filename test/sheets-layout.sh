#!/bin/bash
# A workbook lays out the same everywhere: every column width, row height,
# shown text, measured text width and wrapped line count, natively and in
# the browser, before a save and after it. Sheets' counterpart of
# test/office-layout.sh.
#
# For each workbook — the fixtures under apps/OfficeApp/Tests/OfficeAppTests/
# Fixtures — this prints the layout both ways (`OfficeApp --sheet-layout`
# natively, `starling.debug('sheet')` in headless Chrome through
# build/tools/web-drive.mjs, the file opened through the page's picker)
# and diffs the two; and round-trips each file through our .xlsx writer
# and diffs the native layout of the copy against the original's.
#
# Needs a native OfficeApp (OFFICE_BIN, default the macOS debug build in
# .build-macos-office), the browser build staged (`build/web-app.sh
# OfficeApp --package apps/OfficeApp`), Chrome and node. Skips, with a
# reason, when any is missing — test/run.sh calls it and takes a skip.
#
#   test/sheets-layout.sh              # all fixtures
#   test/sheets-layout.sh book.xlsx    # one file
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${OFFICE_BIN:-$REPO/.build-macos-office/arm64-apple-macosx/debug/OfficeApp}"
STAGE="$REPO/.stage-web-OfficeApp"
PORT="${PORT:-8137}"
DRIVE="$REPO/build/tools/web-drive.mjs"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

skip() { echo "  SKIPPED — $1"; exit 0; }
[ -x "$BIN" ] || skip "no native OfficeApp at $BIN (OFFICE_BIN=…)"
[ -f "$STAGE/app.wasm" ] || skip "no browser build staged (build/web-app.sh OfficeApp --package apps/OfficeApp)"
command -v node >/dev/null || skip "no node"
[ -x "$CHROME" ] || command -v "$CHROME" >/dev/null || skip "no Chrome at $CHROME (CHROME=…)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/sheets-layout.XXXXXX")"
trap 'rm -rf "$WORK"; [ -n "${SERVER:-}" ] && kill "$SERVER" 2>/dev/null' EXIT

if ! curl -s -o /dev/null "http://127.0.0.1:$PORT/"; then
    python3 "$REPO/build/tools/web-serve.py" "$STAGE" "$PORT" >/dev/null 2>&1 &
    SERVER=$!
    for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done
fi

if [ $# -gt 0 ]; then
    DOCS=("$@")
else
    DOCS=()
    for f in "$REPO"/apps/OfficeApp/Tests/OfficeAppTests/Fixtures/*.xlsx; do DOCS+=("$f"); done
fi

fails=0
export URL="http://127.0.0.1:$PORT/" CHROME_PROFILE="$WORK/profile"
for doc in "${DOCS[@]}"; do
    name="$(basename "$doc")"
    native="$WORK/$name.native.txt"
    web="$WORK/$name.web.txt"
    "$BIN" --sheet-layout "$doc" > "$native" || { echo "  ✘ $name: native layout failed"; fails=$((fails + 1)); continue; }
    abs="$(cd "$(dirname "$doc")" && pwd)/$(basename "$doc")"
    # The page starts in Writer; a workbook picked there opens in Sheets.
    node "$DRIVE" wait 8000 chord ctrl o wait 800 setfile "$abs" wait 10000 dump sheet "$web" > "$WORK/$name.log" 2>&1 \
        || { echo "  ✘ $name: browser dump failed"; tail -3 "$WORK/$name.log"; fails=$((fails + 1)); continue; }
    cells="$(grep -c $'\t' "$native")"
    if diff -q "$native" "$web" >/dev/null; then
        echo "  ✔ $name: browser lays out as native ($(head -1 "$native" | cut -d' ' -f2-), $cells cells)"
    else
        echo "  ✘ $name: browser differs from native — $(diff "$native" "$web" | grep -c '^[<>]') lines"
        diff "$native" "$web" | head -12
        fails=$((fails + 1))
    fi
    copy="$WORK/$name.roundtrip.xlsx"
    again="$WORK/$name.roundtrip.txt"
    if "$BIN" --xlsx-roundtrip "$doc" "$copy" >/dev/null && "$BIN" --sheet-layout "$copy" > "$again" && diff -q "$native" "$again" >/dev/null; then
        echo "  ✔ $name: the saved copy lays out the same"
    else
        echo "  ✘ $name: the saved copy lays out differently — $(diff "$native" "$again" 2>/dev/null | grep -c '^[<>]') lines"
        diff "$native" "$again" 2>/dev/null | head -12
        fails=$((fails + 1))
    fi
done
[ "$fails" -eq 0 ]
