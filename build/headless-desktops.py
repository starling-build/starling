#!/usr/bin/env python3
"""Start, list and stop several HEADLESS Starling desktops on one machine.

    build/headless-desktops.py start NAME [--size 1920x1080] [--scale 1] [--threads 2]
    build/headless-desktops.py start-n N [--prefix d] ...      # d1 .. dN
    build/headless-desktops.py list
    build/headless-desktops.py socket NAME                     # print its operator socket
    build/headless-desktops.py stop NAME [NAME ...]
    build/headless-desktops.py stop-all

As a library:

    sys.path.insert(0, "build"); import importlib
    hd = importlib.import_module("headless-desktops")
    d = hd.start("agent1"); d.drive("launch terminal", "shot /tmp/a.png"); hd.stop("agent1")

Every desktop is a separate `DesktopShellApp --rdp` process in its own session
with its OWN runtime directory (mode 0700) holding its operator socket (mode
0600, same-uid only — see docs/plans/headless-desktop.md). No RDP listener,
no display, no root. Run from a staged tree (build/stage.sh): STARLING_STAGE,
else <repo>/.stage.

stop is a clean shutdown: ask the shell to quit over its socket, then SIGTERM,
then SIGKILL the desktop's whole process group — apps it launched included —
and finally verify nothing in that runtime dir's environment is still alive.
"""
import argparse
import json
import os
import signal
import socket
import subprocess
import sys
import time

REPO = os.path.realpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


def base_dir():
    """Where desktops live: $STARLING_HEADLESS_BASE, else a private 0700 dir."""
    b = os.environ.get("STARLING_HEADLESS_BASE")
    if not b:
        xr = os.environ.get("XDG_RUNTIME_DIR")
        b = os.path.join(xr, "starling-headless") if xr and os.path.isdir(xr) \
            else f"/tmp/starling-headless-{os.getuid()}"
    os.makedirs(b, mode=0o700, exist_ok=True)
    st = os.stat(b)
    if st.st_uid != os.getuid() or st.st_mode & 0o077:
        os.chmod(b, 0o700) if st.st_uid == os.getuid() else sys.exit(f"{b} is not ours")
    return b


def _marker(rundir):
    return f"XDG_RUNTIME_DIR={rundir}".encode()


def members(rundir):
    """PIDs of every process of ours whose environment points at rundir."""
    want, me, out = _marker(rundir), os.getuid(), []
    for p in os.listdir("/proc"):
        if not p.isdigit():
            continue
        try:
            if os.stat(f"/proc/{p}").st_uid != me:
                continue
            with open(f"/proc/{p}/environ", "rb") as f:
                if want in f.read().split(b"\0"):
                    out.append(int(p))
        except OSError:
            pass
    return out


class Desktop:
    def __init__(self, name, base=None):
        self.name = name
        self.rundir = os.path.join(base or base_dir(), name)
        self.sock = os.path.join(self.rundir, "starling-operator.sock")
        self.pidfile = os.path.join(self.rundir, "shell.pid")

    @property
    def pid(self):
        try:
            return int(open(self.pidfile).read())
        except (OSError, ValueError):
            return None

    def alive(self):
        p = self.pid
        if not p:
            return False
        try:
            os.kill(p, 0)
            return True
        except OSError:
            return False

    def call(self, op, **kw):
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(30)
        s.connect(self.sock)
        s.sendall((json.dumps({"id": 1, "op": op, **kw}) + "\n").encode())
        buf = b""
        while b"\n" not in buf:
            d = s.recv(1 << 20)
            if not d:
                break
            buf += d
        s.close()
        return json.loads(buf.split(b"\n", 1)[0])

    def drive(self, *actions):
        """Run headless-drive.py actions against this desktop."""
        return subprocess.run([sys.executable, os.path.join(REPO, "build", "headless-drive.py"),
                               "-s", self.sock, *actions], check=True,
                              capture_output=True, text=True).stdout


