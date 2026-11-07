import sys, pymupdf, collections
d = pymupdf.open(sys.argv[1]); SZ = float(sys.argv[2]) if len(sys.argv) > 2 else 16.0
adv = collections.defaultdict(list); face = {}
for p in d:
    for b in p.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            ch = [(c, s['font']) for s in l['spans'] for c in s['chars']]
            for i in range(len(ch) - 1):
                a, fa = ch[i]; b2, fb = ch[i + 1]
                if a['c'] == b2['c'] and fa == fb and a['c'].strip():
                    adv[a['c']].append((b2['origin'][0] - a['origin'][0]) / SZ); face[a['c']] = fa
print('# char\tcodepoint\tface\tn_pairs\tmean_adv_em\tmin_em\tmax_em')
for c in sorted(adv, key=ord):
    v = adv[c]; print('%s\tU+%04X\t%s\t%d\t%.4f\t%.4f\t%.4f' % (c, ord(c), face[c], len(v), sum(v) / len(v), min(v), max(v)))
