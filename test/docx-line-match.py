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
# (DOCX_WORD_REFS: another folder of Word's prints, for a sample not checked in.)
WORD = os.environ.get("DOCX_WORD_REFS") or os.path.join(HERE, "corpus", "docx", "word")


def ignored():
    """The documents whose prints in WORD cannot be scored, from its
    IGNORE.txt ("<doc> <reason>" a line, # for a comment): word/ holds
    Mac Word's, so a print it reads wrongly leaves the Mac scores only and
    stays scored against word-win/. A document named on the command line
    is scored all the same."""
    try:
        with open(os.path.join(WORD, "IGNORE.txt"), encoding="utf-8") as f:
            return {l.split()[0] for l in f if l.strip() and not l.startswith("#")}
    except FileNotFoundError:
        return set()


def mupdf_text(pdf):
    """pdf-text.swift's rows from PyMuPDF: "p<page> <y> <x> <text>", y up
    from the page's top to the line's bottom (so negative), spaces dropped:
    a print on paper of another height still lines up from the top."""
    import pymupdf
    out = []
    with pymupdf.open(pdf) as d:
        for i, page in enumerate(d):
            h = page.rect.height
            # (Clipped glyphs too, as PDFKit reads them on the Mac: Word's
            # print of zh-1a3c7aa0 cuts its footer's "- 28 -" at the box
            # and still carries the last dash, and zh-6600d539 fifteen
            # lines. Read without them the two machines disagreed.)
            for b in page.get_text("dict", flags=pymupdf.TEXTFLAGS_DICT & ~pymupdf.TEXT_CLIP)["blocks"]:
                for l in b.get("lines", []):
                    # (Every space, a no-break one too: the page's text
                    # names what a print set there, and ours sets some.)
                    t = "".join(c for s in l["spans"] for c in s["text"] if not c.isspace())
                    x0 = l["bbox"][0]
                    # (By each piece's baseline, a fifth of its size under it,
                    # not by its box: a box is the face's own — Word's fonts
                    # report their descent, ours, drawn as Type 3 glyphs on
                    # Linux, their ink — and the same line read 2-4pt apart,
                    # zh-264d7516 84.6 here to the Mac's 95.0. And Word prints
                    # raised text (`w:position`) with a text rise, whose box
                    # PyMuPDF reaches down by the rise — zh-10e3a42b's
                    # clauses, 10.5pt up, read 10.5pt low. By baselines the
                    # corpus reads as PDFKit reads it on the Mac.)
                    # (Text set across only: a turned label's origin is no
                    # baseline under its box.)
                    # (Over the spans that hold text: a paragraph's closing
                    # space can sit in a line of its own baseline — in
                    # Word for Windows' print of EmbeddedDocument the
                    # worksheet's "4" shares a line with it, 4pt lower,
                    # and read so it paired with nothing.)
                    inked = [s for s in l["spans"] if s["text"].strip()] or l["spans"]
                    y1 = max(s["origin"][1] + 0.2 * s["size"] for s in inked) \
                        if tuple(round(d, 3) for d in l["dir"]) == (1, 0) else l["bbox"][3]
                    out.append(f"p{i + 1}	{round(-y1)}	{round(x0)}	{t}")
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
    rtl = any(unicodedata.bidirectional(c) in ("R", "AL") for c in a + b)

    # (And U+0000 for anything: a glyph Word's print maps to no
    # character at all — zh-92373179's embedded FangSong_GB2312 gives its
    # 招 so, 213 times, and its 招标 lines read as other lines.)
    def alike(p, q):
        return all(x == y or "\u2e80" <= x <= "\u2fdf" or "\u2e80" <= y <= "\u2fdf"
                   or (not rtl and (x == "\x00" or y == "\x00"))
                   for x, y in zip(p, q))
    # (Or end with the same four: a glyph a print's font gives no
    # character for is missing from its text, and a line that lost its
    # first character is still the same line.)
    def edges(p, q):
        if len(p) < 4 or len(q) < 4:
            return p == q
        return alike(p[:4], q[:4]) or alike(p[-4:], q[-4:])

    # PDFKit reads Word's Arabic in visual order and Skia's in logical
    # order. Compare reversed edges too for a bidi line; this is still
    # the same four-character edge check, not a full-line equality test.
    # Do not let unmapped glyphs stand for Arabic here: Geeza Pro's null
    # text previously gave rtl.docx 71% despite different line breaks.
    if edges(a, b) or (rtl and edges(a, b[::-1])):
        return True
    # (Word for Windows writes a bidi line's words in visual order, each
    # word's letters in logical order: its print of rtl.docx starts
    # "الاتحادفي…", the line's last two words. With the spaces gone the
    # words have no bounds and no four characters are an edge, so such
    # a line is the same line where it holds the same letters — every
    # one, which a line broken a word earlier or later does not; never
    # a null. The text names one glyph by its Persian or its Arabic letter
    # (ی/ي, ھ/ه, ک/ك), so both are folded, and only letters are counted:
    # Windows' print puts the closing stop at the line's visual start and
    # repeats a mark (ًا ًا ًا).)
    if rtl:
        fold = str.maketrans("یھکۀ", "يهكة")
        def letters(t):
            return sorted(c for c in t.translate(fold) if unicodedata.category(c).startswith("L"))
        p, q = letters(a), letters(b)
        return len(p) >= 4 and p == q
    return False


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    sys.stdout.reconfigure(encoding="utf-8")  # (a Windows console's code page has no ideographs)
    work = os.path.expanduser(sys.argv[1])
    key = sys.argv[2] if len(sys.argv) > 2 else None
    count = int(sys.argv[3]) if len(sys.argv) > 3 else 12
    # (DOCX_LINE_READER=mupdf: PyMuPDF on the Mac too, as on Linux —
    # the Windows series (lab/tools/sweep-win.sh) reads both sides so,
    # since PDFKit groups our Type 3 glyphs into other lines than Word's
    # real faces: zh-00f207f1's header row, a line a page.)
    mupdf = os.environ.get("DOCX_LINE_READER") == "mupdf"
    tool = os.path.join(work, "pdf-text") if sys.platform == "darwin" and not mupdf else None
    if tool and not os.access(tool, os.X_OK):
        subprocess.run(["swiftc", "-O", "-o", tool, os.path.join(HERE, "pdf-text.swift")], check=True)
    results = []
    skip = set() if key else ignored()
    for f in sorted(os.listdir(os.path.join(work, "pdf"))):
        if not f.endswith(".pdf") or (key and key not in f) or any(f.startswith(k) for k in skip):
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
