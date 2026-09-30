#!/usr/bin/env python3
"""Drive Writer on macOS through the M1 checklist and screenshot each step.

    test/office-drive.py [--out DIR] [--only STEP,...]

Needs an unlocked screen. Launches apps/OfficeApp/.build/debug/OfficeApp
on the welcome document, finds its window, runs every step below, and
writes DIR/<nn>-<step>.png (window crop, 1x) plus DIR/index.md listing
what each picture should show. Read the pictures; the script cannot
judge them. Coordinates are window-relative points at the default
1440x932 window; the ribbon layout is stable at that width.
"""
import argparse, os, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "apps/OfficeApp/.build/debug/OfficeApp")

CLICK_SRC = r'''
import Foundation
import CoreGraphics
let a = CommandLine.arguments
guard a.count >= 3, let x = Double(a[1]), let y = Double(a[2]) else { exit(2) }
let p = CGPoint(x: x, y: y)
func post(_ t: CGEventType, _ pt: CGPoint, _ b: CGMouseButton = .left, clicks: Int64 = 1, flags: CGEventFlags = []) {
    let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: pt, mouseButton: b)!
    e.setIntegerValueField(.mouseEventClickState, value: clicks)
    e.flags = flags
    e.post(tap: .cghidEventTap); usleep(30_000)
}
let mode = a.count > 3 ? a[3] : "click"
var flags: CGEventFlags = []
if a.contains("shift") { flags.insert(.maskShift) }
if a.contains("cmd") { flags.insert(.maskCommand) }
post(.mouseMoved, p, flags: flags)
switch mode {
case "move": break
case "double":
    post(.leftMouseDown, p, flags: flags); post(.leftMouseUp, p, flags: flags)
    post(.leftMouseDown, p, clicks: 2, flags: flags); post(.leftMouseUp, p, clicks: 2, flags: flags)
case "triple":
    for n: Int64 in 1...3 { post(.leftMouseDown, p, clicks: n, flags: flags); post(.leftMouseUp, p, clicks: n, flags: flags) }
case "drag":
    let x2 = Double(a[4])!, y2 = Double(a[5])!
    post(.leftMouseDown, p, flags: flags)
    let steps = 12
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        post(.leftMouseDragged, CGPoint(x: x + (x2 - x) * t, y: y + (y2 - y) * t), flags: flags)
    }
    post(.leftMouseUp, CGPoint(x: x2, y: y2), flags: flags)
case "scroll":
    let dy = Int32(a[4])!
    let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0)!
    e.location = p
    e.post(tap: .cghidEventTap); usleep(30_000)
default:
    post(.leftMouseDown, p, flags: flags); post(.leftMouseUp, p, flags: flags)
}
'''

def sh(cmd, check=True):
    return subprocess.run(cmd, shell=True, check=check, capture_output=True, text=True).stdout.strip()

