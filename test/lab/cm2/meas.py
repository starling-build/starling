# usage: meas.py DIR  (reads DIR/cm2-orig.pdf, Word's print; writes DIR/CM2-WORD.tsv)
import sys, pymupdf
d = sys.argv[1]; L = 'abcdefghijklmnopqrstuvwxy'
lines = []
for pg in pymupdf.open(d + '/cm2-orig.pdf'):
    for b in pg.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            ch = [c for s in l['spans'] for c in s['chars'] if c['c'].strip()]
            if ch: lines.append(ch)
rows = [(i, l) for i, l in enumerate(lines) if ''.join(c['c'] for c in l).startswith('除；施工')]
print('rows', len(rows), file=sys.stderr)
with open(d + '/CM2-WORD.tsv', 'w', encoding='utf8') as w:
    w.write('# block\trow\tline1_nchars\tline1_last2\tline1_x1\tline2_head\n')
    for k, (i, l1) in enumerate(rows):
        t = ''.join(c['c'] for c in l1); nxt = ''.join(c['c'] for c in lines[i + 1][:3]) if i + 1 < len(lines) else ''
        w.write('%d\t%s\t%d\t%s\t%.2f\t%s\n' % (k // 25 + 1, L[k % 25], len(l1), t[-2:], l1[-1]['bbox'][2], nxt))
