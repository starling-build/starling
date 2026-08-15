#!/usr/bin/env bash
# Build a Starling app for macOS and assemble it into a shippable .app bundle.
#
#   build/macos-app.sh [app] [--run] [--no-build] [--zip]
#
# Default app: TerminalApp. This is ios-app.sh's macOS counterpart: a `swift
# build` executable runs fine on the machine that built it — its rpaths point
# into the engine checkout — but ships nowhere. The bundle below is
# self-contained: the framework and bridge ride in Contents/Frameworks, the
# engine data rides beside the executable, and every absolute rpath is
# deleted after the copy.
#
#   Starling Terminal.app/Contents/
#     MacOS/TerminalApp               the executable (CFBundleExecutable)
#     MacOS/data -> ../Resources/data CocoaHost reads <exe dir>/data/… — the
#                                     same layout as the GTK and Win32 hosts —
#                                     but the seal wants data under Resources/
#     Frameworks/FlutterMacOS.framework
#     Frameworks/libswift_bridge.dylib
#     Resources/data/icudtl.dat
#     Resources/data/flutter_assets
#     Resources/FlutterSwift_*.bundle SwiftPM resource bundles (the terminal's
#                                     fonts): Bundle.module falls back to
#                                     Bundle.main.resourceURL inside a .app
#     Resources/<Name>.icns           from build/macos/<Name>.icns if present
#
# The engine defaults to host_release_arm64 — the shipped app links the
# library it will actually carry. STARLING_ENGINE_OUT overrides.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="TerminalApp"
RUN=0
BUILD=1
ZIP=0

while [ $# -gt 0 ]; do
    case "$1" in
        --run)      RUN=1 ;;
        --no-build) BUILD=0 ;;
        --zip)      ZIP=1 ;;
        -*)         echo "unknown option: $1" >&2; exit 2 ;;
        *)          APP="$1" ;;
    esac
    shift
done

ENGINE_OUT="${STARLING_ENGINE_OUT:-$REPO/engine/src/out/host_release_arm64}"
if [ ! -f "$ENGINE_OUT/FlutterMacOS.framework/Versions/A/FlutterMacOS" ]; then
    echo "error: no macOS engine at $ENGINE_OUT" >&2
    echo "       build it in the engine repo:" >&2
    echo "         ./flutter/tools/gn --mac-cpu arm64 --runtime-mode release --no-lto" >&2
    echo "         ninja -C out/host_release_arm64 \\" >&2
    echo "             flutter/shell/platform/darwin/macos:flutter_framework \\" >&2
    echo "             flutter/lib/ui/swift:swift_bridge" >&2
    exit 1
fi

PKG="$REPO/apps/$APP"
[ -d "$PKG" ] || { echo "error: no app package at $PKG" >&2; exit 1; }

if [ "$BUILD" = 1 ]; then
    echo "==> building $APP (release, $(basename "$ENGINE_OUT"))"
    STARLING_ENGINE_OUT="$ENGINE_OUT" \
        swift build -c release --package-path "$PKG"
fi

BUILT="$PKG/.build/release"
[ -f "$BUILT/$APP" ] || { echo "error: no $APP binary under $BUILT" >&2; exit 1; }

# The short name drops the "App" suffix the SwiftPM target carries; it keys
# the icon lookup (build/macos/<Name>.icns) and the CFBundleIconFile. What
# the user SEES — Dock, menu bar, app switcher, Activity Monitor, Finder —
# is the display name, and there the bare short name collides: "Terminal"
# on a Mac reads as Apple's Terminal. So the visible name carries the brand.
NAME="${APP%App}"
DISPLAY_NAME="${STARLING_APP_DISPLAY_NAME:-Starling $NAME}"
VER="${STARLING_APP_VERSION:-0.1.0}"
OUT="$REPO/.stage-macos/$DISPLAY_NAME.app"
C="$OUT/Contents"
rm -rf "$OUT"
mkdir -p "$C/MacOS" "$C/Frameworks" "$C/Resources/data"

