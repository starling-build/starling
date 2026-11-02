import json, sys, os
from fontTools.ttLib import TTFont
FILES = {'century': 'century.ttf', 'verdana': 'verdana.ttf', 'verdanab': 'verdanab.ttf', 'verdanai': 'verdanai.ttf', 'verdanaz': 'verdanaz.ttf',
         'centuryb': 'centuryb.ttf', 'centuryi': 'centuryi.ttf'}
out = {}
for k, fn in FILES.items():
    p = 'C:/Windows/Fonts/' + fn
    if not os.path.exists(p): continue
    f = TTFont(p); h = f['hhea']; o = f['OS/2']; m = f['hmtx']; c = f.getBestCmap()
    adv = {str(u): m[c[u]][0] for u in list(range(0x20, 0x7f)) + list(range(0xa0, 0x100)) if u in c}
    out[k] = {'file': fn, 'upm': f['head'].unitsPerEm, 'hhea': [h.ascent, h.descent, h.lineGap],
              'os2': {'typoAsc': o.sTypoAscender, 'typoDesc': o.sTypoDescender, 'typoGap': o.sTypoLineGap, 'winAsc': o.usWinAscent, 'winDesc': o.usWinDescent,
                      'fsSelection': o.fsSelection}, 'adv': adv}
json.dump(out, open('fontmetrics.json', 'w'), indent=0)
for k, v in out.items(): print(k, v['upm'], v['hhea'], v['os2'], len(v['adv']))
