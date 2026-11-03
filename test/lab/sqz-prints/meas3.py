import sys; sys.path.insert(0, '.')
from rd import lines
P = [w for pg, w in lines(sys.argv[1] + '/sqz3-orig.pdf') if w[0][0] == 'Everyone']
C = [l.split() for l in open(sys.argv[1] + '/cases.tsv')]
res = {}
out = open('SQZ3-WORD.tsv', 'w', encoding='utf8'); out.write('# words_k\tspaces\toverrun_pt\tline1_words\toutcome\tgap_mean\tshrink_pct\n')
for (k, d), w in zip(C, P):
    k = int(k); n = len(w); stay = n >= k
    g = [w[i+1][1] - w[i][2] for i in range(n - 1)]; gm = sum(g) / len(g) if g else float('nan')
    out.write('%d\t%d\t%s\t%d\t%s\t%.3f\t%.1f\n' % (k, k - 1, d, n, 'stayed' if stay else 'wrapped', gm, 100 * (3.4965 - gm) / 3.4965))
    res.setdefault(k, []).append((float(d), stay, n))
for k, v in res.items():
    st = [x for x in v if x[1]]; fl = [x for x in v if not x[1]]
    print('k=%d (%d spaces): last stay overrun=%s (%.3f pt/space, %.1f%%); first not-stay=%s' % (k, k - 1, st[-1][0] if st else None, st[-1][0] / (k - 1) if st else 0, 100 * st[-1][0] / (k - 1) / 3.4965 if st else 0, fl[0][0] if fl else None))
