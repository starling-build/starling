#!/bin/bash
# gate-stamp.sh KIND BIN — one line "bin=<sha1 of BIN> scorer=<sha1 of the KIND's scorer files in THIS checkout>" (amd-8, 2026-11-25).
# A saved gate base (sheets, slides, Word rows) is written next to this line (file STAMP) and reused ONLY when the line computed now for
# the same base binary equals it. Why: the base scores are made by the scorer of whoever's checkout drew them, so a base drawn by a PR that
# edited the scorer (or by another binary) silently differed from a fresh draw (Sheets LIBRE_OFFICE-128382-0: 83.3 saved, 82.5 fresh).
# A cache without a STAMP counts as unknown and is redrawn. KIND: sheets | slides | rows.
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
case "${1:-}" in
  sheets) F="test/tools/sheets-sweep.py test/pdf-diff.py test/docx-line-match.py";;
  slides) F="test/pdf-diff.py test/pptx-line-match.py test/docx-line-match.py test/tools/pptx-combine.py test/pptx-app-render.sh";;
  rows)   F="test/tools/docx-pair.sh test/docx-line-match.py test/pdf-diff.py test/docx-visual.py test/tools/docx-combine.py";;
  *) echo "usage: gate-stamp.sh sheets|slides|rows BIN" >&2; exit 2;;
esac
[ -r "${2:-}" ] || { echo "gate-stamp: no binary $2" >&2; exit 2; }
S=$(cd "$ROOT" && cat $F 2>/dev/null | sha1sum | cut -c1-40)
# settings: the env knobs a render depends on (a base drawn without the gate's Windows fonts differed, 2026-11-25)
E="fonts=${OFFICE_WORD_FONTS:-} src=${OFFICE_FONT_SOURCE:-} nopairs=${PDFDIFF_NO_PAIRS:-} now=${OFFICE_NOW:-}"
echo "bin=$(sha1sum < "$2" | cut -c1-40) scorer=$S $E"
