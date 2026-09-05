#!/usr/bin/env python3
"""Functional tests against a running Starling desktop.

    test/functional.py [-v] [--only NAME]

Needs a shell already running (build/run-desktop.sh) and root for the input
device — run it with sudo.

Everything is asserted against **structured state from the broker socket**,
never against pixels. `list_apps` is what the launcher would show, `dock_rects`
is the dock as laid out right now, and both report liveness the shell itself
maintains. A screenshot suite over a compositor rots faster than it catches
anything: every theme tweak, font change and animation invalidates it, and the
usual response is to re-bless the baseline, at which point it tests nothing.
Screenshots here are artifacts for a human, not assertions.

One check reads pixels — `terminal: the glyphs paint, and on the grid`. What
that rule is really against is a stored BASELINE, and there is none: the
terminal paints its own ruler and the check relates two measurements inside a
single frame (see test/glyph-pixels.py). It is here because the thing it
watches — whether a cell drew anything, and in the right column — is invisible
to structured state by construction. The grid was correct in all four of the
rendering failures that have shipped from this tree.

What is deliberately NOT covered, because a dev shell cannot: the App Store's
pkexec hop. polkit authorises the seat-active session, and a shell launched
over SSH is not it, so Install/Remove from the store UI can only be exercised
in a real session (the VM tier). The CLI path those buttons invoke is covered
here.
"""

import base64
import contextlib
import glob
import json
import os
import pwd
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# These checks run in two places: against a staged dev tree on the build box,
# and against an installed .deb inside the VM, where there is no repo at all.
# Resolve everything from whichever layout is present rather than assuming.
def _first(*candidates: Path) -> Path | None:
    for c in candidates:
        if c.exists():
            return c
    return None


APP_RUN = _first(REPO / ".stage/bin/app-run", Path("/usr/bin/app-run"))
APP_INSTALL = _first(REPO / ".stage/bin/app-install", Path("/usr/bin/app-install"))
SHELL_DRIVE = _first(REPO / "build/shell-drive.py",
                     Path(__file__).resolve().parent / "shell-drive.py")
CATALOG = _first(REPO / "registry/catalog.d",
                 Path(os.environ.get("STARLING_CATALOG_DIR", "/nonexistent")),
                 Path("/usr/share/starling/catalog.d"))

VERBOSE = "-v" in sys.argv
ONLY = None
if "--only" in sys.argv:
    ONLY = sys.argv[sys.argv.index("--only") + 1]

# The real third-party app the install/identity/remove chain runs against.
# GIMP because it is a plain Ubuntu-archive package (no vendor repo, no
# account) whose window carries an app_id and a title that names a document
# rather than the app — the case app_id matching exists for.
REAL_APP = "gimp"

# A fake app for the offline install/remove check: no download, no vendor, no
# network, and nothing on the machine to damage. It covers the part we own —
# that a record appearing and disappearing moves the launcher and the dock —
# on machines where the real install above is switched off.
FAKE_ID = "starlingselftest"
FAKE_ROOT = Path("/tmp/starling-selftest")
FAKE_BIN = FAKE_ROOT / "bin" / "sleep"   # keeps the name: see the fixture

class Skip(Exception):
    """A check whose prerequisite is absent on this machine.

    Reported as SKIP, not FAIL. A check that needs GIMP installed says nothing
    about the desktop on a machine without GIMP, and a gate that goes red for
    that gets ignored — but silence would be worse, so skips are printed and
    counted.
    """


results: list[tuple[str, str, str]] = []


def log(msg: str) -> None:
    if VERBOSE:
        print(f"      {msg}")


# ── broker ───────────────────────────────────────────────────────────────────

def broker_path() -> str:
    uid = os.environ.get("SUDO_UID", os.getuid())
    for d in (os.environ.get("XDG_RUNTIME_DIR"), f"/tmp/xdg-starling-{uid}",
              f"/run/user/{uid}", *sorted(glob.glob("/tmp/xdg-starling-*"))):
        if d and os.path.exists(os.path.join(d, "starling-agent.sock")):
            return os.path.join(d, "starling-agent.sock")
    sys.exit("no starling-agent.sock — is the shell running?")


def ask(op: str, timeout: float = 5.0, **fields) -> dict:
    """One request/response against the broker."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(timeout)
    sock.connect(broker_path())
    sock.send(json.dumps(dict(fields, op=op, id=1)).encode() + b"\n")
    buf = b""
    while b"\n" not in buf:
        chunk = sock.recv(65536)
        if not chunk:
            raise AssertionError(f"broker closed during {op}")
        buf += chunk
    sock.close()
    reply = json.loads(buf.split(b"\n", 1)[0])
    if not reply.get("ok"):
        raise AssertionError(f"{op} failed: {reply.get('error')}")
    return reply




class Session:
    """A stateful broker connection, for ops that need an agent identity.

    `ask()` above opens a connection per request, which is fine for the
    unscoped read-only ops but useless for anything agent-scoped: `hello`
    registers on the connection, so a one-shot request is always anonymous.
    """

    def __init__(self, name="functional.py", agent=None, token=None):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(30.0)
        self.sock.connect(broker_path())
        self.f = self.sock.makefile("rwb")
        self._id = 0
        args = {"name": name}
        if agent and token:
            args.update(agent=agent, token=token)
        hello = self.call("hello", **args)
        self.agent_id = hello["agent"]
        self.token = hello["token"]
        # What the broker says this agent may launch and see. Derived from the
        # registry now rather than a table, which is the thing worth checking.
        self.hello_scope = hello.get("scope", {})

    def call(self, op, **args):
        self._id += 1
        req = {"id": self._id, "op": op}
        req.update(args)
        self.f.write((json.dumps(req) + "\n").encode())
        self.f.flush()
        while True:
            line = self.f.readline()
            if not line:
                raise AssertionError("broker closed the connection")
            msg = json.loads(line)
            if msg.get("id") != self._id:
                continue
            return msg

    def ok(self, op, **args):
        reply = self.call(op, **args)
        assert reply.get("ok"), f"{op} failed: {reply.get('error')}"
        return reply

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def session_busctl(*args: str) -> str:
    """busctl against the session's own bus, as the session user — a session
    bus refuses other uids, and the tier runs as root."""
    bus = os.path.dirname(broker_path()) + "/bus"
    cmd = ["busctl", f"--address=unix:path={bus}"] + list(args)
    user = os.environ.get("SUDO_USER")
    if os.geteuid() == 0 and user:
        cmd = ["sudo", "-u", user] + cmd
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    assert r.returncode == 0, f"busctl {args[0]} failed: {r.stderr.strip()}"
    return r.stdout.strip()


def proc_running(name: str) -> bool:
    """pgrep -x, for first-party apps. The registry's `process` flag matches
    /proc exe paths against records' Bins= — and first-party records have
    none (they are not store-removable, which is what that flag guards), so
    it reads False for them even while they run."""
    return subprocess.run(["pgrep", "-x", name],
                          capture_output=True).returncode == 0


def wayland_display() -> str:
    """The socket name the RUNNING shell listens on.

    Not always wayland-0: a shell that died uncleanly leaves a
    wayland-0.lock behind and the next run takes wayland-1, so a client
    that assumes wayland-0 talks to nothing. The newest socket in the
    runtime dir is the current run's, which is what a client needs.
    """
    rt = os.path.dirname(broker_path())
    socks = [p for p in glob.glob(os.path.join(rt, "wayland-*"))
             if not p.endswith(".lock")]
    if not socks:
        raise Skip("no wayland socket in the session runtime dir")
    return os.path.basename(max(socks, key=lambda p: os.stat(p).st_mtime))


def session_home() -> str:
    """The session user's home — where the shell persists its config."""
    user = os.environ.get("SUDO_USER")
    if user and os.geteuid() == 0:
        return pwd.getpwnam(user).pw_dir
    return os.path.expanduser("~")


# ── driving Settings' panes ──────────────────────────────────────────────────
#
# Checks that need a Settings control use an agent-owned window and its
# semantic tree — the same tree the agent tooling ships on, so a control
# that stops being reachable there is itself a finding. The window lives in
# the agent space, invisible on the user desktop: these checks assert state
# changes, never pixels.

def settings_window() -> tuple:
    s = Session(name="pane-driver")
    win = s.ok("launch", app="settings")["win"]
    wait_for(lambda: len(tree_nodes(s, win)) > 5, "Settings UI to build")
    return s, win


def tree_nodes(s, win) -> list:
    r = s.call("semantic_tree", win=win)
    return r.get("nodes", []) if r.get("ok") else []


def tap_node_for(nodes: list, label: str):
    """The first tappable node at-or-after the node whose label starts with
    `label`. A nav item or row is tappable itself; a switch's tap node is
    unlabeled and follows its row's text."""
    seen = False
    for n in nodes:
        node_label = n.get("label") or ""
        if not seen and node_label.startswith(label):
            seen = True
            if "tap" in (n.get("actions") or []):
                return n.get("node")
            continue
        if seen and "tap" in (n.get("actions") or []):
            return n.get("node")
    return None


def tap_label(s, win, label: str) -> None:
    nid = tap_node_for(tree_nodes(s, win), label)
    assert nid is not None, f"no tappable node for {label!r} in the tree"
    s.ok("perform_action", win=win, node=nid, action="tap")
    time.sleep(1)


def apps() -> dict[str, dict]:
    return {a["app"]: a for a in ask("list_apps")["apps"]}


def dock() -> list[str]:
    return [s["app"] for s in ask("dock_rects")["slots"]]


def png_dims(b64: str) -> tuple:
    """(width, height) from a base64 PNG's IHDR, and it validates the magic —
    enough to prove a capture returned a real image without a decoder here."""
    import struct
    data = base64.b64decode(b64)
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    return struct.unpack(">II", data[16:24])


def wait_for(predicate, what: str, timeout: float = 25.0) -> None:
    """Poll until the shell reports what we expect.

    Generous, because the wait is for a real app to start, map a window and
    composite a frame — and because the shell's own liveness tick is 2s.
    """
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            last = predicate()
            if last:
                return
        except AssertionError:
            raise
        time.sleep(0.5)
    raise AssertionError(f"timed out after {timeout:g}s waiting for {what}")


# ── helpers ──────────────────────────────────────────────────────────────────

def drive(*actions: str) -> None:
    subprocess.run([sys.executable, str(SHELL_DRIVE), *actions],
                   check=True, capture_output=True)


