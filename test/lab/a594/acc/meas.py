import sys, pymupdf
print('# doc\tindent_tw\tcol_pt\tline_ending_accordance\tnext_line_head\tx1_of_that_line')
for n in ('acc0','accoff'):
    ls=[]
    for pg in pymupdf.open('gen/%s-orig.pdf'%n):
        for b in pg.get_text('dict')['blocks']:
            for l in b.get('lines',[]):
                t=''.join(s['text'] for s in l['spans'])
                if t.strip(): ls.append((t.rstrip(),l['bbox'][2]))
    k=0
    for i,(t,x) in enumerate(ls):
        if t.startswith('Everyone, as a member'):
            r=-100+5*k; k+=1
            j=i
            while j<len(ls) and 'accordance' not in ls[j][0]: j+=1
            nx=ls[j+1][0] if j+1<len(ls) else ''
            print('%s\t%d\t%.2f\t...%s\t%s\t%.2f'%(n,r,481.9-r/20,ls[j][0][-30:],nx[:12],ls[j][1]))
