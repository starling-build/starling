#!/usr/bin/env python3
"""gate-sample.py OUT [N] — the render gate's COVERAGE sample (amd-8, 2026-11-20): about N (60) documents of the gated
sets (756 lo xa xb xd xs) chosen greedily so that every feature fingerprint token of test/tools/docx-census.py (structure,
XML features, faces, language/script) is carried by at least one picked document, rarest tokens first, small files (<=300 KB,
the fast renders) preferred. Every set gets at least 3 documents. The gate renders these plus the documents named in the
commit messages; the full sets run in the hourly rounds. Fixed once built: rebuild only when the sets change."""
import collections, importlib.util, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)   # importable by name so the worker pool can unpickle
cen = importlib.import_module("docx-census"); feat = importlib.import_module("docx-features")
def main():
    R = os.path.dirname(os.path.dirname(HERE)); C = os.environ.get("STARLING_CORPUS", "/data/corpus-cache")
    DIRS = {"756": f"{R}/test/corpus/docx/docs", "lo": f"{R}/test/corpus/docx/lo/docs"}
    for s in ("xa", "xb", "xd", "xs"): DIRS[s] = f"{C}/staging/{s}/docs"
    out = sys.argv[1]; N = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    fm = cen.font_map(); stat = collections.Counter(); T = {}; size = {}; sset = {}
    for s, d in DIRS.items():
        for k, r in feat.rows_for(d, jobs=8).items():
            p = os.path.join(d, k if k.endswith(".docx") else k + ".docx")
            stem = k[:-5] if k.endswith(".docx") else k
            if not os.path.exists(p) or os.path.getsize(p) > 300 * 1024: continue
            t = cen.struct_tokens(r) | cen.xml_tokens(p) | cen.face_tokens(r.get("fonts") or [], fm, stat)
            t |= {"lang:" + str(x) for x in (r.get("langs") or [])} | {"set:" + s}
            T[stem] = frozenset(t); size[stem] = os.path.getsize(p); sset[stem] = s
    freq = collections.Counter(x for t in T.values() for x in t)
    W = {x: 1.0 / f for x, f in freq.items()}
    pick, cov = [], set()
    def take(k):
        pick.append(k); cov.update(T[k])
    for s in DIRS:   # a floor per set
        c = sorted((k for k in T if sset[k] == s), key=lambda k: -sum(W[x] for x in T[k]))
        for k in c[:3]: take(k)
    while len(pick) < N:
        best = max((k for k in T if k not in pick), key=lambda k: (sum(W[x] for x in T[k] - cov) / (1 + size[k] / 150000.0)), default=None)
        if best is None or not (T[best] - cov): break
        take(best)
    open(out, "w").write("\n".join(sorted(pick)) + "\n")
    print(f"{len(pick)} docs, {len(cov)} of {len(freq)} tokens covered; per set:", dict(collections.Counter(sset[k] for k in pick)))


if __name__ == "__main__":
    main()