def app_run(app_id: str) -> subprocess.Popen:
    # The tier runs as root while the session belongs to $SUDO_USER, and the
    # runtime dir is per-user — app-run's own default would resolve to root's
    # dir, not the session's. The shell passes STARLING_XDG_DIR to every child
    # it spawns; do the same, aimed at the session actually under test.
    env = dict(os.environ, STARLING_XDG_DIR=os.path.dirname(broker_path()))
    return subprocess.Popen([str(APP_RUN), app_id], env=env,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def quit_app(*names: str) -> None:
    """Ask, then insist. SIGTERM alone is not enough: GIMP 3.2 CATCHES it
    (SigCgt carries 0x4000) and keeps running, which left it owning the
    screen for every later check — the removal check refused, the dock
    click for the next app landed on GIMP's window, and the recording
    check filmed a still GIMP instead of a scrolling terminal. Five
    failures, one surviving process. Escalate rather than assume."""
    for name in names:
        subprocess.run(["pkill", "-x", name], capture_output=True)
    deadline = time.time() + 8
    while time.time() < deadline:
        if not any(subprocess.run(["pgrep", "-x", n], capture_output=True).returncode == 0
                   for n in names):
            return
        time.sleep(0.25)
    for name in names:
        subprocess.run(["pkill", "-KILL", "-x", name], capture_output=True)


def check(name: str):
    """Decorator registering one check."""
    def wrap(fn):
        fn._check_name = name
        return fn
    return wrap


# ── checks ───────────────────────────────────────────────────────────────────

@check("registry: the shell agrees with catalog.d on disk")
def check_registry_matches_disk() -> None:
    on_disk = {p.stem for p in CATALOG.glob("*.app")}
    reported = set(apps())
    missing = on_disk - reported
    assert not missing, f"shell does not know about {sorted(missing)}"
    log(f"{len(reported)} apps known to the shell")


@check("dock: pinned slots are the installed Dock= apps, in order")
def check_dock_matches_catalog() -> None:
    known = apps()
    expected = [a["app"] for a in
                sorted((a for a in known.values()
                        if a["dock"] >= 0 and a["installed"]),
                       key=lambda a: a["dock"])]
    slots = dock()
    assert slots[0] == "launcher", f"slot 0 is {slots[0]!r}, expected launcher"
    pinned = slots[1:1 + len(expected)]
    assert pinned == expected, f"dock pinned {pinned}, catalog says {expected}"
    log(f"dock: {slots}")


@check("store: installing a real app through app-install lands it in the launcher")
def check_real_install() -> None:
    """Install a real third-party app the way the App Store does.

    This is deliberately not setup done behind the tests' back. Installing an
    app is one of the behaviours under test, so the app the identity checks
    need is *produced* by this check rather than assumed — earlier this ran
    `apt-get install gimp` followed by `app-install --record gimp`, which
    fabricated the end state with the repair tool and exercised none of the
    real path.

    `/usr/bin/app-install <id>` is exactly the subprocess the store's Install
    button runs; the store adds `pkexec` in front of it. That hop cannot be
    driven from an SSH shell — polkit authorises the seat-active session — so
    it is proved separately by the pkcheck step in test/vm.sh, which asks
    polkit the same question on behalf of the session's own shell.

    Off by default: it downloads a real package. test/vm.sh turns it on.
    """
    if os.environ.get("STARLING_TEST_INSTALL") != "1":
        raise Skip("set STARLING_TEST_INSTALL=1 to install a real app")
    if apps().get(REAL_APP, {}).get("installed"):
        raise Skip(f"{REAL_APP} is already installed")

    result = subprocess.run(["sudo", str(APP_INSTALL), REAL_APP],
                            capture_output=True, text=True, timeout=900)
    assert result.returncode == 0, \
        f"app-install {REAL_APP} failed: {result.stderr.strip()[-200:]}"
    # The record is what tells the desktop it happened, and it must carry the
    # host facts resolved at install time — not just exist.
    wait_for(lambda: apps()[REAL_APP]["installed"],
             f"the shell to show {REAL_APP} as installed")
    records = Path(os.environ.get("STARLING_APP_RECORDS",
                                  "/var/lib/starling/installed.d"))
    record = (records / f"{REAL_APP}.app").read_text()
    assert "WmClass=" in record, f"no WmClass recorded:\n{record}"
    log(record.strip().replace("\n", " | "))


@check("identity: a third-party window resolves to its app via app_id")
def check_third_party_identity() -> None:
    """The bug this whole design exists for. GIMP declares no TitleMatch, so
    the only way the shell can attribute its window is the app_id it reports
    matching the StartupWMClass app-install recorded."""
    if not apps().get(REAL_APP, {}).get("installed"):
        raise Skip(f"{REAL_APP} is not installed")
    before = apps()[REAL_APP]
    assert not before["process"] and not before["window"], \
        "gimp is already running; quit it first"
    assert "gimp" not in dock(), "gimp already has a dock icon"

    app_run("gimp")
    try:
        wait_for(lambda: apps()["gimp"]["process"], "gimp process")
        log("process seen")
        wait_for(lambda: apps()["gimp"]["window"], "gimp window")
        log("window attributed to gimp")
        wait_for(lambda: "gimp" in dock(), "gimp transient dock icon")
        log(f"dock: {dock()}")
    finally:
        quit_app("gimp", "gimp-3.2")
    wait_for(lambda: "gimp" not in dock(), "gimp icon to go away")
    wait_for(lambda: not apps()["gimp"]["window"], "gimp window to go away")
    # And for the process itself. quit_app only signals, and the window and
    # dock icon both clear the moment the surface goes — while GIMP is still
    # tearing down. The removal check below requires it gone, so leaving that
    # to luck makes this a timing race between two checks: it survived only
    # while the desktop was small enough for GIMP to exit quickly.
    wait_for(lambda: not apps()["gimp"]["process"], "gimp process to exit")


@check("identity: a window is NOT attributed to an app that merely shares its binary")
def check_identity_is_not_incidental() -> None:
    """Keeps the check above honest.

    "GIMP's window was attributed to gimp" would also pass if the shell simply
    credited any window to any running app. The decoy fixture shares GIMP's
    binary but declares a window class that matches nothing, so while GIMP runs
    the shell must report the decoy as process=true, window=false. If that
    window ever turns true, attribution has stopped being app_id-driven.
    """
    decoy = apps().get("starlingnotgimp")
    if decoy is None:
        raise Skip("decoy fixture not present")
    if not apps().get("gimp", {}).get("installed"):
        raise Skip("gimp is not installed")
    assert not apps()["gimp"]["process"], "gimp is already running; quit it first"

    app_run("gimp")
    try:
        wait_for(lambda: apps()["gimp"]["window"], "gimp window")
        state = apps()["starlingnotgimp"]
        assert state["process"], (
            "decoy should be seen as running — it shares GIMP's binary, so a "
            "false here means the process check stopped working")
        assert not state["window"], (
            "decoy was credited with GIMP's window: attribution is no longer "
            "driven by app_id")
        log("decoy: process=True window=False — attribution is app_id-driven")
    finally:
        quit_app("gimp", "gimp-3.2")
    wait_for(lambda: not apps()["gimp"]["process"], "gimp to exit")


def _reinstall_and_launch(app_id: str, query: str, *procs: str,
                          purge: str = "") -> None:
    """Remove the app, install it for real, then launch it THROUGH THE SHELL.

    The launch half is the point, and it must go through the Launchpad rather
    than `app_run()`. Chrome and VS Code both segfaulted on launch from a real
    GDM session while every other signal looked perfect: app-install returned
    0, the record carried a correct WmClass, the launcher tile appeared, and
    the process even started — it just died in ~2.4s without ever mapping a
    window. app-run was passing GDM's GNOME_DESKTOP_SESSION_ID through, and
    Chromium reads that as proof of a GNOME session whatever
    XDG_CURRENT_DESKTOP says.

    Nothing that launches app-run from a shell can see it: this tier's
    environment has no GNOME_DESKTOP_SESSION_ID, and app-run's root branch
    starts from `env -i`. Only the shell's own spawn carries the variable, so
    only a launch driven through the desktop reproduces it.

    Removing first is deliberate: the install is under test, so a machine that
    happens to have the app already must exercise it rather than skip it.
    """
    if os.environ.get("STARLING_TEST_INSTALL") != "1":
        raise Skip("set STARLING_TEST_INSTALL=1 to install a real app")

    quit_app(*procs)
    records = Path(os.environ.get("STARLING_APP_RECORDS",
                                  "/var/lib/starling/installed.d"))

    if apps().get(app_id, {}).get("installed"):
        removed = subprocess.run(["sudo", str(APP_INSTALL), "--remove", app_id],
                                 capture_output=True, text=True, timeout=900)
        assert removed.returncode == 0, \
            f"app-install --remove {app_id} failed: {removed.stderr.strip()[-200:]}"
        wait_for(lambda: not apps()[app_id]["installed"],
                 f"the shell to drop {app_id}")
        log("removed first, so the install below is a real one")
    # A leftover profile is not part of a fresh install, and for VS Code it
    # decides what the launch even does (with one, it restores a window).
    if purge:
        subprocess.run(f"rm -rf {purge}", shell=True, capture_output=True)

    installed = subprocess.run(["sudo", str(APP_INSTALL), app_id],
                               capture_output=True, text=True, timeout=1800)
    assert installed.returncode == 0, \
        f"app-install {app_id} failed: {installed.stderr.strip()[-300:]}"
    wait_for(lambda: apps()[app_id]["installed"],
             f"the shell to show {app_id} installed", timeout=40)
    record = (records / f"{app_id}.app").read_text()
    assert "WmClass=" in record, f"no WmClass recorded:\n{record}"
    log(record.strip().replace("\n", " | "))

    drive("move 300 300", "dock launcher", "click")
    try:
        wait_for(lambda: ask("launcher_state")["open"], "Launchpad to open")
        drive(f"type {query}")
        wait_for(lambda: ask("launcher_state")["filtered"] == [app_id],
                 f"the Launchpad to filter to exactly {app_id}")
        drive("key enter")
        wait_for(lambda: apps()[app_id]["process"], f"{app_id} process",
                 timeout=60)
        log("process started")
        # The window, not the process, is the assertion that matters: the
        # segfault above left a process alive for seconds and mapped nothing.
        wait_for(lambda: apps()[app_id]["window"], f"{app_id} window",
                 timeout=90)
        log("window mapped and attributed to the app via app_id")
    finally:
        drive("key esc")
        quit_app(*procs)


@check("store: Chrome installs from scratch and launches from the Launchpad")
def check_chrome_install_launch() -> None:
    _reinstall_and_launch("chrome", "chrome", "chrome")


@check("store: VS Code installs from scratch and launches from the Launchpad")
def check_vscode_install_launch() -> None:
    _reinstall_and_launch("vscode", "code", "code",
                          purge="/tmp/vscode_wayland-*")


@check("launch: clicking a dock icon starts a first-party app")
def check_dock_launch() -> None:
    """Also covers dock geometry end to end: `dock settings` resolves the slot
    from the live layout, so a wrong answer clicks the wrong app or nothing."""
    assert not apps()["settings"]["window"], "Settings already running"
    drive("move 300 300", "dock settings", "click")
    try:
        wait_for(lambda: apps()["settings"]["window"], "Settings window")
        log("Settings launched from its dock icon")
    finally:
        quit_app("SettingsApp")
    wait_for(lambda: not apps()["settings"]["window"], "Settings to close")


@check("guest: a VM console opens from the launcher, once per domain")
def check_guest_display() -> None:
    """M1 — docs/plans/guest-display.md. A VM console is a texture-backed
    window like any other, so the interesting claims are the ones that are NOT
    like any other window: it comes from a registry record with no process
    behind it, a second launch must not take the display away from the first
    (QEMU allows exactly one control client per domain), and closing the
    window detaches instead of shutting the guest down.

    Driven through the launcher's search rather than by clicking a tile,
    because the tile's position moves with the installed app set — and because
    typing the name is what a person does. Skipped wherever there is no
    domain, which is every machine except one with libvirt and a prepared
    guest.
    """
    domain = os.environ.get("STARLING_GUEST_DOMAIN") or "windows"
    if "windows" not in apps():
        raise Skip("no windows.app in the catalog")

    def domstate() -> str:
        try:
            r = subprocess.run(["virsh", "-c", "qemu:///system", "domstate",
                                domain], capture_output=True, text=True)
        except OSError:
            return ""      # no libvirt on this machine at all
        return r.stdout.strip() if r.returncode == 0 else ""

    if not domstate():
        raise Skip(f"no libvirt domain {domain!r}")
    before = domstate()

    # The record is searchable, which is the launcher half of "apps are data".
    drive("move 300 300", "dock launcher", "click", "sleep 1", "type windows")
    state = ask("launcher_state")
    assert state.get("query", "").lower() == "windows", \
        f"the launcher did not take the query: {state!r}"
    assert "windows" in state.get("filtered", []), \
        f"windows.app did not survive its own name as a filter: {state!r}"

    drive("key enter")
    try:
        # Generous: a shut-off domain is started first, and Windows takes its
        # time before it scans out anything at all.
        wait_for(lambda: apps()["windows"]["window"], "the guest window",
                 timeout=120.0)
        assert domstate() == "running", \
            f"the window opened but the domain is {domstate()!r}"
        log(f"{domain} console open")

        # A second launch focuses the window it already has. If it opened a
        # second display instead, QEMU would close the first and the window
        # would go with it — the failure looks like the shell crashing.
        drive("dock launcher", "click", "sleep 1", "type windows", "key enter",
              "sleep 3")
        assert apps()["windows"]["window"], \
            "a second launch took the display away from the first"
        log("a second launch focused rather than reconnected")
    finally:
        drive("key esc")

    # Deliberately left open. There is no position-independent way to close a
    # window from here — no close chord, and the dock menu needs a click at a
    # coordinate — and a flaky close is worse than none, because the next run
    # would inherit whatever state it left. The check is re-runnable as it is:
    # a second launch focuses, which is the thing it asserts anyway.
    #
    # So the detach contract ("closing the window leaves the VM running") is
    # NOT asserted here. It is verified by hand and recorded in
    # docs/plans/guest-display.md; automating it needs a way to ask the shell
    # to close a window by id.
    assert domstate() == before == "running", \
        f"the domain moved from {before!r} to {domstate()!r}"


@check("guest: seamless mode shows a guest app as a window of its own")
def check_guest_seamless() -> None:
    """M2 — docs/plans/guest-seamless.md, Phase 3. With the console open,
    switching to seamless mode closes it and, once the helper inside the
    guest answers, shows one Starling window per guest top-level. Launching
    Notepad through the helper makes such a window; killing it makes it go.
    Then back to the console, which is the state the M1 check leaves behind.

    Everything here goes through the broker — mode switch, launch, the window
    list — because none of it has a position-independent gesture: the mode
    switch is a dock-menu item and the launch happens inside Windows.

    Needs the helper running in the guest (docs/WINDOWS-VM.md, "Apps as
    windows"); without it the switch falls back to the console and this
    says so rather than hanging. Skipped wherever there is no domain.
    """
    domain = os.environ.get("STARLING_GUEST_DOMAIN") or "windows"
    if "windows" not in apps():
        raise Skip("no windows.app in the catalog")
    # Same skip as the M1 check: a catalog record is not a domain. Without
    # this the check launched a console for a domain that did not exist and
    # waited two minutes for it.
    try:
        r = subprocess.run(["virsh", "-c", "qemu:///system", "domstate", domain],
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise Skip(f"no libvirt domain {domain!r}")
    except OSError:
        raise Skip("no libvirt on this machine")

    def guest() -> dict | None:
        for g in ask("guest_state")["guests"]:
            if g["domain"] == domain:
                return g
        return None

    if guest() is None:
        # The M1 check opens the console and leaves it open; on its own this
        # check has to open it itself.
        drive("move 300 300", "dock launcher", "click", "sleep 1", "type windows",
              "key enter")
        try:
            wait_for(lambda: guest() is not None and guest()["console"],
                     "the guest console", timeout=120.0)
        finally:
            drive("key esc")

    ask("guest_mode", domain=domain, mode="seamless")
    # The helper answers hello within a couple of seconds when it is running;
    # the shell gives it 15 s before falling back to the console.
    wait_for(lambda: guest()["mode"] == "seamless" and not guest()["console"],
             "seamless mode")
    log("console closed; seamless mode on")

    def titled(word: str) -> list[dict]:
        return [w for w in guest()["windows"] if word.lower() in w["title"].lower()]

    try:
        # The helper has to be ready before it can launch anything. Its
        # readiness is not reported directly; a launch that goes nowhere is
        # the symptom, so give it a moment after the switch.
        time.sleep(3)
        if guest()["mode"] != "seamless":
            raise Skip("no helper inside the guest: seamless mode fell back to the console")
        ask("guest_launch", domain=domain, path="notepad.exe")
        wait_for(lambda: titled("notepad"), "a Notepad window from the guest",
                 timeout=30.0)
        w = titled("notepad")[0]
        assert w["frame"]["w"] > 0 and w["frame"]["h"] > 0, f"empty frame: {w!r}"
        # Counted as SOME app's window through wmClass: Notepad's own record
        # once the guest's catalog has arrived (Phase 5), the VM's until then.
        rec = f"guest-{domain}-windowsnotepad"
        owners = [a for a in (apps().get(rec), apps().get("windows")) if a and a["window"]]
        assert owners, "the guest window is nobody's (wmClass)"
        log(f"Notepad is a window: {w['window']} {w['frame']}, owned by {owners[0]['app']}")

        ask("guest_launch", domain=domain, path="taskkill.exe",
            args="/IM notepad.exe /F")
        wait_for(lambda: not titled("notepad"), "the Notepad window to go",
                 timeout=30.0)
        log("Notepad closed in the guest; its window went with it")

        # Phase 5: the guest's own catalog became registry records, so the
        # app is launchable the way any app is — by name, from the launcher
        # — and its window is counted as ITS OWN app's, not the VM's.
        wait_for(lambda: rec in apps() and apps()[rec]["kind"] == "guest-app",
                 "the guest's Notepad record", timeout=30.0)
        assert not apps()[rec]["window"], "no Notepad window should exist yet"
        drive("dock launcher", "click", "sleep 1", "type notepad")
        state = ask("launcher_state")
        assert rec in state.get("filtered", []), \
            f"the launcher does not offer the guest app: {state!r}"
        drive("key enter")
        try:
            wait_for(lambda: apps()[rec]["window"],
                     "Notepad, launched from the launcher, as its own app's window",
                     timeout=45.0)
            assert titled("notepad"), "the record's window is not a guest window"
            log("Notepad launched from the launcher and owns its window")
        finally:
            drive("key esc")
        ask("guest_launch", domain=domain, path="taskkill.exe",
            args="/IM notepad.exe /F")
        wait_for(lambda: not apps()[rec]["window"], "the Notepad window to go",
                 timeout=30.0)
        forget_notepad_session(domain)
    finally:
        ask("guest_mode", domain=domain, mode="console")
        wait_for(lambda: guest()["mode"] == "console" and guest()["console"],
                 "the console back")


@check("agents: a guest app is launched, owned, typed into, and captured")
def check_agent_guest_app() -> None:
    """M3 — docs/plans/guest-agents.md, Phase 1. An agent launches a Windows
    app through the broker exactly as it launches Files: the reply names a
    window, that window is the agent's alone (listed for it, not counted as
    the human's), and its keys reach the app inside the guest."""
    domain = os.environ.get("STARLING_GUEST_DOMAIN") or "windows"
    try:
        r = subprocess.run(["virsh", "-c", "qemu:///system", "domstate", domain],
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise Skip(f"no libvirt domain {domain!r}")
    except OSError:
        raise Skip("no libvirt on this machine")
    rec = f"guest-{domain}-windowsnotepad"
    if rec not in apps():
        raise Skip("no guest catalog yet (the seamless check writes it)")

    def guest() -> dict | None:
        for g in ask("guest_state")["guests"]:
            if g["domain"] == domain:
                return g
        return None

    def mine(win: str) -> dict | None:
        g = guest()
        return next((w for w in (g or {}).get("windows", []) if w["window"] == win), None)

    # An agent's launch puts the session in seamless mode, which closes the
    # person's console if it was open; put things back the way they were.
    mode_before = (guest() or {}).get("mode")
    a = Session(name="guest-agent")
    try:
        reply = a.call("launch", app=rec)
        if not reply.get("ok") and "helper" in reply.get("error", ""):
            raise Skip(f"launch refused: {reply['error']}")
        assert reply.get("ok"), f"launch failed: {reply.get('error')}"
        win = reply["win"]
        # Notepad restores every window of its last session at launch, so
        # the agent may own several; each is its process's, none the human's.
        listed = [w["win"] for w in a.ok("list_windows")["windows"]]
        assert win in listed, f"the agent does not list {win}, only {listed}"
        w = mine(win)
        assert w and w["owner"] == a.agent_id, f"guest_state disagrees about the owner: {w!r}"
        strays = [x for x in guest()["windows"]
                  if "notepad" in x["title"].lower() and x["owner"] != a.agent_id]
        assert not strays, f"windows of the launched process fell to the human: {strays!r}"
        assert not apps()[rec]["window"], "the agent's window is counted as the human's"
        assert not w["focused"], "the agent's window took the human's focus"
        log(f"{win} is {a.agent_id}'s ({len(listed)} window(s)): listed for it, none for the desktop")

        # Keys go through the human's own door into the guest. Settle first,
        # as the shim does: `launch` answers on the first window, and Notepad
        # takes no text until its startup has stopped painting (typed at
        # once, the text was lost with ok:true). Notepad marks a modified
        # buffer with a leading asterisk in its title, which is the guest's
        # own word that the text arrived.
        settled = a.ok("await_settled", win=win, timeout_ms=8000)
        assert not settled["timed_out"], f"the guest never went quiet: {settled!r}"
        # The window is a freshly launched, empty Notepad (its saved tabs
        # were cleared at the end of the last run), so typing marks the
        # buffer modified — Notepad's own leading asterisk in the title,
        # which is the guest saying the keys reached the edit control. Not
        # the exact word: a key dropped under first-launch churn would fail
        # a claim Phase 1 does not make, which is that no key is ever lost.
        a.ok("inject", win=win, ev={"type": "text", "text": "starling"})
        wait_for(lambda: (mine(win) or {}).get("title", "").startswith("*"),
                 "Notepad to report a modified buffer", timeout=15.0)
        log(f"typed into {win}: title is {mine(win)['title']!r}")

        # The lease. The guest has one input queue: while the person has a
        # window of it focused (Calculator, launched the human way and
        # raised by the guest's own foreground change), the agent's input is
        # refused with the distinct error, and allowed again once they are
        # done.
        ask("guest_launch", domain=domain, path="calc.exe")

        def theirs() -> list[dict]:
            return [x for x in guest()["windows"] if x["owner"] == "" and x["focused"]]
        wait_for(theirs, "a human-owned, focused Calculator window", timeout=30.0)
        assert guest()["humanUsing"], "guest_state does not report the human's lease"
        denied = a.call("inject", win=win, ev={"type": "text", "text": "x"})
        assert not denied.get("ok"), "the agent typed while the human held the guest"
        assert "human is using" in denied.get("error", ""), \
            f"refused for the wrong reason: {denied.get('error')}"
        log(f"lease held by the human: {denied['error'][:40]}...")

        # Capture is lease-free: it reads pixels through the helper's
        # PrintWindow, touches no input, and is occlusion-proof — so it
        # succeeds on this background window even now, while inject is refused
        # (M3 Phase 2). It comes back as a PNG, because the channel to the VM
        # is serial and a raw window would be megabytes.
        shot = a.ok("capture", win=win, max_px=1280)
        assert shot.get("format") == "png", f"guest capture is not PNG: {shot!r}"
        pw, ph = png_dims(shot["data"])
        assert (pw, ph) == (shot["w"], shot["h"]), \
            f"PNG IHDR {pw}x{ph} disagrees with w/h {shot['w']}x{shot['h']}"
        assert max(pw, ph) <= 1280 and pw > 100 and ph > 100, f"odd capture size {pw}x{ph}"
        assert len(base64.b64decode(shot["data"])) > 1500, "capture is implausibly small (blank?)"
        log(f"captured {win} at {pw}x{ph} ({len(base64.b64decode(shot['data']))}B PNG) "
            "while the human held the lease")
        ask("guest_launch", domain=domain, path="taskkill.exe",
            args="/IM CalculatorApp.exe /F")
        wait_for(lambda: not theirs() and not guest()["humanUsing"],
                 "the lease back", timeout=30.0)
        a.ok("inject", win=win, ev={"type": "text", "text": "!"})
        log("lease released: the agent types again")
    finally:
        for exe in ("notepad.exe", "CalculatorApp.exe"):
            try:
                ask("guest_launch", domain=domain, path="taskkill.exe",
                    args=f"/IM {exe} /F")
            except AssertionError:
                pass
        forget_notepad_session(domain)
        a.close()
        # Back to the console — the resting state the other guest checks
        # expect to find or create. Only a session the person had explicitly
        # in seamless is left as it was.
        if mode_before != "seamless":
            ask("guest_mode", domain=domain, mode="console")
            wait_for(lambda: (guest() or {}).get("mode") == "console"
                     and (guest() or {}).get("console"), "the console back")


@check("agents: a guest app answers its accessibility tree, and an action drives it")
def check_agent_guest_semantics() -> None:
    """M3 — docs/plans/guest-agents.md, Phase 3. The broker proxies
    semantic_tree/perform_action to the guest's helper, which walks UIA; the
    nodes come back in the SAME flat shape a first-party window's do, so an
    agent addresses a Windows app's controls by label exactly as it does a
    Starling app's — and an action performed on a node drives the real app."""
    domain = os.environ.get("STARLING_GUEST_DOMAIN") or "windows"
    try:
        r = subprocess.run(["virsh", "-c", "qemu:///system", "domstate", domain],
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise Skip(f"no libvirt domain {domain!r}")
    except OSError:
        raise Skip("no libvirt on this machine")
    rec = f"guest-{domain}-windowsnotepad"
    if rec not in apps():
        raise Skip("no guest catalog yet (the seamless check writes it)")

    def guest() -> dict | None:
        for g in ask("guest_state")["guests"]:
            if g["domain"] == domain:
                return g
        return None

    def title(win: str) -> str:
        g = guest() or {}
        return next((w["title"] for w in g.get("windows", []) if w["window"] == win), "")

    mode_before = (guest() or {}).get("mode")
    # Start from one clean, empty Notepad — a restored multi-tab session opens
    # windows whose editor is not the one `launch` returns, and its tree then
    # has no editable node.
    if mode_before == "seamless":
        forget_notepad_session(domain)
    a = Session(name="guest-a11y")
    try:
        reply = a.call("launch", app=rec)
        if not reply.get("ok") and "helper" in reply.get("error", ""):
            raise Skip(f"launch refused: {reply['error']}")
        assert reply.get("ok"), f"launch failed: {reply.get('error')}"
        win = reply["win"]
        a.ok("await_settled", win=win, timeout_ms=8000)

        # The editor's ValuePattern appears a beat after the window does, so
        # re-walk until it is there (or give up and assert on what we have).
        nodes = []
        doc = None
        for _ in range(6):
            nodes = a.ok("semantic_tree", win=win)["nodes"]
            doc = next((n for n in nodes if "set_value" in n["actions"]), None)
            if doc:
                break
            time.sleep(0.5)
        assert nodes, "the UIA tree came back empty"
        labels = {n["label"] for n in nodes}
        # Notepad's menu bar — the tree reaches the real control hierarchy,
        # not just the top-level window.
        assert {"File", "Edit", "View"} <= labels, \
            f"no menu bar in the tree; got {sorted(l for l in labels if l)[:15]}"
        # Every node carries the contract's fields.
        n0 = nodes[0]
        assert set(("node", "label", "actions", "rect")) <= set(n0), f"node shape: {n0!r}"
        # A node that takes text (the editor's ValuePattern) — drive it, and
        # the guest's own asterisk says the buffer changed.
        assert doc, f"no editable node among {len(nodes)}"
        a.ok("perform_action", win=win, node=doc["node"],
             action="set_value", value="starling via UIA")
        wait_for(lambda: title(win).startswith("*"),
                 "the editor to report a modified buffer after set_value", timeout=15.0)
        log(f"{len(nodes)} UIA nodes incl. the menu bar; set_value drove node "
            f"{doc['node']} -> title {title(win)!r}")
    finally:
        try:
            ask("guest_launch", domain=domain, path="taskkill.exe",
                args="/IM notepad.exe /F")
        except AssertionError:
            pass
        forget_notepad_session(domain)
        a.close()
        if mode_before != "seamless":
            ask("guest_mode", domain=domain, mode="console")
            wait_for(lambda: (guest() or {}).get("mode") == "console"
                     and (guest() or {}).get("console"), "the console back")


def forget_notepad_session(domain: str) -> None:
    """Notepad restores every buffer a kill left behind, one window each, on
    its next launch — so each run of these checks would start with one more
    window than the last. Drop its saved tabs after the process is gone."""
    time.sleep(1.5)
    # `if exist`, so the command exits cleanly: Windows 11 opens console
    # commands in Terminal, which stays open after a FAILED command, and a
    # focused Terminal window is the human holding the guest's lease.
    tabs = "%LOCALAPPDATA%\\Packages\\Microsoft.WindowsNotepad_8wekyb3d8bbwe\\LocalState\\TabState"
    try:
        ask("guest_launch", domain=domain, path="cmd.exe",
            args=f'/c if exist "{tabs}" rd /s /q "{tabs}"')
    except AssertionError:
        return

    def terminal_open() -> bool:
        for g in ask("guest_state")["guests"]:
            if g["domain"] == domain:
                return any("terminal" in w["title"].lower() for w in g["windows"])
        return False
    deadline = time.time() + 10
    while terminal_open() and time.time() < deadline:
        time.sleep(0.5)


@check("registry: installing and removing moves the launcher live")
def check_install_remove_loop() -> None:
    """The install/remove loop with no vendor, no network and nothing real to
    break: a record appears, the shell must show the app; it goes, the shell
    must drop it — with no relogin."""
    records = Path(os.environ.get("STARLING_APP_RECORDS",
                                  "/var/lib/starling/installed.d"))
    record = records / f"{FAKE_ID}.app"
    if FAKE_ID not in apps():
        raise Skip("fixture catalog not present")
    assert not apps()[FAKE_ID]["installed"], f"{FAKE_ID} already installed"

    FAKE_BIN.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy("/bin/sleep", FAKE_BIN)
    record.write_text(
        f"[Starling App]\nId={FAKE_ID}\nWmClass={FAKE_ID}\n"
        f"InstalledAt={int(time.time())}\n")
    try:
        wait_for(lambda: apps()[FAKE_ID]["installed"],
                 "the shell to notice the install")
        log("installed, launcher updated")
    finally:
        # Both halves, as a real uninstall does: the record AND the files.
        # Deleting only the record leaves the catalog's Bins probe succeeding,
        # and the app correctly stays installed — the fallback that covers
        # apps installed outside the store.
        record.unlink(missing_ok=True)
        shutil.rmtree(FAKE_ROOT, ignore_errors=True)
    wait_for(lambda: not apps()[FAKE_ID]["installed"],
             "the shell to notice the removal")
    log("removed, launcher updated")


@check("safety: app-install refuses to remove a running app")
def check_remove_guard() -> None:
    """Exercised against the fake app, so a failure of the guard cannot
    uninstall anything real — which is exactly how this check earned its
    place."""
    FAKE_BIN.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy("/bin/sleep", FAKE_BIN)
    def running() -> int:
        return subprocess.run([str(APP_INSTALL), "--running", FAKE_ID],
                              capture_output=True, text=True).returncode

    # The guard answers from the catalog, and the fixture app is only in the
    # copy this suite builds — an attached session reads the shipped one and
    # answers "cannot tell" (rc 2). That is the guard behaving correctly
    # about an app it has never heard of, not a regression.
    if running() == 2:
        raise Skip("fixture catalog not present (attached session)")
    assert running() == 1, "reported running before anything started"
    proc = subprocess.Popen([str(FAKE_BIN), "60"])
    try:
        wait_for(lambda: running() == 0, "the guard to see the process",
                 timeout=10)
        log("guard detects the running process")
    finally:
        proc.terminate()
        proc.wait()
    wait_for(lambda: running() == 1, "the guard to see it exit", timeout=10)
    shutil.rmtree(FAKE_ROOT, ignore_errors=True)


@check("store: removing a real app through app-install drops it from the launcher")
def check_real_remove() -> None:
    """The other half of the loop, through the same path the Remove button
    uses. Runs last, so the identity checks above still had the app."""
    if os.environ.get("STARLING_TEST_INSTALL") != "1":
        raise Skip("set STARLING_TEST_INSTALL=1 to install/remove a real app")
    if not apps().get(REAL_APP, {}).get("installed"):
        raise Skip(f"{REAL_APP} is not installed")
    assert not apps()[REAL_APP]["process"], \
        f"{REAL_APP} is still running — removal must refuse, not proceed"

    result = subprocess.run(["sudo", str(APP_INSTALL), "--remove", REAL_APP],
                            capture_output=True, text=True, timeout=600)
    assert result.returncode == 0, \
        f"app-install --remove {REAL_APP} failed: {result.stderr.strip()[-200:]}"
    wait_for(lambda: not apps()[REAL_APP]["installed"],
             f"the shell to drop {REAL_APP} from the launcher")
    records = Path(os.environ.get("STARLING_APP_RECORDS",
                                  "/var/lib/starling/installed.d"))
    assert not (records / f"{REAL_APP}.app").exists(), \
        "the registry record outlived the app"
    log("removed; launcher and record both gone")


# ── runner ───────────────────────────────────────────────────────────────────



@check("agents: an agent sees only the windows it launched")
def check_agent_scope() -> None:
    """The whole scope model in one assertion. An agent addresses windows it
    owns; another agent's — and the human's — are not listed, not injectable,
    not capturable, and not readable through the semantics endpoint."""
    a = Session(name="scope-a")
    b = Session(name="scope-b")
    try:
        assert a.agent_id != b.agent_id, "two hellos returned the same agent"
        win = a.ok("launch", app="files")["win"]
        try:
            assert [w["win"] for w in a.ok("list_windows")["windows"]] == [win]
            assert b.ok("list_windows")["windows"] == [], \
                "agent B can see agent A's window"
            for op, extra in (("capture", {}),
                              ("semantic_tree", {}),
                              ("inject", {"ev": {"type": "click", "x": 5, "y": 5}})):
                denied = b.call(op, win=win, **extra)
                assert not denied.get("ok"), f"agent B was allowed to {op}"
                assert "no such owned window" in denied.get("error", ""), \
                    f"{op} denied for the wrong reason: {denied.get('error')}"
            log(f"{win} is addressable by {a.agent_id} and invisible to {b.agent_id}")
        finally:
            # The broker has no close op, so the window outlives the check.
            # Harmless — agent windows have no desktop presence and are drawn
            # only in the AI Space — but it is why this tier ends with a
            # Files process still running.
            pass
    finally:
        a.close()
        b.close()


@check("agents: an agent can re-attach to its own identity, not another's")
def check_agent_reattach() -> None:
    """Window ownership is per agent and each command of a CLI is its own
    process, so re-attaching is what makes `launch` then `click` possible at
    all. The token is what stops agent-2 rejoining as agent-1 by guessing."""
    first = Session(name="reattach")
    agent, token = first.agent_id, first.token
    win = first.ok("launch", app="files")["win"]
    first.close()                      # the CLI's process exits here

    back = Session(name="reattach", agent=agent, token=token)
    try:
        assert back.agent_id == agent, f"re-attach gave {back.agent_id}, not {agent}"
        assert [w["win"] for w in back.ok("list_windows")["windows"]] == [win], \
            "re-attached agent lost the window it launched"
        log(f"{agent} came back to {win} on a new connection")
    finally:
        back.close()

    impostor = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    impostor.settimeout(10.0)
    impostor.connect(broker_path())
    try:
        impostor.send(json.dumps(
            {"id": 1, "op": "hello", "name": "impostor",
             "agent": agent, "token": "0" * len(token)}).encode() + b"\n")
        reply = json.loads(impostor.recv(65536).split(b"\n", 1)[0])
        assert not reply.get("ok"), "a wrong token was accepted"
        assert "bad token" in reply.get("error", ""), reply
        log("a wrong token is refused")
    finally:
        impostor.close()


@check("agents: capture reads the window's own pixels, at the size asked for")
def check_agent_capture() -> None:
    """Milestone 1 of docs/plans/computer-use.md, from the outside.

    `capture` used to mmap the child's linear DMA-BUF, which meant it worked
    for first-party children and returned "window has no capturable buffer"
    for every Wayland client — Chrome, VS Code, Claude Desktop itself. It now
    resolves the window's texture through the compositor, so this asserts the
    reply says `texture` rather than `dmabuf`: a silent fall back to the mmap
    would still pass a pixels-are-non-empty check on a first-party window and
    hide the regression from everything except a Chrome test the fast tiers
    cannot run.
    """
    s, win = settings_window()
    try:
        shot = s.ok("capture", win=win)
        assert shot.get("source") == "texture", \
            f"capture fell back to {shot.get('source')!r}"
        assert shot["row_order"] == "top-down", shot["row_order"]
        assert shot["stride"] == shot["w"] * 4, shot["stride"]
        data = base64.b64decode(shot["data"])
        assert len(data) == shot["stride"] * shot["h"], len(data)
        # An all-zero read is a failed capture, not a black window — and
        # writing it out as a screenshot is the worst outcome, because an
        # agent then reasons about an app that looks blank.
        assert any(data[::499]), "capture read back entirely empty"

        # The cap is what keeps a 2560x1600 panel from base64'ing four
        # megapixels an agent asked for at 1280.
        small = s.ok("capture", win=win, max_px=320)
        assert max(small["w"], small["h"]) == 320, (small["w"], small["h"])
        assert small["content"] == shot["content"], "the cap moved the window"
        assert any(base64.b64decode(small["data"])[::499]), "empty at 320px"

        # ...and it has to be QUICK. A screenshot is what an agent looks at
        # between one action and the next, so its cost is added to the age of
        # everything it sees. This reply used to go through Foundation's JSON
        # writer whole, which escapes every '/' — and base64 of a
        # mostly-white UI is mostly '/'. One 1.5-megapixel screenshot took
        # 970ms to serialize, so an agent that typed and screenshotted was
        # looking at the window as it had been a second earlier, and read the
        # empty compose pane it got back as its own typing having missed.
        # The blob is spliced in by hand now: ~45ms. The threshold is a
        # tenth of the bug and ten times the fix.
        t0 = time.monotonic()
        big = s.ok("capture", win=win, max_px=1280)
        took = time.monotonic() - t0
        assert took < 0.4, (
            f"a {big['w']}x{big['h']} screenshot took {took * 1000:.0f}ms — "
            "the pixels are going through a JSON escaper again")
        log(f"{shot['w']}x{shot['h']} from the texture, {small['w']}x{small['h']} "
            f"capped, {big['w']}x{big['h']} in {took * 1000:.0f}ms")
    finally:
        s.close()


@check("agents: inject drives a window by coordinate, and reports where it did")
def check_agent_inject_vocabulary() -> None:
    """Coordinates in, a changed UI out — asserted through the semantic tree
    rather than pixels, which is what keeps this tier fast and stops it
    re-blessing whatever the shell happens to draw.

    The click target comes from the tree's own rect, so this also checks the
    two agree about where things are: a coordinate click that misses would
    leave the tree unchanged and time out here.
    """
    s, win = settings_window()
    try:
        nodes = tree_nodes(s, win)
        target = next(n for n in nodes
                      if (n.get("label") or "").startswith("Network")
                      and "tap" in (n.get("actions") or []))
        x, y, w, h = target["rect"]
        cx, cy = x + w / 2, y + h / 2
        before = [n.get("label") for n in nodes]

        s.ok("inject", win=win, ev={"type": "click", "x": cx, "y": cy})
        wait_for(lambda: [n.get("label") for n in tree_nodes(s, win)] != before,
                 "a coordinate click to change the pane")

        pos = s.ok("cursor_position", win=win)
        assert abs(pos["x"] - cx) < 0.5 and abs(pos["y"] - cy) < 0.5, \
            f"cursor_position says {pos}, click was at {cx},{cy}"

        # The rest of the vocabulary: every member the computer-use contract
        # names has to be accepted, or the shim answers a model with an error
        # it can do nothing about. Effects are the previous assertion's job;
        # this is coverage of the switch.
        for ev in ({"type": "rclick", "x": cx, "y": cy},
                   {"type": "mclick", "x": cx, "y": cy},
                   {"type": "dblclick", "x": cx, "y": cy},
                   {"type": "tripleclick", "x": cx, "y": cy},
                   {"type": "down", "x": cx, "y": cy},
                   {"type": "up", "x": cx, "y": cy},
                   {"type": "drag", "x": cx, "y": cy, "x2": cx + 20, "y2": cy + 20},
                   {"type": "keydown", "physical": 0xE0},
                   {"type": "keyup", "physical": 0xE0},
                   {"type": "text", "text": "hi"}):
            s.ok("inject", win=win, ev=ev)
        s.ok("wait", ms=50)
        log("click, cursor_position and the ten added actions all answered")
    finally:
        s.close()


@check("agents: launch offers the registry, not a table")
def check_agent_launch_scope() -> None:
    """The scope the broker advertises has to be the registry's answer. It was
    a hardcoded four, which CLAUDE.md forbids and which made an agent that can
    only open Settings; the check that matters is that it now tracks what is
    installed rather than what someone remembered to add."""
    s = Session(name="launch-scope")
    try:
        scope = set(s.hello_scope.get("launch", []))
        installed = {a["app"] for a in ask("list_apps")["apps"]
                     if a.get("installed") and a.get("kind") in ("first-party", "host")}
        assert scope == installed, \
            f"scope {sorted(scope)} != installed first-party/host {sorted(installed)}"
        # x11 and android records fit no ownership model — one window covers a
        # whole rootful Xwayland screen or every Android app at once — so they
        # must be refused with a reason rather than silently missing.
        for app in (a["app"] for a in ask("list_apps")["apps"]
                    if a.get("kind") in ("x11", "android")):
            denied = s.call("launch", app=app)
            assert not denied.get("ok"), f"{app} was launchable"
        log(f"{len(scope)} launchable app(s), from the registry")
    finally:
        s.close()


@check("agents: the human can take a window back, until Esc")
def check_agent_take_over() -> None:
    """The safety property the design claims and, until now, did not have.

    Take-over shipped, then went out with the AI Space (3776fd6) — the flag
    lived in that UI. What survived was a doc comment describing a guard the
    code no longer had. It only became a real regression once agent windows
    were drawn at all, which is what the workspace rail now does.

    Driven the way a person does it, because that is the only way the flag
    can be set: the broker deliberately offers no op for it. An agent must
    not be able to hand itself back a window the human is holding.
    """
    # Every agent with a window has a rail entry, and the earlier agent
    # checks leave theirs behind — the first run of this clicked the pane of
    # whichever workspace happened to be selected (an earlier agent's Files
    # window), took THAT, and reported that clicking had not worked. Clearing
    # them first leaves exactly one agent in the rail, which is then the
    # selected one, so the click below needs no rail geometry to aim at.
    quit_app("SettingsApp", "FileExplorerApp")
    s, win = settings_window()
    try:
        assert s.ok("list_windows")["windows"][0]["held"] is False, \
            "a fresh agent window came back already held"

        # Ctrl+Down enters workspace mode; the agent's rail entry appears
        # there because its windows are owned by it. One shell-drive
        # invocation for the whole sequence — a second one delivers no keys
        # at all (see the input-fault note in shell-drive.py).
        drive("move 640 400", "sleep 1", "key ctrl+down", "sleep 3",
              "click 900 400", "sleep 2")
        held = s.ok("list_windows")["windows"][0]
        assert held["held"] is True, "clicking the pane did not take the window"

        # Every op that acts on the window or READS it must refuse, and say
        # which of the two things went wrong: an agent told "no such owned
        # window" about a window it opened cannot tell revocation from a
        # crash, and retries forever.
        for op, kw in (("capture", {}), ("await_settled", {}),
                       ("inject", {"ev": {"type": "hover", "x": 5, "y": 5}})):
            r = s.call(op, win=win, **kw)
            assert not r.get("ok"), f"{op} was allowed while the human held it"
            assert "taken control" in (r.get("error") or ""), \
                f"{op} refused with the wrong reason: {r.get('error')!r}"

        drive("move 900 400", "sleep 1", "key esc", "sleep 2")
        assert s.ok("list_windows")["windows"][0]["held"] is False, \
            "Esc did not give the window back"
        assert s.ok("capture", win=win, max_px=64)["w"] > 0, \
            "capture stayed refused after Esc"
    finally:
        # Leave the desktop where it was found, whatever failed above.
        drive("move 640 400", "sleep 1", "key ctrl+down", "sleep 2")
        s.close()
        quit_app("SettingsApp")


@check("agents: a click lands where the agent aimed, not merely somewhere")
def check_agent_click_coordinates() -> None:
    """The coordinate space the capture promises has to be the one clicks use.

    Every other click check asks "did the page see a click", which a page-wide
    handler answers yes to however far off the pointer landed. That blind spot
    shipped a real bug: the shell read a client's BUFFER size as its surface
    size, and Chromium at a fractional scale draws a buffer 1.5x the surface
    it asked for (wp_viewporter scales it down, buffer_scale stays 1). So
    every coordinate went out 1.5x too far — visibly wrong on screen, and
    invisible to a test that only counted clicks. An agent driving a mail app
    aimed at a toolbar button, hit something else, and typed a paragraph into
    whatever it opened.

    So this check asserts the NUMBERS: the page reports the coordinate it was
    clicked at, in the same space `capture` reports its content size in, and
    the two have to agree.

    Measured as the DISTANCE between two clicks rather than the absolute
    position of one, because the page's own coordinates start below the
    browser's toolbar and the test has no business knowing how tall that is.
    A distance has no such inset in it: aim 200px further down, the page must
    see 200px, and the bug this guards turned that into 300.

    Read back through `capture`, deliberately: the property under test is
    that the picture an agent looks at and the coordinates it clicks with are
    one space, so the answer belongs in the picture. (The window TITLE, which
    the neighbouring check uses, is no good here — Chrome hands a title change
    to the compositor on its own schedule, and an agent window can sit on a
    stale one until the next click, reporting each click's position one click
    late.)
    """
    # A page whose whole job is to paint a red mark where it was clicked.
    page = ("data:text/html,<title>CLICKMARK</title>"
            "<body style='margin:0;background:%23000'>"
            "<div id=d style='position:fixed;left:-99px;top:0;width:30px;"
            "height:30px;background:%23ff2020'></div>"
            "<script>document.onclick=e=>{d.style.left=(e.clientX-15)+'px';"
            "d.style.top=(e.clientY-15)+'px'}</script>")

    def red_mark(shot):
        """Centre of the red mark in the capture's CONTENT coordinates."""
        px = base64.b64decode(shot["data"])
        w, h = shot["w"], shot["h"]
        xs, ys, n = 0, 0, 0
        for row in range(0, h, 2):
            base = row * w * 4
            for col in range(0, w, 2):
                i = base + col * 4
                if px[i] > 170 and px[i + 1] < 90 and px[i + 2] < 90:
                    xs += col
                    ys += row if shot.get("row_order") == "top-down" else h - 1 - row
                    n += 1
        if n < 4:
            return None
        scale = shot["content"][0] / float(w)
        return (xs / n * scale, ys / n * scale)

    s = Session(name="click-coords-check")
    try:
        win = s.ok("launch", app="chrome", url=page)["win"]
        time.sleep(6)                       # the page paints nothing to wait on
        s.call("await_settled", win=win, timeout_ms=8000)
        first = s.ok("capture", win=win, max_px=640)
        cw, ch = first["content"]
        assert cw > 100 and ch > 100, f"implausible content size {cw}x{ch}"
        assert red_mark(first) is None, "the mark is on screen before any click"

        def click_at(x, y):
            s.ok("inject", win=win, ev={"type": "click", "x": x, "y": y})
            s.call("await_settled", win=win, timeout_ms=5000)
            mark = None
            deadline = time.time() + 15
            while mark is None and time.time() < deadline:
                mark = red_mark(s.ok("capture", win=win, max_px=640))
                if mark is None:
                    time.sleep(1)
            assert mark, f"clicking ({x},{y}) painted no mark — did it land?"
            return mark

        # Two points, both well inside the page area (the browser's own
        # toolbar is the top ~10%), and off-centre on both axes so a
        # transposed mapping cannot coincidentally agree.
        a1 = (int(cw * 0.30), int(ch * 0.35))
        a2 = (int(cw * 0.62), int(ch * 0.60))
        g1 = click_at(*a1)
        g2 = click_at(*a2)
        want = (a2[0] - a1[0], a2[1] - a1[1])
        got = (g2[0] - g1[0], g2[1] - g1[1])
        # Subsampling the capture puts a couple of pixels of slack in each
        # centroid; the failure this guards is 50% of the distance.
        tol = 12
        assert abs(got[0] - want[0]) <= tol and abs(got[1] - want[1]) <= tol, (
            f"moved the click {want[0]}x{want[1]}px in a {cw}x{ch} content "
            f"space, the mark moved {got[0]:.0f}x{got[1]:.0f}px — scale "
            f"{got[0] / max(want[0], 1):.2f}x{got[1] / max(want[1], 1):.2f}")
        # Horizontally there is no browser toolbar to absorb an error, so the
        # absolute coordinate has to agree too.
        assert abs(g1[0] - a1[0]) <= tol, (
            f"clicked x={a1[0]}, the mark landed at x={g1[0]:.0f}")
        log(f"{a1} and {a2} in {cw}x{ch} -> "
            f"({g1[0]:.0f},{g1[1]:.0f}) and ({g2[0]:.0f},{g2[1]:.0f})")
    finally:
        s.close()
        quit_app("chrome")


@check("agents: a click still lands after the human's pointer has been elsewhere")
def check_agent_click_after_human_pointer() -> None:
    """One seat, one pointer focus — and the shell kept two ideas of it.

    The agent's pointer path cached the surface it had last entered, and the
    human's path cached its own. Whenever the human's pointer crossed from the
    agent's window onto another one, the client was sent a leave; the agent's
    cache still said "already in there", so it never re-sent the enter. Every
    later inject was accepted, audited ok, and delivered as motion+button —
    and dropped by the client, which believed the pointer was elsewhere.
    Screenshots kept working, so it read as the agent going blind rather than
    mute, and moving the real pointer back over the window "fixed" it.

    Driven end to end because nothing smaller can see it: the fault is in what
    the CLIENT believes, so the only honest oracle is a page reporting what it
    received. The page counts clicks — and pointer LEAVES — into its own
    title, which the broker already reports: no DevTools, no second channel.
    The leave count is what keeps this check honest. The bug's precondition
    is "the client was sent a leave", and if the drive coordinates below ever
    drift off the windows they aim at, no leave is sent and the second click
    lands trivially — the check would keep passing on a shell where the bug
    is back. So the crossing is asserted, not assumed.
    """
    page = ("data:text/html,<title>CLICKS0L0</title><body style='margin:0'>"
            "<script>let n=0,l=0;const t=()=>"
            "document.title='CLICKS'+n+'L'+l;"
            "document.onclick=()=>{n++;t()};"
            "document.onmouseout=e=>{if(!e.relatedTarget){l++;t()}}</script>")

    def title_of(s, win):
        for w in s.ok("list_windows")["windows"]:
            if w["win"] == win:
                return w.get("title") or ""
        return ""

    s = Session(name="click-focus-check")
    desktop_chrome = None
    try:
        win = s.ok("launch", app="chrome", url=page)["win"]
        wait_for(lambda: "CLICKS0" in title_of(s, win), "the test page to load",
                 timeout=40)
        # A second Wayland window for the human's pointer to move ON to. It
        # has to be a real client: the shell's own chrome is not a surface,
        # so crossing onto it sends nobody a leave and the bug stays hidden.
        desktop_chrome = app_run("chrome")

        # The agent's FIRST click always worked, even with the bug — its cache
        # starts empty, so it sends the enter. This is the baseline.
        s.ok("inject", win=win, ev={"type": "click", "x": 200, "y": 300})
        wait_for(lambda: "CLICKS1" in title_of(s, win),
                 "the page to see the agent's first click", timeout=15)

        # Now the human: into the workspace where the agent's window is drawn,
        # over its pane (the human's pointer enters that surface), back out,
        # and onto the desktop's own Chrome (which sends the agent's window a
        # leave). One shell-drive invocation for the lot — a second delivers
        # no motion at all (see the note in shell-drive.py).
        drive("move 640 400", "sleep 1", "key ctrl+down", "sleep 3",
              "move 884 400", "sleep 1", "move 890 405", "sleep 1",
              "key ctrl+up", "sleep 2",
              "move 640 400", "sleep 1", "move 645 405", "sleep 1")

        # The client must have SEEN the crossing — a leave with nowhere to
        # go inside the page. Without this the check can pass vacuously: no
        # leave means the client still believes the pointer is in, and the
        # second click lands whether or not the caches are shared.
        wait_for(lambda: re.search(r"CLICKS\d+L[1-9]", title_of(s, win)),
                 "the page to see the human's pointer leave", timeout=15)

        s.ok("inject", win=win, ev={"type": "click", "x": 200, "y": 300})
        wait_for(lambda: "CLICKS2" in title_of(s, win),
                 "the page to see a click after the human's pointer moved away",
                 timeout=15)
    finally:
        s.close()
        if desktop_chrome is not None:
            desktop_chrome.terminate()
        # Both instances: the agent's and the desktop's. They are separate
        # processes (the agent's launch takes its own profile), and the next
        # check should not inherit either.
        quit_app("chrome")
        drive("move 640 400", "sleep 1")


@check("launcher: typing in the Launchpad filters the app grid")
def check_launcher_search() -> None:
    """Reported against 0.2.1: "the search bar inside the Launchpad doesn't
    respond to typing". Nothing in the key path explains it — evdev→HID matches
    its inverse, the key packet decodes, and the shell's router is installed
    from initState so it wins over the FocusManager fallback runApp leaves.

    So this asserts the two halves separately, because they fail differently:
    `query` moving proves keystrokes reached the shell, and `filtered` shrinking
    proves the grid is driven by them. A query that never moves is a
    key-delivery bug; a query that moves while filtered stands still is a
    filtering one. Typing goes through shell-drive's uinput device, so it is the
    real libinput→engine path a user's keyboard takes, not an injected shortcut.
    """
    state = ask("launcher_state")
    assert not state["open"], "Launchpad already open"
    total = len(state["filtered"])
    assert total > 1, f"need >1 installed app to test filtering, have {total}"

    drive("move 300 300", "dock launcher", "click")
    try:
        wait_for(lambda: ask("launcher_state")["open"], "Launchpad to open")

        # A query no app can match: filtering to empty is unambiguous, where a
        # real prefix might coincide with the whole list on a small catalog.
        drive("type zzq")
        wait_for(lambda: ask("launcher_state")["query"] == "zzq",
                 "the typed query to reach the shell")
        log("keystrokes reached the launcher")

        filtered = ask("launcher_state")["filtered"]
        assert filtered == [], f"query 'zzq' matched {filtered}"
        log("the grid filtered to nothing")

        # Backspace edits rather than clearing, and the grid follows back up.
        drive("key backspace", "key backspace", "key backspace")
        wait_for(lambda: ask("launcher_state")["query"] == "",
                 "backspace to clear the query")
        assert len(ask("launcher_state")["filtered"]) == total, \
            "clearing the query did not restore the full grid"
        log("backspace restored the grid")
    finally:
        drive("key esc", "key esc")
    wait_for(lambda: not ask("launcher_state")["open"], "Launchpad to close")


def _nmcli(*args: str) -> str:
    return subprocess.run(["nmcli", *args], capture_output=True,
                          text=True).stdout.strip()


def _net_sim_up() -> bool:
    sim = REPO / "test/net-sim.sh"
    if not sim.exists():
        return False
    return subprocess.run([str(sim), "status"], capture_output=True).returncode == 0


@check("network: the shell reports the wired link NetworkManager sees")
def check_wired_link() -> None:
    """The wired half of the popup is read-only state, so the failure it
    guards against is the quiet one: a device the shell never notices, or a
    link it calls connected while NetworkManager disagrees. Both look like a
    perfectly normal panel.

    Asserted against `nmcli` rather than the shell's own snapshot, and skipped
    (not failed) on a machine with no wired NIC at all.
    """
    state = ask("wifi_state")
    wired = state.get("wired") or {}

    managed = [
        line.split(":")[0]
        for line in _nmcli("-t", "-f", "DEVICE,TYPE,STATE",
                           "device", "status").splitlines()
        if len(line.split(":")) >= 3
        and line.split(":")[1] == "ethernet"
        and line.split(":")[2] != "unmanaged"
    ]
    if not managed:
        raise Skip("no managed wired device on this machine")

    assert wired, f"NetworkManager has wired devices {managed}, the shell reports none"
    assert wired["device"] in managed, \
        f"the shell reports wired device {wired['device']!r}, not among {managed}"
    log(f"the shell reports {wired['device']}")

    # The shell must agree with NetworkManager about whether it is up, and
    # carry an address whenever it says so.
    dev_state = next(
        (line.split(":")[2] for line in _nmcli("-t", "-f", "DEVICE,TYPE,STATE",
                                               "device", "status").splitlines()
         if line.split(":")[0] == wired["device"]), "")
    assert wired["connected"] == (dev_state == "connected"), \
        f"shell says connected={wired['connected']}, nmcli says {dev_state!r}"
    if wired["connected"]:
        assert wired["ip"], f"{wired['device']} reported connected with no address"
        log(f"connected, {wired['ip']}")
    else:
        log(f"not connected ({dev_state})")


@check("wifi: joining a simulated network from the status-bar popup")
def check_wifi_popup_connect() -> None:
    """The popup is the only network UI in the shell itself, and everything it
    can do routes through nmcli — so a wrong device, a stale snapshot or an
    unregistered callback all look the same on screen: a list that never
    changes. This drives the real path (uinput click → shell → nmcli) and
    then asks NetworkManager directly, because the shell agreeing with itself
    proves nothing.

    Needs the simulated radios: `sudo test/net-sim.sh up`. The OPEN network is
    the one joined — a password would test the shell's text input rather than
    its network path, and that has its own coverage.
    """
    if not _net_sim_up():
        raise Skip("network lab is down (sudo test/net-sim.sh up)")

    state = ask("wifi_state")
    if not state["available"]:
        raise Skip("no managed wifi device")
    assert state["enabled"], "wifi radio is off"

    # Start from not-joined, so "connected" can only come from this run.
    _nmcli("connection", "delete", "Starling-Guest")

    # The icon toggles, so a panel someone left open must be closed first —
    # otherwise this "opens" it shut and every row click lands on the desktop.
    if state["popup_open"]:
        drive("key esc")
        wait_for(lambda: not ask("wifi_state")["popup_open"],
                 "a previously-open wifi popup to close")
    drive(f"click {state['icon']['x']:.0f} {state['icon']['y']:.0f}")
    try:
        wait_for(lambda: ask("wifi_state")["popup_open"], "the wifi popup to open")
        wait_for(lambda: "Starling-Guest" in ask("wifi_state")["networks"],
                 "the simulated network to appear in the scan")
        log("the popup lists the simulated network")

        # Both coordinates come from the shell: `content.center_x` for the
        # band rows take taps in, and `rows` for where this particular row
        # ended up. Nothing here reproduces the popup's layout, so adding a
        # section to the panel (the wired block did exactly that) cannot
        # silently send the click to the wrong network.
        listed = ask("wifi_state")
        row_y = next((r["y"] for r in listed["rows"]
                      if r["ssid"] == "Starling-Guest"), None)
        assert row_y is not None, \
            f"the shell lists no row for Starling-Guest: {listed['rows']}"
        drive(f"click {listed['content']['center_x']:.0f} {row_y:.0f}")

        wait_for(lambda: ask("wifi_state")["active"] == "Starling-Guest",
                 f"the shell to report the network as joined (clicked y={row_y:.0f})",
                 timeout=45)
        log("the shell reports the network joined")

        # The assertion that matters: NetworkManager agrees.
        assert "Starling-Guest" in _nmcli("-t", "-f", "NAME", "connection",
                                          "show", "--active"), \
            "the shell says joined but NetworkManager has no such connection"
        assert ask("wifi_state")["ip"], "joined with no address"
        log(f"NetworkManager confirms the join ({ask('wifi_state')['ip']})")
    finally:
        _nmcli("connection", "down", "Starling-Guest")
        _nmcli("connection", "delete", "Starling-Guest")
        drive("key esc")


@check("notifications: events collect behind the bell, shown only on click")
def check_notifications() -> None:
    """Drives org.freedesktop.Notifications over the session's real bus (as
    the session user — a session bus refuses other uids) and asserts through
    the broker, never pixels: a post collects silently (bell tints, no
    popup), clicking the broker-reported bell center opens the center and
    clears the tint, an expire_timeout does NOT remove anything — events
    stay until dismissed or CloseNotification. The daemon is the shell's
    own; a stock one cannot be here, the launchers mask it.
    """
    bus = os.path.dirname(broker_path()) + "/bus"
    if not os.path.exists(bus):
        raise Skip("no session bus socket beside the broker")
    def busctl(*args: str) -> str:
        return session_busctl("call", "org.freedesktop.Notifications",
                              "/org/freedesktop/Notifications",
                              "org.freedesktop.Notifications", *args)

    def state() -> dict:
        return ask("notification_state")

    def ids() -> list:
        return [n["id"] for n in state()["notifications"]]

    info = busctl("GetServerInformation")
    assert '"Starling"' in info, f"someone else answers the bus name: {info}"

    # A short expire_timeout is deliberately ignored: nothing may vanish
    # before the user has looked.
    nid = int(busctl("Notify", "susssasa{sv}i", "functest", "0", "",
                     "collected", "shown only on click", "0", "0", "1500")
              .split()[1])
    wait_for(lambda: nid in ids(), "the event to be collected")
    s = state()
    assert not s["popup_open"], "a post must not open anything on its own"
    assert s["unseen"], "the bell should be tinted until the user looks"
    time.sleep(3)
    assert nid in ids(), \
        "the event expired on its own — a center shows what you missed"

    drive(f"click {s['icon']['x']:.0f} {s['icon']['y']:.0f}")
    wait_for(lambda: state()["popup_open"], "the bell click to open the center")
    assert not state()["unseen"], "opening the center clears the tint"
    drive("key esc")
    wait_for(lambda: not state()["popup_open"], "esc to close the center")
    assert nid in ids(), "closing the popup must not discard events"

    busctl("CloseNotification", "u", str(nid))
    wait_for(lambda: nid not in ids(), "CloseNotification to remove it")
    log("collected, survived its timeout, shown on click, closed by call")


@check("battery: the status bar tracks the kernel's battery")
def check_battery() -> None:
    """Driven with the kernel's own fake-battery driver (test_power), which
    creates test_battery/test_ac in the real /sys/class/power_supply — so the
    whole shipping path runs: sysfs → BatteryReader → the 5s poll → the icon
    and its broker-served geometry. No overrides, no fixture directory.

    Waits are 15s where the icon must move: the poll is 5s and sysfs has no
    inotify, so nothing here is event-driven.
    """
    if ask("battery_state")["present"]:
        raise Skip("machine has a real battery; test_power would mix with it")
    if subprocess.run(["modprobe", "test_power"],
                      capture_output=True).returncode != 0:
        raise Skip("test_power module not available (root? modules-extra?)")
    status_param = Path("/sys/module/test_power/parameters/battery_status")
    try:
        wait_for(lambda: ask("battery_state")["present"],
                 "the shell to notice the fake battery", timeout=15)
        st = ask("battery_state")
        assert "icon" in st, "present battery reports no icon position"
        log(f"icon appeared at ({st['icon']['x']:.0f}, {st['icon']['y']:.0f}), "
            f"{st['percent']}% {st['state']}")

        # The popup opens from a click on the broker-reported center — the
        # same drift-proof contract the wifi popup has.
        drive(f"click {st['icon']['x']:.0f} {st['icon']['y']:.0f}")
        wait_for(lambda: ask("battery_state")["popup_open"],
                 "the battery popup to open")
        drive("key esc")
        wait_for(lambda: not ask("battery_state")["popup_open"],
                 "the battery popup to close")

        # Flip the kernel's reported state; the poll must follow. This is
        # the plug-in-the-charger path a laptop exercises constantly.
        status_param.write_text("charging")
        wait_for(lambda: ask("battery_state")["state"] == "Charging",
                 "the shell to follow the status flip", timeout=15)
        log("state followed the kernel flip to Charging")
    finally:
        subprocess.run(["rmmod", "test_power"], capture_output=True)
    wait_for(lambda: not ask("battery_state")["present"],
             "the icon to go away with the module", timeout=15)
    log("icon left with the module")


@check("bus: the shell owns its two well-known names")
def check_bus_names() -> None:
    """One line of coverage for a whole failure class. The session bus once
    died silently (a root-owned log file killed its redirect) and the shell
    ran busless for weeks — every file dialog broken, nothing failing loudly.
    Unowned names mean that; owned-by-someone-else means an activation race
    the launchers' masking should have prevented."""
    bus = os.path.dirname(broker_path()) + "/bus"
    if not os.path.exists(bus):
        raise Skip("no session bus socket beside the broker")
    shell_pid = int(subprocess.check_output(
        ["pgrep", "-x", "DesktopShellApp"]).split()[0])
    for name in ("org.freedesktop.portal.Desktop",
                 "org.freedesktop.Notifications"):
        out = session_busctl("status", name)
        pid = next((int(l.split("=", 1)[1]) for l in out.splitlines()
                    if l.startswith("PID=")), None)
        assert pid == shell_pid, \
            f"{name} is owned by pid {pid}, not the shell ({shell_pid})"
    log("both names answer to the shell's own pid")


@check("portal: OpenFile launches the shell's picker")
def check_portal_chooser() -> None:
    """The FileChooser path end to end minus the human: a bus call must
    launch FileExplorerApp --picker as a composited child. This is the
    interface every Chromium/Electron/GTK file dialog rides."""
    # Earlier checks (the agents pair) can leave a Files process behind;
    # the probe needs the namespace to itself, so clear it rather than skip.
    if proc_running("FileExplorerApp"):
        quit_app("FileExplorerApp")
        wait_for(lambda: not proc_running("FileExplorerApp"),
                 "a leftover Files process to exit")
    out = session_busctl("call", "org.freedesktop.portal.Desktop",
                         "/org/freedesktop/portal/desktop",
                         "org.freedesktop.portal.FileChooser", "OpenFile",
                         "ssa{sv}", "", "Functional Test", "0")
    assert out.startswith("o "), f"OpenFile returned no request handle: {out}"
    try:
        wait_for(lambda: proc_running("FileExplorerApp"),
                 "the picker helper to start")
        log("picker launched from the bus call")
    finally:
        quit_app("FileExplorerApp")
    wait_for(lambda: not proc_running("FileExplorerApp"), "the picker to exit")


@check("portal: a chooser opened from a window is that window's dialog")
def check_portal_chooser_dialog() -> None:
    """A file dialog belongs ON the page that asked for it. It used to open
    as a free toplevel — a fixed spot on the desktop, and in a workspace a
    whole new TAB that replaced the page — so 'attach a file' looked like the
    app vanishing. Now the chooser is created as the requesting window's
    dialog (parentWindowId), which the pane overlays and the desktop centers.

    Driven the way Chrome really does it: a click on <input type=file> makes
    the portal OpenFile call, and the resulting picker window must arrive in
    the same agent's window list marked as the Chrome window's dialog, at its
    own natural size rather than resized to any pane."""
    if proc_running("FileExplorerApp"):
        quit_app("FileExplorerApp")
        wait_for(lambda: not proc_running("FileExplorerApp"),
                 "a leftover Files process to exit")
    page = ("data:text/html,<title>FILEPICK</title><body style='margin:0'>"
            "<input type=file style='position:fixed;left:0;top:0;"
            "width:100vw;height:100vh'>")
    s = Session(name="chooser-dialog-check")
    try:
        win = s.ok("launch", app="chrome", url=page)["win"]
        time.sleep(6)
        s.call("await_settled", win=win, timeout_ms=8000)
        shot = s.ok("capture", win=win, max_px=640)
        cw, ch = shot["content"]
        s.ok("inject", win=win,
             ev={"type": "click", "x": cw // 2, "y": int(ch * 0.6)})

        def chooser():
            for w in s.ok("list_windows")["windows"]:
                if w["app"].startswith("portal-chooser-"):
                    return w
            return None
        wait_for(lambda: chooser() is not None,
                 "the chooser to appear in the agent's own window list")
        c = chooser()
        assert c["dialog_for"] == win, (
            f"the chooser is nobody's dialog (dialog_for="
            f"{c['dialog_for']!r}, wanted {win!r})")
        assert c["content"][0] == 760, (
            f"the chooser was resized ({c['content']}) — a dialog keeps its "
            f"natural size")
        log(f"chooser {c['win']} is a dialog for {win}")
    finally:
        quit_app("FileExplorerApp")
        s.close()
        quit_app("chrome")
    wait_for(lambda: not proc_running("FileExplorerApp"), "the picker to exit")


@check("screensaver: it appears on its own when idle, and input wakes it")
def check_screensaver_idle() -> None:
    """The whole point of the feature is that nobody has to ask for it, so
    the assertion is that it arrives with no input at all — and then that
    input takes it away again.

    The shell is started with STARLING_SCREENSAVER_IDLE=15 by functional.sh,
    which is why this waits ~15s rather than the shipped ten minutes. Every
    other check in this file drives the pointer, so the idle clock is
    whatever the previous check left it at: the wait starts from now, not
    from the shell's launch.

    Asserted through the broker, never a screenshot. A screensaver is a
    full-screen visual change, so a pixel baseline for one would have to be
    re-blessed on every shader tweak and would then be asserting nothing.
    """
    idle = ask("screensaver")["idle_seconds"]
    if idle <= 0 or idle > 60:
        raise Skip(f"shell's idle timeout is {idle}s — needs the test value")

    # Wake anything already up, then leave the desk alone.
    if ask("screensaver")["active"]:
        drive("key esc")
        wait_for(lambda: not ask("screensaver")["active"], "the saver to clear")
    drive("move 400 400")
    time.sleep(1)

    wait_for(lambda: ask("screensaver")["active"],
             f"the screensaver to appear after {idle}s idle",
             timeout=idle + 20)
    log(f"appeared unprompted after ~{idle}s")

    # The saver ignores the first pointer pixels on purpose (a hand resting
    # on a trackpad emits hover a pixel at a time), so wake it with travel
    # well past the 24px threshold rather than a nudge.
    time.sleep(1)
    drive("move 400 400", "move 900 700")
    wait_for(lambda: not ask("screensaver")["active"],
             "pointer travel to wake the desktop")
    log("pointer travel woke it")

    # And it must come back — the idle cycle re-arms after a wake, which is
    # the bug you only find on the second cycle.
    wait_for(lambda: ask("screensaver")["active"],
             "the screensaver to return on the next idle period",
             timeout=idle + 20)
    drive("key esc")
    wait_for(lambda: not ask("screensaver")["active"], "the saver to clear")
    log("second cycle armed and fired")


def _build_bad_dmabuf_client(into: str) -> str:
    """Compile the fixture hostile-buffer client, or Skip if we can't.
    Same build-on-the-fly reasoning as _build_idle_inhibit_client below."""
    dmabuf_xml = ("/usr/share/wayland-protocols/unstable/linux-dmabuf/"
                  "linux-dmabuf-unstable-v1.xml")
    xdg_xml = "/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml"
    src = _first(REPO / "test/fixtures/bad-dmabuf-client.c",
                 Path(__file__).resolve().parent / "bad-dmabuf-client.c")
    if not shutil.which("wayland-scanner") or not shutil.which("cc"):
        raise Skip("needs wayland-scanner and a C compiler")
    if not os.path.exists(dmabuf_xml) or not os.path.exists(xdg_xml) \
            or src is None:
        raise Skip("protocol XMLs or fixture source missing")
    pieces = []
    for xml, stem in ((dmabuf_xml, "linux-dmabuf-unstable-v1"),
                      (xdg_xml, "xdg-shell")):
        hdr = os.path.join(into, f"{stem}-client-protocol.h")
        code = os.path.join(into, f"{stem}-protocol.c")
        for args in (["wayland-scanner", "client-header", xml, hdr],
                     ["wayland-scanner", "private-code", xml, code]):
            r = subprocess.run(args, capture_output=True, text=True)
            if r.returncode != 0:
                raise Skip(f"wayland-scanner failed: {r.stderr.strip()[:200]}")
        pieces.append(code)
    out = os.path.join(into, "bad-dmabuf")
    r = subprocess.run(
        ["cc", "-o", out, str(src)] + pieces
        + ["-I", into, "-lwayland-client", "-lgbm"],
        capture_output=True, text=True)
    if r.returncode != 0:
        raise Skip(f"could not build the bad-dmabuf client: "
                   f"{r.stderr.strip()[:200]}")
    return out


@check("compositor: a hostile dma-buf commit costs the client, not the shell")
def check_bad_dmabuf_survival() -> None:
    """A client committing buffers the compositor cannot import must lose
    only its own window content.

    From a real incident (2026-08-08, the PRIME work): Chromium steered to
    the NVIDIA main_device committed NVIDIA-tiled buffers; the compositor's
    eglCreateImageKHR refused each one — correctly — and the shell then died
    of an amdgpu CS rejection. The steering experiment was reverted, but the
    exposure is generic: ANY client may commit a dma-buf with a modifier the
    compositor never advertised (a lying client needs no GPU at all), so a
    failed import has to be a self-contained event. The client here cycles
    four full-screen-sized buffers wearing the incident's exact modifier at
    ~60fps; the shell must stay alive and responsive throughout.
    """
    with tempfile.TemporaryDirectory() as tmp:
        client_bin = _build_bad_dmabuf_client(tmp)
        env = dict(os.environ)
        env["XDG_RUNTIME_DIR"] = os.path.dirname(broker_path())
        env["WAYLAND_DISPLAY"] = wayland_display()
        proc = subprocess.Popen([client_bin], env=env,
                                stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        try:
            line = proc.stdout.readline().strip()
            if "bad buffer committed" not in line:
                raise Skip(f"hostile client could not set up: {line!r}")
            log("hostile client committing at ~60fps")
            deadline = time.time() + 8
            while time.time() < deadline:
                assert ask("screen")["ok"], "broker went unresponsive"
                assert proc.poll() is None, \
                    "hostile client died — the compositor may have " \
                    "disconnected it instead of surviving it"
                time.sleep(1)
        finally:
            proc.kill()
            proc.wait()
    # The shell outlives the client's death too.
    assert ask("screen")["ok"], "broker unresponsive after client death"
    log("shell alive and responsive through 8s of unimportable commits")


def _build_idle_inhibit_client(into: str) -> str:
    """Compile the fixture idle-inhibit client, or Skip if we can't.

    Built here rather than shipped as a binary: it needs the protocol
    bindings generated from the system's own wayland-protocols XML, and a
    checked-in a.out would rot against libwayland.
    """
    xml = "/usr/share/wayland-protocols/unstable/idle-inhibit/idle-inhibit-unstable-v1.xml"
    # Beside functional.py as well as in the repo: inside the VM gate there is
    # no repo, and REPO resolves to the parent of wherever this file was
    # dropped. Same two-place lookup as APP_RUN and SHELL_DRIVE above.
    src = _first(REPO / "test/fixtures/idle-inhibit-client.c",
                 Path(__file__).resolve().parent / "idle-inhibit-client.c")
    if not shutil.which("wayland-scanner") or not shutil.which("cc"):
        raise Skip("needs wayland-scanner and a C compiler")
    if not os.path.exists(xml) or src is None:
        raise Skip("idle-inhibit protocol XML or fixture source missing")
    hdr = os.path.join(into, "idle-inhibit-unstable-v1-client-protocol.h")
    code = os.path.join(into, "idle-inhibit-unstable-v1-protocol.c")
    out = os.path.join(into, "inhibit")
    for args in (["wayland-scanner", "client-header", xml, hdr],
                 ["wayland-scanner", "private-code", xml, code],
                 ["cc", "-o", out, str(src), code, "-I", into, "-lwayland-client"]):
        r = subprocess.run(args, capture_output=True, text=True)
        if r.returncode != 0:
            raise Skip(f"could not build the inhibit client: {r.stderr.strip()[:200]}")
    return out


@check("screensaver: a client holding an idle inhibitor keeps it away")
def check_screensaver_inhibit() -> None:
    """Chrome playing a video must not be covered by the screensaver, and a
    Chrome that CRASHES mid-video must not suppress it forever.

    This half of the feature was dead code for a long time and nothing
    noticed: the compositor implemented zwp_idle_inhibit_manager_v1, accepted
    every inhibitor, and dropped it on the floor — under a comment explaining
    that idle tracking didn't exist. It does now. That is exactly the failure
    shape this suite exists for, so it gets a check rather than trust.

    The SIGKILL at the end is the point of the second half: a client that
    dies never sends zwp_idle_inhibitor_v1.destroy, so the count can only be
    right if it is maintained by a wl_resource destructor.
    """
    idle = ask("screensaver")["idle_seconds"]
    if idle <= 0 or idle > 60:
        raise Skip(f"shell's idle timeout is {idle}s — needs the test value")

    with tempfile.TemporaryDirectory() as tmp:
        client_bin = _build_idle_inhibit_client(tmp)

        # Wake anything currently up, so the assertion below is about the
        # inhibitor and not about a saver that was already there.
        if ask("screensaver")["active"]:
            drive("move 400 400", "move 900 700")
            wait_for(lambda: not ask("screensaver")["active"], "the saver to clear")

        env = dict(os.environ)
        env["XDG_RUNTIME_DIR"] = os.path.dirname(broker_path())
        env["WAYLAND_DISPLAY"] = wayland_display()
        proc = subprocess.Popen([client_bin], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True)
        try:
            wait_for(lambda: ask("screensaver")["inhibited"],
                     "the compositor to count the client's inhibitor",
                     timeout=15)
            log("inhibitor counted")

            # The assertion: well past the timeout, with no input at all.
            deadline = time.time() + idle * 2 + 5
            while time.time() < deadline:
                assert not ask("screensaver")["active"], (
                    "screensaver appeared while a client held an idle inhibitor")
                time.sleep(2)
            log(f"stayed away for {idle * 2 + 5}s of idle, as it should")
        finally:
            proc.kill()   # SIGKILL: no destroy request is ever sent
            proc.wait()

    wait_for(lambda: not ask("screensaver")["inhibited"],
             "the inhibitor count to drop when the client DIED", timeout=15)
    log("count released on client death, not on a destroy request")

    # And the saver comes back — a released inhibitor must not leave the idle
    # cycle stalled, and the user gets a fresh period rather than the tail of
    # the one that was running when playback started.
    wait_for(lambda: ask("screensaver")["active"],
             "the screensaver to resume once nothing inhibits it",
             timeout=idle * 3 + 20)
    drive("move 400 400", "move 900 700")
    wait_for(lambda: not ask("screensaver")["active"], "the saver to clear")


@check("tiling: the Settings toggle retiles a live desktop and nothing dies")
def check_tiling_toggle() -> None:
    """Guards the crash class that shipped: flipping tiling resizes every
    user window's renderer mid-flight, which once corrupted child heaps
    (the reassemble-off-the-UI-thread bug). Both apps surviving both flips
    IS the assertion; the persisted file proves the flips happened."""
    layout = Path(session_home()) / ".config/starling/window-layout"
    def persisted() -> str:
        try:
            return layout.read_text().strip()
        except OSError:
            return "floating"
    original = persisted()

    assert not apps()["files"]["window"], "Files already running; quit it first"
    drive("move 300 300", "dock files", "click")
    wait_for(lambda: apps()["files"]["window"], "a user window to tile")
    s, win = settings_window()
    try:
        tap_label(s, win, "Appearance")
        flipped = "floating" if original == "tiling" else "tiling"
        tap_label(s, win, "Tiling Windows")
        wait_for(lambda: persisted() == flipped, "the layout choice to persist")
        time.sleep(2)   # let the retile resize land on the child renderer
        assert apps()["files"]["window"], "Files vanished in the retile"
        assert proc_running("SettingsApp"), "Settings died in the retile"
        tap_label(s, win, "Tiling Windows")
        wait_for(lambda: persisted() == original, "the layout to flip back")
        time.sleep(2)
        assert apps()["files"]["window"], "Files vanished restoring floating"
        assert proc_running("SettingsApp"), "Settings died restoring floating"
        log("two live resizes per app, no casualties")
    finally:
        s.close()
        quit_app("SettingsApp", "FileExplorerApp")
    wait_for(lambda: not apps()["files"]["window"], "Files to close")


@check("style: switching desktop style moves the chrome, not just its colours")
def check_desktop_style() -> None:
    """A style is a SHAPE, so a colour-only regression has to fail here.

    The assertion is geometric: the bottom bar's slots sit at a different
    height in each style — the Windows taskbar is on the screen edge, the
    macOS dock floats above it — so the tile centres move closer to the
    bottom under Fluent and back under macOS. A style that only recoloured
    would leave them exactly where they were and pass every colour check
    ever written.

    The persisted file is the second half: a switch that does not survive
    a relogin is not a setting, and that file is the whole of the record.
    """
    style_file = Path(session_home()) / ".config/starling/style"

    def persisted() -> str:
        try:
            return style_file.read_text().strip()
        except OSError:
            return "macos"   # the default, and what an absent file means

    def bar_y() -> float:
        slots = ask("dock_rects")["slots"]
        assert slots, "the bottom bar reported no slots"
        return slots[0]["y"]

    original = persisted()
    s, win = settings_window()
    try:
        tap_label(s, win, "Appearance")
        tap_label(s, win, "macOS")
        wait_for(lambda: persisted() == "macos", "the macOS style to persist")
        time.sleep(1)
        macos_y, macos_slots = bar_y(), len(ask("dock_rects")["slots"])

        tap_label(s, win, "Windows")
        wait_for(lambda: persisted() == "fluent", "the Windows style to persist")
        time.sleep(1)
        fluent_y, fluent_slots = bar_y(), len(ask("dock_rects")["slots"])

        assert fluent_y > macos_y + 10, (
            f"the bar did not move: macOS {macos_y:.0f}, Fluent {fluent_y:.0f}"
            " — a style that only repaints is not a style")
        assert fluent_slots == macos_slots, (
            f"slot count changed with the style: {macos_slots} → {fluent_slots}")
        assert proc_running("SettingsApp"), "Settings died in the style switch"
        log(f"bar moved {macos_y:.0f} → {fluent_y:.0f}, "
            f"{fluent_slots} slots either way")
    finally:
        # Leave the desktop as it was found, whatever happened above.
        try:
            tap_label(s, win, "macOS" if original == "macos" else "Windows")
            wait_for(lambda: persisted() == original, "the style to restore")
        finally:
            s.close()
            quit_app("SettingsApp")


@check("datetime: the pane sets the system timezone when the session may")
def check_datetime_pane() -> None:
    """Drives the region→city picker and asks timedatectl whether it took.
    Seat-active sessions are authorised silently (allow_active) — the VM
    gate is the only place that's true, so everywhere else this documents
    the refusal as a Skip rather than pretending."""
    def zone() -> str:
        out = subprocess.check_output(["timedatectl", "show"], text=True)
        return next((l.split("=", 1)[1] for l in out.splitlines()
                     if l.startswith("Timezone=")), "")
    original = zone()
    target = ("Australia", "Sydney", "Australia/Sydney")
    if original == target[2]:
        target = ("Pacific", "Auckland", "Pacific/Auckland")

    s, win = settings_window()
    try:
        tap_label(s, win, "Date & Time")
        tap_label(s, win, "Time Zone")
        tap_label(s, win, target[0])
        tap_label(s, win, target[1])
        time.sleep(2)
        now = zone()
        if now == original:
            raise Skip("polkit refused — the session is not seat-active "
                       "(the VM gate is where this proves out)")
        assert now == target[2], f"picked {target[2]}, system says {now}"
        log(f"timezone followed the picker: {original} → {now}")
    finally:
        s.close()
        quit_app("SettingsApp")
        if zone() != original:
            subprocess.run(["timedatectl", "set-timezone", original],
                           capture_output=True)


@check("settings: every pane opens, and the version is the package's truth")
def check_settings_walk() -> None:
    """Opens all nine panes in one sitting — each one's build() runs, so a
    pane that crashes the app cannot ship — and checks the General pane's
    version against the VERSION stamp the shell actually runs from, read
    out of the shell's own environment. \"dev build\" with no stamp is a
    pass: that is the truth this pane exists to tell."""
    shell_pid = int(subprocess.check_output(
        ["pgrep", "-x", "DesktopShellApp"]).split()[0])
    environ = Path(f"/proc/{shell_pid}/environ").read_bytes().split(b"\0")
    data_dir = next((e.split(b"=", 1)[1].decode() for e in environ
                     if e.startswith(b"STARLING_DATA_DIR=")),
                    "/usr/share/starling")
    try:
        expected = (Path(data_dir) / "VERSION").read_text().strip()
    except OSError:
        expected = "dev build"

    s, win = settings_window()
    try:
        for pane in ("Network", "Displays", "Sound", "Date & Time",
                     "Default Apps", "Appearance", "Power", "About",
                     "General"):
            tap_label(s, win, pane)
            assert proc_running("SettingsApp"), f"Settings died opening {pane}"
        labels = [n.get("label") or "" for n in tree_nodes(s, win)]
        assert f"Version {expected}" in labels, \
            f"General shows none of 'Version {expected}': {[l for l in labels if 'ersion' in l]}"
        log(f"nine panes, no casualties, version reads '{expected}'")
    finally:
        s.close()
        quit_app("SettingsApp")


@check("control center: quick tiles drive the settings they mirror")
def check_control_center() -> None:
    """Opens the panel from the broker-reported icon, taps the Dark Mode and
    Tiling tiles at the centers the shell serves, and asserts against the
    same state the Settings panes read — the tile IS the setting. Mute is
    asserted when PipeWire answers; wifi only ever on machines with a
    managed radio, so the tile's no-op path is what most boxes exercise."""
    cc = lambda: ask("control_center_state")
    s = cc()
    assert not s["open"], "the control center is already open"

    drive(f"click {s['icon']['x']:.0f} {s['icon']['y']:.0f}")
    wait_for(lambda: cc()["open"], "the panel to open")
    tiles = {t["id"]: t for t in cc()["tiles"]}

    dark = cc()["dark"]
    drive(f"click {tiles['dark']['x']:.0f} {tiles['dark']['y']:.0f}")
    wait_for(lambda: cc()["dark"] != dark, "Dark Mode to flip")
    drive(f"click {tiles['dark']['x']:.0f} {tiles['dark']['y']:.0f}")
    wait_for(lambda: cc()["dark"] == dark, "Dark Mode to flip back")

    tiling = cc()["tiling"]
    drive(f"click {tiles['tiling']['x']:.0f} {tiles['tiling']['y']:.0f}")
    wait_for(lambda: cc()["tiling"] != tiling, "Tiling to flip")
    drive(f"click {tiles['tiling']['x']:.0f} {tiles['tiling']['y']:.0f}")
    wait_for(lambda: cc()["tiling"] == tiling, "Tiling to flip back")

    if cc()["audio_available"]:
        muted = cc()["muted"]
        drive(f"click {tiles['mute']['x']:.0f} {tiles['mute']['y']:.0f}")
        wait_for(lambda: cc()["muted"] != muted, "Mute to flip")
        drive(f"click {tiles['mute']['x']:.0f} {tiles['mute']['y']:.0f}")
        wait_for(lambda: cc()["muted"] == muted, "Mute to flip back")
        log("dark, tiling and mute all round-tripped")
    else:
        log("dark and tiling round-tripped (no audio on this machine)")

    drive("key esc")
    wait_for(lambda: not cc()["open"], "esc to close the panel")


@check("recording: the record tile produces a playable MP4")
def check_recording() -> None:
    """Starts a recording from the control-center tile, waits for the state
    machine to reach `recording` — which only happens once a frame has gone
    all the way through capture, the mailbox, the pacer and into ffmpeg —
    stops it from the tile, and ffprobes the file the shell says it saved.
    Skips without ffmpeg (the .deb Recommends it; a dev box may not)."""
    rec = lambda: ask("recording_state")
    r = rec()
    if not r["available"]:
        raise Skip("no ffmpeg on this machine")
    assert r["state"] == "idle", f"a recording is already {r['state']}"

    cc = lambda: ask("control_center_state")
    try:
        drive(f"click {cc()['icon']['x']:.0f} {cc()['icon']['y']:.0f}")
        wait_for(lambda: cc()["open"], "the panel to open")
        tiles = {t["id"]: t for t in cc()["tiles"]}
        drive(f"click {tiles['record']['x']:.0f} {tiles['record']['y']:.0f}")
        wait_for(lambda: rec()["state"] == "recording",
                 "the first frame to reach ffmpeg")
        time.sleep(2)  # a couple of seconds of real desktop
        assert rec()["elapsed_s"] >= 1, "the elapsed clock is not advancing"

        drive(f"click {cc()['icon']['x']:.0f} {cc()['icon']['y']:.0f}")
        wait_for(lambda: cc()["open"], "the panel to reopen")
        drive(f"click {tiles['record']['x']:.0f} {tiles['record']['y']:.0f}")
        wait_for(lambda: rec()["state"] == "idle", "the encode to finalize")
        drive("key esc")
    finally:
        if rec()["state"] not in ("idle", "stopping"):
            drive("key ctrl+shift+r")  # don't leave a session recording

    path = rec()["last_file"]
    assert path, "the shell reports no saved file"
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=codec_name,width,height",
         "-of", "csv=p=0", path],
        capture_output=True, text=True)
    try:
        assert probe.returncode == 0, f"ffprobe rejects {path}: {probe.stderr}"
        codec, w, h = probe.stdout.strip().split(",")[:3]
        assert codec == "h264", f"expected h264, got {codec}"
        # The file must match the shell's own claim about the session
        # (full-res through VAAPI, half-res through the x264 fallback on
        # big screens — the claim is the policy's output, the file is the
        # ground truth, and this is the two of them agreeing). ±1 for the
        # even-dimension crop.
        r = rec()
        assert abs(int(w) - r["capture_w"]) <= 1 \
            and abs(int(h) - r["capture_h"]) <= 1, \
            f"recorded {w}x{h}, shell claims {r['capture_w']}x{r['capture_h']}"
        # And the claim itself must be the screen or exactly half of it.
        pw, ph = ask("screen")["physical"]
        assert any(abs(r["capture_w"] - pw / d) <= 1
                   and abs(r["capture_h"] - ph / d) <= 1 for d in (1, 2)), \
            f"capture {r['capture_w']}x{r['capture_h']} is neither " \
            f"{pw:.0f}x{ph:.0f} nor half of it"
        # Every frame must actually DECODE. ffprobe reading the container's
        # headers is not evidence of that: a bitstream whose slices are
        # malformed still reports the right codec, size and frame count, and
        # ffmpeg still emits pictures for it — so this check once passed a
        # recorder that was corrupting every P-frame.
        #
        # Match decode failures specifically rather than "stderr said
        # anything". ffmpeg's null muxer also warns about non-monotonic dts
        # in ITS OWN output stream, which a variable-rate screen capture
        # provokes on any encoder — the libav one this replaced does it too.
        # That is noise here; the file's own timestamps are checked below.
        decode = subprocess.run(
            ["ffmpeg", "-threads", "1", "-v", "error", "-i", path, "-f", "null", "-"],
            capture_output=True, text=True)
        bad = [ln for ln in decode.stderr.splitlines()
               if "error while decoding" in ln or "Invalid data" in ln
               or "no frame" in ln or "corrupt" in ln.lower()]
        assert not bad, (
            f"{len(bad)} decode error(s) in the recording, first: {bad[0]}")

        # And the container's own timestamps must strictly increase — the
        # property the warning above is really about, asked of the file
        # rather than of ffmpeg's re-encode.
        pkts = subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "v:0",
             "-show_entries", "packet=dts", "-of", "csv=p=0", path],
            capture_output=True, text=True).stdout.split()
        dts = [int(x.rstrip(",")) for x in pkts if x.rstrip(",").lstrip("-").isdigit()]
        bad_dts = [i for i in range(1, len(dts)) if dts[i] <= dts[i - 1]]
        assert not bad_dts, (
            f"{len(bad_dts)} non-increasing dts in the file, first at packet "
            f"{bad_dts[0]}: {dts[bad_dts[0] - 1]} -> {dts[bad_dts[0]]}")

        enc = "zero-copy vaapi" if r.get("zero_copy") \
            else ("vaapi" if r["hardware"] else "x264")
        # Printed, not log()'d: which encoder ran is the difference between
        # "recording works" and "the encoder we changed was exercised", and
        # the VM gate runs without -v. A green gate that silently took the
        # pipe fallback is not coverage of the zero-copy path.
        print(f"        {codec} {w}x{h} via {enc}, "
              f"{os.path.getsize(path)} bytes, decodes clean")
    finally:
        # The tier must not grow the session user's Videos on every run.
        with contextlib.suppress(OSError):
            os.unlink(path)


@check("recording: Record App picks its window through Mission Control")
def check_record_app_picker() -> None:
    """The Record App tile opens Mission Control as a window picker — every
    window a live exposé card, clicking one records THAT window (its own
    texture, not a screen crop). Launches the calculator from the dock,
    picks it through the picker, and checks the session carries the
    window's label and lands a playable window-sized file."""
    rec = lambda: ask("recording_state")
    if not rec()["available"]:
        raise Skip("no ffmpeg on this machine")
    assert rec()["state"] == "idle", f"a recording is already {rec()['state']}"

    cc = lambda: ask("control_center_state")

    def open_picker() -> list:
        drive(f"click {cc()['icon']['x']:.0f} {cc()['icon']['y']:.0f}")
        wait_for(lambda: cc()["open"], "the panel to open")
        tiles = {t["id"]: t for t in cc()["tiles"]}
        drive(f"click {tiles['recordapp']['x']:.0f} {tiles['recordapp']['y']:.0f}")
        time.sleep(1.2)  # Mission Control's open animation settles
        return rec()["picker"]

    drive("dock calculator", "click")
    try:
        # The window needs a moment to map; each retry collapses whatever
        # the failed attempt left open (panel or picker) with Esc.
        targets: list = []
        deadline = time.time() + 25
        time.sleep(4)
        while not targets and time.time() < deadline:
            drive("key esc")
            targets = open_picker()
        assert targets, "the picker never offered a window card"
        card = next((t for t in targets if "alc" in t["title"]), targets[0])
        drive(f"click {card['x']:.0f} {card['y']:.0f}")
        wait_for(lambda: rec()["state"] == "recording",
                 "the picked window's first frame")
        label = rec()["window"]  # cleared at idle — read it live
        assert label, "the session carries no window label"
        time.sleep(2)
        drive("key ctrl+shift+r")
        wait_for(lambda: rec()["state"] == "idle", "the encode to finalize")
    finally:
        if rec()["state"] not in ("idle", "stopping"):
            drive("key ctrl+shift+r")
        subprocess.run(["pkill", "-x", "CalculatorApp"], capture_output=True)

    path = rec()["last_file"]
    assert path and "(" in os.path.basename(path), \
        f"expected a window-labelled file, got {path!r}"
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "stream=codec_name,width,height",
         "-of", "csv=p=0", path],
        capture_output=True, text=True)
    try:
        assert probe.returncode == 0, f"ffprobe rejects {path}: {probe.stderr}"
        codec, w, h = probe.stdout.strip().split(",")[:3]
        assert codec == "h264", f"expected h264, got {codec}"
        # A window capture, not a screen crop: far smaller than the screen.
        pw, ph = ask("screen")["physical"]
        assert int(w) < pw and int(h) < ph, \
            f"recorded {w}x{h} does not look like a window on {pw}x{ph}"
        log(f"picked '{label}', {codec} {w}x{h}, "
            f"{os.path.getsize(path)} bytes")
    finally:
        with contextlib.suppress(OSError):
            os.unlink(path)


def _motion(path: str, sample_fps: int = 4) -> tuple[int, int, float]:
    """Sample a recording across its whole length and report how many
    consecutive sampled pairs actually differ. A file can be perfectly
    valid — right codec, right size, decodable — and still be a still
    image; only this catches that. Returns (moved, pairs, max_diff)."""
    with tempfile.TemporaryDirectory() as d:
        rc = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", path, "-vf", f"fps={sample_fps}",
             f"{d}/f%04d.png"], capture_output=True, text=True)
        assert rc.returncode == 0, f"ffmpeg could not decode {path}: {rc.stderr}"
        frames = sorted(Path(d).iterdir())
        assert len(frames) >= 3, f"only {len(frames)} frames sampled from {path}"
        # Mean absolute difference per pair, computed without numpy/PIL:
        # ffmpeg's own signalstats would need a filter build, so compare the
        # raw PNG bytes decoded to grayscale via ffmpeg one pair at a time.
        diffs = []
        for a, b in zip(frames, frames[1:]):
            out = subprocess.run(
                ["ffmpeg", "-v", "error", "-i", str(a), "-i", str(b),
                 "-filter_complex", "blend=all_mode=difference,signalstats,"
                 "metadata=print:key=lavfi.signalstats.YAVG:file=-",
                 "-f", "null", "-"], capture_output=True, text=True)
            val = 0.0
            for line in out.stdout.splitlines():
                if "YAVG" in line:
                    val = float(line.rsplit("=", 1)[1])
            diffs.append(val)
        moved = sum(1 for v in diffs if v > 0.5)
        return moved, len(diffs), max(diffs)


