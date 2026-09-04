#!/usr/bin/env python3
"""Copy a local file into a libvirt Windows guest through the QEMU agent.

`guest-exec` cannot carry a large payload on its command line — a source
file's worth of base64 fails with "Failed to execute helper program (Invalid
argument)" well before the file is big. `guest-file-open`/`write`/`close` has
no such limit, so this chunks through that instead. It is the inverse of
`winrun.py` and needs nothing installed in the guest.

    winput.py -d <domain> <local-file> <guest-path>
"""
import argparse
import base64
import json
import subprocess

# Base64 of this stays well inside the agent's frame; larger chunks start
# failing the same way the command line does, and the failure is not
# obviously about size.
CHUNK = 48 * 1024


def agent(domain, payload, timeout=60):
    out = subprocess.run(
        ["sudo", "-n", "virsh", "qemu-agent-command", "--timeout", str(timeout),
         domain, json.dumps(payload)], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip())
    return json.loads(out.stdout)["return"]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("-d", "--domain", required=True)
    p.add_argument("local")
    p.add_argument("remote")
    a = p.parse_args()

    with open(a.local, "rb") as f:
        data = f.read()
    handle = agent(a.domain, {"execute": "guest-file-open",
                              "arguments": {"path": a.remote, "mode": "wb"}})
    try:
        for i in range(0, len(data), CHUNK):
            agent(a.domain, {"execute": "guest-file-write",
                             "arguments": {"handle": handle,
                                           "buf-b64": base64.b64encode(
                                               data[i:i + CHUNK]).decode()}})
    finally:
        agent(a.domain, {"execute": "guest-file-close",
                         "arguments": {"handle": handle}})
    print("wrote %d bytes to %s" % (len(data), a.remote))


main()
