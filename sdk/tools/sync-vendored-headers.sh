#!/usr/bin/env bash
# Vendor the headers this package needs from outside itself.
#
#   tools/sync-vendored-headers.sh [--check] [engine-root]
#
# Two sources: the engine's public headers, and one header from the Swift
# toolchain (see TOOLCHAIN below).
#
# The framework reaches the engine through three header sets, and all three are
# closed: nothing in them includes anything outside its own directory (the C++
# bridge headers cross-reference by bare filename; embedder.h and fl_drm_view.h
# include only libc). So they can live here, and the package then *compiles* with
# no engine checkout at all — the engine becomes a link-time dependency only.
#
# Deliberately not vendored: swift_runtime_controller.h. It pulls
# flutter/runtime/runtime_controller_interface.h, and from there FML, tonic and
# dart_api.h — a large slice of the engine tree. It is not in the modulemap and
# the framework does not need it; keep it that way.
#
# The manifest for the C++ bridge set is the modulemap itself, so adding a bridge
# header means editing one file rather than two.
#
# --check exits non-zero on drift. Drift matters more than it looks: these
# headers describe the ABI of the libflutter_engine we link against, so a stale
# copy is not a compile error, it is a crash at runtime.
set -euo pipefail

SDK="$(cd "$(dirname "$0")/.." && pwd)"
MODULEMAP="Sources/FlutterSwiftBridgeCxx/include/module.modulemap"

# Single headers to vendor: <engine-relative source>:<destination dir in package>
SINGLES=(
    "flutter/shell/platform/embedder/embedder.h:Sources/FlutterEmbedderBridge/include/engine"
    "flutter/shell/platform/linux_drm/fl_drm_view.h:Sources/FlutterDRMBridge/include/engine"
)
# Where the modulemap-declared C++ bridge headers land.
CXX_DEST="Sources/FlutterSwiftBridgeCxx/include/engine"
CXX_SRC="flutter/lib/ui/swift/include"

CHECK=0
if [ "${1:-}" = "--check" ]; then CHECK=1; shift; fi

# Where the engine checkout is. Explicit argument or $ENGINE_ROOT wins; otherwise
# try the two layouts that exist in practice — an `engine` symlink beside this
# package, and a sibling clone of starling-engine.
ENGINE="${1:-${ENGINE_ROOT:-}}"
if [ -z "$ENGINE" ]; then
    for candidate in "$SDK/../engine" "$SDK/../starling-engine/engine"; do
        if [ -d "$candidate/src/$CXX_SRC" ]; then ENGINE="$candidate"; break; fi
    done
fi
SRC="$ENGINE/src"
if [ -z "$ENGINE" ] || [ ! -d "$SRC/$CXX_SRC" ]; then
    echo "error: no engine bridge headers at ${SRC:-<unset>}/$CXX_SRC" >&2
    echo "       pass the engine root as an argument, or set ENGINE_ROOT" >&2
    exit 1
fi

cd "$SDK"
drift=0
count=0

# one <src> <dest> — copy, or report drift under --check.
one() {
    local from="$1" to="$2"
    if [ ! -f "$from" ]; then
        echo "error: $from is declared but missing from the engine tree" >&2
        exit 1
    fi
    count=$((count + 1))
    if [ "$CHECK" = 1 ]; then
        cmp -s "$from" "$to" || { echo "drift: ${to#Sources/}"; drift=1; }
    else
        mkdir -p "$(dirname "$to")"
        cp "$from" "$to"
    fi
}

# The C++ bridge set, as declared by the modulemap (basenames only).
# read -r in a loop rather than mapfile: mapfile is a bash 4 builtin and macOS
# ships bash 3.2 as /bin/bash, which is what /usr/bin/env bash finds there.
HEADERS=()
while IFS= read -r h; do
    HEADERS+=("$h")
done < <(sed -n 's/.*header "\([^"]*\)".*/\1/p' "$MODULEMAP" \
         | xargs -n1 basename | sort -u)
if [ "${#HEADERS[@]}" -eq 0 ]; then
    echo "error: $MODULEMAP declares no headers" >&2; exit 1
fi
for h in "${HEADERS[@]}"; do
    one "$SRC/$CXX_SRC/$h" "$CXX_DEST/$h"
done

# A header left here after being dropped from the modulemap is dead weight that
# still compiles, so it gets flagged either way.
for stale in $(cd "$CXX_DEST" 2>/dev/null && ls -1 *.h 2>/dev/null || true); do
    printf '%s\n' "${HEADERS[@]}" | grep -qxF "$stale" && continue
    if [ "$CHECK" = 1 ]; then
        echo "stale: $stale is vendored but absent from the modulemap"; drift=1
    else
        rm -f "$CXX_DEST/$stale"; echo "removed stale $stale"
    fi
done

for entry in "${SINGLES[@]}"; do
    rel="${entry%%:*}"; dest="${entry##*:}"
    one "$SRC/$rel" "$dest/$(basename "$rel")"
