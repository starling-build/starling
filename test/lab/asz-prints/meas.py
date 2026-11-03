import sys, pymupdf
d = sys.argv[1]
L = []
for pg in pymupdf.open(d + '/asz-orig.pdf'):
    for b in pg.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            ch = [c for s in l['spans'] for c in s['chars'] if c['c'] != ' ']
            if ch and ch[0]['c'] == '檢': L.append((pg.number+1, ch, l['spans'][0]['size']))
print('# rows', len(L), file=sys.stderr)
with open(d + '/ASZ-CHARS.tsv', 'w', encoding='utf8') as f:
    f.write('# row\tpage\tn_chars\tchar:x_origin:x1 ... (line 1, every character; one line per row)\n')
    for r, (pn, ch, sz) in zip('abcdefghi', L):
        f.write('%s\t%d\t%d\t%s\n' % (r, pn, len(ch), ' '.join('%s:%.2f:%.2f' % (c['c'], c['origin'][0], c['bbox'][2]) for c in ch)))
