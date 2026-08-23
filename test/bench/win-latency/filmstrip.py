#!/usr/bin/env python3
"""Every composited frame from the keystroke onward, side by side.

At 30 Hz the desktop only updates every 33 ms, so these ARE all the frames --
nothing is sampled or interpolated. Counting them is the honest way to see a
difference too small to feel one-off.
"""
from PIL import Image, ImageDraw, ImageFont

T0, N = 8, 11
SRC_MS = 1000.0 / 30.0
OURS_OFF, NAT_FIRST_OFF, NAT_SET_OFF = 2, 5, 9

BG, TEXT, DIM = (13,17,23), (230,237,243), (139,148,158)
GREEN, AMBER, BLUE, LINE = (63,185,80), (210,153,34), (88,166,255), (48,54,61)
FR = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
f_h  = ImageFont.truetype(FB, 40); f_row = ImageFont.truetype(FB, 30)
f_ms = ImageFont.truetype(FR, 19); f_n = ImageFont.truetype(FB, 22)
f_ft = ImageFont.truetype(FR, 21); f_bad = ImageFont.truetype(FB, 20)

TW, TH = 168, 158
GAP, LEFT, TOP = 12, 258, 150
Wd = LEFT + N * (TW + GAP) + 30
Hd = TOP + 2 * (TH + 96) + 90

im = Image.new("RGB", (Wd, Hd), BG)
d = ImageDraw.Draw(im)
d.text((40, 40), "Every composited frame after the Win key", font=f_h, fill=TEXT)
d.text((42, 96), "30 Hz panel — one frame every 33 ms. Nothing sampled: this is all of them.",
       font=f_ft, fill=DIM)

for r, (name, dirn, land, col) in enumerate([("Starling", "fr_ours", OURS_OFF, BLUE),
                                             ("Windows 11", "fr_native", NAT_SET_OFF, AMBER)]):
    y = TOP + r * (TH + 96)
    d.text((40, y + TH // 2 - 18), name, font=f_row, fill=col)
    for i in range(N):
        x = LEFT + i * (TW + GAP)
        th = Image.open("%s/%03d.png" % (dirn, T0 + i + 1)).convert("RGB").resize((TW, TH), Image.LANCZOS)
        im.paste(th, (x, y))
        landed = i >= land
        d.rectangle([x-2, y-2, x+TW+1, y+TH+1],
                    outline=(GREEN if landed else LINE), width=(3 if landed else 1))
        d.text((x, y + TH + 8), "%d ms" % round(i * SRC_MS), font=f_ms,
               fill=(TEXT if landed else DIM))
        if i == 0:
            d.text((x, y - 30), "key", font=f_n, fill=TEXT)
        if i == land:
            d.text((x, y - 30), "DRAWN", font=f_n, fill=GREEN)
        if r == 1 and i == NAT_FIRST_OFF:
            d.text((x, y - 30), "first px", font=f_n, fill=AMBER)

d.text((42, Hd - 62),
       "Starling is finished in 2 frames.  Windows shows its first pixels at frame 5 and settles at frame 9.",
       font=f_ft, fill=TEXT)
im.save("filmstrip.png")
print("filmstrip.png", im.size)
