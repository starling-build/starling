#!/usr/bin/env python3
"""Every composited frame from Win+E onward, side by side.

At 30 Hz the desktop only updates every 33 ms, so these ARE all the frames --
with one declared exception: Explorer takes 34 frames to finish, and a row of
34 tiles is unreadable, so frames 12-32 are elided behind a marked gap. That
is the only thing skipped, and the footer says so. Ours is the SLOWER side of
its median (3 frames, 100 ms, median 83), matching the film's own choice, so
the strip cannot be accused of showing our best open.

Reads fl_ours/ and fl_native/ -- 47 4K frames per side, 003.png = the
keystroke (T0=2). From the 2026-08-27 captures (file-ours20.mkv rep 3,
file-native.mkv rep 2 -- offsets verified to reproduce the committed
analysis exactly: +3, and +11/+34):

    ffmpeg -i file-ours20.mkv  -vf "fps=30,select='between(n,615,661)'" \
           -vsync vfr -start_number 1 fl_ours/%03d.png
    ffmpeg -i file-native.mkv  -vf "fps=30,select='between(n,349,395)'" \
           -vsync vfr -start_number 1 fl_native/%03d.png

The fps=30 in front of select is NOT optional. The captures are
-fps_mode passthrough, so a dropped capture frame leaves a PTS gap;
extract.sh's rawvideo path fills those gaps (constant-rate timeline, what
the analyzers count in), while a bare select counts decoded frames and
lands you 1-2 frames off t0 -- measured on this very capture, where it put
the keystroke two files early and the window "up" a frame before the key.
fps=30 makes the PNG numbering count the same timeline as the analysis.
"""
from PIL import Image, ImageDraw, ImageFont

T0 = 2
SRC_MS = 1000.0 / 30.0
N = 12                                  # every frame, 0..11 (0-367 ms)
TAIL = [33, 34]                         # then the finish line
OURS_OFF, NAT_FIRST_OFF, NAT_SET_OFF = 3, 11, 34

# Square crops of the 4K frame, one per side, each containing that side's
# window (they open in different places; each row is its own capture).
CROPS = {"fl_ours": (860, 0, 3020, 2160), "fl_native": (500, 0, 2660, 2160)}

BG, TEXT, DIM = (13,17,23), (230,237,243), (139,148,158)
GREEN, AMBER, BLUE, LINE = (63,185,80), (210,153,34), (88,166,255), (48,54,61)
FR = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
f_h  = ImageFont.truetype(FB, 40); f_row = ImageFont.truetype(FB, 30)
f_ms = ImageFont.truetype(FR, 19); f_n = ImageFont.truetype(FB, 22)
f_ft = ImageFont.truetype(FR, 21); f_gap = ImageFont.truetype(FB, 26)

TW, TH = 168, 158
GAP, LEFT, TOP = 12, 258, 150
GAPW = 96                               # the elided-frames column
COLS = N + len(TAIL)
Wd = LEFT + COLS * (TW + GAP) + GAPW + GAP + 30
Hd = TOP + 2 * (TH + 96) + 90

im = Image.new("RGB", (Wd, Hd), BG)
d = ImageDraw.Draw(im)
d.text((40, 40), "Every composited frame after Win+E", font=f_h, fill=TEXT)
d.text((42, 96), "30 Hz panel — one frame every 33 ms. Nothing sampled; only the marked gap is skipped.",
       font=f_ft, fill=DIM)

def xcol(c):
    x = LEFT + c * (TW + GAP)
    if c >= N: x += GAPW + GAP
    return x

for r, (name, dirn, land, col) in enumerate([("Starling", "fl_ours", OURS_OFF, BLUE),
                                             ("Windows 11", "fl_native", NAT_SET_OFF, AMBER)]):
    y = TOP + r * (TH + 96)
    d.text((40, y + TH // 2 - 18), name, font=f_row, fill=col)
    for c, i in enumerate(list(range(N)) + TAIL):
        x = xcol(c)
        th = Image.open("%s/%03d.png" % (dirn, T0 + i + 1)).convert("RGB") \
                  .crop(CROPS[dirn]).resize((TW, TH), Image.LANCZOS)
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
    # The gap: 21 real frames, stated rather than shown.
    gx = LEFT + N * (TW + GAP)
    d.rectangle([gx, y, gx + GAPW, y + TH], fill=(20,25,31))
    d.text((gx + 30, y + TH // 2 - 36), "· · ·", font=f_gap, fill=DIM)
    if r == 1:
        d.text((gx - 56, y + TH + 34), "21 frames — still loading", font=f_ms, fill=DIM)

d.text((42, Hd - 62),
       "Starling lists files in 3 frames — 100 ms (median of 20: 83).  Windows shows first pixels at frame 11, 367 ms, "
       "and finishes its list at frame 34 — 1133 ms this open, median 1116.",
       font=f_ft, fill=TEXT)
im.save("filmstrip-launch.png")
print("filmstrip-launch.png", im.size)
