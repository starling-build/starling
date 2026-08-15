#!/usr/bin/env bash
# Build a Starling app for iOS and assemble it into a real .app bundle, then
# optionally install and launch it on a simulator.
#
#   build/ios-app.sh [app] [--device] [--run] [--sim NAME] [--no-build]
#
# Default app: TerminalApp. Default target: the iOS simulator, because that is
# the one that needs no signing identity and no provisioning profile — a
# device build is the same tree with `--device` and a real signature.
#
# This is stage.sh's counterpart for iOS and exists for the same reason: an
# iOS app cannot run out of .build under any circumstances. A bare Mach-O is
# not an app there, the loader will only follow @rpath into the bundle, and
# the engine's own asset lookup goes through NSBundle. So the layout below is
# not a packaging step that happens at the end — it is the only arrangement in
# which the thing runs at all.
#
#   Terminal.app/
#     TerminalApp                     the executable (CFBundleExecutable)
#     Info.plist                      identity, min OS, device family
#     flutter_assets/                 found by FLTAssetsPathFromBundle's
#                                     bare-`flutter_assets` fallback
#     FlutterSwift_*.bundle           SwiftPM resource bundles: the terminal's
#                                     DejaVu/Roboto Mono faces reach the engine
#                                     through Bundle.module, which resolves
#                                     inside the main bundle
#     Frameworks/
#       Flutter.framework             the engine, and icudtl.dat with it
#       libswift_bridge.dylib         the Swift bridge, @rpath'd beside it
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="TerminalApp"
MODE="sim"
RUN=0
BUILD=1
SIM="iPhone 16 Pro"

while [ $# -gt 0 ]; do
    case "$1" in
        --device)   MODE="device" ;;
        --run)      RUN=1 ;;
        --no-build) BUILD=0 ;;
        --sim)      SIM="$2"; shift ;;
        -*)         echo "unknown option: $1" >&2; exit 2 ;;
        *)          APP="$1" ;;
    esac
    shift
done

if [ "$MODE" = "device" ]; then
    SDK_NAME="iphoneos"
    TRIPLE="arm64-apple-ios17.0"
    # gn names the device directory without the cpu suffix: `--ios` alone
    # is arm64, only `--simulator` grows a `_sim_arm64` tail.
    ENGINE_OUT="$REPO/engine/src/out/ios_debug"
    STARLING_IOS_VALUE="device"
else
    SDK_NAME="iphonesimulator"
    TRIPLE="arm64-apple-ios17.0-simulator"
    ENGINE_OUT="$REPO/engine/src/out/ios_debug_sim_arm64"
    STARLING_IOS_VALUE="1"
fi

SDK_PATH="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
if [ ! -f "$ENGINE_OUT/Flutter.framework/Flutter" ]; then
    echo "error: no iOS engine at $ENGINE_OUT" >&2
    echo "       build it in the engine repo:" >&2
    echo "         ./flutter/tools/gn --ios ${MODE:+--simulator --simulator-cpu arm64}" >&2
    echo "         ninja -C out/$(basename "$ENGINE_OUT") \\" >&2
    echo "             flutter/shell/platform/darwin/ios:universal_flutter_framework \\" >&2
    echo "             flutter/lib/ui/swift:swift_bridge" >&2
    exit 1
fi

PKG="$REPO/apps/$APP"
[ -d "$PKG" ] || { echo "error: no app package at $PKG" >&2; exit 1; }

if [ "$BUILD" = 1 ]; then
    echo "==> building $APP for $SDK_NAME"
    STARLING_IOS="$STARLING_IOS_VALUE" \
        swift build -c release --package-path "$PKG" \
            --triple "$TRIPLE" --sdk "$SDK_PATH"
fi

BUILT="$PKG/.build/$(basename "$TRIPLE" | sed 's/^arm64-apple-ios[0-9.]*/arm64-apple-ios/')/release"
# SwiftPM names the directory after the triple with the version stripped:
# arm64-apple-ios-simulator, or arm64-apple-ios for a device.
[ -d "$BUILT" ] || BUILT="$PKG/.build/arm64-apple-ios-simulator/release"
[ -f "$BUILT/$APP" ] || { echo "error: no $APP binary under $BUILT" >&2; exit 1; }

