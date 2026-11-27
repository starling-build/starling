#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""sheets-sweep.py BIN OUT [-j N] [names...] — (names: books from any set, xlsx, xlsx2 or r3, with or without extension; no names = every set)
 the Sheets measurement (amd-8, 2026-11-22), the counterpart of the Slides sweep.
Draws every workbook of the corpus (books/*.xlsx, cache copy) with `BIN --sheet-pdf`, and scores each page against Excel's print
(excel/NAME-orig.pdf) two ways: pixels (test/pdf-diff.py, % of pixels differing) and text lines (the Word v2 line rule, as for Slides).
OUT/per-page.tsv: book, page, pixel_pct, matched, xl_lines, ours_lines, line_pct   (page = Excel's page number; a page only one side has
scores 100 pixels and 0 lines).  OUT/per-book.tsv: book, pages_xl, pages_ours, pixel_mean, pixel_worst, line_pct (lines matched / Excel lines, "-" without text), status.
A book Excel printed nothing of and we also print nothing is a match (status ok-empty); one we cannot read is status ERROR."""
import hashlib, importlib.util, json, multiprocessing, os, re, subprocess, sys, time

for _v in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS"):
    os.environ.setdefault(_v, "1")
HERE = os.path.dirname(os.path.abspath(__file__))
TEST = os.path.dirname(HERE)
CC = os.environ.get("CORPUS_CACHE", "/data/corpus-cache") + "/test/corpus/xlsx"
BOOKS, XL = CC + "/books", CC + "/" + os.environ.get("SHEETS_EXCEL", "excel-20261122")   # SHEETS_EXCEL names the prints folder under xlsx/
os.environ["DOCX_LINE_MATCH"] = "v2"
os.environ["DOCX_LINE_ROT"] = "0"   # Slides/Sheets keep turned text as before; only Word reads it in its own frame (2026-11-27)
spec = importlib.util.spec_from_file_location("d", os.path.join(TEST, "docx-line-match.py"))
M = importlib.util.module_from_spec(spec); spec.loader.exec_module(M)
M.WORD = XL; M.ignored = lambda: set(); M.OFFPAGE = True
BIN = OUT = None
REUSE = {}   # stem -> (pdf sha1, rows, seconds) from a previous sweep's score-cache.tsv (see load_reuse)

def scorer_sha():
    # the scoring code: a cached score is valid only for the same scorer
    h = hashlib.sha1()
    for f in (os.path.abspath(__file__), os.path.join(TEST, "pdf-diff.py"), os.path.join(TEST, "docx-line-match.py")): h.update(open(f, "rb").read())
    return h.hexdigest()

def load_reuse(d):
    # SHEETS_REUSE=DIR (a previous sweep's OUT): a book whose PDF is byte-identical to the one scored there takes that score.
    # Exact, not approximate: the same PDF and the same scorer give the same rows. Ignored when the scorer differs.
    f = (d or "") + "/score-cache.tsv"
    if not d or not os.path.exists(f): return {}
    L = open(f).read().splitlines()
    if not L or L[0] != "#scorer\t" + scorer_sha(): return {}
    r = {}
    for l in L[1:]:
        k, sha, sec, js = l.split("\t", 3); r[k] = (sha, [tuple(x) for x in json.loads(js)], float(sec))
    return r
# A second set (xlsx2: 480 xlsx + 100 xls, 2026-11-22, amd-9's dev set; only books whose export.tsv verdict is "pdf" have a complete print). SHEETS_SETS names the sets.
CC2 = os.environ.get("CORPUS_CACHE", "/data/corpus-cache") + "/test/corpus/xlsx2"
BOOKS2, XL2 = CC2 + "/books", CC2 + "/" + os.environ.get("SHEETS_EXCEL", "excel-20261122")

# Third set (xlsx-cjk-r3, 2026-11-23: ko xlsx/xls, zh, ja; 6 folders, Excel prints in <folder>/excel-win/<id>-orig.pdf, an .xls book prints to <id>-orig.pdf too).
CC3 = os.environ.get("CORPUS_CACHE", "/data/corpus-cache") + "/test/corpus/xlsx-cjk-r3"
def refpdf(xl, name):
    for b in (stem(name), name.rsplit(".", 1)[0]):
        if os.path.exists(f"{xl}/{b}-orig.pdf"): return f"{xl}/{b}-orig.pdf"
    return f"{xl}/{stem(name)}-orig.pdf"

def refnow(ref):
    """The wall time Excel printed the reference PDF (its /CreationDate), so a book with NOW()/TODAY() is scored for layout, not for a date mismatch.
    No readable date: one fixed time. Same value for base and PR draws (amd-8, 2026-11-25)."""
    try:
        with open(ref, "rb") as f: d = f.read()
        m = re.search(rb"/CreationDate\s*\(D:(\d{4})(\d\d)(\d\d)(\d\d)(\d\d)(\d\d)", d)
        if m: return "%s-%s-%sT%s:%s:%s" % tuple(x.decode() for x in m.groups())
    except OSError: pass
    return "2026-10-30T12:00:00"

def stem(name): return name[:-5] if name.endswith(".xlsx") else name   # an .xls book keeps its extension: it prints to NAME.xls-orig.pdf

def job(item):
    name, books, xl = item
    base = stem(name); pdf = f"{OUT}/pdf/{base}.pdf"; ref = refpdf(xl, name); t0 = time.time()
    M.WORD = xl
    env = dict(os.environ, SHEET_PDF_MAX_PAGES="20", OFFICE_FONT_SOURCE=os.environ.get("OFFICE_FONT_SOURCE", "bundled"),
               OFFICE_NOW=os.environ.get("OFFICE_NOW") or refnow(ref))  # fixed clock: NOW()/TODAY() draw the day Excel printed the reference, the same in base and PR
    try:
        p = subprocess.run([BIN, "--sheet-pdf", f"{books}/{name}", pdf], capture_output=True, text=True, timeout=300, env=env)
        out = (p.stdout + p.stderr)
    except subprocess.TimeoutExpired:
        return name, [], "ERROR timeout", "", time.time() - t0
    xl_pages = len(re.findall(rb"/Type\s*/Page\b", open(ref, "rb").read()))
    if p.returncode != 0:
        if "nothing to print" in out and xl_pages == 0:
            return name, [], "ok-empty", "", time.time() - t0
        return name, [], "ERROR " + (out.strip().splitlines() or [""])[-1][:100], "", time.time() - t0
    sha = hashlib.sha1(open(pdf, "rb").read()).hexdigest()
    if base in REUSE and REUSE[base][0] == sha: return name, REUSE[base][1], "ok", sha, time.time() - t0
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
    return name, rows, "ok", sha, time.time() - t0

def locate(name):
    """(name, books folder, Excel prints folder) of a named book, searched in xlsx, xlsx2, then each r3 folder; None if no set holds it.
    A name may carry its extension or not (an .xlsx book is also found by its bare stem)."""
    cands = [name] if name.endswith((".xlsx", ".xls")) else [name + ".xlsx", name + ".xls", name]
    where = [(BOOKS, XL), (BOOKS2, XL2)]
    if os.path.isdir(CC3): where += [(f"{CC3}/{d}", f"{CC3}/{d}/excel-win") for d in sorted(os.listdir(CC3)) if os.path.isdir(f"{CC3}/{d}")]
    for c in cands:
        for bk, xl in where:
            if os.path.isfile(f"{bk}/{c}"): return (c, bk, xl)
    return None

def main():
    global BIN, OUT
    args = sys.argv[1:]; jobs = 32
    if "-j" in args: i = args.index("-j"); jobs = int(args[i + 1]); del args[i:i + 2]
    BIN, OUT = os.path.realpath(args[0]), args[1]; names = args[2:]
    if not os.environ.get("STARLING_ICU"):   # the ICU data of the engine the binary loads, as docx-pair.sh and pptx-app-render.sh set it: without it Thai and other dictionary-break text loses its line breaks
        ldd = subprocess.run(["ldd", BIN], capture_output=True, text=True).stdout
        eng = next((l.split("=>")[1].split()[0] for l in ldd.splitlines() if "libflutter_engine.so" in l and "=>" in l), "")
        for d in (os.path.dirname(eng), os.environ.get("STARLING_ENGINE_OUT", "")):
            if d and os.path.isfile(d + "/icudtl.dat"):
                os.environ["STARLING_ICU"] = d + "/icudtl.dat"; break
    if not os.path.isfile(os.environ.get("STARLING_ICU", "")):
        sys.exit(f"sheets-sweep: no ICU data (icudtl.dat) found for {BIN}: set STARLING_ICU")
    os.makedirs(OUT + "/pdf", exist_ok=True); os.makedirs(OUT + "/pairs", exist_ok=True)
    items = []
    for n in names:
        it = locate(n)
        if not it: sys.exit(f"sheets-sweep: no book named {n} in any set")
        items.append(it)
    if not names:
        sets = os.environ.get("SHEETS_SETS", "xlsx,xlsx2,r3").split(",")
        if "xlsx" in sets:
            items += [(f, BOOKS, XL) for f in sorted(os.listdir(BOOKS)) if f.endswith(".xlsx") and os.path.exists(f"{XL}/{f[:-5]}-orig.pdf")]
        if "xlsx2" in sets and os.path.exists(f"{XL2}/export.tsv"):
            ok = {l.split("\t")[0] for l in open(f"{XL2}/export.tsv") if l.rstrip("\n").endswith("\tpdf")}
            items += [(f, BOOKS2, XL2) for f in sorted(os.listdir(BOOKS2)) if f in ok and os.path.exists(f"{XL2}/{stem(f)}-orig.pdf")]
    if not names and "r3" in os.environ.get("SHEETS_SETS", "xlsx,xlsx2,r3").split(","):
        for d in sorted(os.listdir(CC3)) if os.path.isdir(CC3) else []:
            bk, xl = f"{CC3}/{d}", f"{CC3}/{d}/excel-win"
            items += [(f, bk, xl) for f in sorted(os.listdir(bk)) if f.endswith((".xlsx", ".xls")) and os.path.exists(refpdf(xl, f))]
    # slowest first (seconds from the reused sweep when there is one, else file size): the few heavy books must not start last
    global REUSE
    REUSE = load_reuse(os.environ.get("SHEETS_REUSE"))
    items.sort(key=lambda t: (-REUSE[stem(t[0])][2] if stem(t[0]) in REUSE else 0, -os.path.getsize(f"{t[1]}/{t[0]}")))
    res = {}; cache = {}
    with multiprocessing.get_context("fork").Pool(jobs) as pool:
        for n, r, s, sha, sec in pool.imap_unordered(job, items, chunksize=1):
            res[n] = (r, s)
            if s == "ok" and sha: cache[stem(n)] = (sha, r, sec)
    with open(OUT + "/score-cache.tsv.tmp", "w") as f:
        f.write("#scorer\t" + scorer_sha() + "\n")
        for k in sorted(cache): f.write(f"{k}\t{cache[k][0]}\t{cache[k][2]:.2f}\t{json.dumps(cache[k][1])}\n")
    os.replace(OUT + "/score-cache.tsv.tmp", OUT + "/score-cache.tsv")
    print(f"sheets-sweep: {len(items)} books, {sum(1 for k, v in cache.items() if k in REUSE and REUSE[k][0] == v[0])} scored from the reused sweep", flush=True)
    pp, pb = open(OUT + "/per-page.tsv.tmp", "w"), open(OUT + "/per-book.tsv.tmp", "w")
    pp.write("book\tpage\tpixel_pct\tmatched\txl_lines\tours_lines\tline_pct\n")
    pb.write("book\tpages_xl\tpages_ours\tpixel_mean\tpixel_worst\tline_pct\tstatus\n")
    for n in sorted(res):
        rows, st = res[n]; b = stem(n)
        for pg, px, m, t, u in rows: pp.write(f"{b}\t{pg}\t{px:.2f}\t{m}\t{t}\t{u}\t{100*m/t if t else 100:.1f}\n")
        if st == "ok-empty": pb.write(f"{b}\t0\t0\t0.00\t0.00\t-\t{st}\n"); continue
        if not rows: pb.write(f"{b}\t-\t-\t-\t-\t-\t{st}\n"); continue
        T = sum(r[3] for r in rows); Mt = sum(r[2] for r in rows)
        pb.write(f"{b}\t{sum(1 for r in rows if r[3] or r[1] < 100)}\t{sum(1 for r in rows if r[4] or r[1] < 100)}\t{sum(r[1] for r in rows)/len(rows):.2f}\t{max(r[1] for r in rows):.2f}\t{(f'{100*Mt/T:.1f}' if T else '-')}\t{st}\n")
    pp.close(); pb.close()
    os.replace(OUT + "/per-page.tsv.tmp", OUT + "/per-page.tsv"); os.replace(OUT + "/per-book.tsv.tmp", OUT + "/per-book.tsv")

if __name__ == "__main__":
    main()
