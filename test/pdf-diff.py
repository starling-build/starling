#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""pdf-diff.py A.pdf B.pdf OUTDIR [scale] — test/pdf-diff.swift where there
is no CoreGraphics (Windows, Linux): the same arguments, the same lines, the
same threshold and the same pair images, with MuPDF rasterising the pages
(pip install pymupdf numpy pillow). The two rasterisers anti-alias
differently, so a score from this one is comparable with other scores from
this one and not with a sweep made on a Mac.
"""
import os
import sys

import numpy as np
import pymupdf
from PIL import Image

if len(sys.argv) < 4:
    print("usage: pdf-diff A.pdf B.pdf OUTDIR [scale]")
    sys.exit(2)
try:
    a, b = pymupdf.open(sys.argv[1]), pymupdf.open(sys.argv[2])
except Exception:  # noqa: BLE001 — unreadable is a usage error here, as in the Swift tool
    print("usage: pdf-diff A.pdf B.pdf OUTDIR [scale]")
    sys.exit(2)
out_dir = sys.argv[3]
scale = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
os.makedirs(out_dir, exist_ok=True)


def render(page, w, h):
    """The page stretched to w x h on white, as RGB."""
    box = page.rect
    m = pymupdf.Matrix(w / box.width, h / box.height)
    pix = page.get_pixmap(matrix=m, alpha=False, colorspace=pymupdf.csRGB)
    img = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width, pix.n)[:, :, :3]
    if (pix.width, pix.height) != (w, h):  # a rounding pixel either way
        fixed = np.full((h, w, 3), 255, dtype=np.uint8)
        hh, ww = min(h, pix.height), min(w, pix.width)
        fixed[:hh, :ww] = img[:hh, :ww]
        return fixed
    return img


pages = max(len(a), len(b))
worst = total = 0.0
for n in range(1, max(pages, 1) + 1):
    if n > len(a) or n > len(b):
        print("page %2d  missing in %s" % (n, "A" if n > len(a) else "B"))
        worst = 100.0
        total += 100.0
        continue
    pa, pb = a[n - 1], b[n - 1]
    w, h = int(pa.rect.width * scale), int(pa.rect.height * scale)
    ia, ib = render(pa, w, h), render(pb, w, h)
    d = np.abs(ia.astype(np.int16) - ib.astype(np.int16)).max(axis=2)
    differing = d > 32
    share = 100.0 * differing.sum() / (w * h)
    mean = d.sum() / (w * h)
    worst = max(worst, share)
    total += share
    print("page %2d  %6.2f%% pixels differ  mean %5.2f" % (n, share, mean))
    if share > 0.5:
        diff = np.full((h, w, 3), 255, dtype=np.uint8)
        diff[differing] = (255, 0, 0)
        pair = np.zeros((h, w * 3 + 20, 3), dtype=np.uint8)
        pair[:, :] = (255, 0, 0)
        for k, img in enumerate((ia, ib, diff)):
            pair[:, k * (w + 10):k * (w + 10) + w] = img
        base = os.path.basename(sys.argv[2])
        base = base[:-4] if base.lower().endswith(".pdf") else base
        Image.fromarray(pair).save(os.path.join(out_dir, "pair-%05.2f-%s-p%d.png" % (share, base, n)))
print("summary pages=%d worst=%.2f%% mean=%.2f%%" % (pages, worst, total / pages if pages > 0 else 0))
