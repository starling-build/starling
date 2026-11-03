import sys, pymupdf
d = sys.argv[1]; P = []
for pg in pymupdf.open(d + '/edge-orig.pdf'):
    for b in pg.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            ch = [c for s in l['spans'] for c in s['chars'] if c['c'] != ' ']
            if not ch: continue
            if ch[0]['c'] == '通' and ''.join(c['c'] for c in ch[:4]) == '通過環境': P.append([ch])
            elif P: P[-1].append(ch)
print('# paras', len(P), file=sys.stderr)
rows = 'abcdefghijklmnopqrstu'
with open(d + '/EDGE-WORD.tsv', 'w', encoding='utf8') as f:
    f.write('# row\tright_indent_tw\twidth_pt\tline1_nchars\tline1_last2\tends_ji\tline1_x0\tline1_x1\tline2_head\n')
    for i, (r, p) in enumerate(zip(rows, P)):
        ri = -124 + 10 * 0 + (i - 10) * 1  # rows a..u: width 0.5pt wider (10tw) at a .. narrower at u
        ri = -124 - (10 - i)   # a: -134 (wider), k: -124, u: -114
        l1 = p[0]; t = ''.join(c['c'] for c in l1)
        f.write('%s\t%d\t%.2f\t%d\t%s\t%s\t%.2f\t%.2f\t%s\n' % (r, ri, 377.45 - (ri + 124) / 20, len(l1), t[-2:], 'Y' if t.endswith('及') else 'n', l1[0]['origin'][0], l1[-1]['bbox'][2], ''.join(c['c'] for c in p[1][:3]) if len(p) > 1 else ''))
with open(d + '/EDGE-CHARS.tsv', 'w', encoding='utf8') as f:
    f.write('# row\tchar:x_origin:x1 ... (line 1, every character)\n')
    for r, p in zip(rows, P):
        if r in 'jkl': f.write('%s\t%s\n' % (r, ' '.join('%s:%.2f:%.2f' % (c['c'], c['origin'][0], c['bbox'][2]) for c in p[0])))
