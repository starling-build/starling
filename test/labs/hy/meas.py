import pymupdf,glob,os,sys
def lines(f):
    d=pymupdf.open(f);o=[]
    for p in d:
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines',[]):
                cs=[c for s in l['spans'] for c in s['chars']]
                t=''.join(c['c'] for c in cs).rstrip()
                if t: o.append((round(l['bbox'][2],1),t))
    return o
if __name__=='__main__':
    for f in sorted(glob.glob('run/hy[A-D]*-orig.pdf')+glob.glob('run/hyF*-orig.pdf')):
        L=lines(f);h=[t.endswith('-') for _,t in L]
        run=m=0
        for x in h:
            run=run+1 if x else 0; m=max(m,run)
        print(os.path.basename(f)[:-9],'lines',len(L),'hyph',sum(h),'maxconsec',m)
