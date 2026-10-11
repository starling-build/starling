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
# Word's prints of the ORIGINALS are kept across Word sessions. They were
# once trusted only within the session that made them, and every relaunch
# then reprinted every original, 180 pages of bug65649 included. Measured
# 2026-10-11: 13 of 15 originals reprint pixel-identically in a later
# session; two do not — heading123 (its "Times" is substituted another
# way from one session to the next, 4.7%) and delins (its tracked-change
# balloons, 4.6%). So: the UNSTABLE originals are reprinted every session,
# and the rest are reused behind a canary — each new session reprints one
# small stable original and compares it with its kept print: identical,
# and the kept prints are trusted for the session; different (a Word
# update, a font change), and the session reprints everything.
# CANARY names the file; DOCX_RENDER_FRESH=1 reprints all.
UNSTABLE=" ${UNSTABLE:-heading123.docx delins.docx} "
CANARY=${CANARY:-Styles.docx}; cbase=${CANARY%.docx}
MARK="$WORK/pdf/.trusted-$WORD_START"
if [ -z "$DOCX_RENDER_FRESH" ] && [ ! -e "$MARK" ] && [ ! -e "$MARK.no" ]; then
  if [ -s "$WORK/pdf/$cbase-orig.pdf" ] && [ -f "$IN/$CANARY" ]; then
    r=$(osascript "$HERE/docx-word-pdf.applescript" "$IN/$CANARY" "$WORK/pdf/canary-check.pdf" 2>&1)
    c=$([ "$r" = pdf ] && "$DIFF" "$WORK/pdf/$cbase-orig.pdf" "$WORK/pdf/canary-check.pdf" "$WORK/pdf" 1 | tail -1)
    # (A print that failed decides nothing: the next run asks again.)
    case "$c" in *"mean=0.00%"*) : > "$MARK" ;; *"mean="*) : > "$MARK.no"; echo "canary differs ($c): reprinting originals this session" >&2 ;; *) echo "canary print failed ($r): originals reprinted this run" >&2 ;; esac
  else : > "$MARK.no"; fi
fi
names=("$@"); [ ${#names[@]} -gt 0 ] || names=($(cd "$OUT" && ls *.docx))
for n in "${names[@]}"; do
  n=$(basename "$n"); base=${n%.docx}
  [ -f "$IN/$n" ] || { echo "skip $n: no original"; continue; }
  # Reuse the kept print when this session is trusted (or made it) and
  # the original has not changed since.
  o="$WORK/pdf/$base-orig.pdf"
  trusted=$MARK; case "$UNSTABLE" in *" $n "*) trusted=/nonexistent ;; esac
  if [ -s "$o" ] && [ "$o" -nt "$IN/$n" ] && [ -z "$DOCX_RENDER_FRESH" ] && { [ -e "$trusted" ] || [ "$(stat -f %m "$o")" -gt "$WORD_START" ]; }; then r1=pdf
  else r1=$(osascript "$HERE/docx-word-pdf.applescript" "$IN/$n" "$o" 2>&1); fi
  r2=$(osascript "$HERE/docx-word-pdf.applescript" "$OUT/$n" "$WORK/pdf/$base-ours.pdf" 2>&1)
  if [ "$r1" != "pdf" ] || [ "$r2" != "pdf" ]; then
    printf '%s\tERROR\t%s / %s\n' "$n" "$r1" "$r2" | tee -a "$WORK/render.tsv"; continue
  fi
  s=$("$DIFF" "$WORK/pdf/$base-orig.pdf" "$WORK/pdf/$base-ours.pdf" "$WORK/pairs" 1 | tail -1)
  printf '%s\t%s\n' "$n" "$s" | tee -a "$WORK/render.tsv"
done
