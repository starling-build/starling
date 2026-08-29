#!/usr/bin/env python3
"""What the desktop costs, doing nothing and doing things.

    sudo test/bench/shell-usage.py [--seconds N]

Drives the running shell through a set of states and measures the shell
process's CPU and resident memory in each. Needs a live desktop
(build/run-desktop.sh) and root, because it drives input through
build/shell-drive.py.

WHY /proc AND NOT `top`
-----------------------
CPU percentage from a sampling tool is an average over whatever window that
tool chose, and for a compositor that is exactly the wrong thing: a shell can
sit at 0% and then burn a core the moment a pointer crosses a tile. So each
scenario here is a FIXED wall-clock window with a known state held for its
whole duration, and the number is that window's jiffies over that window's
seconds. Nothing is inferred from a spot reading.

The measurement covers every thread of the process (/proc/<pid>/stat totals
them), which matters: the render and platform threads are where a compositor's
work actually happens, and a per-thread reading would miss it.

WHAT IDLE MEANS HERE
--------------------
"Idle" is the pointer parked away from every hoverable surface with nothing
animating. That is the number that decides whether a laptop's battery survives
the desktop being open, and it is the one worth defending: everything else is
paid only while the user is doing something.
"""

import argparse
import os
import re
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DRIVE = os.path.join(REPO, "build", "shell-drive.py")
HZ = os.sysconf("SC_CLK_TCK")


def shell_pid() -> int:
    out = subprocess.run(["pgrep", "-x", "DesktopShellApp"],
                         capture_output=True, text=True).stdout.split()
    if not out:
        sys.exit("no DesktopShellApp running — start build/run-desktop.sh first")
    return int(out[0])


def cpu_jiffies(pid: int) -> int:
    """utime + stime for every thread of the process."""
    with open(f"/proc/{pid}/stat", encoding="utf-8") as fh:
        # The comm field can contain spaces and parens; everything after the
        # last ')' is positional, and utime/stime are fields 14 and 15.
        fields = fh.read().rsplit(")", 1)[1].split()
    return int(fields[11]) + int(fields[12])


def rss_kb(pid: int) -> int:
    with open(f"/proc/{pid}/status", encoding="utf-8") as fh:
        m = re.search(r"^VmRSS:\s+(\d+) kB", fh.read(), re.M)
    return int(m.group(1)) if m else 0


def drive(*actions: str) -> None:
    subprocess.run([sys.executable, DRIVE, *actions],
                   capture_output=True, text=True)


def measure(pid: int, seconds: float) -> tuple[float, int, int]:
    """CPU% of one core, and RSS before/after, over `seconds` of a held state."""
    r0 = rss_kb(pid)
    j0 = cpu_jiffies(pid)
    t0 = time.monotonic()
    time.sleep(seconds)
    j1 = cpu_jiffies(pid)
    t1 = time.monotonic()
    r1 = rss_kb(pid)
    pct = (j1 - j0) / HZ / (t1 - t0) * 100.0
    return pct, r0, r1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=float, default=6.0,
                    help="how long to hold each state (default 6)")
    args = ap.parse_args()
    pid = shell_pid()

    # Slot centres, from the shell itself rather than a mirror of its layout.
    slots = {}
    out = subprocess.run([sys.executable, DRIVE, "dock ?"],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        p = line.split()
        if len(p) >= 4 and p[1] == "dock":
            slots[p[2]] = (float(p[3]), float(p[4]))
    if "launcher" not in slots:
        sys.exit("could not read the bar's slots from the shell")

    away = (640.0, 300.0)           # wallpaper, nothing hoverable
    bar_idle = slots["launcher"]    # a tile, but Start has no preview

    scenarios = [
        ("idle (pointer away)",
         lambda: drive(f"move {away[0]} {away[1]}")),
        ("pointer on a tile, no preview",
         lambda: drive(f"move {bar_idle[0]} {bar_idle[1]}")),
    ]

    # A running app gives us the live-preview case, which is the one that can
    # tie the shell's frame rate to the app's.
    running = [k for k in ("settings", "files", "terminal") if k in slots]
    if running:
        app = running[0]
        scenarios.append((f"hovering {app} (LIVE preview)",
                          lambda a=app: drive(f"move {slots[a][0]} {slots[a][1]}")))

    scenarios += [
        ("Start open",
         lambda: drive(f"move {slots['launcher'][0]} {slots['launcher'][1]}",
                       f"click {slots['launcher'][0]} {slots['launcher'][1]}",
                       "sleep 1", f"move {away[0]} {away[1]}")),
        ("back to idle",
         lambda: drive(f"move {away[0]} {away[1]}",
                       f"click {away[0]} {away[1]}",
                       f"move {away[0]} {away[1]}")),
    ]

    print(f"desktop usage — pid {pid}, {args.seconds:g}s per state, "
          f"CPU% is of one core")
    print()
    print(f"  {'state':34} {'CPU%':>7}  {'RSS MB':>8}  {'ΔRSS kB':>8}")
    first_rss = None
    for name, setup in scenarios:
        setup()
        time.sleep(1.0)             # let the state settle before counting
        pct, r0, r1 = measure(pid, args.seconds)
        if first_rss is None:
            first_rss = r0
        print(f"  {name:34} {pct:7.2f}  {r1/1024:8.1f}  {r1-r0:+8d}")

    print()
    print(f"  RSS drift across the run: {(rss_kb(pid) - first_rss):+d} kB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
