#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""test/docx-line-match.py WORK [KEY [N]] — how many of Word's lines this app
sets in the same place.

The page diff of test/docx-app-render.sh counts pixels, and a document whose
every line is one line late scores like one that is all wrong. This reads
the text instead: every line of Word's print (test/corpus/docx/word) and of
ours (WORK/pdf, from a sweep) as page, height on the page and text, and a
line of Word's is matched when ours has one on the same page, within 3pt
of its height, that starts or ends with the same four characters. So the score is
the share of the document that breaks into the same lines and pages, and
it drops at the first paragraph that does not — which is what to fix next.

    test/docx-line-match.py ~/starling-doc-check/app            # every document, worst first
    test/docx-line-match.py ~/starling-doc-check/app zh-3550    # one: where it first parts from Word
    test/docx-line-match.py ~/starling-doc-check/app zh-3550 30 # … and 30 lines from there

On a Mac PDFKit reads the lines (test/pdf-text.swift, compiled into WORK on
first use); anywhere else PyMuPDF does, into the same rows — so compare
scores from the same kind of machine, as with the page diff. Compatibility forms are folded (NFKC), since a PDF's
text names the glyph and the two sides' fonts name some ideographs apart.
"""
import os
import statistics
import subprocess
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
WORD = os.path.join(HERE, "corpus", "docx", "word")


def mupdf_text(pdf):
    """pdf-text.swift's rows from PyMuPDF: "p<page> <y> <x> <text>", y up
    from the page's foot to the line's bottom, spaces dropped."""
    import pymupdf
    out = []
    with pymupdf.open(pdf) as d:
        for i, page in enumerate(d):
            h = page.rect.height
            for b in page.get_text("dict")["blocks"]:
                for l in b.get("lines", []):
                    t = "".join(s["text"] for s in l["spans"]).replace(" ", "")
                    x0, _, _, y1 = l["bbox"]
                    out.append(f"p{i + 1}	{round(h - y1)}	{round(x0)}	{t}")
    return out


def lines(tool, pdf):
    if tool:
        out = subprocess.run([tool, pdf], capture_output=True, text=True).stdout.splitlines()
    else:
        out = mupdf_text(pdf)
    rows = []
    for l in out:
        p = l.split("\t")
        if len(p) < 4:
            continue
        # (Without the object character a print may carry for an inline box.)
        t = unicodedata.normalize("NFKC", p[3]).replace("\ufffc", "").strip()
        if t:
            rows.append((int(p[0][1:]), float(p[1]), float(p[2]), t))
    # PDFKit cuts a line where its fonts change: the pieces of one line
    # (same page, same height) are put back together, leftmost first.
    # (Leftmost first whatever their heights: a mark that hangs past the
    # margin is a piece of its own, a hair higher than its line.)
    rows.sort(key=lambda r: (r[0], -r[1], r[2]))
    groups = []
    for r in rows:
        if groups and groups[-1][0][0] == r[0] and abs(groups[-1][0][1] - r[1]) < 2.5:
            groups[-1].append(r)
        else:
            groups.append([r])
    merged = []
    for g in groups:
        g.sort(key=lambda r: r[2])
        merged.append((g[0][0], max(r[1] for r in g), g[0][2], "".join(r[3] for r in g)))
    return merged


def same_start(a, b):
    """Whether two lines begin (or end) with the same four characters. A PDF's text
    names a glyph by the first character its font maps to it, and for 民,
    長 or 青 that is the radical (⺠, ⻑, ⻘) in some faces: a radical
    stands for whatever is opposite it."""
    if len(a) < 4 or len(b) < 4:
        return a[:4] == b[:4]

    def alike(p, q):
        return all(x == y or "\u2e80" <= x <= "\u2fdf" or "\u2e80" <= y <= "\u2fdf" for x, y in zip(p, q))
    # (Or end with the same four: a glyph a print's font gives no
    # character for is missing from its text, and a line that lost its
    # first character is still the same line.)
    return alike(a[:4], b[:4]) or alike(a[-4:], b[-4:])


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    sys.stdout.reconfigure(encoding="utf-8")  # (a Windows console's code page has no ideographs)
    work = os.path.expanduser(sys.argv[1])
    key = sys.argv[2] if len(sys.argv) > 2 else None
    count = int(sys.argv[3]) if len(sys.argv) > 3 else 12
    tool = os.path.join(work, "pdf-text") if sys.platform == "darwin" else None
    if tool and not os.access(tool, os.X_OK):
        subprocess.run(["swiftc", "-O", "-o", tool, os.path.join(HERE, "pdf-text.swift")], check=True)
    results = []
    for f in sorted(os.listdir(os.path.join(work, "pdf"))):
        if not f.endswith(".pdf") or (key and key not in f):
            continue
        ref = os.path.join(WORD, f[:-4] + "-orig.pdf")
        if not os.path.exists(ref):
            continue
        a, b = lines(tool, ref), lines(tool, os.path.join(work, "pdf", f))
        by_page = {}
        for r in b:
            by_page.setdefault(r[0], []).append(r)
        missed = [r for r in a if not any(abs(o[1] - r[1]) <= 3 and same_start(o[3], r[3]) for o in by_page.get(r[0], []))]
        pages = (max((r[0] for r in a), default=0), max((r[0] for r in b), default=0))
        results.append(((len(a) - len(missed)) / max(1, len(a)), f[:-4], len(a), len(b), pages))
        if key:
            print(f"{f[:-4]}: Word {len(a)} lines on {pages[0]} pages, ours {len(b)} on {pages[1]}, matched {len(a) - len(missed)}")
            if missed:
                at = a.index(missed[0])
                first = a[max(0, at - 3)]
                print("--- Word, from three lines before the first that has no match")
                for r in a[max(0, at - 3):at + count]:
                    print(f"  p{r[0]} y{r[1]:5.0f} x{r[2]:5.0f} {r[3][:50]}")
                print("--- ours, from the same place")
                for r in [r for r in b if (r[0], -r[1]) >= (first[0], -(first[1] + 25))][:count + 3]:
                    print(f"  p{r[0]} y{r[1]:5.0f} x{r[2]:5.0f} {r[3][:50]}")
    if not key and results:
        results.sort()
        v = [r[0] for r in results]
        print(f"{len(v)} documents: mean {100 * statistics.mean(v):.1f}% of Word's lines matched, median {100 * statistics.median(v):.1f}%; "
              f"{sum(x >= .95 for x in v)} at 95% or more, {sum(x >= .5 for x in v)} at half or more; "
              f"{sum(r[4][0] == r[4][1] for r in results)} with Word's page count")
        for r in results:
            print(f"  {100 * r[0]:5.1f}%  lines {r[2]}/{r[3]}  pages {r[4][0]}/{r[4][1]}  {r[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
