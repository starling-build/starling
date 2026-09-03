#!/usr/bin/env bash
# Build the QEMU the desktop's guest windows run on.
#
# Starling carries its own QEMU rather than waiting on upstream, and this is
# what produces it. It is a SIDE-BY-SIDE emulator under /usr/lib/starling/qemu,
# not a replacement for the distro's: the domain's <emulator> points at it, and
# every other VM on the machine keeps using Ubuntu's package. That is the whole
# reason this is safe — a Starling-configured QEMU is built for one job (the
# dbus display path) and would be a downgrade as a general-purpose one.
#
# It starts from UBUNTU's source, not upstream's tarball, so the distro's own
# patch stack is underneath ours.
#
#   build/qemu/build-qemu.sh            # build and install to the prefix
#   build/qemu/build-qemu.sh --check    # just say whether it is already there
#
# See build/qemu/README.md for what the two patches are and why.
set -euo pipefail

PREFIX="${STARLING_QEMU_PREFIX:-/usr/lib/starling/qemu}"
BIN="$PREFIX/bin/qemu-system-x86_64"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${STARLING_QEMU_WORK:-/var/tmp/starling-qemu}"

if [ "${1:-}" = "--check" ]; then
    if [ -x "$BIN" ]; then
        echo "$BIN"
        "$BIN" --version | head -1
        exit 0
    fi
    echo "no Starling QEMU at $BIN" >&2
    exit 1
fi

command -v apt-get >/dev/null || { echo "not a Debian/Ubuntu host" >&2; exit 1; }

echo "==> build deps"
sudo apt-get build-dep -y qemu

mkdir -p "$WORK"
cd "$WORK"

# One source tree per run, so a failed build never leaves a half-patched one
# to be rebuilt on top of.
rm -rf qemu-*/
echo "==> ubuntu source"
apt-get source qemu
SRC=$(find . -maxdepth 1 -type d -name 'qemu-*' | head -1)
[ -n "$SRC" ] || { echo "apt-get source produced no tree" >&2; exit 1; }
cd "$SRC"

echo "==> patches"
for p in "$HERE"/patches/*.patch; do
    echo "    $(basename "$p")"
    # -p1 with a fuzz allowance: these are small hunks in files the distro
    # also patches, and an exact-offset requirement would fail on a point
    # release for no reason. A REJECT is still fatal.
    patch -p1 --fuzz=3 --no-backup-if-mismatch < "$p"
done

# Only what the desktop needs. Everything omitted here is a thing the distro's
# QEMU still does for every other VM on the machine.
echo "==> configure"
./configure \
    --prefix="$PREFIX" \
    --target-list=x86_64-softmmu \
    --enable-kvm \
    --enable-opengl \
    --enable-gio \
    --disable-docs \
    --disable-strip \
    --disable-relocatable \
    --disable-download \
    --disable-sdl \
    --disable-gtk \
    --disable-vnc \
    --disable-spice \
    --disable-guest-agent \
    --disable-tools \
    --disable-install-blobs \
    --firmwarepath=/usr/share/qemu:/usr/share/seabios
    # The last two are what make a side-by-side build work at all, and both
    # are lifted from Ubuntu's own debian/rules. Ubuntu repacks the source
    # WITHOUT the prebuilt firmware blobs (that is what "+ds" means), so a
    # build that tries to install them dies on a missing .bin; and with none
    # installed, the emulator has to be pointed at the distro's copies or it
    # cannot find a VGA BIOS for a machine it is otherwise perfectly able to
    # run.

echo "==> build"
make -j"$(nproc)"

echo "==> install to $PREFIX"
sudo make install

# AppArmor, without which the binary is unusable no matter how it is built:
# libvirtd's stock profile lets it exec only /usr/bin/*, so `virsh define` on
# a domain naming this one fails at probe time with "Permission denied" — for
# a binary that is 0755 under directories that are all traversable. Installed
# here rather than left to the reader because a QEMU nothing may run is not a
# build that succeeded.
echo "==> apparmor"
for f in usr.sbin.libvirtd abstractions/libvirt-qemu; do
    src="$HERE/apparmor/$(echo "$f" | tr / -)"
    dst="/etc/apparmor.d/local/$f"
    [ -f "$src" ] || continue
    sudo mkdir -p "$(dirname "$dst")"
    if [ -f "$dst" ] && grep -q "$PREFIX" "$dst"; then
        echo "    $dst already names $PREFIX"
        continue
    fi
    # Appended inside markers, never overwritten: these files are shared with
    # whatever else the machine has taught libvirt about (the Triton stack is
    # in both here), and the markers are what lets starling-qemu's postrm take
    # out exactly its own lines. Same block shape as that package writes, so a
    # dev-box install and a packaged one are interchangeable.
    { echo '# >>> starling-qemu — do not edit inside these markers'
      cat "$src"
      echo '# <<< starling-qemu'; } | sudo tee -a "$dst" >/dev/null
    echo "    appended to $dst"
done
sudo systemctl reload apparmor 2>/dev/null || sudo apparmor_parser -r /etc/apparmor.d/usr.sbin.libvirtd 2>/dev/null || true
sudo systemctl restart libvirtd 2>/dev/null || true

"$BIN" --version | head -1
echo
echo "Point a domain at it with:"
echo "    <emulator>$BIN</emulator>"
echo "and match its machine type — this build is a point release of the"
echo "distro's, so pc-q35-<its version> is what it accepts."
