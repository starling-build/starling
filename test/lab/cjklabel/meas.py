import pymupdf
d=pymupdf.open('cjkl-orig.pdf')
for pn,p in enumerate(d):
    print('== page',pn+1)
    for b in p.get_text('rawdict')['blocks']:
        for l in b.get('lines',[]):
            for s in l['spans']:
                t=''.join(c['c'] for c in s['chars'])
                if not t.strip(): continue
                c=s['chars'][0]
                print('  %-12s %-22s sz=%.2f base=%.2f x=%.1f'%(t[:10],s['font'],s['size'],c['origin'][1],c['origin'][0]))
