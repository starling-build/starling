import sys, pymupdf
d = sys.argv[1]
CFG = {'cend-jin': ('準', ['abcdefghijklmnopqrstuvwxy', 'ABCDEFGHIJKLMNOPQRSTUVWXY'], '進精'), 'cend-cheng': ('做', ['abcdefghijklmnopqrstuvwxy', 'ABCDEFGHIJKLMNOPQRSTUVWXY', [str(i) for i in range(1, 26)]], '程體')}
wr = open(d + '/CEND-WORD.tsv', 'w', encoding='utf8'); wr.write('# doc\trow\tline1_nchars\tline1_last2\tlast_char\tline1_x1\tline2_head\n')
ch_out = open(d + '/CEND-CHARS.tsv', 'w', encoding='utf8'); ch_out.write('# doc\trow\tchar:x_origin:x1 ... (line 1)\n')
for doc, (first, groups, take) in CFG.items():
    P = []
    for pg in pymupdf.open('%s/%s-orig.pdf' % (d, doc)):
        for b in pg.get_text('rawdict')['blocks']:
            for l in b.get('lines', []):
                ch = [c for s in l['spans'] for c in s['chars'] if c['c'] != ' ']
                if not ch: continue
                if ch[0]['c'] == first and not (P and len(P[-1]) == 1 and False): P.append([ch])
                elif P: P[-1].append(ch)
    labels = [x for g in groups for x in g]
    print(doc, 'paragraphs', len(P), 'labels', len(labels), file=sys.stderr)
    for lab, p in zip(labels, P):
        l1 = p[0]; t = ''.join(c['c'] for c in l1)
        wr.write('%s\t%s\t%d\t%s\t%s\t%.2f\t%s\n' % (doc, lab, len(l1), t[-2:], t[-1], l1[-1]['bbox'][2], ''.join(c['c'] for c in p[1][:3]) if len(p) > 1 else ''))
        if lab in ('k', 'K', '11'):
            ch_out.write('%s\t%s\t%s\n' % (doc, lab, ' '.join('%s:%.2f:%.2f' % (c['c'], c['origin'][0], c['bbox'][2]) for c in l1)))
