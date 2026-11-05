# usage: meas.py DIR  (reads DIR/cm-<case>-orig.pdf, Word's prints; writes DIR/CM-WORD.tsv, DIR/CM-CHARS.tsv)
import sys, pymupdf, os
d = sys.argv[1]
CFG = {'cm-fei': '廳負責人', 'cm-ze': '為加強', 'cm-fa': '除；施工', 'cm-fang': '（二）举报', 'cm-wu': '郵寄保訓', 'cm-jiu': '範例1吳瓊恩', 'cm-guan': '交通运输'}
L = 'abcdefghijklmnopqrstuvwxy'
wr = open(d + '/CM-WORD.tsv', 'w', encoding='utf8'); wr.write('# doc\trow\tline1_nchars\tline1_last2\tline1_x1\tline2_head\n')
co = open(d + '/CM-CHARS.tsv', 'w', encoding='utf8'); co.write('# doc\trow\tchar:x_origin:x1 ... (line 1)\n')
for doc, pref in CFG.items():
    f = '%s/%s-orig.pdf' % (d, doc)
    if not os.path.exists(f): print('missing', f, file=sys.stderr); continue
    lines = []
    for pg in pymupdf.open(f):
        for b in pg.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                ch = [c for s in l['spans'] for c in s['chars'] if c['c'].strip()]
                if ch: lines.append(ch)
    rows = [(i, l) for i, l in enumerate(lines) if ''.join(c['c'] for c in l).replace(' ', '').startswith(pref.replace(' ', ''))]
    print(doc, 'rows', len(rows), file=sys.stderr)
    for lab, (i, l1) in zip(L, rows):
        t = ''.join(c['c'] for c in l1); nxt = ''.join(c['c'] for c in lines[i + 1][:3]) if i + 1 < len(lines) else ''
        wr.write('%s\t%s\t%d\t%s\t%.2f\t%s\n' % (doc, lab, len(l1), t[-2:], l1[-1]['bbox'][2], nxt))
        if lab == 'k':
            co.write('%s\t%s\t%s\n' % (doc, lab, ' '.join('%s:%.2f:%.2f' % (c['c'], c['origin'][0], c['bbox'][2]) for c in l1)))