@check("recording: the footage actually moves")
def check_recording_motion() -> None:
    """A recording of a changing screen must contain changing frames. This
    is the check that a frozen or barely-ticking capture fails: the earlier
    checks all pass on a still image, which is exactly how a capture bug
    once shipped looking green. Drives continuously-changing content (a
    terminal streaming random hex), records the screen, and requires most
    sampled pairs to differ."""
    rec = lambda: ask("recording_state")
    if not rec()["available"]:
        raise Skip("no ffmpeg on this machine")
    assert rec()["state"] == "idle", f"a recording is already {rec()['state']}"

    drive("dock terminal", "click")
    # Wait for the process, not a fixed sleep: after the checks above have
    # opened and killed apps of their own, a freshly clicked dock icon can
    # take noticeably longer to map than on an idle desktop.
    wait_for(lambda: subprocess.run(["pgrep", "-x", "TerminalApp"],
                                    capture_output=True).returncode == 0,
             "the terminal process")
    time.sleep(4)

    # Random hex: every line differs, so a repeated frame is unambiguous.
    flood = "while true; do head -c 1200 /dev/urandom | xxd | head -30; done"

    def flooding() -> bool:
        """Is the terminal actually churning?

        Not `pgrep xxd`: each iteration is `head -c 1200 | xxd | head -30`,
        which lives for microseconds — sampled 40 times across a running
        flood it matched ZERO times, so it reports "no flood" while the
        screen scrolls. Measure the terminal's own CPU instead. Idle it is
        ~0 ticks; rendering the flood it was ~25 ticks/s on the dev box and
        stays far above the threshold on a slow VM.
        """
        pids = subprocess.run(["pgrep", "-x", "TerminalApp"],
                              capture_output=True, text=True).stdout.split()
        if not pids:
            return False
        def ticks() -> int:
            try:
                parts = open(f"/proc/{pids[0]}/stat").read().rsplit(") ", 1)[1].split()
                return int(parts[11]) + int(parts[12])
            except (OSError, IndexError):
                return -1
        a = ticks()
        if a < 0:
            return False
        time.sleep(0.8)
        b = ticks()
        return b >= 0 and (b - a) >= 3

    # And CONFIRM it started. Keystrokes go to whatever holds focus, and a
    # window that has mapped does not always hold it yet — when the typing
    # landed in the void the screen stayed still, the recording was of a
    # motionless desktop, and this check blamed the recorder. That failure
    # was intermittent on a slow machine and unreproducible on a fast one.
    # Retry the line rather than race it, and say plainly which half broke.
    for _ in range(3):
        drive(f"type {flood}")
        drive("key enter")
        if flooding():
            break
    assert flooding(), (
        "the terminal is idle after three attempts to start the flood — the "
        "typed line never ran, so there is nothing moving to record and the "
        "motion assertion below would blame the recorder for it")
    time.sleep(3)
    try:
        drive("key ctrl+shift+r")
        wait_for(lambda: rec()["state"] == "recording", "the first frame")
        time.sleep(8)
        drive("key ctrl+shift+r")
        wait_for(lambda: rec()["state"] == "idle", "the encode to finalize")
    finally:
        if rec()["state"] not in ("idle", "stopping"):
            drive("key ctrl+shift+r")
        drive("key ctrl+c")  # stop the flood
        subprocess.run(["pkill", "-x", "TerminalApp"], capture_output=True)

    path = rec()["last_file"]
    assert path, "the shell reports no saved file"
    try:
        moved, pairs, peak = _motion(path)
        # The desktop cannot always hit the sample rate, but a recording of
        # a continuously-changing screen must be moving most of the time.
        assert moved >= pairs * 0.6, (
            f"only {moved}/{pairs} sampled pairs differ (peak {peak:.1f}) — "
            f"the recording is frozen or badly under-sampling motion")
        dur = float(subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "csv=p=0", path], capture_output=True, text=True).stdout)
        nframes = len(subprocess.run(
            ["ffprobe", "-v", "error", "-select_streams", "v:0",
             "-show_entries", "packet=pts_time", "-of", "csv=p=0", path],
            capture_output=True, text=True).stdout.split())
        fps = nframes / dur if dur else 0
        assert fps >= 12, f"recorded at {fps:.1f}fps — too choppy to watch"
        log(f"{moved}/{pairs} pairs moving, {fps:.1f}fps, peak diff {peak:.1f}")
    finally:
        with contextlib.suppress(OSError):
            os.unlink(path)


