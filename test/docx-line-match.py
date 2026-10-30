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

DOCX_LINE_MATCH=v2 (opt-in, PyMuPDF only; the default is unchanged) reads
lines from the page's glyphs instead of the reader's lines: whitespace
takes no part, a line is the glyphs on one baseline (`mupdf_glyphs`), and a
line set apart in pieces is matched piece by piece (`found`) — so that a
print's trailing space, a few tenths of a point between cells, or two
labels sharing a baseline no longer score as misses.
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


# DOCX_LINE_MATCH=v2: lines from the page's glyphs, not the reader's lines.
# (Opt-in, so that a pair under way keeps its meaning; v1 stays the default.)
V2 = os.environ.get("DOCX_LINE_MATCH") == "v2"


def _inkless(c):
    """A character that draws nothing a line could be told by: a space of
    any width (a no-break one, U+3000) or a format or control character
    (a zero-width space or joiner). (One of the private use area does
    draw: it stands, as an unmapped glyph does, for whatever is opposite
    it — zh-dc9e54ca's "☐" boxes are U+F0A8 in Word's print. So does a
    glyph read as U+0000, which its font maps to no character: our Thai,
    zh-6a4fc013's, is drawn so.)"""
    return c != "\x00" and (c.isspace() or unicodedata.category(c) in ("Cf", "Cc"))


