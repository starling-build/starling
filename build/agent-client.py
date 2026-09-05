#!/usr/bin/env python3
"""agent-client.py — drive the Starling desktop from the command line.

One command per invocation, so an agent harness (or a shell script, or a
person) can compose them. The agent identity persists between invocations in a
state file, which is what makes `launch` in one command and `click` in the next
address the same window — window ownership is per agent, and each process
otherwise gets a fresh one.

    agent-client.py launch chrome https://example.com   -> prints the window id
    agent-client.py windows                             -> what this agent owns
    agent-client.py goto   <win> <url>
    agent-client.py fill   <win> <css-selector> <text>
    agent-client.py click  <win> <css-selector>
    agent-client.py text   <win> [css-selector]         -> read the page back
    agent-client.py shot   <win> <out.png>
    agent-client.py tree   <win>                        -> first-party app UI tree
    agent-client.py act    <win> <node-id> <action>
    agent-client.py settled <win>                       -> wait for repaint
    agent-client.py reset                               -> forget the identity

Every action goes through the shell's agent broker; web pages are driven by the
Chrome DevTools Protocol. Nothing here injects pixel coordinates — pages are
addressed by CSS selector and first-party apps by semantic node, so a command
fails loudly instead of silently clicking empty space.
"""

import base64
import glob
import json
import zlib
import os
import socket
import struct
import sys
import time
import urllib.request

# ── broker ───────────────────────────────────────────────────────────────────


def broker_path() -> str:
    # Own session first; the glob covers driving a session owned by someone
    # else (root tooling) — the runtime dir is per-user, /tmp/xdg-starling-<uid>.
    dirs = [os.environ.get("XDG_RUNTIME_DIR"), "/run/user/%d" % os.getuid(),
            "/tmp/xdg-starling-%d" % os.getuid()]
    dirs += sorted(glob.glob("/tmp/xdg-starling-*"))
    for d in dirs:
        if d and os.path.exists(os.path.join(d, "starling-agent.sock")):
            return os.path.join(d, "starling-agent.sock")
    sys.exit("no starling-agent.sock — is the Starling shell running?")


class Broker:
    """One connection to the shell's agent broker."""

    def __init__(self, name: str = "agent-client.py",
                 agent: str = None, token: str = None):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(broker_path())
        self.f = self.sock.makefile("rwb")
        self._id = 0
        args = {"name": name}
        if agent and token:
            args["agent"] = agent
            args["token"] = token
        try:
            hello = self.call("hello", **args)
        except RuntimeError:
            # The stored identity is gone (the shell restarted, most likely).
            # Registering anew beats failing — the caller re-saves what it gets.
            if not (agent and token):
                raise
            hello = self.call("hello", name=name)
        self.agent_id = hello["agent"]
        self.token = hello.get("token")
        self.reattached = bool(hello.get("reattached"))
        self.scope = hello.get("scope", {})

    def call(self, op: str, **args):
        """One request/response. Raises on a broker-level failure."""
        self._id += 1
        req = {"id": self._id, "op": op}
        req.update(args)
        self.f.write((json.dumps(req) + "\n").encode())
        self.f.flush()
        while True:
            line = self.f.readline()
            if not line:
                raise RuntimeError("broker closed the connection")
            msg = json.loads(line)
            # Unsolicited pushes (app status) carry no id — skip them.
            if msg.get("id") != self._id:
                continue
            if not msg.get("ok"):
                raise RuntimeError("%s failed: %s" % (op, msg.get("error")))
            return msg


# ── a minimal Chrome DevTools Protocol client ────────────────────────────────
#
# CDP is JSON over one WebSocket. The stdlib has no WebSocket client, and this
# is the whole of what the protocol needs from one: an HTTP upgrade, text
# frames out (masked, as clients must), text frames in.


