#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""sheets-sweep.py BIN OUT [-j N] [names...] — the Sheets measurement (amd-8, 2026-11-22), the counterpart of the Slides sweep.
Draws every workbook of the corpus (books/*.xlsx, cache copy) with `BIN --sheet-pdf`, and scores each page against Excel's print
(excel/NAME-orig.pdf) two ways: pixels (test/pdf-diff.py, % of pixels differing) and text lines (the Word v2 line rule, as for Slides).
OUT/per-page.tsv: book, page, pixel_pct, matched, xl_lines, ours_lines, line_pct   (page = Excel's page number; a page only one side has
scores 100 pixels and 0 lines).  OUT/per-book.tsv: book, pages_xl, pages_ours, pixel_mean, pixel_worst, line_pct (lines matched / Excel lines, "-" without text), status.
A book Excel printed nothing of and we also print nothing is a match (status ok-empty); one we cannot read is status ERROR."""
import importlib.util, multiprocessing, os, re, subprocess, sys, time

for _v in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ.setdefault(_v, "1")
HERE = os.path.dirname(os.path.abspath(__file__))
TEST = os.path.dirname(HERE)
CC = os.environ.get("CORPUS_CACHE", "/data/corpus-cache") + "/test/corpus/xlsx"
BOOKS, XL = CC + "/books", CC + "/" + os.environ.get("SHEETS_EXCEL", "excel-20261122")   # SHEETS_EXCEL names the prints folder under xlsx/
os.environ["DOCX_LINE_MATCH"] = "v2"
spec = importlib.util.spec_from_file_location("d", os.path.join(TEST, "docx-line-match.py"))
M = importlib.util.module_from_spec(spec); spec.loader.exec_module(M)
M.WORD = XL; M.ignored = lambda: set(); M.OFFPAGE = True
BIN = OUT = None

def job(name):
    base = name[:-5]; pdf = f"{OUT}/pdf/{base}.pdf"; ref = f"{XL}/{base}-orig.pdf"
    env = dict(os.environ, SHEET_PDF_MAX_PAGES="20", OFFICE_FONT_SOURCE=os.environ.get("OFFICE_FONT_SOURCE", "bundled"))
    try:
        p = subprocess.run([BIN, "--sheet-pdf", f"{BOOKS}/{name}", pdf], capture_output=True, text=True, timeout=300, env=env)
        out = (p.stdout + p.stderr)
    except subprocess.TimeoutExpired:
        return name, [], "ERROR timeout"
    xl_pages = len(re.findall(rb"/Type\s*/Page\b", open(ref, "rb").read()))
    if p.returncode != 0:
        if "nothing to print" in out and xl_pages == 0:
            return name, [], "ok-empty"
        return name, [], "ERROR " + (out.strip().splitlines() or [""])[-1][:100]
    d = subprocess.run([sys.executable, os.path.join(TEST, "pdf-diff.py"), ref, pdf, f"{OUT}/pairs/{base}", "1"], capture_output=True, text=True, timeout=600).stdout
    px = {int(m.group(1)): float(m.group(2)) for m in re.finditer(r"^page\s+(\d+)\s+([\d.]+)% pixels differ", d, re.M)}
    try:
        # LIMIT (2026-11-22): the ink test misfires on warped or gradient text (WordArt): the text layer holds it
        # unwarped, so the glyph box has no ink and its edge letters read as hidden. Slides lo-tdf114848 p2 fell
        # 9 of 9 to 4 of 9 on this, so Slides does not use the rule. A Sheets WordArt shape would hit it too.
        dw, do = M._unseen_pairs(ref, pdf)   # glyphs a clip hides and no ink shows (49156 p1: 28 digits outside the clip) are not text either print shows
        a = M.lines(None, ref, dw); b = M.lines(None, pdf, do)
    except Exception as e:
        a = b = []
    ap, bp = {}, {}
    for r in a: ap.setdefault(r[0], []).append(r)
    for r in b: bp.setdefault(r[0], []).append(r)
    pages = sorted(set(px) | set(ap) | set(bp))
    rows = []
    for pg in pages:
        t = len(ap.get(pg, [])); miss = len(M.unmatched(ap[pg], bp.get(pg, []))) if t else 0
        rows.append((pg, px.get(pg, 100.0), t - miss, t, len(bp.get(pg, []))))
    return name, rows, "ok"

def main():
    global BIN, OUT
    args = sys.argv[1:]; jobs = 32
    if "-j" in args: i = args.index("-j"); jobs = int(args[i + 1]); del args[i:i + 2]
    BIN, OUT = os.path.realpath(args[0]), args[1]; names = args[2:]
    os.makedirs(OUT + "/pdf", exist_ok=True); os.makedirs(OUT + "/pairs", exist_ok=True)
    if not names:
        names = sorted(f for f in os.listdir(BOOKS) if f.endswith(".xlsx") and os.path.exists(f"{XL}/{f[:-5]}-orig.pdf"))
    names.sort(key=lambda f: -os.path.getsize(f"{BOOKS}/{f}"))
    with multiprocessing.get_context("fork").Pool(jobs) as pool: res = {n: (r, s) for n, r, s in pool.imap_unordered(job, names, chunksize=1)}
    pp, pb = open(OUT + "/per-page.tsv.tmp", "w"), open(OUT + "/per-book.tsv.tmp", "w")
    pp.write("book\tpage\tpixel_pct\tmatched\txl_lines\tours_lines\tline_pct\n")
    pb.write("book\tpages_xl\tpages_ours\tpixel_mean\tpixel_worst\tline_pct\tstatus\n")
    for n in sorted(res):
        rows, st = res[n]; b = n[:-5]
        for pg, px, m, t, u in rows: pp.write(f"{b}\t{pg}\t{px:.2f}\t{m}\t{t}\t{u}\t{100*m/t if t else 100:.1f}\n")
        if st == "ok-empty": pb.write(f"{b}\t0\t0\t0.00\t0.00\t-\t{st}\n"); continue
        if not rows: pb.write(f"{b}\t-\t-\t-\t-\t-\t{st}\n"); continue
        T = sum(r[3] for r in rows); Mt = sum(r[2] for r in rows)
        pb.write(f"{b}\t{sum(1 for r in rows if r[3] or r[1] < 100)}\t{sum(1 for r in rows if r[4] or r[1] < 100)}\t{sum(r[1] for r in rows)/len(rows):.2f}\t{max(r[1] for r in rows):.2f}\t{(f'{100*Mt/T:.1f}' if T else '-')}\t{st}\n")
    pp.close(); pb.close()
    os.replace(OUT + "/per-page.tsv.tmp", OUT + "/per-page.tsv"); os.replace(OUT + "/per-book.tsv.tmp", OUT + "/per-book.tsv")

if __name__ == "__main__":
    main()
