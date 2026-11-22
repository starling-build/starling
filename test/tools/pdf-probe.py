#!/usr/bin/env python3
"""pdf-probe: the PyMuPDF one-liners workers kept rewriting, as subcommands (amd-8, 2026-11-22).
One PDF (or two for `diff`), one page range; every row is plain text, tab-free enough to grep. Pages are 1-based.

  pdf-probe.py lines  PDF [PAGES] [--grep TXT]     one row per baseline: page, y (baseline), x0-x1, size, font, text
  pdf-probe.py glyphs PDF PAGE [--line N | --grep TXT]  per glyph of a line: char, origin x/y, advance (next origin - origin), size, font
  pdf-probe.py fonts  PDF [PAGES]                  per font: glyph count, sizes seen, flags (italic/bold/mono/serif), embedded
  pdf-probe.py trace  PDF [PAGES]                  text render mode and opacity per span run, flags invisible (mode 3 / opacity 0) and off-page text
  pdf-probe.py images PDF [PAGES]                  per image: page, bbox, pixel size, colour space, bits, bytes
  pdf-probe.py draws  PDF [PAGES]                  per filled/stroked path: true bbox (curve extents, not Bezier control points), fill, stroke, width
  pdf-probe.py diff   A.pdf B.pdf PAGE [--out PNG] [--clip x0,y0,x1,y1] [--dpi N]
                                                   % of pixels differing on one page (crop optional); --out writes a red/blue overlay

  pdf-probe.py words  PDF [PAGES] [--grep TXT]     one row per word box
  pdf-probe.py crop   PDF PAGE x0,y0,x1,y1 OUT.png [--dpi N]   render one region to look at it
  pdf-probe.py borders PDF [PAGES] [--max-w PT]    table/cell rulings: stroked lines and thin filled rects, h/v, position, extent, width, colour
  pdf-probe.py imgdraw PDF [PAGES]                 per image DRAW: bbox and the 6-number matrix (scale, flip, rotation)
  pdf-probe.py labels PDF [PAGES] [--min-lines N]  multi-line text blocks (two-line labels): bbox, baseline gaps, each line
  pdf-probe.py CMD --help                          the one-line help of a subcommand

PAGES is "3", "2-5" or "1,4,7-9" (default: all). Needs PyMuPDF; re-runs itself in ~/venv-word when the system python lacks it."""
import os, sys, warnings
warnings.filterwarnings("ignore")
try:
    import pymupdf
except ImportError:
    py = os.path.expanduser("~/venv-word/bin/python")
    if os.path.exists(py) and os.path.realpath(sys.executable) != os.path.realpath(py):
        os.execv(py, [py, "-W", "ignore"] + sys.argv)
    sys.exit("pdf-probe: PyMuPDF not found")


def pages(spec, n):
    if not spec:
        return list(range(n))
    out = []
    for part in spec.split(","):
        a, _, b = part.partition("-")
        out += range(int(a) - 1, int(b or a))
    return [p for p in out if 0 <= p < n]


def take(argv, flag, default=None):
    if flag in argv:
        i = argv.index(flag); v = argv[i + 1]; del argv[i:i + 2]; return v
    return default


def spans_of(page):
    for b in page.get_text("rawdict", flags=pymupdf.TEXTFLAGS_RAWDICT & ~pymupdf.TEXT_CLIP)["blocks"]:
        for l in b.get("lines", []):
            for s in l["spans"]:
                yield l, s


def text_of(s):
    return "".join(c["c"] for c in s["chars"])


def cmd_lines(argv):
    g = take(argv, "--grep"); by_font = "--by-font" in argv
    if by_font:
        argv.remove("--by-font")  # one row per face: faces sharing a baseline (sideways columns side by side) stay apart
    pdf = argv[0]; d = pymupdf.open(pdf)
    for pn in pages(argv[1] if len(argv) > 1 else None, len(d)):
        rows = {}
        for l, s in spans_of(d[pn]):
            if s["chars"]:
                rows.setdefault((round(s["origin"][1], 1), tuple(round(v) for v in l["dir"]), s["font"] if by_font else ""), []).append(s)
        for (y, _, _f), ss in sorted(rows.items(), key=lambda kv: (kv[0][0], min(s["bbox"][0] for s in kv[1]))):
            ss.sort(key=lambda s: s["bbox"][0]); t = "".join(text_of(s) for s in ss)
            if g and g not in t:
                continue
            print("p%d\ty=%.1f\tx=%.1f-%.1f\t%.1fpt\t%s\t%s" % (pn + 1, y, ss[0]["bbox"][0], ss[-1]["bbox"][2], ss[0]["size"], ss[0]["font"], t))