def mupdf_glyphs(pdf):
    """v2's rows, from the page's glyphs rather than the reader's lines.
    Each line of text set across is the inked glyphs on one baseline:
    grouped by their origins (the baseline itself — a fifth of the size
    under it, which v1 reads a line by and a row still reports, puts
    zh-d8247da5's 10pt stand-in "A" 0.4pt off the 12pt "※公有" whose
    baseline it shares) within 2.5pt under the first of them, as v1 puts
    the reader's lines together. (Not by gaps of a few tenths: a table's
    cells stand that far apart in one print and on one baseline in the
    other — zh-c399c91a's number cells, 0.7pt off their rows in Word's.)
    Whitespace takes no part (`_inkless`): Word's print of zh-77079ee8
    closes its number cell "1 " with a space glyph, and the reader's line
    ran through it into the next cell's "需求評估及服", 10pt higher, where
    ours, with no space, read two. Turned text is grouped by its own baseline
    (below), and its box is the inked glyphs': zh-c4f2be3b's upright page
    number " - 5 - " reached 7pt lower in Word's print by its closing
    space."""
    import pymupdf
    out = []
    with pymupdf.open(pdf) as d:
        for i, page in enumerate(d):
            glyphs = []
            turned = []
            line_no = 0
            # (Clipped glyphs too, as v1 reads them: the reader drops a
            # glyph the clip does not wholly hold, and Word's footer boxes
            # clip their page numbers — zh-f47b8a74's "10" read "1", and our
            # Thai, drawn inside a clip, read as nothing.)
            for b in page.get_text("rawdict", flags=pymupdf.TEXTFLAGS_RAWDICT & ~pymupdf.TEXT_CLIP)["blocks"]:
                for l in b.get("lines", []):
                    line_no += 1
                    across = tuple(round(v, 3) for v in l["dir"]) == (1, 0)
                    inked = [(c, s["size"]) for s in l["spans"] for c in s["chars"] if not _inkless(c["c"])]
                    if not inked:
                        continue
                    if across:
                        # (The reader's line, parted where its baseline moves
                        # on by more than 1pt — two cells' text the reader ran
                        # together: zh-093d0f9a's "計畫" a cell over its row's
                        # "工作計畫名稱…", 8pt apart in ours — but not at a mark
                        # markedly smaller than its text, raised or lowered
                        # against it: a footnote's "1" stays the line's.)
                        parts, big, at = [], 0.0, None
                        for s in l["spans"]:
                            for c in s["chars"]:
                                if _inkless(c["c"]):
                                    continue
                                z, y = s["size"], c["origin"][1]
                                if parts and z < 0.85 * big:
                                    parts[-1].append((c, z))
                                    continue
                                # (And the text a mark comes first in: Word's
                                # zh-344a8d08 starts a line of its 16pt text
                                # with an 8pt "1" 8pt higher.)
                                if parts and 0.85 * z > big:
                                    big, at = z, y
                                    parts[-1].append((c, z))
                                    continue
                                if not parts or abs(y - at) > 1.0:
                                    parts.append([])
                                    big, at = z, y
                                elif z > big:
                                    big, at = z, y
                                parts[-1].append((c, z))
                        def base(q):
                            top = max(z for _, z in q)
                            return statistics.median(c["origin"][1] for c, z in q if z == top)
                        for q in parts:
                            line_no += 1
                            at = base(q)
                            for k, (c, size) in enumerate(q):
                                ch = "\x00" if unicodedata.category(c["c"]) == "Co" else c["c"]
                                glyphs.append((at, c["origin"][1] + 0.2 * size, c["origin"][0], ch, c["bbox"][2], size, line_no, k))
                    else:
                        d = tuple(round(v, 2) for v in l["dir"])
                        for c, size in inked:
                            turned.append((d, c["origin"][0], c["origin"][1], c["bbox"], c["c"], size))
            glyphs.sort()
            row = []
            for g in glyphs + [None]:
                if g is not None and (not row or g[0] - row[0][0] < 2.5):
                    row.append(g)
                    continue
                if row:
                    # (Leftmost first by the reader's lines, each in its own
                    # order: a Thai vowel or tone mark is a glyph of its own,
                    # its origin left of the letter it sits on, and zh-6a4fc013
                    # read by position alone scrambled every Thai line.)
                    left = {}
                    for r in row:
                        left[r[6]] = min(left.get(r[6], r[2]), r[2])
                    row.sort(key=lambda r: (left[r[6]], r[6], r[7]))
                    # (With its pieces, where four fifths of its
                    # glyphs' sizes stand empty between two: see `found`.)
                    pieces = [[row[0]]]
                    for prev, g2 in zip(row, row[1:]):
                        if g2[2] - prev[4] > 0.8 * max(prev[5], g2[5]):
                            pieces.append([])
                        pieces[-1].append(g2)
                    parts = "\x1e".join(f"{round(q[0][2])}\x1f{round(max(r[4] for r in q))}\x1f{''.join(r[3] for r in q)}"
                                         for q in pieces) if len(pieces) > 1 else ""
                    out.append(f"p{i + 1}\t{round(-max(r[1] for r in row))}\t{round(row[0][2])}\t{''.join(r[3] for r in row)}"
                               f"\t{parts}\t{round(max(r[4] for r in row))}")
                row = [g] if g is not None else []
            # (Turned text by its own baseline too — a column of glyphs,
            # one origin across — parted where a glyph's size stands empty
            # along it: zh-b24b396a's p13 sets each "30" turned 270°, its
            # glyphs where Word's are to 0.2pt, and the reader took one
            # print's "3" and "0" for a line and the other's for two.)
            turned.sort(key=lambda g: (g[0], round(g[1] / 0.6), g[2]))
            run = []
            for g in turned + [None]:
                if g is not None and run and g[0] == run[-1][0] and abs(g[1] - run[-1][1]) <= 0.6 \
                        and g[3][1] - run[-1][3][3] <= max(g[5], run[-1][5]):
                    run.append(g)
                    continue
                if run:
                    text = "".join(r[4] for r in (run if run[0][0][1] > 0 else reversed(run)))
                    out.append(f"p{i + 1}\t{round(-max(r[3][3] for r in run))}\t{round(min(r[3][0] for r in run))}\t{text}"
                               f"\t\t{round(max(r[3][2] for r in run))}")
                run = [g] if g is not None else []
    return out


def lines(tool, pdf):
    if V2:
        out = mupdf_glyphs(pdf)
    elif tool:
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
        if t and V2:
            # (Each piece its start, end and text; the line its end too.)
            parts = tuple((float(x), float(x1), unicodedata.normalize("NFKC", q)) for x, x1, q in
                          (piece.split("\x1f") for piece in p[4].split("\x1e"))) if len(p) > 4 and p[4] else ()
            rows.append((int(p[0][1:]), float(p[1]), float(p[2]), t, parts, float(p[5]) if len(p) > 5 and p[5] else float(p[2])))
        elif t:
            rows.append((int(p[0][1:]), float(p[1]), float(p[2]), t))
    # PDFKit cuts a line where its fonts change: the pieces of one line
    # (same page, same height) are put back together, leftmost first.
    # (Leftmost first whatever their heights: a mark that hangs past the
    # margin is a piece of its own, a hair higher than its line.)
    rows.sort(key=lambda r: (r[0], -r[1], r[2]))
    # (v2's rows are lines already, grouped by their glyphs' baselines.)
    if V2:
        return rows
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


