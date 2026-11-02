import pymupdf, sys
import gen
d = pymupdf.open(sys.argv[1] if len(sys.argv) > 1 else 'run/cambria-orig.pdf')
out = ['# case\tsize_pt\tfirst_baseline_y\tfirst_baseline_minus_top_margin(72)\tpitches(6 lines -> 5 values)\tmean_pitch\tfont']
for pn, (n, sz, ex, br) in enumerate(gen.CASES):
    p = d[pn]
    ls = []
    for b in p.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            cs = [c for s in l['spans'] for c in s['chars']]
            if ''.join(c['c'] for c in cs).strip():
                ls.append((l['spans'][0]['chars'][0]['origin'][1], l['spans'][0]['font']))
    ls.sort()
    ys = [y for y, _ in ls]
    pit = [round(ys[i + 1] - ys[i], 3) for i in range(len(ys) - 1)]
    out.append('\t'.join(map(str, [n, sz, round(ys[0], 3), round(ys[0] - 72, 3), ' '.join(map(str, pit)), round((ys[-1] - ys[0]) / (len(ys) - 1), 3), ls[0][1]])) + '  # %d lines' % len(ys))
open('CAMBRIA-WORD.tsv', 'w', encoding='utf8').write('\n'.join(out) + '\n')
print('\n'.join(out))
