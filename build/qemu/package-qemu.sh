#!/usr/bin/env bash
# Package the Starling QEMU as its own .deb.
#
# Separate from the desktop package on purpose. The desktop RUNS on the
# distro's QEMU — every M1 milestone was reached on it — and only two things
# go wrong without ours: rebooting a guest kills the VM, and copying inside a
# guest never reaches the desktop. So this is a `Suggests`, not a hard
# dependency, and someone who never opens a Windows window never downloads
# 25 MB of emulator. The shell says which emulator a domain is using, so the
# choice is visible rather than silent.
#
#   build/qemu/build-qemu.sh          # produces the prefix
#   build/qemu/package-qemu.sh        # turns it into a .deb
#
set -euo pipefail

VER="${STARLING_QEMU_VER:-0.4.0}"
PREFIX="${STARLING_QEMU_PREFIX:-/usr/lib/starling/qemu}"
PKG=starling-qemu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Outside the repo, like build/package-desktop.sh — a .deb is not content.
OUT="${STARLING_QEMU_OUT:-/tmp/starling-pkg}"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

[ -x "$PREFIX/bin/qemu-system-x86_64" ] || {
    echo "no build at $PREFIX — run build/qemu/build-qemu.sh first" >&2
    exit 1
}
DEB_ARCH=$(dpkg --print-architecture)

echo "==> staging $PREFIX"
mkdir -p "$ROOT$PREFIX" "$ROOT/DEBIAN" "$OUT"
cp -a "$PREFIX/." "$ROOT$PREFIX/"
# The build follows Ubuntu's --disable-strip (they strip into -dbgsym
# packages downstream); we have no dbgsym package, so strip here. 84 MB -> ~25.
strip --strip-unneeded "$ROOT$PREFIX/bin/qemu-system-x86_64" 2>/dev/null || true
# Headers are a build artefact of the prefix, not something a user needs.
rm -rf "$ROOT$PREFIX/include"

# The AppArmor rules ship as data and are APPENDED by the maintainer scripts,
# never installed as files. /etc/apparmor.d/local/* is owned by no package but
# is shared — the Triton stack keeps its rules in the same two files — so a
# .deb that owned them would silently drop somebody else's lines on upgrade.
mkdir -p "$ROOT$PREFIX/share/starling"
cp "$HERE/apparmor/usr.sbin.libvirtd" \
   "$ROOT$PREFIX/share/starling/apparmor-libvirtd.rules"
cp "$HERE/apparmor/abstractions-libvirt-qemu" \
   "$ROOT$PREFIX/share/starling/apparmor-libvirt-qemu.rules"

INSTALLED=$(du -sk "$ROOT" | cut -f1)

cat > "$ROOT/DEBIAN/control" <<CONTROL
Package: $PKG
Version: $VER
Section: otherosfs
Priority: optional
Architecture: $DEB_ARCH
Maintainer: Starling <dev@starling.build>
Depends: libvirt-daemon-system, apparmor
Installed-Size: $INSTALLED
Description: QEMU build for Starling's guest windows
 A QEMU built from Ubuntu's source with two fixes the desktop needs to run a
 Windows guest in a desktop window, installed side by side at
 $PREFIX. The distro's QEMU is untouched and keeps serving
 every other VM on the machine; a domain opts in by naming this binary as its
 <emulator>.
 .
 Without it a guest still runs, but rebooting one kills the whole VM, and
 copying inside a guest never reaches the desktop clipboard.
 .
 A domain must name the emulator explicitly, so installing this package
 changes nothing on its own.
CONTROL

# ── maintainer scripts ──────────────────────────────────────────────────────
# Marked blocks, so removal takes out exactly what was added and nothing a
# person or another package put in the same file.
cat > "$ROOT/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
PREFIX=/usr/lib/starling/qemu
add_block() {   # add_block <rules-file> <target>
    rules="$1"; target="$2"
    [ -f "$rules" ] || return 0
    mkdir -p "$(dirname "$target")"
    touch "$target"
    grep -q '^# >>> starling-qemu' "$target" && return 0
    {
        echo '# >>> starling-qemu — do not edit inside these markers'
        cat "$rules"
        echo '# <<< starling-qemu'
    } >> "$target"
}
if [ "$1" = configure ]; then
    add_block "$PREFIX/share/starling/apparmor-libvirtd.rules" \
              /etc/apparmor.d/local/usr.sbin.libvirtd
    add_block "$PREFIX/share/starling/apparmor-libvirt-qemu.rules" \
              /etc/apparmor.d/local/abstractions/libvirt-qemu
    # Without these, libvirtd cannot exec the binary and `virsh define` on a
    # domain naming it fails at probe with "Permission denied" — for a 0755
    # file. Reloading is what makes the package usable at all.
    apparmor_parser -r -T -W /etc/apparmor.d/usr.sbin.libvirtd 2>/dev/null || true
    systemctl reload apparmor 2>/dev/null || true
    systemctl try-restart libvirtd 2>/dev/null || true
fi
exit 0
POSTINST

cat > "$ROOT/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
set -e
del_block() {
    target="$1"
    [ -f "$target" ] || return 0
    sed -i '/^# >>> starling-qemu/,/^# <<< starling-qemu/d' "$target"
}
if [ "$1" = remove ] || [ "$1" = purge ]; then
    del_block /etc/apparmor.d/local/usr.sbin.libvirtd
    del_block /etc/apparmor.d/local/abstractions/libvirt-qemu
    systemctl reload apparmor 2>/dev/null || true
    systemctl try-restart libvirtd 2>/dev/null || true
fi
exit 0
POSTRM

chmod 755 "$ROOT/DEBIAN/postinst" "$ROOT/DEBIAN/postrm"

dpkg-deb --build --root-owner-group "$ROOT" \
    "$OUT/${PKG}_${VER}_${DEB_ARCH}.deb" >/dev/null
ls -lh "$OUT/${PKG}_${VER}_${DEB_ARCH}.deb"
