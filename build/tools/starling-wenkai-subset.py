#!/usr/bin/env python3
"""Subset LXGW WenKai TC (OFL 1.1) for the Kai names: build/tools/starling-wenkai-subset.py IN.ttf OUT.ttf
(needs fontTools). The set is defined by property, not listed by hand: the ideographs of Big5 and GB2312 level 1, the other characters of both,
ASCII, Latin-1, general and CJK punctuation, fullwidth forms, Bopomofo and kana, that the font has. GSUB/GPOS
features are kept whole (vert, vrt2, kern, locl...). The family name is kept: the licence declares no Reserved
Font Name. A character outside the set falls to the CJK chain."""
import sys
from fontTools.ttLib import TTFont
from fontTools import subset

def decode(codec, lead0, lead1, trail0=0x40):
    out = set()
    for hi in range(lead0, lead1 + 1):
        for lo in range(trail0, 0xFF):
            try:
                out.update(ord(c) for c in bytes([hi, lo]).decode(codec))
            except UnicodeDecodeError:
                pass
    return out

def wanted():
    """Ideographs: Big5 level 1 (the 5,401 frequent ones, leads A4-C6) and GB2312 level 1 (3,755, leads B0-D7);
    everything else of Big5 and GB2312 (symbols, Greek, Cyrillic, zhuyin, line drawing) whole. Measured on the
    corpus's Kai runs (1.03 M ideographs, dev decks and Word docs): 99.96 % of occurrences."""
    s = set()
    for c in decode('big5', 0x81, 0xFE) | decode('gb2312', 0x81, 0xFE, 0xA1):
        if not 0x3400 <= c < 0xA000:
            s.add(c)
    s |= decode('big5', 0xA4, 0xC6) | decode('gb2312', 0xB0, 0xD7, 0xA1)
    for a, b in ((0x20, 0x7E), (0xA0, 0xFF), (0x2000, 0x206F), (0x3000, 0x303F), (0x3040, 0x30FF),
                 (0x3100, 0x312F), (0x31A0, 0x31BF), (0x31F0, 0x31FF), (0xFF00, 0xFFEF)):
        s.update(range(a, b + 1))
    return s

if __name__ == '__main__':
    src, dst = sys.argv[1:3]
    cmap = TTFont(src).getBestCmap()
    keep = sorted(c for c in wanted() if c in cmap)
    opts = subset.Options()
    opts.layout_features = ['*']
    opts.name_IDs = ['*']
    opts.notdef_outline = True
    opts.glyph_names = False
    opts.hinting = False
    f = TTFont(src)
    s = subset.Subsetter(opts)
    s.populate(unicodes=keep)
    s.subset(f)
    f.save(dst)
    print(len(keep), 'characters', file=sys.stderr)
