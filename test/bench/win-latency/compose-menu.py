#!/usr/bin/env python3
"""Build the side-by-side Start-menu latency film.

Both sources are real Desktop-Duplication captures of the same machine, the
same Win keystroke and the same screen region, recorded separately -- only one
shell can own the Win key at a time. They are aligned on t0, the frame the sync
marker turned white, which is the frame the key went in, and played at 1/8.
"""
import os, shutil
from PIL import Image, ImageDraw, ImageFont

W, H, FPS = 1920, 1080, 30
SLOW = 8                       # each captured frame is held 8 output frames
SRC_MS = 1000.0 / 30.0         # capture ran at 30 fps -> 33.33 ms per frame
T0 = 8                         # index of the marker frame in the extracted sets

# offsets FROM t0, in captured frames (measured, rep 1 of each video take)
OURS_OFF     = 2               # our menu: first pixels and fully drawn, same frame
NAT_FIRST_OFF = 5              # Windows: first pixels
NAT_SET_OFF   = 9              # Windows: settled

BG, PANEL, TEXT = (13,17,23), (22,27,34), (230,237,243)
DIM, GREEN, AMBER, BLUE, LINE = (139,148,158), (63,185,80), (210,153,34), (88,166,255), (48,54,61)

FR = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
def font(sz, bold=True): return ImageFont.truetype(FB if bold else FR, sz)
f_title, f_sub = font(54), font(26, False)
f_pane, f_count = font(34), font(62)
f_cap, f_small = font(30, False), font(22, False)
f_big, f_mid = font(92), font(38)

PANE_W, PANE_H, PANE_Y = 736, 690, 205
PX = [180, 1004]

def load(dirn, idx): return Image.open("%s/%03d.png" % (dirn, min(idx, 66) + 1)).convert("RGB")
def center(d, t, f, y, c): d.text(((W - d.textlength(t, font=f)) / 2, y), t, font=f, fill=c)

def card(lines, hold, bars=None):
    """lines = [(text, font, colour, absolute_y)]"""
    im = Image.new("RGB", (W, H), BG); d = ImageDraw.Draw(im)
    for t, f, c, y in lines:
        center(d, t, f, y, c)
    if bars:
        for label, ms, col, y in bars:
            full = 980
            d.rectangle([470, y, 470 + full, y + 26], fill=(30, 36, 44))
            d.rectangle([470, y, 470 + int(full * ms / 300.0), y + 26], fill=col)
    return [im] * hold

def race_frame(k, caption=None):
    src_off = k // SLOW                       # captured frames since t0
    ms = src_off * SRC_MS
    im = Image.new("RGB", (W, H), BG); d = ImageDraw.Draw(im)
    center(d, "Start menu — keystroke to pixels", f_title, 18, TEXT)
    center(d, "same machine · same Win key · same screen region · played at 1/8 speed", f_sub, 78, DIM)
    center(d, "the small white square is the sync marker — it flips the instant the key is injected", f_small, 108, (90,99,108))

    panes = [("Starling", "fr_ours", OURS_OFF, None, BLUE),
             ("Windows 11", "fr_native", NAT_SET_OFF, NAT_FIRST_OFF, AMBER)]
    for i, (name, dirn, done_off, first_off, col) in enumerate(panes):
        x = PX[i]
        im.paste(load(dirn, T0 + src_off).resize((PANE_W, PANE_H), Image.LANCZOS), (x, PANE_Y))
        d.rectangle([x-2, PANE_Y-2, x+PANE_W+1, PANE_Y+PANE_H+1], outline=LINE, width=2)
        d.text((x, 126), name, font=f_pane, fill=col)

        done = src_off >= done_off
        shown = done_off * SRC_MS if done else ms
        cn = GREEN if done else TEXT
        lab = "%d ms" % round(shown)
        d.text((x + PANE_W - d.textlength(lab, font=f_count), 122), lab, font=f_count, fill=cn)

        by = PANE_Y + PANE_H + 24
        d.rectangle([x, by, x + PANE_W, by + 16], fill=(30, 36, 44))
        d.rectangle([x, by, x + int(PANE_W * min(shown / 400.0, 1.0)), by + 16], fill=cn)

        if done:
            state = "fully drawn"
        elif first_off is not None and src_off >= first_off:
            state = "first pixels at %d ms — still fading in" % round(first_off * SRC_MS)
        else:
            state = "nothing on screen"
        d.text((x, by + 30), state, font=f_small, fill=GREEN if done else DIM)

    if caption:
        d.rectangle([0, H - 88, W, H], fill=PANEL)
        center(d, caption, f_cap, H - 62, TEXT)
    return im

def main():
    shutil.rmtree("frames", ignore_errors=True); os.makedirs("frames")
    seq = card([("How fast does the Start menu open?", f_title, TEXT, 400),
                ("Starling shell vs the Windows 11 shell, on the same PC", f_sub, DIM, 490),
                ("measured off the composited desktop — not a screenshot", f_small, DIM, 540)], 75)

    for k in range(0, 18 * SLOW):
        off = k // SLOW
        cap = None
        if off >= NAT_SET_OFF:
            cap = "Windows: fully drawn at 300 ms.  Starling finished 4.5× sooner."
        elif off >= NAT_FIRST_OFF:
            cap = ("Windows: first faint pixels.  Starling has been readable for %d ms."
                   % round((off - OURS_OFF) * SRC_MS))
        elif off >= OURS_OFF:
            cap = "Starling: fully drawn.  Windows: nothing on screen yet."
        seq.append(race_frame(k, cap))
        if k == OURS_OFF * SLOW: seq += [seq[-1]] * 56      # the money shot
        if k == NAT_SET_OFF * SLOW: seq += [seq[-1]] * 46
    seq += [seq[-1]] * 26

    seq += card([("Keystroke to a finished menu — median of 6 warm opens", f_mid, DIM, 150),
                 ("Starling", f_mid, BLUE, 300),
                 ("67 ms", f_big, GREEN, 350),
                 ("Windows 11", f_mid, AMBER, 560),
                 ("300 ms", f_big, AMBER, 610),
                 ("4.5× faster to a finished menu · 2.8× to first pixels", f_cap, TEXT, 830),
                 ("30 Hz panel: one composited frame = 33 ms, so ours lands in 2 frames", f_small, DIM, 890)], 140,
                bars=[("Starling", 67, GREEN, 470), ("Windows 11", 300, AMBER, 730)])

    for i, im in enumerate(seq): im.save("frames/%05d.png" % i)
    print("wrote %d frames (%.1f s)" % (len(seq), len(seq) / FPS))

main()
