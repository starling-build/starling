#!/usr/bin/env python3
"""Run a PowerShell command inside a libvirt Windows guest via the QEMU guest agent.

Usage:  winrun.py [-d DOMAIN] [-t TIMEOUT] '<powershell command>'
        winrun.py --file <local.ps1>        # run a script file's contents
"""
import argparse
import base64
import json
import subprocess
import sys
import time

DEFAULT_DOMAIN = "passage-srv2025"


def agent(domain, payload, timeout=60):
    cmd = ["sudo", "-n", "virsh", "qemu-agent-command", "--timeout", str(timeout),
           domain, json.dumps(payload)]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"virsh failed: {out.stderr.strip()}")
    return json.loads(out.stdout)["return"]


def run(domain, ps, timeout=600):
    # -EncodedCommand takes UTF-16LE base64; avoids every quoting problem.
    enc = base64.b64encode(ps.encode("utf-16-le")).decode()
    r = agent(domain, {
        "execute": "guest-exec",
        "arguments": {
            "path": "powershell.exe",
            "arg": ["-NoProfile", "-NonInteractive", "-EncodedCommand", enc],
            "capture-output": True,
        },
    })
    pid = r["pid"]
    deadline = time.time() + timeout
    delay = 0.3
    while time.time() < deadline:
        st = agent(domain, {"execute": "guest-exec-status", "arguments": {"pid": pid}})
        if st.get("exited"):
            def dec(k):
                return base64.b64decode(st[k]).decode("utf-8", "replace") if st.get(k) else ""
            return st.get("exitcode", 0), dec("out-data"), dec("err-data")
        time.sleep(delay)
        delay = min(delay * 1.5, 5.0)
    raise TimeoutError(f"guest command still running after {timeout}s (pid {pid})")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("command", nargs="?")
    p.add_argument("-d", "--domain", default=DEFAULT_DOMAIN)
    p.add_argument("-t", "--timeout", type=int, default=600)
    p.add_argument("-f", "--file", help="read the PowerShell script from this file")
    a = p.parse_args()

    ps = open(a.file).read() if a.file else a.command
    if not ps:
        p.error("need a command or --file")

    code, out, err = run(a.domain, ps, a.timeout)
    if out:
        sys.stdout.write(out)
    if err:
        sys.stderr.write(err)
    sys.exit(code)


if __name__ == "__main__":
    main()
