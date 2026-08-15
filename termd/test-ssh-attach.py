#!/usr/bin/env python3
"""Attach a termd session over ssh, from a POSIX box to a Windows daemon.

test-termd.py speaks the protocol over pipes, which is enough to check every
frame and every offset — and it cannot see the two bugs that made termd
unusable over ssh, because both live in the seam between a real terminal and
the daemon:

  - a Windows console under a ConPTY reports key EVENTS, not key bytes, so
    the prefix scan never matched and ^] d never detached (and every cursor
    key was replayed at the far end as Escape, '[', 'A');
  - Windows OpenSSH runs each session inside a job object and kills the job
    on disconnect, so the "detached" daemon died with the client it was
    started by — the one thing this program exists to prevent.

Both passed the protocol suite while failing in the field. So this drives the
real thing: ssh -tt gives the client a pty on both ends, and the checks below
are the promises termd makes to a person, in the order they would meet them.

    ./test-ssh-attach.py                      # uses the defaults below
    TERMD_SSH_HOST=me@win ./test-ssh-attach.py

Needs: a Windows host running sshd with key auth, starling-termd.exe built
there (sdk-style: tools\\build-windows.ps1), and PowerShell as the login
shell — the remote command is written in it.
"""
import fcntl
import os
import select
import struct
import subprocess
import sys
import termios
import time

HOST = os.environ.get("TERMD_SSH_HOST", "dishengsu@192.168.122.153")
KEY = os.environ.get("TERMD_SSH_KEY",
                     os.path.expanduser("~/starling-win-vm/winvm_key"))
KNOWN = os.environ.get("TERMD_SSH_KNOWN_HOSTS",
                       os.path.expanduser("~/starling-win-vm/known_hosts_win"))
EXE = os.environ.get("TERMD_REMOTE_EXE",
                     r"C:\src\starling\termd\starling-termd.exe")
NAME = "ssh attach test"
COLS, ROWS = 100, 30

SSH = ["ssh", "-i", KEY, "-o", "StrictHostKeyChecking=no",
       "-o", f"UserKnownHostsFile={KNOWN}", "-o", "BatchMode=yes",
       "-o", "LogLevel=ERROR"]

results = []


def check(name, ok, detail=""):
    results.append((name, ok))
    print(f"  {'ok  ' if ok else 'FAIL'}  {name}" + ("" if ok else f"  — {detail}"))


def ssh_run(ps, timeout=60):
    """One non-interactive PowerShell command on the far side."""
    p = subprocess.run(SSH + [HOST, ps], capture_output=True, text=True,
                       timeout=timeout)
    return p.stdout + p.stderr


class Attach:
    """`ssh -tt host starling-termd <name>`, driven through a real pty."""

    def __init__(self, name):
        self.master, slave = pty_open()
        # The size the session should open at. Set BEFORE ssh starts, because
        # ssh reports the size it sees when it asks for the remote pty.
        fcntl.ioctl(self.master, termios.TIOCSWINSZ,
                    struct.pack("HHHH", ROWS, COLS, 0, 0))
        self.p = subprocess.Popen(SSH + ["-tt", HOST, f"& '{EXE}' '{name}'"],
                                  stdin=slave, stdout=slave, stderr=slave,
                                  close_fds=True)
        os.close(slave)
        self.buf = b""

    def _pump(self):
        r, _, _ = select.select([self.master], [], [], 0.4)
        if not r:
            return True
        try:
            chunk = os.read(self.master, 65536)
        except OSError:
            return False
        if not chunk:
            return False
        self.buf += chunk
        return True

    def read_count(self, pattern, times, timeout=30):
        """Wait for `pattern` to arrive `times` over.

        A typed line echoes once as it is typed and again as the command's
        output, so a check that stops at the first sight is only proving the
        echo — which is exactly what it looked like when this raced.
        """
        deadline = time.time() + timeout
        while time.time() < deadline:
            if not self._pump():
                break
            if self.buf.count(pattern) >= times:
                return True
        return False

    def read_until(self, pattern, timeout=30):
        return self.read_count(pattern, 1, timeout)

    def send(self, data):
        os.write(self.master, data)

    def wait_exit(self, timeout=15):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.p.poll() is not None:
                return self.p.returncode
            time.sleep(0.25)
        return None

    def close(self):
        try:
            self.p.kill()
        except Exception:
            pass
        try:
            os.close(self.master)
        except Exception:
            pass


def pty_open():
    import pty
    return pty.openpty()


print("── termd over ssh: a POSIX client, a Windows daemon ───────────")

