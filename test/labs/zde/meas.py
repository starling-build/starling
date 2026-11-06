import sys,os,glob,pymupdf
print('# doc\tline\tidx\tchar\tsize\torigin_x\tadvance(next origin - this origin; last char: bbox width)\tline_end_x')
for f in sorted(glob.glob(os.path.join(sys.argv[1],'*-orig.pdf'))):
    k=os.path.basename(f)[:-9]; p=pymupdf.open(f)[0]
    ls=[]
    for b in p.get_text('rawdict')['blocks']:
        for l in b.get('lines',[]):
            ch=[(c,s['size']) for s in l['spans'] for c in s['chars']]
            if ch: ls.append((round(l['bbox'][1],1),ch))
    ls.sort(key=lambda t:t[0])
    for n,(y,ch) in enumerate(ls[:int(sys.argv[2]) if len(sys.argv)>2 else 1],1):
        xs=[c['origin'][0] for c,_ in ch]; end=ch[-1][0]['bbox'][2]
        for i,(c,sz) in enumerate(ch):
            a=xs[i+1]-xs[i] if i+1<len(xs) else c['bbox'][2]-xs[i]
            print('%s\t%d\t%d\t%s\t%.1f\t%.2f\t%.2f\t%.2f'%(k,n,i,c['c'],sz,xs[i],a,end))
