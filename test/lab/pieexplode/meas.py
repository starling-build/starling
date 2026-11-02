#!/usr/bin/env python3
"""meas.py DIR > PIEEXPLODE-WORD.tsv (Windows 01QbbApP). The 3-D pie is a raster with an alpha channel (810x406 px mapped to the image bbox); bbox of alpha>16 pixels = the whole pie (rim included),
peach-coloured pixels (r-b>50, r>g>b) = the 44% slice's top+side, mapped to page pt. Label centres from the text layer ('56%','44%'). cols: doc, pie L R T B, peach L R T B, 56% x y, 44% x y, image bbox."""
import sys, os, numpy as np, pymupdf
print('# doc\tpieL\tpieR\tpieT\tpieB\twidth\theight\tpeachL\tpeachR\tpeachT\tpeachB\tx56\ty56\tx44\ty44\timg_bbox_pt')
for f in sorted(os.listdir(sys.argv[1])):
    if not f.endswith('-orig.pdf'): continue
    doc = pymupdf.open(os.path.join(sys.argv[1], f)); p = doc[0]
    info = [i for i in p.get_image_info(xrefs=True) if i['width'] > 100]
    ii = info[0]; xr = ii['xref']; bb = ii['bbox']
    pm = pymupdf.Pixmap(doc, xr)
    if pm.alpha: pm = pymupdf.Pixmap(pm, 0)
    a = np.frombuffer(pm.samples, np.uint8).reshape(pm.height, pm.width, pm.n)
    sm = int(doc.xref_get_key(xr, 'SMask')[1].split()[0])   # the pie sits on a transparent ground: its alpha is the image's SMask plane
    sp = pymupdf.Pixmap(doc, sm)
    al = np.frombuffer(sp.samples, np.uint8).reshape(sp.height, sp.width)
    rgb = a[:, :, :3].astype(int)
    sx = (bb[2] - bb[0]) / pm.width; sy = (bb[3] - bb[1]) / pm.height
    def box(m):
        ys, xs = np.nonzero(m)
        if len(xs) == 0: return ('-',) * 4
        return (bb[0] + xs.min() * sx, bb[0] + (xs.max() + 1) * sx, bb[1] + ys.min() * sy, bb[1] + (ys.max() + 1) * sy)
    pie = box(al > 16)
    peach = box((al > 16) & (rgb[:, :, 0] - rgb[:, :, 2] > 50) & (rgb[:, :, 0] > rgb[:, :, 1]) & (rgb[:, :, 1] > rgb[:, :, 2]))
    lab = {}
    for w in p.get_text('words'):
        if w[4] in ('56%', '44%'): lab[w[4]] = ((w[0] + w[2]) / 2, (w[1] + w[3]) / 2)
    fm = lambda t: '%.1f' % t if t != '-' else '-'
    print('\t'.join([f[:-9]] + [fm(v) for v in pie] + ['%.1f' % (pie[1] - pie[0]), '%.1f' % (pie[3] - pie[2])] + [fm(v) for v in peach]
          + ['%.1f\t%.1f' % lab['56%'] if '56%' in lab else '-\t-', '%.1f\t%.1f' % lab['44%'] if '44%' in lab else '-\t-', '%.1f,%.1f,%.1f,%.1f' % tuple(bb)]))
