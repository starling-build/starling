#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""test/docx-line-match.py WORK [KEY [N]] — how many of Word's lines this app
sets in the same place.

The page diff of test/docx-app-render.sh counts pixels, and a document whose
every line is one line late scores like one that is all wrong. This reads
the text instead: every line of Word's print (test/corpus/docx/word-win) and of
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
import math
import os
import statistics
import subprocess
import sys
import unicodedata
# PyMuPDF 2.0 imports its optional layout package (onnxruntime) at `import pymupdf`: 575 threads and 60 CPU-seconds spent at import, so one scorer
# process ran at 700-1900% CPU (OMP/OPENBLAS/OPJ_NUM_THREADS do not stop them, and a CPU mask does not either: the threads pin themselves).
# These tools never use it; None in sys.modules makes that import fail, which pymupdf catches (amd-8, 2026-11-23: 20-page diff 64 s CPU to 1.5 s).
sys.modules.setdefault("pymupdf.layout", None)

HERE = os.path.dirname(os.path.abspath(__file__))
# (DOCX_WORD_REFS: another folder of Word's prints, for a sample not checked in.)
WORD = os.environ.get("DOCX_WORD_REFS") or os.path.join(HERE, "corpus", "docx", "word-win")


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


def _key(c):
    return (round(c["origin"][0], 1), round(c["origin"][1], 1), c["c"])


_RAW = {}   # (pdf path, page) -> the no-clip rawdict blocks _glyph_ink read; mupdf_glyphs takes (and so consumes) them: one extraction per page, not two


def _glyph_ink(pdf, dpi=150):
    """(all, hidden) per page for v2's hidden-glyph rule. Word's PDFs keep the text a CLIP hides (a header's
    line-number box clips its 24th number: the glyph stays in the text layer, nothing is inked). HIDDEN = a glyph
    the reader's own clip test drops (rawdict with TEXT_CLIP) whose box holds no ink in the page as drawn (a
    rendered page, no pixel under 250). Only such glyphs are judged: other glyph boxes (Tamil, Thai, Arabic marks)
    can sit where the page has no ink of its own. ALL = every inked glyph's (x, y, char)."""
    import pymupdf
    import numpy as np
    allg, hidden = {}, {}
    k = dpi / 72.0
    with pymupdf.open(pdf) as d:
        for i, page in enumerate(d):
            noclip = page.get_text("rawdict", flags=pymupdf.TEXTFLAGS_RAWDICT & ~pymupdf.TEXT_CLIP)["blocks"]
            if len(d) <= 150: _RAW[(os.path.abspath(pdf), i)] = noclip   # mupdf_glyphs reads the same dict next (once, then it is dropped)
            full = [c for b in noclip
                    for l in b.get("lines", []) for sp in l["spans"] for c in sp["chars"] if not _inkless(c["c"])]
            seen = {_key(c) for b in page.get_text("rawdict", flags=pymupdf.TEXTFLAGS_RAWDICT)["blocks"]
                    for l in b.get("lines", []) for sp in l["spans"] for c in sp["chars"]}
            allg[i], hid = set(), set()
            pm = None
            for c in full:
                key = _key(c)
                allg[i].add(key)
                if key in seen:
                    continue
                if pm is None:
                    pix = page.get_pixmap(dpi=dpi, colorspace=pymupdf.csGRAY, annots=False)
                    pm = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width)
                x0, y0, x1, y1 = c["bbox"]
                ix0, iy0 = max(int(x0 * k), 0), max(int(y0 * k), 0)
                ix1, iy1 = min(int(x1 * k) + 1, pm.shape[1]), min(int(y1 * k) + 1, pm.shape[0])
                if ix1 > ix0 and iy1 > iy0 and pm[iy0:iy1, ix0:ix1].min() >= 250:
                    hid.add(key)
            hidden[i] = hid
    return allg, hidden


