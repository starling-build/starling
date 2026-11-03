import sys; sys.path.insert(0, '.')
from rd import lines
cases = [l.rstrip().split(chr(9)) for l in open(sys.argv[1] + '/cases.tsv')]
L = lines(sys.argv[1] + '/sqz2-orig.pdf')
# paragraph starts: a/c start with 'essary', b with 'Everyone'
P = []; seenE = False
for pg, w in L:
    if w[0][0] == 'Everyone': seenE = True
    if w[0][0] == 'Everyone' or (w[0][0] == 'essary' and not seenE): P.append([w])
    elif P: P[-1].append(w)
print('# paras', len(P), len(cases), file=sys.stderr)
print('# case\tspacing_tw\toverrun_pt\toutcome\tline1_end\tline_with_target_words\tgap_mean\tgap_natural\tshrink_per_space_pt\tshrink_pct')
GN = 3.4965  # TNR 14 space = 0.25 em
for (name, val, d), p in zip(cases, P):
    val = int(val)
    val = int(val)
    val = int(val)
    tgt = p[0] if name in ('a', 'c') else p[2]
    if name[0] == 'b' and (len(p) < 3 or not p[1][-1][0].endswith('-')): note = 'line2_not_hyph'
    else: note = ''
    last = tgt[-1][0]
    stay = last.startswith('sickness')
    o = 'stayed' if stay else ('hyphenated' if last.endswith('-') else 'wrapped')
    gaps = [tgt[k+1][1] - tgt[k][2] for k in range(len(tgt) - 1)]; g = sum(gaps) / len(gaps)
    print('%s\t%s\t%s\t%s\t%s\t%s\t%.3f\t%.3f\t%.3f\t%.1f' % (name, val, d, o + (' ' + note if note else ''), tgt[-1][0], len(tgt), g, GN, GN - g, 100 * (GN - g) / GN))