def _yavg(*ffmpeg_args: str) -> list[float]:
    """Run an ffmpeg graph ending in signalstats and return the YAVG series.

    Same tooling `_motion` settled on and for the same reason: no numpy, no
    PIL, nothing to install in a VM whose whole point is being a clean machine.
    """
    out = subprocess.run(["ffmpeg", "-v", "error", *ffmpeg_args,
                          "-f", "null", "-"], capture_output=True, text=True)
    return [float(line.rsplit("=", 1)[1])
            for line in out.stdout.splitlines() if "YAVG" in line]


_PRINT = "metadata=print:key=lavfi.signalstats.YAVG:file=-"


def _png_diff(a: str, b: str) -> float:
    """Mean absolute difference between two stills, 0 = identical."""
    vals = _yavg("-i", a, "-i", b, "-filter_complex",
                 f"blend=all_mode=difference,signalstats,{_PRINT}")
    assert vals, f"could not compare {a} and {b}"
    return vals[0]


def _detail(path: str, sample_fps: int = 2) -> float:
    """Mean edge energy across a recording — a scale-sensitive summary.

    Magnifying content puts the same features across more pixels, so edges per
    unit area drop: a 2x take of one screen scores markedly lower than the wide
    take of the same screen. That is a property of the CONTENT, which is what
    makes it usable here — it needs no baseline image, so it does not rot the
    way a screenshot suite does, and it compares a recording only against
    another recording made seconds earlier of the same still desktop.
    """
    vals = _yavg("-i", path, "-vf",
                 f"fps={sample_fps},edgedetect=low=0.1:high=0.3,signalstats,{_PRINT}")
    assert len(vals) >= 2, f"only {len(vals)} frames sampled from {path}"
    return sum(vals) / len(vals)


