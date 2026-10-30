#!/bin/bash
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
#
# test/tools/docx-sweep.sh WORK [-k KEYFILE] [-c] [-j JOBS] [-t] — convert corpus documents with
# Word for Windows' fonts into WORK/pdf (bundled faces, Windows mode) and score them against
# test/corpus/docx/word-win with test/docx-line-match.py, v1 into WORK/match.txt and v2 into
# WORK/match-v2.txt.
#
#   -k KEYFILE  only those documents: one key a line (a key or a prefix of one; "#" lines and
#               anything after a tab are ignored) — what test/tools/docx-select.py writes with
#               --keyfile, or a trace's documents (see -t)
#   -c          add the canary set (test/corpus/docx/canaries.txt) to them
#   -j JOBS     conversions at once (default 4: three sessions sweeping together fill the memory
#               at 8 each)
#   -t          trace instead of convert: lay each document out without writing its PDF
#               (`OfficeApp --trace-rules`), with OFFICE_RULE_TRACE=WORK/trace.tsv, and write the
#               documents that reached any rule to WORK/trace.keys. Nothing is scored.
#
# A cheap pair: select the documents a change can reach and add the canaries,
#     docx-select.py 'mode >= 15 and pagebreak_first_before > 0' --keyfile k.txt
#     docx-sweep.sh WORK-candidate -k k.txt -c ; (revert) ; docx-sweep.sh WORK-base -k k.txt -c
# or let the candidate say, with a RuleTrace.hit() on the branch it changed:
#     docx-sweep.sh WORK-trace -t ; docx-sweep.sh WORK-candidate -k WORK-trace/trace.keys -c
# The Windows box's confirmation sweep, over all 756, is still what a fix lands on.
#
# Environment: OFFICE_APP (the binary; default the repo's .build-shared one), STARLING_ICU or
# WORD_EO (the engine out directory holding icudtl.dat), PYTHON (default python3, with PyMuPDF).
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
APP=${OFFICE_APP:-$ROOT/.build-shared/x86_64-unknown-linux-gnu/release/OfficeApp}
PYTHON=${PYTHON:-python3}
JOBS=4; KEYFILE=; CANARIES=; TRACE=
WORK=${1:?usage: docx-sweep.sh WORK [-k KEYFILE] [-c] [-j JOBS] [-t]}; shift
while [ $# -gt 0 ]; do
  case $1 in
    -k) KEYFILE=$2; shift 2;;
    -c) CANARIES=1; shift;;
    -j) JOBS=$2; shift 2;;
    -t) TRACE=1; shift;;
    *) echo "unknown option $1" >&2; exit 2;;
  esac
done
ICU=${STARLING_ICU:-${WORD_EO:+$WORD_EO/icudtl.dat}}
[ -n "$ICU" ] || { echo "set STARLING_ICU (or WORD_EO, the engine out directory)" >&2; exit 2; }
[ -x "$APP" ] || { echo "no binary at $APP (set OFFICE_APP)" >&2; exit 2; }
DOCS=$ROOT/test/corpus/docx/docs; WIN=$ROOT/test/corpus/docx/word-win
mkdir -p "$WORK/pdf"; rm -f "$WORK/fail.txt" "$WORK/trace.tsv" "$WORK/trace.keys"
unset LD_LIBRARY_PATH
export OFFICE_FONT_SOURCE=bundled STARLING_ICU="$ICU" OFFICE_WORD_FONTS=windows

# The documents: every one with a Word for Windows print, or those the key file (and canaries) name.
names=$(cd "$DOCS" && ls *.docx | sed 's/\.docx$//' | while IFS= read -r b; do [ -f "$WIN/$b-orig.pdf" ] && echo "$b"; done)
if [ -n "$KEYFILE$CANARIES" ]; then
  keys=$( { [ -n "$KEYFILE" ] && sed 's/\t.*//; /^#/d; /^[[:space:]]*$/d' "$KEYFILE"
            [ -n "$CANARIES" ] && sed 's/\t.*//; /^#/d; /^[[:space:]]*$/d' "$ROOT/test/corpus/docx/canaries.txt"; } | sort -u)
  names=$(echo "$names" | awk -v keys="$keys" 'BEGIN { n = split(keys, K, "\n") } { for (i = 1; i <= n; i++) if (K[i] != "" && index($0, K[i]) == 1) { print; next } }')
fi
count=$(echo "$names" | grep -c .)
echo "$count documents"

if [ -n "$TRACE" ]; then
  : > "$WORK/trace.tsv"
  export OFFICE_RULE_TRACE="$WORK/trace.tsv"
  echo "$names" | xargs -P "$JOBS" -I{} sh -c 'timeout 300 "'"$APP"'" --trace-rules "'"$DOCS"'/{}.docx" >/dev/null 2>&1 || echo "FAIL {}"' > "$WORK/fail.txt"
  cut -f1 "$WORK/trace.tsv" | sort -u > "$WORK/trace.keys"
  echo "$(wc -l < "$WORK/trace.keys") documents reached a rule ($(cut -f2 "$WORK/trace.tsv" | sort -u | wc -l) rules): $WORK/trace.keys"
  [ -s "$WORK/fail.txt" ] && { echo "FAILURES:"; cat "$WORK/fail.txt"; }
  exit 0
fi

echo "$names" | xargs -P "$JOBS" -I{} sh -c '
  rm -f "'"$WORK"'/pdf/{}.pdf"
  timeout 300 "'"$APP"'" --convert "'"$DOCS"'/{}.docx" "'"$WORK"'/pdf/{}.pdf" >/dev/null 2>"'"$WORK"'/pdf/{}.err" || echo "FAIL {}"' > "$WORK/fail.txt"
export DOCX_WORD_REFS=$WIN
$PYTHON "$ROOT/test/docx-line-match.py" "$WORK" > "$WORK/match.txt"
DOCX_LINE_MATCH=v2 $PYTHON "$ROOT/test/docx-line-match.py" "$WORK" > "$WORK/match-v2.txt"
echo "v1: $(head -1 "$WORK/match.txt")"
echo "v2: $(head -1 "$WORK/match-v2.txt")"
[ -s "$WORK/fail.txt" ] && { echo "CONVERSION FAILURES:"; cat "$WORK/fail.txt"; }
exit 0
