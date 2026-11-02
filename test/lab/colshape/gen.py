#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR — lab colshape: lo-8743d336's 3-D column chart (4 categories x 3 series) with each column shape
(cylinder as the control, cone, pyramid, coneToMax, pyramidToMax) at two views: A = the file's own (rAngAx 1, rotX/rotY
default), B = rotX 30, rotY 40, rAngAx 0, perspective 30. Names: colshape-<shape>-<A|B>.docx
Question: how Word draws each shape — the apex, the base, how the ToMax kinds narrow, the cap, the shading across."""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart = z.read('word/charts/chart1.xml').decode('utf8')
views = {'A': '<c:view3D><c:rAngAx val="1"/></c:view3D>',
         'B': '<c:view3D><c:rotX val="30"/><c:rotY val="40"/><c:rAngAx val="0"/><c:perspective val="30"/></c:view3D>'}
for shape in ('cylinder', 'cone', 'pyramid', 'coneToMax', 'pyramidToMax'):
    for v, xml in views.items():
        c = re.sub(r'<c:view3D>.*?</c:view3D>', lambda m: xml, chart, count=1, flags=re.S)
        c = re.sub(r'<c:shape val="\w+"/>', '<c:shape val="%s"/>' % shape, c)
        assert '<c:shape val="%s"/>' % shape in c
        o = zipfile.ZipFile('%s/colshape-%s-%s.docx' % (out, shape, v), 'w', zipfile.ZIP_DEFLATED)
        for i in z.infolist():
            d = z.read(i.filename)
            if i.filename == 'word/charts/chart1.xml': d = c.encode('utf8')
            o.writestr(i.filename, d)
        o.close()
