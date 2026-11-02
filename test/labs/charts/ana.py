import pymupdf, glob, os, re
log = {}
for l in open('all.log', encoding='utf8', errors='replace'):
    p = l.rstrip('\n').split('\t')
    if len(p) >= 6 and p[0] in ('col2d', 'bar2d', 'col3d', 'stk3d'):
        log[(p[0], p[1], p[2])] = p[3:6]
out = ['# type\tmax-data\tW\tCOM min/max/step\tvalue-axis labels in the PDF']
for t in ('col2d', 'bar2d', 'col3d', 'stk3d'):
    for m in ('5', '12.3', '95', '1200'):
        f = 'out/chart-%s-%s.pdf' % (t, m)
        d = pymupdf.open(f)
        for i, W in enumerate((200, 300, 450, 600)):
            p = d[i]
            ws = [(w[0], w[1], w[4]) for w in p.get_text('words')]
            num = [w for w in ws if re.fullmatch(r'[0-9.,]+', w[2])]
            # value axis: for column charts the labels share a left x; for bars they share a baseline y
            if t in ('col2d', 'col3d'):
                xs = {}
                for x, y, s in num: xs.setdefault(round(x / 10), []).append((y, s))
                lab = max(xs.values(), key=len) if xs else []
                labs = [s for y, s in sorted(lab, reverse=True)]
            else:
                ys = {}
                for x, y, s in num: ys.setdefault(round(y / 4), []).append((x, s))
                lab = max(ys.values(), key=len) if ys else []
                labs = [s for x, s in sorted(lab)]
            out.append('\t'.join([t, m, str(W), '/'.join(log.get((t, m, str(W)), log.get((t, m.replace('.0', ''), str(W)), ['?']))), ' '.join(labs)]))
open('CHART-WORD.tsv', 'w', encoding='utf8').write('\n'.join(out) + '\n')
print('\n'.join(out))
