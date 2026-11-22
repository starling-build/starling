#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""sheets-features.py PER_PAGE.tsv [PER_BOOK.tsv] — add a `features` column (last) to a Sheets round file (amd-8, 2026-11-22).
Per PAGE in per-page.tsv (the page is tied to its sheet by matching Excel's page text to each sheet's cell and chart text, sheets in print order; per book in per-book.tsv: all sheets together), read from the workbook's own parts:
chart picture shape merged condfmt cjk rtl pivot table comment sparkline control fit header printarea wrap
("-" none, "?" book not found). One grep ranks a kind of page:  awk -F'\\t' '$8 ~ /merged/ && $3>5' per-page.tsv | sort -t$'\\t' -k3 -nr | head"""
import glob, os, re, sys, zipfile

CC = os.environ.get("CORPUS_CACHE", "/data/corpus-cache") + "/test/corpus/xlsx/books"
CJK = re.compile("[぀-ヿ㐀-鿿가-힯＀-￯]")
RTL = re.compile("[֐-ࣿ]")

def parse(path):
    """Per sheet (workbook order, printed ones only): (name, features set, token set); plus book-level features."""
    import xml.etree.ElementTree as ET
    z = zipfile.ZipFile(path)
    names = set(z.namelist())
    def rd(n): return z.read(n).decode("utf8", "replace")
    def rels(part):
        d, b = os.path.split(part)
        r = d + "/_rels/" + b + ".rels"
        out = {}
        if r in names:
            for m in re.finditer(r"<Relationship\b[^>]*>", rd(r)):
                t = m.group(0)
                i = re.search(r'\bId="([^"]*)"', t); g = re.search(r'\bTarget="([^"]*)"', t)
                if i and g:
                    tg = g.group(1)
                    out[i.group(1)] = os.path.normpath(tg[1:] if tg.startswith("/") else d + "/" + tg).replace("\\", "/")
        return out
    words = lambda t: set(re.findall(r"\w+", t))
    shared = []
    for n in names:
        if n.endswith("sharedStrings.xml"):
            shared = [words("".join(re.findall(r"<t[^>]*>([^<]*)</t>", x))) for x in re.split(r"<si>|<si ", rd(n))[1:]]
    book = set()
    wbn = next((n for n in names if n.endswith("workbook.xml")), None)
    sheets = []
    if wbn:
        wx = rd(wbn)
        if "_xlnm.Print_Area" in wx: book.add("printarea")
        wr = rels(wbn)
        for m in re.finditer(r"<sheet\b[^>]*>", wx):
            t = m.group(0)
            if re.search(r'state="(hidden|veryHidden)"', t): continue
            rid = re.search(r'r:id="([^"]*)"', t)
            nm = re.search(r'\bname="([^"]*)"', t)
            if rid and rid.group(1) in wr and wr[rid.group(1)] in names:
                sheets.append((nm.group(1) if nm else "", wr[rid.group(1)]))
    for n in names:
        if re.search(r"styles\.xml$", n) and 'wrapText="1"' in rd(n): book.add("wrap")
    out = []
    for nm, part in sheets:
        f, tok = set(), set()
        x = rd(part)
        r = rels(part)
        if "chartsheets/" in part: f.add("chart")
        for t in r.values():
            if re.search(r"drawings/drawing\d*\.xml$", t) and t in names:
                dx = rd(t)
                if "<xdr:sp" in dx or "<xdr:cxnSp" in dx: f.add("shape")
                if "<xdr:pic" in dx: f.add("picture")
                tok |= words(" ".join(re.findall(r"<a:t>([^<]*)</a:t>", dx)))
                for c in rels(t).values():
                    if re.search(r"charts/chart\d*\.xml$", c) and c in names:
                        f.add("chart")
                        cx = rd(c)
                        tok |= words(" ".join(re.findall(r"<a:t>([^<]*)</a:t>|<c:v>([^<]*)</c:v>", cx) and [a + b for a, b in re.findall(r"<a:t>([^<]*)</a:t>|<c:v>([^<]*)</c:v>", cx)]))
            if re.search(r"media/", t): f.add("picture")
            if re.search(r"pivotTables/", t): f.add("pivot")
            if re.search(r"tables/table", t): f.add("table")
            if re.search(r"comments\d*\.xml$|threadedComments", t): f.add("comment")
            if re.search(r"ctrlProps/|vmlDrawing", t): f.add("control")
        if "<mergeCell " in x: f.add("merged")
        if "<conditionalFormatting" in x: f.add("condfmt")
        if "sparklineGroup" in x: f.add("sparkline")
        if 'rightToLeft="1"' in x: f.add("rtl")
        if re.search(r'<pageSetUpPr\b[^>]*\bfitToPage="(1|true)"', x): f.add("fit")   # fitToPage="0" is not fit-to-page
        if "<headerFooter" in x: f.add("header")
        text = ""
        for m in re.finditer(r"<c\b([^>]*?)(?:/>|>(.*?)</c>)", x, re.S):
            at, body = m.groups()
            if body is None: continue
            v = re.search(r"<v>([^<]*)</v>", body)
            if 't="s"' in at and v and v.group(1).isdigit() and int(v.group(1)) < len(shared): tok |= shared[int(v.group(1))]; text += " ".join(shared[int(v.group(1))])
            elif v: tok |= words(v.group(1))
            i = re.findall(r"<t[^>]*>([^<]*)</t>", body) if "<is>" in body else []
            if i: tok |= words(" ".join(i)); text += " ".join(i)
        if CJK.search(text): f.add("cjk")
        if RTL.search(text): f.add("rtl")
        out.append((nm, f, tok))
    return book, out

def fmt(fs): return ",".join(sorted(fs)) or "-"

def assign(sheets, pages):
    """pages: list of word sets (Excel's print, in order). Sheets print in order, so pick a non-decreasing
    sheet per page maximising word overlap; a page with no overlap stays on the previous sheet."""
    n, m = len(sheets), len(pages)
    if not n: return [None] * m
    NEG = -1e9
    best = [[NEG] * n for _ in range(m)]; back = [[0] * n for _ in range(m)]
    for p in range(m):
        for s in range(n):
            sc = len(pages[p] & sheets[s][2])
            if p == 0: best[p][s] = sc - 0.001 * s; continue
            for q in range(s + 1):
                v = best[p - 1][q] + sc - (0 if q == s else 0.5)
                if v > best[p][s]: best[p][s] = v; back[p][s] = q
    s = max(range(n), key=lambda i: best[m - 1][i]); res = [0] * m
    for p in range(m - 1, -1, -1): res[p] = s; s = back[p][s]
    return res

def pagewords(book, nm):
    try:
        import pymupdf
        R = os.environ.get("CORPUS_CACHE", "/data/corpus-cache") + "/test/corpus/%s/" + os.environ.get("SHEETS_EXCEL", "excel-20261122")
        f = "%s/%s-orig.pdf" % (R % "xlsx", nm)
        d = pymupdf.open(f if os.path.exists(f) else "%s/%s-orig.pdf" % (R % "xlsx2", nm))
        return [set(re.findall(r"\w+", pg.get_text())) for pg in d]
    except Exception:
        return None

def main():
    fs = sys.argv[1:] or sys.exit(__doc__)
    ix = {os.path.basename(p)[:-5]: p for p in glob.glob(CC.replace("/xlsx/", "/xlsx2/") + "/*.xlsx")}   # the second set (xlsx2) first, then the first set wins on a clash
    ix.update({os.path.basename(p)[:-5]: p for p in glob.glob(CC + "/*.xlsx")})
    cache = {}
    def book_info(nm):
        if nm not in cache:
            try: cache[nm] = parse(ix[nm]) if nm in ix else None
            except Exception: cache[nm] = None   # a deliberately broken workbook
        return cache[nm]
    pgmap = {}
    for fn in fs:
        rows = [l.rstrip("\n").split("\t") for l in open(fn)]
        head = rows[0]
        if head[-1] == "features": head = head[:-1]; rows = [r[:-1] for r in rows]
        perpage = head[:2] == ["book", "page"]
        out = ["\t".join(head + ["features"])]
        for r in rows[1:]:
            if r[0].startswith("#"): out.append("\t".join(r)); continue
            info = book_info(r[0])
            if info is None: out.append("\t".join(r + ["?"])); continue
            book, sh = info
            if perpage:
                if r[0] not in pgmap:
                    pw = pagewords(book, r[0])
                    pgmap[r[0]] = assign(sh, pw) if pw else None
                a = pgmap[r[0]]
                pg = int(r[1]) - 1
                if a is not None and pg < len(a) and a[pg] is not None: f = sh[a[pg]][1] | book
                else: f = set().union(*[x[1] for x in sh]) | book if sh else book
            else:
                f = set().union(*[x[1] for x in sh]) | book if sh else book
            out.append("\t".join(r + [fmt(f)]))
        tmp = fn + f".tmp{os.getpid()}"; open(tmp, "w").write("\n".join(out) + "\n"); os.replace(tmp, fn)

if __name__ == "__main__":
    main()
