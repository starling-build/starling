#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""sheets-features.py PER_PAGE.tsv [PER_BOOK.tsv] — add a `features` column (last) to a Sheets round file (amd-8, 2026-11-22).
Per BOOK (a page cannot be tied to its sheet from the PDF alone), comma-separated, read from the workbook's own parts:
chart picture shape merged condfmt cjk rtl pivot table comment sparkline control fit header printarea wrap
("-" none, "?" book not found). One grep ranks a kind of page:  awk -F'\\t' '$8 ~ /merged/ && $3>5' per-page.tsv | sort -t$'\\t' -k3 -nr | head"""
import glob, os, re, sys, zipfile

CC = os.environ.get("CORPUS_CACHE", "/data/corpus-cache") + "/test/corpus/xlsx/books"
CJK = re.compile("[぀-ヿ㐀-鿿가-힯＀-￯]")
RTL = re.compile("[֐-ࣿ]")

def features(path):
    f = set()
    try:
        z = zipfile.ZipFile(path)
    except Exception:
        return "?"
    names = z.namelist()
    def has(p): return any(re.search(p, n) for n in names)
    if has(r"charts/chart\d*\.xml$|chartsheets/"): f.add("chart")
    if has(r"media/"): f.add("picture")
    if has(r"drawings/drawing\d*\.xml$"):
        for n in names:
            if re.search(r"drawings/drawing\d*\.xml$", n):
                x = z.read(n).decode("utf8", "replace")
                if "<xdr:sp" in x or "<xdr:cxnSp" in x: f.add("shape")
                if "<xdr:pic" in x: f.add("picture")
    if has(r"pivotTables/"): f.add("pivot")
    if has(r"tables/table"): f.add("table")
    if has(r"comments\d*\.xml$|threadedComments"): f.add("comment")
    if has(r"ctrlProps/|vmlDrawing"): f.add("control")
    text = ""
    for n in names:
        if re.search(r"worksheets/sheet\d+\.xml$", n):
            x = z.read(n).decode("utf8", "replace")
            if "<mergeCell " in x: f.add("merged")
            if "<conditionalFormatting" in x: f.add("condfmt")
            if "sparklineGroup" in x: f.add("sparkline")
            if 'rightToLeft="1"' in x: f.add("rtl")
            if "<pageSetup" in x and "fitToPage" in x or 'fitToPage="1"' in x: f.add("fit")
            if "<headerFooter" in x: f.add("header")
            if "<inlineStr" in x or "<is>" in x: text += x
        elif re.search(r"sharedStrings\.xml$", n):
            text += z.read(n).decode("utf8", "replace")
        elif re.search(r"workbook\.xml$", n):
            if "_xlnm.Print_Area" in z.read(n).decode("utf8", "replace"): f.add("printarea")
        elif re.search(r"styles\.xml$", n):
            if 'wrapText="1"' in z.read(n).decode("utf8", "replace"): f.add("wrap")
    if CJK.search(text): f.add("cjk")
    if RTL.search(text): f.add("rtl")
    return ",".join(sorted(f)) or "-"

def main():
    fs = sys.argv[1:] or sys.exit(__doc__)
    ix = {os.path.basename(p)[:-5]: p for p in glob.glob(CC + "/*.xlsx")}
    cache = {}
    for fn in fs:
        rows = [l.rstrip("\n").split("\t") for l in open(fn)]
        head = rows[0]
        if head[-1] == "features": head = head[:-1]; rows = [r[:-1] for r in rows]
        out = ["\t".join(head + ["features"])]
        for r in rows[1:]:
            if r[0].startswith("#"): out.append("\t".join(r)); continue
            if r[0] not in cache:
                try: cache[r[0]] = features(ix[r[0]]) if r[0] in ix else "?"
                except Exception: cache[r[0]] = "?"   # a deliberately broken workbook
            out.append("\t".join(r + [cache[r[0]]]))
        tmp = fn + f".tmp{os.getpid()}"; open(tmp, "w").write("\n".join(out) + "\n"); os.replace(tmp, fn)

if __name__ == "__main__":
    main()
