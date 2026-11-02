import pymupdf, glob, os, sys
run = sys.argv[1]
for f in sorted(glob.glob(run + '/fm-*-orig.pdf'), key=lambda s: (len(s), s)):
    d = pymupdf.open(f)
    out = []
    for pn, p in enumerate(d, 1):
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                t = ''.join(c['c'] for s in l['spans'] for c in s['chars']).strip()
                if t:
                    out.append('p%d %s y%.1f x%.1f' % (pn, t, l['spans'][0]['chars'][0]['origin'][1], l['spans'][0]['chars'][0]['origin'][0]))
        hl = sorted({round(dr['rect'].y0, 1) for dr in p.get_drawings() if dr['rect'].height < 1.5 and dr['rect'].width > 20})
        out.append('p%d hlines %s' % (pn, hl))
    print(os.path.basename(f)[3:-9], '| ' + ' | '.join(out))
