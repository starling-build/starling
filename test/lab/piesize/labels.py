import sys,os,re,glob,math,pymupdf
# labels.py DIR FITTSV > LABELS-WORD.tsv: data labels 'labelK[...],' + value, centre/offset from the fitted pie (PIEFIT-WORD.tsv), inside/outside
fit={}
for l in open(sys.argv[2],encoding='utf8'):
    c=l.split('\t')
    if l[0]!='#' and len(c)>3: fit[c[0]]=tuple(map(float,c[1:4]))
print('# doc\tk\tcx\tcy\tdx\tdy\tdist\tdist/R\tw\th\tIN|OUT(centre vs R)\tbox_vs_pie(OUT=no overlap)')
for f in sorted(glob.glob(os.path.join(sys.argv[1],'*-orig.pdf'))):
    n=os.path.basename(f)[:-9]; cx0,cy0,R=fit[n]
    p=pymupdf.open(f)[0]; ws=sorted(p.get_text('words'),key=lambda w:(w[5],w[6],w[7]))
    i=0
    while i<len(ws):
        m=re.match(r'label(\d+)',ws[i][4])
        if not m: i+=1; continue
        j=i
        while j<len(ws) and j<i+4 and not ws[j][4].endswith(','): j+=1
        if j>=len(ws) or j>=i+4 or not ws[j][4].endswith(','): i+=1; continue
        parts=ws[i:j+1]
        if j+1<len(ws) and re.fullmatch(r'[\d.]+',ws[j+1][4]): parts.append(ws[j+1])
        x0=min(q[0] for q in parts);x1=max(q[2] for q in parts);y0=min(q[1] for q in parts);y1=max(q[3] for q in parts)
        cx,cy=(x0+x1)/2,(y0+y1)/2; d=math.hypot(cx-cx0,cy-cy0)
        # nearest point of box to pie centre
        nx=min(max(cx0,x0),x1);ny=min(max(cy0,y0),y1); bd=math.hypot(nx-cx0,ny-cy0)
        print('%s\t%s\t%.2f\t%.2f\t%+.2f\t%+.2f\t%.2f\t%.2f\t%.1f\t%.1f\t%s\t%s'%(n,m.group(1),cx,cy,cx-cx0,cy-cy0,d,d/R,x1-x0,y1-y0,'IN' if d<R else 'OUT','overlap' if bd<R else 'OUT'))
        i=j+1
