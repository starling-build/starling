#!/usr/bin/env bash
# Build starling-terminal_<ver>_<arch>.deb — the STANDALONE terminal for
# ordinary Linux desktops (GNOME/KDE, Wayland or X11): the GTK build of
# TerminalApp with everything it loads bundled under /usr/lib/starling-terminal.
# Independent of the desktop package; installs beside it cleanly.
#
# The payload is exactly what a live run maps (checked via /proc/<pid>/maps):
# the binary, libFlutterShared + the two engine libs, the Swift runtime
# closure, the SwiftPM font resource bundles, and data/icudtl.dat. No
# flutter_assets: the Swift runtime never reads them, and the GTK run proves
# it. The Noto CJK / Color Emoji fallbacks are system fonts looked up by
# absolute path — Recommends, not payload.
#
# Prereqs:
#   ninja -C engine/src/out/host_release libflutter_engine.so libflutter_linux_gtk.so
#   STARLING_APP_GTK=1 STARLING_ENGINE_OUT=$PWD/engine/src/out/host_release \
#       swift build -c release --package-path apps/TerminalApp \
#       --scratch-path $PWD/.build-gtk
#
#   build/package-terminal-gtk.sh [outdir]  ->  <outdir>/starling-terminal_*.deb
#
# Or from a released SDK bundle, with no engine checkout and no sdk/ in play —
# what a consumer has, and what a release should be built from:
#
#   tar xzf dist/starling-sdk-linux-x86_64.tar.gz -C /tmp/sdk
#   B=/tmp/sdk/starling-sdk-linux-x86_64
#   env -u STARLING_ENGINE_OUT STARLING_APP_GTK=1 STARLING_SDK_BUNDLE=$B \
#       swift build -c release --package-path apps/TerminalApp \
#       --scratch-path $PWD/.build-gtk
#   STARLING_SDK_BUNDLE=$B build/package-terminal-gtk.sh
set -euo pipefail

VER=0.1.0
PKG=starling-terminal
OUT="${1:-/tmp/starling-terminal-pkg}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

# A released SDK bundle to package from instead of this repo's sdk/ and an
# engine checkout — the consumer path, keyed on the same variable the app's
# manifest reads, so the binary and the payload cannot come from different
# places. Unset (every dev build) nothing below changes.
#
# A bundle splits what an engine out directory keeps flat: libraries in
# engine/lib, run-time data in engine/share. Detect the split rather than
# assuming it, because STARLING_ENGINE_OUT still overrides the engine — the
# manifest gives it the same precedence at link time, and a package whose
# libraries disagreed with the binary's would be worse than either.
BUNDLE="${STARLING_SDK_BUNDLE:-}"
if [ -n "$BUNDLE" ]; then
    [ -d "$BUNDLE/engine/lib" ] || {
        echo "error: STARLING_SDK_BUNDLE=$BUNDLE has no engine/lib —" >&2
        echo "       point it at an UNPACKED bundle, not the tarball" >&2; exit 1; }
    E="${STARLING_ENGINE_OUT:-$BUNDLE/engine/lib}"
    SDK_LICENSE="$BUNDLE/LICENSE"
    # The engine's third-party notices must describe the engine being shipped,
    # so they travel with it: a bundle carries them inside its own
    # flutter_assets, and reaching into $REPO/build for them would ship this
    # tree's copy against someone else's engine.
    ENGINE_NOTICES="$BUNDLE/engine/share/flutter_assets/NOTICES.Z"
    FRAMEWORK_SOURCES="$BUNDLE/Sources"
else
    E="${STARLING_ENGINE_OUT:-$REPO/engine/src/out/host_release}"
    SDK_LICENSE="$REPO/sdk/LICENSE"
    ENGINE_NOTICES="$REPO/build/flutter_assets/NOTICES.Z"
    FRAMEWORK_SOURCES="$REPO/sdk/Sources"
fi
# Wherever the engine came from, icudtl.dat sits beside it in an out directory
# and under engine/share in a bundle.
if [ -f "$E/icudtl.dat" ]; then ICU="$E/icudtl.dat"
else ICU="$BUNDLE/engine/share/icudtl.dat"; fi
[ -f "$ICU" ] || { echo "error: no icudtl.dat for $E" >&2; exit 1; }

B="${STARLING_TERMINAL_SCRATCH:-$REPO/.build-gtk}"
# <scratch>/release is SwiftPM's symlink into <scratch>/<triple>/release —
# resolving it finds the triple without naming one.
REL="$(readlink -f "$B/release")"
BIN="$REL/TerminalApp"

[ -x "$BIN" ] || {
    echo "error: $BIN not built — run the swift build in the header" >&2; exit 1; }
# A binary built without STARLING_APP_GTK=1 is the DRM/shell one: it links no
# GTK embedder and exits immediately outside the shell. Refuse it. (grep
# without -q: -q quits at the first match, readelf dies of SIGPIPE, and
# pipefail reads that as "no match".)
readelf -d "$BIN" | grep flutter_linux_gtk >/dev/null || {
    echo "error: $BIN is not a GTK build (no libflutter_linux_gtk in its" >&2
    echo "       link set) — rebuild with STARLING_APP_GTK=1" >&2; exit 1; }
