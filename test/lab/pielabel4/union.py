import sys,os,glob,pymupdf
print('# doc\tunion_x0\tx1\ty0\ty1\tcx\tcy\tR=min(w,h)/2\tw\th\tnfills')
for f in sorted(glob.glob(os.path.join(sys.argv[1],'*-orig.pdf'))):
    p=pymupdf.open(f)[0]
    rs=[d['rect'] for d in p.get_drawings() if d.get('fill') and d['fill']!=(1.0,1.0,1.0) and d['rect'].width>1 and d['rect'].height>1 and d['rect'].width<400]
    # keep fills of the wedges: those inside the chart frame, exclude page-wide/legend swatches by size > 20 on either side
    big=[r for r in rs if r.width>20 or r.height>20]
    x0=min(r.x0 for r in big);x1=max(r.x1 for r in big);y0=min(r.y0 for r in big);y1=max(r.y1 for r in big)
    print('%s\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%d'%(os.path.basename(f)[:-9],x0,x1,y0,y1,(x0+x1)/2,(y0+y1)/2,min(x1-x0,y1-y0)/2,x1-x0,y1-y0,len(big)))
