#!/usr/bin/env python3
"""lab p3bx (for windows: PowerPoint prints, page 2 of each deck): where PowerPoint puts the 3-D bar box inside a laid inner plot.
Source: LIBRE_OFFICE-100610-0 slide 2 chart12 (frame 496.7 pt, 404.7 wide; inner plot x .1219, w .8567; rotX 15 rotY 20; three series).
Known (lab bar3dbox): plot w .4/.6/.857/.95 put the box's left at -/+14.6/16/21.8/-4.1 pt from the plot's left, the box's total width
167.7/183.5/280.7/309.4 pt. Questions: the curve between (w50 w70 w80 w90 w100), and whether the data labels (shown at the bar ends) take part
(nl-*: showVal 0)."""
import zipfile, sys, os
SRC = "test/corpus/pptx/decks/LIBRE_OFFICE-100610-0.pptx"
W0 = '<c:w val="0.856702619414484"/>'
def w(v): return lambda x: x.replace(W0, '<c:w val="%s"/>' % v, 1)
def nolab(f): return lambda x: f(x).replace('<c:showVal val="1"/>', '<c:showVal val="0"/>')
V = {"w50": w(0.5), "w70": w(0.7), "w80": w(0.8), "w90": w(0.9), "w100": w(1.0),
     "nl-orig": nolab(lambda x: x), "nl-w60": nolab(w(0.6)), "nl-w95": nolab(w(0.95))}
os.makedirs("test/labs/p3bx/decks", exist_ok=True)
for k, f in V.items():
    zi = zipfile.ZipFile(SRC)
    with zipfile.ZipFile("test/labs/p3bx/decks/p3bx-%s.pptx" % k, "w", zipfile.ZIP_DEFLATED) as zo:
        for it in zi.infolist():
            b = zi.read(it.filename)
            if it.filename == "ppt/charts/chart12.xml":
                t = b.decode(); n = f(t)
                if n == t: sys.exit("no change " + k)
                b = n.encode()
            zo.writestr(it, b)
