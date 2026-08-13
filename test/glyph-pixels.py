#!/usr/bin/env python3
"""What the terminal actually PAINTED — the half no other check in this tree sees.

`test/bench/glyph-gate.py` asks whether a codepoint has a glyph in a face we
load. That is a question about fonts on disk, and it is the cheap half. Two
failures live downstream of it, both shipped, both found by a person looking at
a screen rather than by anything here:

  1. a glyph that RESOLVES but paints nothing. Backwards font fallback inside
     one paragraph silently dropped every run after it (c2ecbf3): the cell held
     the right character, the advance measured correctly, and the row was
     blank from 日 onwards. Colour emoji did the same on CoreText.
  2. a glyph that paints but lands in the WRONG PLACE. A row was one shaped
     paragraph, so each face's natural advance applied instead of the cell
     (b0dc7d5): CJK ran 21% narrow, braille 20% wide, and everything after a
     wide glyph slid off its column for the rest of the row.

Neither is visible to the grid. The core's conformance suite and differential
battery compare CELLS, and the cells were right in both. The benchmark times
the terminal, and not painting is cheaper than painting, so a coverage hole
arrives as a better number. This is the instrument for the pixels.

    sudo test/glyph-pixels.py             drive a live desktop end to end
    sudo test/glyph-pixels.py --keep      ... and leave the terminal up
         test/glyph-pixels.py --shot P    analyse a screenshot taken earlier
         test/glyph-pixels.py --pattern   print the pattern script, to run by hand

**This is not a screenshot suite.** functional.py rejects those for good
reason: a stored baseline over a compositor rots on every theme tweak and gets
re-blessed until it asserts nothing. Nothing here is compared against a stored
image. The terminal paints its own ruler — a row of cells with alternating
background colours — so the cell grid is MEASURED from the same frame as the
glyphs, and every assertion is a relation between two things in that one
screenshot: does this cell contain ink, and does this glyph sit on the column
the ruler puts there. Change the theme, the font, or the window size and the
measurement simply re-derives itself.
"""

import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL_DRIVE = os.path.join(REPO, "build/shell-drive.py")
PATTERN_PATH = "/tmp/starling-glyph-pattern.sh"

# ── the pattern ─────────────────────────────────────────────────────────────
# Colours chosen to be absent from any wallpaper we ship and far apart in every
# channel, so classifying a pixel needs no tuning: pure magenta is the page,
# pure cyan marks the ruler and the two bars that bracket the block.
MAGENTA = (255, 0, 255)
CYAN = (0, 255, 255)
FG = (255, 255, 255)

BLOCK_CELLS = 40      # width of the painted block
CONTENT_CELLS = 20    # cells of glyphs on a test row, then the terminator
TERMINATOR = "|"      # ASCII, from the primary face, identical on every row
# One blank cell between the content and the terminator. Without it the block
# elements — █ and ▓ fill their cell edge to edge — spill antialiasing into the
# terminator's cell, and since the terminator's own ink is a thin bar near the
# middle, a column of stray white at the left edge drags its centroid a third
# of a cell left. That read as -0.29 cells of drift on exactly the two rows
# whose glyphs are widest, which is precisely what a real advance bug looks
# like. The gap costs one column and removes the confusion.
TERMINATOR_CELL = CONTENT_CELLS + 1

