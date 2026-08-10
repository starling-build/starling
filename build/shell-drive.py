#!/usr/bin/env python3
"""Drive DesktopShellApp with scripted input — the shell's UI test harness.

Creates a virtual absolute-position mouse via /dev/uinput (the shell's
libinput picks it up through the host udev in run-shell-gpu.sh dev mode)
and executes a list of actions given as argv. Needs root (sudo) for
/dev/uinput and for signaling the shell.

    sudo tools/shell-drive.py <action> [<action> ...]

Actions (coordinates are LOGICAL px — the shell's own coordinate space —
scaled by FLUTTER_DRM_DPI, default 2.0):

    move X Y               glide the cursor to (X, Y)
    down / up              press / release the left button
    click [X Y]            click (optionally moving there first)
    rclick [X Y]           right-click (optionally moving there first)
    dblclick [X Y]         double-click (optionally moving there first)
    drag X1 Y1 X2 Y2       press at (X1,Y1), glide to (X2,Y2), release
    resize X Y DX DY       grab at (X,Y) and pull by (DX,DY) — put the grab
                           point on a window edge/corner to resize it (the
                           handles extend 6px inside the window bounds)
    key COMBO              press a key chord: enter, backspace, ctrl+a,
                           shift+tab, ... (see KEYCODES below)
    keydown NAME / keyup NAME
                           press / release a single key (for testing holds)
    type TEXT              type ASCII text (US layout; rest of the action
                           string after "type " is typed verbatim)
    dock NAME              move onto a dock icon by app id (launcher,
                           settings, files, terminal, …). The live layout is
                           read from the shell, so transient icons for running
                           apps are accounted for; "dock ?" lists what is on
                           screen right now
    rel DX DY              RELATIVE pointer motion (physical px) — crosses
                           onto other outputs in a multi-monitor layout,
                           which the absolute move/click device cannot
    reldown / relup        press / release the left button on the relative
                           mouse (for drags that cross a monitor seam)
    sleep S                wait S seconds
    shot PATH.png          screenshot -> PNG at PATH (wiggles the cursor
                           to flush the engine's capture-on-next-frame)
    record-start           start engine-side frame recording (SIGRTMIN+1)
    record-stop PATH.mp4   stop recording and assemble the MP4: presented
                           frames carry timestamps, so held frames are
                           duplicated into a constant 30fps timeline

Example — open Settings, move its window, screenshot:

    sudo tools/shell-drive.py dock settings click "sleep 3" \\
        drag 500 79 900 300 "shot /tmp/moved.png"

Dock geometry is NOT mirrored here: `dock NAME` asks the shell for its real
slot centers over the broker socket, so it follows the installed app set and
the transient icons of running apps. Nothing to keep in sync.
"""

import fcntl
import glob
import os
import signal
import struct
import subprocess
import sys
import time

# ── screen geometry: asked for, never assumed ───────────────────────────────
# The absolute pointer device is created against the panel's PHYSICAL size, so
# getting it wrong does not fail loudly — it silently scales every coordinate.
# These used to default to 3840x2160, which was right on the machine this was
# written on and wrong in the 5120x2160 test VM, where every click landed at
# about two thirds of the intended position and the dock checks "failed".
#
# So ask the shell, and fall back to the env/defaults only when it is not
# running (the values are still needed to construct the device).
def _screen_from_shell():
    try:
        import json
        import socket as _socket
        sock = _socket.socket(_socket.AF_UNIX, _socket.SOCK_STREAM)
        sock.settimeout(3)
        sock.connect(broker_socket())
        sock.send(b'{"op":"screen","id":1}\n')
        buf = b""
        while b"\n" not in buf:
            chunk = sock.recv(65536)
            if not chunk:
                return None
            buf += chunk
        sock.close()
        reply = json.loads(buf.split(b"\n", 1)[0])
        if reply.get("ok"):
            return reply["physical"][0], reply["physical"][1], reply["dpi"]
    except (Exception, SystemExit):
        pass
    return None


