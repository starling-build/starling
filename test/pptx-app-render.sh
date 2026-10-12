#!/bin/bash
# test/pptx-app-render.sh IN_DIR PPT_DIR WORK [names…] — how this app DRAWS
# a deck against how PowerPoint draws it: every .pptx in IN_DIR that has a
# NAME-orig.pdf in PPT_DIR (PowerPoint's export, from
# test/pptx-powerpoint-render.sh) is exported by `OfficeApp --deck-pdf` and
# test/pdf-diff.swift scores each page: share of differing pixels. Where the
# render gate measures the WRITER (PowerPoint vs PowerPoint), this measures
# the PAINTER (us vs PowerPoint), so the scores are larger — fonts, text
# wrap and anti-aliasing differ — and the use is the ranking: the worst
# decks show what the app does not draw at all. WORK gets our PDFs (pdf/),
# the side-by-side PNGs of pages over the threshold (pairs/), and
# render.tsv (name, pages, worst %, mean %); rows already there are
# skipped, so a sweep resumes. OFFICE_APP picks the binary.
#   test/pptx-app-render.sh                  # the corpus in the repo, into ~/starling-ppt-check/app
#   test/pptx-app-render.sh WORK             # … into WORK
#   OFFICE_WEB=1 test/pptx-app-render.sh WORK   # … drawn by the browser build
#   test/pptx-app-render.sh test/corpus/pptx/decks test/corpus/pptx/powerpoint WORK [names…]
# The decks and PowerPoint's PDFs of them are checked in under
# test/corpus/pptx (its README says where they come from and how the PDFs
# were made); with fewer than three arguments those are what is swept.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
if [ $# -le 1 ]; then
  IN="$ROOT/test/corpus/pptx/decks"; PPT="$ROOT/test/corpus/pptx/powerpoint"; WORK="${1:-$HOME/starling-ppt-check/app}"
  shift $#
else
  IN=$1; PPT=$2; WORK=$3; shift 3
fi
APP="${OFFICE_APP:-$ROOT/apps/OfficeApp/.build/release/OfficeApp}"
[ -d "$IN" ] && [ -d "$PPT" ] || { echo "usage: $0 IN_DIR PPT_DIR WORK [names]" >&2; exit 2; }
mkdir -p "$WORK/pdf" "$WORK/pairs"
# The page diff is CoreGraphics on a Mac and MuPDF anywhere else
# (test/pdf-diff.py: the same lines and threshold, another rasteriser — so
# a sweep is comparable with sweeps from the same kind of machine). Under
# Git Bash the app is SwiftPM's Windows build, or OFFICE_APP.
if [ "$(uname)" = Darwin ]; then
  DIFF=("$WORK/pdf-diff")
  if [ ! -x "$DIFF" ]; then
    swiftc -O -o "$DIFF" "$HERE/pdf-diff.swift" 2>&1 | grep -E 'error:' && exit 1
  fi
elif [ "$(uname)" = Linux ]; then
  # What build/build-all.sh makes, and its own RUNPATH picking the engine:
  # an inherited LD_LIBRARY_PATH outranks it (the packaged terminal exports
  # one to every shell inside it, and with it an older engine). PYTHON names
  # an interpreter that has pymupdf, where the system's does not.
  unset LD_LIBRARY_PATH
  DIFF=("${PYTHON:-python3}" "$HERE/pdf-diff.py")
  [ -n "$OFFICE_APP" ] || [ -x "$APP" ] || APP="$ROOT/.build-shared/x86_64-unknown-linux-gnu/release/OfficeApp"
else
  DIFF=(python "$HERE/pdf-diff.py")
  [ -n "$OFFICE_APP" ] || [ -x "$APP" ] || APP="$ROOT/apps/OfficeApp/.build/x86_64-unknown-windows-msvc/release/OfficeApp.exe"
fi
# CORPUS_GROUP=matched or =others sweeps one of the corpus's two groups
# (test/pptx-corpus-groups.py writes the lists from the baselines: every
# page 0.00% different from PowerPoint's, and the rest), by the list of
# this machine's page diff. A matched deck that no longer scores 0.00 has
# regressed: the sweep says which and exits 1.
LISTS="$ROOT/test/corpus/pptx"; SUFFIX=-mupdf; [ "$(uname)" = Darwin ] && SUFFIX=
names=("$@")
if [ ${#names[@]} -eq 0 ] && [ -n "$CORPUS_GROUP" ]; then
  [ -f "$LISTS/$CORPUS_GROUP$SUFFIX.txt" ] || { echo "no list $LISTS/$CORPUS_GROUP$SUFFIX.txt" >&2; exit 2; }
  names=($(tr -d '\015' < "$LISTS/$CORPUS_GROUP$SUFFIX.txt"))
fi
[ ${#names[@]} -gt 0 ] || names=($(cd "$IN" && ls *.pptx | grep -v '^~\$'))
touch "$WORK/render.tsv"
# OFFICE_WEB=1 sweeps the BROWSER build instead: every deck opened in
# headless Chrome and exported there (build/tools/web-drive.mjs pdfs — one
# page for the whole sweep), then scored as the native PDFs are, so the
# rows compare with the same baseline. Needs the web build staged with the
# skwasm that writes PDFs (docs/BUILDING.md §1.7), Chrome (CHROME) and node.
if [ -n "$OFFICE_WEB" ]; then
  STAGE="$ROOT/.stage-web-OfficeApp"
  [ -s "$STAGE/app.wasm" ] || { echo "no web build staged: build/web-app.sh OfficeApp --package apps/OfficeApp" >&2; exit 2; }
  IN_ABS=$(cd "$IN" && pwd)   # Chrome reads a file only by its full path
  : > "$WORK/web-list.txt"
  for n in "${names[@]}"; do
    n=$(basename "$n")
    [ -f "$PPT/${n%.pptx}-orig.pdf" ] && ! grep -q "^$n	" "$WORK/render.tsv" && echo "$IN_ABS/$n" >> "$WORK/web-list.txt"
  done
  python3 "$ROOT/build/tools/web-serve.py" "$STAGE" "${WEB_PORT:-8143}" >/dev/null 2>&1 & SERVER=$!
  trap 'kill $SERVER 2>/dev/null' EXIT
  sleep 1
  URL="http://127.0.0.1:${WEB_PORT:-8143}/" PORT="${DEVTOOLS:-9343}" CHROME_PROFILE="$WORK/chrome-profile" \
    node "$ROOT/build/tools/web-drive.mjs" pdfs "$WORK/web-list.txt" "$WORK/pdf" > "$WORK/web-drive.log" 2>&1
  kill $SERVER 2>/dev/null
fi
for n in "${names[@]}"; do
  n=$(basename "$n"); base=${n%.pptx}
  [ -f "$PPT/$base-orig.pdf" ] || continue
  grep -q "^$n	" "$WORK/render.tsv" && continue
  if [ -n "$OFFICE_WEB" ]; then
    [ -s "$WORK/pdf/$base.pdf" ] || {
      printf '%s\tERROR\t%s\n' "$n" "$(grep "^$n	" "$WORK/pdf/web.tsv" | tail -1 | cut -f2- | cut -c1-120)" | tee -a "$WORK/render.tsv"; continue; }
  elif ! out=$("$APP" --deck-pdf "$IN/$n" "$WORK/pdf/$base.pdf" 2>&1); then
    printf '%s\tERROR\t%s\n' "$n" "$(echo "$out" | tail -1 | cut -c1-120)" | tee -a "$WORK/render.tsv"; continue
  fi
  s=$("${DIFF[@]}" "$PPT/$base-orig.pdf" "$WORK/pdf/$base.pdf" "$WORK/pairs" 1 | tail -1)
  printf '%s\t%s\n' "$n" "$s" | tee -a "$WORK/render.tsv"
done
if [ "$CORPUS_GROUP" = matched ]; then
  lost=$(for n in "${names[@]}"; do grep "^$n	" "$WORK/render.tsv"; done | grep -v 'worst=0.00%')
  [ -z "$lost" ] || { echo "no longer matching PowerPoint exactly:"; echo "$lost"; exit 1; }
fi
