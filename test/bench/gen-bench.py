#!/usr/bin/env python3
"""Generate terminal benchmark streams, one file per workload.

Modelled on vtebench's categories. Each workload is written to a FILE and the
benchmark then `cat`s it: that way the producer costs the same on both
terminals (a page-cached read) and what we measure is the terminal draining
and drawing, not `seq` or a Python loop.

Sizes are chosen so each test runs a couple of seconds on a fast terminal —
long enough that startup and the repaint coalescing window do not dominate.
"""
import os, random, sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "bench"
# <= the narrower of the two terminals, so "one line" is the same amount of
# work in both regardless of window size. The fullscreen protocol (both
# terminals verified at the SAME grid — see run-gnome-fs.sh) regenerates the
# corpus at that grid so the cell-filling workloads fill every column.
COLS = int(sys.argv[2]) if len(sys.argv) > 2 else 200
ROWS = int(sys.argv[3]) if len(sys.argv) > 3 else 45
# The sizes below were chosen when "a couple of seconds per workload" was
# true; the terminals have since gotten ~4x faster and most workloads finish
# in 0.1-0.4 s, where timer noise and scheduler luck are a visible fraction
# of the number. SCALE multiplies every workload's repeat count — pass ~6 to
# put the faster terminal back at 1-2 s per workload. The default of 1 keeps
# the standard corpus byte-identical to what every archived round measured.
SCALE = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
def S(n): return int(n * SCALE)
os.makedirs(OUT, exist_ok=True)
random.seed(1234)   # deterministic corpus

def write(name, data):
    p = os.path.join(OUT, name)
    with open(p, "wb") as f:
        f.write(data if isinstance(data, bytes) else data.encode())
    print(f"{name:24s} {os.path.getsize(p)/1e6:8.1f} MB")

# 1. light_cells — short lines, the classic scrolling dump. Mostly measures
#    line feed + scrollback churn rather than cell filling.
write("01_light_cells.txt", "".join(f"{i}\n" for i in range(S(1_500_000))))

# 2. dense_cells — every line fills the row, so cell writes dominate.
row = "".join(chr(0x41 + (i % 26)) for i in range(COLS))
write("02_dense_cells.txt", "".join(row + "\n" for _ in range(S(150_000))))

# 3. sgr_fg — an SGR colour change per cell: hammers the CSI parser and the
#    attribute path, not just the glyph store.
buf = []
for _ in range(S(60_000)):
    buf.append("".join(f"\x1b[3{i % 8}m{chr(0x41 + i % 26)}" for i in range(COLS)))
    buf.append("\x1b[0m\n")
write("03_sgr_fg.txt", "".join(buf))

# 4. sgr_truecolor — 24-bit colour, so each escape carries five parameters.
buf = []
for _ in range(S(30_000)):
    buf.append("".join(
        f"\x1b[38;2;{(i*7)%256};{(i*13)%256};{(i*29)%256}m{chr(0x41 + i % 26)}"
        for i in range(COLS)))
    buf.append("\x1b[0m\n")
write("04_sgr_truecolor.txt", "".join(buf))

# 5. unicode — exercises the UTF-8 decode path (2, 3 and 4 byte sequences).
#    Glyph coverage differs between the two fonts, but decoding is the point.
pool = "héllo wörld Привет αβγδ 日本語 中文 ✓✗→ ≤∞ 🎉🚀"
line = (pool * ((COLS // len(pool)) + 1))[:COLS]
write("05_unicode.txt", "".join(line + "\n" for _ in range(S(150_000))))

# 6. cursor_motion — CSI cursor addressing with no scrolling: the cost is
#    parsing and random cell access, which a pure dump never touches.
buf = ["\x1b[2J"]
for _ in range(S(400_000)):
    r = random.randint(1, ROWS); c = random.randint(1, COLS)
    buf.append(f"\x1b[{r};{c}H{chr(0x41 + random.randint(0,25))}")
write("06_cursor_motion.txt", "".join(buf) + "\x1b[2J\x1b[H")

# 7. alt_screen — enter/leave the alternate screen with a full repaint each
#    time, the shape every TUI (vim, htop, less) actually produces.
buf = []
for _ in range(S(4_000)):
    buf.append("\x1b[?1049h\x1b[2J\x1b[H")
    for r in range(ROWS):
        buf.append(f"\x1b[{r+1};1H" + row[:COLS])
    buf.append("\x1b[?1049l")
write("07_alt_screen.txt", "".join(buf))

# 8. scroll_region — DECSTBM, so scrolling goes through the region path
#    rather than the whole-screen one.
buf = [f"\x1b[5;{ROWS-5}r"]
for i in range(S(600_000)):
    buf.append(f"line {i} " + row[:60] + "\n")
buf.append("\x1b[r")
write("08_scroll_region.txt", "".join(buf))

# 9. long_lines — far wider than the window, so autowrap runs constantly.
long_row = "".join(chr(0x41 + (i % 26)) for i in range(COLS * 8))
write("09_long_lines.txt", "".join(long_row + "\n" for _ in range(S(25_000))))

# 10. binary — random printable bytes with stray escapes: the parser's
#     worst case, and a crash test as much as a speed one.
if SCALE == 1.0:
    rnd = bytearray()
    for _ in range(30_000_000):
        rnd.append(random.choice(b"abcdefghijklmnopqrstuvwxyz0123456789 \n\x1b["))
    binary = bytes(rnd)
else:
    # chunked draw — the per-byte loop takes minutes at scale; the default
    # path stays byte-for-byte what the archived corpora were built from
    alphabet = b"abcdefghijklmnopqrstuvwxyz0123456789 \n\x1b["
    parts = []
    left = S(30_000_000)
    while left > 0:
        k = min(left, 1_000_000)
        parts.append(bytes(random.choices(alphabet, k=k)))
        left -= k
    binary = b"".join(parts)
write("10_binary.txt", binary + b"\x1b[0m\n")

# box_glyphs — deliberately UNNUMBERED: not part of the 10-workload suite, so
# every archived round's suite totals stay comparable. This is the corpus for
# the synthesized-glyph path (TerminalBoxGlyphs): TUI chrome repaints with
# rounded corners and dashed separators, double-line frames, braille spinners
# and graphs, and powerline status lines. Run it standalone when the
# synthesis coverage changes, so "the fast path got wider" stays a measured
# claim rather than an argued one.
inner = COLS - 2
spin = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
frames = []
for i in range(S(900)):
    f = []
    f.append("\x1b[H")
    f.append("╭" + "─" * inner + "╮\n")
    for r in range(ROWS - 6):
        s = spin[(i + r) % len(spin)]
        graph = "".join(chr(0x2800 + ((i * 7 + r * 13 + k) % 255) + 1)
                        for k in range(24))
        body = f" {s} job {r:03d} {graph} " + "▁▂▃▄▅▆▇█"[(i + r) % 8] * 8
        f.append("│" + body.ljust(inner)[:inner] + "│\n")
    f.append("├" + "┄" * inner + "┤\n")
    f.append("╔" + "═" * (inner - 2) + "╗\n".ljust(1))
    seg = (f"\x1b[47;30m mode {i % 9} \x1b[0m"
           f"\x1b[7m branch/main \x1b[27m ok ")
    f.append("║" + (seg + "\x1b[0m").ljust(inner) + "║\n")
    f.append("╚" + "═" * (inner - 2) + "╝\n")
    f.append("╰" + "─" * inner + "╯\n")
    frames.append("".join(f))
write("box_glyphs.txt", "".join(frames))
