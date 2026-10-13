#!/usr/bin/env bash
# Build starling-office_<ver>_<arch>.flatpak — the same tree
# build/package-office-gtk.sh puts in the .deb, as a single-file Flatpak
# bundle for every other distribution (Fedora, openSUSE, Arch, …).
#
#   build/package-office-gtk.sh [outdir]       # first: it stages the tree
#   build/package-office-flatpak.sh [outdir]   ->  <outdir>/starling-office_*.flatpak
#
# Install with `flatpak install --user starling-office_*.flatpak`; the GNOME
# runtime it names comes from Flathub. Not built by flatpak-builder: the
# binaries are the ones already built (they need glibc 2.38, the runtime has
# newer), laid out under /app by hand and exported with `flatpak build-*`.
set -euo pipefail

VER="${STARLING_OFFICE_VERSION:-0.1.0}"
ID=build.starling.Office
RUNTIME_VER="${STARLING_OFFICE_RUNTIME:-49}"
OUT="${1:-$HOME/tmp/starling-office-pkg}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
G="$REPO/build/office-gtk"
DEB_ARCH="${STARLING_DEB_ARCH:-$(dpkg --print-architecture)}"
ARCH="$(flatpak --default-arch)"
SRC="$OUT/starling-office_${VER}_${DEB_ARCH}/usr"
[ -x "$SRC/lib/starling-office/starling-office" ] || {
    echo "error: $SRC not staged — run build/package-office-gtk.sh first" >&2; exit 1; }

APP="$OUT/flatpak-app"; OSTREE="$OUT/flatpak-repo"
rm -rf "$APP" "$OSTREE"
mkdir -p "$APP"
# `flatpak build-init` writes these three lines too, but insists the SDK be
# installed, and nothing here is compiled. (No export/ yet: its presence is
# how build-finish decides a directory is already finished.)
cat > "$APP/metadata" <<META
[Application]
name=$ID
runtime=org.gnome.Platform/$ARCH/$RUNTIME_VER
sdk=org.gnome.Sdk/$ARCH/$RUNTIME_VER
META
mkdir -p "$APP/files/bin" "$APP/files/lib" "$APP/files/share/applications" \
         "$APP/files/share/icons/hicolor/scalable/apps" "$APP/files/share/metainfo" \
         "$APP/files/share/doc"

cp -r "$SRC/lib/starling-office" "$APP/files/lib/"
cp -r "$SRC/share/doc/starling-office" "$APP/files/share/doc/"
install -m755 "$G/starling-office" "$APP/files/bin/starling-office"

# The engine library links libinput (its other embedder reads input devices
# itself; a window never calls it) and the GNOME runtime has none. A .deb
# depends on the system's; here it rides along with the two libraries of
# its own the runtime also lacks — all MIT, all content with glibc 2.38.
# /app/lib is on a Flatpak's library path already.
SYSLIB="/usr/lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
for so in libinput.so.10 libmtdev.so.1 libwacom.so.9; do
    install -m644 "$(readlink -f "$SYSLIB/$so")" "$APP/files/lib/$so"
    pkg=$(dpkg -S "$(readlink -f "$SYSLIB/$so")" | cut -d: -f1)
    cp "/usr/share/doc/$pkg/copyright" "$APP/files/share/doc/starling-office/copyright.$pkg"
done

# Everything a Flatpak exports carries the app's id: the three menu entries
# and their icons are renamed, Writer taking the bare id.
for app in writer sheets slides; do
    case $app in writer) name=$ID ;; sheets) name=$ID.Sheets ;; slides) name=$ID.Slides ;; esac
    sed -e "s/^Icon=.*/Icon=$name/" "$G/starling-$app.desktop" \
        > "$APP/files/share/applications/$name.desktop"
    install -m644 "$G/starling-$app.svg" "$APP/files/share/icons/hicolor/scalable/apps/$name.svg"
done
sed -e "s/@VER@/$VER/" -e "s/@DATE@/$(date +%Y-%m-%d)/" "$G/$ID.metainfo.xml" \
    > "$APP/files/share/metainfo/$ID.metainfo.xml"

# The window, the GPU, and the user's files: the app opens and saves
# documents by path, so it sees the home directory rather than a portal's
# one-file grants.
flatpak build-finish "$APP" --command=starling-office \
    --env=STARLING_OFFICE_HOME=/app/lib/starling-office \
    --socket=wayland --socket=fallback-x11 --share=ipc --device=dri \
    --filesystem=home
flatpak build-export "$OSTREE" "$APP" stable >/dev/null
BUNDLE="$OUT/starling-office_${VER}_${ARCH}.flatpak"
flatpak build-bundle "$OSTREE" "$BUNDLE" "$ID" stable \
    --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo
ls -lh "$BUNDLE"
