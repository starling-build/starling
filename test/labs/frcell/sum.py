import pymupdf,sys,os
for f in sys.argv[1:]:
    d=pymupdf.open(f)
    for pn,p in enumerate(d):
        if 'Calculator' not in p.get_text(): continue
        T=[]
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines',[]):
                t=''.join(c['c'] for s in l['spans'] for c in s['chars']).strip()
                T.append((round(l['bbox'][1],1),round(l['bbox'][0],1),t or 'SP'))
        sp=[y for y,x,t in T if t=='SP' and x<125 and 270<y<345]
        def first(w): return next(((y,x) for y,x,t in T if t==w),None)
        cal=[(y,x) for y,x,t in T if t.startswith('Calculator')]
        hl=sorted({round(r.y0,1) for dr in p.get_drawings() for r in [dr['rect']] if r.height<1.6 and r.width>300 and 90<r.y0<430})
        print(os.path.basename(f)[:-9],'page',pn+1,'| Calculator',cal,'| A Sun',first('Sun'),'| B Add',first('Add Sub'),'| frame-lines x<125 y',sp,'| wide hlines',hl, '| A26', first('A26'))
