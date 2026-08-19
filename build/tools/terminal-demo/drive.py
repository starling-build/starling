#!/usr/bin/env python3
"""Drive Starling Terminal through the demo, on macOS.

    build/tools/terminal-demo/drive.py --out DIR [--host user@box] [--ws demo]

Types, splits, opens a workspace, breaks the link and restarts the app, in one
scripted pass — and writes `beats.json` into DIR as it goes: one entry per
narrated moment, with the seconds it happened at. `captions.py` turns that into
subtitles, which is why the timing lives here rather than in a separate script
that would have to guess.

Recording is NOT started here. Run `screencapture` in the foreground beside it
(see docs/DEMO-TERMINAL.md) — a capture killed mid-write wedges the login's
ScreenCaptureKit layer until you log out, so it must not be at the mercy of
this script's exit path.

Everything it does is a real session: a real ssh workspace on a real host, a
real link break, a real relaunch. Nothing is staged.
"""
import argparse, json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))

ap = argparse.ArgumentParser()
ap.add_argument("--out", required=True, help="where beats.json and the built clicker go")
ap.add_argument("--app", default=f"{REPO}/.stage-macos/Starling Terminal.app/Contents/MacOS/TerminalApp")
ap.add_argument("--host", default="", help="ssh destination for the workspace beats; omit to skip them")
ap.add_argument("--ws", default="demo", help="workspace name on that host")
ap.add_argument("--remote-termd", default="", help="path to starling-termd ON THE REMOTE HOST")
ap.add_argument("--repo", default=REPO, help="a git checkout to show `git log` from, and to run claude in")
args = ap.parse_args()

os.makedirs(args.out, exist_ok=True)
CLICK = os.path.join(args.out, "click")
if not os.path.exists(CLICK):
    subprocess.run(["swiftc", "-O", "-o", CLICK, os.path.join(HERE, "click.swift")], check=True)

T0 = time.time()
BEATS = []


def osa(script):
    subprocess.run(["osascript", "-e", script], capture_output=True)


def beat(name):
    t = time.time() - T0
    BEATS.append({"t": round(t, 2), "text": name})
    print(f"[{t:6.2f}] {name}", flush=True)


def typed(text, cps=28):
    """Type with a human rhythm. One osascript call, not one per character —
    per-character invocations cost ~150 ms each and the rhythm goes ragged."""
    esc = text.replace("\\", "\\\\").replace('"', '\\"')
    osa(f'''tell application "System Events"
      repeat with c in characters of "{esc}"
        keystroke (c as text)
        delay {1.0 / cps:.3f}
      end repeat
    end tell''')


def enter():
    osa('tell application "System Events" to key code 36')


def chord(key, *mods):
    m = ", ".join(f"{x} down" for x in mods)
    osa(f'tell application "System Events" to keystroke "{key}" using {{{m}}}')


def clear_field(n=48):
    """Backspace a text field empty. The switcher PREFILLS the last host with
    a trailing slash, so typing a full `host/ws:name` over it yields
    `host/host/ws:name` — a destination that resolves to nothing, and whose
    only symptom is `[link lost — reconnecting…]` every couple of seconds
    forever, with ssh's actual error never reaching the pane."""
    osa(f'''tell application "System Events"
      repeat {n} times
        key code 51
        delay 0.012
      end repeat
    end tell''')


def run(text, cps=28, settle=0.5):
    typed(text, cps)
    time.sleep(0.35)
    enter()
    time.sleep(settle)


def click(x, y, n=1):
    subprocess.run([CLICK, str(x), str(y), str(n)], capture_output=True)


def place(pid, x=60, y=60, w=1280, h=800):
    """Deterministic geometry, because the pane coordinates below are absolute
    screen points. Move the window and every click lands in the wrong pane."""
    osa(f'''tell application "System Events" to tell (first process whose unix id is {pid})
      set position of window 1 to {{{x}, {y}}}
      set size of window 1 to {{{w}, {h}}}
    end tell''')


# Pane centres for a window at (60,60) sized 1280x800, after ⌘D then ⌘⇧D.
LEFT, RIGHT_TOP, RIGHT_BOT = (380, 500), (1020, 300), (1020, 680)

# ── a local shell ─────────────────────────────────────────────────────────
time.sleep(2.0)
beat("A local shell — what you get when you launch")
run("uname -srm && echo $SHELL", settle=2.0)

# ── panes ─────────────────────────────────────────────────────────────────
beat("⌘D splits left | right")
chord("d", "command")
time.sleep(1.4)
run("top -o cpu", settle=3.0)

beat("⌘⇧D splits top / bottom")
chord("d", "command", "shift")
time.sleep(1.4)
run(f"git -C {args.repo} log --oneline --graph -12", cps=45, settle=3.0)

# ── an agent in one of them ───────────────────────────────────────────────
beat("Click a pane to focus it — and run anything in it")
click(*LEFT)
time.sleep(0.8)
# `cd` first: Claude Code asks "is this a project you trust?" for a directory
# it has not seen, and that prompt is the operator's to answer, not a demo's.
run(f"cd {args.repo} && claude", settle=10.0)
beat("Claude Code on the left, top on the right, git below")
typed("in one sentence, what is a pty?", cps=22)
time.sleep(0.5)
enter()
time.sleep(17.0)

# ── a workspace on another machine ────────────────────────────────────────
if args.host:
    beat("⌘O opens a workspace — here, over ssh")
    chord("o", "command")
    time.sleep(1.2)
    clear_field()
    time.sleep(0.6)
    typed(f"{args.host}/ws:{args.ws}", cps=22)
    time.sleep(0.6)
    enter()
    time.sleep(4.5)
    beat("A new tab, a shell on the far machine")
    run("hostname && uptime", settle=2.5)
    chord("d", "command")
    time.sleep(1.4)
    run("while true; do date +%T; sleep 1; done", cps=45, settle=4.0)

    # ── the link breaks ───────────────────────────────────────────────────
    beat("Now break the network")
    subprocess.run("pkill -x ssh", shell=True, capture_output=True)
    time.sleep(6.0)
    beat("The far side never stopped — the client replays what it missed")
    time.sleep(6.0)

    # ── and survives the client dying ─────────────────────────────────────
    beat("Quit the terminal completely")
    subprocess.run("pkill -f 'MacOS/TerminalApp'", shell=True, capture_output=True)
    time.sleep(3.0)
    beat("Reopen it — the arrangement and the scrollback come back")
    env = {"PATH": "/usr/bin:/bin", "HOME": os.path.expanduser("~"), "SHELL": "/bin/zsh"}
    if args.remote_termd:
        env["STARLING_TERMD"] = args.remote_termd
    p = subprocess.Popen([args.app, "--workspace", f"{args.host}/ws:{args.ws}"],
                         env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(6.0)
    place(p.pid)
    time.sleep(9.0)

beat("")  # end marker: the last caption runs until here

json.dump(BEATS, open(os.path.join(args.out, "beats.json"), "w"), indent=1)
print(f"total {time.time() - T0:.1f}s", file=sys.stderr)
