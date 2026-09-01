#!/usr/bin/env python3
"""starling-computer-use — computer use for Claude Desktop, over MCP.

Claude Desktop for Linux ships without computer use. It cannot be handed the
`computer_toolset_20260801` toolset — a client declares its own tools on its
own API requests, and no third party can inject one — but it does load MCP
servers from ~/.config/Claude/claude_desktop_config.json. So this is that
toolset's seventeen members, same names and same semantics, as MCP tools
backed by the shell's agent broker.

What makes it different from every other computer-use bridge is what is
underneath, not what is here: the broker only ever addresses windows this
agent launched. The human's windows are not listed, not injectable and not
capturable — not by policy, by lookup failure — and input is delivered to the
agent's own targeted stream, so the person keeps typing in their window while
this types in its own. That is why there is no VM: the isolation is the
compositor's, per window, rather than a machine boundary.

Two consequences fall out of the per-window model and shape the tool list:

  * every tool takes an explicit `win`. There is no "the screen" here, so
    there is nothing for a bare coordinate to be relative to.
  * two tools exist that the toolset has no member for — computer_launch and
    computer_windows — because an agent with no way to open a window has
    nothing it is allowed to look at.

    starling-computer-use serve      # MCP over stdio (what Claude Desktop runs)
    starling-computer-use install    # add ourselves to the desktop's config
    starling-computer-use selftest   # drive it from the command line

Stdlib only, like agent-client.py beside it — which it imports rather than
reimplements, so the broker protocol and the identity file have one owner.
"""

import base64
import importlib.machinery
import importlib.util
import json
import os
import struct
import sys
import time
import zlib

# ── the client library next door ─────────────────────────────────────────────
#
# agent-client.py is not importable by name (the dash), and lives in two places
# depending on how we were started: beside us in the repo, or as `agent-client`
# in the same bin/ directory of an install. Load it by path from wherever we
# are, so a dev run and a packaged run are the same code.


def _load_agent_client():
    here = os.path.dirname(os.path.abspath(__file__))
    for cand in (os.path.join(here, "agent-client.py"),
                 os.path.join(here, "agent-client"),
                 "/usr/bin/agent-client"):
        if os.path.exists(cand):
            # The loader has to be named explicitly. Two of these three
            # candidates have no `.py` on the end — stage.sh installs the
            # client as plain `agent-client` — and spec_from_file_location
            # infers the loader FROM THE EXTENSION, so for those it returns
            # None and the next line dies on `NoneType has no attribute
            # loader`. Which meant this worked in the repo and failed in
            # every install: the only path where the extension is present is
            # the dev one.
            loader = importlib.machinery.SourceFileLoader(
                "starling_agent_client", cand)
            spec = importlib.util.spec_from_file_location(
                "starling_agent_client", cand, loader=loader)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            return mod
    raise SystemExit("agent-client not found beside %s or in /usr/bin" % here)


ac = _load_agent_client()


# ── keys ─────────────────────────────────────────────────────────────────────
#
# The tool's `key` takes xdotool syntax — "ctrl+s", "Return", "shift+Tab" — and
# the broker takes USB HID usages, the same ones the engine's evdev→HID table
# produces. This is that translation, and it is US-layout like the seat's
# keymap. Names follow X keysyms because that is what the tool documents and
# what a model will emit; the aliases are the spellings that turn up in
# practice.

_HID = {}
for _i in range(26):
    _HID[chr(ord("a") + _i)] = 0x04 + _i
for _i, _c in enumerate("123456789"):
    _HID[_c] = 0x1E + _i
_HID["0"] = 0x27
_HID.update({
    "return": 0x28, "enter": 0x28, "kp_enter": 0x58,
    "escape": 0x29, "esc": 0x29,
    "backspace": 0x2A, "tab": 0x2B, "space": 0x2C,
    "minus": 0x2D, "equal": 0x2E, "bracketleft": 0x2F, "bracketright": 0x30,
    "backslash": 0x31, "semicolon": 0x33, "apostrophe": 0x34, "grave": 0x35,
    "comma": 0x36, "period": 0x37, "slash": 0x38,
    "caps_lock": 0x39,
    "print": 0x46, "scroll_lock": 0x47, "pause": 0x48,
    "insert": 0x49, "home": 0x4A, "prior": 0x4B, "page_up": 0x4B,
    "delete": 0x4C, "end": 0x4D, "next": 0x4E, "page_down": 0x4E,
    "right": 0x4F, "left": 0x50, "down": 0x51, "up": 0x52,
    "num_lock": 0x53, "menu": 0x65,
})
for _i in range(12):
    _HID["f%d" % (_i + 1)] = (0x3A + _i) if _i < 10 else (0x44 + _i - 10)

