import pymupdf,sys
def heights(p):
    ys=[]
    for pg in pymupdf.open(p):
        py=[]
        for d in pg.get_drawings():
            for it in d['items']:
                if it[0]=='l' and abs(it[1].y-it[2].y)<0.01 and abs(it[1].x-it[2].x)>30: py.append(round(it[1].y,2))
                if it[0]=='re' and it[1].height<1.5 and it[1].width>30: py.append(round((it[1].y0+it[1].y1)/2,2))
        ys.append(sorted(set(py)))
    return ys
if __name__=='__main__':
    for p in sys.argv[1:]:
        ys=heights(p); print(p,[len(y) for y in ys])
