# -*- coding: utf-8 -*-
import pymupdf, glob, os
CH = '部署，上特引》）。'
rows = ['# doc\tpages\t' + '\t'.join(CH) + '\tcombined-line fonts (same 9 chars in one run)']
for f in sorted(glob.glob('run/*-orig.pdf')):
    d = pymupdf.open(f); per = {}; comb = []
    for p in d:
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                cs = [(c['c'], s['font']) for s in l['spans'] for c in s['chars'] if c['c'].strip()]
                if len(cs) == 1: per.setdefault(cs[0][0], cs[0][1])
                elif len(cs) == len(CH): comb = cs
    rows.append('\t'.join([os.path.basename(f).replace('-orig.pdf', ''), str(len(d))] + [per.get(c, '-') for c in CH] + [' '.join('%s:%s' % (c, fn) for c, fn in comb)]))
open('GOTH2-WORD.tsv', 'w', encoding='utf8').write('\n'.join(rows) + '\n'); print('\n'.join(r.split('\t')[0] + ' | ' + ' '.join(r.split('\t')[2:11]) for r in rows))
