#!/usr/bin/env python3
"""gen.py SRC.docx OUTDIR — lab pieexplode: lo-4d273731's 3-D pie (rotX 30, rotY 317, 56%/44%) with the pull
(c:explosion) 0/10/25/50 on ONE slice (the 44% one) or on ALL, at perspective 30 and 90.
Names: pie-<persp>-<one|all>-<pull>.docx"""
import sys, re, zipfile
src, out = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(src)
chart = z.read('word/charts/chart1.xml').decode('utf8')
for persp in (30, 90):
    for scope in ('one', 'all'):
        for pull in (0, 10, 25, 50):
            c = re.sub(r'<c:perspective val="\d+"\s*/>', '<c:perspective val="%d" />' % persp, chart)
            # series-level pull, then each point's own
            c = re.sub(r'(</c:spPr>\s*)<c:explosion val="\d+"\s*/>(\s*<c:dPt>)',
                       lambda m: m.group(1) + '<c:explosion val="%d" />' % (pull if scope == 'all' else 0) + m.group(2), c, count=1)
            def point(m):
                i = int(m.group(1))
                v = pull if (scope == 'all' or i == 1) else 0
                return m.group(0)[:m.start(2) - m.start(0)] + 'val="%d"' % v + m.group(0)[m.end(2) - m.start(0):]
            c = re.sub(r'<c:idx val="(\d)" />\s*<c:bubble3D val="0" />\s*<c:explosion (val="\d+")', point, c)
            c = re.sub(r'(</c:tx>\s*)<c:explosion val="25"\s*/>', lambda m: m.group(1) + '<c:explosion val="%d" />' % (pull if scope == 'all' else 0), c)
            name = 'pie-%d-%s-%d.docx' % (persp, scope, pull)
            o = zipfile.ZipFile('%s/%s' % (out, name), 'w', zipfile.ZIP_DEFLATED)
            for i in z.infolist():
                d = z.read(i.filename)
                if i.filename == 'word/charts/chart1.xml': d = c.encode('utf8')
                o.writestr(i.filename, d)
            o.close()
