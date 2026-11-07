import sys, pymupdf
d = pymupdf.open(sys.argv[1]); p = d[0]; SZ = 16.0
print('# combo\thint\trun\tface\tsize\tadvances_em(per digit, last digit uses next char)\tmean_em\ttext')
lines = []
for b in p.get_text('rawdict')['blocks']:
    for l in b.get('lines', []):
        ch = [(c, s['font'], s['size']) for s in l['spans'] for c in s['chars']]
        lines.append((l['spans'][0]['origin'][1], l['bbox'][0], ch))
lines.sort(key=lambda r: (round(r[0], 1), r[1]))
combo = None; kind = 0
for y, x0, ch in lines:
    t = ''.join(c['c'] for c, f, s in ch)
    if t.endswith(': ') or t.rstrip().endswith(':'): combo = t.strip().rstrip(':'); kind = 0; continue
    kind += 1; hint = 'eastAsia' if kind == 1 else 'none'
    # digit runs: maximal ascii-digit runs
    i = 0; run = 0
    while i < len(ch):
        if ch[i][0]['c'].isascii() and ch[i][0]['c'].isdigit():
            j = i
            while j < len(ch) and ch[j][0]['c'].isascii() and ch[j][0]['c'].isdigit(): j += 1
            xs = [c['origin'][0] for c, f, s in ch[i:j]]
            nxt = ch[j][0]['origin'][0] if j < len(ch) else ch[j-1][0]['bbox'][2]
            adv = [(xs[k + 1] - xs[k]) / SZ for k in range(len(xs) - 1)] + [(nxt - xs[-1]) / SZ]
            faces = '+'.join(dict.fromkeys(f for c, f, s in ch[i:j]))
            run += 1
            print('%s\t%s\t%d\t%s\t%.2f\t%s\t%.4f\t%s' % (combo, hint, run, faces, ch[i][2], ' '.join('%.3f' % a for a in adv), sum(adv) / len(adv), ''.join(c['c'] for c, f, s in ch[i:j])))
            i = j
        else: i += 1
