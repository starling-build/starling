import pymupdf,glob
for f in sorted(glob.glob('run3/*-orig.pdf')):
    p=pymupdf.open(f)[0]
    bs=sorted({round(d['rect'].y1,1) for d in p.get_drawings() if d['rect'].height<1.5 and d['rect'].width>100} | {round(d['rect'].y0,1) for d in p.get_drawings() if d['rect'].height<1.5 and d['rect'].width>100})
    # glyph tops
    out=[]
    for b in p.get_text('rawdict')['blocks']:
        for l in b.get('lines',[]):
            t=''.join(c['c'] for s in l['spans'] for c in s['chars'])
            out.append((round(l['bbox'][1],1),round(l['bbox'][3],1),t.strip()[:12]))
    print(f,'lines y:',bs);[print('  ',o) for o in out]
