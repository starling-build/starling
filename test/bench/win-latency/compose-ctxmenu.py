#!/usr/bin/env python3
"""Build the side-by-side context-menu latency film.

Both sources are real Desktop-Duplication captures of the same machine, the
same right-click on a folder row in the same folder, recorded separately --
each file manager runs under its own shell, and only one shell can own the
desktop at a time. They are aligned on t0, the frame the sync marker turned
white, which is the frame the click went in, and played at 1/8.

The measured numbers this renders (20 warm reps each, median):

    ours       first pixels  66.6 ms   finished  66.6 ms   (the same frame)
    Explorer   first pixels 233.2 ms   finished 299.8 ms

Same devices as compose-menu.py: a per-pane counter that freezes green when
that pane lands, a photo-finish hold on the frame where ours is done and
theirs is still bare, and a closing card with the medians.
Frames are written to STDOUT as raw RGB and piped straight into ffmpeg:

    python3 compose-ctxmenu.py | ffmpeg -f rawvideo -pix_fmt rgb24 \
        -s 1920x1080 -r 30 -i - -c:v libx264 -preset slow -crf 20 \
        -pix_fmt yuv420p -movflags +faststart -y ctxmenu-latency.mp4

A PNG sequence for this film is ~2 GB, which is how the first attempt filled
a tmpfs; and holding the whole sequence in memory to hard-link duplicates is
~900 MB. Streaming costs neither -- each frame is rendered, written and
dropped.
"""
import sys
from PIL import Image, ImageDraw, ImageFont

W, H, FPS = 1920, 1080, 30
SLOW = 8                       # each captured frame is held 8 output frames
SRC_MS = 1000.0 / 30.0         # capture ran at 30 fps -> 33.33 ms per frame
T0 = 8                         # index of the marker frame in the extracted sets

# offsets FROM t0, in captured frames (rep 2 of each take, the median case)
OURS_OFF      = 2              # our menu: first pixels and complete, one frame
NAT_FIRST_OFF = 7              # Windows: first pixels
NAT_SET_OFF   = 9              # Windows: finished

BG, PANEL, TEXT = (13,17,23), (22,27,34), (230,237,243)
DIM, GREEN, AMBER, BLUE, LINE = (139,148,158), (63,185,80), (210,153,34), (88,166,255), (48,54,61)

FR = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
def font(sz, bold=True): return ImageFont.truetype(FB if bold else FR, sz)
f_title, f_sub = font(52), font(26, False)
f_pane, f_count = font(34), font(58)
f_cap, f_small = font(29, False), font(22, False)
f_big, f_mid = font(92), font(38)

PANE_W, PANE_H, PANE_Y = 760, 608, 232    # 1400x1120 crops, aspect kept
PX = [168, 992]

_cache = {}
def load(dirn, idx):
    """Decoded source frames are cached: the first version of this re-decoded
    a 1400x1120 PNG for every output frame and took minutes."""
    key = (dirn, min(idx, 66) + 1)
    if key not in _cache:
        _cache[key] = Image.open("%s/%03d.png" % key).convert("RGB").resize(
            (PANE_W, PANE_H), Image.LANCZOS)
    return _cache[key]

def center(d, t, f, y, c): d.text(((W - d.textlength(t, font=f)) / 2, y), t, font=f, fill=c)

def card(lines, hold, bars=None):
    im = Image.new("RGB", (W, H), BG); d = ImageDraw.Draw(im)
    for t, f, c, y in lines:
        center(d, t, f, y, c)
    if bars:
        for label, ms, col, y in bars:
            full = 980
            d.rectangle([470, y, 470 + full, y + 26], fill=(30, 36, 44))
            d.rectangle([470, y, 470 + int(full * min(ms, 320) / 320.0), y + 26], fill=col)
    return [im] * hold

