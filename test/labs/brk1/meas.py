import sys,os,json,glob,pymupdf
OP={'p':'（','b':'【','a':'《','q':'「'}
print('# variant\tW\tOPEN2_on_line1\tx_OPEN1\tadv_OPEN1\tx_OPEN2\tadv_OPEN2\tspace_adv\tline1_end_x\tn_chars_line1')
for f in sorted(glob.glob(os.path.join(sys.argv[1],'*-orig.pdf'))):
    k=os.path.basename(f)[:-9]; Ws=json.load(open(f[:-9]+'.meta')); o=OP[k.split('-')[1]]; S=int(k[-1])
    rows=[]
    for p in pymupdf.open(f):
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines',[]):
                ch=[c for s in l['spans'] for c in s['chars']]
                if ch and ch[0]['c']=='政': rows.append((p.number,l['bbox'][1],ch))
    rows.sort(key=lambda r:(r[0],r[1]))
    for i,(pn,y,ch) in enumerate(rows):
        t=''.join(c['c'] for c in ch); xs=[c['origin'][0] for c in ch]
        idx=[j for j,c in enumerate(ch) if c['c']==o]
        def adv(j): return round(xs[j+1]-xs[j],2) if j+1<len(xs) else None
        o1=idx[0] if idx else None; o2=idx[1] if len(idx)>1 else None
        sp=[j for j,c in enumerate(ch) if c['c']==' ']
        print('%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%.2f\t%d'%(k,Ws[i] if i<len(Ws) else '?','Y' if o2 is not None else 'N',
          round(xs[o1],2) if o1 is not None else '',adv(o1) if o1 is not None else '',round(xs[o2],2) if o2 is not None else '',adv(o2) if o2 is not None else '',
          adv(sp[0]) if sp else '',ch[-1]['bbox'][2],len(ch)))