cp "$BUILT/$APP" "$C/MacOS/$APP"
for b in "$BUILT"/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$C/Resources/"
done
# CocoaHost reads <exe dir>/data, but codesign's resource seal only covers
# Resources/ — anything else under MacOS/ must be signed code. So the data
# lives in Resources/ and MacOS/data is a sealed symlink to it.
cp "$ENGINE_OUT/FlutterMacOS.framework/Versions/A/Resources/icudtl.dat" "$C/Resources/data/"
cp -R "$REPO/sdk/Resources/flutter_assets" "$C/Resources/data/flutter_assets"
rm -f "$C/Resources/data/flutter_assets/.last_build_id"
ln -s ../Resources/data "$C/MacOS/data"
# cp -R keeps the framework's Versions/Current symlink structure intact.
cp -R "$ENGINE_OUT/FlutterMacOS.framework" "$C/Frameworks/FlutterMacOS.framework"
cp "$ENGINE_OUT/libswift_bridge.dylib" "$C/Frameworks/libswift_bridge.dylib"
ICON=""
if [ -f "$REPO/build/macos/$NAME.icns" ]; then
    cp "$REPO/build/macos/$NAME.icns" "$C/Resources/$NAME.icns"
    ICON="$NAME"
fi

# Both engine deps are @rpath references, so pointing rpath into the bundle is
# the whole relocation. Then delete every absolute rpath the build baked in:
# the engine out-directory (and, via SwiftPM's manifest cache, sometimes a
# stale second one) plus the swift.org toolchain path. /usr/lib/swift and
# @loader_path stay — the Swift runtime resolves from the OS.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$C/MacOS/$APP"
otool -l "$C/MacOS/$APP" | awk '/LC_RPATH/{f=1} f && / path /{print $2; f=0}' |
while read -r rp; do
    case "$rp" in
        /usr/lib/swift) ;;
        /*) install_name_tool -delete_rpath "$rp" "$C/MacOS/$APP" ;;
    esac
done

cat > "$C/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>        <string>en</string>
  <key>CFBundleExecutable</key>               <string>$APP</string>
  <key>CFBundleIdentifier</key>               <string>build.starling.$(echo "$NAME" | tr '[:upper:]' '[:lower:]')</string>
  <key>CFBundleInfoDictionaryVersion</key>    <string>6.0</string>
  <key>CFBundleName</key>                     <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>              <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>              <string>APPL</string>
  <key>CFBundleShortVersionString</key>       <string>$VER</string>
  <key>CFBundleVersion</key>                  <string>$VER</string>
  ${ICON:+<key>CFBundleIconFile</key>               <string>$ICON</string>}
  <key>LSMinimumSystemVersion</key>           <string>14.0</string>
  <key>NSHighResolutionCapable</key>          <true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key> <true/>
</dict>
</plist>
PLIST

# Inside-out: the nested code first, then the bundle seal over it. Ad-hoc by
# default — enough to run locally and for a recipient who right-clicks Open
# (or clears quarantine); pass a "Developer ID Application: …" identity in
# STARLING_MACOS_IDENTITY to produce something notarizable.
IDENTITY="${STARLING_MACOS_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --timestamp=none \
    "$C/Frameworks/libswift_bridge.dylib"
codesign --force --sign "$IDENTITY" --timestamp=none \
    "$C/Frameworks/FlutterMacOS.framework"
codesign --force --sign "$IDENTITY" --timestamp=none "$OUT"
codesign --verify --strict "$OUT"

echo "==> $OUT"

if [ "$ZIP" = 1 ]; then
    ZIPOUT="$REPO/.stage-macos/${DISPLAY_NAME// /-}-$VER-macos-arm64.zip"
    rm -f "$ZIPOUT"
    # ditto's zip keeps symlinks and metadata, which `zip -r` would flatten —
    # a framework with a materialized Versions/Current fails codesign on the
    # receiving end.
    ditto -c -k --keepParent "$OUT" "$ZIPOUT"
    echo "==> $ZIPOUT"
fi

[ "$RUN" = 1 ] && open "$OUT"
exit 0
