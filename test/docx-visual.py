#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""docx-visual.py OURS_DIR REFS_DIR OUT [pairs_dir] — the Word VISUAL gate.

The line matcher (docx-line-match.py) reads text: it cannot see x positions,
graphics, colours, charts, shapes or borders. This one looks at the pages.
Every document with a Word print (REFS_DIR/NAME-orig.pdf) and a PDF of ours
(OURS_DIR/NAME.pdf, or OURS_DIR/pdf/NAME.pdf — what docx-line-sweep.sh
writes) is rasterised page by page at 96 dpi, grey, and compared.

A pixel differs when it is NOT within the other page's neighbourhood (RADIUS 2:
5x5)
range, by more than THRESH grey levels, in either direction. That is the
Slides gate's "share of pixels differing by more than a threshold"
(pdf-diff.py, 32 on the worst channel) with sub-pixel anti-aliasing taken out:
a glyph edge, or a whole line, up to two pixels off (1.5pt) is not a difference;
ink that is missing, extra or further away is. The share is of the
page's pixels. A page one side lacks counts 100.

OUT is written as rows "worst% mean% pages worstpage NAME", worst first, with
a header; test/corpus/docx/scores/linux/*.visual is such a file. pairs_dir
(optional) gets a side-by-side PNG (ours | Word | differences) of each
document's worst page over PAIR_MIN percent.

  DOCX_VISUAL_JOBS   processes (default: all cores)
  DOCX_VISUAL_RADIUS pixels of shift forgiven (default 2); DOCX_VISUAL_DPI default 96;  DOCX_VISUAL_THRESH default 40
"""
import os
import sys
from multiprocessing import Pool

import numpy as np
import pymupdf

DPI = float(os.environ.get("DOCX_VISUAL_DPI", "96"))
THRESH = int(os.environ.get("DOCX_VISUAL_THRESH", "40"))
RADIUS = int(os.environ.get("DOCX_VISUAL_RADIUS", "2"))
PAIR_MIN = float(os.environ.get("PAIR_MIN", "0.5"))


def render(page, w, h):
    box = page.rect
    m = pymupdf.Matrix(w / box.width, h / box.height)
    pix = page.get_pixmap(matrix=m, alpha=False, colorspace=pymupdf.csGRAY)
    img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width)
    if (pix.width, pix.height) != (w, h):
        fixed = np.full((h, w), 255, dtype=np.uint8)
        hh, ww = min(h, pix.height), min(w, pix.width)
        fixed[:hh, :ww] = img[:hh, :ww]
        return fixed
    return img


def _range3(a):
    """The min and max of each pixel's neighbourhood, RADIUS pixels each way."""
    p = np.pad(a, RADIUS, mode="edge")
    h, w = a.shape
    lo = a.copy()
    hi = a.copy()
    for dy in range(2 * RADIUS + 1):
        for dx in range(2 * RADIUS + 1):
            s = p[dy:dy + h, dx:dx + w]
            np.minimum(lo, s, out=lo)
            np.maximum(hi, s, out=hi)
    return lo.astype(np.int16), hi.astype(np.int16)


def differ(ours, word):
    """Boolean map of the pixels that differ beyond a one-pixel shift."""
    lo_o, hi_o = _range3(ours)
    lo_w, hi_w = _range3(word)
    o, w = ours.astype(np.int16), word.astype(np.int16)
    return (w < lo_o - THRESH) | (w > hi_o + THRESH) | (o < lo_w - THRESH) | (o > hi_w + THRESH)


def score(args):
    name, ours_path, ref_path, pairs = args
    try:
        a, b = pymupdf.open(ours_path), pymupdf.open(ref_path)
    except Exception as e:  # noqa: BLE001
        return name, None, str(e)[:60]
    k = DPI / 72.0
    shares = []
    worst, worst_page, worst_imgs = -1.0, 0, None
    for n in range(max(len(a), len(b))):
        if n >= len(a) or n >= len(b):
            shares.append(100.0)
            if 100.0 > worst:
                worst, worst_page, worst_imgs = 100.0, n + 1, None
            continue
        pw, ph = b[n].rect.width, b[n].rect.height
        w, h = max(1, int(pw * k)), max(1, int(ph * k))
        io, iw = render(a[n], w, h), render(b[n], w, h)
        d = differ(io, iw)
        share = 100.0 * d.sum() / (w * h)
        shares.append(share)
        if share > worst:
            worst, worst_page = share, n + 1
            worst_imgs = (io, iw, d) if pairs and share >= PAIR_MIN else None
    if pairs and worst_imgs is not None:
        from PIL import Image
        io, iw, d = worst_imgs
        h, w = io.shape
        diff = np.full((h, w, 3), 255, dtype=np.uint8)
        diff[d] = (255, 0, 0)
        pair = np.zeros((h, w * 3 + 20, 3), dtype=np.uint8)
        pair[:, :] = (255, 0, 0)
        for j, img in enumerate((np.stack([io] * 3, axis=2), np.stack([iw] * 3, axis=2), diff)):
            pair[:, j * (w + 10):j * (w + 10) + w] = img
        Image.fromarray(pair).save(os.path.join(pairs, "pair-%05.2f-%s-p%d.png" % (worst, name, worst_page)))
    return name, (max(worst, 0.0), sum(shares) / max(len(shares), 1), len(shares), worst_page), ""


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    ours, refs, out = sys.argv[1:4]
    pairs = sys.argv[4] if len(sys.argv) > 4 else None
    if pairs:
        os.makedirs(pairs, exist_ok=True)
    if os.path.isdir(os.path.join(ours, "pdf")):
        ours = os.path.join(ours, "pdf")
    jobs = []
    for f in sorted(os.listdir(refs)):
        if not f.endswith("-orig.pdf"):
            continue
        name = f[:-9]
        p = os.path.join(ours, name + ".pdf")
        if os.path.exists(p):
            jobs.append((name, p, os.path.join(refs, f), pairs))
    n = int(os.environ.get("DOCX_VISUAL_JOBS", "0")) or os.cpu_count()
    with Pool(n) as pool:
        rows = pool.map(score, jobs, chunksize=1)
    ok = sorted((r for r in rows if r[1]), key=lambda r: -r[1][0])
    bad = [r for r in rows if not r[1]]
    with open(out, "w") as fh:
        vals = [r[1][0] for r in ok]
        fh.write("%d documents: worst page differs by %.2f%% of its pixels on average; %d under 1%%, %d under 5%%, %d over 20%%"
                 " (96 dpi grey, %d-level threshold, %dpx shift forgiven)\n"
                 % (len(ok), sum(vals) / max(len(vals), 1), sum(v < 1 for v in vals), sum(v < 5 for v in vals),
                    sum(v > 20 for v in vals), THRESH, RADIUS))
        for name, (w, m, pg, wp), _ in ok:
            fh.write("%6.2f%% mean %5.2f%% pages %3d worst p%-3d %s\n" % (w, m, pg, wp, name))
        for name, _, why in bad:
            fh.write("  unreadable %s %s\n" % (name, why))
    print(open(out).readline().strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
