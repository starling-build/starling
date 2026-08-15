#!/usr/bin/env python3
"""The Starling Terminal icon: a murmuration of starlings forming a prompt
chevron. Writes build/icon/terminal-icon.svg (the reviewable form) and packs
build/macos/Terminal.icns — the ONE compiled icon artifact both platforms
consume: macos-app.sh copies it into the .app bundle, package-terminal-gtk.sh
extracts its PNGs into the hicolor tree.

Deterministic: a seeded RNG scatters the flock, so a rerun reproduces the
committed artifact bit-for-bit (same Python Mersenne stream). Rendering uses
GdkPixbuf's SVG loader (librsvg) via python3-gi — present on any GNOME dev
box. Runs only when the icon changes; the outputs are committed.

Icon grammar, for future app icons in the family: the flock forms the app's
glyph — a prompt chevron here, an S for the brand mark — amber birds
(#fbbf5c / #f0a02a / #ffd9a0) on the dark navy squircle (#0a0e17), densest at
the glyph's turn, a few strays peeling off the entry. Many birds, one shape;
many apps, one desktop.
"""
import math
import random
import struct
from pathlib import Path

import gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf

HERE = Path(__file__).resolve().parent
SVG_OUT = HERE / "terminal-icon.svg"
ICNS_OUT = HERE.parent / "macos" / "Terminal.icns"

C = 1024
SEED = 23
# Content fills 82% of the canvas with a transparent margin — Apple's
# icon-grid proportion; GNOME app icons carry similar padding.
MARGIN = 0.82
# icns entry types per pixel size; the @2x types duplicate the same pixels,
# the way iconutil's own output does.
TYPES = {32: ["ic11"], 64: ["ic12"], 128: ["ic07"],
         256: ["ic08", "ic13"], 512: ["ic09", "ic14"], 1024: ["ic10"]}


def quad(p0, p1, p2, t):
    x = (1-t)**2*p0[0] + 2*(1-t)*t*p1[0] + t**2*p2[0]
    y = (1-t)**2*p0[1] + 2*(1-t)*t*p1[1] + t**2*p2[1]
    dx = 2*(1-t)*(p1[0]-p0[0]) + 2*t*(p2[0]-p1[0])
    dy = 2*(1-t)*(p1[1]-p0[1]) + 2*t*(p2[1]-p1[1])
    return x, y, math.atan2(dy, dx)


def subcurve(p0, p1, p2, a, b):
    """The quad restricted to t in [a,b], as a new quad (for the tapered
    ghost segments)."""
    q0 = quad(p0, p1, p2, a)[:2]
    q2 = quad(p0, p1, p2, b)[:2]
    qm = quad(p0, p1, p2, (a+b)/2)[:2]
    ctrl = (2*qm[0]-(q0[0]+q2[0])/2, 2*qm[1]-(q0[1]+q2[1])/2)
    return q0, ctrl, q2


def build_svg():
    rng = random.Random(SEED)
    p = [f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 {C} {C}'>",
         "<defs><radialGradient id='glow' cx='58%' cy='50%' r='62%'>"
         "<stop offset='0%' stop-color='#fbbf5c' stop-opacity='0.10'/>"
         "<stop offset='100%' stop-color='#fbbf5c' stop-opacity='0'/>"
         "</radialGradient></defs>",
         f"<rect width='{C}' height='{C}' rx='{int(C*0.22)}' fill='#0a0e17'/>",
         f"<rect width='{C}' height='{C}' rx='{int(C*0.22)}' fill='url(#glow)'/>"]
    vertex = (0.695*C, 0.500*C)
    legs = [((0.365*C, 0.275*C), (0.545*C, 0.360*C), vertex),
            (vertex, (0.545*C, 0.640*C), (0.365*C, 0.725*C))]
    # Tapered ghost spine: nested strokes, wide only in the dense middle —
    # it guarantees the glyph reads at 16px and no blunt cap ever pokes out
    # of the flock.
    for p0, p1, p2 in legs:
        for a, b, w in [(0.15, 0.85, 56), (0.06, 0.97, 34), (0.0, 1.0, 18)]:
            q0, ctrl, q2 = subcurve(p0, p1, p2, a, b)
            p.append(f"<path d='M{q0[0]:.0f} {q0[1]:.0f} Q{ctrl[0]:.0f} "
                     f"{ctrl[1]:.0f} {q2[0]:.0f} {q2[1]:.0f}' fill='none' "
                     f"stroke='#f5b654' stroke-opacity='0.20' "
                     f"stroke-width='{w}' stroke-linecap='round'/>")
    colors = ["#fbbf5c"]*7 + ["#f0a02a"]*2 + ["#ffd9a0"]*1
    birds = []
    for li, (p0, p1, p2) in enumerate(legs):
        for _ in range(560):
            # Density biased toward the vertex end of each leg: the flock
            # bunches AT the point, which keeps the corner sharp.
            t = min(1.0, max(0.0, rng.gauss(0.62 if li == 0 else 0.38, 0.30)))
            x, y, ang = quad(p0, p1, p2, t)
            sigma = 13 if rng.random() < 0.82 else 40
            d = rng.gauss(0, sigma)
            px = x + d*math.cos(ang+math.pi/2)
            py = y + d*math.sin(ang+math.pi/2)
            edge = min(t, 1-t)
            r = 3.4 + 9.5*(0.45 + 0.55*edge)*rng.random()
            if abs(d) > 28:
                r *= 0.6
            birds.append((px, py, r, ang, rng.choice(colors),
                          0.75 + 0.25*rng.random()))
    # Strays continuing the entry tangent off the top leg — motion, life.
    x0, y0, ang0 = quad(*legs[0], 0.0)
    for _ in range(12):
        dist = 40 + 150*rng.random()
        px = x0 - dist*math.cos(ang0) + rng.gauss(0, 34)
        py = y0 - dist*math.sin(ang0) + rng.gauss(0, 30)
        birds.append((px, py, 2.4 + 3.2*rng.random(), ang0,
                      rng.choice(colors), 0.45 + 0.3*rng.random()))
    for px, py, r, ang, col, op in birds:
        if not (0.045*C < px < 0.955*C and 0.045*C < py < 0.955*C):
            continue
        p.append(f"<ellipse cx='{px:.1f}' cy='{py:.1f}' rx='{r*1.4:.1f}' "
                 f"ry='{r:.1f}' transform='rotate({math.degrees(ang):.0f} "
                 f"{px:.1f} {py:.1f})' fill='{col}' fill-opacity='{op:.2f}'/>")
    p.append("</svg>")
    return "".join(p)


def render_png(size):
    inner = round(size * MARGIN)
    art = GdkPixbuf.Pixbuf.new_from_file_at_size(str(SVG_OUT), inner, inner)
    canvas = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, size, size)
    canvas.fill(0x00000000)
    off = (size - inner) // 2
    art.composite(canvas, off, off, inner, inner, off, off, 1, 1,
                  GdkPixbuf.InterpType.HYPER, 255)
    ok, png = canvas.save_to_bufferv("png", [], [])
    assert ok
    return bytes(png)


def main():
    SVG_OUT.write_text(build_svg())
    entries = []
    for size, types in sorted(TYPES.items()):
        png = render_png(size)
        for t in types:
            entries.append(t.encode("ascii") + struct.pack(">I", len(png) + 8) + png)
    body = b"".join(entries)
    ICNS_OUT.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
    print(f"{SVG_OUT.name} + {ICNS_OUT}: {len(body) + 8} bytes, "
          f"sizes {sorted(TYPES)}")


if __name__ == "__main__":
    main()
