import pymupdf,glob
for f in sorted(glob.glob('ag-*-orig.pdf')):
    p=pymupdf.open(f)[0]; L=[]
    for b in p.get_text('rawdict')['blocks']:
        for l in b.get('lines',[]):
            ch=[(c['c'],c['origin'][0]) for s in l['spans'] for c in s['chars']]
            L.append((l['bbox'][1],ch))
    L.sort(key=lambda t:t[0]); res=[]
    for y,ch in L[:4]:
        t=''.join(c for c,x in ch)
        i=t.find('1') if '1' in t else -1
        if i<0: continue
        # first digit group: ideo before, digits, [space], ideo after
        j=i
        while j<len(t) and (t[j].isdigit() or t[j]==' '): j+=1
        if t[i-1]==' ': i-=1
        xs=[x for c,x in ch]
        seg=[(t[k],round(xs[k+1]-xs[k],2)) for k in range(i-1,j)]
        res.append(''.join('%s:%.2f '%(c,a) for c,a in seg))
    print(f[3:-9],'|',' || '.join(res))