def cmd_glyphs(argv):
    g = take(argv, "--grep"); ln = take(argv, "--line"); d = pymupdf.open(argv[0]); pg = d[int(argv[1]) - 1]
    n = 0
    for l, s in spans_of(pg):
        n += 1
        if (ln and n != int(ln)) or (g and g not in text_of(s)):
            continue
        cs = s["chars"]
        print("-- span %d  %s %.1fpt  dir %s" % (n, s["font"], s["size"], tuple(round(v, 2) for v in l["dir"])))
        for i, c in enumerate(cs):
            adv = (cs[i + 1]["origin"][0] - c["origin"][0]) if i + 1 < len(cs) else float("nan")
            print("%s\tU+%04X\tx=%.2f\ty=%.2f\tadv=%.2f" % (c["c"], ord(c["c"]), c["origin"][0], c["origin"][1], adv))


FLAGS = [(2, "italic"), (4, "serif"), (8, "mono"), (16, "bold")]


def cmd_fonts(argv):
    d = pymupdf.open(argv[0]); stat = {}
    for pn in pages(argv[1] if len(argv) > 1 else None, len(d)):
        for l, s in spans_of(d[pn]):
            e = stat.setdefault(s["font"], [0, set(), s["flags"]]); e[0] += len(s["chars"]); e[1].add(round(s["size"], 1))
    emb = {}
    for pn in pages(argv[1] if len(argv) > 1 else None, len(d)):
        for f in d[pn].get_fonts():
            emb[f[3]] = f[1] if f[1] != "n/a" else "no-file"
    for k, (n, sz, fl) in sorted(stat.items(), key=lambda kv: -kv[1][0]):
        print("%-38s glyphs=%-6d sizes=%s  %s  %s" % (k, n, ",".join("%g" % z for z in sorted(sz)[:8]), "/".join(nm for b, nm in FLAGS if fl & b) or "regular", emb.get(k, "")))


def cmd_trace(argv):
    d = pymupdf.open(argv[0])
    for pn in pages(argv[1] if len(argv) > 1 else None, len(d)):
        R = d[pn].rect
        for t in d[pn].get_texttrace():
            txt = "".join(chr(c[0]) for c in t["chars"])
            if not txt.strip():
                continue
            x, y = t["chars"][0][2]
            flag = "INVISIBLE" if t["type"] == 3 or t["opacity"] == 0 else ("OFFPAGE" if not (R.x0 <= x <= R.x1 and R.y0 <= y <= R.y1) else "")
            print("p%d\tmode=%d\topacity=%.2f\t%s\t%.1fpt\t(%.0f,%.0f)\t%s\t%s" % (pn + 1, t["type"], t["opacity"], t["font"], t["size"], x, y, flag, txt[:60]))


def cmd_images(argv):
    d = pymupdf.open(argv[0])
    for pn in pages(argv[1] if len(argv) > 1 else None, len(d)):
        for im in d[pn].get_images(full=True):
            xr = im[0]; info = d.extract_image(xr) or {}
            for r in d[pn].get_image_rects(xr) or [None]:
                print("p%d\txref=%d\tbbox=%s\t%dx%d px\t%s\tbpc=%s\t%d bytes\t%s" % (pn + 1, xr, tuple(round(v, 1) for v in r) if r else "-", im[2], im[3], im[5], im[4], len(info.get("image", b"")), info.get("ext", "")))


def cubic_extrema(p0, c1, c2, p3):
    """True x/y extents of a cubic Bezier: end points plus the roots of the derivative (control points are NOT on the curve)."""
    xs, ys = [p0[0], p3[0]], [p0[1], p3[1]]
    for k, out in ((0, xs), (1, ys)):
        a0, a1, a2, a3 = p0[k], c1[k], c2[k], p3[k]
        a = -a0 + 3 * a1 - 3 * a2 + a3; b = 2 * (a0 - 2 * a1 + a2); c = a1 - a0   # derivative / 3 = a t^2 + b t + c
        ts = []
        if abs(a) < 1e-12:
            if abs(b) > 1e-12:
                ts = [-c / b]
        else:
            disc = b * b - 4 * a * c
            if disc >= 0:
                r = disc ** 0.5; ts = [(-b + r) / (2 * a), (-b - r) / (2 * a)]
        for t in ts:
            if 0 < t < 1:
                m = 1 - t; out.append(m**3 * a0 + 3 * m * m * t * a1 + 3 * m * t * t * a2 + t**3 * a3)
    return xs, ys


