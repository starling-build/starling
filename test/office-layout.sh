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
# (Starling's own fonts, whatever this machine has: a harness pins them so no
# baseline moves with the machine — see OfficeFonts.fontSource.)
export OFFICE_FONT_SOURCE="${OFFICE_FONT_SOURCE:-bundled}"
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# Per platform: the macOS debug build, or what build/build-all.sh makes on
# Linux. And on Linux the binary's own RUNPATH must pick the engine — an
# inherited LD_LIBRARY_PATH outranks it (the packaged terminal exports one to
# every shell inside it, and with it an older engine).
if [ "$(uname -s)" = Darwin ]; then
    DEFAULT_BIN="$REPO/.build-macos-office/arm64-apple-macosx/debug/OfficeApp"
    DEFAULT_CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
else
    unset LD_LIBRARY_PATH
    DEFAULT_BIN="$REPO/.build-shared/x86_64-unknown-linux-gnu/release/OfficeApp"
    DEFAULT_CHROME="$(command -v google-chrome || command -v chromium || echo google-chrome)"
fi
BIN="${OFFICE_BIN:-$DEFAULT_BIN}"
STAGE="$REPO/.stage-web-OfficeApp"
PORT="${PORT:-8137}"
DRIVE="$REPO/build/tools/web-drive.mjs"
CHROME="${CHROME:-$DEFAULT_CHROME}"

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
export URL="http://127.0.0.1:$PORT/" CHROME_PROFILE="$WORK/profile" CHROME
# A screen-sized font must not become narrower merely because its size
# falls between FreeType's 1/64-pixel units. Test the low-level web engine
# too: a native-only corpus sweep does not exercise this font backend.
if node "$DRIVE" wait 6000 eval "$(cat "$REPO/test/office-font-scale.js")" > "$WORK/font-scale.log" 2>&1; then
    echo "  ✔ fractional font advances and glyph ink scale consistently"
else
    echo "  ✘ fractional font advances or glyph ink differ by size"
    tail -3 "$WORK/font-scale.log"
    fails=$((fails + 1))
fi
for doc in "${DOCS[@]}"; do
    name="$(basename "$doc")"
    native="$WORK/$name.native.txt"
    web="$WORK/$name.web.txt"
    # The built-in welcome uses Cmd labels on macOS and Ctrl on the web.
    # Save it once, then open identical bytes on both sides, just as for
    # the fixtures. Comparing two platform-specific documents is not a
    # layout comparison. This also exercises its .docx round trip.
    if [ "$doc" = welcome ]; then
        doc="$WORK/welcome.docx"
        "$BIN" --convert welcome "$doc" >/dev/null \
            || { echo "  ✘ $name: could not write welcome fixture"; fails=$((fails + 1)); continue; }
    fi
    "$BIN" --layout "$doc" > "$native" || { echo "  ✘ $name: native layout failed"; fails=$((fails + 1)); continue; }
    abs="$(cd "$(dirname "$doc")" && pwd)/$(basename "$doc")"
    node "$DRIVE" wait 6000 chord ctrl o wait 500 setfile "$abs" wait 8000 dump layout "$web" > "$WORK/$name.log" 2>&1 \
        || { echo "  ✘ $name: browser dump failed"; tail -3 "$WORK/$name.log"; fails=$((fails + 1)); continue; }
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
# Fixed text frames need a drawing check too: a body-only layout dump
# does not see a glyph wrongly moved inside its box or clipped away.
# OFFICE_PYTHON may select the document-check environment with PyMuPDF.
BOX_PY="${OFFICE_PYTHON:-python3}"
BOX_TEST="$REPO/test/office-fixed-text-box.py"
if "$BOX_PY" -c 'import pymupdf' >/dev/null 2>&1; then
    "$BOX_PY" "$BOX_TEST" --binary "$BIN" || fails=$((fails + 1))
    if "$BOX_PY" "$BOX_TEST" --fixture "$WORK/fixed-frames.docx"; then
        printf '%s\n' "$WORK/fixed-frames.docx" > "$WORK/fixed-frames.txt"
        if node "$DRIVE" wait 6000 pdfs "$WORK/fixed-frames.txt" "$WORK/fixed-frame-pdfs" > "$WORK/fixed-frames.log" 2>&1 \
            && "$BOX_PY" "$BOX_TEST" --pdf "$WORK/fixed-frame-pdfs/fixed-frames.pdf"; then
            echo "  ✔ fixed text frames: native and browser keep and clip the intended glyphs"
        else
            echo "  ✘ fixed text frames differ from the Word controls"
            tail -3 "$WORK/fixed-frames.log"
            fails=$((fails + 1))
        fi
    else
        fails=$((fails + 1))
    fi
    OPENER_TEST="$REPO/test/office-opener-fit.py"
    "$BOX_PY" "$OPENER_TEST" --binary "$BIN" || fails=$((fails + 1))
    if "$BOX_PY" "$OPENER_TEST" --fixture "$WORK/openers.docx"; then
        printf '%s\n' "$WORK/openers.docx" > "$WORK/openers.txt"
        if node "$DRIVE" wait 6000 pdfs "$WORK/openers.txt" "$WORK/opener-pdfs" > "$WORK/openers.log" 2>&1 \
            && "$BOX_PY" "$OPENER_TEST" --pdf "$WORK/opener-pdfs/openers.pdf"; then
            echo "  ✔ opening marks: native and browser match the Word boundary controls"
        else
            echo "  ✘ opening-mark compression differs from the Word controls"
            tail -3 "$WORK/openers.log"
            fails=$((fails + 1))
        fi
    else
        fails=$((fails + 1))
    fi
else
    echo "  SKIPPED fixed-frame and opener PDF checks — PyMuPDF unavailable (OFFICE_PYTHON=…)"
fi
[ "$fails" -eq 0 ]
