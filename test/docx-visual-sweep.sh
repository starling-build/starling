#!/bin/bash
# test/docx-visual-sweep.sh WORK — the Word VISUAL gate over both corpora: every document is
# converted (docx-line-sweep.sh, into WORK/756/pdf and WORK/lo/pdf — PDFs already there are
# reused, so `SKIP_CONVERT=1` scores what a line sweep left), then test/docx-visual.py ranks
# the documents by their worst page against Word's print (see its header for the method).
# Writes WORK/756.visual and WORK/lo.visual (the committed copies are
# test/corpus/docx/scores/linux/*.visual) and the worst page of each document over 0.5% as a
# side-by-side PNG in WORK/*/pairs. PARALLEL = conversions at a time (default 48), the scoring
# uses every core. Needs pymupdf and numpy (PYTHON names an interpreter that has them).
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
WORK=${1:?usage: $0 WORK}
PY="${PYTHON:-python3}"
for set in 756 lo; do
  if [ $set = lo ]; then export DOCX_CORPUS="$ROOT/test/corpus/docx/lo"; else export DOCX_CORPUS="$ROOT/test/corpus/docx"; fi
  mkdir -p "$WORK/$set"
  if [ -z "$SKIP_CONVERT" ]; then PARALLEL="${PARALLEL:-48}" DOCX_LINE_MATCH=v2 "$HERE/docx-line-sweep.sh" "$WORK/$set" >/dev/null 2>&1; fi
  "$PY" -W ignore "$HERE/docx-visual.py" "$WORK/$set" "$DOCX_CORPUS/word-win" "$WORK/$set.visual" "$WORK/$set/pairs"
done
