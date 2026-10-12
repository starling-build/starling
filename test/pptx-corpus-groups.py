#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""test/pptx-corpus-groups.py — the corpus in two groups, from its baselines.

For each baseline in test/corpus/pptx (baseline.tsv, the Mac's page diff;
baseline-mupdf.tsv, MuPDF's) writes two lists of deck names beside it:

    matched[-mupdf].txt   every page 0.00% different from PowerPoint's
    others[-mupdf].txt    the rest of the decks that have a PowerPoint PDF

"Matched" is exact: worst page 0.00%, not "small". A deck in that list that
scores anything else in a sweep has regressed; a deck that reaches 0.00
moves over the next time this runs. The lists are generated — run this
after writing a sweep over a baseline, and commit them with it. The decks
with no PowerPoint PDF (fuzzer files PowerPoint will not open) are in
neither list. test/pptx-app-render.sh sweeps one group with
CORPUS_GROUP=matched or CORPUS_GROUP=others.

`test/pptx-corpus-groups.py xlsx` does the same for test/corpus/xlsx —
workbooks against Excel's PDFs, swept by test/xlsx-app-render.sh — and
`… docx` for test/corpus/docx, documents against Word's PDFs, swept by
test/docx-app-render.sh.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.join(HERE, "corpus", "pptx")


def split(baseline, suffix):
    matched, others = [], []
    with open(os.path.join(CORPUS, baseline), encoding="utf-8") as f:
        for line in f:
            name, _, rest = line.rstrip("\r\n").partition("\t")
            if not name:
                continue
            m = re.search(r"worst=([\d.]+)%", rest)
            (matched if m and float(m.group(1)) == 0 else others).append(name)
    for label, names in (("matched", matched), ("others", others)):
        with open(os.path.join(CORPUS, label + suffix + ".txt"), "w", encoding="utf-8", newline="\n") as f:
            f.write("".join(n + "\n" for n in sorted(names)))
    return len(matched), len(others)


def main():
    global CORPUS
    if len(sys.argv) > 1:
        CORPUS = os.path.join(HERE, "corpus", sys.argv[1])
    for baseline, suffix in (("baseline.tsv", ""), ("baseline-mupdf.tsv", "-mupdf")):
        if not os.path.exists(os.path.join(CORPUS, baseline)):
            continue
        m, o = split(baseline, suffix)
        print(f"{baseline}: {m} matched, {o} others")
    return 0


if __name__ == "__main__":
    sys.exit(main())
