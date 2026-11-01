import sys, glob, os, pymupdf
for f in sorted(glob.glob(sys.argv[1] + '/*-orig.pdf')):
    d = pymupdf.open(f); print('##', os.path.basename(f))
    for b in d[0].get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            cs = [c for s in l['spans'] for c in s['chars']]
            if not cs: continue
            sz = l['spans'][0]['size']
            xs = [c['bbox'][0] for c in cs]; ends = cs[-1]['bbox'][2]
            adv = [round(xs[i+1]-xs[i], 2) for i in range(len(xs)-1)]
            print(f"{sz:.1f}\t{''.join(c['c'] for c in cs)}\tx0={xs[0]:.2f}\tw={ends-xs[0]:.2f}\tadv=" + ' '.join(f"{c['c']}:{a}" for c, a in zip(cs, adv)))
