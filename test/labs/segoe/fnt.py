import sys
from fontTools.ttLib import TTFont
import os
for fn in ('segoeui','segoeuib','segoeuil','segoeuii'):
    p='C:/Windows/Fonts/%s.ttf'%fn
    if not os.path.exists(p): print(fn,'MISSING'); continue
    f=TTFont(p); h=f['hhea']; o=f['OS/2']; m=f['hmtx']; c=f.getBestCmap()
    print(fn,'upem',f['head'].unitsPerEm,'hhea',h.ascent,h.descent,h.lineGap,'win',o.usWinAscent,o.usWinDescent,'typo',o.sTypoAscender,o.sTypoDescender,o.sTypoLineGap)
    def adv(r): return [m[c[u]][0] if u in c else None for u in r]
    print(' ascii',adv(range(0x20,0x7f)))
    if fn in('segoeui','segoeuib'):
        print(' A0-FF',adv(range(0xa0,0x100)))
        print(' cyr',adv(list(range(0x410,0x450))+[0x401,0x451]))
