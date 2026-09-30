#!/bin/bash
# The same document lays out the same everywhere: every line break and
# every page, natively and in the browser, before a save and after it.
#
# For each document — the welcome page and the fixtures under
# apps/OfficeApp/Tests/OfficeAppTests/Fixtures — this prints the layout
# both ways (`OfficeApp --layout` natively, `starling.debug('layout')`
# in headless Chrome through build/tools/web-drive.mjs) and diffs the
# two; and round-trips each file through our .docx writer and diffs the
# native layout of the copy against the original's. One line of
# difference is one line broken elsewhere, and the diff says which.
#
# Needs a native OfficeApp (OFFICE_BIN, default the macOS debug build in
# .build-macos-office), the browser build staged (`build/web-app.sh
# OfficeApp --package apps/OfficeApp`), Chrome and node. Skips, with a
# reason, when any is missing — test/run.sh calls it and takes a skip.
#
#   test/office-layout.sh            # all documents
#   test/office-layout.sh path.docx  # one file
#
# Last measured (2026-09-30): the 26-page Word fixture, the TextEdit
# fixture and the welcome page — 0 differing lines each way, once the
# page's segmenter stopped adding breaks ICU refuses and the writer
# stopped giving cell paragraphs the body's space-after.
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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/office-layout.XXXXXX")"
trap 'rm -rf "$WORK"; [ -n "${SERVER:-}" ] && kill "$SERVER" 2>/dev/null' EXIT

# The dev server, unless one is already up on the port.
if ! curl -s -o /dev/null "http://127.0.0.1:$PORT/"; then
    python3 "$REPO/build/tools/web-serve.py" "$STAGE" "$PORT" >/dev/null 2>&1 &
    SERVER=$!
    for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done
fi

if [ $# -gt 0 ]; then
    DOCS=("$@")
else
    DOCS=(welcome)
    for f in "$REPO"/apps/OfficeApp/Tests/OfficeAppTests/Fixtures/*.docx; do DOCS+=("$f"); done
fi

fails=0
export URL="http://127.0.0.1:$PORT/" CHROME_PROFILE="$WORK/profile"
for doc in "${DOCS[@]}"; do
    name="$(basename "$doc")"
    native="$WORK/$name.native.txt"
    web="$WORK/$name.web.txt"
    if [ "$doc" = welcome ]; then
        "$BIN" --layout welcome > "$native" || { echo "  ✘ $name: native layout failed"; fails=$((fails + 1)); continue; }
        node "$DRIVE" wait 6000 dump layout "$web" > "$WORK/$name.log" 2>&1 \
            || { echo "  ✘ $name: browser dump failed"; tail -3 "$WORK/$name.log"; fails=$((fails + 1)); continue; }
    else
        "$BIN" --layout "$doc" > "$native" || { echo "  ✘ $name: native layout failed"; fails=$((fails + 1)); continue; }
        abs="$(cd "$(dirname "$doc")" && pwd)/$(basename "$doc")"
        node "$DRIVE" wait 6000 chord ctrl o wait 500 setfile "$abs" wait 8000 dump layout "$web" > "$WORK/$name.log" 2>&1 \
            || { echo "  ✘ $name: browser dump failed"; tail -3 "$WORK/$name.log"; fails=$((fails + 1)); continue; }
    fi
    pages="$(head -1 "$native")"
    lines="$(grep -c '^p' "$native")"
    if diff -q "$native" "$web" >/dev/null; then
        echo "  ✔ $name: browser lays out as native ($pages, $lines lines)"
    else
        echo "  ✘ $name: browser differs from native — $(diff "$native" "$web" | grep -c '^[<>]') lines"
        diff "$native" "$web" | head -12
        fails=$((fails + 1))
    fi
    # And the file survives our writer with its layout.
    if [ "$doc" != welcome ]; then
        copy="$WORK/$name.roundtrip.docx"
        again="$WORK/$name.roundtrip.txt"
        if "$BIN" --convert "$doc" "$copy" >/dev/null && "$BIN" --layout "$copy" > "$again" && diff -q "$native" "$again" >/dev/null; then
            echo "  ✔ $name: the saved copy lays out the same"
        else
            echo "  ✘ $name: the saved copy lays out differently — $(diff "$native" "$again" 2>/dev/null | grep -c '^[<>]') lines"
            diff "$native" "$again" 2>/dev/null | head -12
            fails=$((fails + 1))
        fi
    fi
done
[ "$fails" -eq 0 ]
