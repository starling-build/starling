import pymupdf,glob,sys
for f in sorted(glob.glob(sys.argv[1]+'/*-orig.pdf')):
    d=pymupdf.open(f); print(f)
    for pn,p in enumerate(d):
        ys=sorted({round(r.y1,1) for dr in p.get_drawings() for r in [dr['rect']] if r.height<1.5 and 390<r.width<410})
        if not ys: continue
        print(' page',pn+1,'border ys',ys)
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines',[]):
                t=''.join(c['c'] for s in l['spans'] for c in s['chars'])
                if ys[0]-30<l['bbox'][1]<ys[-1]+60 and not t.strip()[:5]=='Table':
                    print('   ',round(l['bbox'][0],1),round(l['bbox'][1],1),repr(t.strip()[:30]))