def race_frame(k, caption=None):
    src_off = k // SLOW
    ms = src_off * SRC_MS
    im = Image.new("RGB", (W, H), BG); d = ImageDraw.Draw(im)
    center(d, "Right-click a folder — click to menu", f_title, 20, TEXT)
    center(d, "same PC · same folder · same row · played at 1/8 speed", f_sub, 84, DIM)
    center(d, "captured off the composited desktop, not a screenshot — the white square is the sync marker",
           f_small, 116, (90,99,108))

    panes = [("Starling", "fr_ctx_ours", OURS_OFF, None, BLUE),
             ("Windows 11", "fr_ctx_native", NAT_SET_OFF, NAT_FIRST_OFF, AMBER)]
    for i, (name, dirn, done_off, first_off, col) in enumerate(panes):
        x = PX[i]
        im.paste(load(dirn, T0 + src_off), (x, PANE_Y))
        d.rectangle([x-2, PANE_Y-2, x+PANE_W+1, PANE_Y+PANE_H+1], outline=LINE, width=2)
        d.text((x, 158), name, font=f_pane, fill=col)

        done = src_off >= done_off
        shown = done_off * SRC_MS if done else ms
        # A running counter is DIM and a landed one is green: at the photo
        # finish both panes read the same number, and colour is what says
        # which of them is a final answer.
        cn = GREEN if done else DIM
        lab = "%d ms" % round(shown)
        d.text((x + PANE_W - d.textlength(lab, font=f_count), 150), lab, font=f_count, fill=cn)

        by = PANE_Y + PANE_H + 26
        d.rectangle([x, by, x + PANE_W, by + 16], fill=(30, 36, 44))
        d.rectangle([x, by, x + int(PANE_W * min(shown / 340.0, 1.0)), by + 16], fill=cn)

        if done:
            state = "menu on screen, complete"
        elif first_off is not None and src_off >= first_off:
            state = "first pixels at %d ms — still filling in" % round(first_off * SRC_MS)
        else:
            state = "nothing on screen"
        d.text((x, by + 32), state, font=f_small, fill=GREEN if done else DIM)

    if caption:
        d.rectangle([0, H - 88, W, H], fill=PANEL)
        center(d, caption, f_cap, H - 62, TEXT)
    return im

def emit(im, n=1):
    """One rendered frame, n times, straight down the pipe."""
    raw = im.tobytes()
    for _ in range(n):
        sys.stdout.buffer.write(raw)

def main():
    for im in card([("How fast does the right-click menu open?", f_title, TEXT, 380),
                    ("Starling's file explorer vs Windows File Explorer, on the same PC", f_sub, DIM, 470),
                    ("each in its own shell — only one shell can own the desktop at a time", f_small, DIM, 520),
                    ("20 warm right-clicks each · median · 30 Hz panel, so one frame is 33 ms", f_small, DIM, 560)], 1):
        emit(im, 78)

    total = 78
    for k in range(0, 17 * SLOW):
        off = k // SLOW
        cap = None
        if off >= NAT_SET_OFF:
            cap = "Windows: complete at 300 ms.  Starling was done at 67 ms — 4.5× sooner."
        elif off >= NAT_FIRST_OFF:
            cap = ("Windows: first pixels.  Starling's menu has been readable for %d ms."
                   % round((off - OURS_OFF) * SRC_MS))
        elif off >= OURS_OFF:
            cap = "Starling: the whole menu, drawn.  Windows: nothing on screen yet."
        im = race_frame(k, cap)
        hold = 1
        if k == OURS_OFF * SLOW: hold += 58        # the photo finish
        if k == NAT_SET_OFF * SLOW: hold += 46
        if k == 17 * SLOW - 1: hold += 24
        emit(im, hold)
        total += hold

    for im in card([("Right-click to a finished menu — median of 20 warm opens", f_mid, DIM, 150),
                    ("Starling", f_mid, BLUE, 296),
                    ("67 ms", f_big, GREEN, 346),
                    ("Windows 11", f_mid, AMBER, 556),
                    ("300 ms", f_big, AMBER, 606),
                    ("4.5× faster to a finished menu · 3.5× to first pixels", f_cap, TEXT, 826),
                    ("both menus carry the same third-party rows — the same shell handlers, asked the same way",
                     f_small, DIM, 884)], 1,
                   bars=[("Starling", 67, GREEN, 466), ("Windows 11", 300, AMBER, 726)]):
        emit(im, 150)
    total += 150
    sys.stderr.write("streamed %d frames (%.1f s)\n" % (total, total / FPS))

main()