# The bundle name drops the "App" suffix the SwiftPM target carries, so the
# home screen reads "Terminal" the way every other Starling surface names it.
NAME="${APP%App}"
OUT="$REPO/.stage-ios/$NAME.app"
rm -rf "$OUT"
mkdir -p "$OUT/Frameworks"

cp "$BUILT/$APP" "$OUT/$APP"
for b in "$BUILT"/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$OUT/"
done
cp -R "$REPO/sdk/Resources/flutter_assets" "$OUT/flutter_assets"
cp -R "$ENGINE_OUT/Flutter.framework" "$OUT/Frameworks/Flutter.framework"
cp "$ENGINE_OUT/libswift_bridge.dylib" "$OUT/Frameworks/libswift_bridge.dylib"

# UIRequiredDeviceCapabilities is deliberately absent: the simulator is not
# arm64e and listing arm64 there has rejected simulator installs before.
# UILaunchScreen (empty dict) is required from iOS 14 — without it the app
# launches into a letterboxed 320x480 canvas on a modern screen, which reads
# as "the terminal renders tiny" rather than "the bundle is missing a key".
cat > "$OUT/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>        <string>en</string>
  <key>CFBundleExecutable</key>               <string>$APP</string>
  <key>CFBundleIdentifier</key>               <string>build.starling.$(echo "$NAME" | tr '[:upper:]' '[:lower:]')</string>
  <key>CFBundleInfoDictionaryVersion</key>    <string>6.0</string>
  <key>CFBundleName</key>                     <string>$NAME</string>
  <key>CFBundleDisplayName</key>              <string>$NAME</string>
  <key>CFBundlePackageType</key>              <string>APPL</string>
  <key>CFBundleShortVersionString</key>       <string>0.1</string>
  <key>CFBundleVersion</key>                  <string>1</string>
  <key>LSRequiresIPhoneOS</key>               <true/>
  <key>MinimumOSVersion</key>                 <string>17.0</string>
  <key>UILaunchScreen</key>                   <dict/>
  <key>UIDeviceFamily</key>                   <array><integer>1</integer><integer>2</integer></array>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
  <key>CFBundleSupportedPlatforms</key>       <array><string>$( [ "$MODE" = device ] && echo iPhoneOS || echo iPhoneSimulator )</string></array>
</dict>
</plist>
PLIST

# Ad-hoc is enough for the simulator, which checks that a signature exists and
# not who made it. A device build needs a real identity: pass one in
# $STARLING_IOS_IDENTITY along with a provisioning profile in the bundle.
IDENTITY="${STARLING_IOS_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --timestamp=none \
    "$OUT/Frameworks/libswift_bridge.dylib" >/dev/null 2>&1 || true
codesign --force --sign "$IDENTITY" --timestamp=none \
    "$OUT/Frameworks/Flutter.framework" >/dev/null 2>&1 || true
codesign --force --sign "$IDENTITY" --timestamp=none "$OUT"

echo "==> $OUT"

[ "$RUN" = 1 ] || exit 0
[ "$MODE" = "sim" ] || { echo "--run drives a simulator only" >&2; exit 2; }

BUNDLE_ID="build.starling.$(echo "$NAME" | tr '[:upper:]' '[:lower:]')"
DEV="$(xcrun simctl list devices available | grep -m1 "$SIM (" | sed 's/.*(\([A-F0-9-]*\)).*/\1/')"
[ -n "$DEV" ] || { echo "error: no available simulator matching '$SIM'" >&2; exit 1; }

xcrun simctl boot "$DEV" 2>/dev/null || true
xcrun simctl bootstatus "$DEV" -b >/dev/null 2>&1 || true
open -a Simulator --args -CurrentDeviceUDID "$DEV" 2>/dev/null || true
xcrun simctl install "$DEV" "$OUT"
# SIMCTL_CHILD_* is how an env var reaches the app rather than simctl itself,
# which is how the terminal is pointed at a daemon (STARLING_TERMD_HOST/PORT).
xcrun simctl launch --console-pty "$DEV" "$BUNDLE_ID"
