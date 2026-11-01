#!/usr/bin/env python3
"""Measure a headless desktop: idle cost, then a steady animation workload.

    build/tools/headless-bench.py SOCKET [SECONDS]

Workload: Settings + Terminal open, then a window is dragged back and forth
for SECONDS (default 10) — every drag step repaints the shell chrome AND
re-composites a client window, which is the worst steady case short of video.
Reports presented frames/s, frame-interval percentiles and process CPU
seconds per wall second ("cores") and per frame, from the shell's own
`stats` op. The box's load average is printed beside it: llvmpipe shares the
CPUs with everyone, so a number without its load is not a number.
"""
import json
import os
import socket
import sys
import time


class C:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX)
        self.s.connect(path)
        self.b = b""
        self.n = 0

    def call(self, op, **kw):
        self.n += 1
        self.s.sendall((json.dumps({"id": self.n, "op": op, **kw}) + "\n").encode())
        while b"\n" not in self.b:
            d = self.s.recv(1 << 20)
            if not d:
                raise SystemExit("closed")
            self.b += d
        l, self.b = self.b.split(b"\n", 1)
        r = json.loads(l)
        if not r.get("ok"):
            raise SystemExit(f"{op}: {r}")
        return r


def main():
    c = C(sys.argv[1])
    secs = float(sys.argv[2]) if len(sys.argv) > 2 else 10
    scr = c.call("screen")
    lw, lh = scr["logical"]
    out = {"physical": scr["physical"], "scale": scr["scale"],
           "renderer": scr["renderer"], "load1": os.getloadavg()[0]}
    c.call("launch", app="settings")
    time.sleep(4)
    c.call("launch", app="terminal")
    # let the open animations and first-frame uploads finish, then measure a
    # truly idle desktop (a clock that ticks once a minute, nothing else)
    time.sleep(12)
    c.call("stats", reset=True)
    time.sleep(8)
    out["idle"] = c.call("stats")
    # drag the front window (the terminal) by its title bar, back and forth
    wins = c.call("windows")["windows"]
    front = max(wins, key=lambda w: w["z"])
    x, y, w, h = front["rect"]
    tx, ty = x + w / 2, y + 12
    c.call("stats", reset=True)
    t_end = time.time() + secs
    a, b = (tx, ty), (tx + min(400, lw / 4), ty + min(200, lh / 6))
    n = 0
    while time.time() < t_end:
        c.call("drag", x1=a[0], y1=a[1], x2=b[0], y2=b[1])
        a, b = b, a
        n += 1
    st = c.call("stats")
    st["drags"] = n
    st["cores"] = st["cpu_s"] / st["wall_s"]
    st["cpu_ms_per_frame"] = 1000 * st["cpu_s"] / max(1, st["presents"])
    out["drag"] = st
    out["load1_after"] = os.getloadavg()[0]
    print(json.dumps(out, indent=1))


main()