# Each row is CONTENT_CELLS of one thing, so drift accumulates over twenty
# advances before the terminator has to say where it landed — a 1% error in a
# glyph's width is a fifth of a cell by then, which is why the terminator is at
# the END. Every group here is one a TUI draws its interface out of; the two
# mixed rows are the exact case that broke, in both orders (the failing one put
# CJK first — see c2ecbf3, where `日本語 ✓✗→` lost everything from 日 onwards
# while `✓✗→ 日本語` drew perfectly).
def _uniform(ch, cells=1):
    return [(ch, cells)] * (CONTENT_CELLS // cells)


def _spans(text):
    """Explicit cell widths — no wcwidth dependency, and the expected layout is
    then part of the test rather than something it looks up and trusts."""
    wide = set("日本語中文한글")
    return [(c, 2 if c in wide else 1) for c in text]


ROWS = [
    ("ascii",     _uniform("M"),          "the reference: the primary face, on its own grid"),
    ("box light", _uniform("─"),          "every frame: vim, htop, mc"),
    ("box heavy", _uniform("━"),          "emphasis frames"),
    ("blocks",    _uniform("█"),          "progress bars, sparklines"),
    ("shades",    _uniform("▓"),          "meters, htop bars"),
    ("braille",   _uniform("⠋"),          "EVERY TUI spinner"),
    ("arrows",    _uniform("→"),          "hints, diffs"),
    ("marks",     _uniform("✓"),          "pass/fail"),
    ("geometric", _uniform("●"),          "bullets, play/stop"),
    ("cjk",       _uniform("日", 2),      "wide cells: two columns, one glyph"),
    ("mixed cjk first", _spans("日本語 ✓✗→ ⠋⠋ abcdef"), "the order that lost half the row"),
    ("mixed cjk last",  _spans("abcdef ⠋⠋ ✓✗→ 日本語"), "the same glyphs, the order that worked"),
]

# ── attributes ──────────────────────────────────────────────────────────────
# The rows above ask whether a glyph painted. These ask whether the CELL did,
# under the three attributes that are drawn rather than shaped — and both are
# places a cell can come out invisible while the grid holds exactly the right
# character and attribute bits.
#
#   reverse   the swap happens in two places now: the background is resolved by
#             _paintedBG for the backdrop layer, the foreground by the row
#             painter's own loop. Nothing makes them agree. Resolve both to the
#             same colour and the cell is a flat block with the text inside it
#             invisible — and every structural check here still passes, because
#             the cell is painted, just uniformly.
#   underline the only ink on a space. TerminalView trims trailing cells that
#             carry neither ink nor an underline, so an underlined run at the
#             END of a line survives only because of an explicit guard in that
#             condition. Nothing exercised it; the tail row below does.
#
# Each carries its own check and skips the glyph checks, which mean nothing
# here: a reversed cell is ink from edge to edge by design.
ATTR_ROWS = [
    ("reverse", "\x1b[7m", "\x1b[27m", "M" * CONTENT_CELLS, True,
     "reverse video (ESC[7m): a selected line, a status bar"),
    ("underline", "\x1b[4m", "\x1b[24m", " " * CONTENT_CELLS, True,
     "underline (ESC[4m) on spaces: the rule is the only ink"),
    ("underline tail", "\x1b[4m", "\x1b[24m", None, False,
     "underlined spaces that END the line — the trailing-trim guard"),
    # `J N`: the space at cell 1 is underlined and NOT trailing, so the ENGINE
    # rules it; cells 3+ are trailing, so the row painter does. Two rule-only
    # cells, one from each painter, in one row.
    ("underline join", "\x1b[4m", "\x1b[24m", "J N", False,
     "text then spaces, both underlined: two painters, one rule"),
]

# The first and last printed lines are solid cyan bars and the second is the
# ruler, so the block's extent and its row pitch are readable off the image
# without knowing anything about the font.
BAR, RULER = 0, 1
FIRST_ROW = 2
FIRST_ATTR_ROW = FIRST_ROW + len(ROWS)
N_LINES = FIRST_ATTR_ROW + len(ATTR_ROWS) + 1


def sgr(fg, bg):
    return (f"\x1b[38;2;{fg[0]};{fg[1]};{fg[2]};"
            f"48;2;{bg[0]};{bg[1]};{bg[2]}m")


RESET = "\x1b[0m"


def pattern_lines():
    lines = [sgr(FG, CYAN) + " " * BLOCK_CELLS + RESET]
    ruler = "".join(sgr(FG, CYAN if i % 2 else MAGENTA) + " "
                    for i in range(BLOCK_CELLS))
    lines.append(ruler + RESET)
    for _, spans, _ in ROWS:
        text = "".join(ch for ch, _ in spans)
        used = sum(n for _, n in spans)
        assert used == CONTENT_CELLS, f"{text!r} is {used} cells, not {CONTENT_CELLS}"
        pad = " " * (BLOCK_CELLS - TERMINATOR_CELL - 1)
        lines.append(sgr(FG, MAGENTA) + text + " " + TERMINATOR + pad + RESET)
    for _, on, off, text, terminated, _ in ATTR_ROWS:
        if not terminated:
            # Fills the block, so the attribute run is what ENDS the line —
            # with nothing after it to keep the trimmer honest. Any text comes
            # first, which is what puts the two painters on one row: the engine
            # rules the part with ink in it, the row painter the trailing rest.
            body = text or ""
            lines.append(sgr(FG, MAGENTA) + on + body
                         + " " * (BLOCK_CELLS - len(body)) + RESET)
            continue
        pad = " " * (BLOCK_CELLS - TERMINATOR_CELL - 1)
        # `off` rather than a full reset: the terminator has to stay an
        # ordinary white-on-magenta glyph so it still measures the grid.
        lines.append(sgr(FG, MAGENTA) + on + text + off + " " + TERMINATOR
                     + pad + RESET)
    lines.append(sgr(FG, CYAN) + " " * BLOCK_CELLS + RESET)
    assert len(lines) == N_LINES
    return lines


def pattern_script():
    # A quoted heredoc, so the escape bytes reach the terminal exactly as
    # written rather than through printf's own interpretation of '%'.
    body = "\n".join(pattern_lines())
    return f"""#!/bin/bash
# Generated by test/glyph-pixels.py — the terminal paints its own ruler.
set -u
size=$(stty size 2>/dev/null || echo "0 0")
rows=${{size%% *}}; cols=${{size##* }}
if [ "$cols" -lt {BLOCK_CELLS + 2} ] || [ "$rows" -lt {N_LINES + 2} ]; then
    printf 'GLYPH-PIXELS: terminal is %sx%s, need at least {BLOCK_CELLS + 2}x{N_LINES + 2}\\n' \\
        "$cols" "$rows"
    sleep 900
    exit 0
fi
trap 'printf "\\033[?25h"' EXIT
# Clear, home, and hide the cursor — a block cursor is ink, and it would sit in
# a cell this test is about to ask whether anything painted into.
printf '\\033[2J\\033[H\\033[?25l'
cat <<'STARLING_PATTERN'
{body}
STARLING_PATTERN
# Hold the screen. Returning to the prompt would repaint over the block, and
# the shell's own prompt colours would land inside the region being measured.
sleep 900
"""


# ── reading the screenshot ──────────────────────────────────────────────────

def die(msg):
    print(f"glyph-pixels: {msg}", file=sys.stderr)
    sys.exit(1)


def _band(profile, floor_ratio=0.4):
    """The longest contiguous run of rows/columns above a fraction of the peak.

    Longest run, not "every index above the threshold": the wallpaper can carry
    a stray pixel of either colour, and a single one of those at y=12 would
    stretch the block to the top of the screen and put every later measurement
    somewhere it is not.
    """
    peak = max(profile)
    if peak == 0:
        return None
    floor = peak * floor_ratio
    best = run = None
    for i, v in enumerate(profile):
        if v >= floor:
            run = (run[0], i) if run else (i, i)
            if not best or (run[1] - run[0]) > (best[1] - best[0]):
                best = run
        else:
            run = None
    return best


def find_block(img):
    """Locate the painted block, and hand back its bounding box.

    Anchored on the two solid CYAN BARS, the first and last lines the pattern
    prints — never on the block as a whole. The rows between them are what is
    under test and any of them may fail to paint: measuring the block's extent
    from its own content means a renderer that drops a row also moves every
    row band, and then a broken terminal is reported as fifteen small
    mysteries instead of the one real fault. The first attempt did exactly
    that — a blank ruler row shortened the block by two lines and every
    measurement below it landed between cells.
    """
    from PIL import ImageChops

    r, g, b = img.split()
    hi = lambda ch: ch.point(lambda v: 255 if v > 190 else 0)
    lo = lambda ch: ch.point(lambda v: 255 if v < 90 else 0)
    both = lambda a, c: ImageChops.multiply(a, c)
    magenta = both(both(hi(r), lo(g)), hi(b))
    cyan = both(both(lo(r), hi(g)), hi(b))

    w, h = img.size
    rows = list(cyan.resize((1, h), 4).getdata())      # 4 = Image.BOX
    peak = max(rows)
    if peak == 0:
        die("no painted block in the screenshot — the pattern never ran, or "
            "the keystrokes went to another window. This is a failure, not a "
            "skip: a gate that measures nothing passes everything.")
    # The bars are solid cyan across the block; the ruler is half of it, so
    # three quarters of the peak separates them cleanly.
    runs = []
    start = None
    for i, v in enumerate(rows):
        if v >= peak * 0.75:
            start = i if start is None else start
        elif start is not None:
            runs.append((start, i - 1))
            start = None
    if start is not None:
        runs.append((start, len(rows) - 1))
    if len(runs) < 2:
        die(f"found {len(runs)} solid bar(s), expected 2 — the pattern is "
            f"half-drawn or something is covering the terminal")
    y0, y1 = runs[0][0], runs[-1][1]

    cols = list(cyan.crop((0, runs[0][0], w, runs[0][1] + 1))
                .resize((w, 1), 4).getdata())
    span = _band(cols, 0.5)
    if span is None or span[1] - span[0] < BLOCK_CELLS:
        die(f"the top bar is {span} wide — too narrow to hold {BLOCK_CELLS} "
            f"cells")
    # The bars are one line each and the block is N_LINES of them, so this is
    # the row pitch before anything in between has had a say.
    pitch = (y1 + 1 - y0) / N_LINES
    if not 0.5 * (runs[0][1] - runs[0][0] + 1) <= pitch <= 3 * (runs[0][1] - runs[0][0] + 1):
        die(f"the bars are {y1 + 1 - y0} px apart, which is not {N_LINES} "
            f"lines of a {runs[0][1] - runs[0][0] + 1} px bar — the wrong two "
            f"runs were taken for the frame")
    return span[0], y0, span[1], y1, magenta, cyan


def measure_grid(cyan_mask, x0, x1, y0, row_h):
    """Cell width and origin, read off the ruler the terminal just painted.

    The ruler alternates the CELL BACKGROUND, which the row painter fills by
    the grid rect — so this measures the grid itself, with no glyph, no font
    metric and no assumption in it. That is the whole point: the numbers the
    glyphs are judged against come from the same frame that drew them.

    Returns (origin, cell, residual, complaint). A ruler that cannot be read is
    reported, not fatal: it is itself one of the failures this gate exists for
    — forty cells of coloured spaces paint nothing when the background rides on
    the text — and stopping there would hide the drift and the holes underneath
    it behind a single line about calibration. The fallback divides the block's
    own width, which is worth less (it assumes the extent it should measure)
    and is labelled as such wherever it is used.
    """
    band = cyan_mask.crop((x0, int(y0 + (RULER + 0.3) * row_h),
                           x1 + 1, int(y0 + (RULER + 0.7) * row_h)))
    w, h = band.size
    col = [v > 127 for v in band.resize((w, 1), 4).getdata()]
    edges = [x for x in range(1, w) if col[x] != col[x - 1]]
    fallback = (float(x0), (x1 + 1 - x0) / BLOCK_CELLS, 0.0)
    if len(edges) != BLOCK_CELLS - 1:
        return (*fallback,
                f"the ruler resolves to {len(edges) + 1} cells, not "
                f"{BLOCK_CELLS} — a row of {BLOCK_CELLS} coloured spaces did "
                f"not paint, so the grid below is the block's width divided "
                f"up rather than measured")
    # Least squares through (k, edge_k): the k-th edge sits at origin + k*width.
    n = len(edges)
    ks = list(range(1, n + 1))
    mk, mx = sum(ks) / n, sum(edges) / n
    var = sum((k - mk) ** 2 for k in ks)
    width = sum((k - mk) * (x - mx) for k, x in zip(ks, edges)) / var
    origin = mx - width * mk
    resid = max(abs(origin + k * width - x) for k, x in zip(ks, edges))
    if resid > 1.5:
        return (*fallback,
                f"the ruler's cells are {resid:.2f} px from evenly spaced — "
                f"the cell backgrounds themselves are off the grid")
    return origin + x0, width, resid, None


def ink_of(img, bg, box):
    """Ink pixels and their horizontal centroid inside one cell span.

    Distance from the row's own background across ALL THREE channels, not
    brightness: a colour emoji's red is as far from magenta as white is, and a
    green-channel test would score it as blank — reporting a painted glyph as
    the very bug this file exists to catch.
    """
    x0, y0, x1, y1 = box
    if x1 <= x0 or y1 <= y0:
        return 0, None
    px = img.crop((x0, y0, x1, y1)).getdata()
    count = 0
    weighted = 0.0
    w = x1 - x0
    for i, (r, g, b) in enumerate(px):
        if max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2])) > 60:
            count += 1
            weighted += i % w
    return count, (x0 + weighted / count + 0.5) if count else None


