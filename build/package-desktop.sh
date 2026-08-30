#!/usr/bin/env bash
# Build starling-desktop_<ver>_<arch>.deb — the v0 Ubuntu package: shell,
# engine, Swift runtime, first-party apps, assets, and the GDM session
# entry. Everything lands under /usr/lib/starling + /usr/share/starling;
# the binaries' $ORIGIN RUNPATH plus the launcher's LD_LIBRARY_PATH make
# the tree self-contained (no swiftly toolchain, no dev paths on target).
#
# Prereqs: build/build-all.sh (sdk + shell + apps, one scratch tree), engine
# host_release built (ninja libflutter_linux_drm.so libflutter_engine.so).
#
# The payload comes from build/stage.sh — that script defines the layout, and
# build/run-desktop.sh runs from the same staged tree, so what you test in dev
# is what the package installs.
#
#   tools/package-desktop.sh [outdir]   ->  <outdir>/starling-desktop_*.deb
set -euo pipefail

VER=0.4.0
# The binary package name, and therefore the .deb filename, the doc dir
# (Debian policy: /usr/share/doc/<pkg>/copyright) and what `apt`/`dpkg -s`
# call it. Stated once; everything below derives from it.
PKG=starling
OUT="${1:-/tmp/starling-pkg}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
E=$REPO/engine/src/out/host_release
# The one build tree build/build-all.sh produces — sdk, shell and every app,
# with a single libFlutterShared.so. Same variable stage.sh uses.
SHELL_BUILD="${STARLING_SCRATCH:-$REPO/.build-shared}"
# The system-integration payload: the session launcher GDM execs, its
# wayland-session entry, the polkit policy behind the App Store's Install
# button, and the NetworkManager drop-in. Real files rather than heredocs so
# a packager for another distribution installs the same bytes we do instead
# of transcribing them — see build/session/README.md.
SESSION=$REPO/build/session

