#!/usr/bin/env python3
"""gate-sample.py OUT [N] — the render gate's COVERAGE sample (amd-8, 2026-11-20): about N (80) documents of the gated
sets (756 lo xa xb xd xs sa1 sa2 dx2) chosen greedily so that every feature fingerprint token of test/tools/docx-census.py (structure,
XML features, faces, language/script) is carried by at least one picked document, rarest tokens first, small files (<=300 KB,
the fast renders) preferred. Every set gets at least 3 documents. The gate renders these plus the documents named in the
commit messages; the full sets run in the hourly rounds. Fixed once built: rebuild only when the sets change."""
import collections, importlib.util, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)   # importable by name so the worker pool can unpickle
cen = importlib.import_module("docx-census"); feat = importlib.import_module("docx-features")
SLOW = ("07356df9", "a6d65f60")   # slow renders: only when a commit names them

def main():
    R = os.path.dirname(os.path.dirname(HERE)); C = os.environ.get("STARLING_CORPUS", "/data/corpus-cache")
    DIRS = {"756": f"{R}/test/corpus/docx/docs", "lo": f"{R}/test/corpus/docx/lo/docs"}
    for s in ("xa", "xb", "xd", "sa1", "sa2", "dx2", "xs"): DIRS[s] = f"{C}/staging/{s}/docs"
    out = sys.argv[1]; N = int(sys.argv[2]) if len(sys.argv) > 2 else 80
    ML = {}   # stem -> manifest language (the ground truth for dx2 and sa1)
    for mf in (f"{R}/test/corpus/docx/dx2/manifest.tsv", f"{C}/staging/sa1/manifest.tsv"):
        if os.path.exists(mf):
            rows = [l.rstrip("\n").split("\t") for l in open(mf)]
            ix = rows[0].index("language") if "language" in rows[0] else 2   # dx2's manifest has no header row
            for c in (rows[1:] if "language" in rows[0] else rows): ML[c[0]] = c[ix]
    fm = cen.font_map(); stat = collections.Counter(); T = {}; size = {}; sset = {}
    for s, d in DIRS.items():
        for k, r in feat.rows_for(d, jobs=8).items():
            p = os.path.join(d, k if k.endswith(".docx") else k + ".docx")
            stem = k[:-5] if k.endswith(".docx") else k
            if not os.path.exists(p) or os.path.getsize(p) > 300 * 1024 or stem.startswith(SLOW): continue
            t = cen.struct_tokens(r) | cen.xml_tokens(p) | cen.face_tokens(r.get("fonts") or [], fm, stat)
            t |= {"mlang:" + ML[stem]} if stem in ML else set()
            t |= {"lang:" + str(x) for x in (r.get("langs") or [])} | {"set:" + s}
            T[stem] = frozenset(t); size[stem] = os.path.getsize(p); sset[stem] = s
    freq = collections.Counter(x for t in T.values() for x in t)
    W = {x: 1.0 / f for x, f in freq.items()}
    pick, cov = [], set()
    QUOTA = {"756": 7, "lo": 7, "xa": 8, "xb": 8, "xd": 5, "xs": 6, "sa1": 12, "sa2": 10, "dx2": 17}   # about 80: the user focus (sa1 es/pt, sa2, dx2 ko/ja) gets the most
    print("candidates per set:", dict(collections.Counter(sset.values())))
    def take(k):
        pick.append(k); cov.update(T[k])
    def gain(k):
        return sum(W[x] for x in T[k] - cov) / (1 + size[k] / 150000.0)
    for s in DIRS:
        q = QUOTA.get(s, 6); mine = [k for k in T if sset[k] == s]; got = 0
        if s == "dx2":   # the user focus languages first: 5 each of ko and ja
            for lg in ("ko", "ja"):
                for _ in range(5):
                    c = [k for k in mine if k not in pick and ("mlang:" + lg) in T[k]]
                    if c: take(max(c, key=gain)); got += 1
        while got < q:
            c = [k for k in mine if k not in pick]
            if not c: break
            take(max(c, key=gain)); got += 1
    open(out, "w").write("\n".join(sorted(pick)) + "\n")
    print(f"{len(pick)} docs, {len(cov)} of {len(freq)} tokens covered; per set:", dict(collections.Counter(sset[k] for k in pick)))


if __name__ == "__main__":
    main()