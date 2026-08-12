#!/usr/bin/env python3
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
"""Milestone 1 of docs/plans/remote-terminal.md, proved end to end.

The claim under test is the one the whole design rests on: a session
outlives its client, and a reattach at a byte offset resumes exactly —
no repeated bytes, no lost ones. Everything here speaks the wire protocol
directly over the unix socket, because the daemon has to be usable from a
plain pipe (a design decision in the plan) and because a test that went
through the Swift client would be testing two things at once.
"""
import os, socket, struct, subprocess, sys, tempfile, time

HDR = 8
(HELLO, HELLO_OK, LIST, LIST_REPLY, OPEN, ATTACH, ATTACHED, DATA, INPUT,
 RESIZE, ACK, EXIT, DETACH, ERROR, PING, PONG) = range(1, 17)
VERSION = 1

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(HERE, "starling-termd")

fails = []


def check(name, ok, detail=""):
    print(f"  {'ok  ' if ok else 'FAIL'}  {name}{'' if ok else '  — ' + detail}")
    if not ok:
        fails.append(name)


def frame(kind, payload=b""):
    return struct.pack("<BBHI", kind, 0, 0, len(payload)) + payload


class Client:
    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(5)
        self.sock.connect(path)
        self.buf = b""

    def send(self, kind, payload=b""):
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

    def collect(self, seconds=1.0):
        """Every DATA byte that arrives within a window, plus the next offset."""
        out, first, nxt = b"", None, None
        end = time.time() + seconds
        while time.time() < end:
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
            self.sock.close()
        except OSError:
            pass


def main():
    if not os.path.exists(BIN):
        print("build it first: make -C termd")
        return 2

    tmp = tempfile.mkdtemp(prefix="termd-test-")
    sock_path = os.path.join(tmp, "sock")
    env = dict(os.environ, STARLING_TERMD_SOCKET=sock_path)
    daemon = subprocess.Popen([BIN, "--serve", "--idle-exit", "60"], env=env,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(100):
        if os.path.exists(sock_path):
            break
        time.sleep(0.02)

    try:
        print("── termd: sessions that outlive their client ─────────────────")

        # A session that keeps producing after its client leaves.
        a = Client(sock_path)
        check("hello handshake", a.hello())
        script = ("printf 'FIRST\\n'; sleep 0.4; printf 'SECOND\\n'; "
                  "sleep 0.4; printf 'THIRD\\n'; sleep 30")
        a.send(OPEN, struct.pack("<HH", 80, 24) + script.encode())
        kind, payload = a.recv(ATTACHED)
        check("open returns a session", kind == ATTACHED)
        sid = struct.unpack("<I", payload[:4])[0]

        seen, _, next_off = a.collect(0.25)
        check("first output arrives", b"FIRST" in seen, repr(seen[:80]))
        a.close()

        # …the shell keeps running while nobody is attached…
        time.sleep(1.0)

        # …and a reattach at the offset resumes exactly there.
        b = Client(sock_path)
        b.hello()
        b.send(ATTACH, struct.pack("<IQHH", sid, next_off, 80, 24))
        kind, payload = b.recv(ATTACHED)
        got_id, resume = struct.unpack("<IQ", payload[:12])
        check("reattach honours the offset", kind == ATTACHED and got_id == sid
              and resume == next_off, f"asked {next_off}, got {resume}")

        tail, first_seq, _ = b.collect(0.6)
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
        whole, first_seq, _ = c.collect(0.6)
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
        d.collect(0.4)                                # let the prompt settle
        d.send(INPUT, b"echo termd-input-works\n")
        echoed, _, _ = d.collect(1.2)
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
