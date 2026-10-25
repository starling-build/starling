#!/bin/bash
# test/docx-web-render.sh [IN_DIR] WORK [names…] — how the BROWSER build
# draws a Word document against how the native build draws it: every .docx
# in IN_DIR is exported to PDF twice — `OfficeApp --convert` natively, and
# File → Export → PDF in headless Chrome (build/tools/web-drive.mjs pdfs,
# one page for the whole sweep) — and test/pdf-diff scores each page: share
# of differing pixels. The two are one painter over two renderers, so the
# expected score is 0.00 and anything else is a difference between the
# builds: a font the page did not fetch, a picture the browser decodes
# otherwise, a line broken elsewhere. It says nothing about Word — that is
# test/docx-word-render.sh, on a Mac with Word; this carries its verdict on
# the native build over to the browser's.
#
# IN_DIR defaults to POI's corpus where test/docx-corpus.py puts it
# (~/.cache/starling/docx-corpus/in); WORK gets native/,
# web/, pairs/ (side-by-side PNGs of pages that differ) and render.tsv
# (name, pages, worst %, mean % — or NATIVE-FAIL / the browser's verdict).
# Rows already there are skipped, so a sweep resumes. Needs a native
# OfficeApp (OFFICE_APP), the web build staged with the skwasm that writes
# PDFs (docs/BUILDING.md §1.7), Chrome (CHROME), node, and pymupdf (PYTHON).
#   python3 test/docx-corpus.py            # fetches the corpus
#   test/docx-web-render.sh WORK
#   test/docx-web-render.sh apps/OfficeApp/Tests/OfficeAppTests/Fixtures WORK
# (Starling's own fonts, whatever this machine has: a harness pins them so no
# baseline moves with the machine — see OfficeFonts.fontSource.)
export OFFICE_FONT_SOURCE="${OFFICE_FONT_SOURCE:-bundled}"
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
if [ $# -le 1 ]; then
  IN="$HOME/.cache/starling/docx-corpus/in"; WORK="${1:?usage: $0 [IN_DIR] WORK [names]}"; shift $#
else
  IN=$1; WORK=$2; shift 2
fi
[ -d "$IN" ] || { echo "no documents in $IN (python3 test/docx-corpus.py fetches POI's)" >&2; exit 2; }
IN=$(cd "$IN" && pwd)
if [ "$(uname)" = Darwin ]; then
  APP="${OFFICE_APP:-$ROOT/apps/OfficeApp/.build/release/OfficeApp}"
  DIFF=("$WORK/pdf-diff")
  mkdir -p "$WORK"
  [ -x "$DIFF" ] || swiftc -O -o "$DIFF" "$HERE/pdf-diff.swift" 2>&1 | grep -E 'error:' && exit 1
else
  # The binary's own RUNPATH picks the engine (see test/pptx-app-render.sh).
  unset LD_LIBRARY_PATH
  APP="${OFFICE_APP:-$ROOT/.build-shared/x86_64-unknown-linux-gnu/release/OfficeApp}"
  DIFF=("${PYTHON:-python3}" "$HERE/pdf-diff.py")
fi
STAGE="$ROOT/.stage-web-OfficeApp"
[ -x "$APP" ] || { echo "no native OfficeApp at $APP" >&2; exit 2; }
[ -s "$STAGE/app.wasm" ] || { echo "no web build staged: build/web-app.sh OfficeApp --package apps/OfficeApp" >&2; exit 2; }
mkdir -p "$WORK/native" "$WORK/web" "$WORK/pairs"
touch "$WORK/render.tsv"
names=("$@"); [ ${#names[@]} -gt 0 ] || names=($(cd "$IN" && ls | grep -i '\.docx$' | grep -v '^~\$'))
: > "$WORK/web-list.txt"
for n in "${names[@]}"; do
  n=$(basename "$n"); base=${n%.*}
  grep -q "^$n	" "$WORK/render.tsv" && continue
  # A document the native build cannot draw has nothing to be compared with.
  [ -s "$WORK/native/$base.pdf" ] || timeout 120 "$APP" --convert "$IN/$n" "$WORK/native/$base.pdf" >/dev/null 2>&1
  [ -s "$WORK/native/$base.pdf" ] && echo "$IN/$n" >> "$WORK/web-list.txt"
done
python3 "$ROOT/build/tools/web-serve.py" "$STAGE" "${WEB_PORT:-8144}" >/dev/null 2>&1 & SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
sleep 1
URL="http://127.0.0.1:${WEB_PORT:-8144}/" PORT="${DEVTOOLS:-9344}" CHROME_PROFILE="$WORK/chrome-profile" \
  node "$ROOT/build/tools/web-drive.mjs" pdfs "$WORK/web-list.txt" "$WORK/web" > "$WORK/web-drive.log" 2>&1
kill $SERVER 2>/dev/null
for n in "${names[@]}"; do
  n=$(basename "$n"); base=${n%.*}
  grep -q "^$n	" "$WORK/render.tsv" && continue
  if [ ! -s "$WORK/native/$base.pdf" ]; then
    printf '%s\tNATIVE-FAIL\n' "$n" | tee -a "$WORK/render.tsv"
  elif [ ! -s "$WORK/web/$base.pdf" ]; then
    printf '%s\t%s\n' "$n" "$(grep "^$n	" "$WORK/web/web.tsv" | tail -1 | cut -f2- | cut -c1-120)" | tee -a "$WORK/render.tsv"
  else
    printf '%s\t%s\n' "$n" "$("${DIFF[@]}" "$WORK/native/$base.pdf" "$WORK/web/$base.pdf" "$WORK/pairs" 1 | tail -1)" | tee -a "$WORK/render.tsv"
  fi
done
awk -F'\t' '/summary/ { n++; if ($2 ~ /worst=0\.00%/) same++ } !/summary/ { other++ }
  END { printf "%d documents compared, %d identical on every page, %d not drawn by one side\n", n, same, other }' "$WORK/render.tsv"
