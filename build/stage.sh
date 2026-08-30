#!/usr/bin/env bash
# Assemble a complete, self-contained Starling desktop tree from the build
# outputs scattered across this repo (shell/.build, apps/*/.build, the engine
# checkout, the swiftly toolchain) into ONE directory.
#
#   build/stage.sh [outdir] [--apps "A B C"] [--config release]
#
# Default outdir: .stage/ at the repo root (gitignored).
#
# The staged layout mirrors the installed one exactly:
#
#   <stage>/lib/         -> /usr/lib/starling    binaries + every .so they need
#   <stage>/lib/apps/    -> .../apps             child apps (FLUTTER_APPS_DIR)
#   <stage>/lib/appbin/  -> .../appbin           xdg-open shim etc.
#   <stage>/share/       -> /usr/share/starling  icudtl.dat, flutter_assets,
#                                                wallpaper, icons, shaders
#   <stage>/bin/         -> /usr/bin             app-run, app-install
#
# Why this exists: running straight out of .build only works by coincidence of
# relative rpaths and the shell's cwd, and child apps are spawned with
# LD_LIBRARY_PATH scrubbed, so they resolve libraries via their own $ORIGIN
# only. Staging puts every library next to the binary that needs it, which is
# the same arrangement that ships — so the dev loop exercises the shipping
# configuration instead of a dev-only one.
#
# Both build/run-desktop.sh and build/package-desktop.sh consume this, so the
# layout is defined in exactly one place.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT=""
CONFIG=release
APPS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --apps)   APPS="$2"; shift 2 ;;
        --config) CONFIG="$2"; shift 2 ;;
        -*)       echo "unknown option: $1" >&2; exit 1 ;;
        *)        OUT="$1"; shift ;;
    esac
done
OUT="${OUT:-$REPO/.stage}"

# ONE build tree for the whole desktop — the shell and every app — produced by
# build/build-all.sh. sdk/ is a path dependency of all twelve packages, and
# SwiftPM compiles a path dependency per consuming package: built one package
# at a time, this tree holds twelve copies of the framework and staging has to
# choose. Choosing is where the bugs lived — the staged copy was the shell's,
# so an sdk/ change reached the app you rebuilt and not the framework it loads,
# silently whenever the change was to an existing function rather than the API.
# A shared scratch path builds the sdk targets once and has everything reuse
# them, so there is one framework and nothing to choose between.
SHELL_BUILD="${STARLING_SCRATCH:-$REPO/.build-shared}"

# SwiftPM writes to .build/<target-triple>/<config>, so staging has to know the
# triple. Derive it — this used to be hardcoded to x86_64-unknown-linux-gnu, so
# on any other architecture staging looked in a directory that does not exist
# and died at the first install(1) with "cannot stat .../x86_64-unknown-linux-gnu
# /release/libFlutterShared.so", which reads as a missing build rather than a
# wrong guess.
#
# The build tree is the authority: it is the thing being read, and consulting it
# needs no toolchain on PATH — stage.sh runs under sudo in some flows, where
# swiftly's swiftc is not on root's PATH. swiftc is the fallback, and the host
# architecture the last resort.
host_triple() {
    local p d
    for p in "$SHELL_BUILD"/*/"$CONFIG"/libFlutterShared.so; do
        [ -e "$p" ] || continue
        d=${p#"$SHELL_BUILD"/}
        printf '%s\n' "${d%%/*}"
        return 0
    done
    d="$(swiftc -print-target-info 2>/dev/null \
         | sed -n 's/.*"unversionedTriple": *"\([^"]*\)".*/\1/p' | head -1)"
    [ -n "$d" ] && { printf '%s\n' "$d"; return 0; }
    printf '%s\n' "$(uname -m)-unknown-linux-gnu"
}
TRIPLE="${STARLING_TRIPLE:-$(host_triple)}"
E=$REPO/engine/src/out/host_release
[ -d "$E" ] || E=$REPO/engine/src/out/host_debug
E="${STARLING_ENGINE_OUT:-$E}"

[ -f "$E/libflutter_engine.so" ] || {
    echo "error: no libflutter_engine.so in $E — build the engine first" >&2; exit 1
}
[ -x "$SHELL_BUILD/$CONFIG/DesktopShellApp" ] || {
    echo "error: nothing built at $SHELL_BUILD — run build/build-all.sh" >&2; exit 1
}

