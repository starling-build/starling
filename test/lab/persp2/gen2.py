#!/usr/bin/env python3
"""gen2.py PERSP_DOCS_DIR OUTDIR — lab persp2 (for amd-opus, amd-3): the persp docs of lab persp (wip/lab-persp) with ALL THREE axes
deleted (c:delete 1 on catAx/valAx/serAx) and no legend, so that only the 3-D box is in the plot area. Question: with nothing but
the box, is its drawn height constant across turns (as amd-opus found on the surface chart), and what scale / centre does the room
give per view and frame? Compare lab persp, where the box plus its labels was fitted (box height 201.8/213.8/224.8 at turn 40/20/70).
Names persp2-<id>.docx, id as in lab persp (views v<rotX>-<rotY>-p<persp>, frames f<w>x<h>-v<rotX>-<rotY>, groupings g<cat>x<ser>, stacked)."""
import sys, re, zipfile, os
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
IDS = ['v%d-%d-p30' % (a, b) for a in (15, 30, 45) for b in (20, 40, 70)] + ['v30-40-p0', 'v30-40-p60', 'f288x216-v30-40', 'f540x324-v30-40',
       'f540x324-v15-20', 'g8x1', 'g2x5', 'stacked', 'hp50', 'hp100']
for i in IDS:
    z = zipfile.ZipFile('%s/persp-%s.docx' % (src, i))
    o = zipfile.ZipFile('%s/persp2-%s.docx' % (out, i), 'w', zipfile.ZIP_DEFLATED)
    for it in z.infolist():
        d = z.read(it.filename)
        if it.filename == 'word/charts/chart1.xml':
            c = d.decode('utf8')
            c = re.sub(r'(<c:(?:catAx|valAx|serAx)><c:axId val="\d+"/><c:scaling>.*?</c:scaling>)', r'\1<c:delete val="1"/>', c, flags=re.S)
            c = re.sub(r'<c:legend>.*?</c:legend>', '', c, flags=re.S)
            assert c.count('<c:delete val="1"/>') >= 2
            d = c.encode('utf8')
        o.writestr(it.filename, d)
    o.close()
print(len(IDS), 'docs')
