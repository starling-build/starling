#!/usr/bin/env python3
"""Record a TUI's raw byte stream from a pty, for the detection corpus.

Writes exactly what the program wrote — escape sequences included — so a
recording can be replayed through the emulator and asserted against.
"""
import argparse
import fcntl
import os
import pty
import select
import signal
import struct
import subprocess
import sys
import termios
import time


def record(argv, out_path, feed, cols, rows, idle_stop, max_wall):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    proc = subprocess.Popen(
        argv, stdin=slave, stdout=slave, stderr=slave,
        start_new_session=True, close_fds=True,
    )
    os.close(slave)

    out = open(out_path, "wb")
    started = time.time()
    last_data = started
    total = 0
    # Each feed entry is (delay_seconds_from_start, bytes).
    pending = list(feed)

    try:
        while True:
            now = time.time()
            if now - started > max_wall:
                break
            while pending and now - started >= pending[0][0]:
                _, data = pending.pop(0)
                os.write(master, data)

            r, _, _ = select.select([master], [], [], 0.2)
            if r:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                out.write(chunk)
                total += len(chunk)
                last_data = time.time()
            else:
                # Idle only counts once the program has actually drawn and
                # every scripted keystroke has been delivered.
                if total > 0 and not pending and time.time() - last_data > idle_stop:
                    break
    finally:
        out.close()
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        os.close(master)

    return total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--cols", type=int, default=100)
    ap.add_argument("--rows", type=int, default=30)
    ap.add_argument("--idle-stop", type=float, default=5.0)
    ap.add_argument("--max-wall", type=float, default=120.0)
    ap.add_argument("--cwd")
    # "delay:text" — text is sent as-is with a trailing \r unless it ends in \\
    ap.add_argument("--send", action="append", default=[])
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    args = ap.parse_args()

    argv = args.cmd[1:] if args.cmd and args.cmd[0] == "--" else args.cmd
    if not argv:
        sys.exit("no command")

    feed = []
    for spec in args.send:
        delay, _, text = spec.partition(":")
        raw = text.endswith("\\")
        text = text[:-1] if raw else text + "\r"
        feed.append((float(delay), text.encode().decode("unicode_escape").encode()))

    # Resolved before the chdir below, or a relative --out lands somewhere
    # surprising (or, more often, fails outright).
    out_path = os.path.abspath(args.out)
    if args.cwd:
        os.chdir(args.cwd)

    n = record(argv, out_path, feed, args.cols, args.rows,
               args.idle_stop, args.max_wall)
    print(f"{n} bytes -> {args.out}")


if __name__ == "__main__":
    main()
