#!/usr/bin/env bash
# Assemble a self-contained Starling SDK distribution: the framework source plus
# the engine binaries it links against, in one tree.
#
#   tools/make-bundle.sh [--debug|--release] [outdir]
#
# Produces <outdir>/starling-sdk-<platform>-<arch>/ and a .tar.gz of it. A
# consumer unpacks that and depends on it by path:
#
#   .package(path: "/opt/starling-sdk")
#
# and needs no engine checkout, no ../engine symlink, and no configuration —
# Package.swift probes for engine/lib inside the bundle.
#
# WHY A PATH DEPENDENCY AND NOT A VERSIONED ONE. SwiftPM cannot carry a native
# *library* as a binaryTarget on Linux (XCFramework is Apple-only; artifactbundles
# hold executables), and locating the bundled engine needs -L/-rpath, which are
# .unsafeFlags — rejected for dependencies resolved by URL+version, allowed for a
# path dependency. Bundling therefore sidesteps that restriction rather than
# satisfying it. The cost is no `swift package update`: this is a download-and-point
# SDK, the same shape as the Flutter SDK itself.
set -euo pipefail

SDK="$(cd "$(dirname "$0")/.." && pwd)"

# This package is standalone, so the engine checkout is not at a fixed offset any
# more. Same candidates as tools/sync-vendored-headers.sh: an `engine` symlink
# beside the package, or a sibling clone of starling-engine.
ENGINE_ROOT="${ENGINE_ROOT:-}"
if [ -z "$ENGINE_ROOT" ]; then
    for candidate in "$SDK/../engine" "$SDK/../starling-engine/engine"; do
        if [ -d "$candidate/src" ]; then ENGINE_ROOT="$candidate"; break; fi
    done
fi

CONFIG=release
case "${1:-}" in
    --debug)   CONFIG=debug;   shift ;;
    --release) CONFIG=release; shift ;;
esac
OUT="${1:-/tmp/starling-sdk-bundle}"

case "$(uname -s)" in
    Linux)  PLATFORM=linux  ;;
    Darwin) PLATFORM=macos  ;;
    *) echo "error: unsupported platform $(uname -s)" >&2; exit 1 ;;
esac
ARCH="$(uname -m)"
NAME="starling-sdk-$PLATFORM-$ARCH"
DEST="$OUT/$NAME"

# The engine build to take binaries from. host_debug is what the desktop links
# against day to day; host_release is what a consumer should ship. On a Mac
# the gn out dir carries the cpu suffix (--mac-cpu arm64 → host_release_arm64),
# so probe that spelling first there.
E="${FLUTTER_SWIFT_ENGINE_OUT:-}"
if [ -z "$E" ]; then
    E="$ENGINE_ROOT/src/out/host_$CONFIG"
    if [ "$PLATFORM" = macos ] && [ -d "$ENGINE_ROOT/src/out/host_${CONFIG}_$ARCH" ]; then
        E="$ENGINE_ROOT/src/out/host_${CONFIG}_$ARCH"
    fi
fi
if [ ! -f "$E/libflutter_engine.so" ] && [ ! -f "$E/libswift_bridge.dylib" ]; then
    echo "error: no engine binaries in $E" >&2
    echo "       build the engine first (see docs/BUILDING.md), or set" >&2
    echo "       FLUTTER_SWIFT_ENGINE_OUT to a directory that has them" >&2
    exit 1
fi

# Refuse to ship headers that have drifted from the engine we are bundling: the
# vendored bridge headers describe that binary's ABI.
if ! "$SDK/tools/sync-vendored-headers.sh" --check >/dev/null 2>&1; then
    echo "error: vendored headers have drifted from the engine tree" >&2
    echo "       run tools/sync-vendored-headers.sh and rebuild before bundling" >&2
    exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST/engine/lib" "$DEST/engine/share"

# --- framework source -------------------------------------------------------
# Sources/, Examples/, Tests/ and tools/ go as-is. .build is deliberately
# excluded — a consumer's toolchain differs from ours.
# Examples/ must ship: the manifest declares the app targets with explicit
# paths there, and SwiftPM refuses to parse a manifest whose target
# directories are missing.
# README.md is not copied: the bundle gets its own, written below.
for item in Package.swift Sources Examples Tests tools LICENSE; do
    [ -e "$SDK/$item" ] || { echo "error: missing $item" >&2; exit 1; }
    cp -r "$SDK/$item" "$DEST/"
done

