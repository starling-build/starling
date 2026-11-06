import sys,glob,os,pymupdf
import numpy as np
print('# doc\tcx\tcy\tR\tnpts\trms_resid  (circle fit to the vertices of the coloured wedge paths; the wedge apex is excluded by using only points far from the best apex guess)')
for f in sorted(glob.glob(os.path.join(sys.argv[1],'*-orig.pdf'))):
    p=pymupdf.open(f)[0]; pts=[]
    for d in p.get_drawings():
        if not d.get('fill') or d['fill']==(1.0,1.0,1.0) or d['rect'].width<=1 or d['rect'].width>400: continue
        if max(d['rect'].width,d['rect'].height)<20 and False: continue
        for it in d['items']:
            if it[0]=='c': pts+= [(it[1].x,it[1].y),(it[4].x,it[4].y)]
            elif it[0]=='l': pts+= [(it[1].x,it[1].y),(it[2].x,it[2].y)]
    P=np.array(pts)
    c=P.mean(0)
    for _ in range(6):   # iterate: drop points not on the circle (apex, legend swatches)
        A=np.c_[2*P[:,0],2*P[:,1],np.ones(len(P))]; b=(P**2).sum(1)
        s=np.linalg.lstsq(A,b,rcond=None)[0]; cx,cy=s[0],s[1]; R=np.sqrt(s[2]+cx*cx+cy*cy)
        r=np.hypot(P[:,0]-cx,P[:,1]-cy)-R
        keep=np.abs(r)<max(0.3,np.percentile(np.abs(r),70))
        if keep.all(): break
        P=P[keep]
    r=np.hypot(P[:,0]-cx,P[:,1]-cy)-R
    print('%s\t%.2f\t%.2f\t%.2f\t%d\t%.3f'%(os.path.basename(f)[:-9],cx,cy,R,len(P),np.sqrt((r**2).mean())))
