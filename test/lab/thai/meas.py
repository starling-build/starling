import pymupdf, glob, os
for f in sorted(glob.glob('run/*-orig.pdf')):
    d = pymupdf.open(f); p = d[0]; rows = {}
    fonts = set()
    for b in p.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(s['text'] for s in l['spans']); fonts |= {s['font'] for s in l['spans']}
            rows[(round(l["bbox"][1], 1), len(rows))] = t
    print('==', os.path.basename(f)[:-9], len(d), 'pages; fonts', fonts)
    for y in sorted(rows): print('  ', y, len(rows[y]), rows[y])
