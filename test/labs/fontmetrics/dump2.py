import json, os
from fontTools.ttLib import TTFont
names = "comic comicbd gara garabd garait georgia georgiab georgiai georgiaz corbel corbelb corbeli corbelz consola consolab consolai consolaz gothic gothicb gothici gothicbi".split()
out = json.load(open('fontmetrics.json'))
for k in names:
    p = 'C:/Windows/Fonts/' + k + '.ttf'
    if not os.path.exists(p): print('MISSING', k); continue
    f = TTFont(p); h = f['hhea']; o = f['OS/2']; m = f['hmtx']; c = f.getBestCmap()
    adv = {str(u): m[c[u]][0] for u in list(range(0x20, 0x7f)) + list(range(0xa0, 0x100)) if u in c}
    out[k] = {'file': k + '.ttf', 'family': f['name'].getDebugName(1), 'style': f['name'].getDebugName(2), 'upm': f['head'].unitsPerEm, 'hhea': [h.ascent, h.descent, h.lineGap],
              'os2': {'typoAsc': o.sTypoAscender, 'typoDesc': o.sTypoDescender, 'typoGap': o.sTypoLineGap, 'winAsc': o.usWinAscent, 'winDesc': o.usWinDescent, 'fsSelection': o.fsSelection}, 'adv': adv}
    print(k, out[k]['family'], out[k]['style'], out[k]['upm'], out[k]['hhea'], out[k]['os2']['winAsc'], out[k]['os2']['winDesc'], len(adv))
json.dump(out, open('fontmetrics.json', 'w'), indent=0)
