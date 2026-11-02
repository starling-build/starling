# -*- coding: utf-8 -*-
import pymupdf, sys
sys.path.insert(0, '.')
TEXT = '部署，为推动全国食品药品监管领域基层政务公开标准化规范化，提升基层政务公开和政务服务水平，在总结各县（区、市）市场监管部门试点经验的基础上，特编制《食品药品监管领域基层政务公开标准指引》（以下简称《指引》）。'
CFG = ['gf_fs', 'gf_song', 'gf_jh', 'gf_jh2', 'gf_nh', 'gf_orig']
SHORT = {'MS-Gothic': 'G', 'MicrosoftJhengHeiRegular': 'J', 'SimSun': 'S', 'NSimSun': 'NS', 'MicrosoftYaHei': 'Y'}


def chars(page):
    out = []
    for b in page.get_text('rawdict')['blocks']:
        for l in b.get('lines', []):
            for s in l['spans']:
                for c in s['chars']:
                    if c['c'].strip():
                        out.append((c['c'], s['font'], c['origin'][1], c['origin'][0]))
    return out


res = {}
for c in CFG:
    d = pymupdf.open(('f2/' if c in ('gf_nh', 'gf_orig') else 'f/') + '%s-orig.pdf' % c)
    p1 = chars(d[0]); p2 = chars(d[1]) if len(d) > 1 else None
    p1.sort(key=lambda t: (round(t[2]), t[3]))
    if c == 'gf_orig':
        st = ''.join(t[0] for t in p1); k = st.index(TEXT[:6]); p1 = p1[k:k + len(TEXT)]
        res[c] = (p1, p1); assert ''.join(t[0] for t in p1) == TEXT; continue
    p2.sort(key=lambda t: t[2])
    rows=[]
    for t in p2:
        if rows and t[2]-rows[-1][-1][2]<10: rows[-1].append(t)
        else: rows.append([t])
    p2=[t for r in rows for t in sorted(r,key=lambda t:t[3])]
    res[c] = (p1, p2)
    assert ''.join(t[0] for t in p1) == TEXT, (c, ''.join(t[0] for t in p1)[:30])
    assert ''.join(t[0] for t in p2) == TEXT, (c, 'tbl')
fonts = sorted({t[1] for c in CFG for p in res[c] for t in p})
print(fonts)
with open('GOTHFACE-WORD.tsv', 'w', encoding='utf8') as o:
    o.write('# idx\tchar\t' + '\t'.join('%s_ctx\t%s_alone' % (c, c) for c in CFG) + '\t(font full names: %s)\n' % ' | '.join(fonts))
    for i, ch in enumerate(TEXT):
        row = [str(i), ch]
        for c in CFG:
            p1, p2 = res[c]
            row += [SHORT.get(p1[i][1], p1[i][1]), SHORT.get(p2[i][1], p2[i][1])]
        o.write('\t'.join(row) + '\n')
        print('\t'.join(row))
