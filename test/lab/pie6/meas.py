import pymupdf, sys
import gen
FX, FY = 72.0, 72.0
d = pymupdf.open(sys.argv[1] if len(sys.argv) > 1 else 'run/pie6-orig.pdf')
rows = []
for pn, (s, f, o) in enumerate(gen.combos()):
    p = d[pn]
    nm, pv = gen.NAMES[s], gen.SH[s]
    toks = {nm, '%d%%' % pv}
    if f == 'f3':
        toks.add(str(pv))
    ws = [w for w in p.get_text('words') if w[4] in toks]
    if not ws:
        rows.append((pn + 1, s, f, o, 'NONE')); continue
    x0 = min(w[0] for w in ws); y0 = min(w[1] for w in ws); x1 = max(w[2] for w in ws); y1 = max(w[3] for w in ws)
    rows.append((pn + 1, s, f, o, round((x0 + x1) / 2 - FX, 1), round((y0 + y1) / 2 - FY, 1), round(x0 - FX, 1), round(y0 - FY, 1), round(x1 - x0, 1), round(y1 - y0, 1), len(ws)))
with open('PIE6-WORD.tsv', 'w', encoding='utf8') as out:
    out.write('# page\tslice_idx\tfmt\toffset(x,y)\tcx\tcy (label centre, pt from frame top-left, frame 400.7x216)\tleft\ttop\tw\th\twords\n')
    for r in rows:
        out.write('\t'.join(map(str, r)) + '\n')
        print(*r)
