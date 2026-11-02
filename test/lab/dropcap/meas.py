import pymupdf, sys
K = sys.argv[1:] or ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'orig']
rows = ['# case\tpage\tline_idx\tchar\tx0\tbaseline_y\tx1\ty0\ty1\tsize\tfont (every glyph of the drop cap and the first 2 body lines)']
for k in K:
    d = pymupdf.open('run/dc_%s-orig.pdf' % k)
    for pn, p in enumerate(d):
        li = 0
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                for s in l['spans']:
                    t = ''.join(c['c'] for c in s['chars'])
                    cap = s['size'] > 20
                    if not (cap or li < 2):
                        continue
                    if cap or li < 2:
                        for c in s['chars'] if cap else s['chars'][:3]:
                            rows.append('\t'.join(map(str, [k, pn + 1, li, c['c'], round(c['bbox'][0], 2), round(c['origin'][1], 2), round(c['bbox'][2], 2), round(c['bbox'][1], 2), round(c['bbox'][3], 2), round(s['size'], 2), s['font']])))
                if not any(s['size'] > 20 for s in l['spans']):
                    li += 1
open('DROPCAP-WORD.tsv', 'w', encoding='utf8').write('\n'.join(rows) + '\n')
print('\n'.join(rows))
