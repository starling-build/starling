#!/usr/bin/env python3
# The guest keyboard table, against the tables it has to agree with.
#
# Keys reach a VM guest as XT set-1 scancodes ("qnum"), so the shell carries
# HidQnum.pairs alongside HidEvdev.pairs. That is a second keycode table which
# must not drift from the first: a HID usage the shell can deliver but has no
# qnum for is a key that silently does nothing in Windows, and nothing else
# would catch it — the shell's own UI keeps working, and the guest just never
# sees the key. Same failure mode as the HID↔evdev drift CLAUDE.md records.
#
# Both files are parsed as text, the way test/lint.py reads Swift: this tier
# has no compiler and no desktop.

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GUEST = REPO / "shell/Sources/DesktopShellApp/Guest/HidQnum.swift"
WAYLAND = REPO / "shell/Sources/DesktopShellApp/Wayland/HidEvdev.swift"

failures = []


def check(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok    {name}")
    else:
        failures.append(name)
        print(f"  FAIL  {name}{': ' + detail if detail else ''}")


def pairs(path: Path, kind: str) -> list:
    """The (first, second) integers of every `(a, b),` line in `pairs`."""
    text = path.read_text()
    body = text[text.index(f"static let pairs: [(hid: UInt64, {kind}"):]
    body = body[:body.index("\n    ]")]
    return [(int(a, 0), int(b, 0))
            for a, b in re.findall(r"\((0x[0-9A-Fa-f]+|\d+),\s*(0x[0-9A-Fa-f]+|\d+)\)", body)]


def main() -> int:
    if not GUEST.exists():
        print(f"  FAIL  {GUEST.relative_to(REPO)} is missing")
        return 1

    qnum = pairs(GUEST, "qnum")
    evdev = pairs(WAYLAND, "evdev")
    check("the guest table is non-trivial", len(qnum) > 100, f"only {len(qnum)} entries")

    hids = [h for h, _ in qnum]
    dupes = sorted({hex(h) for h in hids if hids.count(h) > 1})
    check("no HID usage is mapped twice", not dupes, ", ".join(dupes))

    have = dict(qnum)
    missing = sorted(f"0x{h:02X}" for h, _ in evdev if h not in have)
    check("every HID usage the shell can deliver has a qnum",
          not missing, "no qnum for " + ", ".join(missing))

    bad = sorted(f"0x{h:02X}→{q:#x}" for h, q in qnum if q == 0 or q > 0xFF)
    check("every qnum is a single byte, and none is 0",
          not bad, ", ".join(bad))

    # The extended-key encoding, spot-checked against the table the M0 spike
    # drove a real guest with (docs/windows-vm/dbus-display.py): keypad Enter,
    # Home and left Meta are 0xe0-prefixed in set 1 and carry the high bit.
    spot = {0x58: 0x9C, 0x4A: 0xC7, 0xE3: 0xDB, 0x04: 0x1E, 0x28: 0x1C}
    wrong = sorted(f"0x{h:02X}: got {have.get(h)!r}, want {q:#x}"
                   for h, q in spot.items() if have.get(h) != q)
    check("the extended-key encoding matches the spike's working table",
          not wrong, "; ".join(wrong))

    if failures:
        print(f"FAIL — {len(failures)} guest keyboard check(s)")
        return 1
    print(f"all guest keyboard checks passed ({len(qnum)} keys)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
