#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""docx-combine.py — the COMBINED Word score (user rule 2026-11-06: "it shouldn't be solely based on text").

A document is scored from its text lines (the official v2 line score) when Word's print has
extractable text lines. When Word's print has none (lines 0/n in the v2 row, lines WORD/OURS:
no text on either side, or text only we draw because Word draws it as shapes) it is scored from the visual comparison instead:
100 if its worst page differs from Word's by <= 1% of the pixels, falling linearly to 0 at 10%.

  docx-combine.py select V2FILE
      names (one per line) of the documents whose Word print has 0 text lines: the visual-scored ones.
  docx-combine.py combine V2FILE VISUALFILE OUT_VIS OUT_COMBINED [LABEL]
      OUT_VIS      one row per visual-scored document, in the v2 row format (docx-cmp.py reads it)
      OUT_COMBINED every document: the v2 row, or the visual row for a visual-scored one
      prints the headline: combined mean, with the pure line mean (docs with text) and the
      visual stats beside it, so nothing is hidden. A visual-scored document with no visual
      row is an ERROR (exit 3): it never drops out of the mean and never defaults to 100.
"""
import re, sys

ROW = re.compile(r'\s*([\d.]+)%\s+lines (\d+)/(\d+)\s+pages (\d+)/(\d+)\s+(\S+)')
VIS = re.compile(r'\s*([\d.]+)% mean\s+([\d.]+)% pages\s+(\d+) worst p(\d+)\s+(\S+)')
LO_PCT, HI_PCT = 1.0, 10.0


def vscore(worst):
    """100 at <= 1% of the pixels, 0 at >= 10%, linear between."""
    return max(0.0, min(100.0, 100.0 * (HI_PCT - worst) / (HI_PCT - LO_PCT)))


def load_rows(path):
    rows = {}
    for line in open(path):
        m = ROW.match(line)
        if m:
            rows[m.group(6)] = (float(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5)))
    return rows


def load_vis(path):
    d = {}
    for line in open(path):
        m = VIS.match(line)
        if m:
            d[m.group(5)] = float(m.group(1))
    return d


def main():
    cmd = sys.argv[1]
    rows = load_rows(sys.argv[2])
    vis_names = sorted(k for k, v in rows.items() if v[1] == 0)   # (row: lines WORD/OURS)
    if cmd == 'select':
        print('\n'.join(vis_names))
        return 0
    if cmd != 'combine':
        print(__doc__, file=sys.stderr)
        return 2
    vis = load_vis(sys.argv[3])
    out_vis, out_comb = sys.argv[4], sys.argv[5]
    label = sys.argv[6] if len(sys.argv) > 6 else ''
    missing = [k for k in vis_names if k not in vis]
    if missing:
        print(f"ERROR: {len(missing)} visual-scored documents have no visual row: {' '.join(missing[:6])}", file=sys.stderr)
        return 3
    comb, vrows = {}, {}
    for k, v in rows.items():
        if k in vis_names:
            s = round(vscore(vis[k]), 1)
            vrows[k] = comb[k] = (s, v[1], v[2], v[3], v[4])
        else:
            comb[k] = v

    def fmt(k, v):
        return f"{v[0]:6.1f}%  lines {v[1]}/{v[2]}  pages {v[3]}/{v[4]}  {k}\n"

    with open(out_vis, 'w') as f:
        f.write(f"{len(vrows)} visual-scored documents (Word's print has no text lines): 100 at worst page <= {LO_PCT:g}% of pixels, 0 at {HI_PCT:g}%\n")
        for k in sorted(vrows):
            f.write(fmt(k, vrows[k]))
    n = len(comb)
    cmean = sum(v[0] for v in comb.values()) / n
    text = [v[0] for k, v in comb.items() if k not in vrows]
    lmean = sum(text) / len(text)
    vm = sum(v[0] for v in vrows.values()) / len(vrows) if vrows else 0.0
    wm = sum(vis[k] for k in vrows) / len(vrows) if vrows else 0.0
    head = (f"{n} documents: COMBINED mean {cmean:.2f}% ({len(text)} scored by Word's text lines, {len(vrows)} by the visual comparison); "
            f"pure line mean {lmean:.2f}% over the {len(text)} documents with text; "
            f"visual-scored mean {vm:.2f}% (worst page differs by {wm:.2f}% of pixels on average, "
            f"{sum(1 for k in vrows if vis[k] <= LO_PCT)} at or under {LO_PCT:g}%)")
    with open(out_comb, 'w') as f:
        f.write(head + "\n")
        for k in sorted(comb):
            f.write(fmt(k, comb[k]))
    print(f"COMBINED {label}: {head}")
    return 0


sys.exit(main())