def true_rect(items):
    """Bounding box of the drawn shape itself, not of its Bezier control points (pymupdf's path['rect'] includes them)."""
    xs, ys = [], []
    for it in items:
        if it[0] == "c":
            cx, cy = cubic_extrema(*[(q.x, q.y) for q in it[1:5]]); xs += cx; ys += cy
        elif it[0] in ("re", "qu"):
            r = it[1].rect if it[0] == "qu" else it[1]; xs += [r.x0, r.x1]; ys += [r.y0, r.y1]
        else:
            for q in it[1:3]:
                xs.append(q.x); ys.append(q.y)
    return (min(xs), min(ys), max(xs), max(ys)) if xs else None


def cmd_draws(argv):
    d = pymupdf.open(argv[0])
    for pn in pages(argv[1] if len(argv) > 1 else None, len(d)):
        for p in d[pn].get_drawings():
            r = true_rect(p["items"]) or tuple(p["rect"])
            print("p%d\t%s\t(%.1f,%.1f,%.1f,%.1f)\tfill=%s\tstroke=%s\tw=%s" % (pn + 1, p["type"], r[0], r[1], r[2], r[3],
                  tuple(round(v, 2) for v in p["fill"]) if p.get("fill") else "-", tuple(round(v, 2) for v in p["color"]) if p.get("color") else "-", p.get("width")))


def cmd_diff(argv):
    out = take(argv, "--out"); clip = take(argv, "--clip"); dpi = int(take(argv, "--dpi", "72"))
    a, b, pn = pymupdf.open(argv[0]), pymupdf.open(argv[1]), int(argv[2]) - 1
    c = pymupdf.Rect(*[float(v) for v in clip.split(",")]) if clip else None
    pa, pb = (x[pn].get_pixmap(dpi=dpi, clip=c, colorspace=pymupdf.csGRAY) for x in (a, b))
    if (pa.width, pa.height) != (pb.width, pb.height):
        sys.exit("pdf-probe: page sizes differ %dx%d vs %dx%d" % (pa.width, pa.height, pb.width, pb.height))
    sa, sb = pa.samples, pb.samples; n = len(sa)
    diff = sum(1 for i in range(n) if abs(sa[i] - sb[i]) > 32)
    print("page %d: %.2f%% of %d px differ (>32 of 255)" % (pn + 1, 100.0 * diff / n, n))
    if out:
        ov = bytearray(n * 3)
        for i in range(n):
            if abs(sa[i] - sb[i]) > 32:   # red: only A inked, blue: only B inked
                ov[3 * i:3 * i + 3] = bytes((255, 0, 0)) if sa[i] < sb[i] else bytes((0, 0, 255))
            else:
                ov[3 * i:3 * i + 3] = bytes((sa[i],) * 3)
        pymupdf.Pixmap(pymupdf.csRGB, pa.width, pa.height, bytes(ov), False).save(out); print("wrote", out)


def cmd_words(argv):
    """words PDF [PAGES] [--grep TXT]: one row per word: page, bbox, text (PyMuPDF word boxes, reading order)."""
    g = take(argv, "--grep"); d = pymupdf.open(argv[0])
    for pn in pages(argv[1] if len(argv) > 1 else None, len(d)):
        for w in d[pn].get_text("words"):
            if not g or g in w[4]:
                print("p%d\t(%.1f,%.1f,%.1f,%.1f)\t%s" % (pn + 1, w[0], w[1], w[2], w[3], w[4]))


def cmd_crop(argv):
    """crop PDF PAGE x0,y0,x1,y1 OUT.png [--dpi N]: render one region of one page (points) to a PNG, to look at it."""
    dpi = int(take(argv, "--dpi", 144)); d = pymupdf.open(argv[0]); pg = d[int(argv[1]) - 1]
    clip = pymupdf.Rect(*[float(v) for v in argv[2].split(",")])
    pg.get_pixmap(dpi=dpi, clip=clip).save(argv[3]); print("%s: %s at %d dpi" % (argv[3], tuple(clip), dpi))


