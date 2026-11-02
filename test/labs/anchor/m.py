import pymupdf
keys="an_a an_b an_c an_d an_b18 an_b20".split()
want={'E1','E2','E3','Z1','Z2','Table2:A1','26','Table1:A1','17','18','19','1'}
out=[]
for k in keys:
    d=pymupdf.open('v/%s-orig.pdf'%k)
    row=[]
    last=None
    for i,p in enumerate(d):
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines',[]):
                t=''.join(c['c'] for s in l['spans'] for c in s['chars']).strip()
                if not t: continue
                y=round(l['spans'][0]['chars'][0]['origin'][1],1)
                if t in ('E1','E2','E3','Z1','Z2','Table2:A1','26'): row.append('%s p%d %.1f'%(t,i+1,y))
                if t.isdigit() and int(t)<=19: last=(t,i+1,y)
    line='%-7s %s | last T1 row %s'%(k,'; '.join(row),last)
    print(line); out.append(line)
open('ANCHOR-WORD.txt','w',encoding='utf8').write('# baselines (pt, page top-left origin y), Word for Windows, compat 15, pages 595.35x558.5 (A4-wide, short)\n'+'\n'.join(out)+'\n')