done

# The GTK embedder's public header set (fl_view.h, fl_engine.h, …), vendored
# whole. NOT under include/: only the bridge's own C glue includes them (with
# FLUTTER_LINUX_COMPILATION defined, the same way the embedder compiles
# itself), so they stay out of the Swift-visible module — GTK types never
# reach the C++-interop importer. The set is closed over quoted relative
# includes plus system GTK/GLib headers.
GTK_SRC="flutter/shell/platform/linux/public/flutter_linux"
GTK_DEST="Sources/FlutterGTKBridge/flutter_linux"
for f in "$SRC/$GTK_SRC"/*.h; do
    one "$f" "$GTK_DEST/$(basename "$f")"
done
for stale in $(cd "$GTK_DEST" 2>/dev/null && ls -1 *.h 2>/dev/null || true); do
    [ -f "$SRC/$GTK_SRC/$stale" ] && continue
    if [ "$CHECK" = 1 ]; then
        echo "stale: flutter_linux/$stale is vendored but gone from the engine"; drift=1
    else
        rm -f "$GTK_DEST/$stale"; echo "removed stale flutter_linux/$stale"
    fi
done

# The Win32 embedder's public header set, vendored the same way and for the
# same reason: only FlutterWin32Bridge's C glue includes them, so <windows.h>
# and the FlutterDesktop* types never reach the C++-interop importer. Unlike
# flutter_linux this is not a whole directory — flutter_windows.h lives beside
# the Windows embedder while the four headers it includes are in
# shell/platform/common/public — so the set is listed explicitly. It is closed:
# nothing in it includes anything outside the destination directory.
WIN_DEST="Sources/FlutterWin32Bridge/flutter_windows"
WIN_HEADERS=(
    "flutter/shell/platform/windows/public/flutter_windows.h"
    "flutter/shell/platform/common/public/flutter_export.h"
    "flutter/shell/platform/common/public/flutter_messenger.h"
    "flutter/shell/platform/common/public/flutter_plugin_registrar.h"
    "flutter/shell/platform/common/public/flutter_texture_registrar.h"
)
WIN_BASENAMES=()
for rel in "${WIN_HEADERS[@]}"; do
    one "$SRC/$rel" "$WIN_DEST/$(basename "$rel")"
    WIN_BASENAMES+=("$(basename "$rel")")
done
for stale in $(cd "$WIN_DEST" 2>/dev/null && ls -1 *.h 2>/dev/null || true); do
    printf '%s\n' "${WIN_BASENAMES[@]}" | grep -qxF "$stale" && continue
    if [ "$CHECK" = 1 ]; then
        echo "stale: flutter_windows/$stale is vendored but not in the list"; drift=1
    else
        rm -f "$WIN_DEST/$stale"; echo "removed stale flutter_windows/$stale"
    fi
done

# FlutterMacOS.framework's public header set, vendored for the same reason as
# the other two: only FlutterCocoaBridge's ObjC glue includes them, so
# <Cocoa/Cocoa.h> and the Flutter* ObjC classes never reach the C++-interop
# importer.
#
# The set is the framework's own, taken from the two lists the framework build
# copies into Versions/A/Headers: the macOS headers in
# shell/platform/darwin/macos/BUILD.gn and framework_common_headers from
# shell/platform/darwin/common/framework_common.gni. It has to be spelled out
# here because those two lists live in GN, and it must stay equal to them —
# vendoring a header the framework does not publish would compile here and be
# missing from any bundle built against a real framework.
#
# Flattening into one directory is what the framework does too
# (install_framework_headers.py copies basenames), and the headers are written
# for it: they import each other by bare quoted filename across the macos/common
# split. So a plain copy is enough, with no include rewriting.
MAC_DEST="Sources/FlutterCocoaBridge/flutter_macos"
MAC_HEADERS=(
    "flutter/shell/platform/darwin/macos/framework/Headers/FlutterAppDelegate.h"
    "flutter/shell/platform/darwin/macos/framework/Headers/FlutterAppLifecycleDelegate.h"
    "flutter/shell/platform/darwin/macos/framework/Headers/FlutterEngine.h"
    "flutter/shell/platform/darwin/macos/framework/Headers/FlutterMacOS.h"
    "flutter/shell/platform/darwin/macos/framework/Headers/FlutterPlatformViews.h"
    "flutter/shell/platform/darwin/macos/framework/Headers/FlutterPluginMacOS.h"
    "flutter/shell/platform/darwin/macos/framework/Headers/FlutterPluginRegistrarMacOS.h"
    "flutter/shell/platform/darwin/macos/framework/Headers/FlutterViewController.h"
    "flutter/shell/platform/darwin/common/framework/Headers/FlutterMacros.h"
    "flutter/shell/platform/darwin/common/framework/Headers/FlutterBinaryMessenger.h"
    "flutter/shell/platform/darwin/common/framework/Headers/FlutterChannels.h"
    "flutter/shell/platform/darwin/common/framework/Headers/FlutterCodecs.h"
    "flutter/shell/platform/darwin/common/framework/Headers/FlutterHourFormat.h"
    "flutter/shell/platform/darwin/common/framework/Headers/FlutterTexture.h"
    "flutter/shell/platform/darwin/common/framework/Headers/FlutterDartProject.h"
)
MAC_BASENAMES=()
for rel in "${MAC_HEADERS[@]}"; do
    one "$SRC/$rel" "$MAC_DEST/$(basename "$rel")"
    MAC_BASENAMES+=("$(basename "$rel")")
done
for stale in $(cd "$MAC_DEST" 2>/dev/null && ls -1 *.h 2>/dev/null || true); do
    printf '%s\n' "${MAC_BASENAMES[@]}" | grep -qxF "$stale" && continue
    if [ "$CHECK" = 1 ]; then
        echo "stale: flutter_macos/$stale is vendored but not in the list"; drift=1
    else
        rm -f "$MAC_DEST/$stale"; echo "removed stale flutter_macos/$stale"
    fi
done

# --- TOOLCHAIN --------------------------------------------------------------
#
# <swift/bridging> is the only toolchain header the bridge headers need, and it
# is the sole reason they used to require an absolute -I into the Swift
# installation. That flag was on *every* Swift target, and .unsafeFlags anywhere
# in a package makes the whole package unusable as a versioned dependency — so
# vendoring this one 11 KB header is what makes FlutterSwift publishable.
#
# All the bridge headers take from it is SWIFT_SHARED_REFERENCE and
# SWIFT_RETURNS_INDEPENDENT_VALUE. Those annotations are what hand the C++
# objects to Swift ARC, so a no-op fallback would compile and then corrupt
# memory; the real definitions have to be here.
#
# The tradeoff: this copy shadows the toolchain's own for anyone building with a
# different Swift version. It is a small, stable compiler-support header — but
# if a future toolchain changes it incompatibly, this is where that breaks.
#
# It is deliberately NOT part of the drift gate, and not overwritten once it
# exists. Unlike every other header here it does not describe the engine's ABI;
# it describes the toolchain in use, and toolchains differ per machine. The
# vendored copy is the newest known-good one, and it has to be: macOS builds
# with Xcode's bundled Swift (6.2.1 at the time of writing) while Linux builds
# with swiftly's (6.2.4), and 6.2.4's copy is a superset — same
# SWIFT_SHARED_REFERENCE and SWIFT_RETURNS_INDEPENDENT_VALUE, plus macros the
# older one lacks. Copying unconditionally meant a macOS run silently
# downgraded it, and --check then failed on every macOS machine, which blocks
# make-bundle.sh before it starts.
#
# So: sync it only when it is missing, and report a difference without failing.
# FLUTTER_SWIFT_SYNC_TOOLCHAIN=1 forces the overwrite, which is what to use when
# deliberately moving to a newer toolchain.
# Ask the compiler where its resources are rather than guessing from $(which
# swiftc): under swiftly that is a shim binary, so walking up from it lands
# nowhere. runtimeResourcePath is <toolchain>/usr/lib/swift on every platform.
RESOURCE_DIR="$(swiftc -print-target-info 2>/dev/null \
    | sed -n 's/.*"runtimeResourcePath"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
if [ -z "$RESOURCE_DIR" ]; then
    echo "error: could not read runtimeResourcePath from 'swiftc -print-target-info'" >&2
    exit 1
fi
TOOLCHAIN_INCLUDE="$(cd "$RESOURCE_DIR/../../include" && pwd)"
BRIDGING_SRC="$TOOLCHAIN_INCLUDE/swift/bridging"
BRIDGING_DEST="Sources/FlutterSwiftBridgeCxx/include/swift/bridging"
if [ ! -f "$BRIDGING_DEST" ] || [ "${FLUTTER_SWIFT_SYNC_TOOLCHAIN:-0}" = 1 ]; then
    one "$BRIDGING_SRC" "$BRIDGING_DEST"
elif ! cmp -s "$BRIDGING_SRC" "$BRIDGING_DEST"; then
    echo "note: ${BRIDGING_DEST#Sources/} differs from this toolchain's copy" \
         "($TOOLCHAIN_INCLUDE) — kept the vendored one;" \
         "FLUTTER_SWIFT_SYNC_TOOLCHAIN=1 to take the toolchain's"
fi

if [ "$CHECK" = 1 ]; then
    if [ "$drift" = 0 ]; then
        echo "vendored headers in sync ($count headers)"
    else
        echo "vendored headers HAVE DRIFTED — run tools/sync-vendored-headers.sh" >&2
    fi
    exit "$drift"
fi

echo "vendored $count headers ($SRC + $TOOLCHAIN_INCLUDE)"
