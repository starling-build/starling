import math,re,glob
L='lab/'
def angles():
    A={}
    for f in glob.glob(L+'*/docs/*.docx'):
        import zipfile
        c=zipfile.ZipFile(f).read('word/charts/chart1.xml').decode()
        a=int(re.search(r'firstSliceAng val="(\d+)"',c).group(1))
        n=len(re.findall(r'<c:pt idx',re.search(r'<c:val>.*?</c:val>',c,re.S).group(0)))
        vals=[float(v) for v in re.findall(r'<c:v>([\d.]+)</c:v>',re.search(r'<c:val>.*?</c:val>',c,re.S).group(0))]
        A[f.split('/')[-1][:-5]]=(a,vals)
    return A
def rows():
    A=angles(); out=[]
    for t in ['pielabel3/PIEEQ-WORD.tsv','pieang/PIEANG-WORD.tsv','piewid/PIEWID-WORD.tsv']:
        for ln in open(L+t):
            if ln.startswith('#'): continue
            p=ln.split('\t')
            doc=p[0];k=int(p[1]);dx,dy,w,h=map(float,(p[4],p[5],p[7],p[8]))
            pcx,pcy,R,leg=map(float,p[9:13]);io=p[13]
            a,vals=A[doc];tot=sum(vals);cum=sum(vals[:k-1])
            th=(a+360*(cum+vals[k-1]/2)/tot)%360
            out.append(dict(doc=doc,k=k,dx=dx,dy=dy,w=w,h=h,pcx=pcx,pcy=pcy,R=R,leg=leg,io=io,th=th,n=len(vals),
                 span=360*vals[k-1]/tot,start=(a+360*cum/tot)%360))
    return out
def closest(dx,dy,w,h):
    x=min(max(0,dx-w/2),dx+w/2) if not (dx-w/2<=0<=dx+w/2) else 0
    y=min(max(0,dy-h/2),dy+h/2) if not (dy-h/2<=0<=dy+h/2) else 0
    # nearest point of box to origin
    x=0 if dx-w/2<=0<=dx+w/2 else (dx-w/2 if dx>0 else dx+w/2)
    y=0 if dy-h/2<=0<=dy+h/2 else (dy-h/2 if dy>0 else dy+h/2)
    return x,y
