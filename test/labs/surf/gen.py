"""surf lab (Windows 01QbbApP, for amd-4): lo-5afb220423472cb1 chart2 (surface3D) alone, view3D varied.
usage: gen.py SRC.docx OUTDIR"""
import sys, os, re, zipfile
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
V = {'x20y0': (20, 0), 'x20y20': (20, 20), 'x20y90': (20, 90), 'x20y170': (20, 170), 'x20y180': (20, 180), 'x20y270': (20, 270),
     'x0y20': (0, 20), 'x40y20': (40, 20)}
zin = zipfile.ZipFile(src)
for k, (rx, ry) in V.items():
    with zipfile.ZipFile(os.path.join(out, 'surf-%s.docx' % k), 'w', zipfile.ZIP_DEFLATED) as zo:
        for n in zin.namelist():
            data = zin.read(n)
            if n == 'word/document.xml':
                d = data.decode('utf-8')
                runs = re.findall(r'<w:r>(?:(?!</w:r>).)*?</w:r>', d, re.S)
                keep = [r for r in runs if 'r:id="rId6"' in r]
                assert len(keep) == 1, len(keep)
                for r in runs:
                    if r is not keep[0] and '<w:drawing>' in r:
                        d = d.replace(r, '', 1)
                data = d.encode('utf-8')
            elif n == 'word/charts/chart2.xml':
                c = data.decode('utf-8')
                c, m = re.subn(r'<c:rotX val="\d+"/><c:rotY val="\d+"/>', '<c:rotX val="%d"/><c:rotY val="%d"/>' % (rx, ry), c)
                assert m == 1
                data = c.encode('utf-8')
            zo.writestr(n, data)
print('ok')
