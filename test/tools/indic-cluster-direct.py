#!/usr/bin/env python3
"""Per-cluster advances read DIRECTLY from Word prints: a cluster's advance is the next cluster's first-glyph origin minus its own, in em (median, 3+ samples).
Unlike indic-cluster-fit.py (least squares on whole-word widths, which mis-solves clusters with a pre-base i-matra: ji read 0.997, direct 0.701, sd 0.004 over 240 samples).
usage: python3 test/tools/indic-cluster-direct.py FACE   (writes /tmp/direct_<FACE>.pkl; Devanagari only)"""
import pymupdf,glob,collections,statistics,re,sys,unicodedata
FACE=sys.argv[1]
res=collections.defaultdict(list)
cons=lambda c:0x915<=ord(c)<=0x939 or 0x958<=ord(c)<=0x95F
for f in glob.glob('/data/corpus-cache/staging/*/word-win/*-orig.pdf'):
    try: d=pymupdf.open(f)
    except: continue
    for p in d:
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines',[]):
                for s in l['spans']:
                    if s['font']!=FACE: continue
                    ch=s['chars']; n=len(ch)
                    # cluster starts: a consonant not preceded by virama
                    starts=[i for i in range(n) if cons(ch[i]['c']) and not (i>0 and ch[i-1]['c']=='्') and not (ch[i]['c']=='़')]
                    for a,b2 in zip(starts,starts[1:]):
                        txt=''.join(c['c'] for c in ch[a:b2])
                        if any(not (0x900<=ord(c)<=0x97f) for c in txt) : continue
                        if abs(ch[b2]['origin'][1]-ch[a]['origin'][1])>0.5: continue
                        res[txt].append((ch[b2]['origin'][0]-ch[a]['origin'][0])/s['size'])
out={}
for k,v in res.items():
    if len(v)>=3: out[k]=(len(v),statistics.median(v),statistics.pstdev(v))
import pickle; pickle.dump(out,open('/tmp/direct_%s.pkl'%FACE.replace(',','_'),'wb'))
print(len(out))
