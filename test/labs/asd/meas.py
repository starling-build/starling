import pymupdf
KEYS = ['1none', '2tnr-ascii-hansi', '3tnr-ascii-hansi-hintEA', '4tnr-all-three', '5song-ascii-hansi-hintEA']
for dd in ('ddsong', 'ddtnr'):
    p = pymupdf.open('asd-%s-orig.pdf' % dd)[0]
    paras = []
    for b in p.get_text('rawdict')['blocks']:
        if b['type'] != 0:
            continue
        for l in b['lines']:
            ch = []
            fonts = set()
            for s in l['spans']:
                fonts.add(s['font'][:14])
                ch += [(c['c'], c['origin'][0]) for c in s['chars']]
            paras.append((l['bbox'][1], ch, fonts))
    paras.sort(key=lambda t: t[0])
    for k, (y, ch, fonts) in zip(KEYS, paras):
        t = ''.join(c for c, x in ch)
        i = t.index('3')
        pre = ch[i][1] - ch[i - 1][1]  # prev ideograph origin -> '3' origin
        d3 = ch[i + 1][1] - ch[i][1]
        d0 = ch[i + 2][1] - ch[i + 1][1]
        print('%s %-26s ideo adv=%.2f  gap_before=%.2f  3adv=%.2f 0->next=%.2f  gap_after=%.2f  fonts=%s' % (
            dd, k, ch[i - 1][1] - ch[i - 2][1], pre - 15, d3, d0, d0 - 7.5, sorted(fonts)))
