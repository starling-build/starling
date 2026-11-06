import sys,os,glob,pymupdf
print('# doc\tpara(1..16, right indent=2*(n-1)pt)\tend_of_line1\tline1_last6\tbox_x1')
for f in sorted(glob.glob(os.path.join(sys.argv[1],'*-orig.pdf'))):
    k=os.path.basename(f)[:-9]; L=[]
    for p in pymupdf.open(f):
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines',[]):
                ch=[c for s in l['spans'] for c in s['chars']]
                t=''.join(c['c'] for c in ch)
                L.append((p.number,round(l['bbox'][1],1),t.replace(' ',''),ch[-1]['bbox'][2] if ch else 0))
    n=0
    for pn,y,t,x in sorted(L):
        if t.startswith('4.保險期間'):
            n+=1; e=('止；□' if '止；□' in t else ('止；' if t.endswith('止；') else ('止' if t.endswith('止') else 'before 止')))
            print('%s\t%d\t%s\t%s\t%.2f'%(k,n,e,t[-6:],x))
