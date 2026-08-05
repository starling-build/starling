#!/usr/bin/env python3
"""Summarise repeated terminal benchmark runs.

Reads res-<term>-<n>.txt files written by test/bench/run-bench.sh and reports,
per workload, the median wall/CPU across runs plus the spread, so a single
noisy run cannot carry the comparison.
"""
import glob, os, re, statistics as st, sys, json

DIR = sys.argv[1] if len(sys.argv) > 1 else "/var/tmp/bench"
# Labels to compare, ours first. Defaults to the round-1 (Starling) pair;
# pass e.g. `analyse.py /var/tmp/bench starling-gnome ghostty-gnome` for round 2.
LABELS = sys.argv[2:4] if len(sys.argv) > 3 else ["starling", "ghostty"]

def load(term):
    runs = []
    for p in sorted(glob.glob(os.path.join(DIR, f"res-{term}-*.txt"))):
        # `res-starling-*` also matches `res-starling-gnome-1.txt`; only the
        # plain numeric suffix is a run of THIS label. Mixing the two silently
        # averages across desktops and quietly corrupts every median below.
        if not re.fullmatch(rf"res-{re.escape(term)}-\d+\.txt", os.path.basename(p)):
            continue
        d, rss = {}, None
        for line in open(p):
            if line.startswith("#"):
                continue
            f = line.split()
            if f[0] == "rss_kb":
                rss = int(f[1])
            elif len(f) == 3:
                d[f[0]] = (float(f[1]), float(f[2]))
        runs.append({"file": os.path.basename(p), "tests": d, "rss_kb": rss})
    return runs

terms = {}
for t in LABELS:
    terms[t] = load(t)
    print(f"{t}: {len(terms[t])} runs")

names = sorted({n for t in terms.values() for r in t for n in r["tests"]})

OURS, GH = LABELS

def med(term, name, idx):
    vals = [r["tests"][name][idx] for r in terms[term] if name in r["tests"]]
    return st.median(vals), min(vals), max(vals)

print()
hdr = f"{'workload':<18} {'ours wall':>18} {'ghostty wall':>18} {'ratio':>7} " \
      f"{'ours cpu':>18} {'ghostty cpu':>18} {'ratio':>7}"
print(hdr); print("-" * len(hdr))

rows = []
for n in names:
    ow, olo, ohi = med(OURS, n, 0)
    gw, glo, ghi = med(GH, n, 0)
    oc, oclo, ochi = med(OURS, n, 1)
    gc, gclo, gchi = med(GH, n, 1)
    rw = ow / gw if gw else float("nan")
    rc = oc / gc if gc else float("nan")
    print(f"{n:<18} {ow:8.3f} [{olo:.3f}-{ohi:.3f}] {gw:8.3f} [{glo:.3f}-{ghi:.3f}] "
          f"{rw:6.2f}x {oc:8.2f} [{oclo:.2f}-{ochi:.2f}] {gc:8.2f} [{gclo:.2f}-{gchi:.2f}] {rc:6.2f}x")
    rows.append(dict(name=n, ours_wall=ow, ours_wall_lo=olo, ours_wall_hi=ohi,
                     gh_wall=gw, gh_wall_lo=glo, gh_wall_hi=ghi, ratio_wall=rw,
                     ours_cpu=oc, ours_cpu_lo=oclo, ours_cpu_hi=ochi,
                     gh_cpu=gc, gh_cpu_lo=gclo, gh_cpu_hi=gchi, ratio_cpu=rc))

tw_o = sum(r["ours_wall"] for r in rows); tw_g = sum(r["gh_wall"] for r in rows)
tc_o = sum(r["ours_cpu"] for r in rows);  tc_g = sum(r["gh_cpu"] for r in rows)
print("-" * len(hdr))
print(f"{'TOTAL':<18} {tw_o:8.3f}{'':12} {tw_g:8.3f}{'':12} {tw_o/tw_g:6.2f}x "
      f"{tc_o:8.2f}{'':12} {tc_g:8.2f}{'':12} {tc_o/tc_g:6.2f}x")

print("\nRSS after each run (MB):")
for t in terms:
    print(f"  {t:<9}", ", ".join(f"{r['rss_kb']/1024:.0f}" for r in terms[t]))

wins = sum(1 for r in rows if r["ratio_wall"] < 1.0)
print(f"\nwall-time wins: ours {wins}/{len(rows)}, ghostty {len(rows)-wins}/{len(rows)}")
cwins = sum(1 for r in rows if r["ratio_cpu"] < 1.0)
print(f"cpu wins:       ours {cwins}/{len(rows)}, ghostty {len(rows)-cwins}/{len(rows)}")

json.dump({"rows": rows, "raw": terms},
          open(os.path.join(DIR, "summary.json"), "w"), indent=1)
print(f"\nwrote {DIR}/summary.json")
