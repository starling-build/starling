import pymupdf,sys,glob,os
files=sys.argv[1:]
for f in files:
    d=pymupdf.open(f); print('==',os.path.basename(f),len(d))
    for pn,p in enumerate(d):
        if 'Calculator' not in p.get_text(): continue
        print(' page',pn+1)
        ys=[]
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines',[]):
                t=''.join(c['c'] for s in l['spans'] for c in s['chars'])
                y=l['bbox'][1]
                if 90<y<420: ys.append((round(y,1),round(l['bbox'][0],1),t.strip()[:28] or '<spaces>'))
        for r in sorted(ys): print('   text',r)
        hs=sorted({(round(r.y0,1),round(r.x0,1),round(r.x1,1)) for dr in p.get_drawings() for r in [dr['rect']] if r.height<1.6 and r.width>25 and 90<r.y0<420})
        print('   hlines',hs)