# --- engine binaries --------------------------------------------------------
if [ "$PLATFORM" = linux ]; then
    install -m644 "$E/libflutter_engine.so" "$DEST/engine/lib/"
    # The DRM embedder is what FlutterDRMBridge binds; optional for consumers
    # that only use the framework, so do not fail without it.
    [ -f "$E/libflutter_linux_drm.so" ] && install -m644 "$E/libflutter_linux_drm.so" "$DEST/engine/lib/"
    # The GTK embedder is what FlutterGTK binds — the windowed host, and so the
    # one every ordinary desktop app in this bundle depends on. Missing it is
    # not a degraded bundle, it is a broken one: apps link fine and die at
    # startup on "libflutter_linux_gtk.so: cannot open shared object file". It
    # used to be copied only if present, and shipped a bundle without it,
    # because BUILDING.md's ninja line did not name it. Refuse instead.
    if [ ! -f "$E/libflutter_linux_gtk.so" ]; then
        echo "error: $E/libflutter_linux_gtk.so is missing — build it with" >&2
        echo "       ninja -C $(basename "$E") libflutter_linux_gtk.so" >&2
        exit 1
    fi
    install -m644 "$E/libflutter_linux_gtk.so" "$DEST/engine/lib/"
else
    cp -R "$E/FlutterMacOS.framework" "$DEST/engine/lib/"
    install -m644 "$E/libswift_bridge.dylib" "$DEST/engine/lib/"
fi

# --- runtime data -----------------------------------------------------------
# icudtl.dat and flutter_assets are needed at *run* time, not link time, but a
# consumer with neither cannot start an engine, so they travel with the bundle.
#
# macOS deliberately does not take the one beside the engine. There are two
# different files in a mac out directory and only one of them is Flutter's:
# FlutterMacOS.framework/Versions/A/Resources/icudtl.dat is the trimmed build
# (~780 KB, //flutter/third_party/icu/flutter) and has already travelled with
# the framework above, while the top-level icudtl.dat is full ICU (~10 MB,
# third_party/icu/common) that the engine's own tests use. Shipping the second
# one would put 10 MB of the wrong flavour in engine/share for a consumer to
# point at by habit, so on macOS the framework's copy is the only one — which
# is why the hosts look inside the framework first.
if [ "$PLATFORM" = linux ]; then
    [ -f "$E/icudtl.dat" ] && install -m644 "$E/icudtl.dat" "$DEST/engine/share/"
fi

# flutter_assets: the vendored copy in Resources/ normally, overridable, with the
# desktop's copy as a fallback for anyone building from a starling checkout.
ASSETS="${FLUTTER_SWIFT_ASSETS:-}"
if [ -z "$ASSETS" ]; then
    for candidate in "$SDK/Resources/flutter_assets" "$SDK/../starling/build/flutter_assets"; do
        if [ -d "$candidate" ]; then ASSETS="$candidate"; break; fi
    done
fi
if [ -n "$ASSETS" ]; then
    cp -r "$ASSETS" "$DEST/engine/share/"
else
    echo "warning: no flutter_assets found; the bundle cannot start an engine" >&2
    echo "         set FLUTTER_SWIFT_ASSETS to an asset bundle" >&2
fi

# --- the generated README's platform-specific halves -------------------------
# The two platforms differ in the three places a consumer can get stuck: the
# extra swiftSettings they need, how the engine is deployed beside their binary,
# and where icudtl.dat is. Writing the Linux answers on a macOS bundle would be
# worse than saying nothing — .so/$ORIGIN/LD_LIBRARY_PATH have no meaning there.
if [ "$PLATFORM" = linux ]; then
    MATH_SETTING='
            // Required on Ubuntu 26.04 (glibc 2.43 + libstdc++ 15), and harmless
            // elsewhere. SwiftPM does not propagate swiftSettings from a
            // dependency, so this package applying it internally does nothing for
            // you: your own C++-interop targets pull Foundation'"'"'s C shim in their
            // own context and hit "cmath: redefinition of '"'"'acos'"'"'" without it.
            // Drop it once swift.org ships a native 26.04 toolchain.
            .unsafeFlags(["-Xcc", "-D_GLIBCXX_MATH_H",
                          "-Xcc", "-include", "-Xcc", "/usr/include/math.h"]),'
    HOST_PRODUCT="FlutterGTK"
    ENGINE_LIB_DESC="libflutter_engine.so, libflutter_linux_drm.so, libflutter_linux_gtk.so"
    ICU_LAYOUT="    engine/share/icudtl.dat         ICU data, needed to start an engine"
    SHIP_BODY='The rpath above points here, which is fine on your machine and useless on someone
else'"'"'s. SwiftPM also puts `$ORIGIN` in the rpath, so deployment is a copy:

