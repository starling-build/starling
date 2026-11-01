import sys, os, importlib.util, collections, unicodedata
R = os.environ['STARLING_REPO']
spec = importlib.util.spec_from_file_location('lm', R + '/test/docx-line-match.py'); lm = importlib.util.module_from_spec(spec); spec.loader.exec_module(lm)
d = sys.argv[1]
def cls(c):
    cat = unicodedata.category(c)
    if '一' <= c <= '鿿' or '㐀' <= c <= '䶿': return 'ideo'
    if cat.startswith('P') or cat.startswith('S'): return c
    return 'other'
rows = []
for f in sorted(os.listdir(d + '/pdf')):
    k = f[:-4]
    w = os.path.join(lm.WORD, k + '-orig.pdf')
    if not os.path.exists(w): continue
    try:
        a = lm.lines(d + '/pdf-text', w); b = lm.lines(d + '/pdf-text', d + '/pdf/' + f)
    except Exception as e: continue
    by = {}
    for r in b: by.setdefault(r[0], []).append(r)
    for i, r in enumerate(a):
        for o in by.get(r[0], []):
            if abs(o[1] - r[1]) <= 3 and abs(o[2] - r[2]) <= 3 and r[3] != o[3] and lm.same_start(o[3], r[3]):
                wa, ob = r[3], o[3]
                c = 0
                while c < min(len(wa), len(ob)) and wa[c] == ob[c]: c += 1
                tw, to = wa[c:], ob[c:]
                if len(tw) <= 3 and len(to) <= 3 and (len(tw) + len(to)) > 0 and (not tw or not to or True):
                    nxtw = a[i + 1][3][:1] if i + 1 < len(a) and a[i + 1][0] == r[0] else ''
                    rows.append((k, r[0], round(r[1]), wa[-1], ob[-1], tw, to, nxtw, wa[-8:], ob[-8:], wa, ob, round(r[2])))
                break

import io
out = io.open(sys.stdout.fileno(), 'w', encoding='utf-8', errors='replace', closefd=False)
for x in rows:
    if any('\u3000' <= ch <= '\u9fff' or '\uff00' <= ch <= '\uffef' or ch in '\u201c\u201d\u2018\u2019\u2014' for ch in x[8] + x[9]): out.write('\t'.join(map(str, x)) + '\n')
out.flush()
