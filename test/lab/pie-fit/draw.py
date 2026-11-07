"""draw.py DOC [DOC...] OUT.png: Word's label boxes (hhea box, px, relative to the pie centre) with rim points, from the lab TSVs."""
import sys, math
from PIL import Image, ImageDraw
from load import rows
R = rows(); docs = sys.argv[1:-1]; out = sys.argv[-1]
S = 3  # px per Word px
W = 300 * S; H = 240 * S
im = Image.new('RGB', (W * len(docs), H), 'white'); dr = ImageDraw.Draw(im)
for i, d in enumerate(docs):
    L = [r for r in R if r['doc'] == d]
    ox = i * W + W // 2; oy = H // 2
    def P(x, y): return (ox + x * S, oy + y * S)
    Rp = L[0]['R'] / 0.75
    dr.ellipse([P(-Rp, -Rp), P(Rp, Rp)], outline='black')
    dr.line([P(-140, 0), P(140, 0)], fill='#ddd'); dr.line([P(0, -120), P(0, 120)], fill='#ddd')
    for r in L:
        th = math.radians(r['th']); px = Rp * math.sin(th); py = -Rp * math.cos(th)
        dr.ellipse([P(px - 1.5, py - 1.5), P(px + 1.5, py + 1.5)], fill='red')
        # fitz box in px, then Word box: top -2.4 px, bottom +0.25
        l = (r['dx'] - r['w'] / 2) / 0.75; t = (r['dy'] - r['h'] / 2) / 0.75; w = r['w'] / 0.75; h = r['h'] / 0.75
        dr.rectangle([P(l, t - 2.4), P(l + w, t + h + 0.25)], outline='blue' if not r['leader'] else 'green')
        dr.rectangle([P(l, t), P(l + w, t + h)], outline='#aaf')
        dr.text(P(l + 2, t - 1), '%d' % r['k'], fill='black')
    dr.text((i * W + 4, 4), d, fill='black')
im.save(out)
