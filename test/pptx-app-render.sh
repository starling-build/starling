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
#   test/pptx-app-render.sh ~/.cache/starling/pptx-corpus/in ~/starling-ppt-check ~/starling-ppt-check/app
IN=$1; PPT=$2; WORK=$3; shift 3; HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
APP="${OFFICE_APP:-$ROOT/apps/OfficeApp/.build/release/OfficeApp}"
[ -d "$IN" ] && [ -d "$PPT" ] || { echo "usage: $0 IN_DIR PPT_DIR WORK [names]" >&2; exit 2; }
mkdir -p "$WORK/pdf" "$WORK/pairs"
DIFF="$WORK/pdf-diff"
if [ ! -x "$DIFF" ]; then
  swiftc -O -o "$DIFF" "$HERE/pdf-diff.swift" 2>&1 | grep -E 'error:' && exit 1
fi
names=("$@"); [ ${#names[@]} -gt 0 ] || names=($(cd "$IN" && ls *.pptx | grep -v '^~\$'))
touch "$WORK/render.tsv"
for n in "${names[@]}"; do
  n=$(basename "$n"); base=${n%.pptx}
  [ -f "$PPT/$base-orig.pdf" ] || continue
  grep -q "^$n	" "$WORK/render.tsv" && continue
  if ! out=$("$APP" --deck-pdf "$IN/$n" "$WORK/pdf/$base.pdf" 2>&1); then
    printf '%s\tERROR\t%s\n' "$n" "$(echo "$out" | tail -1 | cut -c1-120)" | tee -a "$WORK/render.tsv"; continue
  fi
  s=$("$DIFF" "$PPT/$base-orig.pdf" "$WORK/pdf/$base.pdf" "$WORK/pairs" 1 | tail -1)
  printf '%s\t%s\n' "$n" "$s" | tee -a "$WORK/render.tsv"
done