# This wants the cold path, and an earlier run may have left a daemon up.
ssh_run("Get-Process starling-termd -EA SilentlyContinue | Stop-Process -Force")
time.sleep(1)
cold = ssh_run(f"& '{EXE}' --list")
check("no daemon on a cold machine", "no daemon" in cold, cold.strip()[:120])

# ── first attach: creates the session ──────────────────────────────────────
a = Attach(NAME)
check("attaching by name over ssh starts a session",
      a.read_until(b">", timeout=40), repr(a.buf[-160:]))

a.send(b"$marker = 'termd-ssh-4242'; echo $marker\r")
check("keystrokes reach the shell and output comes back",
      a.read_count(b"termd-ssh-4242", 2), repr(a.buf[-200:]))

# A cursor key must arrive as ESC [ A and recall the line just run. Forwarded
# as raw key events it lands as Escape then "[A", which clears the line and
# types into it instead — passing every protocol check on the way.
#
# Match on the recalled TEXT rather than the whole command line: the shell
# redraws it with colour escapes between the words, so "echo $marker" is not
# a contiguous byte string on screen even when the recall worked perfectly.
seen_before = a.buf.count(b"termd-ssh-4242")
mark = len(a.buf)
a.send(b"\x1b[A")
recalled = a.read_count(b"termd-ssh-4242", seen_before + 1, timeout=15)
check("the up arrow recalls the last command, not '[A'",
      recalled and b"[A" not in a.buf[mark:], repr(a.buf[mark:][-160:]))

# Non-ASCII, all three shapes: a two-byte UTF-8 character, three-byte CJK,
# and a four-byte emoji whose surrogate halves arrive Alt+Numpad style — on
# the key-UP of Alt, which a decoder that drops key-ups silently eats. The
# expected text appears twice, typed echo and command output; matching on
# the payload alone dodges the colour escapes the shell paints between
# tokens. These were ALL broken over ssh once: the session console decoded
# input bytes at the OEM code page, and no chcp after the fact could reach
# the decision. The daemon now sets the console to UTF-8 the way sshd does.
a.send("echo café\r".encode())
check("a two-byte character round-trips (café)",
      a.read_count("café".encode(), 2), repr(a.buf[-120:]))
a.send("echo 日本語\r".encode())
check("CJK round-trips (日本語)",
      a.read_count("日本語".encode(), 2), repr(a.buf[-120:]))
a.send("echo \U0001F389\r".encode())
check("an astral-plane character round-trips (emoji)",
      a.read_count("\U0001F389".encode(), 2), repr(a.buf[-120:]))

listing = ssh_run(f"& '{EXE}' --list")
check("the session is listed while attached", NAME in listing, listing.strip()[:200])
check(f"the session opened at the terminal's size ({COLS}x{ROWS})",
      f"{COLS}x{ROWS}" in listing, listing.strip()[:200])

# ── detach ─────────────────────────────────────────────────────────────────
a.send(b"\x1dd")
rc = a.wait_exit()
check("^] d detaches and ssh exits", rc == 0, f"rc={rc}")
a.close()

check("the session outlives the ssh client",
      NAME in ssh_run(f"& '{EXE}' --list"))

# The client is gone politely; now make one vanish. This is the job-object
# case: ssh dying used to take the daemon with it.
b = Attach(NAME)
b.read_until(b"termd-ssh-4242", timeout=40)
b.close()
time.sleep(3)
check("the session survives an ssh client that is killed outright",
      NAME in ssh_run(f"& '{EXE}' --list"))

# ── reattach: same session, same shell ─────────────────────────────────────
c = Attach(NAME)
check("reattaching replays the history",
      c.read_until(b"termd-ssh-4242", timeout=40), repr(c.buf[-200:]))

c.send(b"echo \"still-here:$marker\"\r")
# Once, not twice: the typed line carries "$marker", so only the shell's own
# output can contain the expanded value — which is the whole point of the
# check. No replay could produce it; only the original shell still running.
check("the shell itself survived — its variable is still set",
      c.read_until(b"still-here:termd-ssh-4242"), repr(c.buf[-200:]))

c.send(b"\x1dd")
c.wait_exit()
c.close()

ssh_run("Get-Process starling-termd -EA SilentlyContinue | Stop-Process -Force")

bad = [n for n, ok in results if not ok]
print()
print("all ssh-attach checks passed" if not bad
      else f"{len(bad)} FAILED: " + "; ".join(bad))
sys.exit(1 if bad else 0)
