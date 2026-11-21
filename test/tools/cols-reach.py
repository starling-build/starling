#!/usr/bin/env python3
# cols-reach.py — count eval docs with multi-column sections (w:cols num>1) and the ones the importer
# turns into a one-row table (regime C in docs/plans/section-columns.md). An approximation of Docx.swift's
# condition; the exact list is the RuleTrace hit section-columns-as-row once P1 lands.
# Usage: python3 -I test/tools/cols-reach.py NAME=DOCSDIR ...  (writes ./tablepath-NAME.txt)
import sys
sys.setrecursionlimit(100000)
import sys, os, zipfile, re, xml.etree.ElementTree as ET
W='{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
def scan(path):
    try:
        z=zipfile.ZipFile(path); x=z.read('word/document.xml')
        root=ET.fromstring(x)
    except Exception: return None
    body=root.find(W+'body')
    if body is None: return None
    secs=[]; cur={'tbl':0,'colbr':0,'fn':0,'anchor':0,'paras':0}
    def close(sp):
        nonlocal cur
        cols=sp.find(W+'cols') if sp is not None else None
        num=int(cols.get(W+'num','1') or 1) if cols is not None else 1
        t=sp.find(W+'type') if sp is not None else None
        typ=t.get(W+'val') if t is not None else 'nextPage'
        cur.update(num=num,typ=typ,sep=(cols is not None and cols.get(W+'sep') in ('1','true','on')),
                   unequal=(cols is not None and cols.get(W+'equalWidth') in ('0','false','off')))
        secs.append(cur); cur={'tbl':0,'colbr':0,'fn':0,'anchor':0,'paras':0}
    for ch in body:
        tag=ch.tag
        if tag==W+'tbl': cur['tbl']+=1
        if tag in (W+'p',W+'tbl',W+'sdt'):
            for e in ch.iter():
                t=e.tag
                if t==W+'br' and e.get(W+'type')=='column': cur['colbr']+=1
                elif t==W+'footnoteReference': cur['fn']+=1
                elif t.endswith('}anchor') and 'drawingml' in t: cur['anchor']+=1
                elif t==W+'tbl': cur['tbl']+=1
            cur['paras']+=1
            sp=ch.find(W+'pPr/'+W+'sectPr') if tag==W+'p' else None
            if sp is not None: close(sp)
    close(body.find(W+'sectPr'))
    if secs and secs[-1]['paras']==0 and len(secs)>1: pass
    multi=[k for k,s in enumerate(secs) if s['num']>1]
    if not multi: return {'any':0}
    r={'any':1}
    nums=set(max(1,s['num']) for s in secs)
    r['mixed']=int(len(nums)>1); r['whole']=int(len(nums)==1)
    tp=0
    for k in multi:
        s=secs[k]
        own=(k>0 and s['typ']=='continuous'); nxt=(k+1<len(secs) and secs[k+1]['typ']=='continuous')
        if (own or nxt) and s['tbl']==0: tp=1
    r['tablepath']=tp
    r['sep']=int(any(secs[k]['sep'] for k in multi)); r['unequal']=int(any(secs[k]['unequal'] for k in multi))
    r['colbr']=int(any(secs[k]['colbr'] for k in multi)); r['fn']=int(any(secs[k]['fn'] for k in multi))
    r['tbl']=int(any(secs[k]['tbl'] for k in multi)); r['float']=int(any(secs[k]['anchor'] for k in multi))
    r['contend']=int(any(k+1<len(secs) and secs[k+1]['typ']=='continuous' for k in multi))
    return r
keys=['any','whole','mixed','tablepath','contend','unequal','sep','colbr','tbl','float','fn']
for name,d in [a.split('=',1) for a in sys.argv[1:]]:
    tot={k:0 for k in keys}; n=0; ids={'tablepath':[]}
    for f in sorted(os.listdir(d)):
        if not f.endswith('.docx'): continue
        r=scan(os.path.join(d,f)); n+=1
        if not r or not r['any']: continue
        for k in keys: tot[k]+=r.get(k,0)
        if r.get('tablepath'): ids['tablepath'].append(f[:-5])
    print(name, 'docs',n, ' '.join(f'{k}={tot[k]}' for k in keys))
    open(f'tablepath-{name}.txt','w').write('\n'.join(ids['tablepath'])+'\n')
