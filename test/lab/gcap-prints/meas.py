import sys, pymupdf
d = sys.argv[1]
doc = pymupdf.open(d + '/gcap-orig.pdf')
L = []
for pg in doc:
    for b in pg.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            ch = [c for s in l['spans'] for c in s['chars'] if c['c'] != ' ']
            if ch: L.append((pg.number+1, ch, l['spans'][0]['size']))
paras = []
for pn, ch, sz in L:
    t = ''.join(c['c'] for c in ch)
    if t.startswith('的公益'): paras.append([(pn, ch, sz)])
    elif paras: paras[-1].append((pn, ch, sz))
print('# row\tidx\tpage\tsize\tline1_nchars\tline1_tail\tends_yu\tline1_x1\tline2_head')
first = {}
for i, p in enumerate(paras):
    row = 'abcdef'[i // 16]; k = i % 16 + 1
    pn, ch, sz = p[0]
    t = ''.join(c['c'] for c in ch)
    yu = t.endswith('予')
    l2 = ''.join(c['c'] for c in p[1][1][:3]) if len(p) > 1 else ''
    print('%s\t%d\t%d\t%.1f\t%d\t%s\t%s\t%.2f\t%s' % (row, k, pn, sz, len(ch), t[-5:], 'Y' if yu else 'n', ch[-1]['bbox'][2], l2))
    if yu and row not in first: first[row] = (k, ch)
print('# paragraphs', len(paras), file=sys.stderr)
with open(d + '/GCAP-CHARS.tsv', 'w', encoding='utf8') as f:
    f.write('# row\tidx\tchar_no\tchar\tx_origin\tx1\n')
    for row, (k, ch) in first.items():
        for n, c in enumerate(ch): f.write('%s\t%d\t%d\t%s\t%.2f\t%.2f\n' % (row, k, n+1, c['c'], c['origin'][0], c['bbox'][2]))
