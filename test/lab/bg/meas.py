import sys, glob, os, pymupdf
d = sys.argv[1]
print('# doc\tpages\tpage_fill_rgb\tfill_rect\tpixel_centre_rgb')
for f in sorted(glob.glob(os.path.join(d, '*-orig.pdf'))):
    k = os.path.basename(f)[:-9]; pg = pymupdf.open(f)[0]
    fills = [(dr['fill'], dr['rect']) for dr in pg.get_drawings() if dr.get('fill')]
    big = [x for x in fills if x[1].width > 0.9 * pg.rect.width and x[1].height > 0.9 * pg.rect.height]
    px = pg.get_pixmap(matrix=pymupdf.Matrix(1, 1)); c = px.pixel(int(px.width / 2), int(px.height * 0.8))
    print('%s\t%d\t%s\t%s\t%s' % (k, len(pymupdf.open(f)), ','.join('%d' % round(v * 255) for v in big[0][0]) if big else '', '%.0fx%.0f' % (big[0][1].width, big[0][1].height) if big else '', ','.join(map(str, c))))