def _unseen_pairs(ref_pdf, our_pdf):
    """The glyphs v2 leaves out of each side: those hidden on one side and not drawn on the other. A glyph that
    Word hides and we draw (a page number's second digit, which Word's footer box clips) is a real difference and
    stays; one hidden on one side and absent, or hidden, on the other is nothing either print shows."""
    try:
        wa, wh = _glyph_ink(ref_pdf)
        oa, oh = _glyph_ink(our_pdf)
    except Exception:
        return {}, {}
    def near(pool, key):
        return any(c == key[2] and abs(x - key[0]) < 3 and abs(y - key[1]) < 3 for x, y, c in pool)
    dw, do = {}, {}
    for i, hs in wh.items():
        vis = oa.get(i, set()) - oh.get(i, set())
        # (A line Word's clip hides WHOLE — every glyph on its baseline hidden — is no line Word shows, whether
        # or not we draw it: a fixed-height box keeps the text in the print and clips it away, dx2 2263e221's third
        # header lines. A line clipped in part stays a real difference, as above. Word's side only.)
        rows = {}
        for (x, y, c) in wa.get(i, set()):
            rows.setdefault(round(y), []).append((x, y, c))
        whole = {g for g in hs if all(q in hs for r in (round(g[1]) - 1, round(g[1]), round(g[1]) + 1)
                                       for q in rows.get(r, ()) if abs(q[1] - g[1]) < 0.5)}
        dw[i] = {g for g in hs if not near(vis, g)} | whole
    for i, hs in oh.items():
        vis = wa.get(i, set()) - wh.get(i, set())
        do[i] = {g for g in hs if not near(vis, g)}
    return dw, do


def _runs(singles):
    """Slides: the upright single glyphs that stand in a run of three or more, each the next an em along (0.9 to 1.1)
    and within 0.3 em across: one column of upright text among a slide's horizontal boxes (a bullet or a number a line
    apart steps 1.2 em or more)."""
    ordered = sorted(singles, key=lambda g: (round(g[1] / max(g[3], 1) / 0.6), g[2]))
    keep, run = [], []
    for g in ordered + [None]:
        if g is not None and run and abs(g[1] - run[-1][1]) <= 0.3 * g[3] and 0.9 <= (g[2] - run[-1][2]) / g[3] <= 1.1:
            run.append(g)
            continue
        if len(run) >= 3:
            keep += run
        run = [g] if g is not None else []
    return keep


def _columns(singles, total, mixed=False):
    """Rows for the columns of a page of vertical writing, or [] where the page
    is not one. A glyph set upright in a column reads as a line of one glyph in
    the print, so the page is vertical where most of its glyphs are such lines
    and stack: another such glyph within 0.3 em across and one or two ems along
    (a horizontal page's rows of numbers or bullets step by other amounts).
    Its columns are grouped by their glyphs' em centres across (within 0.3 em
    of the column's first) and each is a row: its height is the centre
    across, its start and end the glyphs' along it."""
    if mixed:
        keep = _runs(singles)
        return _columns(keep, len(keep)) if keep else []
    if len(singles) < 8 or len(singles) < 0.5 * total:
        return []
    def stacked(g):
        return any(h is not g and abs(h[1] - g[1]) <= 0.3 * g[3] and (0.9 <= abs(h[2] - g[2]) / g[3] <= 1.1 or 1.9 <= abs(h[2] - g[2]) / g[3] <= 2.1)
                   for h in singles)
    if sum(1 for g in singles if stacked(g)) < 0.7 * len(singles):
        return []
    cols = []
    for g in sorted(singles, key=lambda g: g[1]):
        if cols and g[1] - cols[-1][0][1] <= 0.3 * g[3]:
            cols[-1].append(g)
        else:
            cols.append([g])
    rows = []
    for col in sorted(cols, key=lambda c: -c[0][1]):
        col.sort(key=lambda g: g[2])
        pieces = [[col[0]]]
        for prev, g in zip(col, col[1:]):
            if g[2] - prev[2] > 1.8 * max(prev[3], g[3]):
                pieces.append([])
            pieces[-1].append(g)
        cx = statistics.median(g[1] for g in col)
        parts = "\x1e".join(f"{round(q[0][2])}\x1f{round(q[-1][2] + q[-1][3])}\x1f{''.join(g[4] for g in q)}"
                            for q in pieces) if len(pieces) > 1 else ""
        rows.append(f"{round(-cx)}\t{round(col[0][2])}\t{''.join(g[4] for g in col)}\t{parts}\t{round(col[-1][2] + col[-1][3])}")
    return rows


