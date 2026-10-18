"""Build "Starling FangSong" from Zhuque Fangsong (OFL 1.1): FangSong's metrics.

The face OfficeApp draws 仿宋 text in (apps/OfficeApp/Sources/OfficeApp/Resources/fonts/README.md).

build/tools/starling-fangsong.py ZHUQUE.ttf OUT.ttf

- ASCII 0x21-0x7E: each glyph in a 0.5 em cell, centred, narrowed to fit
  (FangSong's Latin is monospaced at half an em); the space 0.5 em.
- Curly quotes: a full em, “ ‘ at the cell's right and ” ’ at its left, as
  FangSong sets them.
- Full-width forms U+FF01-FF5E it lacks: the half-width glyph centred in an em.
- Line: Liberation Sans's vertical metrics, the stand-in it replaces in the app.
- GPOS (Latin kerning) dropped: it would undo the monospaced cells.
- Renamed, as the OFL asks of a modified font.
"""
import sys
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen

src, out = sys.argv[1], sys.argv[2]
f = TTFont(src)
upm = f['head'].unitsPerEm
cmap = f.getBestCmap()
gs = f.getGlyphSet()
glyf, hmtx = f['glyf'], f['hmtx']


def bounds(name):
    p = BoundsPen(gs)
    gs[name].draw(p)
    return p.bounds


def redraw(name, sx, dx):
    """The glyph `name` drawn again, x scaled by sx then moved by dx."""
    pen = TTGlyphPen(gs)
    gs[name].draw(TransformPen(pen, (sx, 0, 0, 1, dx, 0)))
    return pen.glyph()


new_glyphs = {}
new_hmtx = {}
half, full = upm // 2, upm
room = int(half * 0.92)

# ASCII into half-em cells.
for u in range(0x21, 0x7F):
    g = cmap.get(u)
    if g is None:
        continue
    b = bounds(g)
    if not b:
        new_hmtx[g] = (half, 0)
        continue
    w = b[2] - b[0]
    sx = min(1.0, room / w) if w > 0 else 1.0
    nw = w * sx
    dx = (half - nw) / 2 - b[0] * sx
    new_glyphs[g] = redraw(g, sx, dx)
    new_hmtx[g] = (half, 0)
if 0x20 in cmap:
    new_hmtx[cmap[0x20]] = (half, 0)

# Curly quotes into full cells.
for u, side in ((0x201C, 'right'), (0x2018, 'right'), (0x201D, 'left'), (0x2019, 'left')):
    g = cmap.get(u)
    if g is None:
        continue
    b = bounds(g)
    if side == 'right':
        dx = int(full * 0.863) - b[2]
    else:
        dx = int(full * 0.139) - b[0]
    new_glyphs[g] = redraw(g, 1.0, dx)
    new_hmtx[g] = (full, 0)

# Full-width forms from the half-width glyphs.
order = list(f.getGlyphOrder())
added = []
for u in range(0xFF01, 0xFF5F):
    if u in cmap:
        continue
    base = cmap.get(u - 0xFEE0)
    if base is None:
        continue
    b = bounds(base)
    name = 'uni%04X' % u
    if b:
        w = b[2] - b[0]
        dx = (full - w) / 2 - b[0]
        new_glyphs[name] = redraw(base, 1.0, dx)
    else:
        new_glyphs[name] = TTGlyphPen(gs).glyph()
    new_hmtx[name] = (full, 0)
    added.append((u, name))

for name, glyph in new_glyphs.items():
    glyf[name] = glyph
for name, m in new_hmtx.items():
    hmtx[name] = m
if added:
    f.setGlyphOrder(order + [n for _, n in added])
    for table in f['cmap'].tables:
        if table.isUnicode():
            for u, n in added:
                table.cmap[u] = n
f['maxp'].numGlyphs = len(f.getGlyphOrder())

# Vertical metrics: the stand-in's this face replaces in the app (Liberation
# Sans: hhea 1854/-434/67, typo 1491/-431/307, win 1854/434 of 2048), so that
# lines keep the heights they had and only the drawing changes. The app sets a
# Chinese line's height from its own table (OfficeFonts.EastAsianFace), not
# from these; they only must not move it.
k = upm / 2048
f['hhea'].ascent, f['hhea'].descent, f['hhea'].lineGap = round(1854 * k), round(-434 * k), round(67 * k)
os2 = f['OS/2']
os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = round(1491 * k), round(-431 * k), round(307 * k)
os2.usWinAscent, os2.usWinDescent = round(1854 * k), round(434 * k)
os2.fsSelection &= ~(1 << 7)
os2.xAvgCharWidth = full

if 'GPOS' in f:
    del f['GPOS']
if 'DSIG' in f:
    del f['DSIG']

# The name, as the OFL asks of a modified font.
family, ps = 'Starling FangSong', 'StarlingFangSong-Regular'
for rec in f['name'].names:
    nid = rec.nameID
    if nid in (1, 16):
        rec.string = family
    elif nid == 4:
        rec.string = family + ' Regular'
    elif nid == 6:
        rec.string = ps
    elif nid == 3:
        rec.string = 'Starling: ' + ps
    elif nid == 5:
        rec.string = str(rec.toUnicode()) + '; Starling FangSong metrics'
f['name'].setName('Modified from Zhuque Fangsong (OFL 1.1) to FangSong\'s metrics for Starling.', 10, 3, 1, 0x409)

f.save(out)
print('saved', out, 'glyphs', len(f.getGlyphOrder()), 'added', len(added))
