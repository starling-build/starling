#!/usr/bin/env python3
"""Make NotoColorEmoji-Pictographs.ttf from NotoColorEmoji.ttf (SIL OFL 1.1).

The subset keeps the characters whose Unicode Emoji_Presentation property is
Yes (emoji-data.txt: faces, hands, flags' regional indicators, skin tones,
and the BMP ones such as U+2705, U+2B50, U+231A), plus ZWJ (U+200D), space and
CR (a font missing those traps the unit-test run: a layout asks the fallback
for a space). It drops the text-style symbols (U+263A, U+2714, U+2605, U+2764 ...) and the plain geometric shapes used as bullets (U+26AB ...)
that Word and PowerPoint draw as plain outlines unless a U+FE0F follows (see --text-bases below:
those go in a second face, drawn only before U+FE0F). The result goes AHEAD of DejaVu in the
glyph fallback. It is a modified version under a new name, as the OFL asks.

Source: Ubuntu's fonts-noto-color-emoji (/usr/share/fonts/truetype/noto/
NotoColorEmoji.ttf, sha256 9fd0a3d0...f10, in fonts/README.md);
emoji-data.txt: https://www.unicode.org/Public/16.0.0/ucd/emoji/emoji-data.txt
fonttools is NOT a repo dependency; use a throwaway venv:
    python3 -m venv /tmp/ftv && /tmp/ftv/bin/pip install fonttools
    /tmp/ftv/bin/python build/tools/subset-emoji.py NotoColorEmoji.ttf \
        apps/OfficeApp/Sources/OfficeApp/Resources/fonts/NotoColorEmoji-Pictographs.ttf emoji-data.txt
"""
import sys
from fontTools import subset
from fontTools.ttLib import TTFont

src, dst, data = sys.argv[1], sys.argv[2], sys.argv[3]
# A fourth argument "--text-bases" makes the OTHER subset: the Emoji=Yes characters that are NOT
# Emoji_Presentation (U+2764, U+263A, U+2714, U+2600 ... , not ASCII), as "Noto Color Emoji Variation".
# It is never in the glyph fallback: the layout draws a character in it only when U+FE0F follows
# (Word and PowerPoint then draw it in colour), and a plain U+2764 stays an outline.
text_bases = "--text-bases" in sys.argv[4:]
want = "Emoji" if text_bases else "Emoji_Presentation"
presentation = set()
for line in open(data, encoding="utf-8"):
    line = line.split("#")[0].strip()
    if not line or line.split(";")[1].strip() != want:
        continue
    span = line.split(";")[0].strip().split("..")
    presentation.update(range(int(span[0], 16), int(span[-1], 16) + 1))
if text_bases:
    pres = set()
    for line in open(data, encoding="utf-8"):
        line = line.split("#")[0].strip()
        if line and line.split(";")[1].strip() == "Emoji_Presentation":
            span = line.split(";")[0].strip().split("..")
            pres.update(range(int(span[0], 16), int(span[-1], 16) + 1))
    presentation = {c for c in presentation if c >= 0x80 and c not in pres}
FAMILY = "Noto Color Emoji Variation" if text_bases else "Noto Color Emoji Pictographs"
opts = subset.Options()
opts.layout_features = ["*"]
opts.glyph_names = True
opts.notdef_outline = True
opts.name_IDs = ["*"]
opts.name_languages = ["*"]
opts.drop_tables = []
font = TTFont(src)
cmap = font.getBestCmap()
# Plain geometric shapes (U+25FD/25FE, U+26AA/26AB, U+2B1B/2B1C) are Emoji_Presentation too,
# but documents use them as bullets and Word draws them as text glyphs of the text face:
# in the colour face they change widths (zh-06c46ba9, zh-bdae17c0 dropped).
shapes = {0x25FD, 0x25FE, 0x26AA, 0x26AB, 0x2B1B, 0x2B1C}
keep = sorted(c for c in cmap if c in presentation and (text_bases or c not in shapes)) + [0x200D, 0x20, 0x0D]
sub = subset.Subsetter(opts)
sub.populate(unicodes=keep)
sub.subset(font)
for rec in font["name"].names:
    if rec.nameID in (1, 16):
        rec.string = FAMILY
    elif rec.nameID in (4, 6):
        rec.string = FAMILY if rec.nameID == 4 else FAMILY.replace(" ", "") + "-Regular"
    elif rec.nameID == 3:
        rec.string = FAMILY.replace(" ", "") + ";subset"
font.save(dst)
print(len(keep), "code points kept")