OFFPAGE = False
_REF_INK = None   # Slides: the reference page's inked glyph boxes, set while scoring ours (turned text, below)
_COLLECT = None   # ... gathered while reading the reference


def _image_infos(page):
    """page.get_image_info(xrefs=True) without decoding every picture of the page again on every page: PyMuPDF finds an image's xref by
    the digest of each picture's pixmap, and a deck repeats its master's pictures on every slide, so the digests are kept per document."""
    import pymupdf
    doc = page.parent
    info = page.get_image_info(hashes=True)
    if not doc.is_pdf:
        return info
    seen = doc.__dict__.setdefault("_xref_digests", {})
    digests = {}
    for item in page.get_images():
        xref = item[0]
        if xref not in seen:
            pix = pymupdf.Pixmap(doc, xref)
            seen[xref] = pix.digest
            del pix
        digests[seen[xref]] = xref
    for item in info:
        item["xref"] = digests.get(item["digest"], 0)
    return info


def _one_colour(doc, im):
    """Whether the picture `im` (a `get_image_info` entry) is a single colour throughout: a solid fill drawn as a picture."""
    import pymupdf
    try:
        px = pymupdf.Pixmap(doc, im["xref"])
        n = px.n
        b = px.samples
        return len(b) >= n and all(b[i:i + n] == b[:n] for i in range(0, len(b), n))
    except Exception:
        return False


# The Symbol font's code page: a text layer that names a Symbol glyph by its private-use code U+F000 + the font's byte (the sum sign is
# U+F0E5) says the same character as Unicode's own (U+2211). The Adobe Symbol encoding, published; both prints are folded alike.
_SYM_UP = "ΑΒΧΔΕΦΓΗΙϑΚΛΜΝΟΠΘΡΣΤΥςΩΞΨΖ"
_SYM_LO = "αβχδεφγηιϕκλμνοπθρστυϖωξψζ"
_SYM_HI = ("€ϒ′≤⁄∞ƒ♣♦♥♠↔←↑→↓°±″≥×∝∂•÷≠≡≈…⏐⎯↵ℵℑℜ℘⊗⊕∅∩∪⊃⊇⊄⊂⊆∈∉∠∇®©™∏√⋅¬∧∨⇔⇐⇑⇒⇓◊〈®©™∑")
_SYMBOL = {0xF022: "∀", 0xF024: "∃", 0xF027: "∋", 0xF02A: "∗", 0xF02D: "−", 0xF040: "≅", 0xF05C: "∴", 0xF05E: "⊥", 0xF07E: "∼", 0xF0F1: "〉", 0xF0F2: "∫"}
for _i, _c in enumerate(_SYM_UP): _SYMBOL[0xF041 + _i] = _c
for _i, _c in enumerate(_SYM_LO): _SYMBOL[0xF061 + _i] = _c
for _i, _c in enumerate(_SYM_HI): _SYMBOL[0xF0A0 + _i] = _c
_SYMBOL = {k: v for k, v in _SYMBOL.items() if not (0xF0E6 <= k <= 0xF0F0)}


def _ghost_shapes(page):
    """The ink a ghost glyph may sit on: vector shapes (not a whole-page one) and pictures of one colour."""
    import pymupdf
    # get_cdrawings: the same paths as get_drawings without a Point/Rect object per path point (24 M of them on one deck: 80 s of 114 s)
    half = 0.5 * page.rect.width * page.rect.height
    shapes = []
    for dr in page.get_cdrawings():
        if dr.get("fill") or dr.get("color"):
            r = pymupdf.Rect(dr["rect"])
            if r.width * r.height < half: shapes.append(r)
    shapes += [pymupdf.Rect(im["bbox"]) for im in _image_infos(page) if _one_colour(page.parent, im)]
    return shapes