def start(name, size="1920x1080", scale="1", threads=2, stage=None, timeout=60):
    stage = stage or os.environ.get("STARLING_STAGE") or os.path.join(REPO, ".stage")
    shell = os.path.join(stage, "lib", "DesktopShellApp")
    if not os.access(shell, os.X_OK):
        sys.exit(f"no staged tree at {stage} (run build/stage.sh)")
    d = Desktop(name)
    if d.alive():
        sys.exit(f"{name} is already running (pid {d.pid})")
    if os.path.isdir(d.rundir):
        for f in os.listdir(d.rundir):               # stale socket / pidfile from a dead run
            try:
                os.unlink(os.path.join(d.rundir, f))
            except OSError:
                pass
    os.makedirs(d.rundir, mode=0o700, exist_ok=True)
    os.chmod(d.rundir, 0o700)
    env = {k: v for k, v in os.environ.items() if k not in ("DISPLAY", "WAYLAND_DISPLAY")}
    env.update(
        LD_LIBRARY_PATH=os.path.join(stage, "lib"),
        XDG_RUNTIME_DIR=d.rundir,
        FLUTTER_ENGINE_OUT=os.path.join(stage, "share"),
        STARLING_DATA_DIR=os.path.join(stage, "share"),
        FLUTTER_APPS_DIR=os.path.join(stage, "lib", "apps"),
        STARLING_CHILD_HOST_GL="1",
        STARLING_APP_RUN=os.path.join(stage, "bin", "app-run"),
        STARLING_RDP_SIZE=size, STARLING_RDP_SCALE=str(scale),
        STARLING_HEADLESS_NO_RDP="1", LP_NUM_THREADS=str(threads),
    )
    log = open(os.path.join(d.rundir, "shell.log"), "wb")
    p = subprocess.Popen([shell, "--rdp"], cwd=os.path.join(stage, "lib"), env=env,
                         stdout=log, stderr=log, stdin=subprocess.DEVNULL,
                         start_new_session=True)       # own session: one group to stop
    open(d.pidfile, "w").write(str(p.pid))
    end = time.time() + timeout
    while time.time() < end:
        if p.poll() is not None:
            sys.exit(f"{name}: shell exited ({p.returncode}); see {d.rundir}/shell.log")
        if os.path.exists(d.sock):
            try:
                if d.call("hello").get("ok"):
                    return d
            except OSError:
                pass
        time.sleep(0.1)
    stop(name)
    sys.exit(f"{name}: no operator socket after {timeout}s")


def stop(name, grace=5.0):
    """Clean shutdown. Returns the list of PIDs that had to be killed (empty = clean)."""
    d = Desktop(name)
    pid = d.pid
    killed = []
    if pid and d.alive():
        try:
            d.call("quit")
        except (OSError, ValueError):
            pass
        for sig, wait in ((None, grace), (signal.SIGTERM, grace), (signal.SIGKILL, 2.0)):
            if sig is not None:
                try:
                    os.killpg(pid, sig)               # the desktop's own session/group
                except OSError:
                    pass
            end = time.time() + wait
            while time.time() < end and (d.alive() or _group_alive(pid)):
                time.sleep(0.1)
            if not (d.alive() or _group_alive(pid)):
                break
    # anything of ours still carrying this runtime dir (a child that left the group)
    for _ in range(20):
        left = members(d.rundir)
        if not left:
            break
        for p in left:
            if p != os.getpid():
                try:
                    killed.append(f"{p}:{open(f'/proc/{p}/comm').read().strip()}")
                except OSError:
                    killed.append(str(p))
                try:
                    os.kill(p, signal.SIGKILL)
                except OSError:
                    pass
        time.sleep(0.1)
    for f in ("starling-operator.sock", "shell.pid"):
        try:
            os.unlink(os.path.join(d.rundir, f))
        except OSError:
            pass
    return killed


def _group_alive(pgid):
    try:
        os.killpg(pgid, 0)
        return True
    except OSError:
        return False


def names():
    b = base_dir()
    return sorted(n for n in os.listdir(b) if os.path.isdir(os.path.join(b, n)))


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for c in ("start", "start-n"):
        p = sub.add_parser(c)
        p.add_argument("name" if c == "start" else "n")
        p.add_argument("--size", default="1920x1080")
        p.add_argument("--scale", default="1")
        p.add_argument("--threads", type=int, default=2)
        if c == "start-n":
            p.add_argument("--prefix", default="d")
    sub.add_parser("list")
    sub.add_parser("stop-all")
    p = sub.add_parser("socket"); p.add_argument("name")
    p = sub.add_parser("stop"); p.add_argument("names", nargs="+")
    a = ap.parse_args(argv)
    if a.cmd == "start":
        d = start(a.name, a.size, a.scale, a.threads)
        print(d.sock)
    elif a.cmd == "start-n":
        for i in range(1, int(a.n) + 1):
            print(start(f"{a.prefix}{i}", a.size, a.scale, a.threads).sock, flush=True)
    elif a.cmd == "list":
        for n in names():
            d = Desktop(n)
            print(f"{n}\t{'running' if d.alive() else 'stopped'}\tpid={d.pid}\t{d.sock}")
    elif a.cmd == "socket":
        print(Desktop(a.name).sock)
    elif a.cmd in ("stop", "stop-all"):
        for n in (a.names if a.cmd == "stop" else [n for n in names() if Desktop(n).alive()]):
            k = stop(n)
            print(f"{n}: stopped" + (f" (had to kill {len(k)} straggler(s): {k})" if k else " cleanly"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
