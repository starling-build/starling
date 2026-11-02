import pymupdf
out=[]
for k in (360,240,480):
    d=pymupdf.open('v/g%d-orig.pdf'%k)
    for pn,p in enumerate(d):
        ls=[]
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines',[]):
                cs=[c for s in l['spans'] for c in s['chars']]
                t=''.join(c['c'] for c in cs)
                fonts=sorted({s['font'] for s in l['spans']})
                ls.append((round(l['spans'][0]['chars'][0]['origin'][1],1),t,fonts,round(cs[0]['origin'][0],1)))
        ls.sort()
        prev=None
        for y,t,f,x in ls:
            pitch='' if prev is None else '%.1f'%(y-prev)
            prev=y
            out.append('line=%d p%d y=%.1f pitch=%s x=%.1f %s %s'%(k,pn+1,y,pitch,x,f,t[:12]+('..' if len(t)>12 else '')))
open('GOTHLINE-WORD.txt','w',encoding='utf8').write('\n'.join(out)+'\n')
print('\n'.join(out))
