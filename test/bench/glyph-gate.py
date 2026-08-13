#!/usr/bin/env python3
"""Every character the corpus draws must have a glyph in a face we load.

The engine has NO system font fallback: a codepoint missing from every loaded
family paints *nothing*, while the cursor advances over the cell correctly.
Nothing else in this tree notices that.

  - The core's differential battery (core/README.md) compares the GRID, and
    the grid is right — the cell holds the codepoint it should.
  - The benchmark times the terminal, and painting nothing is CHEAPER than
    shaping and rasterising a glyph.

So a coverage regression is invisible to the correctness tests and shows up in
the benchmark as a *better* number. That is the one way this suite can be made
to lie in our favour, and it has happened twice for real: Roboto Mono has no
box-drawing at all (every TUI frame invisible), and braille — every spinner in
every TUI — was missing from all four faces until DejaVu Sans was bundled.

This gate closes that: run it before a benchmark and a blank-painting terminal
fails instead of scoring well.

    glyph-gate.py                 # the TUI set below — a CORRECTNESS check,
                                  # no corpus needed, runs in test/run.sh
    glyph-gate.py <corpus-dir>    # a benchmark corpus, before timing it

The default mode is the one that matters. Guarding only the benchmark would
leave the actual bug — a terminal that draws blanks — free to ship as long as
nobody benchmarked it; both regressions above were found by a person looking
at a screen, months apart. The TUI set is small, fixed, and covers what a
full-screen program draws its interface out of.

Exit 0 when every codepoint resolves, 1 when any does not — and 1, loudly, if
it cannot find the fonts at all. A gate that passes because it checked nothing
is worse than no gate, so "I found no faces" is a failure, never a skip.
"""

import glob
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
FONT_DIR = os.path.join(REPO, "sdk/Sources/Flutter/Terminal/Fonts")
LOADER = os.path.join(REPO, "sdk/Sources/Flutter/Terminal/TerminalView.swift")


# ── the fonts the terminal actually loads ───────────────────────────────────
# Read from the source rather than restated here. A second copy of the list is
# a second thing to forget: the gate would keep passing against the faces we
# used to load while the terminal drew with a different set.

def loaded_faces():
    faces = sorted(glob.glob(os.path.join(FONT_DIR, "*.ttf")))
    if not faces:
        die(f"no bundled faces under {FONT_DIR}")

    try:
        src = open(LOADER, encoding="utf8").read()
    except OSError as e:
        die(f"cannot read {LOADER}: {e}")
    block = re.search(r"systemFallbacks:.*?=\s*\[(.*?)\n\s*\]", src, re.S)
    if not block:
        die("could not find `systemFallbacks` in TerminalView.swift — if it "
            "moved or was renamed, fix this gate rather than deleting it")
    paths = re.findall(r'\("([^"]+)",\s*"[^"]*"\)', block.group(1))
    if not paths:
        die("`systemFallbacks` parsed as empty — the gate would then be "
            "checking only the bundled faces and passing vacuously")

    present = [p for p in paths if os.path.exists(p)]
    for p in paths:
        if p not in present:
            print(f"  note: {p} is not installed on this machine — the "
                  f"terminal will not load it either")
    return faces + present


# ── cmap ────────────────────────────────────────────────────────────────────
# Formats 4 and 12, plus TrueType collections, which is everything our faces
# use. Deliberately no fontconfig: the gate has to run wherever a benchmark
# does, and `fc-query` is one more thing to be missing on a bare test box.

def _tables(data, base=0):
    n = struct.unpack(">H", data[base + 4:base + 6])[0]
    out = {}
    for i in range(n):
        rec = base + 12 + i * 16
        tag = data[rec:rec + 4].decode("latin1")
        off, ln = struct.unpack(">II", data[rec + 8:rec + 16])
        out[tag] = (off, ln)
    return out


def coverage(path):
    data = open(path, "rb").read()
    bases = [0]
    if data[:4] == b"ttcf":                      # a collection: every font in it
        count = struct.unpack(">I", data[8:12])[0]
        bases = list(struct.unpack(f">{count}I", data[12:12 + count * 4]))

    covered = set()
    for base in bases:
        t = _tables(data, base)
        if "cmap" not in t:
            continue
        off = t["cmap"][0]
        n = struct.unpack(">H", data[off + 2:off + 4])[0]
        for i in range(n):
            rec = off + 4 + i * 8
            _, _, sub = struct.unpack(">HHI", data[rec:rec + 8])
            sub += off
            fmt = struct.unpack(">H", data[sub:sub + 2])[0]
            if fmt == 4:
                segx2 = struct.unpack(">H", data[sub + 6:sub + 8])[0]
                seg = segx2 // 2
                ends = struct.unpack(">%dH" % seg, data[sub + 14:sub + 14 + segx2])
                sp = sub + 16 + segx2
                starts = struct.unpack(">%dH" % seg, data[sp:sp + segx2])
                dp = sp + segx2
                deltas = struct.unpack(">%dh" % seg, data[dp:dp + segx2])
                rp = dp + segx2
                ranges = struct.unpack(">%dH" % seg, data[rp:rp + segx2])
                for s in range(seg):
                    for cp in range(starts[s], min(ends[s], 0xFFFF) + 1):
                        if cp == 0xFFFF:
                            continue
                        if ranges[s] == 0:
                            gid = (cp + deltas[s]) & 0xFFFF
                        else:
                            gi = rp + s * 2 + ranges[s] + (cp - starts[s]) * 2
                            if gi + 2 > len(data):
                                continue
                            gid = struct.unpack(">H", data[gi:gi + 2])[0]
                            if gid:
                                gid = (gid + deltas[s]) & 0xFFFF
                        if gid:
                            covered.add(cp)
            elif fmt == 12:
                ngroups = struct.unpack(">I", data[sub + 12:sub + 16])[0]
                for g in range(ngroups):
                    gp = sub + 16 + g * 12
                    lo, hi, gid = struct.unpack(">III", data[gp:gp + 12])
                    if gid:
                        covered.update(range(lo, min(hi, lo + 0x10000) + 1))
    return covered