# The apps to ship, read out of the registry — NOT a list maintained here.
#
# This was a hardcoded five, and it had silently drifted from the catalog by
# two: Text Editor and Image Viewer were declared in registry/catalog.d, built
# by every tier, staged into .stage, and then simply left out of the .deb.
# Text Editor carries Dock=4, so an installed desktop showed a dock icon whose
# binary was not on disk — which is what
# https://github.com/starling-build/starling/issues/4 ("Add native Text Editor
# app") is: from a user's seat there was no text editor, because the one we
# wrote never shipped. It is the exact failure CLAUDE.md describes — an app id
# living in a table apart from the registry, and the two disagreeing in silence.
#
# `Kind=first-party` is the discriminator: for those records `Exec=` IS the
# executable name (AppRecord.swift:30), while third-party records name an
# app-run recipe and ship no binary of ours. So adding a first-party app is
# still one file, the way "Apps are data, not code" promises, and apps/ entries
# with no record (DSATool, FlutterDemoApp — dev and demo tools)
# stay out on purpose.
first_party_execs() {
    local f kind exec
    for f in "$REPO"/registry/catalog.d/*.app; do
        [ -f "$f" ] || continue
        kind=$(sed -n 's/^Kind=//p'  "$f" | head -1)
        exec=$(sed -n 's/^Exec=//p'  "$f" | head -1)
        [ "$kind" = first-party ] && [ -n "$exec" ] && printf '%s\n' "$exec"
    done | sort -u
}

# An app that vendors a prebuilt library for another architecture cannot link,
# and nothing here can make it — apps/ImageViewerApp ships an x86-64
# libpdfium.so, so it does not build on arm64. Same rule test/run.sh applies:
# skipped by architecture rather than by name, so there is no second list to
# drift, and announced rather than dropped in silence. The host's ELF machine
# word is read off /bin/true instead of mapping uname -m to an ELF name.
elf_machine() { readelf -h "$1" 2>/dev/null | sed -n 's/^ *Machine: *//p'; }
HOST_MACHINE="$(elf_machine /bin/true)"
vendored_arch_mismatch() {
    local lib m
    for lib in "$1"/.deps/*/lib/*.so; do
        [ -f "$lib" ] || continue
        m="$(elf_machine "$lib")"
        [ -n "$m" ] && [ -n "$HOST_MACHINE" ] && [ "$m" != "$HOST_MACHINE" ] && {
            printf '%s (%s, host is %s)\n' "$(basename "$lib")" "$m" "$HOST_MACHINE"
            return 0
        }
    done
    return 1
}

APPS=""
for a in $(first_party_execs); do
    if [ -x "$SHELL_BUILD/release/$a" ]; then
        APPS="$APPS $a"
    elif mismatch=$(vendored_arch_mismatch "$REPO/apps/$a"); then
        echo "warning: $a is NOT in this .deb — vendored $mismatch" >&2
    else
        # Hard error, not a warning. The registry says this app exists, so the
        # installed desktop will show it in the launcher and possibly the dock;
        # shipping without the binary is the bug this whole block replaces.
        echo "error: $a is in registry/catalog.d but has no built binary at" >&2
        echo "       $SHELL_BUILD/release/$a — run build/build-all.sh, or" >&2
        echo "       drop its record" >&2
        exit 1
    fi
done
APPS="$(echo "$APPS" | xargs)"

# The Debian architecture of the machine we are building on. Hardcoding amd64
# here did not fail on arm64 — it produced starling_<ver>_amd64.deb containing
# arm64 binaries, which is worse than an error: dpkg would refuse it on a real
# amd64 machine and the mislabelling only shows up there. Override with
# STARLING_DEB_ARCH when cross-building.
DEB_ARCH="${STARLING_DEB_ARCH:-$(dpkg --print-architecture)}"

ROOT="$OUT/${PKG}_${VER}_${DEB_ARCH}"
LIB=$ROOT/usr/lib/starling
SHARE=$ROOT/usr/share/starling
rm -rf "$ROOT"
mkdir -p "$ROOT/usr/lib" "$ROOT/usr/share" "$ROOT/usr/bin" "$ROOT/usr/libexec" \
         "$ROOT/usr/share/wayland-sessions" "$ROOT/DEBIAN"
# Where app-install records what it installed, and what the shell watches for
# changes. Shipped empty rather than created on first install: the shell sets
# its watch at startup and runs as the session user, so it cannot create a
# directory under /var/lib itself.
mkdir -p "$ROOT/var/lib/starling/installed.d"

# --- payload: assembled by stage.sh, the single definition of the layout ------
# The staged tree IS the installed tree; here it is just relocated under the
# packaging root and given control metadata.
"$REPO/build/stage.sh" "$OUT/stage" --apps "$APPS"
cp -r "$OUT/stage/lib"   "$LIB"
cp -r "$OUT/stage/share" "$SHARE"
cp -a "$OUT/stage/bin/." "$ROOT/usr/bin/"
# The version, stamped where Settings reads it. Only the package writes this
# — a dev tree has no stamp and Settings says "dev build", which is the
# truth. Settings used to carry its own copy of this string, and it shipped
# reading 0.2.1 on a 0.2.2 install.
printf '%s\n' "$VER" > "$SHARE/VERSION"

# --- licensing -----------------------------------------------------------------
# Debian policy requires /usr/share/doc/<pkg>/copyright, and it is also how the
# redistribution terms of what we bundle are satisfied: the Swift runtime and
# Roboto Mono are Apache-2.0 (§4 wants the licence text and NOTICE alongside the
# binaries), the engine and sdk/ are BSD-3, the wayland protocol bindings MIT.
# NOTICE is the authored index; the engine's own exhaustive third-party notices
# already ship as share/starling/flutter_assets/NOTICES.Z and are referenced
# from it rather than duplicated.
DOC=$ROOT/usr/share/doc/$PKG
mkdir -p "$DOC"
cp "$REPO/LICENSE"    "$DOC/LICENSE.Apache-2.0"
cp "$REPO/sdk/LICENSE" "$DOC/LICENSE.BSD-3-Clause.flutter"
# The font licences travel as files because they have to: MIT and the SIL Open
# Font License both require their text to accompany what they cover, and a
# .ttf cannot carry a notice inside it the way a source file can.
cp "$REPO"/licenses/LICENSE.* "$DOC/"
{
    cat "$REPO/NOTICE"
    cat <<EOF

================================================================================
Full licence texts
================================================================================

Apache-2.0    /usr/share/doc/$PKG/LICENSE.Apache-2.0
BSD-3-Clause  /usr/share/doc/$PKG/LICENSE.BSD-3-Clause.flutter
              (also /usr/share/common-licenses/Apache-2.0 and .../BSD)
MIT           /usr/share/doc/$PKG/LICENSE.MIT.fluentui-system-icons
OFL-1.1       /usr/share/doc/$PKG/LICENSE.OFL-1.1.Selawik
Bitstream     /usr/share/doc/$PKG/LICENSE.Bitstream-Vera.DejaVu

The Flutter engine's complete third-party notices, generated by its own build:

    /usr/share/starling/flutter_assets/NOTICES.Z   (gzip; zcat to read)
EOF
} > "$DOC/copyright"

# polkit: let the active session's user run app-install through pkexec
# without a prompt — the App Store's Install button drives this.
install -Dm644 "$SESSION/org.starling.app-install.policy" \
               "$ROOT/usr/share/polkit-1/actions/org.starling.app-install.policy"

# NetworkManager: manage wired devices too.
#
# Ubuntu's server/cloud base ships
# /usr/lib/NetworkManager/conf.d/10-globally-managed-devices.conf saying
# `unmanaged-devices=*,except:type:wifi,…` — NM owns the radio and netplan
# owns the wire. A desktop needs NM to own both, or its network UI shows no
# ethernet at all on a machine with a cable in it, which reads as a bug in the
# desktop rather than a policy of the base system. ubuntu-desktop solves this
# by overwriting that same file; we ship a higher-numbered one instead so the
# two packages do not fight over a path.
#
# Precedence keeps the user in charge: NM reads /usr/lib before /etc, so
# anything in /etc/NetworkManager/conf.d still wins over this.
install -Dm644 "$SESSION/90-starling-managed-devices.conf" \
               "$ROOT/usr/lib/NetworkManager/conf.d/90-starling-managed-devices.conf"

# --- session launcher --------------------------------------------------------
install -Dm755 "$SESSION/starling-session" \
               "$ROOT/usr/libexec/starling-session"
# On a normal machine the display manager execs the libexec path and nobody
# types it. In WSL there IS no display manager: the user runs the session
# themselves, so it needs to be on PATH under a name worth typing.
ln -sf ../libexec/starling-session "$ROOT/usr/bin/starling-session"

install -Dm644 "$SESSION/starling.desktop" \
               "$ROOT/usr/share/wayland-sessions/starling.desktop"

# --- control ------------------------------------------------------------------
# Depends computed from the staged ELF objects. -l points dpkg-shlibdeps at
# the bundled private libs (Swift runtime, engine, FlutterShared) so they
# resolve without generating package deps.
#
# What the scanner cannot see, appended by hand. Only usr/lib/starling holds
# ELF objects; usr/bin and usr/libexec are scripts, so everything they exec
# is invisible to shlibdeps and has to be declared here:
#   libseat1     dlopen'd by the embedder for device access
#   dbus         starling-session execs dbus-daemon (dbus -> dbus-daemon)
#   pkexec       AppStoreApp execs pkexec app-install, which is what the
#                shipped polkit policy authorises (pkexec -> polkitd)
# Anything added to usr/bin or usr/libexec that shells out to a new command
# needs its package listed here too — nothing else will catch it.
#
# Deliberately NOT declared: bubblewrap. app-run execs /usr/bin/bwrap, but
# that is the opt-in third-party compat runtime, which also needs a
# debootstrap'd /var/lib/starling-apps/runtime this package does not ship.
# Third-party apps are expected to use their native Ubuntu packaging, so the
# shipped desktop — shell, dock, and the first-party apps the shell spawns
# directly — never reaches bwrap. Do not add it as a hard dependency.
#
# Everything else the runtime needs arrives transitively and does not belong
# here: keymaps via libxkbcommon0 -> xkb-data, and the GL driver via
# libegl1 -> libegl-mesa0 -> mesa-libgallium. Fonts are bundled in the
# package (Skia is built with fontconfig off), so no system font dep.
#
# The fallback is a last resort, only for a host where dpkg-shlibdeps cannot
# run. It must stay in sync with what the scanner actually emits — a stale
# list ships a .deb that under-declares and then fails on a lean system.
FALLBACK_DEPS="libc6, libgcc-s1, libstdc++6, libinput10, libgbm1, libegl1, libgles2, libxkbcommon0, libwayland-server0, libxshmfence1, libdrm2, libsystemd0, libudev1, libva2, libva-drm2, libpipewire-0.3-0t64"
SCAN="usr/lib/starling/DesktopShellApp"
for a in $APPS; do SCAN="$SCAN usr/lib/starling/apps/$a"; done
for so in "$LIB"/*.so; do SCAN="$SCAN usr/lib/starling/$(basename "$so")"; done
SHLIBDEPS_ERR=$OUT/shlibdeps.err
DEPS=$(
    cd "$ROOT" && mkdir -p debian && : > debian/control &&
    dpkg-shlibdeps -O -l"$LIB" $SCAN 2>"$SHLIBDEPS_ERR" | sed 's/^shlibs:Depends=//'
    rm -rf "$ROOT/debian"
)
if [ -n "$DEPS" ]; then
    echo "Depends (dpkg-shlibdeps): $DEPS"
elif [ "${STARLING_ALLOW_FALLBACK_DEPS:-0}" = 1 ]; then
    echo "WARNING: dpkg-shlibdeps produced nothing — using static fallback list"
    echo "         (STARLING_ALLOW_FALLBACK_DEPS=1; deps may be incomplete)"
    DEPS=$FALLBACK_DEPS
else
    echo "ERROR: dpkg-shlibdeps produced no Depends. Refusing to ship a .deb"
    echo "       with a guessed dependency list. Install dpkg-dev, or set"
    echo "       STARLING_ALLOW_FALLBACK_DEPS=1 to use FALLBACK_DEPS anyway."
    echo "--- dpkg-shlibdeps stderr ---"
    cat "$SHLIBDEPS_ERR" >&2
    exit 1
fi

cat > "$ROOT/DEBIAN/control" <<CONTROL
Package: $PKG
Version: $VER
Section: x11
Priority: optional
Architecture: $DEB_ARCH
Maintainer: Starling <dev@starling.build>
Depends: $DEPS, libseat1, dbus, pkexec
Recommends: gdm3 | lightdm | sddm, xwayland, x11-utils, xdg-utils, network-manager, ffmpeg, pipewire-pulse, pulseaudio-utils
Conflicts: starling-desktop
Replaces: starling-desktop
Provides: starling-desktop
Description: Starling desktop environment
 A new Linux desktop environment: a Flutter/Swift shell, its own
 compositor, and first-party apps. Select the "Starling" session at
 the login screen.
 .
 Brings its own Wayland compositor and its own X11 server, so it runs
 native Wayland clients and X11 apps alike.
 .
 Needs a Wayland-capable login manager to reach the session menu; the
 gdm3 | lightdm | sddm recommend pulls one in when none is installed
 (satisfied automatically on Ubuntu Desktop).
CONTROL

dpkg-deb --build --root-owner-group "$ROOT"
ls -lh "$OUT"/${PKG}_${VER}_${DEB_ARCH}.deb
