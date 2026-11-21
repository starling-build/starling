#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""test/pptx-line-match.py WORK [KEY [N]] — how many of PowerPoint's text lines this app sets in the same place.

The Word v2 line rule (test/docx-line-match.py, unchanged, imported) applied to Slides: every horizontal line
of PowerPoint for Windows's print (PPT_REFS, default test/corpus/pptx/powerpoint-win, else the corpus cache) and of ours
(WORK/pdf, from test/pptx-app-render.sh or `OfficeApp --deck-pdf`), slide by slide. A PowerPoint line is matched when
ours has one on the same slide within 3 pt of its height that starts or ends with the same four characters.
A deck's score is the share of PowerPoint's lines matched. A deck whose print has no text lines is left to the
visual score (the combined rule of test/tools/docx-combine.py).

Output rows are the v2 row format, "  95.0%  lines W/O  pages W/O  NAME", so docx-combine.py reads them.
With a KEY it names one deck and prints where it first parts from PowerPoint.
PPT_MATCH_JOBS=N scores in N processes.
"""
import importlib.util, os, sys

os.environ["DOCX_LINE_MATCH"] = "v2"
os.environ.setdefault("PPT_RTL_NORM", "1")
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("docx_line_match", os.path.join(HERE, "docx-line-match.py"))
M = importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)

def refs():
    for p in (os.environ.get("PPT_REFS"), os.path.join(HERE, "corpus", "pptx", "powerpoint-win"),
              os.path.join(os.environ.get("CORPUS_CACHE", "/data/corpus-cache"), "test/corpus/pptx/powerpoint-win")):
        if p and os.path.isdir(p) and os.listdir(p):
            return p
    sys.exit("pptx-line-match: no PowerPoint prints (set PPT_REFS)")

M.WORD = refs()
M.ignored = lambda: set()
_CTX = None

def _job(f):
    return M.score_document(*_CTX, f)

def main():
    if len(sys.argv) < 2:
        print(__doc__); return 2
    sys.stdout.reconfigure(encoding="utf-8")
    work = os.path.expanduser(sys.argv[1])
    key = sys.argv[2] if len(sys.argv) > 2 else None
    count = int(sys.argv[3]) if len(sys.argv) > 3 else 12
    names = [f for f in sorted(os.listdir(os.path.join(work, "pdf"))) if f.endswith(".pdf") and (not key or key in f)]
    jobs = 1 if key else int(os.environ.get("PPT_MATCH_JOBS") or 1)
    if jobs > 1 and len(names) > 1:
        import multiprocessing
        global _CTX
        _CTX = (None, work, key, count)
        with multiprocessing.get_context("fork").Pool(min(jobs, len(names))) as pool:
            order = sorted(names, key=lambda f: -os.path.getsize(os.path.join(work, "pdf", f)))
            results = [r for r in pool.imap_unordered(_job, order, chunksize=1) if r]
    else:
        results = [r for r in (M.score_document(None, work, key, count, f) for f in names) if r]
    if not key and results:
        results.sort()
        v = [r[0] for r in results if r[2] > 0]
        print(f"{len(results)} decks, {len(v)} with text lines: mean {100 * sum(v) / max(1, len(v)):.1f}% of PowerPoint's lines matched; "
              f"{sum(x >= .95 for x in v)} at 95% or more, {len(results) - len(v)} with no text lines (visual score)")
        for r in results:
            print(f"  {100 * r[0]:5.1f}%  lines {r[2]}/{r[3]}  pages {r[4][0]}/{r[4][1]}  {r[1]}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