# ── the corpus ──────────────────────────────────────────────────────────────

def corpus_codepoints(directory):
    files = sorted(glob.glob(os.path.join(directory, "[0-9]*.txt")))
    if not files:
        die(f"no corpus in {directory} — generate one with gen-bench.py first")
    seen = {}
    for f in files:
        raw = open(f, "rb").read()
        # set() over bytes/str runs in C at ~170 MB/s; the same thing written
        # as `for ch in raw` is a 20x slower gate over a 400 MB corpus, which
        # is the difference between running this before every round and
        # quietly not bothering. isascii() is near-free and skips the decode
        # for the nine workloads that never leave ASCII.
        if raw.isascii():
            cps = set(raw)
        else:
            cps = {ord(c) for c in set(raw.decode("utf8", "replace"))}
        # C0/C1 and DEL are commands, not cells. Everything else in these
        # streams — including the ASCII inside an escape sequence — either
        # lands in a cell or is harmless to check.
        cps = {cp for cp in cps
               if cp >= 0x20 and cp != 0x7F and not 0x80 <= cp <= 0x9F}
        for cp in cps - seen.keys():
            seen[cp] = os.path.basename(f)
    return seen, files


# ── what a TUI draws its interface out of ───────────────────────────────────
# Not "every character a terminal might see" — that is the corpus mode's job,
# and the answer there is "all of Unicode", which no bundled font satisfies.
# This is the set whose absence makes a program's INTERFACE disappear while
# its text still reads, which is the failure that has actually shipped here.
# Each entry names a real user of it, so a future reader can tell whether a
# gap matters rather than guessing.
TUI_SET = [
    ("box drawing, light",   range(0x2500, 0x2510), "every frame: vim, htop, mc"),
    ("box drawing, rounded", range(0x256D, 0x2571), "Claude Code's input box"),
    ("box drawing, double",  range(0x2550, 0x2557), "dialog frames"),
    ("box drawing, heavy",   [0x2501, 0x2503, 0x250F, 0x2513, 0x251B, 0x2517], "emphasis frames"),
    ("box drawing, joins",   [0x251C, 0x2524, 0x252C, 0x2534, 0x253C], "tables"),
    ("block elements",       range(0x2580, 0x2590), "progress bars, sparklines"),
    ("shade blocks",         [0x2591, 0x2592, 0x2593], "meters, htop bars"),
    ("braille",              range(0x2800, 0x2900), "EVERY TUI spinner"),
    ("arrows",               [0x2190, 0x2191, 0x2192, 0x2193], "hints, diffs"),
    ("geometric",            [0x25A0, 0x25B2, 0x25B6, 0x25BC, 0x25C0, 0x25CF], "bullets, play/stop"),
    ("marks",                [0x2713, 0x2717, 0x2718, 0x274C, 0x2714], "pass/fail"),
    ("prompt + ellipsis",    [0x276F, 0x2026, 0x00B7], "shell prompts, truncation"),
]


def die(msg):
    print(f"glyph-gate: {msg}", file=sys.stderr)
    sys.exit(1)


def check_tui_set(covered):
    """The correctness mode: report per group, so a gap names its own victim."""
    bad = 0
    for name, cps, who in TUI_SET:
        cps = list(cps)
        missing = [cp for cp in cps if cp not in covered]
        mark = "ok  " if not missing else "GAP "
        detail = "" if not missing else \
            f"  {len(missing)}/{len(cps)} missing: " + \
            "".join(chr(c) for c in missing[:12])
        print(f"  {mark} {name:<22} {who}{detail}")
        bad += bool(missing)
    return bad


def main():
    directory = sys.argv[1] if len(sys.argv) > 1 else None

    faces = loaded_faces()
    covered = set()
    for f in faces:
        covered |= coverage(f)

    if directory is None:
        print(f"glyph-gate: {len(faces)} faces, "
              f"{len(covered)} codepoints between them")
        bad = check_tui_set(covered)
        if bad:
            print(f"\nglyph-gate: FAIL — {bad} group(s) paint NOTHING. The "
                  f"grid is right and the cursor advances; the screen is "
                  f"blank. No other test in this tree sees that.")
            return 1
        print("\nglyph-gate: ok — every TUI drawing group resolves")
        return 0

    seen, files = corpus_codepoints(directory)
    print(f"glyph-gate: {len(files)} workloads in {directory}, "
          f"{len(seen)} distinct codepoints")
    for f in faces:
        print(f"  {os.path.basename(f):<26} {len(coverage(f)):>6} codepoints")

    missing = sorted(cp for cp in seen if cp not in covered)
    if missing:
        print()
        print("glyph-gate: FAIL — these paint NOTHING, and cost nothing to "
              "paint, so the benchmark would reward the gap:")
        for cp in missing[:40]:
            print(f"    U+{cp:04X} {chr(cp)!r:<10} first in {seen[cp]}")
        if len(missing) > 40:
            print(f"    ... and {len(missing) - 40} more")
        return 1

    print(f"\nglyph-gate: ok — all {len(seen)} codepoints resolve")
    return 0


if __name__ == "__main__":
    sys.exit(main())
