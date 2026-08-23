#!/usr/bin/env python3
"""File-manager launch, side by side.

Win+E on the same machine. Ours starts a WHOLE NEW PROCESS each time;
Explorer opens a new window inside the already-running shell, which is its
best case. Aligned on t0 (the marker frame = the keystroke), 1/6 speed.
"""
import os, shutil
from PIL import Image, ImageDraw, ImageFont

W, H, FPS = 1920, 1080, 30
SLOW = 6
SRC_MS = 1000.0 / 30.0
T0 = 2                        # index of the marker frame in the extracted sets
OURS_FIRST, OURS_DONE = 10, 16      # offsets from t0, this take
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
CROP = (400, 150, 400+2600, 150+1700)     # trim the 4K frame to the action

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
    center(d, "Starling starts a whole new process each time; Explorer opens a window inside the shell that is already running",
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
    if off >= NAT_DONE:      cap = "Explorer finally lists its files at 1133 ms."
    elif off >= OURS_DONE:   cap = "Starling is usable. Explorer has a window frame and 'Working on it…'"
    elif off >= NAT_FIRST:   cap = "Both have pixels now — neither has files."
    elif off >= OURS_FIRST:  cap = "Starling starts painting first."
    if cap:
        d.rectangle([0, H-84, W, H], fill=PANEL)
        center(d, cap, f_cap, H-60, TEXT)
    return im

def main():
    shutil.rmtree("frames2", ignore_errors=True); os.makedirs("frames2")
    seq = card([("Opening the file manager", f_title, TEXT, 400),
                ("Starling Files vs Windows Explorer, same PC, Win+E", f_sub, DIM, 486),
                ("one representative open of six", f_small, DIM, 534)], 70)
    for k in range(0, 40*SLOW):
        seq.append(frame(k))
        if k == OURS_DONE*SLOW: seq += [seq[-1]]*60
        if k == NAT_DONE*SLOW:  seq += [seq[-1]]*44
    seq += [seq[-1]]*24
    seq += card([("Keystroke to a usable window — median of 6 launches", f_mid, DIM, 150),
                 ("Starling Files", f_mid, BLUE, 296),
                 ("500 ms", f_big, GREEN, 344),
                 ("Windows Explorer", f_mid, AMBER, 556),
                 ("1149 ms", f_big, AMBER, 604),
                 ("2.3× faster — while paying for a new process that Explorer never pays",
                  f_cap, TEXT, 830),
                 ("'usable' = the file list is actually on screen, not just a window frame", f_small, DIM, 888)],
                140, bars=[(500, GREEN, 466), (1149, AMBER, 726)])
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
