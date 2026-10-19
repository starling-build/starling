#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""test/pptx-line-survey.py WORK [--across] [--rows FILE] — where the
corpus's text lines stand off PowerPoint's, by face and by deck.

The page diff of test/pptx-app-render.sh counts pixels: a deck whose every
line is a point low scores like one with a few wrong pictures. This reads
the text instead. Every horizontal line of PowerPoint's print
(test/corpus/pptx/powerpoint) and of ours (WORK/pdf, from a sweep) that
occurs once on its page is matched by its text, and the matched pairs are
compared: their baselines (or, with --across, where they start). It prints,
per face PowerPoint names, how many lines are off by half a point or more
(a whole point across) of how many compared, then the decks those lines
are in, worst first, with the mean offset (+ is ours low, or right).

That is how a rule shows itself: one face off in every deck (Consolas,
Helvetica — its depth below the baseline), one deck off on every line
(a shrink-to-fit's first baseline), a chart's legend drifting further
the further right. --rows writes every off line, tab-separated (deck,
page, offset, face, size, text), for a closer look.
"""
import argparse
import collections
import glob
import os
import sys

try:
    import pymupdf
except ImportError:
    sys.exit("needs PyMuPDF (pip install pymupdf)")

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "corpus", "pptx")


def lines(page, across):
    found = {}
    for block in page.get_text("dict")["blocks"]:
        for line in block.get("lines", []):
            if tuple(line["dir"]) != (1.0, 0.0):
                continue
            text = "".join(s["text"] for s in line["spans"]).strip()
            if len(text) < 8:
                continue
            span = max(line["spans"], key=lambda s: len(s["text"]))
            at = line["spans"][0]["origin"][0] if across else span["origin"][1]
            found.setdefault(text, []).append((at, span["font"], round(span["size"])))
    return {t: v[0] for t, v in found.items() if len(v) == 1}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("work", help="a sweep's WORK directory (its pdf/ holds ours)")
    ap.add_argument("--across", action="store_true", help="where lines start, not their baselines")
    ap.add_argument("--rows", help="write every off line here")
    args = ap.parse_args()
    limit = 1.0 if args.across else 0.5
    off, total, rows = collections.Counter(), collections.Counter(), []
    for ref in sorted(glob.glob(os.path.join(ROOT, "powerpoint", "*-orig.pdf"))):
        base = os.path.basename(ref)[:-len("-orig.pdf")]
        ours = os.path.join(args.work, "pdf", base + ".pdf")
        if not os.path.exists(ours):
            continue
        try:
            theirs_doc, ours_doc = pymupdf.open(ref), pymupdf.open(ours)
        except Exception:
            continue
        for i in range(min(len(theirs_doc), len(ours_doc))):
            a, r = lines(ours_doc[i], args.across), lines(theirs_doc[i], args.across)
            for text in a.keys() & r.keys():
                d = a[text][0] - r[text][0]
                if abs(d) > 6:
                    continue
                face = r[text][1].split("-")[0].split(",")[0]
                total[face] += 1
                if abs(d) >= limit:
                    off[face] += 1
                    rows.append((base, i + 1, round(d, 2), face, a[text][2], text[:40]))
    print("face  off/compared")
    for face, n in total.most_common(25):
        print(f"{face:28s} {off[face]:5d}/{n:5d}  {off[face] / n:.2f}")
    print()
    by_deck = collections.defaultdict(list)
    for row in rows:
        by_deck[row[0]].append(row[2])
    for deck, ds in sorted(by_deck.items(), key=lambda kv: -len(kv[1]))[:25]:
        print(f"{len(ds):4d} {sum(ds) / len(ds):+.2f} {deck}")
    if args.rows:
        with open(args.rows, "w") as f:
            f.write("\n".join("\t".join(map(str, r)) for r in rows) + "\n")


if __name__ == "__main__":
    main()