# ── the checks ──────────────────────────────────────────────────────────────

# A glyph may sit anywhere inside its cell — `→` is not centred the way `M` is
# — so drift is measured against the SAME glyph on the ascii row (the
# terminator) and, for uniform rows, against the row's own first cell. That
# removes the glyph's bearing from the number and leaves only the advance
# error, which is the bug.
#
# Measured on this box, 11.7 px cells, so the numbers behind the threshold are
# on the record rather than guessed at:
#
#   grid-corrected renderer    every row  +0.00   (identical to two decimals)
#   before the correction      up to      +0.21   (the mixed-script rows)
#   the same bug on CoreText   about      +4      (CJK ran 21% narrow)
#
# 0.15 sits between the first two: a renderer that has stopped pinning runs to
# their columns fails here even on Linux, where the primary and fallback
# monospace advances are only 0.33% apart, while a correct one has fifteen
# times the instrument's resolution in hand.
TOLERANCE = 0.15
MIN_INK = 2


def _near(p, c, tol=60):
    return max(abs(p[0] - c[0]), abs(p[1] - c[1]), abs(p[2] - c[2])) <= tol


def _rule_rows(img, cell_box, line, c):
    """Which pixel rows of one cell carry ink — the rule, in a blank cell."""
    x0, y0, x1, y1 = cell_box(line, c, 1)
    return {y for y in range(y0, y1)
            if any(not _near(img.getpixel((x, y)), MAGENTA)
                   for x in range(x0, x1))}