@check("recording: Ctrl+Shift+= zooms the take and not the screen")
def check_recording_zoom() -> None:
    """The zoom is deliberately invisible: it crops what the encoder sees, so
    the room watching the presenter's screen sees nothing happen while the
    take comes out magnified. Both halves of that are assertions, and they
    fail in opposite directions — a zoom that moved the screen would be the
    feature not working, and a zoom that changed nothing in the file would be
    it not working either. Neither is visible from the shell's own state:
    `recording_state` publishes elapsed time and capture size but no zoom
    level, and the capture size is the framebuffer rather than the crop.

    So this records the same still desktop twice, wide and at 2x, and compares
    the two files' edge density. Nothing is compared against a stored
    baseline; the reference is a recording made seconds earlier of the same
    screen.
    """
    rec = lambda: ask("recording_state")
    if not rec()["available"]:
        raise Skip("no ffmpeg on this machine")
    assert rec()["state"] == "idle", f"a recording is already {rec()['state']}"

    # Still, dense, high-contrast content: edge density is the measure, so the
    # screen needs detail to have any, and it must not move or the two takes
    # differ for reasons that have nothing to do with the crop.
    drive("dock terminal", "click")
    wait_for(lambda: proc_running("TerminalApp"), "the terminal process")
    time.sleep(4)
    drive("type seq 1 400 | paste - - - - - -")
    drive("key enter")
    time.sleep(3)

    shots: list[str] = []

    def take(seconds: float, zoom_steps: int) -> str:
        """Record the desktop, optionally zooming in `zoom_steps` first."""
        drive("key ctrl+shift+r")
        wait_for(lambda: rec()["state"] == "recording", "the first frame")
        try:
            for _ in range(zoom_steps):
                # Only honoured while recording, which is why it is in here.
                drive("key ctrl+shift+=")
                time.sleep(0.4)
            # The crop eases toward its target rather than snapping, so give
            # it time to arrive before the frames that will be measured.
            time.sleep(1.5)
            shot = tempfile.mktemp(suffix=".png")
            drive(f"shot {shot}")
            shots.append(shot)
            # The tier runs the shell with a 15 s screensaver idle, and the
            # saver swallows whatever key wakes it — which was the stop chord
            # below, so the recording never ended and the screencast check
            # after this one found the engine's capture still taken. A lone
            # Shift every few seconds keeps the desktop awake without moving
            # the pointer, which the zoom crop follows.
            left = seconds
            while left > 0:
                time.sleep(min(8.0, left))
                left -= 8.0
                if left > 0:
                    drive("key shift")
        finally:
            # Wake first if the saver did come up; a lone Shift is harmless
            # to the terminal underneath if it did not.
            drive("key shift", "sleep 0.3", "key ctrl+shift+r")
            wait_for(lambda: rec()["state"] == "idle", "the encode to finalize")
        path = rec()["last_file"]
        assert path, "the shell reports no saved file"
        return path

    wide = zoomed = None
    try:
        wide = take(5, zoom_steps=0)
        # Two steps: 1.0 -> 1.5 -> 2.0. The 2x step is the one worth pinning,
        # because on a 4K panel it is the 1:1 crop the feature exists for.
        zoomed = take(5, zoom_steps=2)

        # 1. The screen did not move. Both stills are of the same still
        #    desktop, one taken while zoomed 2x — if the zoom leaked onto the
        #    screen this is where it shows.
        moved = _png_diff(shots[0], shots[1])
        assert moved < 2.0, (
            f"the desktop changed by {moved:.1f} between the wide and zoomed "
            "takes — the recording zoom is supposed to be invisible on screen")
        log(f"screen unchanged while zoomed (diff {moved:.2f})")

        # 2. The take is magnified. Same screen, so a lower edge density can
        #    only come from the crop.
        d_wide, d_zoom = _detail(wide), _detail(zoomed)
        assert d_wide > 0, "the wide take has no detail to compare against"
        ratio = d_zoom / d_wide
        assert ratio < 0.8, (
            f"edge density barely moved ({d_zoom:.2f} zoomed vs {d_wide:.2f} "
            f"wide, ratio {ratio:.2f}) — the take does not look magnified, so "
            "Ctrl+Shift+= did not crop what the encoder sees")
        log(f"zoomed take is magnified (edge density ratio {ratio:.2f})")
    finally:
        if rec()["state"] not in ("idle", "stopping"):
            drive("key ctrl+shift+r")
        drive("key ctrl+c")
        quit_app("TerminalApp")
        for p in shots + [wide, zoomed]:
            if p:
                with contextlib.suppress(OSError):
                    os.unlink(p)


