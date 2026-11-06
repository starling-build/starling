import sys,os,glob,pymupdf
print('# doc\tpage\tchart_frame(x0,y0,x1,y1)\tplot_axis_bbox(x0,y0,x1,y1)\tleft_vertical_axis_x\tright_vertical_axis_x\tbottom_axis_y\tn_pages')
for f in sorted(glob.glob(os.path.join(sys.argv[1],'*-orig.pdf'))):
    k=os.path.basename(f)[:-9]; d=pymupdf.open(f)
    for i,p in enumerate(d):
        st=[x for x in p.get_drawings() if x.get('color') and not x.get('fill')]
        fr=[x['rect'] for x in st if abs((x.get('width') or 0)-0.14)<0.02]
        if not fr: continue
        F=fr[0]
        ax=[x['rect'] for x in st if x['color'][0]<0.5 and (x.get('width') or 0)>0.5 and (x['rect'].width<0.01 or x['rect'].height<0.01 or True) and F.contains(x['rect'])]
        if not ax: continue
        vx=sorted({round(r.x0,1) for r in ax if r.width<0.01 and r.height>20})
        hy=sorted({round(r.y0,1) for r in ax if r.height<0.01 and r.width>20})
        x0=min(r.x0 for r in ax);y0=min(r.y0 for r in ax);x1=max(r.x1 for r in ax);y1=max(r.y1 for r in ax)
        print('%s\t%d\t(%.1f,%.1f,%.1f,%.1f)\t(%.1f,%.1f,%.1f,%.1f)\t%s\t%s\t%s\t%d'%(k,i+1,F.x0,F.y0,F.x1,F.y1,x0,y0,x1,y1,vx[0] if vx else '',vx[-1] if vx else '',hy[-1] if hy else '',len(d)))