def mupdf_glyphs(pdf, drop=None):
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
            singles = []
            line_no = 0
            ghost = None
            # (Clipped glyphs too, as v1 reads them: the reader drops a
            # glyph the clip does not wholly hold, and Word's footer boxes
            # clip their page numbers — zh-f47b8a74's "10" read "1", and our
            # Thai, drawn inside a clip, read as nothing.)
            blocks = _RAW.pop((os.path.abspath(pdf), i), None)
            if blocks is None:
                blocks = page.get_text("rawdict", flags=pymupdf.TEXTFLAGS_RAWDICT & ~pymupdf.TEXT_CLIP)["blocks"]
            trace = page.get_texttrace()   # read once for both uses below
            # A run squeezed across (Tz, or a matrix whose x scale is not its y scale) is sized by the reader as the geometric mean of the
            # two scales in the text dict and by the x scale in the trace: the y scale, the real size, is mean^2 / x (amd-8, 2026-11-22).
            xsz = {}
            for t in trace:
                if t["size"] > 0:
                    for ch in t["chars"]:
                        xsz[(round(ch[2][0], 1), round(ch[2][1], 1))] = t["size"]
            for b in blocks:
                for l in b.get("lines", []):
                    for sp in l["spans"]:
                        if sp["chars"]:
                            tx = xsz.get((round(sp["chars"][0]["origin"][0], 1), round(sp["chars"][0]["origin"][1], 1)))
                            if tx and abs(tx - sp["size"]) > 0.01 * sp["size"]:
                                sp["size"] = sp["size"] ** 2 / tx
            # Slides (PPT_MIN_PT, amd-8 2026-11-23): PowerPoint prints an invisible second copy of the text under a hyperlinked
            # shape at 1.0-1.4 pt (4cc69f8d4a9b: 5,203 such spans). Spans under the size are no text either print shows: dropped
            # from BOTH PDFs, by size only.
            minpt = float(os.environ.get("PPT_MIN_PT") or 0)
            if minpt:
                for b in blocks:
                    for l in b.get("lines", []):
                        for sp in l["spans"]:
                            if sp["size"] < minpt:
                                sp["chars"] = []
            gone = drop.get(i) if drop else None
            if gone:
                for b in blocks:
                    for l in b.get("lines", []):
                        for sp in l["spans"]:
                            sp["chars"] = [c for c in sp["chars"] if _key(c) not in gone]
            for b in blocks:
                for l in b.get("lines", []):
                    line_no += 1
                    across = tuple(round(v, 3) for v in l["dir"]) == (1, 0)
                    if OFFPAGE:   # Slides: a Symbol private-use code reads as the Unicode character it stands for
                        for s in l["spans"]:
                            for c in s["chars"]:
                                if len(c["c"]) == 1 and ord(c["c"]) in _SYMBOL and "symbol" in s["font"].lower() and "wingdings" not in s["font"].lower():
                                    c["c"] = _SYMBOL[ord(c["c"])]
                                elif len(c["c"]) == 1 and 0x25A0 <= ord(c["c"]) <= 0x25FF:   # a square or triangle bullet: one shape, whichever size form a face stores it as (■ and ◼)
                                    c["c"] = "\u25a0"
                    inked = [(c, s["size"]) for s in l["spans"] for c in s["chars"] if not _inkless(c["c"])]
                    if OFFPAGE:   # Slides (pptx-line-match.py): a glyph whose origin lies outside the page is not drawn on it, on either side
                        R = page.rect
                        inked = [(c, z) for c, z in inked if R.x0 <= c["origin"][0] <= R.x1 and R.y0 <= c["origin"][1] <= R.y1]
                        # ... and neither is text set invisible (render mode 3, or opacity 0: a shadow copy PowerPoint writes in the text layer, es 21eed05e's contents list)
                        if ghost is None:
                            ghost = set()
                            # ... except where it sits on ink drawn by a vector shape (amd-8, 2026-11-22, amd-4's finding): our Wingdings
                            # bullets are SHAPES with the glyph kept as invisible text, where PowerPoint writes the bullet as visible text
                            # (ko-30dac1f5, lo-tdf126234). Invisible text over nothing (a ghost copy) still counts on neither side.
                            shapes = None
                            for t in trace:
                                if t["type"] == 3 or t["opacity"] == 0:
                                    if shapes is None:   # only a page that has invisible text needs its shapes (get_drawings is the slow call: 80 s of 114 s on ko-a1b39848a0)
                                        shapes = _ghost_shapes(page)
                                    for ch in t["chars"]:
                                        bb = pymupdf.Rect(ch[3])
                                        if not any(bb.intersects(r) and not r.is_empty for r in shapes):
                                            ghost.add((round(ch[2][0], 1), round(ch[2][1], 1)))
                        inked = [(c, z) for c, z in inked if (round(c["origin"][0], 1), round(c["origin"][1], 1)) not in ghost]
                    if OFFPAGE and abs(l["dir"][0]) > 0.02 and abs(l["dir"][1]) > 0.02:
                        # Slides: text turned off the axes counts only where the reference print has text at that place
                        # (amd-10, 2026-11-27). A 45-degree chart label PowerPoint keeps no text layer for (es ce626c34) counts
                        # on neither side; curved WordArt, every glyph a line at its own angle, PowerPoint does keep
                        # (lo-tdf116350-texteffects, ~300 glyphs), so it counts on both. The reference's own turned text always stays.
                        if _REF_INK is None:
                            pass
                        else:
                            lb = pymupdf.Rect(l["bbox"])
                            if not any(lb.intersects(r) for r in _REF_INK.get(i, ())):
                                continue
                    if OFFPAGE and _REF_INK is None and _COLLECT is not None:
                        _COLLECT.setdefault(i, []).extend(pymupdf.Rect(c["bbox"]) for c, _ in inked)
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
                            if len(q) == 1:
                                c, size = q[0]
                                singles.append((line_no, (c["bbox"][0] + c["bbox"][2]) / 2, c["origin"][1], size,
                                                "\x00" if unicodedata.category(c["c"]) == "Co" else c["c"]))
                    else:
                        d = tuple(round(v, 2) for v in l["dir"])
                        for c, size in inked:
                            turned.append((d, c["origin"][0], c["origin"][1], c["bbox"], c["c"], size))
            # (A page of vertical writing: its upright glyphs are a line each
            # in the print, one per column cell. See `_columns`.)
            cols = _columns(singles, len(glyphs))
            kept = singles
            if not cols and OFFPAGE:
                cols = _columns(singles, len(glyphs), True)
                if cols:
                    kept = _runs(singles)
            if cols:
                gone = {n for n, *_ in kept}
                glyphs = [g for g in glyphs if g[6] not in gone]
                out += [f"p{i + 1}\t{r}" for r in cols]
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
                        if g2[2] - prev[4] > 0.8 * max(prev[5], g2[5]) - 0.1:  # (0.1pt: a gap of exactly 4/5 em is 18.00 in one print, 18.02 in the other)
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
            if ROT:
                out += _turned_rows([g for g in turned if _axis(g[0])], i)
                turned = [g for g in turned if not _axis(g[0])]
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
    if os.environ.get("PPT_RTL_NORM"):
        out = _fold_strays(out)
    return out


