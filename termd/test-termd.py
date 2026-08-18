#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""Milestone 1 of docs/plans/remote-terminal.md, proved end to end.

The claim under test is the one the whole design rests on: a session
outlives its client, and a reattach at a byte offset resumes exactly —
no repeated bytes, no lost ones. Everything here speaks the wire protocol
directly over the wire, because the daemon has to be usable from a plain
pipe (a design decision in the plan) and because a test that went through
the Swift client would be testing two things at once.

Two transports, same checks. By default it connects to the unix socket. With
--stdio it drives `starling-termd --stdio` over its pipes instead, which is
what an ssh channel does -- and is the only way to run this on Windows, where
CPython does not expose AF_UNIX even though the OS has it.
"""
import os, queue, socket, struct, subprocess, sys, tempfile, threading, time

HDR = 8
(HELLO, HELLO_OK, LIST, LIST_REPLY, OPEN, ATTACH, ATTACHED, DATA, INPUT,
 RESIZE, ACK, EXIT, DETACH, ERROR, PING, PONG) = range(1, 17)
(WS_CREATE, WS_INFO, WS_LIST, WS_LIST_REPLY, WS_ADD, WS_SET_META,
 WS_GET_META, WS_META) = range(17, 25)
VERSION = 2

HERE = os.path.dirname(os.path.abspath(__file__))
WINDOWS = sys.platform == "win32"
if WINDOWS:
    # The console defaults to cp1252, which cannot encode the rule this prints
    # as its heading — and an encoding error there aborts the whole run before
    # a single check has been made.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
BIN = os.path.join(HERE, "starling-termd" + (".exe" if WINDOWS else ""))
USE_STDIO = "--stdio" in sys.argv or WINDOWS

# The session runs whatever shell the platform has, so the fixture that drives
# it cannot be one string. Same three markers, same pauses, either way.
# How long a shell takes to say anything, and how far apart the fixture puts
# its markers. ConPTY plus PowerShell is roughly an order of magnitude slower
# to start than /bin/sh, so both numbers are scaled rather than guessed at.
BOOT = 15.0 if WINDOWS else 2.0
STEP = 2.0 if WINDOWS else 0.4

# Prints the multiplexer markers a session must NOT have inherited, wrapped in
# brackets so an empty one is still visible in the stream and a check can tell
# "unset" from "the fixture never ran".
if WINDOWS:
    MUX_SCRIPT = 'cmd.exe /c echo MUX[%TMUX%][%TERM_PROGRAM%]'
    # cmd leaves an unset %VAR% as the literal text, so that is what absence
    # looks like here rather than an empty pair of brackets.
    MUX_CLEAN = b"MUX[%TMUX%][%TERM_PROGRAM%]"
else:
    MUX_SCRIPT = "printf 'MUX[%s][%s]\\n' \"$TMUX\" \"$TERM_PROGRAM\""
    MUX_CLEAN = b"MUX[][]"

if WINDOWS:
    # cmd, not PowerShell, and no inner quotes. powershell.exe -Command with a
    # quoted multi-statement string loses its quotes somewhere between
    # CreateProcessW and its own parser, and answers by prompting
    # "Supply values for the following parameters" instead of running anything.
    # `ping -n N` is the delay that needs no console of its own.
    SCRIPT = ('cmd.exe /c echo FIRST& ping -n 3 127.0.0.1 >nul'
              '& echo SECOND& ping -n 3 127.0.0.1 >nul'
              '& echo THIRD& ping -n 60 127.0.0.1 >nul')
    ECHO_INPUT = b"echo termd-input-works\r"
    PROMPT = b">"      # PS C:\...>
    NAMED_SCRIPT = 'cmd.exe /c echo NAMED-ONE& ping -n 60 127.0.0.1 >nul'
else:
    SCRIPT = ("printf 'FIRST\\n'; sleep 0.4; printf 'SECOND\\n'; "
              "sleep 0.4; printf 'THIRD\\n'; sleep 30")
    ECHO_INPUT = b"echo termd-input-works\n"
    PROMPT = b"$"
    NAMED_SCRIPT = "printf 'NAMED-ONE\\n'; sleep 30"

fails = []


def check(name, ok, detail=""):
    print(f"  {'ok  ' if ok else 'FAIL'}  {name}{'' if ok else '  — ' + detail}")
    if not ok:
        fails.append(name)


def frame(kind, payload=b""):
    return struct.pack("<BBHI", kind, 0, 0, len(payload)) + payload


def open_payload(cols=80, rows=24, name="", command=""):
    """An OPEN body: the name is length-prefixed so the command can be free."""
    n = name.encode()
    return struct.pack("<HHH", cols, rows, len(n)) + n + command.encode()


def ws_entries(payload):
    """WS_LIST_REPLY → [(ws_id, blob_len, [session ids], name)]."""
    count = struct.unpack("<H", payload[:2])[0]
    out, off = [], 2
    for _ in range(count):
        wid, blob_len, nses = struct.unpack("<IIH", payload[off:off + 10])
        off += 10
        sessions = list(struct.unpack("<" + "I" * nses, payload[off:off + 4 * nses]))
        off += 4 * nses
        nlen = struct.unpack("<H", payload[off:off + 2])[0]
        off += 2
        name = payload[off:off + nlen].decode("utf-8", "replace")
        off += nlen
        out.append((wid, blob_len, sessions, name))
    return out


def list_entries(payload):
    """LIST_REPLY → [(id, cols, rows, alive, seq, name)].

    Entries are variable-length since names arrived, so this walks rather
    than indexing.
    """
    count = struct.unpack("<H", payload[:2])[0]
    out, off = [], 2
    for _ in range(count):
        if off + 19 > len(payload):
            break
        sid, cols, rows, alive, seq, nlen = struct.unpack(
            "<IHHBQH", payload[off:off + 19])
        name = payload[off + 19:off + 19 + nlen].decode("utf-8", "replace")
        out.append((sid, cols, rows, alive, seq, name))
        off += 19 + nlen
    return out


class Client:
    """One connection to the daemon, over a socket or over a --stdio bridge.

    The pipe case needs a reader thread: there is no select() on a pipe on
    Windows, and recv() below wants a timeout.
    """

    def __init__(self, path):
        self.buf = b""
        self.sock = None
        self.proc = None
        self.q = None
        if USE_STDIO:
            env = dict(os.environ, STARLING_TERMD_SOCKET=path)
            self.proc = subprocess.Popen(
                [BIN, "--stdio"], env=env,
                stdin=subprocess.PIPE, stdout=subprocess.PIPE)
            self.q = queue.Queue()
            t = threading.Thread(target=self._drain, daemon=True)
            t.start()
        else:
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.sock.settimeout(5)
            self.sock.connect(path)

    def _drain(self):
        # os.read on the raw fd, not stdout.read(n): the buffered reader waits
        # for all n bytes, which for a stream that arrives in bursts means the
        # test sees nothing until well past its own timeout.
        fd = self.proc.stdout.fileno()
        while True:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                chunk = b""
            self.q.put(chunk)
            if not chunk:
                return

    def send(self, kind, payload=b""):
        if self.proc:
            self.proc.stdin.write(frame(kind, payload))
            self.proc.stdin.flush()
        else:
            self.sock.sendall(frame(kind, payload))

    def recv(self, want=None, timeout=3.0):
        """Next frame, or the next frame of type `want`, dropping others."""
        end = time.time() + timeout
        while True:
            while len(self.buf) >= HDR:
                kind, _, _, ln = struct.unpack("<BBHI", self.buf[:HDR])
                if len(self.buf) < HDR + ln:
                    break
                payload = self.buf[HDR:HDR + ln]
                self.buf = self.buf[HDR + ln:]
                if want is None or kind == want:
                    return kind, payload
            if time.time() > end:
                return None, b""
            if self.proc:
                try:
                    chunk = self.q.get(timeout=max(0.05, end - time.time()))
                except queue.Empty:
                    return None, b""
            else:
                self.sock.settimeout(max(0.05, end - time.time()))
                try:
                    chunk = self.sock.recv(65536)
                except socket.timeout:
                    return None, b""
            if not chunk:
                return None, b""
            self.buf += chunk

    def hello(self):
        self.send(HELLO, struct.pack("<H", VERSION))
        kind, payload = self.recv(HELLO_OK)
        return kind == HELLO_OK

    def collect(self, seconds=1.0, until=None):
        """Every DATA byte that arrives within a window, plus the next offset.

        With `until`, returns as soon as that marker has been seen. A fixed
        window cannot serve both platforms: a POSIX shell prints within
        milliseconds and ConPTY plus PowerShell takes well over a second, so
        a window generous enough for Windows would swallow the next phase of
        the fixture on Linux.
        """
        out, first, nxt = b"", None, None
        end = time.time() + seconds
        while time.time() < end:
            if until is not None and until in out:
                break
            kind, payload = self.recv(timeout=max(0.05, end - time.time()))
            if kind == DATA:
                seq = struct.unpack("<Q", payload[:8])[0]
                if first is None:
                    first = seq
                out += payload[8:]
                nxt = seq + len(payload) - 8
        return out, first, nxt

    def close(self):
        try:
            if self.proc:
                self.proc.stdin.close()
                self.proc.terminate()
            else:
                self.sock.close()
        except OSError:
            pass


def main():
    if not os.path.exists(BIN):
        print("build it first: make -C termd")
        return 2

    tmp = tempfile.mkdtemp(prefix="termd-test-")
    sock_path = os.path.join(tmp, "sock")
    # Started the way a daemon launched from inside tmux is, so the scrub has
    # something real to remove: without these the check below passes on a
    # build that does nothing at all.
    env = dict(os.environ, STARLING_TERMD_SOCKET=sock_path,
               TMUX="/tmp/tmux-1000/default,1,0", TMUX_PANE="%0",
               TERM_PROGRAM="tmux", TERM_PROGRAM_VERSION="3.6")
    # STARLING_TERMD_DEBUG=<file> keeps the daemon's own log, which is the
    # only view of what the pty reader threads did.
    dbg = os.environ.get("STARLING_TERMD_DEBUG")
    argv = [BIN, "--serve", "--idle-exit", "60"] + (["-v"] if dbg else [])
    log = open(dbg, "wb") if dbg else subprocess.DEVNULL
    daemon = subprocess.Popen(argv, env=env,
                              stdout=subprocess.DEVNULL,
                              stderr=(log if dbg else subprocess.DEVNULL))
    for _ in range(150):
        if os.path.exists(sock_path):
            break
        time.sleep(0.02)

    try:
        print("── termd: sessions that outlive their client ─────────────────")

        # A session that keeps producing after its client leaves.
        a = Client(sock_path)
        check("hello handshake", a.hello())
        a.send(OPEN, open_payload(command=SCRIPT))
        kind, payload = a.recv(ATTACHED)
        check("open returns a session", kind == ATTACHED)
        sid = struct.unpack("<I", payload[:4])[0]

        seen, _, next_off = a.collect(BOOT, until=b"FIRST")
        check("first output arrives", b"FIRST" in seen, repr(seen[:80]))
        a.close()

        # …the shell keeps running while nobody is attached…
        time.sleep(STEP * 1.6)

        # …and a reattach at the offset resumes exactly there.
        b = Client(sock_path)
        b.hello()
        b.send(ATTACH, struct.pack("<IQHH", sid, next_off, 80, 24))
        kind, payload = b.recv(ATTACHED)
        got_id, resume = struct.unpack("<IQ", payload[:12])
        check("reattach honours the offset", kind == ATTACHED and got_id == sid
              and resume == next_off, f"asked {next_off}, got {resume}")

        tail, first_seq, _ = b.collect(STEP * 3, until=b"SECOND")
        check("output produced while detached is there", b"SECOND" in tail,
              repr(tail[:120]))
        check("nothing before the offset is repeated", b"FIRST" not in tail,
              repr(tail[:120]))
        check("the stream resumes at the asked-for byte", first_seq == next_off,
              f"{first_seq} != {next_off}")
        b.close()

        # A fresh client asking from zero gets the whole history back.
        c = Client(sock_path)
        c.hello()
        c.send(ATTACH, struct.pack("<IQHH", sid, 0, 80, 24))
        c.recv(ATTACHED)
        whole, first_seq, _ = c.collect(STEP * 3, until=b"SECOND")
        check("replay from zero has everything", b"FIRST" in whole
              and b"SECOND" in whole, repr(whole[:160]))
        check("replay from zero starts at zero", first_seq == 0, str(first_seq))
        c.close()

        # …and a client that asks for a CAP gets the tail instead. This is what
        # keeps a six-pane workspace from replaying eight megabytes per pane on
        # a slow link. The field is trailing, so the frames above — which do not
        # send it — must keep meaning exactly what they meant before.
        cap = Client(sock_path)
        cap.hello()
        cap.send(ATTACH, struct.pack("<IQHHI", sid, 0, 80, 24, 8))
        kind, payload = cap.recv(ATTACHED)
        capped_from = struct.unpack("<IQ", payload[:12])[1] if kind == ATTACHED else 0
        check("a capped attach starts near the end, not at zero",
              kind == ATTACHED and capped_from >= next_off, str(capped_from))
        short, first_seq, _ = cap.collect(STEP * 1.5)
        check("a capped attach replays only the tail", b"FIRST" not in short,
              repr(short[:120]))
        check("a capped attach is honest about where it starts",
              first_seq == capped_from or not short,
              f"{first_seq} != {capped_from}")
        cap.close()

        # A cap larger than the history is not a truncation — it means "all of
        # it", the same as leaving the field out.
        big = Client(sock_path)
        big.hello()
        big.send(ATTACH, struct.pack("<IQHHI", sid, 0, 80, 24, 1 << 30))
        big.recv(ATTACHED)
        everything, first_seq, _ = big.collect(STEP * 3, until=b"SECOND")
        check("a cap wider than the ring still replays everything",
              b"FIRST" in everything and first_seq == 0, str(first_seq))
        big.close()

        # Input reaches the shell, and its echo comes back on the same stream.
        d = Client(sock_path)
        d.hello()
        d.send(OPEN, open_payload())                 # no command: a shell
        kind, payload = d.recv(ATTACHED)
        shell_id = struct.unpack("<I", payload[:4])[0]
        d.collect(BOOT, until=PROMPT)   # let the prompt actually appear
        d.send(INPUT, ECHO_INPUT)
        echoed, _, _ = d.collect(BOOT, until=b"termd-input-works")
        check("input reaches the shell", b"termd-input-works" in echoed,
              repr(echoed[-120:]))

        # LIST sees both sessions.
        d.send(LIST)
        kind, payload = d.recv(LIST_REPLY)
        ids = {e[0] for e in list_entries(payload)} if kind == LIST_REPLY else set()
        check("list reports the sessions", {sid, shell_id} <= ids,
              f"{ids} missing one of {sid},{shell_id}")
        d.close()

        # Names: the handle a human can remember. `termd "iOS dev"` has to
        # reach the same shell tomorrow without anyone recalling a number,
        # which makes a named OPEN attach-or-create rather than always create.
        n1 = Client(sock_path)
        n1.hello()
        n1.send(OPEN, open_payload(name="iOS dev", command=NAMED_SCRIPT))
        kind, payload = n1.recv(ATTACHED)
        named_id = struct.unpack("<I", payload[:4])[0] if kind == ATTACHED else 0
        check("a named open returns a session", kind == ATTACHED)
        marked, _, _ = n1.collect(BOOT, until=b"NAMED-ONE")
        check("the named session runs", b"NAMED-ONE" in marked, repr(marked[:80]))
        n1.close()

        n2 = Client(sock_path)
        n2.hello()
        n2.send(LIST)
        kind, payload = n2.recv(LIST_REPLY)
        by_name = {e[5]: e[0] for e in list_entries(payload)}
        check("list reports the name", by_name.get("iOS dev") == named_id,
              f"{by_name} has no iOS dev at {named_id}")

        # Opening the same name resumes that shell — never forks a second one
        # beside it — and replays what it printed while nobody was attached.
        # The command is ignored on that path, so a name is safe to re-open.
        n2.send(OPEN, open_payload(name="iOS dev", command="echo SHOULD-NOT-RUN"))
        kind, payload = n2.recv(ATTACHED)
        again_id = struct.unpack("<I", payload[:4])[0] if kind == ATTACHED else 0
        check("re-opening a name attaches, never forks", again_id == named_id,
              f"{again_id} != {named_id}")
        back, _, _ = n2.collect(STEP * 3, until=b"NAMED-ONE")
        check("a named re-open replays the history", b"NAMED-ONE" in back,
              repr(back[:120]))
        check("the re-open ran no second command", b"SHOULD-NOT-RUN" not in back,
              repr(back[:120]))
        n2.close()

        # A name typed with a stray space or a control byte is the same name:
        # otherwise a paste that carried one silently opens a second session.
        n3 = Client(sock_path)
        n3.hello()
        n3.send(OPEN, open_payload(name="  iOS dev\x07 ", command=NAMED_SCRIPT))
        kind, payload = n3.recv(ATTACHED)
        trimmed_id = struct.unpack("<I", payload[:4])[0] if kind == ATTACHED else 0
        check("a name matches after trimming and control bytes",
              trimmed_id == named_id, f"{trimmed_id} != {named_id}")
        n3.close()

        # `starling-termd "name"` — the attach client. It is the one part of
        # the binary that touches a terminal, and it must not RENDER any of
        # it: DATA goes to stdout untouched. What is checked here is the
        # plumbing around that, because every piece of it is a way to strand
        # a user's terminal or their session.
        att_env = dict(env, STARLING_TERMD_SOCKET=sock_path)
        ap = subprocess.Popen([BIN, "attach probe"], env=att_env,
                              stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE)
        aq = queue.Queue()
        threading.Thread(target=lambda: [aq.put(c) or (c or None)
                                         for c in iter(lambda: os.read(
                                             ap.stdout.fileno(), 65536), b"")],
                         daemon=True).start()

        def acollect(seconds, until=None):
            out, end = b"", time.time() + seconds
            while time.time() < end:
                try:
                    chunk = aq.get(timeout=0.1)
                except queue.Empty:
                    continue
                if not chunk:
                    break
                out += chunk
                if until and until in out:
                    break
            return out

        acollect(BOOT if WINDOWS else 1.0, until=PROMPT)
        ap.stdin.write(ECHO_INPUT)
        ap.stdin.flush()
        seen = acollect(BOOT, until=b"termd-input-works")
        check("attach carries input and output", b"termd-input-works" in seen,
              repr(seen[-120:]))

        # ^] d detaches. Without a stolen key there is no way out of a
        # byte-exact tunnel at all, and the session must survive the exit.
        ap.stdin.write(b"\x1dd")
        ap.stdin.flush()
        try:
            ap.wait(timeout=5)
            check("^] d detaches the client", ap.returncode == 0,
                  f"rc={ap.returncode}")
        except subprocess.TimeoutExpired:
            check("^] d detaches the client", False, "client never exited")
            ap.kill()

        probe = Client(sock_path)
        probe.hello()
        probe.send(LIST)
        kind, payload = probe.recv(LIST_REPLY)
        alive = {e[5]: e[3] for e in list_entries(payload)}
        check("the session outlives the detached client",
              alive.get("attach probe") == 1, str(alive))
        probe.close()

        # The tty half, which only exists on POSIX. Raw mode is what makes
        # the tunnel byte-exact — and OPOST in particular, without which a
        # tunnelled session prints a staircase — and a client that fails to
        # put it back leaves the user's shell unusable after it exits.
        if not WINDOWS:
            import fcntl, pty, termios
            master, slave = pty.openpty()
            fcntl.ioctl(master, termios.TIOCSWINSZ,
                        struct.pack("HHHH", 30, 100, 0, 0))
            tp = subprocess.Popen([BIN, "tty probe"], env=att_env,
                                  stdin=slave, stdout=slave,
                                  stderr=subprocess.DEVNULL)
            os.close(slave)
            time.sleep(1.2)
            attrs = termios.tcgetattr(master)
            check("attach puts the terminal in raw mode",
                  not attrs[3] & termios.ICANON and not attrs[3] & termios.ECHO
                  and not attrs[1] & termios.OPOST, "termios still cooked")

            def sess_size(name):
                out = subprocess.run([BIN, "--list"], env=att_env,
                                     capture_output=True, text=True).stdout
                for line in out.splitlines():
                    if name in line:
                        return line.split()[-4]
                return "?"

            check("the session opens at the terminal's size",
                  sess_size("tty probe") == "100x30", sess_size("tty probe"))
            fcntl.ioctl(master, termios.TIOCSWINSZ,
                        struct.pack("HHHH", 44, 132, 0, 0))
            time.sleep(1.0)
            check("resizing the window resizes the session",
                  sess_size("tty probe") == "132x44", sess_size("tty probe"))

            os.write(master, b"\x1dd")
            try:
                tp.wait(timeout=5)
            except subprocess.TimeoutExpired:
                tp.kill()
            back = termios.tcgetattr(master)
            check("the terminal is restored on the way out",
                  bool(back[3] & termios.ICANON) and bool(back[1] & termios.OPOST),
                  "left raw")
            os.close(master)

        # A session does not inherit the multiplexer markers of whatever
        # started the daemon. Programs that adapt their drawing to their host
        # believe these, so a tmux-started daemon otherwise makes every
        # session render for a tmux that is not there.
        m = Client(sock_path)
        m.hello()
        m.send(OPEN, open_payload(command=MUX_SCRIPT))
        m.recv(ATTACHED)
        mux, _, _ = m.collect(BOOT, until=b"]")
        check("a session inherits no multiplexer markers", MUX_CLEAN in mux,
              repr(mux[-120:]))
        m.close()

        # --- workspaces ---------------------------------------------------
        # The daemon stores an arrangement it never parses. These checks are
        # the whole of milestone 2 in docs/plans/remote-workspace.md: create,
        # fill, write a blob, LOSE THE CONNECTION, come back and find it
        # byte-identical.
        BLOB = bytes(range(256)) * 3 + b"\x00\xff{\"panes\": [0.5, 0.5]}"

        w = Client(sock_path)
        w.hello()
        w.send(WS_CREATE, struct.pack("<H", 3) + b"dev")
        kind, payload = w.recv(WS_INFO)
        ws_id = struct.unpack("<I", payload[:4])[0]
        check("a workspace is created", kind == WS_INFO and ws_id > 0,
              f"frame {kind}")

        # Idempotent by name, like a named OPEN — a client that lost the id
        # must not end up with a second workspace beside the first.
        w.send(WS_CREATE, struct.pack("<H", 3) + b"dev")
        _, payload = w.recv(WS_INFO)
        check("creating the same workspace twice returns the same id",
              struct.unpack("<I", payload[:4])[0] == ws_id)

        sids = []
        for _ in range(3):
            w.send(OPEN, open_payload())
            _, payload = w.recv(ATTACHED)
            sid = struct.unpack("<I", payload[:4])[0]
            sids.append(sid)
            w.send(WS_ADD, struct.pack("<II", ws_id, sid))
            w.recv(WS_INFO)
            w.send(DETACH)
        check("three sessions join the workspace", len(set(sids)) == 3)

        w.send(WS_SET_META, struct.pack("<I", ws_id) + BLOB)
        w.recv(WS_INFO)
        # The connection dies here. This is the whole point: arrangement has
        # to outlive the client that arranged it.
        w.close()

        w2 = Client(sock_path)
        w2.hello()
        w2.send(WS_GET_META, struct.pack("<I", ws_id))
        kind, payload = w2.recv(WS_META)
        got = payload[4:]
        check("the layout blob survives the connection and is byte-identical",
              kind == WS_META and got == BLOB,
              f"{len(got)} bytes, wanted {len(BLOB)}")

        w2.send(WS_LIST)
        _, payload = w2.recv(WS_LIST_REPLY)
        entries = [e for e in ws_entries(payload) if e[0] == ws_id]
        check("the workspace lists its name, sessions and blob length",
              len(entries) == 1 and entries[0][3] == "dev"
              and sorted(entries[0][2]) == sorted(sids)
              and entries[0][1] == len(BLOB),
              repr(entries))

        # A session dying must not take the workspace or the blob with it —
        # the arrangement is the durable thing, the shells are not.
        k = Client(sock_path)
        k.hello()
        k.send(ATTACH, struct.pack("<IQHH", sids[0], 0, 80, 24))
        k.recv(ATTACHED)
        k.send(INPUT, b"exit\n")
        time.sleep(BOOT)
        k.close()

        w2.send(WS_LIST)
        _, payload = w2.recv(WS_LIST_REPLY)
        entries = [e for e in ws_entries(payload) if e[0] == ws_id]
        check("a dead session leaves the workspace and its blob intact",
              len(entries) == 1 and entries[0][1] == len(BLOB),
              repr(entries))

        w2.send(WS_GET_META, struct.pack("<I", 999))
        kind, payload = w2.recv(ERROR)
        check("an unknown workspace is an error, not an empty blob",
              kind == ERROR, f"frame {kind}")

        # Two clients on one workspace. Whoever writes last wins, and the
        # others are TOLD — without that they keep drawing the arrangement
        # they had and write it back over this one on their next change.
        # w2 is already watching (it asked for the blob above).
        w3 = Client(sock_path)
        w3.hello()
        w3.send(WS_CREATE, struct.pack("<H", len(b"dev")) + b"dev")
        w3.recv(WS_INFO)
        MOVED = BLOB + b"\x99"
        w3.send(WS_SET_META, struct.pack("<I", ws_id) + MOVED)

        kind, payload = w3.recv(WS_INFO, timeout=2.0)
        check("the client that wrote gets its acknowledgement",
              kind == WS_INFO, f"frame {kind}")
        kind, payload = w2.recv(WS_META, timeout=2.0)
        check("the other client is told, unasked",
              kind == WS_META and payload[4:] == MOVED,
              f"frame {kind}, {len(payload) - 4} bytes")

        # …and the writer is not told its own news, or two clients would
        # answer each other forever.
        kind, _ = w3.recv(WS_META, timeout=0.6)
        check("the writer is not sent its own arrangement back", kind is None,
              f"frame {kind}")

        # A connection that never named the workspace hears nothing about it.
        quiet = Client(sock_path)
        quiet.hello()
        w3.send(WS_SET_META, struct.pack("<I", ws_id) + BLOB)
        w3.recv(WS_INFO)
        kind, _ = quiet.recv(WS_META, timeout=0.6)
        check("a connection not watching hears nothing", kind is None,
              f"frame {kind}")
        quiet.close()
        w3.close()
        w2.close()

        # A wrong version is refused rather than half-spoken.
        e = Client(sock_path)
        e.send(HELLO, struct.pack("<H", 999))
        kind, payload = e.recv(ERROR)
        check("a version mismatch is an error", kind == ERROR,
              f"got frame {kind}")
        e.close()

    finally:
        daemon.terminate()
        try:
            daemon.wait(timeout=3)
        except subprocess.TimeoutExpired:
            daemon.kill()

    print()
    if fails:
        print(f"FAILED: {', '.join(fails)}")
        return 1
    print("all termd checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
