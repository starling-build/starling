import sys,pymupdf
p=pymupdf.open(sys.argv[1])[0]
edges=sorted({round((d['rect'].x0+d['rect'].x1)/2,2) for d in p.get_drawings() if d['rect'].width<1.5 and d['rect'].height>20})
cs=[]
for b in p.get_text('rawdict')['blocks']:
    for l in b.get('lines',[]):
        for s in l['spans']:
            for c in s['chars']:
                if c['c'] in '手語翻譯服務': cs.append((c['origin'][0],c['bbox'][0],c['bbox'][2],c['origin'][1],s['size']))
print('# table\tcell\tsize\tglyph_origin_x\tglyph_bbox_x0\tx1\tcell_left\tcell_right\tleft_gap\tright_gap\tfirst_char_y\tlast_char_y   (cell edges at %s)'%edges)
for i in range(0,len(cs),6):
    g=cs[i:i+6]; n=i//6; t,c=n//5+1,n%5+1
    x0=min(a[1] for a in g); x1=max(a[2] for a in g)
    cl=max([e for e in edges if e<=x0+0.01] or [float('nan')]); cr=min([e for e in edges if e>=x1-0.01] or [float('nan')])
    print('T%d\tc%d\t%.1f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.2f\t%.1f\t%.1f'%(t,c,g[0][4],g[0][0],x0,x1,cl,cr,x0-cl,cr-x1,g[0][3],g[-1][3]))