# DOCX_LINE_ROT=1 (v2): turned text read in its own frame (amd-8, 2026-11-26; amd-1: a fix to rotated cells moved no score).
# Without it a turned run is a row keyed by its box's lower end, so its height is where the column ENDS, and across it
# (the height that matters for a turned line) nothing is judged. With it the run is turned back to read left to right:
# along = the origin on the run direction, height = minus the origin across it, a fifth of the size below the baseline as
# for a line set across; and it lands on a page of its own per direction (ROT_PAGE * k + page), so a turned line pairs
# only with a turned line of the same direction. Only text turned a quarter or half turn is read so: text set along a
# curve or a slant (WordArt; lo-677416be draws each glyph at its own angle) stays as before, since no line holds there.
# ON by default for Word since 2026-11-27 (starling-bd); DOCX_LINE_ROT=0 turns it off. Slides and Sheets pin it off in their own callers.
ROT = V2 and os.environ.get("DOCX_LINE_ROT", "1") == "1"
ROT_PAGE = 100000
_ROT_DIRS = [(0, -1), (0, 1), (-1, 0)]


def _axis(d):
    n = math.hypot(*d) or 1
    return (round(d[0] / n, 2), round(d[1] / n, 2)) in _ROT_DIRS


def _turned_rows(turned, i):
    rows = []
    by = {}
    for d, ox, oy, bb, ch, size in turned:
        n = math.hypot(*d) or 1
        u, v = d[0] / n, d[1] / n
        d = (round(u, 2) + 0.0, round(v, 2) + 0.0)
        along = ox * u + oy * v
        across = -ox * v + oy * u
        ends = [x * u + y * v for x in (bb[0], bb[2]) for y in (bb[1], bb[3])]
        by.setdefault(d, []).append((across, along, min(ends), max(ends), ch, size))
    for d in sorted(by):
        n = math.hypot(*d) or 1
        page = ROT_PAGE * (1 + _ROT_DIRS.index((round(d[0] / n, 2) + 0.0, round(d[1] / n, 2) + 0.0))) + i + 1
        gl = sorted(by[d], key=lambda g: (round(g[0] / 0.6), g[1]))
        run = []
        for g in gl + [None]:
            if g is not None and run and abs(g[0] - run[-1][0]) <= 0.6 and g[2] - run[-1][3] <= max(g[5], run[-1][5]):
                run.append(g)
                continue
            if run:
                top = max(r[5] for r in run)
                base = statistics.median(r[0] for r in run if r[5] == top) + 0.2 * top
                rows.append(f"p{page}\t{round(-base)}\t{round(min(r[2] for r in run))}\t{''.join(r[4] for r in run)}"
                            f"\t\t{round(max(r[3] for r in run))}")
            run = [g] if g is not None else []
    return rows


