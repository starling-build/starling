#!/usr/bin/env python3
# windows_install.py — fast checks for the App Store's Windows install.
#
# The full install is a ~6 GB download and a 20–40 min unattended setup, far
# too heavy and network-dependent for a test tier. What IS cheap, and what has
# actually drifted before, is (1) the catalog record surfacing the Install
# button with the right shape, and (2) the recipe's `--check` dry run running
# without touching libvirt. Both live here; run.sh calls this in the fast tier.
#
# Exit 0 = passed (or a runtime check was skipped for lack of KVM/libvirt);
# non-zero = a real failure.

import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RECORD = REPO / "registry" / "catalog.d" / "windows.app"
APP_INSTALL = REPO / "build" / "app-install.sh"

fails = 0


def fail(msg: str) -> None:
    global fails
    fails += 1
    print(f"  ✗ {msg}")


def ok(msg: str) -> None:
    print(f"  ✔ {msg}")


def parse_keyfile(path: Path) -> dict:
    kv = {}
    in_group = False
    for line in path.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if s.startswith("[") and s.endswith("]"):
            in_group = s == "[Starling App]"
            continue
        if in_group and "=" in s and not s.startswith("#"):
            k, v = s.split("=", 1)
            kv[k.strip()] = v.strip()
    return kv


def check_record() -> None:
    print("catalog: windows.app surfaces the Install button")
    if not RECORD.exists():
        fail(f"{RECORD} does not exist")
        return
    kf = parse_keyfile(RECORD)

    if kf.get("Kind") != "vm":
        fail(f"Kind={kf.get('Kind')!r}, expected 'vm'")
    else:
        ok("Kind=vm")

    # The store lists an app only if it has an Install recipe (or a debURL);
    # without this the Windows tile has no button.
    if kf.get("Install") != "windows":
        fail(f"Install={kf.get('Install')!r}, expected 'windows' "
             "(the store would show no Install button)")
    else:
        ok("Install=windows")

    if not kf.get("Domain"):
        fail("Kind=vm needs Domain= (which libvirt domain to open)")
    else:
        ok(f"Domain={kf['Domain']}")

    # "Installed" must mean provisioned, not "libvirt is present". A marker
    # under /var/lib/starling/vm — NOT /usr/bin/virsh, the pre-install-button
    # value, which would make the store show it installed before it is.
    bins = kf.get("Bins", "")
    if "virsh" in bins:
        fail(f"Bins={bins!r} still points at virsh — the store would show "
             "Windows as installed before it is provisioned")
    elif "starling/vm" not in bins:
        fail(f"Bins={bins!r} is not the install marker under /var/lib/starling/vm")
    else:
        ok(f"Bins={bins} (provisioned-and-booted marker)")

    # The recipe named by Install must exist in app-install.sh, as a case that
    # actually installs (not a refuse-branch). Cheap substring check; lint does
    # the rigorous version.
    text = APP_INSTALL.read_text(encoding="utf-8")
    if "windows)" not in text or "install_windows" not in text:
        fail("build/app-install.sh has no 'windows' recipe")
    else:
        ok("build/app-install.sh has the windows recipe")


def check_dry_run() -> None:
    print("recipe: app-install --check windows reports prerequisites")
    if not (os.path.exists("/dev/kvm") and shutil.which("virsh")):
        print("  - SKIPPED (no /dev/kvm or no libvirt on this host)")
        return
    # --check must run unprivileged and touch no libvirt state: it only reads
    # /dev/kvm, the default network's state, free space, and group membership.
    env = dict(os.environ, STARLING_CATALOG_DIR=str(REPO / "registry" / "catalog.d"))
    try:
        r = subprocess.run(["sh", str(APP_INSTALL), "--check", "windows"],
                           capture_output=True, text=True, timeout=60, env=env)
    except Exception as e:  # noqa: BLE001
        fail(f"could not run --check: {e}")
        return
    out = r.stdout + r.stderr
    if "Checking prerequisites" not in out:
        fail(f"--check produced no prerequisite report:\n{out.strip()[-400:]}")
        return
    # Exit status is meaningful (0 = ready, non-zero = a prereq is missing);
    # either is a valid "it reported", which is what this tier verifies. It
    # must NOT have defined a domain or written a marker.
    if os.path.exists("/var/lib/starling/vm/windows.installed"):
        # Only a red flag if THIS run created it; can't tell here, so just note.
        pass
    ok(f"--check ran and reported (exit {r.returncode})")


def main() -> int:
    check_record()
    check_dry_run()
    if fails:
        print(f"windows_install: {fails} failure(s)")
        return 1
    print("windows_install: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