def cmd_borders(argv):
    """borders PDF [PAGES] [--max-w PT]: every ruling: a stroked line, or a filled rect thinner than --max-w (default 2 pt).
    Rows: page, h or v, position (y for h, x for v), from-to, thickness, colour. For table and cell borders."""
    mw = float(take(argv, "--max-w", 2)); d = pymupdf.open(argv[0])
    for pn in pages(argv[1] if len(argv) > 1 else None, len(d)):
        for p in d[pn].get_drawings():
            segs = []
            for it in p["items"]:
                if it[0] == "l" and p.get("color") is not None and "s" in p["type"]:
                    segs.append((it[1], it[2], p.get("width") or 0, p.get("color")))
                elif it[0] == "re":
                    r = it[1]
                    if min(r.width, r.height) <= mw and p.get("fill"):
                        segs.append((pymupdf.Point(r.x0, (r.y0 + r.y1) / 2), pymupdf.Point(r.x1, (r.y0 + r.y1) / 2), r.height, p["fill"]) if r.width >= r.height else
                                    (pymupdf.Point((r.x0 + r.x1) / 2, r.y0), pymupdf.Point((r.x0 + r.x1) / 2, r.y1), r.width, p["fill"]))
            for a, b, w, c in segs:
                col = tuple(round(v, 2) for v in c) if c else "-"
                if abs(a.y - b.y) < 0.01:
                    print("p%d\th\ty=%.2f\tx %.1f-%.1f\tw=%.2f\t%s" % (pn + 1, a.y, min(a.x, b.x), max(a.x, b.x), w, col))
                elif abs(a.x - b.x) < 0.01:
                    print("p%d\tv\tx=%.2f\ty %.1f-%.1f\tw=%.2f\t%s" % (pn + 1, a.x, min(a.y, b.y), max(a.y, b.y), w, col))


def cmd_imgdraw(argv):
    """imgdraw PDF [PAGES]: every image DRAW (an image drawn twice shows twice): page, xref, bbox, the 6 numbers of its matrix
    (a b c d e f, as placed), pixel size. Shows scale, flip, rotation and crop that `images` does not."""
    d = pymupdf.open(argv[0])
    for pn in pages(argv[1] if len(argv) > 1 else None, len(d)):
        for i in d[pn].get_image_info(xrefs=True):
            print("p%d\txref=%s\tbbox=(%.1f,%.1f,%.1f,%.1f)\tmatrix=(%s)\t%dx%d px" % (pn + 1, i.get("xref"), *i["bbox"],
                  ",".join("%.3f" % v for v in i["transform"]), i["width"], i["height"]))


def cmd_labels(argv):
    """labels PDF [PAGES] [--min-lines N]: text blocks of N or more lines (default 2): page, block bbox, line count,
    baseline gap between lines, then each line's text. For two-line labels and wrapped captions."""
    mn = int(take(argv, "--min-lines", 2)); d = pymupdf.open(argv[0])
    for pn in pages(argv[1] if len(argv) > 1 else None, len(d)):
        for b in d[pn].get_text("dict")["blocks"]:
            ls = [l for l in b.get("lines", []) if any(s["text"].strip() for s in l["spans"])]
            if len(ls) >= mn:
                ys = [l["spans"][0]["origin"][1] for l in ls]
                print("p%d\t(%.1f,%.1f,%.1f,%.1f)\t%d lines\tgap %s" % (pn + 1, *b["bbox"], len(ls), ",".join("%.1f" % (b2 - a) for a, b2 in zip(ys, ys[1:]))))
                for l in ls:
                    print("\t\t" + "".join(s["text"] for s in l["spans"]))


CMDS = {k[4:]: v for k, v in globals().items() if k.startswith("cmd_")}
if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] in CMDS and sys.argv[2] in ("-h", "--help"):
        print(CMDS[sys.argv[1]].__doc__ or "no help"); sys.exit(0)
    if len(sys.argv) < 3 or sys.argv[1] not in CMDS:
        print(__doc__); sys.exit(2)
    CMDS[sys.argv[1]](sys.argv[2:])
