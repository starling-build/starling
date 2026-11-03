import sys; sys.path.insert(0, '.')
from rd import lines
d = sys.argv[1]; SFX = sys.argv[2] if len(sys.argv) > 2 else ''
FONTS = ['Calibri', 'Times New Roman']; SIZES = [10, 12, 14]; DS = [0.1, 0.3, 0.6, 1.0]
LASTW = 'administration'; FIRST = {1: 'Considerable', 3: 'Everyone', 8: 'Everyone'}
nat = {}
for l in open('SQZ-NATURAL.tsv', encoding='utf8'):
    if l[0] != '#': f, s, n, w, g, _ = l.split('\t'); nat[(f, int(s), int(n))] = (float(w), float(g))
cases = [(f, s, n, dd, al) for f in FONTS for s in SIZES for n in (1, 3, 8) for dd in DS for al in ('left', 'justified')]
print('# hyph\tfont\tsize\tnspaces\talign\toverrun_pt\toutcome\tline1_words\tmean_gap_pt\tnatural_gap_pt\tgap_shrink_pct\tline1_x1\tcolumn_pt')
for doc in ('sqzOn' + SFX, 'sqzOff' + SFX, 'sqzOn360' + SFX):
    L = lines('%s/%s-orig.pdf' % (d, doc)); P = []
    for pg, w in L:
        if w[0][0] in ('Considerable', 'Everyone') and (not P or True) and w[0][0] == FIRST[len(P) // 8 % 1 or 1] or False: pass
    # paragraph starts: line whose first word is Considerable/Everyone
    for pg, w in L:
        if w[0][0] in ('Considerable', 'Everyone'): P.append((pg, w))
    print('# %s paragraphs %d (expect %d)' % (doc, len(P), len(cases)), file=sys.stderr)
    for (f, s, n, dd, al), (pg, w) in zip(cases, P):
        last = w[-1][0]
        outc = 'stayed' if last == LASTW else ('hyphenated' if last.endswith('-') else 'wrapped')
        if len(w) < n + 1 and outc == 'wrapped' and last != LASTW: pass
        gaps = [w[k+1][1] - w[k][2] for k in range(len(w) - 1)]
        g = sum(gaps) / len(gaps) if gaps else float('nan'); gn = nat[(f, s, n)][1]
        print('%s\t%s\t%d\t%d\t%s\t%.1f\t%s\t%d\t%.3f\t%.3f\t%.1f\t%.2f\t%.2f' % (doc[3:].replace(SFX, '') + ('' if not SFX else '/c' + SFX), f, s, n, al, dd, outc, len(w), g, gn, 100 * (gn - g) / gn, w[-1][2], nat[(f, s, n)][0] - dd))