class Driver:
    def __init__(self, out):
        self.out = out
        self.n = 0
        self.index = []
        d = tempfile.mkdtemp(prefix="office-drive-")
        src = os.path.join(d, "click.swift")
        open(src, "w").write(CLICK_SRC)
        self.click_bin = os.path.join(d, "click")
        subprocess.run(["swiftc", "-O", "-o", self.click_bin, src], check=True, capture_output=True)
        self.proc = None
        self.x = self.y = 0
        self.w = self.h = 0

    def launch(self, env=None):
        subprocess.run(["pkill", "-x", "OfficeApp"])
        time.sleep(0.5)
        e = dict(os.environ, SHELL="/bin/sh")
        if env: e.update(env)
        self.proc = subprocess.Popen([APP], env=e, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(4)
        frame = sh('''osascript -e 'tell application "System Events" to get {position, size} of window 1 of (first process whose name is "OfficeApp")' ''')
        self.x, self.y, self.w, self.h = [int(v) for v in frame.split(", ")]
        sh('''osascript -e 'tell application "System Events" to set frontmost of (first process whose name is "OfficeApp") to true' ''')
        time.sleep(0.5)

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    # window-relative points → screen points
    def click(self, x, y, mode="click", *extra):
        args = [self.click_bin, str(self.x + x), str(self.y + y), mode] + [str(v) for v in extra]
        subprocess.run(args, check=True)
        time.sleep(0.25)

    def drag(self, x1, y1, x2, y2, *mods):
        args = [self.click_bin, str(self.x + x1), str(self.y + y1), "drag", str(self.x + x2), str(self.y + y2)] + list(mods)
        subprocess.run(args, check=True)
        time.sleep(0.25)

    def scroll(self, x, y, dy):
        subprocess.run([self.click_bin, str(self.x + x), str(self.y + y), "scroll", str(dy)], check=True)
        time.sleep(0.25)

    def key(self, text=None, key=None, mods=()):
        using = ""
        if mods:
            using = " using {" + ", ".join(m + " down" for m in mods) + "}"
        if text is not None:
            esc = text.replace("\\", "\\\\").replace('"', '\\"')
            sh(f'''osascript -e 'tell application "System Events" to keystroke "{esc}"{using}' ''')
        else:
            sh(f'''osascript -e 'tell application "System Events" to key code {key}{using}' ''')
        time.sleep(0.25)

    def shot(self, name, expect, cursor=False):
        self.n += 1
        path = os.path.join(self.out, f"{self.n:02d}-{name}.png")
        full = path + ".full.png"
        subprocess.run(["screencapture", "-x"] + (["-C"] if cursor else []) + [full], check=True)
        # 2x screen: crop the window, downsample to 1x.
        subprocess.run(["sips", "-c", str(self.h * 2), str(self.w * 2), "--cropOffset", str(self.y * 2), str(self.x * 2), full, "--out", path],
                       check=True, capture_output=True)
        subprocess.run(["sips", "-Z", str(self.w), path, "--out", path], check=True, capture_output=True)
        os.remove(full)
        self.index.append((os.path.basename(path), expect, self.alive()))

KEY = dict(left=123, right=124, down=125, up=126, home=115, end=119, pageup=116, pagedown=121,
           enter=36, backspace=51, delete=117, tab=48, escape=53)

def run(d, only):
    def step(name):
        return not only or name in only

    d.launch()
    d.shot("welcome", "The welcome document: Title, Subtitle, headings, list, link, table, code line; I-beam cursor over the page", cursor=True)

    if step("pointer"):
        d.click(700, 372, "move"); d.shot("cursor-text", "Pointer over the title is an I-beam", cursor=True)
        d.click(400, 126, "move"); d.shot("cursor-ribbon", "Pointer over the ribbon is an arrow", cursor=True)
        d.click(720, 405); d.shot("click-caret", "Caret in the intro paragraph where clicked")
        d.click(720, 405, "double"); d.shot("double-click", "The word under the pointer is selected")
        d.click(720, 405, "triple"); d.shot("triple-click", "The whole intro paragraph is selected")
        d.click(560, 405); d.click(900, 437, "click", "shift"); d.shot("shift-click", "Selection from the first click to the shift-click")
        d.drag(560, 405, 900, 470); d.shot("drag-select", "Selection covers the dragged range")
        d.scroll(720, 600, -300); d.shot("scroll-down", "Page scrolled down by the wheel")
        d.scroll(720, 600, 600); d.shot("scroll-up", "Back at the top")

    if step("keys"):
        d.click(560, 405)
        d.key(key=KEY["down"]); d.key(key=KEY["down"]); d.shot("arrow-down", "Caret two lines down, same x")
        d.key(key=KEY["right"], mods=("option", "shift")); d.shot("opt-shift-right", "One word selected to the right")
        d.key(key=KEY["left"], mods=("command",)); d.shot("cmd-left", "Caret at the line start")
        d.key(key=KEY["end"]); d.shot("end", "Caret at the line end")
        d.key(key=KEY["up"], mods=("option",)); d.shot("opt-up", "Caret at the paragraph start")
        d.key(key=KEY["down"], mods=("command",)); d.shot("cmd-down", "Caret at the document end, view scrolled there")
        d.key(key=KEY["up"], mods=("command",)); d.shot("cmd-up", "Back at the document start")
        d.key(key=KEY["pagedown"]); d.shot("pagedown", "Caret and view moved a screenful down")

    if step("editing"):
        d.click(560, 405); d.key(key=KEY["end"])
        d.key(" typed here"); d.shot("typing", "' typed here' appended to the first intro line's end")
        d.key(key=KEY["backspace"], mods=("command",)); d.shot("cmd-backspace", "The line before the caret deleted")
        d.key("z", mods=("command",)); d.shot("undo", "The line is back")
        d.key(key=KEY["enter"], mods=("shift",)); d.key("after a line break"); d.shot("shift-enter", "A line break inside the paragraph, text on the next line")
        d.key("z", mods=("command",)); d.key("z", mods=("command",))
        d.click(560, 405); d.click(700, 405, "click", "shift"); d.key("b", mods=("command",)); d.shot("cmd-b", "Selection bold")
        d.key("e", mods=("command",)); d.shot("cmd-e", "Intro paragraph centred")
        d.key("l", mods=("command",))
        d.key("]", mods=("command",)); d.shot("cmd-bracket", "Selection one size larger; the Font size box shows it")
        d.key("z", mods=("command",)); d.key("z", mods=("command",)); d.key("z", mods=("command",))

    if step("list"):
        # The list: click the end of the second bullet, Enter twice ends the list.
        d.click(1000, 640); d.key(key=KEY["end"]); d.key(key=KEY["enter"]); d.shot("list-enter", "A new empty bullet under item 2")
        d.key(key=KEY["enter"]); d.shot("list-end", "The empty bullet became a plain paragraph")
        d.key("z", mods=("command",)); d.key("z", mods=("command",))

    if step("table"):
        d.click(560, 760); d.shot("table-click", "Caret in the table; the Table Layout tab is in the strip")
        d.click(560, 760, "move"); d.shot("cursor-table", "I-beam inside a cell", cursor=True)
        d.key(key=KEY["tab"]); d.key(key=KEY["tab"]); d.shot("table-tab", "Two Tabs: the third cell is selected")

    if step("picture"):
        # Paste a picture from the pasteboard (a PNG put there with pbcopy is
        # text; use Preview manually) — here: insert via the clipboard codec
        # is not scriptable, so only check the tab strip after Insert.
        pass

    if step("chrome"):
        d.click(159, 90); d.shot("insert-tab", "Insert tab with Table menu, Pictures, Link enabled")
        d.click(97, 90); d.shot("home-tab", "Home tab; Change Case is a menu, Show/Hide ¶ a toggle")
        d.click(802, 126); d.shot("marks-on", "Formatting marks: a pilcrow at every paragraph end")
        d.click(802, 126)
        d.click(1253, 123); d.shot("styles-menu", "The all-styles menu with Update … to Match Selection at the bottom")
        d.key(key=KEY["escape"])
        d.click(514, 90); d.shot("view-tab", "View tab: Navigation Pane toggle")
        d.click(423, 126); d.shot("nav-pane", "Navigation pane with the welcome headings")
        d.click(423, 126)

    d.shot("final", "Still running, no crash dialog")
    with open(os.path.join(d.out, "index.md"), "w") as f:
        f.write("| picture | should show | app alive |\n| --- | --- | --- |\n")
        for name, expect, alive in d.index:
            f.write(f"| {name} | {expect} | {'yes' if alive else 'NO'} |\n")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(tempfile.gettempdir(), "office-drive"))
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    if not os.path.exists(APP):
        sys.exit("build the app first: swift build --package-path apps/OfficeApp")
    d = Driver(a.out)
    run(d, set(filter(None, a.only.split(","))))
    print("wrote", len(d.index), "pictures to", a.out, "- read index.md, then the pictures")
