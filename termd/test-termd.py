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
VERSION = 1

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
else:
    SCRIPT = ("printf 'FIRST\\n'; sleep 0.4; printf 'SECOND\\n'; "
              "sleep 0.4; printf 'THIRD\\n'; sleep 30")
    ECHO_INPUT = b"echo termd-input-works\n"
    PROMPT = b"$"

fails = []


def check(name, ok, detail=""):
    print(f"  {'ok  ' if ok else 'FAIL'}  {name}{'' if ok else '  — ' + detail}")
    if not ok:
        fails.append(name)


def frame(kind, payload=b""):
    return struct.pack("<BBHI", kind, 0, 0, len(payload)) + payload


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
        a.send(OPEN, struct.pack("<HH", 80, 24) + SCRIPT.encode())
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

        # Input reaches the shell, and its echo comes back on the same stream.
        d = Client(sock_path)
        d.hello()
        d.send(OPEN, struct.pack("<HH", 80, 24))     # no command: a shell
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
        count = struct.unpack("<H", payload[:2])[0] if kind == LIST_REPLY else 0
        ids = {struct.unpack("<I", payload[2 + i * 17:6 + i * 17])[0]
               for i in range(count)}
        check("list reports the sessions", {sid, shell_id} <= ids,
              f"{ids} missing one of {sid},{shell_id}")
        d.close()

        # A session does not inherit the multiplexer markers of whatever
        # started the daemon. Programs that adapt their drawing to their host
        # believe these, so a tmux-started daemon otherwise makes every
        # session render for a tmux that is not there.
        m = Client(sock_path)
        m.hello()
        m.send(OPEN, struct.pack("<HH", 80, 24) + MUX_SCRIPT.encode())
        m.recv(ATTACHED)
        mux, _, _ = m.collect(BOOT, until=b"]")
        check("a session inherits no multiplexer markers", MUX_CLEAN in mux,
              repr(mux[-120:]))
        m.close()

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
