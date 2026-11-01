import sys, glob, os, pymupdf
for f in sorted(glob.glob(sys.argv[1] + '/*-orig.pdf')):
    d = pymupdf.open(f); rows = []
    for b in d[0].get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ''.join(s['text'] for s in l['spans'])
            rows.append((round(l['spans'][0]['origin'][1], 2), round(l['spans'][0]['origin'][0], 2), t[:12], sorted({round(s['size'], 1) for s in l['spans']})))
    print(os.path.basename(f), len(d), 'pages'); [print('  ', r) for r in rows]
