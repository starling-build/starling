import pymupdf
print('# doc\tindent_tw\tcol_pt\tline1_tail\tline1_x1\tline2_head')
for n in ('ac2','ac2off'):
    ls=[]
    for pg in pymupdf.open('gen/%s-orig.pdf'%n):
        for b in pg.get_text('dict')['blocks']:
            for l in b.get('lines',[]):
                t=''.join(s['text'] for s in l['spans']).rstrip()
                if t: ls.append((t,l['bbox'][2]))
    k=0
    for i,(t,x) in enumerate(ls):
        if t.startswith('realization,'):
            r=-300+5*k; k+=1
            print('%s\t%d\t%.2f\t...%s\t%.2f\t%s'%(n,r,481.9-r/20,t[-22:],x,ls[i+1][0][:14]))
