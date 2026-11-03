import pymupdf,sys,glob,os
d=sys.argv[1]
print('# doc\tpages\trows_on_p1\tpitch_median\tpitch_min\tpitch_max\tfirst_baselines')
for f in sorted(glob.glob(d+'/*-orig.pdf')):
    doc=pymupdf.open(f); ys=[]
    for b in doc[0].get_text('dict')['blocks']:
        for l in b.get('lines',[]):
            if l['spans'][0]['text'].strip() and l['bbox'][0]<200: ys.append(round(l['spans'][0]['origin'][1],2))
    ys=sorted(set(ys)); df=[round(b-a,3) for a,b in zip(ys,ys[1:])]
    dd=sorted(df[1:]) if len(df)>1 else df  # skip header->row2 step
    print('%s\t%d\t%d\t%s\t%s\t%s\t%s'%(os.path.basename(f)[:-9],len(doc),len(ys),dd[len(dd)//2] if dd else '',dd[0] if dd else '',dd[-1] if dd else '',' '.join(map(str,ys[:5]))))
