import sys, pymupdf
d = sys.argv[1]
CFG = {'cend2-kuo': ('提供優質', '提供優質'), 'cend2-shi': ('社', '社')}
L='abcdefghijklmnopqrstuvwxy'
labels=list(L)+list(L.upper())+[str(i) for i in range(1,26)]
wr = open(d + '/CEND2-WORD.tsv', 'w', encoding='utf8'); wr.write('# doc\trow\tline1_nchars\tline1_last2\tline1_x1\tline2_head\n')
co = open(d + '/CEND2-CHARS.tsv', 'w', encoding='utf8'); co.write('# doc\trow\tchar:x_origin:x1 ... (line 1)\n')
for doc, (pref, _) in CFG.items():
    P = []
    for pg in pymupdf.open('%s/in/%s-orig.pdf' % (d, doc)):
        for b in pg.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                ch = [c for s in l['spans'] for c in s['chars'] if c['c'].strip()]
                if not ch: continue
                t = ''.join(c['c'] for c in ch)
                if t.startswith(pref) or (doc.endswith('shi') and t[:1]=='社' and t[1:2] in '（甲'): P.append([ch])
                elif P: P[-1].append(ch)
    print(doc, 'paragraphs', len(P), file=sys.stderr)
    for lab, p in zip(labels, P):
        l1 = p[0]; t = ''.join(c['c'] for c in l1)
        wr.write('%s\t%s\t%d\t%s\t%.2f\t%s\n' % (doc, lab, len(l1), t[-2:], l1[-1]['bbox'][2], ''.join(c['c'] for c in p[1][:3]) if len(p) > 1 else ''))
        if lab in ('k', 'K', '11'):
            co.write('%s\t%s\t%s\n' % (doc, lab, ' '.join('%s:%.2f:%.2f' % (c['c'], c['origin'][0], c['bbox'][2]) for c in l1)))
