import sys,os,json,glob,pymupdf
print('# variant\tfirstW_stays\tnparas\tbits(1=工 on line 1, per W step)')
for f in sorted(glob.glob(os.path.join(sys.argv[1],'*-orig.pdf'))):
    k=os.path.basename(f)[:-9]; Ws=json.load(open(f[:-9]+'.meta'))
    first=[]
    for p in pymupdf.open(f):
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines',[]):
                t=''.join(c['c'] for s in l['spans'] for c in s['chars']).replace(' ','')
                first.append((p.number,l['bbox'][1],t))
    paras=[]
    for pn,y,t in sorted(first):
        if t.startswith('政'): paras.append(t)
    bits=''.join('1' if '工' in t else '0' for t in paras)
    fw=next((Ws[i] for i,c in enumerate(bits) if c=='1' and i<len(Ws)),'none')
    print('%s\t%s\t%d\t%s'%(k,fw,len(paras),bits))