def check_reverse(img, cell_box, line):
    """Reverse video must swap the pair, not merge it.

    Both directions are asserted, and that is the point: the cell must be
    mostly FG colour (the swapped background actually painted) and must still
    contain BG-coloured pixels (the glyph drawn in what was the background).
    Resolve the two to the same value — which the split between _paintedBG and
    the row painter's own loop makes possible — and you get a flat block with
    invisible text, which every other check in this file happily passes.
    """
    bad = []
    for c in range(CONTENT_CELLS):
        px = list(img.crop(cell_box(line, c, 1)).getdata())
        if not px:
            continue
        swapped = sum(1 for p in px if _near(p, FG)) / len(px)
        glyph = sum(1 for p in px if _near(p, MAGENTA))
        if swapped < 0.5:
            bad.append(f"cell {c}: background did not invert")
        elif glyph < 2:
            bad.append(f"cell {c}: inverted, but the glyph is not in it")
    return bad


def check_underline(img, cell_box, line, plain_line, cells):
    """An underline is the only ink an underlined space has.

    The band is validated against a row known NOT to be underlined before it is
    trusted: a band placed off the rule would report every cell blank, which
    reads as a broken renderer rather than a broken measurement.
    """
    def band(ln, c):
        x0, y0, x1, y1 = cell_box(ln, c, 1)
        h = y1 - y0
        return img.crop((x0, y0 + int(h * 0.62), x1, y1))

    def inked(ln, c):
        return sum(1 for p in band(ln, c).getdata() if not _near(p, MAGENTA))

    # The negative control is the PAD of a plain row — unattributed spaces on
    # the same background. Using that row's glyph cells instead does not work
    # and is the first thing tried: a letter's ink reaches well into the lower
    # third of its cell, so the band tested positive on a row with no underline
    # in it at all and this guard fired on a perfectly good renderer.
    if sum(inked(plain_line, c) for c in range(TERMINATOR_CELL + 2,
                                               BLOCK_CELLS - 1)) > 0:
        die("the underline band catches ink where a plain row has only blank "
            "background — it is mis-placed, and every result from it is noise")
    return [f"cell {c}: no underline drawn" for c in cells if inked(line, c) < 1]