def _fold_strays(out):
    """(Slides) PowerPoint's print sets a letter or a short word it has pulled out of an Arabic line (a ر, ي or ن, a unit such as
    متر) as a line of its own, a few points off the baseline, and the line it left reads short: eb7ab2c5 p14, p20, f355b7fc,
    8a5ae557 p12. A line of up to three Arabic letters within 6pt of a longer line on its page, and horizontally inside that
    line's extent, is part of that line; both prints are read the same way. (amd-8, 2026-11-22.)"""
    def ar(c):
        return "\u0600" <= c <= "\u06ff" or "\u0750" <= c <= "\u077f" or "\ufb50" <= c <= "\ufeff"
    def arabic(t):
        # up to FIVE Arabic letters, and any non-letters (a list bullet) with them; a row holding a bullet is the first piece of
        # its line wherever it sits (the bullet stands at the line's start, past the end of the letters): 8a5ae557 p2, p4, p13,
        # where PowerPoint's layer sets "➢يع", "لتعلأ", "جملأ" as rows of their own and the host line reads short.
        letters = [c for c in t if unicodedata.category(c).startswith("L")]
        return 0 < len(letters) <= 5 and all(ar(c) for c in letters) and len(t) <= 8
    def bullet(t):
        return any(unicodedata.category(c) == "So" or c == "\u2022" for c in t)
    rows = [l.split("\t") for l in out]
    keep = []
    for r in rows:
        if arabic(r[3]):
            host = [h for h in rows if h is not r and h[0] == r[0] and len(h[3]) > len(r[3]) and abs(int(h[1]) - int(r[1])) <= 6
                    and (bullet(r[3]) or int(h[2]) - 2 <= int(r[2]) <= int(h[5]) + 2)]
            if host:
                min(host, key=lambda h: abs(int(h[1]) - int(r[1])))[3] += r[3]
                continue
        keep.append(r)
    return ["\t".join(r) for r in keep]


