#!/usr/bin/env python3
"""lab bar3dbox (for windows: PowerPoint prints, page 2 of each deck only): variants of LIBRE_OFFICE-100610-0 slide 2 chart12
(3-D horizontal bars, axes deleted, rAngAx, rotX 15 rotY 20, inner plot manual x .1219 y .1906 w .8567 h .7484, three series 13, 6, 2).
Question: where PowerPoint puts the box (front face + depth) inside the inner plot, and how long the value axis runs.
Ours: front 562..842, depth 21; PowerPoint: front 569..828.5, depth 19.5 (frame at 496.7 pt, 404.7 wide).
Tags: orig; w40 w60 w95 (inner w); x02 (inner x .02); h40 (inner h); v26 v130 (values x2, x10); ry0 ry10 ry30 (rotY); rx0 rx30 (rotX); gap100 (gapWidth)."""
import zipfile, sys, os
SRC = "test/corpus/pptx/decks/LIBRE_OFFICE-100610-0.pptx"
def rep(a, b): return lambda x: x.replace(a, b, 1)
def vals(m):
    def f(x):
        for v in (13, 6, 2): x = x.replace('<c:v>%d</c:v>' % v, '<c:v>%d</c:v>' % (v * m), 1)
        return x
    return f
V = {"orig": lambda x: x,
 "w40": rep('<c:w val="0.856702619414484"/>', '<c:w val="0.4"/>'), "w60": rep('<c:w val="0.856702619414484"/>', '<c:w val="0.6"/>'),
 "w95": rep('<c:w val="0.856702619414484"/>', '<c:w val="0.95"/>'),
 "x02": rep('<c:x val="0.121935845356493"/>', '<c:x val="0.02"/>'), "h40": rep('<c:h val="0.748376623376623"/>', '<c:h val="0.4"/>'),
 "v26": vals(2), "v130": vals(10),
 "ry0": rep('<c:rotY val="20"/>', '<c:rotY val="0"/>'), "ry10": rep('<c:rotY val="20"/>', '<c:rotY val="10"/>'), "ry30": rep('<c:rotY val="20"/>', '<c:rotY val="30"/>'),
 "rx0": rep('<c:rotX val="15"/>', '<c:rotX val="0"/>'), "rx30": rep('<c:rotX val="15"/>', '<c:rotX val="30"/>'),
 "gap100": rep('<c:gapWidth val="0"/>', '<c:gapWidth val="100"/>')}
os.makedirs("test/lab/bar3dbox/decks", exist_ok=True)
for k, f in V.items():
    zi = zipfile.ZipFile(SRC)
    with zipfile.ZipFile("test/lab/bar3dbox/decks/bar3dbox-%s.pptx" % k, "w", zipfile.ZIP_DEFLATED) as zo:
        for it in zi.infolist():
            b = zi.read(it.filename)
            if it.filename == "ppt/charts/chart12.xml":
                t = b.decode(); n = f(t)
                if k != "orig" and n == t: sys.exit("no change " + k)
                b = n.encode()
            zo.writestr(it, b)
