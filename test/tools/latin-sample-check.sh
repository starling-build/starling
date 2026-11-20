#!/bin/bash
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
# latin-sample-check.sh BASEBIN FIXBIN [JOBS] — land.sh's extra gate for line-break/layout code (amd-8, 2026-11-09).
# Line-break changes hit Latin-script documents that none of the six gate sets contain (004f6804b and ae17f84b6 dropped
# five 100-scored dx2 documents unseen). This renders a FIXED sample of dx2 documents (test/corpus/docx/dx2/latin-sample.txt:
# 3 per Latin-script language plus the documents those two commits broke) with the base and the fix binary in the pair's
# Windows settings, scores the official v2 line score against Word's prints, and exits 1 on any v2 drop, as the gated sets do.
#   LAND_ACCEPT_DROP=<whole stems> waives a named drop (same rule as land.sh). Needs PYTHON (venv with PyMuPDF), ENGINE_OUT.
#   STAGE: work folder (default /tmp/latin-sample-<pid>). The sample is chosen once: do not edit it to make a landing pass.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../.." && pwd)
BASEBIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); FIXBIN=$(cd "$(dirname "$2")" && pwd)/$(basename "$2"); JOBS=${3:-24}
PY=${PYTHON:-python3}; STAGE=${STAGE:-/tmp/latin-sample-$$}
C=${STARLING_CORPUS:-/data/corpus-cache}/staging/dx2; LIST=${LATIN_LIST:-$ROOT/test/corpus/docx/dx2/latin-sample.txt}
for d in ${ENGINE_OUT:-} engine/src/out/host_release; do [ -d "$d" ] && { EO=$(cd "$d" && pwd -P); break; }; done
[ -n "${EO:-}" ] || { echo "latin-sample: no engine out dir (ENGINE_OUT)" >&2; exit 2; }
[ -d "$C/docs" ] || { echo "latin-sample: no dx2 corpus at $C" >&2; exit 2; }
export OFFICE_NOW_TABLE=$ROOT/test/corpus/docx/clock.tsv OFFICE_FONT_SOURCE=bundled OFFICE_WORD_FONTS=windows
export STARLING_ICU=$EO/icudtl.dat STARLING_ENGINE_OUT=$EO FLUTTER_SWIFT_ENGINE_OUT=$EO LD_LIBRARY_PATH=$EO
rm -rf "$STAGE"; mkdir -p "$STAGE"
for side in base fix; do
  bin=$BASEBIN; [ $side = fix ] && bin=$FIXBIN
  W=$STAGE/$side; mkdir -p "$W/pdf" "$W/err"
  ( cd "$C/docs" && while IFS= read -r n; do [ -f "$C/word-win/$n-orig.pdf" ] && printf '%s\0' "$n.docx"; done < "$LIST" |
    xargs -0 -P "$JOBS" -I{} sh -c 'n="$1"; for try in 1 2; do rm -f "$3/pdf/${n%.docx}.pdf"; perl -e "alarm 300; exec @ARGV" "$2" --convert "$n" "$3/pdf/${n%.docx}.pdf" >/dev/null 2>/dev/null && exit 0; done; rm -f "$3/pdf/${n%.docx}.pdf"; echo "${n%.docx}" >> "$3/fail.txt"' _ {} "$bin" "$W" )
  DOCX_MATCH_JOBS=$JOBS DOCX_LINE_MATCH=v2 DOCX_WORD_REFS=$C/word-win $PY -W ignore -I "$ROOT/test/docx-line-match.py" "$W" > "$W/v2.txt" 2>"$W/v2.err"
done
nb=$(grep -c '%  lines ' "$STAGE/base/v2.txt"); nf=$(grep -c '%  lines ' "$STAGE/fix/v2.txt")
echo "latin-sample: $(wc -l < "$LIST") listed, scored base $nb, fix $nf"
[ "$nb" -gt 0 ] && [ "$nf" -gt 0 ] || { echo "latin-sample: NOTHING SCORED (see $STAGE)"; exit 1; }
if [ -s "$STAGE/fix/fail.txt" ]; then echo "latin-sample: fix renders FAILED: $(tr '\n' ' ' < "$STAGE/fix/fail.txt")"; exit 1; fi
$PY "$HERE/docx-cmp.py" "$STAGE/fix/v2.txt" "$STAGE/base/v2.txt" > "$STAGE/cmp.txt"; grep -E '^up |  UP |  DOWN ' "$STAGE/cmp.txt"
DOWNS=$(grep -E '^[[:space:]]+DOWN' "$STAGE/cmp.txt" | awk '{print $NF}' | sort -u)
BAD=""
for d in $DOWNS; do ok=0; for w in $(echo "${LAND_ACCEPT_DROP:-}" | tr ',' ' '); do [ "${w%.docx}" = "${d%.docx}" ] && ok=1; done; [ $ok = 1 ] || BAD="$BAD $d"; done
if [ -n "$BAD" ]; then echo "latin-sample: v2 DROPS (Latin-script dx2 sample):$BAD"; exit 1; fi
echo "latin-sample: clean"
