#!/usr/bin/env python3
"""Measure head proportions on a full-length render against the reference picture.

  python3 build/tools/agent-proportions.py REFERENCE.jpg RENDER.png [...]

Finds the face column, the top of the hair on it (crown) and the eye line (iris pixels) from colour, and
writes a 4x fine-ruled zoom of the chin and of the feet per image, because the chin cannot be found by
colour (skin runs on down the neck) and the soles sit on floors of different colours. Read chin and
soles off the zooms, then heads tall = (sole - crown) / (chin - crown). The reference is 7.2 heads,
eye-to-chin 4.9% of height. Compare full-length renders only: head crops are framed differently.
"""
import sys, numpy as np
from PIL import Image, ImageDraw
def landmarks(path):
    a = np.asarray(Image.open(path).convert('RGB')).astype(int); H, W, _ = a.shape
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    hair = (R > 150) & (G > 115) & (B < 170) & (R - B > 45)
    skin = (R > 190) & (G > 140) & (B > 110) & (R - B > 25) & (R - B < 110) & ~hair
    ys, xs = np.nonzero(skin[:300]); cx = int(np.median(xs))
    iris = (B > 150) & (B - R > 40) & (B - G > 25); iris[300:] = False
    iy = np.nonzero(iris.any(1))[0]; eye = int(np.median(iy))
    col = slice(cx - 4, cx + 5)
    hy = np.nonzero(hair[:, col].any(1))[0]; crown = hy[hy < eye].min()
    sk = np.nonzero(skin[:, col].any(1))[0]; sk = sk[(sk > eye) & (sk < eye + 150)]
    # chin = end of the first continuous skin run below the eyes
    run = [sk[0]]
    for y in sk[1:]:
        if y - run[-1] > 3: break
        run.append(y)
    return cx, crown, eye, run[-1]
import os
out = os.path.dirname(os.path.abspath(sys.argv[-1]))
for path, label in [(sys.argv[1], 'REF')] + [(p, os.path.basename(os.path.dirname(os.path.abspath(p)))) for p in sys.argv[2:]]:
    cx, crown, eye, chin = landmarks(path); print(label, 'cx', cx, 'crown', crown, 'eye', eye, 'chin', chin)
    im = Image.open(path).convert('RGB'); d = ImageDraw.Draw(im)
    for y, c in ((crown, (0,255,0)), (eye, (0,200,255)), (chin, (255,0,0))): d.line([(0, y), (im.width, y)], fill=c)
    im.crop((cx - 160, 60, cx + 160, 380)).save(f'{out}/lm-{label}.png')
    # fine ruler on the feet
    z = Image.open(path).convert('RGB').crop((150, 1000, 490, 1137)); z = z.resize((z.width * 2, z.height * 2)); d = ImageDraw.Draw(z)
    for y in range(1000, 1137, 5):
        yy = (y - 1000) * 2; d.line([(0, yy), (14 if y % 25 else 40, yy)], fill=(255, 60, 60))
        if y % 25 == 0: d.text((44, yy - 6), str(y), fill=(255, 120, 120))
    z.save(f'{out}/feet-{label}.png')
