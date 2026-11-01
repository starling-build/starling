import sys, re, zipfile, collections, glob, os, json
P='/private/tmp/claude-501/-Users-dishengsu-dev-starling-starling-office/7bd18d8e-e7d2-40e4-a88e-7ed13742d2d6/scratchpad/'
I=lambda c:'一'<=c<='鿿'
rows=[l.rstrip('\n').split('\t') for l in open(P+'census2.tsv',encoding='utf-8')]
pre=[r for r in rows if len(r)>=12 and (r[5]=='' or r[6]=='') and r[0].startswith('zh-') and I((r[5] or r[6])[0]) and I(r[3]) and I(r[4])]
feat={}
def docfeat(k):
    z=zipfile.ZipFile('test/corpus/docx/docs/%s.docx'%k)
    d=z.read('word/document.xml').decode('utf8','replace'); s=z.read('word/settings.xml').decode('utf8','replace')
    g=re.findall(r'<w:docGrid[^>]*>',d)
    gt=re.search(r'w:type="(\w+)"',g[-1]).group(1) if g and 'w:type' in g[-1] else 'none'
    cs=re.search(r'w:charSpace="(-?\d+)"',g[-1]) if g else None
    m=re.search(r'compatibilityMode"[^>]*w:val="(\d+)"',s)
    return dict(grid=gt, charSpace=int(cs.group(1)) if cs else 0, mode=m.group(1) if m else '-', kin0='<w:kinsoku w:val="0"/>' in d, alt='useAltKinsoku' in s,
        csc=(re.search(r'characterSpacingControl w:val="(\w+)"',s) or [0,'-'])[1] if re.search(r'characterSpacingControl w:val="(\w+)"',s) else '-',
        tbl=d.count('<w:tc>')+d.count('<w:tc '), jc=('both' if d.count('w:jc w:val="both"')>d.count('w:jc w:val="left"') else 'left'))
tot=collections.Counter(); 
for r in pre:
    k=r[0]
    if k not in feat:
        try: feat[k]=docfeat(k)
        except Exception as e: feat[k]=None
    f=feat[k]
    if not f: continue
    d='W+' if r[6]=='' else 'O+'
    for key in ('grid','mode','csc','jc'):
        tot[(key,f[key],d)]+=1
    tot[('kin0',f['kin0'],d)]+=1; tot[('alt',f['alt'],d)]+=1; tot[('cells',f['tbl']>50,d)]+=1
    tot[('charSpace<0',f['charSpace']<0, d)]+=1; tot[('charSpace>0',f['charSpace']>0, d)]+=1
keys=sorted({(a,b) for a,b,c in tot})
for a,b in keys: print('%-12s %-18s W+ %3d  O+ %3d'%(a,b,tot[(a,b,'W+')],tot[(a,b,'O+')]))
json.dump(feat,open(P+'feat.json','w'))
