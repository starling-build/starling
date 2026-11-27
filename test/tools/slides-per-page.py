#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""slides-per-page.py WORK REFS OUT SHA — per deck and page, how many of PowerPoint's text lines ours matches (amd-8, 2026-11-22).
The scorer of test/pptx-line-match.py, one row per page, so workers can rank pages from a file. WORK/pdf holds our renders.
OUT starts with "# main SHA <date>" then: deck, page, matched, pp_lines, ours_lines, pct."""
import importlib.util, os, sys, time
from multiprocessing import Pool
work, refs, out, sha = sys.argv[1:5]
os.environ["DOCX_LINE_MATCH"] = "v2"; os.environ["DOCX_LINE_ROT"] = "0"; os.environ.setdefault("PPT_RTL_NORM", "1"); os.environ.setdefault("PPT_MIN_PT", "3")
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("d", os.path.join(here, "..", "docx-line-match.py"))
M = importlib.util.module_from_spec(spec); spec.loader.exec_module(M)
M.WORD = refs; M.ignored = lambda: set(); M.OFFPAGE = True

def job(f):
    res = []
    try:
        ref = os.path.join(refs, f[:-4] + "-orig.pdf")
        if not os.path.exists(ref): return res
        a = M.lines(None, ref, {}); b = M.lines(None, os.path.join(work, "pdf", f), {})
        ap, bp = {}, {}
        for r in a: ap.setdefault(r[0], []).append(r)
        for r in b: bp.setdefault(r[0], []).append(r)
        for p in sorted(ap):
            miss = M.unmatched(ap[p], bp.get(p, []))
            res.append((f[:-4], p, len(ap[p]) - len(miss), len(ap[p]), len(bp.get(p, []))))
    except Exception as e:
        sys.stderr.write(f"{f}: {e}\n")
    return res

if __name__ == "__main__":
    fs = sorted(x for x in os.listdir(os.path.join(work, "pdf")) if x.endswith(".pdf"))
    with Pool(int(os.environ.get("PPT_MATCH_JOBS", "16"))) as p: rows = p.map(job, fs)
    tmp = out + f".tmp{os.getpid()}"
    with open(tmp, "w") as o:
        o.write(f"# main {sha} {time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}\ndeck\tpage\tmatched\tpp_lines\tours_lines\tpct\n")
        for r in rows:
            for d, pg, m, t, u in r: o.write(f"{d}\t{pg}\t{m}\t{t}\t{u}\t{100*m/max(1,t):.1f}\n")
    os.replace(tmp, out)
