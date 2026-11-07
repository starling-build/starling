"""draw1.py OUT.png TH0 TH1: lab pie1 single labels with slice middle in [TH0, TH1], all drawn on one pie (each at its own R, scaled to a common R=100 px), box + rim point in matching colour."""
import sys, math
from PIL import Image, ImageDraw
from load import rows
out, t0, t1 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
L = sorted([r for r in rows() if r['doc'].startswith('p1-one-') and t0 <= r['th'] <= t1], key=lambda r: r['th'])
S = 4.0; W = 1400; H = 900; im = Image.new('RGB', (W, H), 'white'); dr = ImageDraw.Draw(im)
ox, oy = W // 2, H // 2
R0 = 100.0
dr.ellipse([ox - R0 * S, oy - R0 * S, ox + R0 * S, oy + R0 * S], outline='black')
dr.line([(ox - 700, oy), (ox + 700, oy)], fill='#ddd'); dr.line([(ox, oy - 450), (ox, oy + 450)], fill='#ddd')
cols = ['red', 'blue', 'green', 'orange', 'purple', 'brown', 'teal', 'magenta', 'olive', 'navy', 'crimson', 'darkgreen', 'gray', 'black', 'gold', 'pink']
for i, r in enumerate(L):
    k = R0 / r['R']; c = cols[i % len(cols)]
    th = math.radians(r['th']); px = R0 * math.sin(th); py = -R0 * math.cos(th)
    dr.ellipse([ox + (px - 1) * S, oy + (py - 1) * S, ox + (px + 1) * S, oy + (py + 1) * S], fill=c)
    l = (r['dx'] - r['w'] / 2) * k; t = (r['dy'] - r['h'] / 2 - 1.8) * k; rr = (r['dx'] + r['w'] / 2) * k; b = (r['dy'] + r['h'] / 2 + 0.25) * k
    dr.rectangle([ox + l * S, oy + t * S, ox + rr * S, oy + b * S], outline=c)
    dr.text((ox + l * S + 2, oy + t * S + 1), '%g%s' % (r['th'], 'L' if r['leader'] else ''), fill=c)
im.save(out)