# The classic stale-scratch trap, refused rather than shipped: any Terminal
# source newer than the binary means the build above was skipped.
STALE=$(find "$FRAMEWORK_SOURCES" "$REPO/apps/TerminalApp/Sources" \
        -name '*.swift' -newer "$BIN" 2>/dev/null | head -1)
[ -z "$STALE" ] || {
    echo "error: $STALE is newer than $BIN — rebuild before packaging" >&2; exit 1; }

DEB_ARCH="${STARLING_DEB_ARCH:-$(dpkg --print-architecture)}"
ROOT="$OUT/${PKG}_${VER}_${DEB_ARCH}"
LIB=$ROOT/usr/lib/$PKG
rm -rf "$ROOT"
mkdir -p "$LIB/data" "$ROOT/usr/bin" "$ROOT/usr/share/applications" \
         "$ROOT/usr/share/doc/$PKG" "$ROOT/DEBIAN"

# --- payload -----------------------------------------------------------------
install -m755 "$BIN" "$LIB/starling-terminal"
install -m644 "$REL/libFlutterShared.so" "$LIB/"
install -m644 "$E/libflutter_engine.so" "$E/libflutter_linux_gtk.so" "$LIB/"
install -m644 "$ICU" "$LIB/data/"
for r in "$REL"/*.resources; do
    [ -d "$r" ] && cp -r "$r" "$LIB/"
done
# Swift runtime: the ldd closure, limited to what the swiftly toolchain
# provides (absent on target machines) — same recipe as build/stage.sh.
ldd "$BIN" 2>/dev/null | awk '$3 ~ /swiftly\/toolchains/ {print $3}' | sort -u |
while read -r so; do
    install -m644 "$so" "$LIB/"
done

install -Dm755 "$REPO/build/terminal-gtk/starling-terminal" \
               "$ROOT/usr/bin/starling-terminal"
install -Dm644 "$REPO/build/terminal-gtk/starling-terminal.desktop" \
               "$ROOT/usr/share/applications/starling-terminal.desktop"

# The icon: extracted from the SAME .icns the macOS app ships, so the two
# platforms cannot drift. gen-icon.swift (macOS) is the true source.
python3 "$REPO/build/terminal-gtk/icns-to-hicolor.py" \
    "$REPO/build/macos/Terminal.icns" \
    "$ROOT/usr/share/icons/hicolor" starling-terminal

# --- licensing ---------------------------------------------------------------
DOC=$ROOT/usr/share/doc/$PKG
cp "$REPO/LICENSE"     "$DOC/LICENSE.Apache-2.0"
cp "$SDK_LICENSE"      "$DOC/LICENSE.BSD-3-Clause.flutter"
# The engine's own third-party notices, generated by its build — shipped here
# because this package bundles the engine libraries without flutter_assets.
install -m644 "$ENGINE_NOTICES" "$DOC/ENGINE-NOTICES.Z"
{
    cat "$REPO/NOTICE"
    cat <<EOF

================================================================================
Full licence texts
================================================================================

Apache-2.0    /usr/share/doc/$PKG/LICENSE.Apache-2.0
BSD-3-Clause  /usr/share/doc/$PKG/LICENSE.BSD-3-Clause.flutter

The Flutter engine's complete third-party notices, generated by its own build:

    /usr/share/doc/$PKG/ENGINE-NOTICES.Z   (gzip; zcat to read)
EOF
} > "$DOC/copyright"

# --- control -----------------------------------------------------------------
# Depends computed from the bundled ELF objects; -l resolves the private libs
# (Swift runtime, engine, FlutterShared) without generating deps on them.
SCAN="usr/lib/$PKG/starling-terminal"
for so in "$LIB"/*.so; do SCAN="$SCAN usr/lib/$PKG/$(basename "$so")"; done
SHLIBDEPS_ERR=$OUT/shlibdeps.err
DEPS=$(
    cd "$ROOT" && mkdir -p debian && : > debian/control &&
    dpkg-shlibdeps -O -l"$LIB" $SCAN 2>"$SHLIBDEPS_ERR" | sed 's/^shlibs:Depends=//'
    rm -rf "$ROOT/debian"
)
[ -n "$DEPS" ] || {
    echo "ERROR: dpkg-shlibdeps produced no Depends. Install dpkg-dev." >&2
    cat "$SHLIBDEPS_ERR" >&2
    exit 1
}
echo "Depends (dpkg-shlibdeps): $DEPS"

cat > "$ROOT/DEBIAN/control" <<CONTROL
Package: $PKG
Version: $VER
Section: x11
Priority: optional
Architecture: $DEB_ARCH
Maintainer: Starling <dev@starling.build>
Depends: $DEPS
Recommends: fonts-noto-cjk, fonts-noto-color-emoji
Description: Starling Terminal
 The Starling desktop's terminal as a standalone app for any Linux
 desktop: an ordinary window on GNOME, KDE and other environments,
 Wayland or X11.
 .
 GPU-rendered with a C emulator core; scrollback search, blinking
 block cursor, macOS-style look.
CONTROL

dpkg-deb --build --root-owner-group "$ROOT"
ls -lh "$OUT"/${PKG}_${VER}_${DEB_ARCH}.deb