class CDP:
    def __init__(self, ws_url: str):
        assert ws_url.startswith("ws://"), ws_url
        rest = ws_url[len("ws://"):]
        hostport, _, path = rest.partition("/")
        host, _, port = hostport.partition(":")
        self.sock = socket.create_connection((host, int(port or 80)), timeout=30)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((
            "GET /%s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\n"
            "Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n" % (path, hostport, key)
        ).encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise RuntimeError("CDP handshake failed")
            buf += chunk
        if b" 101 " not in buf.split(b"\r\n")[0]:
            raise RuntimeError("CDP handshake refused: %s" % buf.split(b"\r\n")[0])
        self._rest = buf.split(b"\r\n\r\n", 1)[1]
        self._id = 0

    # -- framing --

    def _send(self, payload: bytes):
        header = bytearray([0x81])  # FIN + text
        n = len(payload)
        mask = os.urandom(4)
        if n < 126:
            header.append(0x80 | n)
        elif n < (1 << 16):
            header.append(0x80 | 126)
            header += struct.pack(">H", n)
        else:
            header.append(0x80 | 127)
            header += struct.pack(">Q", n)
        header += mask
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(bytes(header) + masked)

    def _read(self, n: int) -> bytes:
        while len(self._rest) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError("CDP connection closed")
            self._rest += chunk
        out, self._rest = self._rest[:n], self._rest[n:]
        return out

    def _recv(self) -> dict:
        while True:
            b0, b1 = self._read(2)
            opcode = b0 & 0x0F
            length = b1 & 0x7F
            if length == 126:
                length = struct.unpack(">H", self._read(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self._read(8))[0]
            data = self._read(length)
            if opcode == 0x8:                      # close
                raise RuntimeError("CDP closed the connection")
            if opcode == 0x9:                      # ping -> pong
                continue
            if opcode in (0x1, 0x2):
                return json.loads(data)

    # -- protocol --

    def call(self, method: str, session: str = None, **params) -> dict:
        self._id += 1
        msg = {"id": self._id, "method": method, "params": params}
        if session:
            msg["sessionId"] = session
        self._send(json.dumps(msg).encode())
        while True:
            msg = self._recv()
            if msg.get("id") != self._id:
                continue               # an event, or another call's reply
            if "error" in msg:
                raise RuntimeError("%s: %s" % (method, msg["error"]))
            return msg.get("result", {})


def attach_to_page(browser_ws: str, targets_url: str, prefer_url: str = None) -> tuple:
    """Attach to a page target. Returns (cdp, sessionId-or-None).

    Connecting straight to the page's own debugger URL is the simplest path
    and needs no session id at all; the browser endpoint plus an explicit
    attach is the fallback. Note the HTTP target list names the id `id`,
    while the protocol calls the same thing `targetId`.
    """
    pages = []
    for _ in range(40):
        with urllib.request.urlopen(targets_url, timeout=20) as r:
            targets = json.load(r)
        pages = [t for t in targets if t.get("type") == "page"]
        if pages:
            break
        time.sleep(0.5)
    if not pages:
        raise RuntimeError("Chrome has no page target yet")

    page = pages[0]
    if prefer_url:
        page = next((p for p in pages if (p.get("url") or "").startswith(prefer_url)), page)

    if page.get("webSocketDebuggerUrl"):
        return CDP(page["webSocketDebuggerUrl"]), None
    cdp = CDP(browser_ws)
    attached = cdp.call("Target.attachToTarget",
                        targetId=page.get("targetId") or page["id"], flatten=True)
    return cdp, attached["sessionId"]



# ── persistent identity ──────────────────────────────────────────────────────
#
# Window ownership is per agent and each process gets its own connection, so a
# CLI that registered fresh every time could never touch the window its
# previous invocation launched. The broker issues a token at registration and
# accepts it to re-attach; this keeps it, 0600, next to the socket.


def state_path() -> str:
    for d in (os.environ.get("XDG_RUNTIME_DIR"), "/run/user/%d" % os.getuid(),
              "/tmp/xdg-starling-%d" % os.getuid()):
        if d and os.path.isdir(d):
            return os.path.join(d, "starling-agent-client.json")
    return os.path.expanduser("~/.starling-agent-client.json")


def load_state() -> dict:
    try:
        with open(state_path()) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def save_state(state: dict):
    path = state_path()
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        json.dump(state, fh)


def connect(name: str = "agent-client.py") -> Broker:
    """Connect, re-attaching to the stored identity when there is one.

    A stale identity — the shell restarted, so the agent is gone — is not an
    error worth failing on: drop it and register anew.
    """
    state = load_state()
    agent = Broker(name=name, agent=state.get("agent"), token=state.get("token"))
    if agent.agent_id != state.get("agent") or agent.token != state.get("token"):
        save_state({"agent": agent.agent_id, "token": agent.token})
    return agent


# ── web pages, over the DevTools protocol ────────────────────────────────────


def page(agent: Broker, win: str):
    """Attach to the page of an agent-owned Chrome window."""
    for attempt in range(40):
        try:
            ep = agent.call("cdp_endpoint", win=win)
            break
        except RuntimeError:
            if attempt == 39:
                raise
            time.sleep(0.5)
    return attach_to_page(ep["browser_ws"], ep["targets_url"])


def js(cdp, session, expression: str):
    r = cdp.call("Runtime.evaluate", session=session,
                 expression=expression, returnByValue=True, awaitPromise=True)
    if r.get("exceptionDetails"):
        raise RuntimeError("page error: %s"
                           % r["exceptionDetails"].get("text", "unknown"))
    return r.get("result", {}).get("value")


def require(cdp, session, selector: str):
    """Wait for a selector to exist, then return it. Fails loudly if it never does."""
    for _ in range(60):
        if js(cdp, session, "!!document.querySelector(%s)" % json.dumps(selector)):
            return selector
        time.sleep(0.25)
    raise SystemExit("no element matches %s" % selector)


# ── commands ─────────────────────────────────────────────────────────────────


def cmd_launch(argv):
    if not argv:
        raise SystemExit("launch needs an app (chrome, files, settings, terminal)")
    agent = connect()
    args = {"app": argv[0]}
    if len(argv) > 1:
        args["url"] = argv[1]
    print(agent.call("launch", **args)["win"])


def cmd_windows(argv):
    agent = connect()
    for w in agent.call("list_windows").get("windows", []):
        print("%s  %-22s %s" % (w.get("win"), w.get("app", ""), w.get("title", "")))


def cmd_goto(argv):
    if len(argv) < 2:
        raise SystemExit("goto needs <win> <url>")
    agent = connect()
    cdp, session = page(agent, argv[0])
    cdp.call("Page.enable", session=session)
    cdp.call("Page.navigate", session=session, url=argv[1])
    for _ in range(80):
        if js(cdp, session, "document.readyState") == "complete":
            break
        time.sleep(0.25)
    print("loaded %s" % js(cdp, session, "document.title"))


def cmd_fill(argv):
    if len(argv) < 3:
        raise SystemExit("fill needs <win> <selector> <text>")
    win, selector, text = argv[0], argv[1], " ".join(argv[2:])
    agent = connect()
    cdp, session = page(agent, win)
    require(cdp, session, selector)
    js(cdp, session, "document.querySelector(%s).focus()" % json.dumps(selector))
    # insertText goes through Chrome's input pipeline, so the page sees real
    # input events and a human watching the pane sees it typed.
    cdp.call("Input.insertText", session=session, text=text)
    print("filled %s" % selector)


def cmd_click(argv):
    if len(argv) < 2:
        raise SystemExit("click needs <win> <selector>")
    agent = connect()
    cdp, session = page(agent, argv[0])
    require(cdp, session, argv[1])
    js(cdp, session, "document.querySelector(%s).click()" % json.dumps(argv[1]))
    print("clicked %s" % argv[1])


def cmd_text(argv):
    if not argv:
        raise SystemExit("text needs <win> [selector]")
    agent = connect()
    cdp, session = page(agent, argv[0])
    selector = argv[1] if len(argv) > 1 else "body"
    require(cdp, session, selector)
    out = js(cdp, session,
             "(document.querySelector(%s)||{}).innerText||''" % json.dumps(selector))
    print((out or "").strip())


def write_png(path: str, rgba: bytes, width: int, height: int):
    """Minimal PNG writer — the client stays stdlib-only, and zlib is stdlib."""
    raw = b"".join(b"\x00" + rgba[y * width * 4:(y + 1) * width * 4]
                   for y in range(height))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n")
        fh.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
        fh.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        fh.write(chunk(b"IEND", b""))


def _png_to_rgba(data: bytes) -> tuple:
    """Decode a PNG (8-bit, colour type 2 or 6) to top-down RGBA. Stdlib only,
    the mirror of png_bytes above: guest captures arrive as PNG because the
    channel to the VM is serial and a raw-RGBA window is megabytes (M3 Phase 2,
    docs/plans/guest-agents.md)."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    off, width, height, bit, colour = 8, 0, 0, 0, 0
    idat = bytearray()
    while off < len(data):
        ln = struct.unpack(">I", data[off:off + 4])[0]
        tag = data[off + 4:off + 8]
        body = data[off + 8:off + 8 + ln]
        if tag == b"IHDR":
            width, height, bit, colour = struct.unpack(">IIBB", body[:10])
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
        off += 12 + ln
    if bit != 8 or colour not in (2, 6):
        raise ValueError(f"unsupported PNG (bit={bit} colour={colour})")
    src = zlib.decompress(bytes(idat))
    chans = 4 if colour == 6 else 3
    stride = width * chans
    out = bytearray(height * width * 4)
    prev = bytearray(stride)
    pos = 0
    for y in range(height):
        ft = src[pos]; pos += 1
        row = bytearray(src[pos:pos + stride]); pos += stride
        # Reverse the PNG filter for this scanline (None/Sub/Up/Average/Paeth).
        if ft == 1:
            for i in range(chans, stride):
                row[i] = (row[i] + row[i - chans]) & 0xFF
        elif ft == 2:
            for i in range(stride):
                row[i] = (row[i] + prev[i]) & 0xFF
        elif ft == 3:
            for i in range(stride):
                a = row[i - chans] if i >= chans else 0
                row[i] = (row[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif ft == 4:
            for i in range(stride):
                a = row[i - chans] if i >= chans else 0
                b = prev[i]
                c = prev[i - chans] if i >= chans else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                row[i] = (row[i] + pr) & 0xFF
        elif ft != 0:
            raise ValueError(f"bad PNG filter {ft}")
        # To RGBA, forcing alpha opaque for a colour-type-2 (no-alpha) image.
        o = y * width * 4
        if chans == 4:
            out[o:o + stride] = row
        else:
            for x in range(width):
                out[o + x * 4:o + x * 4 + 3] = row[x * 3:x * 3 + 3]
                out[o + x * 4 + 3] = 0xFF
        prev = row
    return bytes(out), width, height


def capture_to_rgba(shot: dict) -> tuple:
    """Turn a broker capture into (rgba, width, height).

    `capture` hands back the window's buffer as it sits in memory — raw
    pixels plus the three facts needed to read them, none of which are
    optional: `stride` (rows are padded), `fourcc` (channel order), and
    `row_order` (first-party children render bottom-up because GL's origin is
    bottom-left, Wayland buffers are top-down). Writing `data` straight to a
    .png produces a file that is not a PNG.
    """
    # A guest window arrives as PNG (M3 Phase 2) — self-describing, so there
    # is no stride/fourcc/row_order to apply; decode and we are done.
    if shot.get("format") == "png":
        return _png_to_rgba(base64.b64decode(shot["data"]))
    data = base64.b64decode(shot["data"])
    width, height, stride = shot["w"], shot["h"], shot["stride"]
    fourcc = (shot.get("fourcc") or "")
    # 'AB24'/'XB24' are R,G,B,A in memory — already RGBA. 'AR24'/'XR24' are
    # B,G,R,A and need the red and blue channels swapped. An X format carries
    # no alpha, so force it opaque rather than trusting the padding byte.
    swap_rb = fourcc.startswith(("AR", "XR"))
    opaque = fourcc.startswith(("X",))
    rows = []
    for y in range(height):
        off = y * stride
        row = bytearray(data[off:off + width * 4])
        if swap_rb:
            row[0::4], row[2::4] = row[2::4], row[0::4]
        if opaque:
            row[3::4] = b"\xff" * width
        rows.append(bytes(row))
    if shot.get("row_order") == "bottom-up":
        rows.reverse()
    return b"".join(rows), width, height


def cmd_shot(argv):
    if len(argv) < 2:
        raise SystemExit("shot needs <win> <out.png>")
    agent = connect()
    # The broker's capture is an mmap of the window's DMA-BUF, which only
    # first-party children have; a Wayland client like Chrome has none, so fall
    # back to the page's own screenshot and say which produced the image.
    try:
        shot = agent.call("capture", win=argv[0])
        rgba, width, height = capture_to_rgba(shot)
        # An all-zero buffer is not a black window, it is a failed read, and
        # writing it out as a screenshot would be the worst outcome: an agent
        # would "see" a black app and reason about it. Observed on a
        # virtualised GPU, where the compositor still composites the window
        # correctly — it imports the DMA-BUF as a GPU texture and never maps
        # it — while the CPU mapping this op relies on comes back empty.
        if not any(rgba[::499]):
            raise SystemExit(
                "capture of %s read back as entirely empty (%dx%d, %s). The "
                "window is composited from the GPU, so the buffer has content;"
                " the CPU mapping does not see it. Known on virtualised GPUs."
                % (argv[0], width, height, shot.get("fourcc")))
        write_png(argv[1], rgba, width, height)
        print("captured %dx%d via the broker -> %s" % (width, height, argv[1]))
        return
    except RuntimeError as exc:
        broker_error = exc
    cdp, session = page(agent, argv[0])
    data = cdp.call("Page.captureScreenshot", session=session)["data"]
    with open(argv[1], "wb") as fh:
        fh.write(base64.b64decode(data))
    print("broker capture unavailable (%s); captured the page via CDP -> %s"
          % (broker_error, argv[1]))


def cmd_tree(argv):
    if not argv:
        raise SystemExit("tree needs <win>")
    agent = connect()
    reply = agent.call("semantic_tree", win=argv[0])
    for node in reply.get("nodes", []):
        actions = ",".join(node.get("actions", []))
        # The id field is "node" — "id" is the request/response envelope's.
        print("%-5s %-40s %s" % (node.get("node"), (node.get("label") or "")[:40], actions))


def cmd_act(argv):
    if len(argv) < 3:
        raise SystemExit("act needs <win> <node-id> <action>")
    agent = connect()
    agent.call("perform_action", win=argv[0], node=int(argv[1]), action=argv[2])
    print("performed %s on node %s" % (argv[2], argv[1]))


def cmd_settled(argv):
    if not argv:
        raise SystemExit("settled needs <win>")
    agent = connect()
    reply = agent.call("await_settled", win=argv[0])
    print("settled in %sms" % reply.get("settled_in_ms", reply.get("waited_ms", "?")))


def cmd_reset(argv):
    try:
        os.unlink(state_path())
        print("forgot the stored agent identity")
    except FileNotFoundError:
        print("no stored identity")


COMMANDS = {
    "launch": cmd_launch, "windows": cmd_windows, "goto": cmd_goto,
    "fill": cmd_fill, "click": cmd_click, "text": cmd_text, "shot": cmd_shot,
    "tree": cmd_tree, "act": cmd_act, "settled": cmd_settled, "reset": cmd_reset,
}


def main() -> int:
    argv = sys.argv[1:]
    if not argv or argv[0] in ("-h", "--help", "help"):
        sys.exit(__doc__)
    cmd = COMMANDS.get(argv[0])
    if cmd is None:
        sys.exit("unknown command %r\n\n%s" % (argv[0], __doc__))
    try:
        cmd(argv[1:])
    except RuntimeError as exc:
        sys.exit("error: %s" % exc)
    return 0


if __name__ == "__main__":
    sys.exit(main())
