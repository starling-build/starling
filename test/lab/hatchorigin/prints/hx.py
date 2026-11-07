import pymupdf, re, sys
d = pymupdf.open(sys.argv[1]); H = d[0].rect.height
print('# page\tchart\tframe_left\tframe_top\tframe_w\tframe_h\tpattern\ttile_origin_x\ttile_origin_y_top\ttile_pt\tfill_bbox_x0\tfill_bbox_y0_top\tfill_bbox_x1\tfill_bbox_y1_top')
for pi, p in enumerate(d):
    pats = {}
    res = d.xref_get_key(p.xref, 'Resources')[1]
    for m in re.finditer(r'/(P\d+) (\d+) 0 R', res):
        o = d.xref_object(int(m.group(2)))
        mm = re.search(r'/Matrix\s*\[\s*([-\d. ]+)\]', o); bb = re.search(r'/BBox\s*\[\s*([-\d. ]+)\]', o)
        pats[m.group(1)] = ([float(x) for x in mm.group(1).split()] if mm else [1,0,0,1,0,0], [float(x) for x in bb.group(1).split()] if bb else [0,0,0,0])
    toks = p.read_contents().decode('latin1').split()
    nums = []; path = []; cur = None; frame = None; chart = 0
    for t in toks:
        try: nums.append(float(t)); continue
        except ValueError: pass
        if t == 're' and len(nums) >= 4:
            x, y, w, h = nums[-4:]; path += [(x, y), (x + w, y + h)]; last_re = (x, y, w, h)
        elif t in ('m', 'l'): path.append((nums[-2], nums[-1]))
        elif t == 'c': path += [(nums[-6], nums[-5]), (nums[-4], nums[-3]), (nums[-2], nums[-1])]
        elif t == 'scn' and cur is None and False: pass
        elif t == 'S':
            if path and len(path) == 2 and last_re[2] > 50 and last_re[3] > 50 and last_re[2] < 200:
                chart += 1; x, y, w, h = last_re; frame = (x, H - y - h, w, h)
            path = []
        elif t in ('f', 'f*'):
            if cur and path and frame:
                xs = [a for a, b in path]; ys = [b for a, b in path]
                e, f = pats[cur][0][4], pats[cur][0][5]; ts = (pats[cur][1][2] * pats[cur][0][0])
                print('%d\t%d\t%.2f\t%.2f\t%.2f\t%.2f\t%s\t%.3f\t%.3f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f' % (pi + 1, chart, frame[0], frame[1], frame[2], frame[3], cur, e, H - f, ts, min(xs), H - max(ys), max(xs), H - min(ys)))
            path = []
        elif t == 'n': path = []
        elif t == 'scn' and len(nums) == 0: pass
        if t == 'scn': pass
        if t.startswith('/P') and t[2:].isdigit(): cur = t[1:]
        if t in ('rg', 'g', 'RG', 'G') : cur = None if t in ('rg', 'g') else cur
        if t in ('q',) : pass
        if t not in ('re','m','l','c','h'): nums = [] if t not in ('W*',) else nums