def _is_hole(p):
    """Is this pixel showing the terminal through the block?

    Every pixel inside the block is painted with magenta, cyan, or the white
    foreground — and each of those has at least two channels at full. So does
    any blend between them, which is what antialiasing produces. The terminal's
    own background is dark in every channel, and it is the ONLY thing that can
    show through a background the renderer failed to paint.

    Two bright channels, rather than a sampled background colour: the window is
    translucent, so "the terminal's background" is the wallpaper tinted by the
    theme and it is not one colour. Testing for the positive — the paint we
    asked for — needs no such sample and does not care what is behind the
    window.
    """
    return sum(1 for v in p if v >= 180) < 2


def analyse(path, verbose=True):
    from PIL import Image

    img = Image.open(path).convert("RGB")
    x0, y0, x1, y1, _, cyan = find_block(img)
    row_h = (y1 + 1 - y0) / N_LINES
    origin, cell, resid, ruler_complaint = measure_grid(cyan, x0, x1, y0, row_h)

    if verbose:
        print(f"glyph-pixels: block {x1 - x0 + 1}x{y1 - y0 + 1} px at "
              f"({x0},{y0}), {N_LINES} lines of {row_h:.2f} px")
        if ruler_complaint:
            print(f"              cell {cell:.3f} px wide, ESTIMATED\n")
        else:
            print(f"              cell {cell:.3f} px wide, ruler residual "
                  f"{resid:.2f} px\n")

    def cell_box(line, c0, cells):
        top = int(y0 + line * row_h + 0.12 * row_h)
        bot = int(y0 + (line + 1) * row_h - 0.12 * row_h)
        # Rounded on both edges, so consecutive cells abut exactly. An extra
        # column of slop here lets a neighbour's antialiasing count as this
        # cell's ink, which reports a blank cell as painted — the one direction
        # this gate must never be wrong in.
        return (round(origin + c0 * cell), top,
                round(origin + (c0 + cells) * cell), bot)

    failures = []
    if ruler_complaint:
        failures.append(f"ruler: {ruler_complaint}")
    ascii_term = None
    print(f"  {'row':<17} {'|-column':>9} {'drift':>8} {'bg':>6}   ink")
    for i, (name, spans, who) in enumerate(ROWS):
        line = FIRST_ROW + i
        bg = MAGENTA

        # 0. is the row's background actually covering its cells?
        #
        # Every cell of this block was given a colour, so nothing inside it may
        # show the terminal through. Two ways it did: a background painted by
        # the text engine takes the FONT's line box, so it stopped short of the
        # cell (6 px of a 25 px row under CJK), and a run with no ink painted
        # none at all, leaving holes where the spaces between scripts were.
        # Both are invisible to the grid and to every other check here.
        band = img.crop((x0, int(y0 + line * row_h) + 1,
                         x1 + 1, int(y0 + (line + 1) * row_h) - 1))
        holes = sum(1 for p in band.getdata() if _is_hole(p))
        covered = 1.0 - holes / (band.size[0] * band.size[1])
        if covered < 0.99:
            failures.append(
                f"{name}: {(1 - covered) * 100:.0f}% of the row shows the "
                f"terminal through it — the cells carry a background colour "
                f"the renderer did not paint over their full height ({who})")

        # 1. did every cell paint?
        blank = []
        centroids = []
        col = 0
        for ch, cells in spans:
            n, cx = ink_of(img, bg, cell_box(line, col, cells))
            if ch != " " and n < MIN_INK:
                blank.append((col, ch))
            centroids.append((col, cells, ch, cx))
            col += cells

        # 2. did the terminator land on its column?
        _, term_cx = ink_of(img, bg, cell_box(line, TERMINATOR_CELL, 1))
        if term_cx is None:
            failures.append(f"{name}: the terminator itself did not paint")
            print(f"  {name:<17} {'--':>9} {'--':>8} {covered:>5.0%}   "
                  f"TERMINATOR BLANK")
            continue
        if ascii_term is None:
            ascii_term = term_cx      # the reference row is first, by design
        column = (term_cx - origin) / cell
        drift = (term_cx - ascii_term) / cell

        note = ""
        if abs(drift) > TOLERANCE:
            failures.append(
                f"{name}: the row ends {drift:+.2f} cells from where the grid "
                f"puts it — {abs(drift) / CONTENT_CELLS * 100:.1f}% per glyph, "
                f"so everything after a {spans[0][0]!r} on a real row is on the "
                f"wrong column ({who})")
            note = "OFF GRID"

        # 3. and for a row of one repeated glyph, WHERE it went wrong
        uniform = len({ch for ch, _ in spans}) == 1
        if uniform and not blank:
            base = centroids[0][3]
            if base is not None:
                worst = max(
                    ((cx - base) / cell - c0, c0)
                    for c0, cells, _, cx in centroids if cx is not None)
                if abs(worst[0]) > TOLERANCE:
                    failures.append(
                        f"{name}: cell {worst[1]} is {worst[0]:+.2f} cells off "
                        f"its column")
                    note = note or f"drifts by cell {worst[1]}"

        if blank:
            shown = "".join(ch for _, ch in blank[:8])
            failures.append(
                f"{name}: {len(blank)}/{len(spans)} glyphs painted NOTHING "
                f"({shown}) — the cells hold the right characters and the "
                f"cursor advanced over them ({who})")
            note = f"{len(blank)}/{len(spans)} BLANK"

        print(f"  {name:<17} {column:>9.2f} {drift:>+8.2f} {covered:>5.0%}   "
              f"{note or 'ok'}")

    # ── attributes ──────────────────────────────────────────────────────────
    for i, (name, _, _, _, terminated, who) in enumerate(ATTR_ROWS):
        line = FIRST_ATTR_ROW + i
        if name == "reverse":
            bad = check_reverse(img, cell_box, line)
        elif name == "underline join":
            # `J N` then underlined spaces to the block edge. The engine rules
            # cells 0-2, because that run has ink in it; everything after is
            # trailing whitespace, which the engine will not paint and the row
            # painter does. They have to be ONE rule — same pixel rows, no step
            # at the seam — which is the only thing keeping _underlineRect()
            # honest about where the engine puts a rule.
            #
            # An earlier version of this row carried a terminator, so the
            # spaces were not trailing after all: the engine drew the whole
            # rule and this compared its output against itself. It passed
            # against a deliberately mis-placed rule, which is how that was
            # found.
            bad = check_underline(img, cell_box, line, FIRST_ROW,
                                  range(BLOCK_CELLS - 1))
            engine, painter = (_rule_rows(img, cell_box, line, c)
                               for c in (1, TERMINATOR_CELL))
            if not engine or not painter:
                side = "the engine" if not engine else "the row painter"
                bad.append(f"{side} drew no rule on its side of the seam")
            elif engine != painter:
                bad.append(f"the rule steps at the seam: engine draws rows "
                           f"{sorted(engine)}, the row painter {sorted(painter)}")
        elif terminated:
            bad = check_underline(img, cell_box, line, FIRST_ROW,
                                  range(CONTENT_CELLS))
        else:
            # Only the tail: cells past where a terminator would have been, so
            # the run under test is the one that ends the line.
            bad = check_underline(img, cell_box, line, FIRST_ROW,
                                  range(TERMINATOR_CELL + 1, BLOCK_CELLS - 1))
        if bad:
            failures.append(f"{name}: {bad[0]}"
                            + (f" (+{len(bad) - 1} more cells)" if len(bad) > 1
                               else "") + f" — {who}")
        print(f"  {name:<17} {'--':>9} {'--':>8} {'--':>6}   "
              f"{'ok' if not bad else str(len(bad)) + ' BAD'}")

    print()
    if failures:
        print(f"glyph-pixels: FAIL — {len(failures)} finding(s)")
        for f in failures:
            print(f"  - {f}")
        return 1
    print(f"glyph-pixels: ok — {len(ROWS)} glyph rows (every glyph painted, "
          f"every cell background covered, every row ends on its column within "
          f"{TOLERANCE:g} of a cell) and {len(ATTR_ROWS)} attribute rows")
    return 0