```bash
cp .build/release/App                 dist/
cp /opt/'"$NAME"'/engine/lib/*.so         dist/     # sits beside the binary
cp -r /opt/'"$NAME"'/engine/share         dist/     # icudtl.dat + flutter_assets
```

`dist/App` then runs anywhere with no `LD_LIBRARY_PATH`. Skip the library copy and
you get `libflutter_engine.so: cannot open shared object file` at startup, not at
build time. Point your embedder at `share/icudtl.dat` and `share/flutter_assets`.'
    OVERRIDE_MATH='`FLUTTER_SWIFT_GLIBC_MATH_COMPAT=0/1` forces the Ubuntu 26.04 <cmath> workaround
off or on; it is applied automatically when libstdc++ 15 or newer is present.'
else
    MATH_SETTING=''
    HOST_PRODUCT="FlutterCocoa"
    ENGINE_LIB_DESC="FlutterMacOS.framework, libswift_bridge.dylib"
    ICU_LAYOUT="    engine/lib/FlutterMacOS.framework/Versions/A/Resources/icudtl.dat
                                    ICU data, needed to start an engine —
                                    inside the framework on this platform"
    SHIP_BODY='The rpath above points here, which is fine on your machine and useless on someone
else'"'"'s. SwiftPM also puts `@executable_path` in the rpath, so deployment is a copy:

```bash
cp .build/release/App                        dist/
cp -R /opt/'"$NAME"'/engine/lib/FlutterMacOS.framework  dist/   # beside the binary
cp    /opt/'"$NAME"'/engine/lib/libswift_bridge.dylib   dist/
cp -r /opt/'"$NAME"'/engine/share                       dist/   # flutter_assets
```

Both engine binaries carry an `@rpath` install name, so `dist/App` then runs
anywhere with nothing set in the environment. Skip the copy and you get
`Library not loaded: @rpath/libswift_bridge.dylib` at launch, not at build time.
Point your embedder at the framework'"'"'s
`Versions/A/Resources/icudtl.dat` and at `share/flutter_assets`.'
    OVERRIDE_MATH=''
fi

cat > "$DEST/README.md" <<EOF
# Starling SDK — $PLATFORM/$ARCH bundle ($CONFIG engine)

The Flutter framework ported to Swift, with the engine binaries it links against.
No engine checkout or toolchain configuration needed.

## Use it

\`\`\`swift
dependencies: [.package(path: "/opt/$NAME")],
targets: [
    .executableTarget(
        name: "App",
        dependencies: [
            .product(name: "Flutter", package: "$NAME"),
            // The dart:ui types — Offset, Size, Rect, Paint, Canvas. Separate
            // from Flutter, which does not re-export them.
            .product(name: "FlutterSwiftBridge", package: "$NAME"),
            // The windowed host for this platform: it opens the window and
            // starts the engine in Swift mode.
            .product(name: "$HOST_PRODUCT", package: "$NAME"),
        ],
        swiftSettings: [
            // Required. The framework is C++-interop; this is not inherited from
            // the dependency, and without it you get:
            //   module 'FlutterSwiftBridgeCxx' requires feature 'cplusplus'
            .interoperabilityMode(.Cxx),$MATH_SETTING
        ]
    ),
]
\`\`\`

\`\`\`swift
import Flutter
import FlutterSwiftBridge

print(Offset(3, 4).distance)   // 5.0
\`\`\`

**You do not add the engine library to your package, and you do not set a library
path.** This package's own linker settings put \`-L\` on the link line and bake an
rpath into your executable, so \`swift build\` and \`swift run\` find
\`libflutter_engine\` with no configuration.

It is a path dependency rather than \`.package(url:from:)\` because locating the
bundled engine needs linker flags SwiftPM classes as unsafe, which it permits for
path dependencies only. Consequence: **moving this directory after building means
rebuilding**, as the engine location is in your binary's rpath.

## Ship your app

$SHIP_BODY

This bundle is built for **$PLATFORM/$ARCH**; other targets need their own.

## Layout

    Package.swift Sources/ Tests/   the framework
    Examples/                       the demo and example apps
    engine/lib/                     $ENGINE_LIB_DESC
$ICU_LAYOUT
    engine/share/flutter_assets/    default asset bundle

## Overrides

\`FLUTTER_SWIFT_ENGINE_OUT\` points at a different engine build.
$OVERRIDE_MATH
EOF

( cd "$OUT" && tar czf "$NAME.tar.gz" "$NAME" )

echo "bundle:  $DEST"
echo "tarball: $OUT/$NAME.tar.gz ($(du -h "$OUT/$NAME.tar.gz" | cut -f1))"
echo "engine:  $E ($CONFIG)"
