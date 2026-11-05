import sys, glob, os, pymupdf
# meas.py DIR > SBOX-WORD.tsv: per doc, per page: the shaded box (fill CCE5FF): top y, bottom y, x0, x1; and the baseline of its 'x'.
d = sys.argv[1]
print('# doc\tpages\tpage\tbox_top_y\tbox_bottom_y\tbox_x0\tbox_x1\tx_baseline')
for f in sorted(glob.glob(os.path.join(d, '*-orig.pdf'))):
    k = os.path.basename(f)[:-9]; doc = pymupdf.open(f)
    for pg in doc:
        boxes = []
        for dr in pg.get_drawings():
            fl = dr.get('fill')
            if fl and abs(fl[0]-0.8) < 0.02 and abs(fl[1]-0.9) < 0.02 and fl[2] > 0.98: boxes.append(dr['rect'])
        xb = [l['spans'][0]['origin'] for b in pg.get_text('dict')['blocks'] for l in b.get('lines', []) if ''.join(s['text'] for s in l['spans']).strip() == 'x']
        for r in boxes:
            print('%s\t%d\t%d\t%.2f\t%.2f\t%.2f\t%.2f\t%s' % (k, len(doc), pg.number + 1, r.y0, r.y1, r.x0, r.x1, ','.join('%.2f' % o[1] for o in xb)))