# ── driving a live desktop ──────────────────────────────────────────────────

def drive(*actions):
    r = subprocess.run([sys.executable, SHELL_DRIVE, *actions],
                       capture_output=True, text=True)
    if r.returncode:
        # Say what shell-drive said. "returned non-zero exit status 1" for a
        # screenshot that never arrived sends the reader to this file instead
        # of to the shell that refused.
        die(f"shell-drive {actions[0]!r} failed:\n"
            f"{(r.stderr or r.stdout).strip()}")


def running(name):
    """Alive, not merely present in the process table.

    `pgrep -x` matches a ZOMBIE, and the shell does not always reap the app it
    spawned — so a killed terminal answers "running" while its last committed
    frame is still on the screen. This gate then typed into nothing, screenshot
    the dead window, and measured the previous run's pixels: a fix looked like
    it had changed nothing at all.
    """
    out = subprocess.run(["pgrep", "-x", name], capture_output=True, text=True)
    for pid in out.stdout.split():
        try:
            with open(f"/proc/{pid}/stat") as fh:
                if fh.read().rsplit(") ", 1)[1].split()[0] != "Z":
                    return True
        except (OSError, IndexError):
            continue
    return False


def quit_terminal():
    """Let the terminal exit through its own shell, not through a signal.

    `pkill` leaves the process a ZOMBIE — the desktop shell does not reap the
    children it spawns — and the dock then believes the terminal is still up:
    clicking its icon focuses the dead window instead of launching, for the
    rest of the session. That is a real bug and it is not this file's, but a
    gate that provokes it cannot be run twice, so ask the shell inside the
    terminal to exit and only fall back to force.
    """
    if not running("TerminalApp"):
        return
    drive("key ctrl+c")          # out of the pattern script's sleep
    time.sleep(0.5)
    drive("type exit")
    drive("key enter")
    for _ in range(20):
        if not running("TerminalApp"):
            return
        time.sleep(0.5)
    subprocess.run(["pkill", "-x", "TerminalApp"], capture_output=True)


