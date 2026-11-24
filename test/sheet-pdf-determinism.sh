#!/bin/bash
# test/sheet-pdf-determinism.sh [BOOK.xlsx…] — the same workbook printed three times,
# each in a fresh process, must give identical PDF bytes. Swift seeds its hashing
# per process, so a paint loop that walks a Dictionary or Set and draws as it goes
# makes the page differ run to run (the gate then sees noise). In-process tests
# cannot catch that: one process has one seed. OFFICE_APP picks the binary.
# Default books are ones that painted conditional-format and table fills in hash
# order before the fix; a missing book is skipped.
set -u
cd "$(dirname "$0")/.."
APP=${OFFICE_APP:-$PWD/.build-shared/x86_64-unknown-linux-gnu/release/OfficeApp}
C=${CORPUS:-/data/corpus-cache/test/corpus}
books=("$@")
[ ${#books[@]} -eq 0 ] && books=($C/xlsx-cjk-r3/ja-xlsx-r3-dev/ja-2a4d0d6b8a.xlsx $C/xlsx2/books/other-7d387a31b4.xlsx $C/xlsx2/books/pt-d05bc02fd0.xlsx)
export OFFICE_NOW_TABLE=$PWD/test/corpus/docx/clock.tsv OFFICE_FONT_SOURCE=bundled
unset SWIFT_DETERMINISTIC_HASHING
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
bad=0; ran=0
for b in "${books[@]}"; do
  [ -f "$b" ] || { echo "skip $(basename "$b") (not found)"; continue; }
  for i in 1 2 3; do "$APP" --sheet-pdf "$b" "$W/$i.pdf" >/dev/null 2>&1 || { echo "FAIL render $b"; bad=1; }; done
  n=$(md5sum "$W"/?.pdf 2>/dev/null | cut -c1-32 | sort -u | wc -l)
  ran=$((ran+1))
  if [ "$n" -eq 1 ]; then echo "ok   $(basename "$b")"; else echo "DIFF $(basename "$b"): $n different PDFs in 3 runs"; bad=1; fi
  rm -f "$W"/?.pdf
done
[ $ran -eq 0 ] && { echo "no books found"; exit 1; }
exit $bad
