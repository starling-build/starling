#!/bin/bash
# test/docx-line-sweep.sh WORK [names…] — the line-match sweep: every document of
# the corpus that has a Word print is converted by `OfficeApp --convert` into
# WORK/pdf (PARALLEL at a time, 300 s each) and test/docx-line-match.py scores the
# result into WORK/match.txt. Failures go to WORK/fail.txt.
#   DOCX_CORPUS   the corpus to sweep: a folder holding docs/ (the .docx files) and
#                 the Word prints in word-win/ (NAME-orig.pdf). Default
#                 test/corpus/docx, the official 756; test/corpus/docx/lo is the
#                 LibreOffice set, scored apart and never folded into the mean.
#   DOCX_REFS     the prints, if not $DOCX_CORPUS/word-win
#   OFFICE_APP    the binary (default .build-shared's release one)
#   PARALLEL      conversions at a time (default 4: three sessions share the box)
#   OFFICE_WORD_FONTS (default windows), DOCX_LINE_MATCH (default v2: the official
#   matcher), OFFICE_FONT_SOURCE (default bundled).
# Pin STARLING_ICU, STARLING_ENGINE_OUT and FLUTTER_SWIFT_ENGINE_OUT to the engine
# the binary was built against.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
CORPUS=$(cd "${DOCX_CORPUS:-$ROOT/test/corpus/docx}" && pwd) || exit 2
REFS="${DOCX_REFS:-$CORPUS/word-win}"
APP="${OFFICE_APP:-$ROOT/.build-shared/x86_64-unknown-linux-gnu/release/OfficeApp}"
[ -d "$CORPUS/docs" ] && [ -d "$REFS" ] && [ -x "$APP" ] || { echo "usage: [DOCX_CORPUS=dir] $0 WORK [names]; needs $CORPUS/docs, $REFS and $APP" >&2; exit 2; }
WORK=$1; shift
mkdir -p "$WORK/pdf"; : > "$WORK/fail.txt"
export OFFICE_FONT_SOURCE="${OFFICE_FONT_SOURCE:-bundled}" OFFICE_WORD_FONTS="${OFFICE_WORD_FONTS:-windows}"
unset LD_LIBRARY_PATH
cd "$CORPUS/docs" || exit 2
if [ $# -gt 0 ]; then printf '%s\n' "$@"; else ls *.docx; fi | while IFS= read -r n; do
  [ -f "$REFS/${n%.docx}-orig.pdf" ] && echo "$n"; done |
  xargs -d '\n' -P "${PARALLEL:-4}" -I{} sh -c 'n="$1"; timeout 300 "$2" --convert "$n" "$3/pdf/${n%.docx}.pdf" >/dev/null 2>&1 || echo "FAIL $n"' _ {} "$APP" "$WORK" >> "$WORK/fail.txt"
DOCX_LINE_MATCH="${DOCX_LINE_MATCH:-v2}" DOCX_WORD_REFS="$REFS" "${PYTHON:-python3}" "$HERE/docx-line-match.py" "$WORK" > "$WORK/match.txt"
tail -5 "$WORK/match.txt"
[ -s "$WORK/fail.txt" ] && { echo "CONVERSION FAILURES:"; cat "$WORK/fail.txt"; }
exit 0
