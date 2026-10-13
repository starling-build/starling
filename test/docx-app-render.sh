#!/bin/bash
# test/docx-app-render.sh IN_DIR WORD_DIR WORK [names…] — how this app
# DRAWS a Word document against how Word prints it: every .docx in IN_DIR
# that has a NAME-orig.pdf in WORD_DIR (Word's own print to PDF, from
# test/docx-word-render.sh) is exported by `OfficeApp --convert NAME.docx
# NAME.pdf` and test/pdf-diff.swift scores each page: share of differing
# pixels. The Writer counterpart of test/pptx-app-render.sh and
# test/xlsx-app-render.sh, and read the same way — fonts and anti-aliasing
# cost every page a little, and one line broken elsewhere moves everything
# after it, so the use is the ranking: the worst documents show what the
# app does not draw, or breaks into pages differently (a page Word has and
# we do not counts as wholly different). It is NOT the round-trip gate:
# that is test/docx-word-render.sh, Word printing the original and our
# saved copy, where the expected score is 0.00. WORK gets our PDFs (pdf/),
# the side-by-side PNGs of pages over the threshold (pairs/), and
# render.tsv (name, pages, worst %, mean %); rows already there are
# skipped, so a sweep resumes. OFFICE_APP picks the binary.
#   test/docx-app-render.sh                  # the corpus in the repo, into ~/starling-doc-check/app
#   test/docx-app-render.sh WORK             # … into WORK
#   OFFICE_WEB=1 test/docx-app-render.sh WORK   # … drawn by the browser build
#   test/docx-app-render.sh test/corpus/docx/docs test/corpus/docx/word WORK [names…]
# The documents and Word's PDFs of them are checked in under
# test/corpus/docx (its README says where they come from and how the PDFs
# were made); with fewer than three arguments those are what is swept.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
if [ $# -le 1 ]; then
  IN="$ROOT/test/corpus/docx/docs"; WD="$ROOT/test/corpus/docx/word"; WORK="${1:-$HOME/starling-doc-check/app}"
  shift $#
else
  IN=$1; WD=$2; WORK=$3; shift 3
fi
APP="${OFFICE_APP:-$ROOT/apps/OfficeApp/.build/release/OfficeApp}"
[ -d "$IN" ] && [ -d "$WD" ] || { echo "usage: $0 IN_DIR WORD_DIR WORK [names]" >&2; exit 2; }
mkdir -p "$WORK/pdf" "$WORK/pairs"
# The page diff is CoreGraphics on a Mac and MuPDF anywhere else
# (test/pdf-diff.py: the same lines and threshold, another rasteriser — so
# a sweep is comparable with sweeps from the same kind of machine).
if [ "$(uname)" = Darwin ]; then
  DIFF=("$WORK/pdf-diff")
  if [ ! -x "$DIFF" ]; then
    swiftc -O -o "$DIFF" "$HERE/pdf-diff.swift" 2>&1 | grep -E 'error:' && exit 1
  fi
elif [ "$(uname)" = Linux ]; then
  unset LD_LIBRARY_PATH
  DIFF=("${PYTHON:-python3}" "$HERE/pdf-diff.py")
  [ -n "$OFFICE_APP" ] || [ -x "$APP" ] || APP="$ROOT/.build-shared/x86_64-unknown-linux-gnu/release/OfficeApp"
else
  DIFF=(python "$HERE/pdf-diff.py")
  [ -n "$OFFICE_APP" ] || [ -x "$APP" ] || APP="$ROOT/apps/OfficeApp/.build/x86_64-unknown-windows-msvc/release/OfficeApp.exe"
fi
# CORPUS_GROUP=matched or =others sweeps one of the corpus's two groups
# (test/pptx-corpus-groups.py docx writes the lists from the baselines:
# every page 0.00% different from Word's, and the rest), by the list of
# this machine's page diff. A matched document that no longer scores 0.00
# has regressed: the sweep says which and exits 1.
LISTS="$ROOT/test/corpus/docx"; SUFFIX=-mupdf; [ "$(uname)" = Darwin ] && SUFFIX=
names=("$@")
if [ ${#names[@]} -eq 0 ] && [ -n "$CORPUS_GROUP" ]; then
  [ -f "$LISTS/$CORPUS_GROUP$SUFFIX.txt" ] || { echo "no list $LISTS/$CORPUS_GROUP$SUFFIX.txt" >&2; exit 2; }
  while IFS= read -r l; do names+=("$l"); done < <(tr -d '\015' < "$LISTS/$CORPUS_GROUP$SUFFIX.txt")
fi
# (By line: a document's name may have spaces in it.)
[ ${#names[@]} -gt 0 ] || while IFS= read -r l; do names+=("$l"); done < <(cd "$IN" && ls *.docx | grep -v '^~\$')
touch "$WORK/render.tsv"
# OFFICE_WEB=1 sweeps the BROWSER build instead, as test/pptx-app-render.sh
# does: every document opened in headless Chrome and exported there
# (build/tools/web-drive.mjs pdfs), then scored against the same PDFs.
if [ -n "$OFFICE_WEB" ]; then
  STAGE="$ROOT/.stage-web-OfficeApp"
  [ -s "$STAGE/app.wasm" ] || { echo "no web build staged: build/web-app.sh OfficeApp --package apps/OfficeApp" >&2; exit 2; }
  : > "$WORK/web-list.txt"
  for n in "${names[@]}"; do
    n=$(basename "$n")
    [ -f "$WD/${n%.docx}-orig.pdf" ] || continue
    awk -F'\t' -v n="$n" '$1 == n { f = 1 } END { exit !f }' "$WORK/render.tsv" || echo "$IN/$n" >> "$WORK/web-list.txt"
  done
  python3 "$ROOT/build/tools/web-serve.py" "$STAGE" "${WEB_PORT:-8146}" >/dev/null 2>&1 & SERVER=$!
  trap 'kill $SERVER 2>/dev/null' EXIT
  sleep 1
  URL="http://127.0.0.1:${WEB_PORT:-8146}/" PORT="${DEVTOOLS:-9346}" CHROME_PROFILE="$WORK/chrome-profile" \
    node "$ROOT/build/tools/web-drive.mjs" pdfs "$WORK/web-list.txt" "$WORK/pdf" > "$WORK/web-drive.log" 2>&1
  kill $SERVER 2>/dev/null
fi
for n in "${names[@]}"; do
  n=$(basename "$n"); base=${n%.docx}
  [ -f "$WD/$base-orig.pdf" ] || continue
  awk -F'\t' -v n="$n" '$1 == n { f = 1 } END { exit !f }' "$WORK/render.tsv" && continue
  if [ -n "$OFFICE_WEB" ]; then
    [ -s "$WORK/pdf/$base.pdf" ] || {
      printf '%s\tERROR\t%s\n' "$n" "$(grep -F "$n	" "$WORK/pdf/web.tsv" | tail -1 | cut -f2- | cut -c1-120)" | tee -a "$WORK/render.tsv"; continue; }
  elif ! out=$(OFFICE_WORD_FONTS=mac "$APP" --convert "$IN/$n" "$WORK/pdf/$base.pdf" 2>&1); then
    printf '%s\tERROR\t%s\n' "$n" "$(echo "$out" | tail -1 | cut -c1-120)" | tee -a "$WORK/render.tsv"; continue
  fi
  s=$("${DIFF[@]}" "$WD/$base-orig.pdf" "$WORK/pdf/$base.pdf" "$WORK/pairs" 1 | tail -1)
  printf '%s\t%s\n' "$n" "$s" | tee -a "$WORK/render.tsv"
done
if [ "$CORPUS_GROUP" = matched ]; then
  lost=$(for n in "${names[@]}"; do awk -F'\t' -v n="$n" '$1 == n' "$WORK/render.tsv"; done | grep -v 'worst=0.00%')
  [ -z "$lost" ] || { echo "no longer matching Word exactly:"; echo "$lost"; exit 1; }
fi
