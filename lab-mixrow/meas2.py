import pymupdf,sys
d=sys.argv[1]; rows=[l.rstrip('\n').split('\t') for l in open(sys.argv[2],encoding='utf-8-sig')]
print('# book\trow\tfont\tcom_height\tprint_height (rule to rule)')
for book in ('calibri11','verdana10'):
    pg=pymupdf.open(d+'/'+book+'-orig.pdf')[0]; ys=set()
    for dr in pg.get_drawings():
        for it in dr['items']:
            if it[0]=='l' and abs(it[1].y-it[2].y)<0.01 and 45<it[1].x<60: ys.add(round(it[1].y,3))
            if it[0]=='re' and 45<it[1].x0<60 and it[1].height<1.5 and it[1].width>40: ys.add(round((it[1].y0+it[1].y1)/2,3))
    ys=sorted(ys); cl=[]
    for y in ys:
        if cl and y-cl[-1][-1]<2: cl[-1].append(y)
        else: cl.append([y])
    ys=[sum(c)/len(c) for c in cl]; rs=[r for r in rows if r[0]==book]
    for i,r in enumerate(rs):
        h='%.2f'%(ys[i+1]-ys[i]) if i+1<len(ys) else ''
        print('%s\t%s\t%s\t%s\t%s'%(book,r[1],r[2],r[3],h))
    print('#',book,'rules',len(ys))