# Default app set: every app with a built binary for this config.
if [ -z "$APPS" ]; then
    for d in "$REPO"/apps/*/; do
        a=$(basename "$d")
        [ -x "$SHELL_BUILD/$CONFIG/$a" ] && APPS="$APPS $a"
    done
fi
APPS="$(echo "$APPS" | xargs)"   # trim

# Building in a package-local scratch is invisible here — stage reads ONLY
# $SHELL_BUILD. If such a scratch holds a NEWER binary than the one about to
# be staged, someone almost certainly rebuilt the wrong tree; say so loudly,
# because the staged copy's own mtime is install(1)'s copy time and looks
# fresh regardless of what it was built from.
drift=""
if [ -x "$REPO/shell/.build/$CONFIG/DesktopShellApp" ] &&
   [ "$REPO/shell/.build/$CONFIG/DesktopShellApp" -nt "$SHELL_BUILD/$CONFIG/DesktopShellApp" ]; then
    drift="$drift shell/.build"
fi
for a in $APPS; do
    if [ -x "$REPO/apps/$a/.build/$CONFIG/$a" ] && [ -x "$SHELL_BUILD/$CONFIG/$a" ] &&
       [ "$REPO/apps/$a/.build/$CONFIG/$a" -nt "$SHELL_BUILD/$CONFIG/$a" ]; then
        drift="$drift apps/$a/.build"
    fi
done
if [ -n "$drift" ]; then
    echo "stage: WARNING: newer binaries in:$drift — package-local scratches are" >&2
    echo "stage: NOT staged; build/build-all.sh feeds $SHELL_BUILD" >&2
fi
if [ -f "$SHELL_BUILD/$CONFIG/BUILD-STAMP" ]; then
    echo "stage: staging build $(cat "$SHELL_BUILD/$CONFIG/BUILD-STAMP")"
fi

LIB=$OUT/lib
SHARE=$OUT/share
rm -rf "$OUT"
mkdir -p "$LIB/apps" "$LIB/appbin" "$SHARE/shaders" "$OUT/bin"

# --- shell + engine ----------------------------------------------------------
install -m755 "$SHELL_BUILD/$CONFIG/DesktopShellApp" "$LIB/"
install -m644 "$SHELL_BUILD/$TRIPLE/$CONFIG/libFlutterShared.so" "$LIB/"
if [ -f "$SHELL_BUILD/$CONFIG/BUILD-STAMP" ]; then
    install -m644 "$SHELL_BUILD/$CONFIG/BUILD-STAMP" "$LIB/"
fi
install -m644 "$E/libflutter_engine.so" "$E/libflutter_linux_drm.so" "$LIB/"

# SwiftPM resource bundles (CupertinoIcons font, …): the generated accessor
# fatals if the bundle isn't next to the executable. Ship every one.
for r in "$SHELL_BUILD/$TRIPLE/$CONFIG/"*.resources; do
    [ -d "$r" ] && cp -r "$r" "$LIB/"
done

# --- Swift runtime: the ldd closure of everything we stage, limited to what
# the swiftly toolchain provides (absent on target machines) ------------------
{
    ldd "$SHELL_BUILD/$CONFIG/DesktopShellApp"
    for a in $APPS; do ldd "$SHELL_BUILD/$CONFIG/$a"; done
} 2>/dev/null | awk '$3 ~ /swiftly\/toolchains/ {print $3}' | sort -u | while read -r so; do
    install -m644 "$so" "$LIB/"
done

# --- first-party apps --------------------------------------------------------
for a in $APPS; do
    install -m755 "$SHELL_BUILD/$CONFIG/$a" "$LIB/apps/"
    for r in "$SHELL_BUILD/$TRIPLE/$CONFIG/"*.resources; do
        [ -d "$r" ] && cp -r "$r" "$LIB/apps/"
    done
    # No per-app framework to stage, and no choice to get wrong: every
    # package is built into one scratch tree (see the note at SHELL_BUILD), so
    # there is exactly one libFlutterShared.so and the apps reach it through
    # the symlink loop below, the same way they reach libflutter_engine.so.
    #
    # It used to be one .build per package — twelve copies of the same
    # framework. Staging them all meant the LAST app in this loop supplied the
    # framework every child app loaded, since $ORIGIN is the shared apps/ dir;
    # staging only the shell's meant an sdk/ change reached the app you rebuilt
    # but not the library it loads. Both were silent. Building once removes the
    # question rather than answering it.
    # Vendored per-app libraries (ImageViewerApp's PDFium).
    for dep in "$REPO/apps/$a/.deps/"*/lib/*.so; do
        [ -f "$dep" ] && install -m644 "$dep" "$LIB/apps/"
    done
done

# Child apps resolve libraries via their own $ORIGIN only — the shell's
# child-spawn path scrubs LD_LIBRARY_PATH (STARLING_CHILD_HOST_GL, a dev-Mesa
# workaround) — so the engine + Swift runtime must be reachable from apps/ too.
# Symlinks keep the tree size flat.
for so in "$LIB"/*.so; do
    b="$(basename "$so")"
    [ -e "$LIB/apps/$b" ] || ln -s "../$b" "$LIB/apps/$b"
done

# --- assets: engine data + flutter_assets + shell data files -----------------
# flutter_assets is what the embedder is pointed at (args.assets_path), but it
# holds only the manifests, the engine's third-party NOTICES and its shaders.
# The Dart snapshots a normal Flutter app would ship here — kernel_blob.bin,
# isolate_snapshot_data, vm_snapshot_data, 35 MB of them — are gone: the Swift
# runtime replaces the Dart framework, so no isolate is ever created and
# neither the release (AOT) nor the debug (JIT) engine reads them. Verified by
# deleting all three and booting both engines.
install -m644 "$E/icudtl.dat" "$SHARE/"
cp -r "$REPO/build/flutter_assets" "$SHARE/"
# Wallpapers: the bundled JPEGs, decoded and center-cropped at runtime.
# sdk/wallpaper.rgba is deliberately NOT staged — it is the legacy
# pre-rendered 3840x2160 raw path, which _loadWallpaperTexture() checks
# FIRST, so staging it silently pins the desktop to that stale image and
# the bundled default never loads (and it costs 33 MB).
mkdir -p "$SHARE/wallpapers"
install -m644 "$REPO"/shell/Resources/Wallpapers/*.jpg "$SHARE/wallpapers/"
# The app catalog: one record per app the desktop knows about. The launcher,
# the dock, the App Store and app-install all read it, so it has to be here
# for any of them to know an app exists.
mkdir -p "$SHARE/catalog.d"
install -m644 "$REPO"/registry/catalog.d/*.app "$SHARE/catalog.d/"
# No third-party app icons are staged: those marks are their owners'
# trademarks, so the dock reads them from the host's freedesktop icon theme at
# runtime (DesktopEntry lookup) and falls back to its own neutral glyph.
install -m644 "$REPO/shell/Sources/DesktopShellApp/Shaders/liquid_glass.frag.iplr" \
    "$SHARE/shaders/"
install -m644 "$REPO/shell/Sources/DesktopShellApp/Shaders/screensaver.frag.iplr" \
    "$SHARE/shaders/"
# Aerials: the directory is shipped, the footage is not. The screensaver is
# complete without it — no clip means the liquid warp over the live desktop,
# which needs no assets — and the clips worth having are tens of megabytes
# each, which is not a cost to put on every install for a decoration. Drop an
# .mp4 in here (or in ~/.local/share/starling/aerials) and the saver dissolves
# into it; AerialPlayer.discoverClip() takes the first by name.
mkdir -p "$SHARE/aerials"
install -m644 "$REPO/shell/Resources/aerials-README" "$SHARE/aerials/README"

# --- third-party app tools: host-direct runner + apt-only installer ---------
install -m755 "$REPO/build/app-run.sh" "$OUT/bin/app-run"
install -m755 "$REPO/build/app-install.sh" "$OUT/bin/app-install"
install -m755 "$REPO/build/wechat-run.sh" "$OUT/bin/wechat-run"
install -m755 "$REPO"/build/appbin/* "$LIB/appbin/"

# --- agent surface: the CLI an agent drives the desktop with, and the skill
# that teaches one how. The CLI goes on PATH because an agent invokes it as a
# shell command; the skill ships as data and is linked into an agent's
# ~/.claude/skills/ (see the README beside it) rather than installed there
# outright, since that directory belongs to the user, not the package.
install -m755 "$REPO/build/agent-client.py" "$OUT/bin/agent-client"
# Computer use for anything that speaks MCP — Claude Desktop for Linux ships
# without it, and this is the seventeen toolset members over the broker. It
# imports agent-client from beside it, so the two travel together.
install -m755 "$REPO/build/computer-use-mcp.py" "$OUT/bin/starling-computer-use"
mkdir -p "$SHARE/skills/starling-desktop"
install -m644 "$REPO/build/skills/starling-desktop/SKILL.md" \
    "$SHARE/skills/starling-desktop/"
install -m644 "$REPO/build/skills/README.md" "$SHARE/skills/"

echo "staged -> $OUT"
echo "  engine: $E"
echo "  config: $CONFIG"
echo "  apps:   $APPS"