# Modifiers are held around the rest of the chord rather than pressed with it.
_MODS = {
    "ctrl": 0xE0, "control": 0xE0,
    "shift": 0xE1,
    "alt": 0xE2, "option": 0xE2,
    "super": 0xE3, "meta": 0xE3, "cmd": 0xE3, "command": 0xE3, "win": 0xE3,
}

# Characters a bare `key` may name directly ("key +"), which need shift.
_SHIFTED_CHAR = {
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7",
    "*": "8", "(": "9", ")": "0", "_": "minus", "+": "equal",
    "{": "bracketleft", "}": "bracketright", "|": "backslash",
    ":": "semicolon", '"': "apostrophe", "~": "grave",
    "<": "comma", ">": "period", "?": "slash",
}


def parse_mods(text):
    """The modifier names in a string, ignoring everything else. Used where
    the tool takes modifiers to HOLD rather than a chord to press."""
    return [_MODS[p.lower()] for p in (text or "").split("+")
            if p.lower() in _MODS]


def parse_chord(text):
    """"ctrl+shift+t" -> ([modifier HIDs], key HID). Raises on an unknown name.

    The last segment is the key and the rest are modifiers, which is what
    makes "ctrl+shift" (a chord of two modifiers) come out as Shift held under
    nothing rather than as an error — a model does emit that.
    """
    raw = text.replace(" ", "")
    parts = raw.split("+")
    # A literal "+" as the key ("ctrl++") splits to an empty tail. Splice it
    # back rather than dropping it, or the chord silently loses its key.
    parts = [p for p in parts if p] + (["+"] if raw.endswith("+") else [])
    if not parts:
        raise ValueError("no key in %r" % text)
    *head, last = parts
    mods = []
    for p in head:
        if p.lower() not in _MODS:
            raise ValueError("%r is not a modifier (in %r)" % (p, text))
        mods.append(_MODS[p.lower()])
    if last.lower() in _MODS:
        return mods, _MODS[last.lower()]
    if last in _SHIFTED_CHAR:
        return mods + [_MODS["shift"]], _HID[_SHIFTED_CHAR[last]]
    if last.lower() in _HID:
        return mods, _HID[last.lower()]
    raise ValueError("no key named %r (US layout; try Return, ctrl+s, F5)" % last)


# ── PNG ──────────────────────────────────────────────────────────────────────


def png_bytes(rgba, width, height):
    """Top-down RGBA -> a PNG in memory. zlib is stdlib; an encoder is not."""
    raw = b"".join(b"\x00" + rgba[y * width * 4:(y + 1) * width * 4]
                   for y in range(height))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6))
            + chunk(b"IEND", b""))


