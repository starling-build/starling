import sys; sys.path.insert(0, '.')
from rd import lines
DS = {1: [round(.1 * k, 1) for k in range(1, 11)], 3: [round(.2 * k, 1) for k in range(1, 13)], 8: [round(.4 * k, 1) for k in range(1, 17)]}
nat = {}
for l in open('SQZ-NATURAL.tsv', encoding='utf8'):
    if l[0] != '#': f, s, n, w, g, _ = l.split('\t'); nat[(f, int(s), n)] = (float(w), float(g))
cases = [(f, s, n, d) for f in ('Calibri', 'Times New Roman') for s in (10, 12, 14) for n in (1, 3, 8) for d in DS[n]]
P = [(pg, w) for pg, w in lines(sys.argv[1] + '/sqzX-orig.pdf') if w[0][0] in ('Considerable', 'Everyone')]
print('# paragraphs', len(P), len(cases), file=sys.stderr)
print('# font\tsize\tnspaces\toverrun_pt\toutcome\tline1_words\tmean_gap_pt\tnatural_gap_pt\tshrink_per_space_pt\tshrink_pct_of_space\tline1_x1\tcolumn_edge_x')
for (f, s, n, d), (pg, w) in zip(cases, P):
    stay = w[-1][0] == 'administration'; o = 'stayed' if stay else ('hyphenated' if w[-1][0].endswith('-') else 'wrapped')
    gaps = [w[k+1][1] - w[k][2] for k in range(len(w) - 1)]; g = sum(gaps) / len(gaps) if gaps else float('nan'); gn = nat[(f, s, str(n))][1] if (f, s, str(n)) in nat else nat[(f, s, n)][1]
    print('%s\t%d\t%d\t%.1f\t%s\t%d\t%.3f\t%.3f\t%.3f\t%.1f\t%.2f\t%.2f' % (f, s, n, d, o, len(w), g, gn, gn - g, 100 * (gn - g) / gn, w[-1][2], 56.7 + (nat[(f, s, n)][0] if (f, s, n) in nat else nat[(f, s, str(n))][0]) - d))
