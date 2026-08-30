#!/usr/bin/env bash
# Drive the WSL gate from here.
#
#   test/wsl/run-gate.sh                       # build, ship and gate
#   test/wsl/run-gate.sh --no-build            # gate the .deb already there
#   STARLING_WIN_HOST=user@host test/wsl/run-gate.sh
#
# WHY THIS GATE EXISTS AND WHERE IT RUNS
#
# WSL has no `/dev/dri` — none, not an empty one — so the DRM path the desktop
# normally takes cannot start there at all. RDP DISPLAY MODE is the whole
# product on that platform: the RDP surface IS the display, rendered
# surfacelessly through llvmpipe. Nothing on the dev box tests that, because
# the dev box has a GPU and takes the other path. This is the gate for it.
#
# The distro is Ubuntu 26.04 under WSL2 on a PHYSICAL Windows box (not the
# win11-gpu VM, which has no WSL). Everything runs inside the distro,
# including the RDP client that drives it, so no Windows-side scheduling is
# needed — unlike test/win/run-gate.sh, which has to become an interactive
# task to see a desktop at all.
#
# Exit code is the gate's: 0 if every check passed.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
# The box is on DHCP and has moved once. If ssh cannot reach it, sweep the
# subnet for port 22 and confirm `hostname` reads DESKTOP-URK35LH.
HOST="${STARLING_WIN_HOST:-starling@192.168.68.56}"
DISTRO="${STARLING_WSL_DISTRO:-Ubuntu-26.04}"
BUILD=1
[ "${1:-}" = "--no-build" ] && BUILD=0

if [ "$BUILD" = 1 ]; then
    echo "== building the package =="
    # host_release, not host_debug: what ships is what is gated. See the
    # project guide's note on the two engine out-directories.
    STARLING_ENGINE_OUT="$REPO/engine/src/out/host_release" \
        "$REPO/build/build-all.sh" >/dev/null || exit 1
    OUT="${STARLING_PKG_OUT:-$HOME/tmp/pkg}"
    mkdir -p "$OUT"
    "$REPO/build/package-desktop.sh" "$OUT" >/dev/null || exit 1
    DEB=$(ls -t "$OUT"/starling_*.deb | head -1)
    echo "   $DEB"
    # Under its own name: "starling-gate.deb" was a harness wart that
    # ended up on camera in the walkthrough, and made a perfectly
    # ordinary Debian package look like something special.
    scp -q "$DEB" "$HOST:C:/dist/$(basename "$DEB")" || exit 1
fi

scp -q "$REPO/test/wsl/gate.sh" "$HOST:C:/dist/wsl-gate.sh" || exit 1
# Run the file directly — ONE level of quoting. Nested quoting through
# `wsl -u root -- bash -lc "…"` is a documented way to lose an afternoon, and
# it is only needed to strip CRs; the file goes over from Linux with Unix
# endings already, so there is nothing to strip.
set -o pipefail
ssh "$HOST" "wsl -d $DISTRO -u root -- bash /mnt/c/dist/wsl-gate.sh" 2>&1 \
  | tr -d '\0' | grep -v "post-quantum\|store now\|openssh.com"

