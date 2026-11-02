#!/usr/bin/env python3
"""Drive a HEADLESS Starling desktop (`DesktopShellApp --rdp`) — no root.

The sibling of shell-drive.py for desktops that have no display, no seat and
no /dev/uinput. Talks to the operator socket
($XDG_RUNTIME_DIR/starling-operator.sock, mode 0600, same-uid only) and uses
the same action vocabulary, so a script written for one ports to the other.

    build/headless-drive.py [-s SOCKET | -d NAME] <action> [<action> ...]

Actions (each one argv element, like shell-drive.py; coordinates LOGICAL px):

    shot PATH.png        screenshot (needs no RDP client attached)
    click [X Y]  rclick X Y  dblclick X Y  move X Y  down X Y  up X Y
    drag X1 Y1 X2 Y2     scroll X Y DX DY
    key COMBO            enter, ctrl+a, alt+f4 ...     keydown/keyup NAME
    type TEXT            US-ASCII text
    launch APP           launch or focus an app by registry id
    windows              print every window as JSON
    focus|close|minimize|maximize|unmaximize [APP|win=ID]   window management
    winmove [APP|win=ID] X Y     resize [APP|win=ID] W H     (logical px)
    waitwin APP [gone] [SECS]    wait until a window of APP opens (or is gone)
    screen               print size / scale / renderer
    stats [reset]        presents, fps, frame-interval percentiles, CPU seconds
    sleep S
    quit                 stop the desktop

Example:
    build/headless-drive.py launch terminal "sleep 3" "shot /tmp/t.png"

Socket choice: -s PATH, else -d NAME (-> /data/s/amd-desktop/run/NAME/...),
else $STARLING_OPERATOR_SOCK, else $XDG_RUNTIME_DIR/starling-operator.sock.
"""
import json
import os
import socket
import sys
import time


def _isnum(t):
    try:
        float(t)
        return True
    except ValueError:
        return False


class Op:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.connect(path)
        self.buf = b""
        self.n = 0

    def call(self, op, **kw):
        self.n += 1
        self.s.sendall((json.dumps({"id": self.n, "op": op, **kw}) + "\n").encode())
        while b"\n" not in self.buf:
            chunk = self.s.recv(1 << 20)
            if not chunk:
                raise SystemExit("operator socket closed")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        r = json.loads(line)
        if not r.get("ok"):
            raise SystemExit(f"{op}: {r.get('error')}")
        return r


def main(argv):
    path = None
    if argv[:1] == ["-s"]:
        path, argv = argv[1], argv[2:]
    elif argv[:1] == ["-d"]:
        path = f"{os.environ.get('RUN_BASE', '/data/s/amd-desktop/run')}/{argv[1]}/starling-operator.sock"
        argv = argv[2:]
    path = path or os.environ.get("STARLING_OPERATOR_SOCK") or os.path.join(
        os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "starling-operator.sock")
    if not argv:
        print(__doc__)
        return 2
    c = Op(path)
    for a in argv:
        w = a.split(" ", 1)
        verb, rest = w[0], (w[1] if len(w) > 1 else "")
        nums = [float(x) for x in rest.split()] if verb not in ("type", "key", "keydown", "keyup", "launch", "shot", "sleep", "stats", "focus", "close", "minimize", "maximize", "unmaximize", "winmove", "resize", "waitwin") and rest else []
        if verb == "shot":
            r = c.call("shot", path=os.path.abspath(rest))
            print(f"shot {rest}: {r['w']}x{r['h']} {r['bytes']}B total {r['ms']:.0f} ms (frame {r['frame_ms']:.0f} ms)")
        elif verb in ("click", "rclick", "dblclick", "move", "down", "up"):
            kw = {}
            if nums:
                kw = {"x": nums[0], "y": nums[1]}
            op = {"rclick": "click"}.get(verb, verb)
            if verb == "rclick":
                kw["button"] = "right"
            if not kw:
                raise SystemExit(f"{verb} needs X Y on a headless desktop (no cursor to reuse)")
            c.call(op, **kw)
        elif verb == "drag":
            c.call("drag", x1=nums[0], y1=nums[1], x2=nums[2], y2=nums[3])
        elif verb == "scroll":
            c.call("scroll", x=nums[0], y=nums[1], dx=nums[2] if len(nums) > 2 else 0, dy=nums[3] if len(nums) > 3 else 0)
        elif verb in ("key", "keydown", "keyup"):
            c.call(verb, key=rest)
        elif verb == "type":
            c.call("type", text=rest)
        elif verb == "launch":
            c.call("launch", app=rest)
        elif verb in ("focus", "close", "minimize", "maximize", "unmaximize", "winmove", "resize"):
            toks = rest.split()
            kw = {}
            if toks and not _isnum(toks[0]):
                t = toks.pop(0)
                kw["win" if t.startswith("win=") else "app"] = t[4:] if t.startswith("win=") else t
            n = [float(x) for x in toks]
            if verb == "winmove":
                kw.update(x=n[0], y=n[1])
            elif verb == "resize":
                kw.update(w=n[0], h=n[1])
            c.call(verb, **kw)
        elif verb == "waitwin":
            toks = rest.split()
            kw = {"app": toks[0], "state": "gone" if "gone" in toks else "open"}
            tail = [t for t in toks[1:] if _isnum(t)]
            if tail:
                kw["timeout"] = float(tail[0])
            c.call("wait_window", **kw)
        elif verb == "windows":
            print(json.dumps(c.call("windows")["windows"], indent=1))
        elif verb == "screen":
            print(json.dumps(c.call("screen")))
        elif verb == "stats":
            print(json.dumps(c.call("stats", reset=(rest == "reset"))))
        elif verb == "sleep":
            time.sleep(float(rest))
        elif verb == "quit":
            c.call("quit")
        else:
            raise SystemExit(f"unknown action {a!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
