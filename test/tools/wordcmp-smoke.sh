#!/bin/bash
# Smoke test for wordcmp: two tiny PDFs (split spans + a shifted line), no corpus needed.
set -e
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
PY=${PYTHON:-$HOME/venv-word/bin/python}; [ -x "$PY" ] || PY=python3
"$PY" -W ignore - "$d" <<'P'
import sys, pymupdf as fitz
d = sys.argv[1]
def mk(name, rows):
    doc = fitz.open(); pg = doc.new_page()
    for x, y, t in rows:
        pg.insert_text((x, y), t, fontsize=11)
    doc.save(f"{d}/{name}.pdf")
mk("word", [(72, 100, "First line of text"), (72, 120, "fine second line"), (72, 140, "Third line here")])
mk("ours", [(72, 100, "First line of "), (150, 100, "text"), (72, 120, "fine second line"), (72, 141.5, "Third line here")])
P
out=$("$PY" -W ignore test/tools/wordcmp.py x.docx --word $d/word.pdf --ours $d/ours.pdf --json)
echo "$out" | "$PY" -c '
import json, sys
j = json.load(sys.stdin); s = j["summary"]
assert s["word_lines"] == 3 and s["our_lines"] == 3, s
fd = s["first_diverging"]
assert fd and fd["text"].startswith("Thirdline") and abs(fd["dy"] - 1.5) < 0.01, fd
assert s["matched"] == 2, s
print("wordcmp smoke ok")'
