import sys,glob,os,fitz
rows=[]
for f in sorted(glob.glob('p/*-orig.pdf')):
    k=os.path.basename(f)[:-9]; d=fitz.open(f)
    out=[k,len(d)]
    for pi in range(min(2,len(d))):
        p=d[pi]; ls=[]
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines',[]):
                t=''.join(c['c'] for s in l['spans'] for c in s['chars'])
                if t.strip(): ls.append((l['bbox'][1],l['bbox'][3],l['spans'][0]['origin'][1],t[:12]))
        ls.sort()
        fills=[r['rect'] for r in p.get_drawings() if r.get('fill') and r['rect'].height>3 and r['rect'].width>100]
        out.append('P%d nlines=%d last_base=%.2f first_base=%.2f'%(pi+1,len(ls),ls[-1][2] if ls else -1,ls[0][2] if ls else -1))
        out.append('boxes=%s'%[(round(r.y0,2),round(r.y1,2)) for r in fills[:3]])
    rows.append('\t'.join(map(str,out)))
open('PBMID-WORD.tsv','w',encoding='utf8').write('\n'.join(rows)+'\n'); print('\n'.join(rows))
