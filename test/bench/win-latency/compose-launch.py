#!/usr/bin/env python3
"""File-manager launch, side by side.

Win+E on the same machine, each shell registered as THE shell when it is
filmed. Both sides are now like-for-like: our file manager is a view inside the
running shell, and Explorer hosts folder windows inside the running explorer,
so neither pays for starting a process. The earlier cut of this film was made
when ours did start one, and it said so; that caveat is gone and the gap got
wider, not narrower.

Aligned on t0 (the marker frame = the keystroke), 1/6 speed.
Take: 2026-08-27, 20 reps per side, the box on its stock CPU settings.
"""
import os, shutil
from PIL import Image, ImageDraw, ImageFont

W, H, FPS = 1920, 1080, 30
SLOW = 6
SRC_MS = 1000.0 / 30.0
T0 = 2                        # index of the marker frame in the extracted sets
# Offsets from t0, in source frames, for THIS take. Ours is deliberately the
# SLOWER side of its median (3 frames, 100 ms, against a median of 83) so the
# film cannot be accused of showing our best open.
OURS_FIRST, OURS_DONE = 3, 3
NAT_FIRST,  NAT_DONE  = 11, 34

BG, PANEL, TEXT = (13,17,23), (22,27,34), (230,237,243)
DIM, GREEN, AMBER, BLUE, LINE = (139,148,158), (63,185,80), (210,153,34), (88,166,255), (48,54,61)
FR = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
def font(s, b=True): return ImageFont.truetype(FB if b else FR, s)
f_title, f_sub, f_pane = font(50), font(25, False), font(31)
f_count, f_cap, f_small = font(58), font(29, False), font(21, False)
f_big, f_mid = font(88), font(36)

PANE_W, PANE_H, PANE_Y = 880, 575, 208
PX = [50, 990]
# Trim the 4K frame to the action, sized to contain BOTH windows: ours lands
# at 886,344-2951,2143 and Explorer's at 512,382-2803,1719.
CROP = (355, 344, 355+2753, 344+1799)

_CACHE = {}
def load(dirn, i):
    """Decode+crop+resize once per source frame, not once per output frame --
    47 4K PNGs re-decoded 1600 times is minutes of work for nothing."""
    key = (dirn, min(i, 46))
    if key not in _CACHE:
        im = Image.open("%s/%03d.png" % (dirn, key[1] + 1)).convert("RGB").crop(CROP)
        _CACHE[key] = im.resize((PANE_W, PANE_H), Image.LANCZOS)
    return _CACHE[key]
def center(d, t, f, y, c): d.text(((W - d.textlength(t, font=f)) / 2, y), t, font=f, fill=c)

def card(lines, hold, bars=None):
    im = Image.new("RGB", (W, H), BG); d = ImageDraw.Draw(im)
    for t, f, c, y in lines: center(d, t, f, y, c)
    if bars:
        for ms, col, y in bars:
            d.rectangle([420, y, 420+1080, y+24], fill=(30,36,44))
            d.rectangle([420, y, 420+int(1080*ms/1200.0), y+24], fill=col)
    return [im]*hold

def frame(k):
    off = k // SLOW
    ms = off * SRC_MS
    im = Image.new("RGB", (W, H), BG); d = ImageDraw.Draw(im)
    center(d, "Opening the file manager — Win+E", f_title, 20, TEXT)
    center(d, "same machine · same keystroke · played at 1/6 speed", f_sub, 80, DIM)
    center(d, "each shell registered as THE shell \u00b7 neither pays to start a process \u00b7 median of 20 opens per side",
           f_small, 116, (110,119,128))

    for i, (name, dirn, first, done, col) in enumerate(
            [("Starling Files", "fl_ours", OURS_FIRST, OURS_DONE, BLUE),
             ("Windows Explorer", "fl_native", NAT_FIRST, NAT_DONE, AMBER)]):
        x = PX[i]
        im.paste(load(dirn, T0 + off), (x, PANE_Y))
        d.rectangle([x-2, PANE_Y-2, x+PANE_W+1, PANE_Y+PANE_H+1], outline=LINE, width=2)
        d.text((x, 158), name, font=f_pane, fill=col)

        is_done = off >= done
        shown = done * SRC_MS if is_done else ms
        cn = GREEN if is_done else TEXT
        lab = "%d ms" % round(shown)
        d.text((x + PANE_W - d.textlength(lab, font=f_count), 150), lab, font=f_count, fill=cn)

        by = PANE_Y + PANE_H + 26
        d.rectangle([x, by, x+PANE_W, by+15], fill=(30,36,44))
        d.rectangle([x, by, x+int(PANE_W*min(shown/1200.0, 1.0)), by+15], fill=cn)

        if is_done:            state, sc = "files listed — usable", GREEN
        elif off >= first:     state, sc = ("window up, still loading" if i else "painting"), DIM
        else:                  state, sc = "nothing on screen", DIM
        d.text((x, by+30), state, font=f_small, fill=sc)

    cap = None
    if off >= NAT_DONE:      cap = "Explorer finally lists its files, at 1133 ms."
    elif off >= NAT_FIRST:   cap = "Explorer has a frame and \u2018Working on it\u2026\u2019. Starling has been usable for 267 ms."
    elif off >= OURS_DONE:   cap = "Starling is already usable \u2014 files listed. Explorer has nothing on screen yet."
    elif off >= OURS_FIRST:  cap = "Starling is up."
    if cap:
        d.rectangle([0, H-84, W, H], fill=PANEL)
        center(d, cap, f_cap, H-60, TEXT)
    return im

def main():
    shutil.rmtree("frames2", ignore_errors=True); os.makedirs("frames2")
    seq = card([("Opening the file manager", f_title, TEXT, 400),
                ("Starling Files vs Windows Explorer, same PC, Win+E", f_sub, DIM, 486),
                ("one representative open of twenty \u00b7 ours is the slower side of its median", f_small, DIM, 534)], 70)
    for k in range(0, 40*SLOW):
        seq.append(frame(k))
        if k == OURS_DONE*SLOW: seq += [seq[-1]]*60
        if k == NAT_DONE*SLOW:  seq += [seq[-1]]*44
    seq += [seq[-1]]*24
    seq += card([("Keystroke to a usable window — median of 20 launches", f_mid, DIM, 150),
                 ("Starling Files", f_mid, BLUE, 296),
                 ("83 ms", f_big, GREEN, 344),
                 ("Windows Explorer", f_mid, AMBER, 556),
                 ("1116 ms", f_big, AMBER, 604),
                 ("13.4× faster — our slowest open still beat Explorer's first pixels by 200 ms",
                  f_cap, TEXT, 830),
                 ("'usable' = the file list is actually on screen, not just a window frame", f_small, DIM, 888)],
                140, bars=[(83, GREEN, 466), (1116, AMBER, 726)])
    import os as _os
    seen = {}
    for i, im in enumerate(seq):
        key = id(im)
        p = "frames2/%05d.png" % i
        if key in seen:
            _os.link(seen[key], p)
        else:
            im.save(p); seen[key] = p
    print("wrote %d frames (%.1f s)" % (len(seq), len(seq)/FPS))
main()
