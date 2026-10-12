#!/bin/bash
# test/xlsx-app-render.sh IN_DIR XL_DIR WORK [names…] — how this app PRINTS
# a workbook against how Excel prints it: every .xlsx in IN_DIR that has a
# NAME-orig.pdf in XL_DIR (Excel's "Entire Workbook" print to PDF, from
# test/xlsx-excel-render.sh) is exported by `OfficeApp --sheet-pdf` and
# test/pdf-diff.swift scores each page: share of differing pixels. The
# Sheets counterpart of test/pptx-app-render.sh, and read the same way —
# fonts, text fit and anti-aliasing cost every page a little, so the use is
# the ranking: the worst workbooks show what the app does not draw, or
# cuts into pages differently (a page Excel has and we do not counts as
# wholly different). Both sides stop at 20 pages (XLSX_MAX_PAGES). WORK
# gets our PDFs (pdf/), the side-by-side PNGs of pages over the threshold
# (pairs/), and render.tsv (name, pages, worst %, mean %); rows already
# there are skipped, so a sweep resumes. OFFICE_APP picks the binary.
#   test/xlsx-app-render.sh                  # the corpus in the repo, into ~/starling-xls-check/app
#   test/xlsx-app-render.sh WORK             # … into WORK
#   test/xlsx-app-render.sh test/corpus/xlsx/books test/corpus/xlsx/excel WORK [names…]
# The workbooks and Excel's PDFs of them are checked in under
# test/corpus/xlsx (its README says where they come from and how the PDFs
# were made); with fewer than three arguments those are what is swept.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
if [ $# -le 1 ]; then
  IN="$ROOT/test/corpus/xlsx/books"; XL="$ROOT/test/corpus/xlsx/excel"; WORK="${1:-$HOME/starling-xls-check/app}"
  shift $#
else
  IN=$1; XL=$2; WORK=$3; shift 3
fi
APP="${OFFICE_APP:-$ROOT/apps/OfficeApp/.build/release/OfficeApp}"
[ -d "$IN" ] && [ -d "$XL" ] || { echo "usage: $0 IN_DIR XL_DIR WORK [names]" >&2; exit 2; }
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
# (test/pptx-corpus-groups.py xlsx writes the lists from the baselines: every
# page 0.00% different from Excel's, and the rest), by the list of
# this machine's page diff. A matched workbook that no longer scores 0.00 has
# regressed: the sweep says which and exits 1.
LISTS="$ROOT/test/corpus/xlsx"; SUFFIX=-mupdf; [ "$(uname)" = Darwin ] && SUFFIX=
names=("$@")
if [ ${#names[@]} -eq 0 ] && [ -n "$CORPUS_GROUP" ]; then
  [ -f "$LISTS/$CORPUS_GROUP$SUFFIX.txt" ] || { echo "no list $LISTS/$CORPUS_GROUP$SUFFIX.txt" >&2; exit 2; }
  names=($(tr -d '\015' < "$LISTS/$CORPUS_GROUP$SUFFIX.txt"))
fi
[ ${#names[@]} -gt 0 ] || names=($(cd "$IN" && ls *.xlsx | grep -v '^~\$'))
touch "$WORK/render.tsv"
for n in "${names[@]}"; do
  n=$(basename "$n"); base=${n%.xlsx}
  [ -f "$XL/$base-orig.pdf" ] || continue
  grep -q "^$n	" "$WORK/render.tsv" && continue
  if ! out=$(SHEET_PDF_MAX_PAGES="${XLSX_MAX_PAGES:-20}" "$APP" --sheet-pdf "$IN/$n" "$WORK/pdf/$base.pdf" 2>&1); then
    printf '%s\tERROR\t%s\n' "$n" "$(echo "$out" | tail -1 | cut -c1-120)" | tee -a "$WORK/render.tsv"; continue
  fi
  s=$("${DIFF[@]}" "$XL/$base-orig.pdf" "$WORK/pdf/$base.pdf" "$WORK/pairs" 1 | tail -1)
  printf '%s\t%s\n' "$n" "$s" | tee -a "$WORK/render.tsv"
done
if [ "$CORPUS_GROUP" = matched ]; then
  lost=$(for n in "${names[@]}"; do grep "^$n	" "$WORK/render.tsv"; done | grep -v 'worst=0.00%')
  [ -z "$lost" ] || { echo "no longer matching Excel exactly:"; echo "$lost"; exit 1; }
fi
