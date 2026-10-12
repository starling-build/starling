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
# Word's prints of the ORIGINALS are trusted only within the Word session
# that made them: both sides of a score come from one session, or the
# score means nothing. Word prints some originals differently from one
# session to the next — heading123 by 4.7%, delins 4.6%, bug59058 7.9%,
# drawing 19.7% (font substitution falling another way) — and WHICH ones
# differ changes per session: drawing was pixel-identical across two
# sessions and 19.7% off in the third. A cross-session cache behind one
# stable canary was tried on 2026-10-11 and reported two regressions
# that were only the cache (the canary passed while those two differed),
# so reuse across sessions is opt-in, for quick iteration on files known
# to be stable: DOCX_RENDER_REUSE=1 reuses kept prints once the CANARY
# original reprints identical, except the UNSTABLE names. Never commit a
# number measured that way.
UNSTABLE=" ${UNSTABLE:-heading123.docx delins.docx bug59058.docx drawing.docx} "
CANARY=${CANARY:-Styles.docx}; cbase=${CANARY%.docx}
MARK="$WORK/pdf/.trusted-$WORD_START"
if [ -n "$DOCX_RENDER_REUSE" ] && [ ! -e "$MARK" ] && [ ! -e "$MARK.no" ]; then
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
  trusted=/nonexistent
  if [ -n "$DOCX_RENDER_REUSE" ]; then trusted=$MARK; case "$UNSTABLE" in *" $n "*) trusted=/nonexistent ;; esac; fi
  if [ -s "$o" ] && [ "$o" -nt "$IN/$n" ] && { [ -e "$trusted" ] || [ "$(stat -f %m "$o")" -gt "$WORD_START" ]; }; then r1=pdf
  else r1=$(osascript "$HERE/docx-word-pdf.applescript" "$IN/$n" "$o" 2>&1); fi
  r2=$(osascript "$HERE/docx-word-pdf.applescript" "$OUT/$n" "$WORK/pdf/$base-ours.pdf" 2>&1)
  if [ "$r1" != "pdf" ] || [ "$r2" != "pdf" ]; then
    printf '%s\tERROR\t%s / %s\n' "$n" "$r1" "$r2" | tee -a "$WORK/render.tsv"; continue
  fi
  s=$("$DIFF" "$WORK/pdf/$base-orig.pdf" "$WORK/pdf/$base-ours.pdf" "$WORK/pairs" 1 | tail -1)
  # The two prints on different paper: a kept original from before Word's
  # print dialog changed its paper (see pdf-diff.swift). Print it again,
  # once, and score against that.
  case "$s" in *"paper=differs"*)
    rm -f "$WORK/pairs/pair-"*"-$base-ours-p"*.png
    r1=$(osascript "$HERE/docx-word-pdf.applescript" "$IN/$n" "$o" 2>&1)
    [ "$r1" = pdf ] && s=$("$DIFF" "$WORK/pdf/$base-orig.pdf" "$WORK/pdf/$base-ours.pdf" "$WORK/pairs" 1 | tail -1) ;;
  esac
  printf '%s\t%s\n' "$n" "$s" | tee -a "$WORK/render.tsv"
done