def _child_environ(pid: str) -> dict[str, str]:
    try:
        raw = open(f"/proc/{pid}/environ", "rb").read()
    except OSError:
        return {}
    out = {}
    for item in raw.split(b"\0"):
        if b"=" in item:
            k, v = item.split(b"=", 1)
            out[k.decode(errors="replace")] = v.decode(errors="replace")
    return out


@check("gpu: an app whose record says Gpu=discrete is launched onto it")
def check_prime_offload() -> None:
    """Per-app PRIME offload, end to end through the shell.

    The policy is one key in a registry record and the mechanism is entirely
    in app-run.sh, with the shell doing nothing but putting STARLING_APP_GPU
    in the child's environment when the record asks and a discrete GPU is
    actually present. Every link in that is an exact string match that fails
    silently — the app launches, renders on the integrated GPU, and nothing
    anywhere says why (test/lint.py compares the literals for that reason).
    This asserts the runtime half the lint cannot see: that the variable
    really reaches the process.

    The fixture is chrome.app with one key added, so the control is exact —
    launch both records and the only thing that can explain a difference in
    the child's environment is `Gpu=discrete` itself.
    """
    if len(glob.glob("/dev/dri/renderD*")) < 2:
        raise Skip("one render node — no discrete GPU to offload onto")
    # Ask the SHELL whether it loaded the fixture, not the disk. `CATALOG`
    # resolves the repo's real catalog.d first and only falls back to
    # STARLING_CATALOG_DIR when that is absent (it exists for the VM, where
    # there is no repo) — so in a dev-tree run it never names the fixture
    # directory the shell was actually given, and a path check here skips
    # with a reason that is the exact opposite of the truth. That is how the
    # first run of this check reported "fixture catalog not in use" while
    # running under test/functional.sh, which is the only thing that puts it
    # in use. `apps()` is the shell's own view and cannot disagree with it.
    installed = apps().get("starlingprime")
    if installed is None:
        raise Skip("fixture catalog not in use (run via test/functional.sh)")
    if not installed.get("installed"):
        raise Skip("Chrome is not installed — the fixture borrows its binary")

    def launch_and_read(app_id: str) -> dict[str, str]:
        """Launch through the shell and read the child's environment.

        Through the SHELL on purpose: the broker's launch op only serves a
        fixed table of first-party apps, and calling app-run directly would
        skip the very decision under test — it is the shell that reads the
        record and decides whether to set the variable at all.
        """
        before = set(subprocess.run(["pgrep", "-f", "/opt/google/chrome"],
                                    capture_output=True, text=True).stdout.split())
        drive("move 300 300", "dock launcher", "click")
        wait_for(lambda: ask("launcher_state")["open"], "Launchpad to open")
        try:
            drive(f"type {installed['name'] if app_id == 'starlingprime' else 'Chrome'}")
            wait_for(lambda: ask("launcher_state")["filtered"] == [app_id],
                     f"the Launchpad to filter to {app_id}")
            drive("key enter")
        finally:
            with contextlib.suppress(Exception):
                if ask("launcher_state")["open"]:
                    drive("key esc")

        def fresh() -> str | None:
            now = set(subprocess.run(["pgrep", "-f", "/opt/google/chrome"],
                                     capture_output=True, text=True).stdout.split())
            new = now - before
            return next(iter(new)) if new else None

        wait_for(fresh, f"{app_id} to start a process")
        return _child_environ(fresh())

    try:
        env = launch_and_read("starlingprime")
        assert env.get("STARLING_APP_GPU") == "discrete", (
            "the shell did not put STARLING_APP_GPU=discrete in the child's "
            f"environment for a record carrying Gpu=discrete (got "
            f"{env.get('STARLING_APP_GPU')!r}) — the app is on the integrated GPU")
        # app-run's half: the preference translated into the vendor knobs.
        # Asserted separately because the two fail independently, and a shell
        # that sets the variable into a launcher that ignores it looks exactly
        # like a machine with no discrete GPU.
        assert env.get("DRI_PRIME") == "1", (
            f"STARLING_APP_GPU arrived but DRI_PRIME did not (got "
            f"{env.get('DRI_PRIME')!r}) — app-run did not translate the preference")
        log("Gpu=discrete reaches the child as STARLING_APP_GPU + DRI_PRIME")
        quit_app("chrome")
        time.sleep(2)

        # The control: the same binary, the same recipe, no Gpu= key. Without
        # this the check above would also pass if the shell handed every app
        # the discrete GPU, which is a different bug with the same green tick.
        plain = launch_and_read("chrome")
        assert "STARLING_APP_GPU" not in plain, (
            "a record with no Gpu= key was still launched onto the discrete "
            "GPU — the offload is not per-app at all")
        log("a record without Gpu= is left on the integrated GPU")
    finally:
        quit_app("chrome")


