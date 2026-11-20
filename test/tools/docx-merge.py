#!/usr/bin/env python3
# docx-merge.py BASE.match FIX.match IDS OUT — the incremental re-pair (amd-8, 2026-11-14): FIX.match holds only the
# documents named in IDS (stems, one per line); every other row is taken from BASE.match, so OUT is a full score file.
# A named document missing from FIX stays missing (it failed to render: the pair reports it). Header recomputed from the
# printed (rounded) percentages, so its mean can differ from a full sweep's in the last digit.
import re, sys, statistics
R = re.compile(r'\s*([\d.]+)%\s+lines (\d+)/(\d+)\s+pages (\d+)/(\d+)\s+(\S+)')
def rows(p):
    d = {}
    for l in open(p):
        m = R.match(l)
        if m: d[m.group(6)] = (float(m.group(1)), l.rstrip('\n'), m.group(4) == m.group(5))
    return d
base, fix = rows(sys.argv[1]), rows(sys.argv[2])
ids = {l.strip() for l in open(sys.argv[3]) if l.strip()}
out = {k: v for k, v in base.items() if k not in ids}
out.update(fix)
r = sorted(out.items(), key=lambda kv: (kv[1][0], kv[0]))
v = [x[1][0] / 100 for x in r]
with open(sys.argv[4], 'w') as f:
    if v:
        f.write(f"{len(v)} documents: mean {100*statistics.mean(v):.1f}% of Word's lines matched, median {100*statistics.median(v):.1f}%; "
                f"{sum(x >= .95 for x in v)} at 95% or more, {sum(x >= .5 for x in v)} at half or more; "
                f"{sum(x[1][2] for x in r)} with Word's page count\n")
        for k, x in r: f.write(x[1] + '\n')
