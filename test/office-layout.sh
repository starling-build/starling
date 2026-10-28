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
# PORT selects this gate's HTTP server. web-drive also calls its DevTools
# setting PORT, so never forward the HTTP value to Chrome's debugging socket.
DEVTOOLS_PORT="${OFFICE_DEVTOOLS_PORT:-9333}"
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
if PORT="$DEVTOOLS_PORT" node "$DRIVE" wait 6000 eval "$(cat "$REPO/test/office-font-scale.js")" > "$WORK/font-scale.log" 2>&1; then
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
    PORT="$DEVTOOLS_PORT" node "$DRIVE" wait 6000 chord ctrl o wait 500 setfile "$abs" settle "$(basename "$abs")" dump layout "$web" > "$WORK/$name.log" 2>&1 \
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
        if PORT="$DEVTOOLS_PORT" node "$DRIVE" wait 6000 pdfs "$WORK/fixed-frames.txt" "$WORK/fixed-frame-pdfs" > "$WORK/fixed-frames.log" 2>&1 \
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
        if PORT="$DEVTOOLS_PORT" node "$DRIVE" wait 6000 pdfs "$WORK/openers.txt" "$WORK/opener-pdfs" > "$WORK/openers.log" 2>&1 \
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
    LATIN_TEST="$REPO/test/office-latin-fit.py"
    "$BOX_PY" "$LATIN_TEST" --binary "$BIN" || fails=$((fails + 1))
    if "$BOX_PY" "$LATIN_TEST" --fixture "$WORK/latin-fit.docx"; then
        printf '%s\n' "$WORK/latin-fit.docx" > "$WORK/latin-fit.txt"
        if PORT="$DEVTOOLS_PORT" node "$DRIVE" wait 6000 pdfs "$WORK/latin-fit.txt" "$WORK/latin-fit-pdfs" > "$WORK/latin-fit.log" 2>&1 \
            && "$BOX_PY" "$LATIN_TEST" --pdf "$WORK/latin-fit-pdfs/latin-fit.pdf"; then
            echo "  ✔ Latin words: native and browser match the Word compression/stretch controls"
        else
            echo "  ✘ Latin-word fitting differs from the Word controls"
            tail -3 "$WORK/latin-fit.log"
            fails=$((fails + 1))
        fi
    else
        fails=$((fails + 1))
    fi
    CELL_WORD_TEST="$REPO/test/office-cell-word-fit.py"
    "$BOX_PY" "$CELL_WORD_TEST" --binary "$BIN" || fails=$((fails + 1))
    if "$BOX_PY" "$CELL_WORD_TEST" --fixture "$WORK/cell-word-fit.docx"; then
        printf '%s\n' "$WORK/cell-word-fit.docx" > "$WORK/cell-word-fit.txt"
        if PORT="$DEVTOOLS_PORT" node "$DRIVE" wait 6000 pdfs "$WORK/cell-word-fit.txt" "$WORK/cell-word-fit-pdfs" > "$WORK/cell-word-fit.log" 2>&1 \
            && "$BOX_PY" "$CELL_WORD_TEST" --pdf "$WORK/cell-word-fit-pdfs/cell-word-fit.pdf"; then
            echo "  ✔ Legacy cell words: native and browser match the Word separating-space controls"
        else
            echo "  ✘ Legacy cell-word fitting differs from the Word controls"
            tail -3 "$WORK/cell-word-fit.log"
            fails=$((fails + 1))
        fi
    else
        fails=$((fails + 1))
    fi
    GRID_BAND_TEST="$REPO/test/office-grid-band.py"
    "$BOX_PY" "$GRID_BAND_TEST" --binary "$BIN" || fails=$((fails + 1))
    if "$BOX_PY" "$GRID_BAND_TEST" --fixture "$WORK/grid-band.docx"; then
        printf '%s\n' "$WORK/grid-band.docx" > "$WORK/grid-band.txt"
        if PORT="$DEVTOOLS_PORT" node "$DRIVE" wait 6000 pdfs "$WORK/grid-band.txt" "$WORK/grid-band-pdfs" > "$WORK/grid-band.log" 2>&1 \
            && "$BOX_PY" "$GRID_BAND_TEST" --pdf "$WORK/grid-band-pdfs/grid-band.pdf"; then
            echo "  ✔ Grid/table clearance: native and browser match the Word controls and avoid later-line overlap"
        else
            echo "  ✘ Grid/table clearance or later-line safety differs"
            tail -3 "$WORK/grid-band.log"
            fails=$((fails + 1))
        fi
    else
        fails=$((fails + 1))
    fi
    MINIMUM_TEST="$REPO/test/office-minimum-baseline.py"
    "$BOX_PY" "$MINIMUM_TEST" --binary "$BIN" || fails=$((fails + 1))
    if "$BOX_PY" "$MINIMUM_TEST" --fixture "$WORK/minimum-baseline.docx"; then
        printf '%s\n' "$WORK/minimum-baseline.docx" > "$WORK/minimum-baseline.txt"
        if PORT="$DEVTOOLS_PORT" node "$DRIVE" wait 6000 pdfs "$WORK/minimum-baseline.txt" "$WORK/minimum-baseline-pdfs" > "$WORK/minimum-baseline.log" 2>&1 \
            && "$BOX_PY" "$MINIMUM_TEST" --pdf "$WORK/minimum-baseline-pdfs/minimum-baseline.pdf"; then
            echo "  ✔ Minimum line baselines: native and browser match the Word controls"
        else
            echo "  ✘ Minimum line baselines differ from the Word controls"
            tail -3 "$WORK/minimum-baseline.log"
            fails=$((fails + 1))
        fi
    else
        fails=$((fails + 1))
    fi
    PICTURE_TEXT_TEST="$REPO/test/office-picture-text-grid.py"
    "$BOX_PY" "$PICTURE_TEXT_TEST" --binary "$BIN" || fails=$((fails + 1))
    for size in 24 48; do
        name="picture-text-$size"
        if "$BOX_PY" "$PICTURE_TEXT_TEST" --size "$size" --fixture "$WORK/$name.docx"; then
            printf '%s\n' "$WORK/$name.docx" > "$WORK/$name.txt"
            if PORT="$DEVTOOLS_PORT" node "$DRIVE" wait 6000 pdfs "$WORK/$name.txt" "$WORK/$name-pdfs" > "$WORK/$name.log" 2>&1 \
                && "$BOX_PY" "$PICTURE_TEXT_TEST" --size "$size" --pdf "$WORK/$name-pdfs/$name.pdf"; then
                echo "  ✔ Grid pictures with ${size}pt text: native and browser match the Word controls"
            else
                echo "  ✘ Grid picture/text positions differ from the Word controls"
                tail -3 "$WORK/$name.log"
                fails=$((fails + 1))
            fi
        else
            fails=$((fails + 1))
        fi
    done
    EMPTY_LIST_TEST="$REPO/test/office-empty-list.py"
    "$BOX_PY" "$EMPTY_LIST_TEST" --binary "$BIN" || fails=$((fails + 1))
    if "$BOX_PY" "$EMPTY_LIST_TEST" --fixture "$WORK/empty-list.docx"; then
        printf '%s\n' "$WORK/empty-list.docx" > "$WORK/empty-list.txt"
        if PORT="$DEVTOOLS_PORT" node "$DRIVE" wait 6000 pdfs "$WORK/empty-list.txt" "$WORK/empty-list-pdfs" > "$WORK/empty-list.log" 2>&1 \
            && "$BOX_PY" "$EMPTY_LIST_TEST" --pdf "$WORK/empty-list-pdfs/empty-list.pdf"; then
            echo "  ✔ Empty list numbers: native and browser match the Word visibility/alignment controls"
        else
            echo "  ✘ Empty list visibility or alignment differs from the Word controls"
            tail -3 "$WORK/empty-list.log"
            fails=$((fails + 1))
        fi
    else
        fails=$((fails + 1))
    fi
    # This font-table rule is specific to the native Mac-reference mode.
    # Web runs author-font mode (WASI has no OFFICE_WORD_FONTS environment),
    # so it must not be compared with these Mac Word fallback baselines.
    FONT_ALT_TEST="$REPO/test/office-font-alternates.py"
    "$BOX_PY" "$FONT_ALT_TEST" --binary "$BIN" || fails=$((fails + 1))
    "$BOX_PY" "$REPO/test/office-missing-gb-fonts.py" --binary "$BIN" || fails=$((fails + 1))
    KINSOKU_TEST="$REPO/test/office-kinsoku-switch.py"
    "$BOX_PY" "$KINSOKU_TEST" --binary "$BIN" || fails=$((fails + 1))
    if "$BOX_PY" "$KINSOKU_TEST" --fixture "$WORK/kinsoku-no-fe.docx" --portable \
        && "$BOX_PY" "$KINSOKU_TEST" --fixture "$WORK/kinsoku-with-fe.docx" --fe-layout --portable; then
        printf '%s\n' "$WORK/kinsoku-no-fe.docx" "$WORK/kinsoku-with-fe.docx" > "$WORK/kinsoku.txt"
        if PORT="$DEVTOOLS_PORT" node "$DRIVE" wait 6000 pdfs "$WORK/kinsoku.txt" "$WORK/kinsoku-pdfs" > "$WORK/kinsoku.log" 2>&1 \
            && "$BOX_PY" "$KINSOKU_TEST" --pdf "$WORK/kinsoku-pdfs/kinsoku-no-fe.pdf" --portable \
            && "$BOX_PY" "$KINSOKU_TEST" --pdf "$WORK/kinsoku-pdfs/kinsoku-with-fe.pdf" --fe-layout --portable; then
            echo "  ✔ kinsoku: native and browser match Word with and without FE layout"
        else
            echo "  ✘ kinsoku line breaks differ from the Word controls"
            tail -3 "$WORK/kinsoku.log"
            fails=$((fails + 1))
        fi
    else
        fails=$((fails + 1))
    fi
    PIE_MOVE_TEST="$REPO/test/office-pie-label-move.py"
    "$BOX_PY" "$PIE_MOVE_TEST" --binary "$BIN" || fails=$((fails + 1))
    if "$BOX_PY" "$PIE_MOVE_TEST" --fixture "$WORK/pie-move.docx"; then
        printf '%s\n' "$WORK/pie-move.docx" > "$WORK/pie-move.txt"
        if PORT="$DEVTOOLS_PORT" node "$DRIVE" wait 6000 pdfs "$WORK/pie-move.txt" "$WORK/pie-move-pdfs" > "$WORK/pie-move.log" 2>&1 \
            && "$BOX_PY" "$PIE_MOVE_TEST" --pdf "$WORK/pie-move-pdfs/pie-move.pdf"; then
            echo "  ✔ flat-pie label moves: native and browser match the Word frame-boundary controls"
        else
            echo "  ✘ flat-pie label moves differ from the Word controls"
            tail -3 "$WORK/pie-move.log"
            fails=$((fails + 1))
        fi
    else
        fails=$((fails + 1))
    fi
else
    echo "  SKIPPED frame, opener, Latin-word, cell-word, grid-band, minimum-baseline, picture-text, empty-list, font-alternate, missing-GB-font, kinsoku and pie-label PDF checks — PyMuPDF unavailable (OFFICE_PYTHON=…)"
fi
[ "$fails" -eq 0 ]
