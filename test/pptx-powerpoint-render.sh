#!/bin/bash
# test/pptx-powerpoint-render.sh IN_DIR OUT_DIR WORK [names…] — the pixel
# comparison through Microsoft PowerPoint: every .pptx in OUT_DIR (Slides'
# saved copies) and its namesake in IN_DIR (the originals) are exported to
# PDF by PowerPoint itself (test/pptx-powerpoint-pdf.applescript), then
# test/pdf-diff.swift renders both and scores each page: share of differing
# pixels. WORK gets the PDFs (flat: NAME-orig.pdf, NAME-ours.pdf), the
# side-by-side PNGs of pages that differ (pairs/), and render.tsv (name,
# verdicts, pages, worst %, mean %). A score is PowerPoint-vs-PowerPoint, so
# every difference is ours to explain — and a copy that PowerPoint repairs
# before drawing says "repaired" in the row.
#
# PowerPoint's sandbox writes only into the exact folder it has been granted
# (the "Grant File Access" dialog, once per folder — a subfolder made later
# is a new folder and blocks the export for 120s), so WORK must BE that
# folder: ~/starling-ppt-check on this Mac, hence the flat PDFs. The inputs
# can stay where they are, since `open -a` grants reads.
#   OFFICE_APP=… python3 test/pptx-corpus.py      # writes ~/.cache/starling/pptx-corpus/out
#   test/pptx-powerpoint-render.sh ~/.cache/starling/pptx-corpus/in \
#       ~/.cache/starling/pptx-corpus/out ~/starling-ppt-check [FILE.pptx ...]
# Rows already in render.tsv are skipped, so an interrupted sweep resumes.
IN=$1; OUT=$2; WORK=$3; shift 3; HERE=$(cd "$(dirname "$0")" && pwd)
[ -d "$IN" ] && [ -d "$OUT" ] || { echo "usage: $0 IN_DIR OUT_DIR WORK [names]" >&2; exit 2; }
mkdir -p "$WORK/pairs"
# On Windows (Git Bash) PowerPoint is driven over COM and the pages are
# diffed by MuPDF: test/pptx-powerpoint-pdf.ps1 and test/pdf-diff.py, which
# print what their Mac counterparts print. No sandbox there, so WORK can be
# any folder — but run this from a shell that is NOT elevated: an elevated
# client cannot reach a PowerPoint running as the desktop user, and the
# export fails with "Server execution failed".
if [ "$(uname)" = Darwin ]; then
  DIFF=("$WORK/pdf-diff")
  if [ ! -x "$DIFF" ]; then
    swiftc -O -o "$DIFF" "$HERE/pdf-diff.swift" 2>&1 | grep -E 'error:' && exit 1
  fi
  export_pdf() { osascript "$HERE/pptx-powerpoint-pdf.applescript" "$1" "$2" 2>&1; }
else
  DIFF=(python "$HERE/pdf-diff.py")
  export_pdf() {
    powershell -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$HERE/pptx-powerpoint-pdf.ps1")"       "$(cygpath -w "$1")" "$(cygpath -w "$2")" 2>&1 | tr -d ''
  }
fi
names=("$@"); [ ${#names[@]} -gt 0 ] || names=($(cd "$OUT" && ls *.pptx | grep -v '^~\$'))
touch "$WORK/render.tsv"
for n in "${names[@]}"; do
  n=$(basename "$n"); base=${n%.pptx}
  [ -f "$IN/$n" ] || { echo "skip $n: no original"; continue; }
  grep -q "^$n	" "$WORK/render.tsv" && continue
  r1=$(export_pdf "$IN/$n" "$WORK/$base-orig.pdf")
  r2=$(export_pdf "$OUT/$n" "$WORK/$base-ours.pdf")
  case "$r1|$r2" in
    pdf*\|pdf*) ;;
    *) printf '%s\tERROR\t%s / %s\n' "$n" "$r1" "$r2" | tee -a "$WORK/render.tsv"; continue ;;
  esac
  s=$("${DIFF[@]}" "$WORK/$base-orig.pdf" "$WORK/$base-ours.pdf" "$WORK/pairs" 1 | tail -1)
  printf '%s\t%s/%s\t%s\n' "$n" "${r1#pdf}" "${r2#pdf}" "$s" | sed 's/\t \?/\t/g' | tee -a "$WORK/render.tsv"
done