def rescale(rgba, w, h, out_w, out_h):
    """Nearest-neighbour resample. Only `zoom` needs it — everything else asks
    the compositor for the size it wants, and gets a GPU blit for free."""
    if (w, h) == (out_w, out_h):
        return rgba
    out = bytearray(out_w * out_h * 4)
    xs = [min(w - 1, x * w // out_w) * 4 for x in range(out_w)]
    for y in range(out_h):
        src = (min(h - 1, y * h // out_h)) * w * 4
        row = y * out_w * 4
        for x in range(out_w):
            o = row + x * 4
            s = src + xs[x]
            out[o:o + 4] = rgba[s:s + 4]
    return bytes(out)


# ── the executor ─────────────────────────────────────────────────────────────
#
# The broker→action mapping, written once. The MCP server below is a frontend
# on it; test/computeruse/conformance.py is the other, running the REAL
# computer_toolset_20260801 against the same code so the two cannot drift.


class ActionError(Exception):
    """A tool failed. The message is what the model gets to read."""


class Executor:

    # Screenshot long edge. The contract has no display_width_px any more —
    # the returned image's dimensions ARE the coordinate space — and the model
    # is documented to do worse above 1920x1080. Our panels are 2560x1600 and
    # 3840x2160, so everything gets downscaled; the compositor does it in the
    # capture blit, so no pixel is ever encoded that is not sent.
    MAX_PX = 1280

    # ...and a ceiling on AREA, which is the one that actually bites. The
    # client resizes any image above roughly 1.15 megapixels before the model
    # sees it, and the model then reads coordinates off THAT smaller picture
    # while this shim's contract says the coordinate space is the size we
    # reported. Nothing errors: every coordinate simply comes back short by
    # the resize factor, so clicks land somewhere plausible and slightly
    # wrong. Found the hard way — a 1280x1167 browser window (1.49 MP) was
    # being shrunk ~11%, which was invisible on list rows and fatal on
    # toolbar buttons, and cost a whole session's worth of misses in Outlook.
    # Staying under the budget means no resize, so the two agree again.
    MAX_AREA = 1_100_000

    @classmethod
    def _area_capped_px(cls, w: int, h: int) -> int:
        """Long-edge cap that also keeps w*h under the area budget."""
        long_side, short_side = max(w, h), min(w, h)
        if long_side <= 0 or short_side <= 0:
            return cls.MAX_PX
        ratio = short_side / float(long_side)
        return max(1, int(min(cls.MAX_PX, (cls.MAX_AREA / ratio) ** 0.5)))

    def __init__(self, name="starling-computer-use"):
        self.broker = ac.connect(name=name)
        # win -> (image_w, image_h, content_w, content_h). The ONE place
        # screenshot pixels become the content-local logical coordinates the
        # broker takes; every action that carries a coordinate goes through
        # to_logical below and nowhere else.
        self._frame = {}
        # win -> the capture long-edge that keeps this window inside the area
        # budget, learned on first capture (see MAX_AREA).
        self._winMaxPx = {}

    # -- coordinates --

    def _remember(self, win, shot):
        cw, ch = shot["content"]
        self._frame[win] = (shot["w"], shot["h"], float(cw), float(ch))

    def to_logical(self, win, x, y):
        """Screenshot px (top-left origin) -> content-local logical px."""
        if win not in self._frame:
            # Never screenshotted this window, so there is no frame to be
            # relative to. Take one — cheap, and far better than guessing a
            # scale factor and clicking somewhere plausible but wrong.
            self._capture(win)
        iw, ih, cw, ch = self._frame[win]
        return (x * cw / iw, y * ch / ih)

    # -- broker --

    def _call(self, op, **kw):
        try:
            return self.broker.call(op, **kw)
        except RuntimeError as exc:
            raise ActionError(str(exc))

    def _capture(self, win, max_px=None):
        shot = self._call("capture", win=win,
                          max_px=max_px or self._winMaxPx.get(win) or self.MAX_PX)
        # First sight of a window: if the long-edge cap alone put it over the
        # area budget, take it again smaller and remember that for next time.
        # One extra capture per window, once — cheaper than every coordinate
        # after it being wrong.
        if max_px is None:
            fitted = self._area_capped_px(shot["w"], shot["h"])
            if fitted < max(shot["w"], shot["h"]):
                self._winMaxPx[win] = fitted
                shot = self._call("capture", win=win, max_px=fitted)
        self._remember(win, shot)
        rgba, w, h = ac.capture_to_rgba(shot)
        return rgba, w, h

    def _inject(self, win, **ev):
        return self._call("inject", win=win, ev=ev)

    # -- pixels --

    def _settle(self, win, timeout_ms=2000, quiet_ms=150):
        """Wait for the window to finish drawing. True if it did.

        Never raises: settling is a courtesy on the way to something else,
        and a window that cannot settle is still worth screenshotting.
        """
        try:
            r = self._call("await_settled", win=win,
                           timeout_ms=timeout_ms, quiet_ms=quiet_ms)
            return not r.get("timed_out")
        except ActionError:
            return True

    def _acted(self, win, text, settle_ms=2500):
        """An action's result, carrying the screen that action produced.

        What a model does after acting is look, and it costs a whole round
        trip to ask. Measured on the recorded demo run: of 55 screenshot
        calls, 36 were the very next call after an action — a turn each, 5.2
        minutes of a 21.7 minute run spent asking "what happened?" and waiting
        to be told. Answering unprompted costs one capture (~45ms) and removes
        the turn, and it removes it from the client's per-turn tool budget too,
        which that run exhausted twice.

        Actions do sometimes come in runs, and those pay for an image nobody
        reads — 13 of them on the same run, against 36 turns saved. That is
        the trade, and it is a good one; `shot=False` opts out where a caller
        knows better.
        """
        if settle_ms:
            self._settle(win, timeout_ms=settle_ms)
        rgba, w, h = self._capture(win)
        return {"image": png_bytes(rgba, w, h),
                "text": "%s — screen after it (%dx%d)" % (text, w, h)}

    def screenshot(self, win, **_):
        # Let the window finish what the last action started. The capture
        # itself is ~60ms now, which is fast enough to photograph a window
        # mid-repaint — the second of latency it used to carry was hiding
        # that.
        self._settle(win, timeout_ms=2500)
        rgba, w, h = self._capture(win)
        return {"image": png_bytes(rgba, w, h),
                "text": "screenshot of %s (%dx%d)" % (win, w, h)}

    def zoom(self, win, region=None, **_):
        """Magnify part of the last screenshot.

        Coordinates DO NOT rebase: the region is given in full-screenshot
        pixels and everything afterwards stays in full-screenshot pixels. The
        model is documented to keep using them, and a shim that quietly
        rebased would turn every post-zoom click into a wrong one.
        """
        if not region or len(region) != 4:
            raise ActionError("zoom needs region [x, y, width, height]")
        rgba, w, h = self._capture(win)
        x, y, rw, rh = [int(v) for v in region]
        x = max(0, min(x, w - 1))
        y = max(0, min(y, h - 1))
        rw = max(1, min(rw, w - x))
        rh = max(1, min(rh, h - y))
        crop = b"".join(rgba[(y + r) * w * 4 + x * 4:(y + r) * w * 4 + (x + rw) * 4]
                        for r in range(rh))
        # Same budget as a full screenshot: a magnified crop that gets resized
        # on the way to the model is a crop whose pixels lie about where they
        # are, and this one is handed straight back as coordinates.
        scale = min(4.0, max(1.0, self._area_capped_px(rw, rh) / float(max(rw, rh))))
        ow, oh = max(1, int(rw * scale)), max(1, int(rh * scale))
        return {"image": png_bytes(rescale(crop, rw, rh, ow, oh), ow, oh),
                "text": ("zoom of %s region %d,%d %dx%d — coordinates stay in "
                         "the full screenshot's space" % (win, x, y, rw, rh))}

    # -- mouse --

    def _click(self, win, coordinate, kind, text=None, shot=True):
        if not coordinate or len(coordinate) != 2:
            raise ActionError("%s needs coordinate [x, y]" % kind)
        lx, ly = self.to_logical(win, coordinate[0], coordinate[1])
        held = parse_mods(text)      # modifier keys held for the click
        for m in held:
            self._inject(win, type="keydown", physical=m)
        try:
            self._inject(win, type=kind, x=lx, y=ly)
        finally:
            for m in reversed(held):
                self._inject(win, type="keyup", physical=m)
        done = "%s at %d,%d in %s" % (kind, coordinate[0], coordinate[1], win)
        return self._acted(win, done) if shot else {"text": done}

    def left_click(self, win, coordinate=None, text=None, shot=True, **_):
        return self._click(win, coordinate, "click", text, shot)

    def right_click(self, win, coordinate=None, text=None, shot=True, **_):
        return self._click(win, coordinate, "rclick", text, shot)

    def middle_click(self, win, coordinate=None, text=None, shot=True, **_):
        return self._click(win, coordinate, "mclick", text, shot)

    def double_click(self, win, coordinate=None, text=None, shot=True, **_):
        return self._click(win, coordinate, "dblclick", text, shot)

    def triple_click(self, win, coordinate=None, text=None, shot=True, **_):
        return self._click(win, coordinate, "tripleclick", text, shot)

    def mouse_move(self, win, coordinate=None, **_):
        if not coordinate:
            raise ActionError("mouse_move needs coordinate [x, y]")
        lx, ly = self.to_logical(win, coordinate[0], coordinate[1])
        self._inject(win, type="move", x=lx, y=ly)
        return {"text": "moved to %d,%d in %s" % (coordinate[0], coordinate[1], win)}

    def _here(self, win, coordinate):
        """Where a press/release lands when the caller named no coordinate:
        wherever this agent last put the pointer. Defaulting to 0,0 would move
        it to the corner first and press there, which is a different gesture."""
        if coordinate:
            return self.to_logical(win, coordinate[0], coordinate[1])
        r = self._call("cursor_position", win=win)
        if r.get("x") is None:
            raise ActionError("no coordinate, and this agent has not moved the "
                              "pointer in %s yet" % win)
        return (r["x"], r["y"])

    def left_mouse_down(self, win, coordinate=None, **_):
        lx, ly = self._here(win, coordinate)
        self._inject(win, type="down", x=lx, y=ly)
        return {"text": "button down in %s" % win}

    def left_mouse_up(self, win, coordinate=None, **_):
        lx, ly = self._here(win, coordinate)
        self._inject(win, type="up", x=lx, y=ly)
        return {"text": "button up in %s" % win}

    def left_click_drag(self, win, coordinate=None, start_coordinate=None, **_):
        if not coordinate or not start_coordinate:
            raise ActionError("left_click_drag needs start_coordinate and coordinate")
        sx, sy = self.to_logical(win, start_coordinate[0], start_coordinate[1])
        ex, ey = self.to_logical(win, coordinate[0], coordinate[1])
        self._inject(win, type="drag", x=sx, y=sy, x2=ex, y2=ey)
        return {"text": "dragged %s -> %s in %s"
                        % (tuple(start_coordinate), tuple(coordinate), win)}

    def cursor_position(self, win, **_):
        r = self._call("cursor_position", win=win)
        if r.get("x") is None:
            return {"text": "this agent has not moved the pointer in %s yet" % win}
        # Back out through the same mapping, so the answer is in the space the
        # model asks its questions in.
        if win not in self._frame:
            self._capture(win)
        iw, ih, cw, ch = self._frame[win]
        return {"text": "cursor at %d,%d in %s"
                        % (round(r["x"] * iw / cw), round(r["y"] * ih / ch), win)}

    # -- keyboard --

    # A keyboard delivers characters at a keyboard's pace; this used to hand
    # a whole paragraph over in one burst — 630 characters as 1260 key events
    # with no gap at all. A rich web editor (Outlook's compose pane) then
    # spends SECONDS working through that queue with nothing repainted, so
    # the screenshot straight afterwards shows an empty body. Measured on a
    # page that costs 8ms a keystroke: 589 characters, five seconds of frozen
    # UI. Claude read that empty body as the text having missed, typed it a
    # second time, and had to go back and delete the duplicate.
    TYPE_CHUNK = 48

    def type(self, win, text=None, shot=True, **_):
        if text is None:
            raise ActionError("type needs text")
        t0 = time.time()
        caught_up = True
        for i in range(0, len(text), self.TYPE_CHUNK):
            self._inject(win, type="text", text=text[i:i + self.TYPE_CHUNK])
            # Between chunks, not just at the end: an app still chewing
            # chunk 3 has no business being handed chunk 4, and a wait per
            # chunk is what keeps the window drawing as the text goes in —
            # which is also what a person watching expects to see. Back
            # pressure only, so quiet_ms=0: all this has to know is that the
            # window drew SOMETHING since the last chunk. Waiting for it to
            # go still as well would add a second per chunk for nothing.
            caught_up &= self._settle(win, timeout_ms=2000, quiet_ms=0)
        # The one wait that has to be generous is the last: this is what
        # makes the next screenshot show the text.
        caught_up &= self._settle(win, timeout_ms=6000)
        done = ("typed %d character(s) into %s%s (%.1fs)"
                % (len(text), win,
                   "" if caught_up else " — the window was still drawing when "
                   "I stopped waiting, so the screen below may be mid-repaint",
                   time.time() - t0))
        # No second settle: the generous one above just ran.
        return self._acted(win, done, settle_ms=0) if shot else {"text": done}

    def key(self, win, text=None, shot=True, **_):
        if not text:
            raise ActionError("key needs text, e.g. \"ctrl+s\" or \"Return\"")
        results = []
        for chord in text.split():          # "cmd+a cmd+c" is two chords
            try:
                mods, k = parse_chord(chord)
            except ValueError as exc:
                raise ActionError(str(exc))
            for m in mods:
                self._inject(win, type="keydown", physical=m)
            try:
                self._inject(win, type="key", physical=k)
            finally:
                for m in reversed(mods):
                    self._inject(win, type="keyup", physical=m)
            results.append(chord)
        done = "pressed %s in %s" % (" ".join(results), win)
        return self._acted(win, done) if shot else {"text": done}

    def hold_key(self, win, text=None, duration=None, **_):
        if not text:
            raise ActionError("hold_key needs text")
        try:
            mods, k = parse_chord(text)
        except ValueError as exc:
            raise ActionError(str(exc))
        for m in mods:
            self._inject(win, type="keydown", physical=m)
        self._inject(win, type="keydown", physical=k)
        self._call("wait", ms=int(max(0.0, min(float(duration or 1), 10.0)) * 1000))
        self._inject(win, type="keyup", physical=k)
        for m in reversed(mods):
            self._inject(win, type="keyup", physical=m)
        return {"text": "held %s for %ss in %s" % (text, duration or 1, win)}

    # -- other --

    def scroll(self, win, coordinate=None, scroll_direction=None, shot=True,
               scroll_amount=None, text=None, **_):
        if not coordinate:
            raise ActionError("scroll needs coordinate [x, y]")
        lx, ly = self.to_logical(win, coordinate[0], coordinate[1])
        amount = int(scroll_amount or 3)
        # A "click" of a wheel is ~20 pixel units on the Flutter side, and the
        # axes are signed the way a wheel is: scrolling DOWN moves the content
        # up, so dy is negative.
        step = 20 * amount
        dx, dy = {"up": (0, step), "down": (0, -step),
                  "left": (step, 0), "right": (-step, 0)}.get(
                      (scroll_direction or "down").lower(), (0, -step))
        held = parse_mods(text)
        for m in held:
            self._inject(win, type="keydown", physical=m)
        try:
            self._inject(win, type="scroll", x=lx, y=ly, dx=dx, dy=dy)
        finally:
            for m in reversed(held):
                self._inject(win, type="keyup", physical=m)
        done = "scrolled %s %d in %s" % (scroll_direction, amount, win)
        return self._acted(win, done) if shot else {"text": done}

    def wait(self, win=None, duration=None, **_):
        ms = int(max(0.0, min(float(duration or 1), 10.0)) * 1000)
        self._call("wait", ms=ms)
        return {"text": "waited %dms" % ms}

    # -- the two the toolset has no member for --

    def computer_launch(self, app=None, url=None, **_):
        if not app:
            raise ActionError("computer_launch needs app (see computer_windows "
                              "for what this agent may launch)")
        r = self._call("launch", app=app, **({"url": url} if url else {}))
        return {"text": "launched %s as %s" % (app, r["win"])}

    def computer_windows(self, **_):
        wins = self._call("list_windows")["windows"]
        scope = self.broker.scope.get("launch", [])
        lines = ["%s  %-24s %s" % (w["win"], w["app"], w["title"]) for w in wins]
        return {"text": ("windows this agent owns:\n" + ("\n".join(lines) or "  (none)")
                         + "\n\nlaunchable: " + ", ".join(scope))}

    def computer_settled(self, win=None, **_):
        """Not a toolset member either, and the one worth having most: it is
        what replaces `wait 2 seconds`. The compositor knows when the window
        stopped painting AND when its own animations finished, which is a fact
        rather than a guess."""
        try:
            r = self._call("await_settled", win=win, timeout_ms=5000)
            if not r.get("timed_out"):
                return {"text": "settled in %dms" % r.get("settled_in_ms", 0)}
            return {"text": "gave up after %dms — %s"
                            % (r.get("settled_in_ms", 0),
                               "still repainting" if r.get("repainted") else
                               "the window never repainted, so the last "
                               "action may have changed nothing")}
        except ActionError as exc:
            return {"text": "not settled: %s" % exc}

    # -- batching --

    def run_batch(self, actions):
        """Sequential, stopping at the first failure — the toolset's rule.

        Everything after a failure comes back is_error with the fixed message
        the contract names, rather than being silently dropped: a model that
        asked for five actions has to be able to tell which ones happened.
        """
        out, failed = [], False
        for act in actions:
            if failed:
                out.append({"is_error": True,
                            "text": "Not executed: an earlier computer action "
                                    "in this turn failed."})
                continue
            name = act.get("name")
            fn = getattr(self, name, None)
            if fn is None or name.startswith("_"):
                out.append({"is_error": True, "text": "no such action %r" % name})
                failed = True
                continue
            try:
                out.append(fn(**act.get("input", {})))
            except ActionError as exc:
                out.append({"is_error": True, "text": str(exc)})
                failed = True
            except Exception as exc:                       # noqa: BLE001
                out.append({"is_error": True, "text": "%s: %s"
                                                      % (type(exc).__name__, exc)})
                failed = True
        return out


# ── MCP ──────────────────────────────────────────────────────────────────────

WIN = {"type": "string",
       "description": "Window id from computer_windows or computer_launch."}
COORD = {"type": "array", "items": {"type": "integer"}, "minItems": 2,
         "maxItems": 2,
         "description": "[x, y] in the LAST screenshot's pixels, top-left "
                        "origin. Take a screenshot first."}
MODTEXT = {"type": "string",
           "description": "Optional modifier keys to hold, e.g. \"ctrl\" or "
                          "\"ctrl+shift\"."}


def _tool(name, desc, props, required):
    return {"name": name, "description": desc,
            "inputSchema": {"type": "object", "properties": props,
                            "required": required}}


def tool_list():
    # Every action answers with the screen it produced, so the reflex
    # "act, then screenshot" is one call instead of two — and one turn
    # instead of two against this client's per-turn tool budget.
    AFTER = ("The result INCLUDES a screenshot taken once the window settled, "
             "so do not follow this with a screenshot call. Pass shot=false "
             "if you are chaining actions and do not need to see each one.")
    SHOT = {"type": "boolean",
            "description": "Include the after-screenshot (default true)."}
    click = lambda verb: _tool(                                     # noqa: E731
        verb, "%s at a screenshot coordinate in an owned window. %s"
              % (verb.replace("_", " ").capitalize(), AFTER),
        {"win": WIN, "coordinate": COORD, "text": MODTEXT, "shot": SHOT},
        ["win", "coordinate"])
    return [
        _tool("screenshot",
              "Capture one owned window's own content. The window's buffer is "
              "read directly, so nothing that overlaps it — including the "
              "human's windows — can appear, and a covered or minimized window "
              "captures the same as a bare one. The returned image's "
              "dimensions are the coordinate space for every other tool.",
              {"win": WIN}, ["win"]),
        _tool("zoom",
              "Magnify a region of a window. Coordinates DO NOT change: keep "
              "using full-screenshot coordinates afterwards.",
              {"win": WIN,
               "region": {"type": "array", "items": {"type": "integer"},
                          "minItems": 4, "maxItems": 4,
                          "description": "[x, y, width, height] in screenshot px."}},
              ["win", "region"]),
        click("left_click"), click("right_click"), click("middle_click"),
        click("double_click"), click("triple_click"),
        _tool("left_click_drag", "Press at start_coordinate, glide to "
                                 "coordinate, release.",
              {"win": WIN, "start_coordinate": COORD, "coordinate": COORD},
              ["win", "start_coordinate", "coordinate"]),
        _tool("mouse_move", "Move the pointer without pressing.",
              {"win": WIN, "coordinate": COORD}, ["win", "coordinate"]),
        _tool("left_mouse_down", "Press the left button and hold it.",
              {"win": WIN, "coordinate": COORD}, ["win"]),
        _tool("left_mouse_up", "Release the left button.",
              {"win": WIN, "coordinate": COORD}, ["win"]),
        _tool("cursor_position",
              "Where THIS agent last put the pointer in a window. The human's "
              "cursor is not readable and is never moved by these tools.",
              {"win": WIN}, ["win"]),
        _tool("type", "Type text. US layout; non-ASCII is reported, not "
                      "guessed. " + AFTER,
              {"win": WIN, "text": {"type": "string"}, "shot": SHOT},
              ["win", "text"]),
        _tool("key", "Press a key or chord in xdotool syntax: \"Return\", "
                     "\"ctrl+s\", \"shift+Tab\". Space-separated chords are "
                     "pressed in order. " + AFTER,
              {"win": WIN, "text": {"type": "string"}, "shot": SHOT},
              ["win", "text"]),
        _tool("hold_key", "Hold a key or chord down for `duration` seconds.",
              {"win": WIN, "text": {"type": "string"},
               "duration": {"type": "number"}}, ["win", "text", "duration"]),
        _tool("scroll", "Scroll at a coordinate. " + AFTER,
              {"win": WIN, "coordinate": COORD, "shot": SHOT,
               "scroll_direction": {"type": "string",
                                    "enum": ["up", "down", "left", "right"]},
               "scroll_amount": {"type": "integer",
                                 "description": "Wheel clicks."},
               "text": MODTEXT},
              ["win", "coordinate", "scroll_direction", "scroll_amount"]),
        _tool("wait", "Pause for `duration` seconds. Prefer computer_settled.",
              {"duration": {"type": "number"}}, ["duration"]),
        _tool("computer_launch",
              "Open an app in a window this agent owns. Only owned windows can "
              "be seen or driven, so this is where every session starts.",
              {"app": {"type": "string",
                       "description": "App id — computer_windows lists them."},
               "url": {"type": "string",
                       "description": "Optional URL or file for host apps."}},
              ["app"]),
        _tool("computer_windows",
              "List the windows this agent owns and the apps it may launch.",
              {}, []),
        _tool("computer_settled",
              "Wait until a window has stopped repainting and the shell's "
              "animations are done. Use this instead of wait: it is the "
              "compositor reporting a fact, not a guess at a duration.",
              {"win": WIN}, ["win"]),
    ]


class MCPServer:
    """JSON-RPC 2.0 over stdio. Enough of MCP to be a tool provider: nothing
    here needs resources, prompts or sampling."""

    PROTOCOL = "2025-06-18"

    def __init__(self):
        self._exec = None            # built lazily: no shell, no connection

    def executor(self):
        if self._exec is None:
            self._exec = Executor()
        return self._exec

    def handle(self, req):
        method = req.get("method")
        if method == "initialize":
            return {"protocolVersion": self.PROTOCOL,
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "starling-computer-use",
                                   "version": "1"}}
        if method in ("notifications/initialized", "notifications/cancelled"):
            return None
        if method == "ping":
            return {}
        if method == "tools/list":
            return {"tools": tool_list()}
        if method == "tools/call":
            params = req.get("params") or {}
            name = params.get("name")
            args = params.get("arguments") or {}
            try:
                ex = self.executor()
            except SystemExit as exc:
                return {"content": [{"type": "text", "text": str(exc)}],
                        "isError": True}
            result = ex.run_batch([{"name": name, "input": args}])[0]
            content = []
            if result.get("text"):
                content.append({"type": "text", "text": result["text"]})
            if result.get("image"):
                content.append({"type": "image",
                                "data": base64.b64encode(result["image"]).decode(),
                                "mimeType": "image/png"})
            out = {"content": content}
            if result.get("is_error"):
                out["isError"] = True
            return out
        raise KeyError(method)

    def serve(self):
        # Line-delimited JSON on stdin/stdout. NOTHING else may be written to
        # stdout — a stray print corrupts the stream and the client sees the
        # server die for no reason. Diagnostics go to stderr.
        for line in sys.stdin.buffer:
            line = line.strip()
            if not line:
                continue
            try:
                req = json.loads(line)
            except ValueError:
                continue
            rid = req.get("id")
            try:
                result = self.handle(req)
            except KeyError as exc:
                reply = {"jsonrpc": "2.0", "id": rid,
                         "error": {"code": -32601,
                                   "message": "method not found: %s" % exc}}
            except Exception as exc:                            # noqa: BLE001
                reply = {"jsonrpc": "2.0", "id": rid,
                         "error": {"code": -32603, "message": str(exc)}}
            else:
                if rid is None:      # a notification: no reply, by protocol
                    continue
                reply = {"jsonrpc": "2.0", "id": rid, "result": result}
            sys.stdout.write(json.dumps(reply) + "\n")
            sys.stdout.flush()


# ── install ──────────────────────────────────────────────────────────────────


def config_path():
    """Where Claude Desktop actually reads its MCP config from.

    It is Electron's `app.getPath("userData")` + claude_desktop_config.json,
    and on Linux userData is `$XDG_CONFIG_HOME/<productName>` — so the
    directory is **Claude**, capitalised, not `claude`. Writing the lowercase
    spelling creates a second directory beside the real one, next to a config
    nothing ever reads: `starling-computer-use install` reported success and
    the server never appeared in the app. CLAUDE_USER_DATA_DIR overrides the
    whole thing, and the app honours it, so we do too.
    """
    override = os.environ.get("CLAUDE_USER_DATA_DIR")
    if override:
        return os.path.join(override, "claude_desktop_config.json")
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "Claude", "claude_desktop_config.json")


def cmd_install(argv):
    """Add ourselves to Claude Desktop's MCP config, MERGING — that file is the
    user's, and other servers in it are not ours to drop."""
    path = config_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        with open(path) as fh:
            cfg = json.load(fh)
    except (OSError, ValueError):
        cfg = {}
    if not isinstance(cfg, dict):
        raise SystemExit("%s is not a JSON object — refusing to rewrite it" % path)
    servers = cfg.setdefault("mcpServers", {})
    me = os.path.abspath(sys.argv[0])
    servers["starling-computer-use"] = {"command": me, "args": ["serve"]}
    tmp = path + ".new"
    with open(tmp, "w") as fh:
        json.dump(cfg, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, path)
    print("registered %s in %s" % (me, path))
    # Point at the file an earlier version of this command wrote to the wrong
    # place, rather than deleting something in the user's config directory.
    stale = os.path.expanduser("~/.config/claude/claude_desktop_config.json")
    if os.path.exists(stale) and os.path.abspath(stale) != os.path.abspath(path):
        print("note: %s is read by nothing — an earlier install wrote it "
              "there. Safe to delete." % stale)
    print("restart Claude Desktop to pick it up.")


# ── selftest ─────────────────────────────────────────────────────────────────


def cmd_selftest(argv):
    """Drive the executor from a terminal — the same path MCP takes, without a
    client. `selftest <app>` opens an app, screenshots it and prints what came
    back, which is the quickest way to see whether the desktop end works."""
    app = argv[0] if argv else "settings"
    ex = Executor(name="starling-computer-use selftest")
    print(ex.computer_windows()["text"])
    r = ex.run_batch([
        {"name": "computer_launch", "input": {"app": app}},
    ])
    print(r[0]["text"])
    win = r[0]["text"].rsplit(" ", 1)[-1]
    out = ex.run_batch([
        {"name": "computer_settled", "input": {"win": win}},
        {"name": "screenshot", "input": {"win": win}},
        {"name": "cursor_position", "input": {"win": win}},
    ])
    for item in out:
        print(("ERROR " if item.get("is_error") else "ok    ") + item.get("text", ""))
        if item.get("image") and len(argv) > 1:
            with open(argv[1], "wb") as fh:
                fh.write(item["image"])
            print("      wrote %s" % argv[1])


def main(argv):
    cmd = argv[0] if argv else "serve"
    if cmd == "serve":
        MCPServer().serve()
    elif cmd == "install":
        cmd_install(argv[1:])
    elif cmd == "selftest":
        cmd_selftest(argv[1:])
    else:
        raise SystemExit(__doc__.strip())


if __name__ == "__main__":
    main(sys.argv[1:])