def lines(tool, pdf, drop=None):
    if V2:
        out = mupdf_glyphs(pdf, drop)
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
    if rtl and os.environ.get("PPT_RTL_NORM"):
        # PowerPoint's print writes the lam-alef ligature as "ال" (swapped), ours as "لا", and
        # its lines in visual order: compare NFKC letters without alef and lam, both directions.
        def core(t):
            return "".join(c for c in unicodedata.normalize("NFKC", t)
                           if unicodedata.category(c).startswith("L") and c not in "\u0627\u0644")
        p, q = core(a), core(b)
        # (Our PDF's lam-alef ligature glyph extracts as the lam alone under its ActualText "لا", where PowerPoint's
        # extracts the pair, so the alef counts differ between the prints, and PowerPoint's lines run in visual order
        # with whole words reversed. The same letters, with alef and lam left out on BOTH sides, are the same line
        # whatever the order: amd-8, 2026-11-22, rtl 898f62b7.)
        if len(p) >= 4 and sorted(p) == sorted(q):
            return True
        if len(p) >= 3 and len(q) >= 3:
            for x in (q, q[::-1]):
                if p[:3] == x[:3] or p[-3:] == x[-3:]:
                    return True
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


_CTX = None


def _score_job(f):
    return score_document(*_CTX, f)


def score_document(tool, work, key, count, f):
    """One document: (ratio, name, Word's lines, ours, (Word's pages, ours)), or None when
    Word's print is missing. With a KEY it also prints where the document first parts from Word."""
    ref = os.path.join(WORD, f[:-4] + "-orig.pdf")
    if not os.path.exists(ref):
        return None
    ours_pdf = os.path.join(work, "pdf", f)
    dw, do = _unseen_pairs(ref, ours_pdf) if V2 else ({}, {})
    global _REF_INK, _COLLECT
    _REF_INK, _COLLECT = None, ({} if OFFPAGE else None)
    try:
        a = lines(tool, ref, dw)
        _REF_INK, _COLLECT = _COLLECT, None
        b = lines(tool, ours_pdf, do)
    finally:
        _REF_INK, _COLLECT = None, None
    by_page = {}
    for r in b:
        by_page.setdefault(r[0], []).append(r)
    by_word = {}
    for r in a:
        by_word.setdefault(r[0], []).append(r)
    missed_rows = [r for page in sorted(by_word) for r in unmatched(by_word[page], by_page.get(page, []))]
    missed_set = set(map(id, missed_rows))
    missed = [r for r in a if id(r) in missed_set]
    pages = (max((r[0] % ROT_PAGE for r in a), default=0), max((r[0] % ROT_PAGE for r in b), default=0))
    result = ((len(a) - len(missed)) / max(1, len(a)), f[:-4], len(a), len(b), pages)
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
    return result


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
    skip = set() if key else ignored()
    names = [f for f in sorted(os.listdir(os.path.join(work, "pdf")))
             if f.endswith(".pdf") and not (key and key not in f) and not any(f.startswith(k) for k in skip)]
    # (DOCX_MATCH_JOBS=N: score the documents in N processes. Each is scored alone and the
    # results are sorted below, so the output is byte for byte the serial one. Not with a
    # KEY, which prints as it goes. The default stays serial.)
    jobs = 1 if key else int(os.environ.get("DOCX_MATCH_JOBS") or 1)
    if jobs > 1 and len(names) > 1 and hasattr(os, "fork"):  # (no fork on Windows: serial there)
        import multiprocessing
        global _CTX
        _CTX = (tool, work, key, count)
        with multiprocessing.get_context("fork").Pool(min(jobs, len(names))) as pool:
            # (Largest print first, so the slow documents do not start last.)
            order = sorted(names, key=lambda f: -os.path.getsize(os.path.join(work, "pdf", f)))
            results = [r for r in pool.imap_unordered(_score_job, order, chunksize=1) if r]
    else:
        results = [r for r in (score_document(tool, work, key, count, f) for f in names) if r]
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
