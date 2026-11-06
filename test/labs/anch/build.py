#!/usr/bin/env python3
"""Lab anch builder: where Word puts an empty wrapNone box when its paragraph's line is pushed under a wrapping chart in the same paragraph.
Starts from src/base.docx (lo-7b8ccfbe: box 6.4pt, chart 9.0pt, wrapSquare, 465x354pt chart). usage: build.py OUTDIR"""
import sys, os, re, zipfile
BOX, CH = 81264, 114844    # EMU offsets of the box and chart in base.docx
TIGHT = ('<wp:wrapTight wrapText="bothSides"><wp:wrapPolygon edited="0"><wp:start x="0" y="0"/><wp:lineTo x="0" y="21600"/>'
         '<wp:lineTo x="21600" y="21600"/><wp:lineTo x="21600" y="0"/><wp:lineTo x="0" y="0"/></wp:wrapPolygon></wp:wrapTight>')
E_ = lambda pt: int(round(pt * 12700))
# (code, description, box offset pt, chart offset pt, wrap, chart behindDoc)
V = [("A1", "ORIGINAL: box 6.4 (above chart top 9.0), square, chart in front", 6.4, 9.0, "square", 0),
     ("A2", "box 32.1 (below chart top 9.0), square, in front",               32.1, 9.0, "square", 0),
     ("A3", "box 6.4, TIGHT, in front",                                        6.4, 9.0, "tight", 0),
     ("A4", "box 32.1, TIGHT, in front",                                       32.1, 9.0, "tight", 0),
     ("A5", "box 6.4, square, chart BEHIND text",                              6.4, 9.0, "square", 1),
     ("A6", "box 32.1, square, chart BEHIND text",                             32.1, 9.0, "square", 1),
     ("A7", "box 6.4, tight, chart behind",                                    6.4, 9.0, "tight", 1),
     ("A8", "box 32.1, tight, chart behind (the zh-d62da4dd shape)",           32.1, 9.0, "tight", 1),
     ("A9", "chart 60 down, box 32.1 (box ABOVE chart top), square, front",    32.1, 60.0, "square", 0),
     ("A10", "chart 60 down, box 90 (box BELOW chart top), square, front",     90.0, 60.0, "square", 0),
     ("A11", "chart 0 down, box 0 (both at the paragraph top), square, front", 0.0, 0.0, "square", 0)]
def make(src, out, box, ch, wrap, behind):
    zi = zipfile.ZipFile(src)
    d = zi.read("word/document.xml").decode("utf8")
    parts = re.split(r"(?=<wp:anchor )", d)       # parts[1] = box anchor, parts[2] = chart anchor
    assert len(parts) == 3
    parts[1] = parts[1].replace(f"<wp:posOffset>{BOX}</wp:posOffset>", f"<wp:posOffset>{E_(box)}</wp:posOffset>")
    c = parts[2].replace(f"<wp:posOffset>{CH}</wp:posOffset>", f"<wp:posOffset>{E_(ch)}</wp:posOffset>")
    c = c.replace('behindDoc="0"', f'behindDoc="{behind}"', 1)
    if wrap == "tight": c = c.replace('<wp:wrapSquare wrapText="bothSides"/>', TIGHT)
    parts[2] = c
    d2 = "".join(parts)
    assert d2 != d
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zo:
        for i in zi.infolist():
            zo.writestr(i, d2.encode("utf8") if i.filename == "word/document.xml" else zi.read(i.filename))
if __name__ == "__main__":
    os.makedirs(sys.argv[1], exist_ok=True)
    here = os.path.dirname(os.path.abspath(__file__))
    for code, desc, box, ch, wrap, behind in V:
        p = os.path.join(sys.argv[1], f"anch-{code}.docx"); make(os.path.join(here, "src/base.docx"), p, box, ch, wrap, behind); print(p, "-", desc)
