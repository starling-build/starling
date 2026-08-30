#!/usr/bin/env python3
# The computer-use MCP server against a FAKE broker — no desktop, no GPU.
#
# Everything between Claude Desktop and the shell is testable without either:
# the JSON-RPC framing, the tool list, the screenshot-pixel → content-logical
# coordinate mapping, chord parsing, PNG encoding, and the batch rule that
# stop-at-first-failure implies. The fake broker on the other end speaks the
# real JSON-lines protocol and records what it was asked to do, so a mapping
# bug shows up as the wrong coordinates arriving rather than as a screenshot a
# human has to squint at.
#
# What this deliberately does NOT cover: whether the compositor actually
# delivers those coordinates to the right pixel. That is the functional tier's
# job, and it needs a real desktop.

import base64
import json
import os
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
SERVER = REPO / "build" / "computer-use-mcp.py"

# The window the fake broker reports: 1280x1266 image px for 768x760 logical
# content px, which is what a real 0.6-of-a-2560x1600-panel window comes back
# as. The two are deliberately not a round factor of each other — a mapping
# that quietly assumes scale 2 passes on nice numbers and fails here.
IMG_W, IMG_H = 1280, 1266
CONTENT_W, CONTENT_H = 768.0, 760.0

failures = []


def check(name, got, want):
    if got == want:
        print("  ok    %s" % name)
    else:
        failures.append(name)
        print("  FAIL  %s: got %r, want %r" % (name, got, want))


def check_true(name, cond, detail=""):
    check(name, bool(cond) or detail or False, True)


class FakeBroker(threading.Thread):
    """The shell's agent socket, minus the shell. Records every request."""

    daemon = True

    def __init__(self, path):
        super().__init__()
        self.seen = []
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.bind(path)
        self.sock.listen(4)

    def run(self):
        while True:
            try:
                conn, _ = self.sock.accept()
            except OSError:
                return
            threading.Thread(target=self._serve, args=(conn,), daemon=True).start()

    def _serve(self, conn):
        f = conn.makefile("rwb")
        for line in f:
            try:
                req = json.loads(line)
            except ValueError:
                continue
            self.seen.append(req)
            reply = self._reply(req)
            reply["id"] = req.get("id")
            f.write((json.dumps(reply) + "\n").encode())
            f.flush()

    def _reply(self, req):
        op = req.get("op")
        if op == "hello":
            return {"ok": True, "proto": 1, "agent": "agent-1", "token": "tok",
                    "scope": {"launch": ["chrome", "files", "settings"],
                              "windows": "owned"}}
        if op == "list_windows":
            return {"ok": True, "windows": [
                {"win": "window-1", "app": "agent-1:settings#1",
                 "title": "Settings", "content": [CONTENT_W, CONTENT_H],
                 "focused": False}]}
        if op == "launch":
            if req.get("app") == "nosuchapp":
                return {"ok": False, "error": "unknown app (scope: chrome,files,settings)"}
            return {"ok": True, "win": "window-1", "content": [CONTENT_W, CONTENT_H]}
        if op == "capture":
            if req.get("win") != "window-1":
                return {"ok": False, "error": "no such owned window"}
            # A recognisable image rather than noise: opaque red, so a channel
            # swap or a stride mistake shows up as the wrong pixel value.
            px = bytes([0xFF, 0x00, 0x00, 0xFF]) * (IMG_W * IMG_H)
            return {"ok": True, "w": IMG_W, "h": IMG_H, "stride": IMG_W * 4,
                    "fourcc": "AB24", "format": "rgba", "row_order": "top-down",
                    "content": [CONTENT_W, CONTENT_H],
                    "scale": IMG_W / CONTENT_W, "source": "texture",
                    "data": base64.b64encode(px).decode()}
        if op == "inject":
            return {"ok": True}
        if op == "cursor_position":
            return {"ok": True, "x": 384.0, "y": 380.0}
        if op == "wait":
            return {"ok": True, "waited_ms": req.get("ms", 0)}
        if op == "await_settled":
            return {"ok": True, "settled_in_ms": 12}
        return {"ok": False, "error": "unknown op %s" % op}


