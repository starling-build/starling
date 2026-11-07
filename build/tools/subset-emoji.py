#!/usr/bin/env python3
"""Make NotoColorEmoji-Pictographs.ttf from NotoColorEmoji.ttf (SIL OFL 1.1).

The subset keeps the pictographs at U+1F000 and above (faces, hands, flags'
regional indicators, skin tones, ...) plus ZWJ (U+200D), with the GSUB
sequences among them, and drops the BMP symbols (U+2xxx) that the document
faces and DejaVu Sans draw as plain outlines (a smiley U+263A is black in
Word and PowerPoint). The result goes AHEAD of DejaVu in the glyph fallback.
It is a modified version under a new name, as the OFL asks.

fonttools is NOT a repo dependency; use a throwaway venv:
    python3 -m venv /tmp/ftv && /tmp/ftv/bin/pip install fonttools
    /tmp/ftv/bin/python build/tools/subset-emoji.py \
        apps/OfficeApp/Sources/OfficeApp/Resources/fonts/NotoColorEmoji.ttf \
        apps/OfficeApp/Sources/OfficeApp/Resources/fonts/NotoColorEmoji-Pictographs.ttf
"""
import sys
from fontTools import subset
from fontTools.ttLib import TTFont

src, dst = sys.argv[1], sys.argv[2]
FAMILY = "Noto Color Emoji Pictographs"
opts = subset.Options()
opts.layout_features = ["*"]
opts.glyph_names = True
opts.notdef_outline = True
opts.name_IDs = ["*"]
opts.name_languages = ["*"]
opts.drop_tables = []
font = TTFont(src)
cmap = font.getBestCmap()
keep = sorted(c for c in cmap if c >= 0x1F000) + [0x200D]
sub = subset.Subsetter(opts)
sub.populate(unicodes=keep)
sub.subset(font)
for rec in font["name"].names:
    if rec.nameID in (1, 16):
        rec.string = FAMILY
    elif rec.nameID in (4, 6):
        rec.string = FAMILY if rec.nameID == 4 else FAMILY.replace(" ", "") + "-Regular"
    elif rec.nameID == 3:
        rec.string = "NotoColorEmoji-Pictographs;subset"
font.save(dst)
print(len(keep), "code points kept")
