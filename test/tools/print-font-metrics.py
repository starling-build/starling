#!/usr/bin/env python3
"""Numbers, not outlines: a Microsoft face's advance widths and line metrics, read
from the subsets its Windows prints embed (test/corpus .../word-win and
.../powerpoint-win), for a stand-in that has no metric-compatible free clone.

    test/tools/print-font-metrics.py Tahoma [Verdana ...]

For each face, Regular and Bold: the advances U+0020-U+007E in ems. Sources, best
first: the hmtx of the subsets (every glyph a print used, exact); the advance
between neighbouring characters in the prints' text (the mode, when a subset is
not read); the rest estimated from Liberation Sans' advance by the median ratio
of the known ones of their kind (upper, lower, digit, other) — marked '~'.
Also prints the hhea ascent, descent and gap (the line). Output is Swift
array literals for OfficeFonts.swift, 15 to a row, and a count of how many
glyphs were read and how many estimated."""
import collections, glob, io, json, os, re, statistics, sys
import pymupdf
from fontTools.ttLib import TTFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
LIB = os.path.join(ROOT, 'apps/OfficeApp/Sources/OfficeApp/Resources/fonts/LiberationSans-%s.ttf')

def prints():
    return sorted(glob.glob(ROOT + '/test/corpus/pptx/powerpoint-win/*.pdf') +
                  glob.glob(ROOT + '/test/corpus/docx/**/word-win/*.pdf', recursive=True))

def named(fam, nm):
    nm = nm.split('+')[-1]
    return nm == fam or nm.startswith(fam + '-') or nm.startswith(fam + ',')

def kind_of(u):
    c = chr(u)
    return 'upper' if c.isupper() else 'lower' if c.islower() else 'digit' if c.isdigit() else 'other'

def read(fam):
    hm = {'R': collections.defaultdict(collections.Counter), 'B': collections.defaultdict(collections.Counter)}
    sp = {'R': collections.defaultdict(list), 'B': collections.defaultdict(list)}
    line = {'R': collections.Counter(), 'B': collections.Counter()}
    files = 0
    for f in prints():
        try: d = pymupdf.open(f)
        except Exception: continue
        used = False
        seen = set()
        for pg in d:
            for x in pg.get_fonts(full=True):
                if x[0] in seen or not named(fam, x[3]): continue
                seen.add(x[0]); used = True
                nm = x[3].split('+')[-1]
                if 'Italic' in nm or 'Oblique' in nm: continue
                k = 'B' if 'Bold' in nm else 'R'
                try: buf = d.extract_font(x[0])[3]
                except Exception: continue
                if not buf: continue
                try:
                    t = TTFont(io.BytesIO(buf)); upm = t['head'].unitsPerEm
                    line[k][(upm, t['hhea'].ascent, t['hhea'].descent, t['hhea'].lineGap)] += 1
                    cm = t.getBestCmap() or {}
                    for u, g in cm.items(): hm[k][u][round(t['hmtx'][g][0] / upm, 4)] += 1
                except Exception: pass
            for b in pg.get_text('rawdict')['blocks']:
                for l in b.get('lines', []):
                    if abs(l['dir'][1]) > 0.01: continue
                    for s in l['spans']:
                        if not named(fam, s['font']): continue
                        nm = s['font']
                        if 'Italic' in nm or 'Oblique' in nm: continue
                        k = 'B' if 'Bold' in nm else 'R'
                        ch = s['chars']
                        for a, b2 in zip(ch, ch[1:]):
                            adv = (b2['origin'][0] - a['origin'][0]) / s['size']
                            if 0.05 < adv < 1.5 and len(a['c']) == 1: sp[k][ord(a['c'])].append(round(adv, 3))
        files += used
    return hm, sp, line, files

def liberation(k):
    t = TTFont(LIB % ('Regular' if k == 'R' else 'Bold')); cm = t.getBestCmap(); upm = t['head'].unitsPerEm
    return {u: t['hmtx'][cm[u]][0] / upm for u in range(32, 127)}

def table(fam):
    hm, sp, line, files = read(fam)
    out = {}
    for k in 'RB':
        lib = liberation(k)
        got, how = {}, {}
        for u in range(32, 127):
            if u in hm[k]: got[u] = hm[k][u].most_common(1)[0][0]; how[u] = 'hmtx'
            elif len(sp[k].get(u, [])) >= 3:
                got[u] = statistics.mode(sp[k][u]); how[u] = 'text'
        ratio = {}
        for kind in ('upper', 'lower', 'digit', 'other'):
            r = [got[u] / lib[u] for u in got if kind_of(u) == kind and lib[u] > 0]
            ratio[kind] = statistics.median(r) if r else (statistics.median([got[u] / lib[u] for u in got]) if got else 1.0)
        for u in range(32, 127):
            if u not in got: got[u] = round(lib[u] * ratio[kind_of(u)], 4); how[u] = 'est'
        out[k] = (got, how, line[k].most_common(1)[0][0] if line[k] else None)
    return out, files

def swift(name, got):
    rows = [', '.join('%.4f' % got[u] for u in range(32 + i, min(32 + i + 15, 127))) for i in range(0, 95, 15)]
    return '    static let %s: [Double] = [\n%s,\n    ]' % (name, ',\n'.join('        ' + r for r in rows))

if __name__ == '__main__':
    for fam in sys.argv[1:]:
        out, files = table(fam)
        low = fam[0].lower() + fam[1:]
        print('// %s: %d prints use it' % (fam, files))
        for k, nm in (('R', low + 'Advances'), ('B', low + 'BoldAdvances')):
            got, how, line = out[k]
            c = collections.Counter(how.values())
            print('// %s: %d from hmtx, %d from text, %d estimated; line (upm, ascent, descent, gap) = %s' % (k, c['hmtx'], c['text'], c['est'], line))
            print(swift(nm, got))