class MCP:
    """One MCP client, over the same stdio pipe Claude Desktop would use."""

    def __init__(self, env, server=None, stderr=subprocess.DEVNULL):
        self.p = subprocess.Popen([sys.executable, str(server or SERVER), "serve"],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=stderr, env=env, bufsize=0)
        self.n = 0

    def rpc(self, method, params=None, notify=False):
        self.n += 1
        req = {"jsonrpc": "2.0", "method": method}
        if not notify:
            req["id"] = self.n
        if params is not None:
            req["params"] = params
        self.p.stdin.write((json.dumps(req) + "\n").encode())
        self.p.stdin.flush()
        if notify:
            return None
        return json.loads(self.p.stdout.readline())

    def call(self, name, **args):
        return self.rpc("tools/call", {"name": name, "arguments": args})["result"]

    def close(self):
        self.p.stdin.close()
        self.p.wait(timeout=10)


def text_of(result):
    return " ".join(c["text"] for c in result.get("content", [])
                    if c["type"] == "text")


def image_of(result):
    for c in result.get("content", []):
        if c["type"] == "image":
            return base64.b64decode(c["data"])
    return None


def main():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        broker = FakeBroker(str(root / "starling-agent.sock"))
        broker.start()

        # XDG_RUNTIME_DIR is where agent-client looks for the socket; HOME is
        # where it persists the agent identity, and pointing it at the temp
        # dir keeps the test from touching the developer's own.
        env = dict(os.environ, XDG_RUNTIME_DIR=str(root), HOME=str(root))
        mcp = MCP(env)

        # ── framing ──────────────────────────────────────────────────────
        init = mcp.rpc("initialize", {"protocolVersion": "2025-06-18",
                                      "capabilities": {},
                                      "clientInfo": {"name": "t", "version": "0"}})
        check("initialize names the server",
              init["result"]["serverInfo"]["name"], "starling-computer-use")
        check("initialize advertises tools",
              "tools" in init["result"]["capabilities"], True)
        mcp.rpc("notifications/initialized", {}, notify=True)

        tools = {t["name"] for t in mcp.rpc("tools/list")["result"]["tools"]}
        members = {"screenshot", "zoom", "left_click", "right_click",
                   "middle_click", "double_click", "triple_click",
                   "left_click_drag", "mouse_move", "left_mouse_down",
                   "left_mouse_up", "cursor_position", "type", "key",
                   "hold_key", "scroll", "wait"}
        check("all 17 toolset members are exposed", members - tools, set())
        check("the per-window tools are exposed too",
              {"computer_launch", "computer_windows", "computer_settled"} - tools,
              set())

        # ── the INSTALLED layout ─────────────────────────────────────────
        #
        # stage.sh drops the two scripts into bin/ under their command names,
        # with no `.py` on the end — and the server loads its client library
        # by path, which is extension-sensitive. Run the same server out of
        # that layout, because the repo layout is the only one where the
        # extension is present and it is therefore the only one where a
        # loader bug cannot show up. It shipped exactly once for that reason.
        binroot = root / "bin"
        binroot.mkdir()
        for src, dst in ((SERVER, "starling-computer-use"),
                         (REPO / "build" / "agent-client.py", "agent-client")):
            (binroot / dst).write_bytes(src.read_bytes())
            (binroot / dst).chmod(0o755)
        # A server that dies on import answers nothing at all, so this reads
        # the reply defensively and reports the traceback rather than raising
        # one of its own — a failing check tells you what broke, a crashing
        # test tells you the test broke.
        installed = MCP(env, server=binroot / "starling-computer-use",
                        stderr=subprocess.PIPE)
        try:
            init2 = installed.rpc("initialize", {"protocolVersion": "2025-06-18",
                                                 "capabilities": {},
                                                 "clientInfo": {"name": "t",
                                                                "version": "0"}})
            name = init2.get("result", {}).get("serverInfo", {}).get("name")
        except Exception:
            name = None
        if name != "starling-computer-use":
            installed.p.kill()
            err = (installed.p.stderr.read() or b"").decode()[-400:]
            print("        server stderr: %s" % err.strip().replace("\n", "\n        "))
        check("the server runs from the installed, extensionless layout",
              name, "starling-computer-use")
        installed.close()

        # ── pixels ───────────────────────────────────────────────────────
        r = mcp.call("computer_launch", app="settings")
        check("launch reports the window", text_of(r), "launched settings as window-1")

        r = mcp.call("screenshot", win="window-1")
        png = image_of(r)
        check("screenshot returns a PNG", png[:8], b"\x89PNG\r\n\x1a\n")
        w, h = struct.unpack(">II", png[16:24])
        check("the PNG is the broker's image, unresized", (w, h), (IMG_W, IMG_H))
        # Decode the first pixel the long way, to catch a channel swap.
        i, first = 8, None
        while i < len(png):
            ln = struct.unpack(">I", png[i:i + 4])[0]
            if png[i + 4:i + 8] == b"IDAT":
                raw = zlib.decompress(png[i + 8:i + 8 + ln])
                first = tuple(raw[1:5])       # skip the row filter byte
                break
            i += 12 + ln
        check("pixels survive the round trip unswapped", first, (0xFF, 0, 0, 0xFF))
        check("the broker was asked to downscale",
              broker.seen[-1].get("max_px"), 1280)

        # ── coordinates ──────────────────────────────────────────────────
        # The whole coordinate contract in one assertion: the model gives
        # screenshot pixels, the broker must receive content-local logical px.
        mcp.call("left_click", win="window-1", coordinate=[640, 633])
        ev = broker.seen[-1]["ev"]
        check("a click maps screenshot px to content-local logical px",
              (round(ev["x"], 3), round(ev["y"], 3)),
              (round(640 * CONTENT_W / IMG_W, 3), round(633 * CONTENT_H / IMG_H, 3)))
        check("left_click is a click", ev["type"], "click")

        mcp.call("right_click", win="window-1", coordinate=[0, 0])
        check("right_click is rclick", broker.seen[-1]["ev"]["type"], "rclick")
        mcp.call("double_click", win="window-1", coordinate=[10, 10])
        check("double_click is dblclick", broker.seen[-1]["ev"]["type"], "dblclick")

        mcp.call("left_click_drag", win="window-1",
                 start_coordinate=[0, 0], coordinate=[1280, 1266])
        ev = broker.seen[-1]["ev"]
        check("a drag carries both endpoints",
              (ev["type"], round(ev["x2"]), round(ev["y2"])),
              ("drag", round(CONTENT_W), round(CONTENT_H)))

        mcp.call("scroll", win="window-1", coordinate=[100, 100],
                 scroll_direction="down", scroll_amount=3)
        ev = broker.seen[-1]["ev"]
        check("scrolling down moves content up (negative dy)",
              (ev["type"], ev["dy"] < 0), ("scroll", True))

        # ── keyboard ─────────────────────────────────────────────────────
        before = len(broker.seen)
        mcp.call("key", win="window-1", text="ctrl+s")
        seq = [r["ev"] for r in broker.seen[before:]]
        check("a chord is held modifier, key, released modifier",
              [(e["type"], e["physical"]) for e in seq],
              [("keydown", 0xE0), ("key", 0x16), ("keyup", 0xE0)])

        r = mcp.call("key", win="window-1", text="ctrl+nosuchkey")
        check("an unknown key name is an error, not a wrong keypress",
              (r.get("isError"), "no key named" in text_of(r)), (True, True))

        mcp.call("type", win="window-1", text="hello")
        check("type goes through as text", broker.seen[-1]["ev"]["type"], "text")

        # ── scope ────────────────────────────────────────────────────────
        r = mcp.call("screenshot", win="window-99")
        check("an unowned window is refused",
              (r.get("isError"), "no such owned window" in text_of(r)), (True, True))

        r = mcp.call("nonexistent_tool", win="window-1")
        check("an unknown tool is refused", r.get("isError"), True)

        # ── batch semantics ──────────────────────────────────────────────
        # Not reachable over MCP (one tool per call), so exercise the executor
        # directly — the conformance loop and any future toolset frontend
        # depend on it, and the contract fixes the wording.
        import importlib.util
        spec = importlib.util.spec_from_file_location("cu", str(SERVER))
        cu = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cu)
        # In-process this time, so OUR env decides which socket it finds. A
        # developer with a real desktop up has a real broker socket sitting in
        # the default location, and without this the batch checks would drive
        # their live session instead of the fake.
        os.environ["XDG_RUNTIME_DIR"] = str(root)
        os.environ["HOME"] = str(root)
        ex = cu.Executor(name="mcp_framing batch")
        out = ex.run_batch([
            {"name": "computer_launch", "input": {"app": "settings"}},
            {"name": "computer_launch", "input": {"app": "nosuchapp"}},
            {"name": "screenshot", "input": {"win": "window-1"}},
        ])
        check("a batch stops at the first failure",
              [bool(o.get("is_error")) for o in out], [False, True, True])
        check("the skipped result uses the contract's exact wording",
              out[2]["text"],
              "Not executed: an earlier computer action in this turn failed.")
        check("nothing ran after the failure",
              broker.seen[-1]["op"], "launch")

        mcp.close()

    if failures:
        print("FAIL — %d check(s)" % len(failures))
        return 1
    print("all MCP framing checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