@check("screencast: the portal serves a live PipeWire stream")
def check_screencast() -> None:
    """org.freedesktop.portal.ScreenCast end to end minus the browser: the
    session handshake on one connection, a Start whose response carries a
    PipeWire node, and real frames pulled off that node — the interface
    Chromium's getDisplayMedia and OBS ride on Wayland. Frames are pulled
    twice: a count proves the stream flows, a PNG snapshot proves it
    carries the desktop rather than black."""
    uid = int(os.environ.get("SUDO_UID", os.getuid()))
    pw_dir = f"/run/user/{uid}"
    if not os.path.exists(f"{pw_dir}/pipewire-0"):
        raise Skip("no PipeWire daemon for the session user")
    try:
        import gi  # noqa: F401
    except ImportError:
        raise Skip("python3-gi not installed")
    if not shutil.which("gst-launch-1.0"):
        raise Skip("gstreamer not installed")

    def as_user(cmd: list, **kw):
        user = os.environ.get("SUDO_USER")
        if os.geteuid() == 0 and user:
            cmd = ["sudo", "-u", user, "env", f"PIPEWIRE_RUNTIME_DIR={pw_dir}"] + cmd
        return subprocess.run(cmd, capture_output=True, text=True, **kw)

    bus = os.path.dirname(broker_path()) + "/bus"
    r = as_user([sys.executable,
                 str(Path(__file__).parent / "screencast_client.py"),
                 f"unix:path={bus}"], timeout=30)
    assert r.returncode == 0, f"portal handshake failed: {r.stderr.strip()}"
    info = json.loads(r.stdout)
    node, w, h = info["node"], info["width"], info["height"]
    assert node > 0 and w > 0 and h > 0, f"bad stream: {info}"
    log(f"stream node {node} ({w}x{h})")

    # gst pulls by NODE NAME, not the id: pipewiresrc's path/target-object
    # resolve against the object *serial*, which only coincidentally equals
    # the id (it did once, which made this flaky instead of red). The id in
    # the Start response stays the contract for real consumers — webrtc
    # passes it straight to pw_stream_connect, which does take ids. The
    # stream-properties inject the media.type gst omits and without which
    # this distro's WirePlumber linking scripts crash ("Constraint:
    # equals: expected constraint value") and no link is ever made.
    gst_src = ["pipewiresrc", "target-object=starling-screencast",
               "stream-properties=props,media.type=Video,"
               "media.category=Capture,media.role=Screen"]
    try:
        pull = as_user(["gst-launch-1.0", "-q"] + gst_src +
                       ["num-buffers=5", "!", "fakesink"], timeout=30)
        assert pull.returncode == 0, \
            f"no frames from node {node}: {pull.stderr.strip()}"
        with tempfile.TemporaryDirectory() as d:
            # The tier runs as root but gst runs as the session user, who
            # must be able to create the file in this directory.
            os.chmod(d, 0o777)
            png = f"{d}/frame.png"
            snap = as_user(["gst-launch-1.0", "-q"] + gst_src +
                           ["num-buffers=1", "!",
                            "videoconvert", "!", "pngenc", "!",
                            "filesink", f"location={png}"], timeout=30)
            assert snap.returncode == 0, f"snapshot failed: {snap.stderr.strip()}"
            size = os.path.getsize(png)
            # A black 1080p frame zips into a few KB of PNG; the desktop
            # (wallpaper, dock, glass) cannot.
            assert size > 30000, f"snapshot is {size}B of PNG — a blank stream"
            log(f"5 buffers pulled, snapshot {size} bytes")
    finally:
        session_busctl("call", "org.freedesktop.portal.Desktop", info["session"],
                       "org.freedesktop.portal.Session", "Close")