def capture(png):
    if not running("DesktopShellApp"):
        die("no shell is running — start one with build/run-desktop.sh")

    # Unlink before writing, both here and for the screenshot below. This runs
    # as root, the session owns the files it left last time, and /tmp is
    # sticky — `fs.protected_regular` then refuses the reopen with EPERM even
    # for root, which reads as "shell-drive is broken" rather than "a file from
    # the last run is in the way".
    for stale in (PATTERN_PATH, png):
        if os.path.exists(stale):
            os.remove(stale)
    with open(PATTERN_PATH, "w", encoding="utf8") as fh:
        fh.write(pattern_script())
    os.chmod(PATTERN_PATH, 0o755)

    if not running("TerminalApp"):
        drive("dock terminal", "click")
        for _ in range(40):
            if running("TerminalApp"):
                break
            time.sleep(0.5)
        else:
            die("the terminal never started")
        time.sleep(4)

    # Retry the line rather than race it. A window that has mapped does not
    # always hold focus yet, and a keystroke that lands in the void leaves a
    # screenshot with no block in it — which this file would otherwise report
    # as "the terminal painted nothing", blaming the renderer for a lost
    # keypress. Confirm the block arrived instead.
    from PIL import Image
    for attempt in range(3):
        drive(f"type bash {PATTERN_PATH}")
        drive("key enter")
        time.sleep(3)
        drive(f"shot {png}")
        img = Image.open(png).convert("RGB")
        try:
            find_block(img)
            return
        except SystemExit:
            if attempt == 2:
                raise
            print("glyph-pixels: no block yet — retyping", file=sys.stderr)
            drive("key ctrl+c")
            time.sleep(1)


def main():
    args = sys.argv[1:]
    if "--pattern" in args:
        sys.stdout.write(pattern_script())
        return 0
    if "--shot" in args:
        return analyse(args[args.index("--shot") + 1])

    png = "/tmp/starling-glyph-pixels.png"
    try:
        capture(png)
        return analyse(png)
    finally:
        if "--keep" not in args:
            quit_terminal()
            if os.path.exists(PATTERN_PATH):
                os.remove(PATTERN_PATH)
        print(f"\n(screenshot: {png})")


if __name__ == "__main__":
    sys.exit(main())
