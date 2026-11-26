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
mk("ours", [(72, 100, "First line of "), (137, 100, "text"), (72, 120, "fine second line"), (72, 141.5, "Third line here")])
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

# Kashida: Word's print of a kashida-justified Arabic line draws the stretched
# joins with glyphs its text calls spaces; the line starts at their ink. A
# space over a dark shading in another colour than the text's is not ink.
"$PY" -W ignore - "$d" <<'P'
import os, sys, pymupdf as fitz
out = os.path.join(sys.argv[1], "k.pdf")
sys.path.insert(0, "test/tools"); sys.argv = ["wordcmp"]
import wordcmp
F = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
doc = fitz.open(); pg = doc.new_page()
pg.insert_text((72, 100), "     مرحبا", fontsize=14, fontname="dv", fontfile=F)
pg.draw_rect(fitz.Rect(72, 96, 100, 98), color=(0, 0, 0), fill=(0, 0, 0))     # the joins, in the text's black
pg.draw_rect(fitz.Rect(72, 126, 110, 142), color=(0, 0, 0.4), fill=(0, 0, 0.4))  # a dark cell
pg.insert_text((72, 140), "     مرحبا", fontsize=14, fontname="dv", fontfile=F, color=(1, 1, 0))
doc.save(out)
lines = wordcmp.extract(out, None)[0]
assert len(lines) == 2, [(l.y, l.x0) for l in lines]
assert abs(lines[0].x0 - 72) < 0.5, ("kashida line starts at its ink", lines[0].x0)
assert lines[1].x0 > 85, ("a space over a dark cell is not ink", lines[1].x0)
print("wordcmp kashida ok")
P

# The working folder takes no part: the same PDFs score alike from the
# checkout and from an empty folder, and the script never asks for it.
a=$("$PY" -W ignore test/tools/wordcmp.py x.docx --word $d/word.pdf --ours $d/ours.pdf --json)
b=$(cd $d && "$PY" -W ignore "$OLDPWD/test/tools/wordcmp.py" x.docx --word $d/word.pdf --ours $d/ours.pdf --json)
[ "$a" = "$b" ] || { echo "wordcmp: scores differ by working folder"; exit 1; }
! grep -n "getcwd" test/tools/wordcmp.py || { echo "wordcmp: reads the working folder"; exit 1; }
echo "wordcmp folder ok"