def _screen():
    if os.environ.get("SHELL_DRIVE_WIDTH"):
        return (int(os.environ["SHELL_DRIVE_WIDTH"]),
                int(os.environ.get("SHELL_DRIVE_HEIGHT", 2160)),
                float(os.environ.get("FLUTTER_DRM_DPI", 2.0)))
    asked = _screen_from_shell()
    if asked:
        return int(asked[0]), int(asked[1]), float(asked[2])
    return 3840, 2160, float(os.environ.get("FLUTTER_DRM_DPI", 2.0))

# ── dock geometry: asked for, never mirrored ────────────────────────────────
# This used to reproduce the dock's layout in Python — icon size, padding,
# margins and a hardcoded app order. It cannot work. The dock is
# centre-aligned and shows a transient icon for every RUNNING app, so
# launching anything shifts every icon left; and the pinned set is the
# catalog's default filtered by what is installed, which varies per machine.
# The stale mirror clicked 122 physical px left of the launcher and did
# nothing, twice reported as "the launcher is broken".
#
# So ask the shell. It serves its real slot centers over the broker socket.


def broker_socket():
    """The shell's broker socket. Under sudo XDG_RUNTIME_DIR is usually the
    caller's, not the session's, so fall back to the dev session dir
    (per-user: /tmp/xdg-starling-<uid>), the invoking user's runtime dir,
    and finally any user's session dir — driving another user's session is
    how the packaged session gets tested.

    Candidates are probed with a real connect(), not os.path.exists: an
    unclean shell death leaves a dead socket file behind, and under sudo
    the user's dir is searched before the root dev session's — a stale
    user-dir socket then shadows the live root one. Twice now that has
    presented as something else entirely (silently warped clicks via the
    3840x2160 screen fallback; dock actions dying with ECONNREFUSED)."""
    import socket as _socket
    candidates = []
    if os.environ.get("XDG_RUNTIME_DIR"):
        candidates.append(os.environ["XDG_RUNTIME_DIR"])
    uid = os.environ.get("SUDO_UID") or str(os.getuid())
    candidates.append(f"/tmp/xdg-starling-{uid}")
    candidates.append(f"/run/user/{uid}")
    candidates += sorted(glob.glob("/tmp/xdg-starling-*"))
    for d in candidates:
        path = os.path.join(d, "starling-agent.sock")
        if not os.path.exists(path):
            continue
        probe = _socket.socket(_socket.AF_UNIX, _socket.SOCK_STREAM)
        probe.settimeout(2)
        try:
            probe.connect(path)
            return path
        except OSError:
            continue
        finally:
            probe.close()
    raise SystemExit(
        "shell-drive: no live starling-agent.sock found (is the shell "
        f"running?) — looked in {', '.join(candidates)}")


