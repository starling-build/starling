#!/usr/bin/env python3
"""Lab smartfit (amd-7): how PowerPoint fits a SmartArt's text as its frame shrinks.
Each source deck (lo-smartart-missing-bullet pList2, lo-vertical-bracket-list, lo-smartart-vertical-block-list) is copied
with its SmartArt graphicFrame height (a:ext cy) stepped from 100% to 40% in 5% steps (width unchanged). Print each to PDF
in PowerPoint for Windows (File > Export > PDF, one slide), name NAME-NN.pdf (NN = step 00..12), and push them
(or the output of meas.py) to this branch.
gen.py SRC_DECKS_DIR OUT_DIR"""
import sys, re, zipfile, os
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
names = ['lo-smartart-missing-bullet', 'lo-vertical-bracket-list', 'lo-smartart-vertical-block-list']
for n in names:
    z = zipfile.ZipFile(os.path.join(src, n + '.pptx'))
    s = z.read('ppt/slides/slide1.xml').decode('utf-8')
    m = re.search(r'(<p:graphicFrame>.*?<p:xfrm><a:off x="(\d+)" y="(\d+)"/><a:ext cx="(\d+)" cy="(\d+)"/></p:xfrm>)', s, flags=re.S)
    assert m, n
    for k in range(13):
        f = 1.0 - 0.05 * k
        cy = int(int(m.group(5)) * f)
        # keep the frame's centre fixed
        y = int(int(m.group(3)) + (int(m.group(5)) - cy) / 2)
        new = m.group(1).replace('<a:off x="%s" y="%s"/><a:ext cx="%s" cy="%s"/>' % (m.group(2), m.group(3), m.group(4), m.group(5)),
                                 '<a:off x="%s" y="%d"/><a:ext cx="%s" cy="%d"/>' % (m.group(2), y, m.group(4), cy))
        s2 = s.replace(m.group(1), new)
        with zipfile.ZipFile(os.path.join(out, '%s-%02d.pptx' % (n, k)), 'w', zipfile.ZIP_DEFLATED) as zo:
            for nm in z.namelist():
                zo.writestr(nm, s2.encode('utf-8') if nm == 'ppt/slides/slide1.xml' else z.read(nm))
print('wrote', len(names) * 13, 'decks to', out)