def matches(o, r):
    """Whether our line `o` is Word's line `r`: within 3pt of its height,
    beginning or ending alike."""
    return abs(o[1] - r[1]) <= 3 and same_start(o[3], r[3])


def found(r, ours):
    """Whether Word's line `r` is matched among `ours` (the page's lines),
    as `unmatched` judges it, for one line alone."""
    return r not in unmatched([r], ours)


def unmatched(words, ours):
    """Word's lines of one page (`words`) that ours do not match.

    A line is matched by a line of ours (`matches`) — or, under v2, piece
    by piece. A line read by its baseline may be things set apart that
    only share it, and ours need not share it to the tenth: zh-27a874b7's
    3-D pie labels "德國" and, 15.8 ems along, another slice's "24" at one
    height, where ours has each in its place on baselines 0.3pt apart. So
    a line that parts where four fifths of a glyph's size stand empty — a
    cell's margins — is matched where every piece is, by a line or a piece
    of ours within 3pt of the line's height; and a line of one piece by a
    piece of ours. (By pieces only as well as whole: where the empty run is
    a print's spaces — zh-dc9e54ca's "☐…同意書" and, 4 ems along, "☐其他" —
    the other print may not part there.)

    (Under v2 a short line or piece — under four characters, which only
    its whole text tells apart — pairs with one of ours alone, each of
    ours taken once, nearest pairs first, and only where the two stand
    within the wider one's width along the baseline — where their ink
    would overlap, moved over: read by their glyphs a chart's labels are
    lines of their own, and zh-27a874b7's pie labels "84" and "15",
    10pt wide, stood 13-16pt from Word's and still matched. How far along
    is not scored beyond that, as it is not for a long line: zh-a4e8599d's
    column of "人数", "合计", 21pt and more wide, stands 17pt right of
    Word's and is a column of the same lines.)"""
    if not V2:
        return [r for r in words if not any(matches(o, r) for o in ours)]
    units = [(o[0], o[1], o[2], o[3], o[5]) for o in ours] + \
            [(o[0], o[1], px, pt, px1) for o in ours for px, px1, pt in o[4]]
    short = []     # (Word line index, the piece asked for)
    done = {}
    for n, r in enumerate(words):
        whole = (r[0], r[1], r[2], r[3], r[5])
        if len(r[3]) >= 4 and any(matches(o, whole) for o in ours):
            done[n] = True
            continue
        asks = [(r[0], r[1], x, t, x1) for x, x1, t in (r[4] or ((r[2], r[5], r[3]),))]
        if len(r[3]) < 4:
            asks = [whole]
        ok = True
        for q in asks:
            if len(q[3]) >= 4:
                ok = ok and any(matches(u, q) for u in units)
            else:
                short.append((n, q))
        done[n] = ok
    # (The short ones, nearest pairs first.)
    pairs = sorted((abs(u[2] - q[2]), k, m) for k, (_, q) in enumerate(short)
                   for m, u in enumerate(units) if abs(u[2] - q[2]) <= max(q[4] - q[2], u[4] - u[2], 1) and matches(u, q))
    taken, given = set(), set()
    for _, k, m in pairs:
        if k not in given and m not in taken:
            given.add(k)
            taken.add(m)
    for k, (n, _) in enumerate(short):
        if k not in given:
            done[n] = False
    return [r for n, r in enumerate(words) if not done[n]]


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
        by_word = {}
        for r in a:
            by_word.setdefault(r[0], []).append(r)
        missed_rows = [r for page in sorted(by_word) for r in unmatched(by_word[page], by_page.get(page, []))]
        missed_set = set(map(id, missed_rows))
        missed = [r for r in a if id(r) in missed_set]
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
