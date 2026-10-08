#!/bin/bash
# test/docx-word-render.sh IN_DIR OUT_DIR WORK — the pixel comparison through
# Microsoft Word: every .docx in IN_DIR (the originals) and its namesake in
# OUT_DIR (Writer's saved copies) are printed to PDF by Word itself
# (test/docx-word-pdf.applescript drives the print dialog, which read-only
# Word still allows), then test/pdf-diff.swift renders both and scores each
# page: share of differing pixels. WORK gets the PDFs, the side-by-side
# PNGs of pages that differ, and render.tsv (name, pages, worst %, mean %).
# A score is Word-vs-Word, so every difference is ours to explain.
#   python3 test/docx-corpus.py
#   cp ~/.cache/starling/docx-corpus/{in,out} under $HOME first (the sandbox)
#   test/docx-word-render.sh ~/w/in ~/w/out ~/w/render [FILE.docx ...]
IN=$1; OUT=$2; WORK=$3; shift 3; HERE=$(cd "$(dirname "$0")" && pwd)
[ -d "$IN" ] && [ -d "$OUT" ] || { echo "usage: $0 IN_DIR OUT_DIR WORK [names]" >&2; exit 2; }
mkdir -p "$WORK/pdf" "$WORK/pairs"
DIFF="$WORK/pdf-diff"
if [ ! -x "$DIFF" ]; then
  swiftc -O -o "$DIFF" "$HERE/pdf-diff.swift" 2>&1 | grep -E 'error:' && exit 1
fi
# When Word started (epoch seconds); launched here if it is not running.
pgrep -x 'Microsoft Word' >/dev/null || { open -a 'Microsoft Word'; sleep 8; }
WORD_START=$(ps -o lstart= -p "$(pgrep -x 'Microsoft Word' | head -1)" | xargs -I{} date -j -f '%a %b %d %T %Y' '{}' +%s)
[ -n "$WORD_START" ] || { echo "cannot read Word's start time" >&2; exit 2; }
names=("$@"); [ ${#names[@]} -gt 0 ] || names=($(cd "$OUT" && ls *.docx))
for n in "${names[@]}"; do
  n=$(basename "$n"); base=${n%.docx}
  [ -f "$IN/$n" ] || { echo "skip $n: no original"; continue; }
  # An original's PDF is reused only if this same Word session printed it:
  # Word rendered heading123's original 4.7% differently the day after
  # (Times substituted another way), which read as a regression in the
  # copy. Both sides come from one session, or the score means nothing.
  if [ -s "$WORK/pdf/$base-orig.pdf" ] && [ "$(stat -f %m "$WORK/pdf/$base-orig.pdf")" -gt "$WORD_START" ]; then r1=pdf
  else r1=$(osascript "$HERE/docx-word-pdf.applescript" "$IN/$n" "$WORK/pdf/$base-orig.pdf" 2>&1); fi
  r2=$(osascript "$HERE/docx-word-pdf.applescript" "$OUT/$n" "$WORK/pdf/$base-ours.pdf" 2>&1)
  if [ "$r1" != "pdf" ] || [ "$r2" != "pdf" ]; then
    printf '%s\tERROR\t%s / %s\n' "$n" "$r1" "$r2" | tee -a "$WORK/render.tsv"; continue
  fi
  s=$("$DIFF" "$WORK/pdf/$base-orig.pdf" "$WORK/pdf/$base-ours.pdf" "$WORK/pairs" 1 | tail -1)
  printf '%s\t%s\n' "$n" "$s" | tee -a "$WORK/render.tsv"
done
