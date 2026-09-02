#!/usr/bin/env python3
"""Regenerate shell/Sources/DesktopShellApp/Guest/HidQnum.swift.

HID usage (page 0x07) -> XT set-1 scancode ("qnum"), the keycode space QEMU's
org.qemu.Display1.Keyboard speaks. The source of truth is keycodemapdb's
data/keymaps.csv: the `USB Keycodes` column paired with `AT set1 keycode`,
which is what `keymap-gen code-map --lang=stdc keymaps.csv usb qnum` emits.

    build/tools/gen-hid-qnum.py > shell/Sources/DesktopShellApp/Guest/HidQnum.swift

Pass a local keymaps.csv as argv[1] to work offline; otherwise it is fetched.
Extended set-1 codes are 0xe0-prefixed; QEMU folds the prefix into the high
bit (0xe01c -> 0x9c). 0xe1-prefixed codes (Pause on real set 1) have no qnum
encoding and are skipped -- the guest gets Pause through 0xe046 instead.
"""
import csv, io, sys, urllib.request

CSV_URL = ("https://gitlab.com/keycodemap/keycodemapdb/-/raw/master/"
           "data/keymaps.csv")
REVISION = "ab223f5d3113, 2024-11-05"


def load(path=None):
    if path:
        return open(path, newline="")
    with urllib.request.urlopen(CSV_URL, timeout=30) as r:
        return io.StringIO(r.read().decode("utf-8"))


def build(fh):
    out = {}
    for row in csv.DictReader(fh):
        usb, set1 = (row["USB Keycodes"] or "").strip(), (row["AT set1 keycode"] or "").strip()
        if not usb or not set1:
            continue
        try:
            u, v = int(usb, 0), int(set1, 16) if set1.startswith("0x") else int(set1, 0)
        except ValueError:
            continue
        if v == 0 or v > 0xFFFF:
            continue
        if v & 0xFF00:
            if (v >> 8) != 0xE0:
                continue
            q = (v & 0xFF) | 0x80
        else:
            q = v
        prev = out.get(u)
        if prev and prev[0] != q:
            sys.exit(f"conflicting qnum for HID 0x{u:02X}: {prev[0]:#x} vs {q:#x}")
        out.setdefault(u, (q, (row["Linux Name"] or "").strip()))
    return out


def name(n):
    return n[4:].replace("_", " ").title() if n.startswith("KEY_") else n


def main():
    table = build(load(sys.argv[1] if len(sys.argv) > 1 else None))
    rows = "\n".join(
        "        (0x%02X, 0x%02X),  // %s%s"
        % (u, q, name(n), " (extended)" if q & 0x80 else "")
        for u, (q, n) in sorted(table.items()))
    sys.stdout.write(TEMPLATE.format(revision=REVISION, rows=rows))


TEMPLATE = '''// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(Linux)

/// HID usage → XT set-1 scancode ("qnum"), the keycode space QEMU's
/// `org.qemu.Display1.Keyboard.Press/Release` speaks.
///
/// Generated, not hand-written — regenerate with
///
///     build/tools/gen-hid-qnum.py > shell/Sources/DesktopShellApp/Guest/HidQnum.swift
///
/// which reads keycodemapdb's `data/keymaps.csv` (revision {revision}) and
/// pairs its `USB Keycodes` column with `AT set1 keycode` — the same two
/// columns `keymap-gen code-map … usb qnum` uses.
///
/// Extended scancodes are `0xe0`-prefixed in set 1; QEMU folds the prefix
/// into the high bit, so `0xe01c` (keypad Enter) is qnum `0x9c`. That is the
/// encoding below, and it matches the table the M0 spike drove a real guest
/// with by hand (`docs/windows-vm/dbus-display.py`) on all 110 names the two
/// share — the cross-check that says this file is right.
///
/// Keys arrive at the intercept point as HID usages already
/// (`DesktopShell.routeKey`, `keyData.physical`), so this is one hop, not two.
/// It is deliberately NOT derived from ``HidEvdev`` at runtime: evdev is a
/// third keycode space with its own gaps, and CLAUDE.md records what a second
/// table that must stay in sync costs. `test/hid_qnum.py` asserts every usage
/// ``HidEvdev`` can deliver has a qnum here.
enum HidQnum {{

    /// (HID usage page 0x07 code, XT set-1 scancode).
    static let pairs: [(hid: UInt64, qnum: UInt32)] = [
{rows}
    ]

    /// HID usage → qnum. Built once, on first use.
    static let qnumForHid: [UInt64: UInt32] = {{
        var m = [UInt64: UInt32](minimumCapacity: pairs.count)
        for p in pairs {{ m[p.hid] = p.qnum }}
        return m
    }}()

    /// The qnum for a HID usage, or nil for a key the guest has no scancode
    /// for (dropped with one log line at the call site rather than sent as 0,
    /// which is a real scancode).
    static func qnum(forHid hid: UInt64) -> UInt32? {{ qnumForHid[hid] }}
}}

#endif  // os(Linux)
'''

if __name__ == "__main__":
    main()