# ── clipboard ────────────────────────────────────────────────────────────────
#
# One selection for the whole desktop (docs/plans/clipboard.md). Two halves that
# fail independently and must both be covered:
#
#   * first-party apps reach the system selection at all — they used to keep
#     their own clipboard in a file, shared with nobody;
#   * a third-party wl_data_device client (Chrome, Electron, GTK) can read a
#     selection that PREDATES it. That one shipped broken: the compositor only
#     ever broadcast on change, so copying and then launching a browser left
#     the browser's clipboard empty until somebody copied again.
#
# Asserted by round-tripping text, never by reading pixels. Where a paste has to
# be proved, the app is seeded with a marker first and the result copied back
# out — otherwise a paste that silently did nothing looks identical to a pass,
# because the editor refuses to copy an empty selection and the old value is
# still on the clipboard.

CLIP_MARK = "starling-clip-check"


def _wl_env() -> dict:
    """XDG_RUNTIME_DIR + WAYLAND_DISPLAY for the session under test.

    The socket name is not fixed: an unclean exit leaves wayland-0.lock behind
    and the next run listens on wayland-1, so it is discovered, never assumed.
    """
    rundir = os.path.dirname(broker_path())
    socks = sorted(p for p in glob.glob(os.path.join(rundir, "wayland-*"))
                   if not p.endswith(".lock"))
    if not socks:
        raise Skip(f"no wayland socket in {rundir}")
    return dict(os.environ, XDG_RUNTIME_DIR=rundir,
                WAYLAND_DISPLAY=os.path.basename(socks[0]))


def _need_wl_clipboard() -> None:
    if not (shutil.which("wl-copy") and shutil.which("wl-paste")):
        raise Skip("wl-clipboard not installed (apt install wl-clipboard)")


def wl_paste(timeout: float = 10) -> str:
    r = subprocess.run(["wl-paste", "-n"], env=_wl_env(), capture_output=True,
                       text=True, timeout=timeout)
    return r.stdout if r.returncode == 0 else ""


@contextlib.contextmanager
def wl_copy(text: str):
    """Own the selection for the body of the block.

    wl-copy stays resident to serve the data, and it inherits our stdout — so
    it is given DEVNULL, or a pipeline waiting on EOF hangs on a process that
    is behaving perfectly.
    """
    p = subprocess.Popen(["wl-copy", text], env=_wl_env(),
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(1.0)   # let it bind and take the selection
        yield p
    finally:
        p.kill()
        p.wait(timeout=5)


def _editor_session():
    """Launch the Text Editor and put the caret in its text area."""
    assert not apps()["editor"]["window"], "Text Editor already running"
    drive("move 300 300", "dock editor", "click")
    wait_for(lambda: apps()["editor"]["window"], "Text Editor window")
    time.sleep(3)                      # first frame + engine warm-up
    drive("click 900 500")             # caret into the document
    time.sleep(1)


def _close_editor():
    """Quit and wait for the SHELL to drop the window.

    pkill returning is not enough: the next check asserts the editor is not
    running, and the shell learns of the exit on its own tick. Without this the
    checks pass or fail depending on which one ran first.
    """
    quit_app("TextEditorApp")
    wait_for(lambda: not apps()["editor"]["window"], "Text Editor to close")


@check("clipboard: a copy in a first-party app reaches the whole desktop")
def check_clipboard_app_to_desktop() -> None:
    _need_wl_clipboard()
    text = f"{CLIP_MARK}-out"
    _editor_session()
    try:
        drive("key ctrl+a", "key backspace", f"type {text}",
              "key ctrl+a", "key ctrl+c")
        time.sleep(2)
        got = wl_paste()
        assert got == text, f"desktop sees {got!r}, editor copied {text!r}"
        log(f"editor copy readable desktop-wide: {got!r}")
    finally:
        _close_editor()


@check("clipboard: a copy made outside pastes into a first-party app")
def check_clipboard_desktop_to_app() -> None:
    _need_wl_clipboard()
    seed, pasted = f"{CLIP_MARK}-seed-", "OUTSIDE"
    _editor_session()
    try:
        drive("key ctrl+a", "key backspace", f"type {seed}")
        time.sleep(1)
        with wl_copy(pasted):
            drive("key ctrl+v")
            time.sleep(2)
        # Copy the document back out: the only way to see what landed without
        # asserting on pixels. Seeding is what makes this honest — with an
        # empty document a failed paste would leave `pasted` on the clipboard
        # and read back as a pass.
        drive("key ctrl+a", "key ctrl+c")
        time.sleep(2)
        got = wl_paste()
        assert got == seed + pasted, \
            f"editor holds {got!r}, expected {seed + pasted!r}"
        log(f"outside copy landed in the editor: {got!r}")
    finally:
        _close_editor()


@check("clipboard: a client started AFTER a copy still sees it")
def check_clipboard_predates_client() -> None:
    """The regression test for a bug that shipped.

    wl_data_device is focus-based and the compositor only broadcast on change,
    so a client that started after the copy never learned about the selection.
    In practice: copy a URL, then launch Chrome, and Chrome pasted nothing.

    A GTK3 client stands in for Chrome — same protocol. It needs a real pointer
    interaction before the offer arrives, because keyboard focus here is lazy
    (sent from the first keystroke) and the compositor hands the selection over
    on pointer enter.
    """
    _need_wl_clipboard()
    probe = Path(__file__).parent / "clipboard_gtk_client.py"
    if not probe.exists():
        raise Skip(f"{probe.name} missing")
    r = subprocess.run([sys.executable, str(probe), "--check-gtk"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise Skip("python3-gi with Gtk 3.0 not available")

    text = f"{CLIP_MARK}-predates"
    with wl_copy(text):
        # Only NOW start the reader, so the selection genuinely predates it.
        proc = subprocess.Popen([sys.executable, str(probe), "--read"],
                                env=_wl_env(), stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, text=True)
        try:
            time.sleep(4)                      # window mapped and composited
            drive("move 700 400", "click 900 500")   # pointer enter + focus
            out, _ = proc.communicate(timeout=25)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=5)
    got = ""
    for line in out.splitlines():
        if line.startswith("GOT:"):
            got = line[4:]
    assert got == text, (
        f"a wl_data_device client started after the copy read {got!r}, "
        f"expected {text!r} — the selection is not being offered on interaction")
    log(f"client started after the copy read it: {got!r}")


@check("clipboard: a frozen selection owner cannot wedge the desktop")
def check_clipboard_frozen_owner() -> None:
    """Wayland clipboard is pull-based: a paste waits on the CURRENT OWNER to
    write. This is the failure the whole design is shaped around — brokered
    through the compositor's event loop, a stopped owner would freeze every
    window on the desktop rather than one app.

    The paste is expected to come back empty. What must not happen is a hang.
    """
    _need_wl_clipboard()
    _editor_session()
    try:
        with wl_copy(f"{CLIP_MARK}-frozen") as owner:
            owner.send_signal(signal.SIGSTOP)
            try:
                start = time.time()
                drive("key ctrl+a", "key backspace", "key ctrl+v")
                time.sleep(4)
                # The shell still answers its broker, and still lays the dock
                # out — i.e. it is dispatching, not blocked on a clipboard fd.
                assert apps()["editor"]["window"], "shell lost the editor window"
                assert dock(), "shell stopped reporting a dock layout"
                elapsed = time.time() - start
                assert elapsed < 20, f"paste path took {elapsed:.0f}s"
                log(f"desktop still live with the owner frozen ({elapsed:.0f}s)")
            finally:
                owner.send_signal(signal.SIGCONT)
        # And it recovers: a fresh copy pastes normally again.
        with wl_copy(f"{CLIP_MARK}-after"):
            drive("key ctrl+a", "key backspace", "key ctrl+v")
            time.sleep(2)
        drive("key ctrl+a", "key ctrl+c")
        time.sleep(2)
        assert wl_paste() == f"{CLIP_MARK}-after", "paste did not recover"
        log("paste recovers once the owner resumes")
    finally:
        _close_editor()


@check("terminal: the glyphs paint, and on the grid")
def check_glyph_pixels() -> None:
    """The one check here that reads PIXELS, and the reasons it is not a
    screenshot suite are in test/glyph-pixels.py.

    Nothing else in this tree looks at what the terminal drew. The grid is
    compared by the core's conformance suite and the differential battery, and
    the grid has been right through every one of these: a codepoint no loaded
    face carries paints nothing, a run downstream of a backwards font fallback
    paints nothing, a cell background painted by the text engine stops short of
    its cell, and a row placed by the shaper walks its glyphs off their
    columns. Four failures, all shipped, all found by a person looking at a
    screen — and the benchmark scored every one of them as an improvement,
    because not painting is cheaper than painting.

    There is no stored image. The terminal paints a ruler — a row of cells with
    alternating background colours — so the cell grid is measured from the same
    frame as the glyphs, and the assertions relate two things inside that one
    screenshot. A theme change or a new font re-derives it rather than
    invalidating it.
    """
    gate = REPO / "test/glyph-pixels.py"
    if not gate.exists():
        raise Skip("test/glyph-pixels.py is not in this tree (VM run)")
    r = subprocess.run([sys.executable, str(gate)],
                       capture_output=True, text=True)
    if r.returncode:
        # The report is the finding: it names the row, the glyph and the group
        # that draws with it. Passing only "exit 1" up would throw that away.
        detail = "\n        ".join(
            l for l in (r.stdout + r.stderr).splitlines()
            if l.strip() and "Warning" not in l)
        raise AssertionError(detail)
    for line in r.stdout.splitlines():
        log(line)


CHECKS = [v for v in dict(globals()).values()
          if callable(v) and hasattr(v, "_check_name")]


def pin_macos_style() -> str | None:
    """Put the desktop in the macOS style for the run, and say what it was.

    Every check here but `check_desktop_style` drives the macOS chrome — the
    menu bar's status items, the dock's slots — and those surfaces do not
    exist in the Fluent style. Without this the suite's result depends on
    which style the box happened to be left in, which is how the control
    centre check started failing on a desktop that was working perfectly.

    Restored in `main`, so a run leaves the desktop as it found it.
    """
    style_file = Path(session_home()) / ".config/starling/style"
    try:
        was = style_file.read_text().strip()
    except OSError:
        was = "macos"
    if was == "macos":
        return None
    s, win = settings_window()
    try:
        tap_label(s, win, "Appearance")
        tap_label(s, win, "macOS")
        wait_for(lambda: style_file.read_text().strip() == "macos",
                 "the desktop to return to the macOS style")
    finally:
        s.close()
        quit_app("SettingsApp")
    return was


def restore_style(was: str | None) -> None:
    if was is None:
        return
    style_file = Path(session_home()) / ".config/starling/style"
    s, win = settings_window()
    try:
        tap_label(s, win, "Appearance")
        tap_label(s, win, "Windows" if was == "fluent" else "macOS")
        wait_for(lambda: style_file.read_text().strip() == was,
                 f"the desktop to go back to the {was} style")
    finally:
        s.close()
        quit_app("SettingsApp")


def main() -> int:
    if os.geteuid() != 0:
        print("note: not root — the dock-click check needs /dev/uinput\n")
    print("starling functional tests")
    entry_style = None
    try:
        entry_style = pin_macos_style()
        if entry_style:
            print(f"  note  desktop was in the {entry_style} style; "
                  "pinned to macOS for the run")
    except Exception as exc:  # noqa: BLE001
        print(f"  note  could not pin the style ({exc}) — "
              "chrome-driving checks may fail")
    for fn in CHECKS:
        name = fn._check_name
        if ONLY and ONLY not in name:
            continue
        start = time.time()
        try:
            fn()
            results.append((name, "PASS", f"{time.time() - start:.1f}s"))
            print(f"  PASS  {name}  ({time.time() - start:.1f}s)")
        except Skip as why:
            results.append((name, "SKIP", str(why)))
            print(f"  SKIP  {name}\n        {why}")
        except Exception as exc:  # noqa: BLE001 - report, never abort the run
            results.append((name, "FAIL", str(exc)))
            print(f"  FAIL  {name}\n        {exc}")

    try:
        restore_style(entry_style)
    except Exception as exc:  # noqa: BLE001 - never turn cleanup into a failure
        print(f"  note  could not restore the {entry_style} style ({exc})")

    failed = [r for r in results if r[1] == "FAIL"]
    skipped = [r for r in results if r[1] == "SKIP"]
    print()
    tally = f"{len(results) - len(failed) - len(skipped)} passed"
    if skipped:
        tally += f", {len(skipped)} skipped"
    if failed:
        print(f"FAIL — {len(failed)} of {len(results)} check(s) ({tally})")
        return 1
    print(f"PASS — {tally}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
