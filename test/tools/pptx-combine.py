#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""pptx-combine.py LINES RENDER_TSV OUT_TSV [DECKS PPT_DIR] — the COMBINED Slides score, per deck.

LINES is the output of test/pptx-line-match.py, RENDER_TSV the one of test/pptx-app-render.sh. A deck whose PowerPoint
print has text lines takes its line score; one with none takes the visual score (100 at <=1% worst slide, 0 at >=10%,
as test/tools/docx-combine.py). A deck that did not render scores 0.
UNSCOREABLE (by property, never by name): the deck's zip is damaged (a strict read of every entry fails) AND PowerPoint's
print is mostly blank (fewer than half its pages hold any ink): PowerPoint printed nothing while we recover and draw it,
so there is nothing to match. Such decks are left out of the mean and listed. Genuinely empty decks with a sound zip stay.
OUT_TSV: name<TAB>score<TAB>kind (line|visual|error|unscoreable). Headline printed with and without the exclusion."""
import glob, os, re, sys, zipfile
ROW = re.compile(r'\s*([\d.]+)%\s+lines (\d+)/(\d+)\s+pages (\d+)/(\d+)\s+(\S+)')

def vscore(w): return max(0.0, min(100.0, 100.0 * (10 - w) / 9))

def damaged(f):
    try:
        z = zipfile.ZipFile(f)
        if z.testzip(): return True
        for i in z.infolist():
            with z.open(i) as h: h.read(1)
        return False
    except Exception:
        return True

def mostly_blank(pdf):
    import pymupdf
    d = pymupdf.open(pdf)
    ink = sum(any(x < 250 for x in p.get_pixmap(dpi=24).samples) for p in d)
    return ink * 2 < len(d)

def main():
    lines_f, rt, out = sys.argv[1:4]
    CC = '/data/corpus-cache/test/corpus/pptx'
    decks, ppt = (sys.argv[4:6] + [CC + '/decks', CC + '/powerpoint-win'])[:2] if len(sys.argv) > 5 else (CC + '/decks', CC + '/powerpoint-win')
    L = {}
    for l in open(lines_f):
        m = ROW.match(l)
        if m: L[m.group(6)] = (float(m.group(1)), int(m.group(2)))
    V, E = {}, set()
    for l in open(rt):
        p = l.rstrip('\n').split('\t'); n = p[0][:-5]
        m = re.search(r'worst=([\d.]+)%', l)
        if m: V[n] = float(m.group(1))
        else: E.add(n)
    rows = []
    for ref in sorted(glob.glob(ppt + '/*-orig.pdf')):
        n = os.path.basename(ref)[:-9]
        deck = os.path.join(decks, n + '.pptx')
        if not os.path.exists(deck): continue
        if damaged(deck) and mostly_blank(ref): rows.append((n, 0.0, 'unscoreable')); continue
        if n in L and L[n][1] > 0: rows.append((n, L[n][0], 'line'))
        elif n in E or n not in V: rows.append((n, 0.0, 'error'))
        else: rows.append((n, vscore(V[n]), 'visual'))
    with open(out, 'w') as f:
        for r in rows: f.write('%s\t%.2f\t%s\n' % r)
    allv = [r[1] for r in rows]; sc = [r[1] for r in rows if r[2] != 'unscoreable']
    print('%d decks: combined mean %.2f (%d line, %d visual, %d error); %d unscoreable left out -> mean %.2f (was %.2f with them)' % (
        len(sc), sum(sc) / len(sc), sum(r[2] == 'line' for r in rows), sum(r[2] == 'visual' for r in rows),
        sum(r[2] == 'error' for r in rows), len(rows) - len(sc), sum(sc) / len(sc), sum(allv) / len(allv)))
    for r in rows:
        if r[2] == 'unscoreable': print('  unscoreable', r[0])
main()