def dock_slots():
    """Live dock layout from the shell: [(app, x, y), ...] in logical px."""
    import json
    import socket as _socket
    sock = _socket.socket(_socket.AF_UNIX, _socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect(broker_socket())
    sock.send(b'{"op":"dock_rects","id":1}\n')
    buf = b""
    while b"\n" not in buf:
        chunk = sock.recv(65536)
        if not chunk:
            raise SystemExit("shell-drive: broker closed the connection")
        buf += chunk
    sock.close()
    reply = json.loads(buf.split(b"\n", 1)[0])
    if not reply.get("ok"):
        raise SystemExit(f"shell-drive: dock_rects failed: {reply.get('error')}")
    return [(s["app"], s["x"], s["y"]) for s in reply["slots"]]


def dock_center(name):
    """Logical center of a dock icon, as the dock is laid out right now."""
    slots = dock_slots()
    for app, x, y in slots:
        if app == name:
            return x, y
    have = ", ".join(app for app, _, _ in slots)
    raise SystemExit(f"unknown dock icon '{name}' (on screen right now: {have})")


SCREEN_W_PHYS, SCREEN_H_PHYS, DPI = _screen()
SCREEN_W = SCREEN_W_PHYS / DPI
SCREEN_H = SCREEN_H_PHYS / DPI


# ── uinput virtual mouse ─────────────────────────────────────────────────────
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT = 0x40045564, 0x40045565, 0x40045567
UI_SET_RELBIT = 0x40045566
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
EV_SYN, EV_KEY, EV_REL, EV_ABS = 0x00, 0x01, 0x02, 0x03
BTN_LEFT, BTN_RIGHT, ABS_X, ABS_Y = 0x110, 0x111, 0x00, 0x01
REL_X, REL_Y = 0x00, 0x01
REL_WHEEL, REL_WHEEL_HI_RES = 0x08, 0x0B


class Mouse:
    def __init__(self):
        f = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(f, UI_SET_EVBIT, EV_KEY)
        fcntl.ioctl(f, UI_SET_KEYBIT, BTN_LEFT)
        fcntl.ioctl(f, UI_SET_KEYBIT, BTN_RIGHT)
        fcntl.ioctl(f, UI_SET_EVBIT, EV_ABS)
        fcntl.ioctl(f, UI_SET_ABSBIT, ABS_X)
        fcntl.ioctl(f, UI_SET_ABSBIT, ABS_Y)
        absmax = [0] * 64
        absmax[ABS_X] = SCREEN_W_PHYS - 1
        absmax[ABS_Y] = SCREEN_H_PHYS - 1
        dev = struct.pack("80sHHHHI", b"shell-drive-mouse", 0x03, 0x5347, 0x0001, 1, 0)
        dev += struct.pack("64i", *absmax) + struct.pack("64i", *([0] * 64)) * 3
        os.write(f, dev)
        fcntl.ioctl(f, UI_DEV_CREATE)
        self.f = f
        self.x, self.y = SCREEN_W_PHYS // 2, SCREEN_H_PHYS // 2
        time.sleep(1.5)  # libinput hotplug settle

    def _emit(self, t, c, v):
        os.write(self.f, struct.pack("llHHi", 0, 0, t, c, v))

    def _syn(self):
        self._emit(EV_SYN, 0, 0)

    def move_phys(self, x, y):
        self.x, self.y = int(x), int(y)
        self._emit(EV_ABS, ABS_X, self.x)
        self._emit(EV_ABS, ABS_Y, self.y)
        self._syn()

    def glide(self, x, y, steps=8, dt=0.02):
        """Interpolated motion so hover effects and drags track naturally."""
        x, y = int(x * DPI), int(y * DPI)
        x0, y0 = self.x, self.y
        for i in range(1, steps + 1):
            self.move_phys(x0 + (x - x0) * i / steps, y0 + (y - y0) * i / steps)
            time.sleep(dt)

    def button(self, pressed, btn=BTN_LEFT):
        self._emit(EV_KEY, btn, 1 if pressed else 0)
        self._syn()

    def close(self):
        fcntl.ioctl(self.f, UI_DEV_DESTROY)
        os.close(self.f)


class RelMouse:
    """Relative-motion mouse: the ABS device above maps onto the PRIMARY
    output only, so crossing onto a second monitor (virtual desktop) needs
    relative deltas. Deltas are physical-ish pixels; the engine scales them
    by the output under the pointer."""

    def __init__(self):
        f = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(f, UI_SET_EVBIT, EV_KEY)
        fcntl.ioctl(f, UI_SET_KEYBIT, BTN_LEFT)
        fcntl.ioctl(f, UI_SET_KEYBIT, BTN_RIGHT)
        fcntl.ioctl(f, UI_SET_EVBIT, EV_REL)
        fcntl.ioctl(f, UI_SET_RELBIT, REL_X)
        fcntl.ioctl(f, UI_SET_RELBIT, REL_Y)
        fcntl.ioctl(f, UI_SET_RELBIT, REL_WHEEL)
        fcntl.ioctl(f, UI_SET_RELBIT, REL_WHEEL_HI_RES)
        dev = struct.pack("80sHHHHI", b"shell-drive-relmouse", 0x03, 0x5347, 0x0002, 1, 0)
        dev += struct.pack("64i", *([0] * 64)) * 4
        os.write(f, dev)
        fcntl.ioctl(f, UI_DEV_CREATE)
        self.f = f
        time.sleep(1.5)  # libinput hotplug settle

    def _emit(self, t, c, v):
        os.write(self.f, struct.pack("llHHi", 0, 0, t, c, v))

    def _syn(self):
        self._emit(EV_SYN, 0, 0)

    def rel(self, dx, dy, steps=8, dt=0.02):
        """Relative glide by (dx, dy) physical px in small increments."""
        dx, dy = int(dx), int(dy)
        sx = sy = 0
        for i in range(1, steps + 1):
            tx, ty = dx * i // steps, dy * i // steps
            self._emit(EV_REL, REL_X, tx - sx)
            self._emit(EV_REL, REL_Y, ty - sy)
            self._syn()
            sx, sy = tx, ty
            time.sleep(dt)

    def button(self, pressed, btn=BTN_LEFT):
        self._emit(EV_KEY, btn, 1 if pressed else 0)
        self._syn()

    def wheel(self, notches):
        """Scroll wheel: positive = up (away from user), one event per
        notch with the matching hi-res value for modern libinput."""
        step = 1 if notches > 0 else -1
        for _ in range(abs(int(notches))):
            self._emit(EV_REL, REL_WHEEL, step)
            self._emit(EV_REL, REL_WHEEL_HI_RES, step * 120)
            self._syn()
            time.sleep(0.03)

    def close(self):
        fcntl.ioctl(self.f, UI_DEV_DESTROY)
        os.close(self.f)


# ── uinput virtual keyboard ──────────────────────────────────────────────────
# evdev keycodes (linux/input-event-codes.h)
KEYCODES = {
    "esc": 1, "1": 2, "2": 3, "3": 4, "4": 5, "5": 6, "6": 7, "7": 8,
    "8": 9, "9": 10, "0": 11, "-": 12, "=": 13, "backspace": 14, "tab": 15,
    "q": 16, "w": 17, "e": 18, "r": 19, "t": 20, "y": 21, "u": 22, "i": 23,
    "o": 24, "p": 25, "[": 26, "]": 27, "enter": 28, "ctrl": 29,
    "a": 30, "s": 31, "d": 32, "f": 33, "g": 34, "h": 35, "j": 36, "k": 37,
    "l": 38, ";": 39, "'": 40, "`": 41, "shift": 42, "\\": 43,
    "z": 44, "x": 45, "c": 46, "v": 47, "b": 48, "n": 49, "m": 50,
    ",": 51, ".": 52, "/": 53, "alt": 56, "space": 57,
    "home": 102, "up": 103, "pageup": 104, "left": 105, "right": 106,
    "end": 107, "down": 108, "pagedown": 109, "insert": 110, "delete": 111,
    "meta": 125,
}
# US-layout characters that need shift, mapped to their unshifted key
SHIFTED = {
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7",
    "*": "8", "(": "9", ")": "0", "_": "-", "+": "=", "{": "[", "}": "]",
    ":": ";", '"': "'", "~": "`", "|": "\\", "<": ",", ">": ".", "?": "/",
}


class Keyboard:
    def __init__(self):
        f = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
        fcntl.ioctl(f, UI_SET_EVBIT, EV_KEY)
        for code in KEYCODES.values():
            fcntl.ioctl(f, UI_SET_KEYBIT, code)
        dev = struct.pack("80sHHHHI", b"shell-drive-kbd", 0x03, 0x5347, 0x0002, 1, 0)
        dev += struct.pack("64i", *([0] * 64)) * 4
        os.write(f, dev)
        fcntl.ioctl(f, UI_DEV_CREATE)
        self.f = f
        time.sleep(1.5)  # libinput hotplug settle

    def _emit(self, t, c, v):
        os.write(self.f, struct.pack("llHHi", 0, 0, t, c, v))

    def _key(self, code, pressed):
        self._emit(EV_KEY, code, 1 if pressed else 0)
        self._emit(EV_SYN, 0, 0)

    def combo(self, spec):
        """Press a key chord like 'enter', 'ctrl+a', 'shift+tab'."""
        parts = spec.lower().split("+")
        codes = []
        for p in parts:
            if p not in KEYCODES:
                raise SystemExit(f"unknown key '{p}' (see KEYCODES in shell-drive.py)")
            codes.append(KEYCODES[p])
        for c in codes:
            self._key(c, True)
            time.sleep(0.02)
        for c in reversed(codes):
            self._key(c, False)
            time.sleep(0.02)

    def type_text(self, text):
        """Type ASCII text (US layout), holding shift where needed."""
        for ch in text:
            if ch == " ":
                key, shift = "space", False
            elif ch in SHIFTED:
                key, shift = SHIFTED[ch], True
            elif ch.isupper():
                key, shift = ch.lower(), True
            elif ch in KEYCODES:
                key, shift = ch, False
            else:
                raise SystemExit(f"cannot type character {ch!r}")
            if shift:
                self._key(KEYCODES["shift"], True)
                time.sleep(0.01)
            self._key(KEYCODES[key], True)
            time.sleep(0.02)
            self._key(KEYCODES[key], False)
            if shift:
                time.sleep(0.01)
                self._key(KEYCODES["shift"], False)
            time.sleep(0.03)

    def close(self):
        fcntl.ioctl(self.f, UI_DEV_DESTROY)
        os.close(self.f)


# ── screenshot ───────────────────────────────────────────────────────────────
def shell_pid():
    return int(subprocess.check_output(["pgrep", "-x", "DesktopShellApp"]).split()[0])


def frame_tick(pid):
    """SIGRTMIN+2: the shell dirties an invisible corner pixel, forcing a
    real presented frame (screenshot/record requests are consumed in the
    engine's present callback; an idle scheduled frame never presents)."""
    os.kill(pid, signal.SIGRTMIN + 2)


def shot(mouse, path):
    """SIGUSR1 screenshot -> PNG, flushed with frame ticks."""
    # By mtime, not by name: the shell numbers screenshots from 0 each run,
    # so a leftover from an earlier session has exactly the name the new
    # one will get, and a name-only diff waits on a file that already
    # "exists" — then reports the shell dead while the shot sits on disk.
    before = {p: os.path.getmtime(p)
              for p in glob.glob("/tmp/drm_screenshot_*.ppm")}
    pid = shell_pid()
    os.kill(pid, signal.SIGUSR1)
    deadline = time.time() + 6
    new = None
    while time.time() < deadline and not new:
        frame_tick(pid)
        time.sleep(0.25)
        new = next((p for p in glob.glob("/tmp/drm_screenshot_*.ppm")
                    if os.path.getmtime(p) > before.get(p, 0)), None)
    if not new:
        raise SystemExit("screenshot never appeared — is the shell running?")
    time.sleep(0.3)  # let the 25MB write finish
    with open(path, "wb") as out:
        subprocess.run(["pnmtopng", new], stdout=out, check=True)
    os.remove(new)
    if "SUDO_UID" in os.environ:
        os.chown(path, int(os.environ["SUDO_UID"]), int(os.environ["SUDO_GID"]))
    print(f"[shell-drive] shot -> {path}")


# ── video recording ──────────────────────────────────────────────────────────
RECORD_BIN = "/tmp/drm_record.bin"


def record_toggle(mouse):
    """SIGRTMIN+1 toggles recording; the flag is consumed in the present
    callback, so follow with frame ticks to guarantee one happens."""
    pid = shell_pid()
    os.kill(pid, signal.SIGRTMIN + 1)
    for _ in range(3):
        frame_tick(pid)
        time.sleep(0.15)


def record_stop(mouse, path):
    record_toggle(mouse)
    time.sleep(0.3)
    rw, rh = SCREEN_W_PHYS // 4, SCREEN_H_PHYS // 4
    fsz = rw * rh * 3
    frames = []
    with open(RECORD_BIN, "rb") as f:
        while True:
            hdr = f.read(8)
            if len(hdr) < 8:
                break
            ts = struct.unpack("<Q", hdr)[0]
            px = f.read(fsz)
            if len(px) < fsz:
                break
            frames.append((ts, px))
    if not frames:
        raise SystemExit("no frames recorded — was record-start issued?")
    fps = 30
    ff = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{rw}x{rh}",
         "-r", str(fps), "-i", "-",
         "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "22", path],
        stdin=subprocess.PIPE)
    # Constant-rate timeline: hold the latest presented frame across gaps.
    t, i = frames[0][0], 0
    step = 1_000_000 // fps
    while t <= frames[-1][0]:
        while i + 1 < len(frames) and frames[i + 1][0] <= t:
            i += 1
        ff.stdin.write(frames[i][1])
        t += step
    for _ in range(fps // 2):  # hold the final frame half a second
        ff.stdin.write(frames[-1][1])
    ff.stdin.close()
    ff.wait()
    os.remove(RECORD_BIN)
    if "SUDO_UID" in os.environ:
        os.chown(path, int(os.environ["SUDO_UID"]), int(os.environ["SUDO_GID"]))
    dur = (frames[-1][0] - frames[0][0]) / 1e6
    print(f"[shell-drive] record -> {path} ({len(frames)} presented frames over {dur:.1f}s)")


# ── action runner ────────────────────────────────────────────────────────────
def main():
    actions = sys.argv[1:]
    if not actions:
        print(__doc__)
        return
    m = Mouse()
    kbd = None
    rm = None

    def keyboard():
        nonlocal kbd
        if kbd is None:
            kbd = Keyboard()
        return kbd

    def relmouse():
        nonlocal rm
        if rm is None:
            rm = RelMouse()
        return rm

    try:
        for a in actions:
            p = a.split()
            cmd = p[0]
            if cmd == "move":
                m.glide(float(p[1]), float(p[2]))
            elif cmd == "rel":
                relmouse().rel(float(p[1]), float(p[2]))
            elif cmd == "wheel":
                relmouse().wheel(int(p[1]))
            elif cmd == "reldown":
                relmouse().button(True)
            elif cmd == "relup":
                relmouse().button(False)
            elif cmd == "down":
                m.button(True)
            elif cmd == "up":
                m.button(False)
            elif cmd == "click":
                if len(p) == 3:
                    m.glide(float(p[1]), float(p[2]))
                    time.sleep(0.15)
                m.button(True)
                time.sleep(0.08)
                m.button(False)
            elif cmd == "rclick":
                if len(p) == 3:
                    m.glide(float(p[1]), float(p[2]))
                    time.sleep(0.15)
                m.button(True, BTN_RIGHT)
                time.sleep(0.08)
                m.button(False, BTN_RIGHT)
            elif cmd == "dblclick":
                if len(p) == 3:
                    m.glide(float(p[1]), float(p[2]))
                    time.sleep(0.15)
                for _ in range(2):
                    m.button(True)
                    time.sleep(0.06)
                    m.button(False)
                    time.sleep(0.08)
            elif cmd in ("drag", "resize"):
                x1, y1 = float(p[1]), float(p[2])
                if cmd == "resize":  # p[3:] is a delta from the grab point
                    x2, y2 = x1 + float(p[3]), y1 + float(p[4])
                else:
                    x2, y2 = float(p[3]), float(p[4])
                m.glide(x1, y1)
                time.sleep(0.15)
                m.button(True)
                time.sleep(0.1)
                m.glide(x2, y2, steps=16, dt=0.03)
                time.sleep(0.1)
                m.button(False)
            elif cmd == "key":
                keyboard().combo(p[1])
            elif cmd == "keydown":
                keyboard()._key(KEYCODES[p[1]], True)
            elif cmd == "keyup":
                keyboard()._key(KEYCODES[p[1]], False)
            elif cmd == "type":
                keyboard().type_text(a[len("type "):])
            elif cmd == "dock":
                if p[1] == "?":
                    for app, x, y in dock_slots():
                        print(f"[shell-drive] dock {app:<12} {x:7.1f} {y:7.1f}")
                    continue
                x, y = dock_center(p[1])
                m.glide(x, y)
            elif cmd == "sleep":
                time.sleep(float(p[1]))
            elif cmd == "shot":
                shot(m, p[1])
            elif cmd == "record-start":
                record_toggle(m)
            elif cmd == "record-stop":
                record_stop(m, p[1])
            else:
                raise SystemExit(f"unknown action '{a}'")
            print(f"[shell-drive] {a}", flush=True)
            time.sleep(0.05)
    finally:
        if kbd is not None:
            kbd.close()
        if rm is not None:
            rm.close()
        m.close()


if __name__ == "__main__":
    main()
