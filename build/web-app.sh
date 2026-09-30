#!/usr/bin/env bash
# Build a Starling app for the browser and assemble the page that runs it.
#
#   build/web-app.sh [target] [--serve] [--debug] [--no-build]
#
# Default target: Pixels (web/Sources/Pixels), milestone 0 of
# docs/plans/wasm.md.
#
# This is stage.sh's counterpart for the web, and for ios-app.sh's reason: the
# thing cannot run out of .build. A .wasm is not a page — it needs the module
# that renders for it, the JavaScript that introduces the two, and the fonts,
# all reachable over HTTP from one directory:
#
#   .stage-web/
#     index.html  starling.js     web/host/, verbatim
#     app.wasm                    the Swift module
#     skwasm/skwasm.{js,wasm}     Flutter's renderer, fetched prebuilt
#     fonts/                      skwasm cannot see system fonts
#
# skwasm is fetched rather than built. Google publishes it per engine commit,
# and the one taken is the upstream commit our engine fork branched from, so
# the binary matches the sources in engine/src/flutter/lib/web_ui/skwasm —
# which is where web/Sources/CSkwasm/include/skwasm.h's signatures come from.
# Building it ourselves needs emsdk (`download_emsdk` in .gclient) and is only
# worth it once we change that C++.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="Pixels"
CONFIG="release"
SERVE=0
BUILD=1
PORT="${STARLING_WEB_PORT:-8137}"

# The flutter/flutter commit starling-engine's `starling` branch forked from:
#   git -C engine merge-base origin/starling <any upstream branch>
SKWASM_REV="${STARLING_SKWASM_REV:-df87ee3db00df61d882f99e655a3dc5f8387f806}"

while [ $# -gt 0 ]; do
    case "$1" in
        --serve)    SERVE=1 ;;
        --debug)    CONFIG="debug" ;;
        --no-build) BUILD=0 ;;
        -*)         echo "unknown option: $1" >&2; exit 2 ;;
        *)          TARGET="$1" ;;
    esac
    shift
done

# The Swift SDK must match the compiler exactly, so derive its name from the
# compiler rather than naming a version here.
SWIFT_TAG="$(swift --version 2>&1 | sed -nE 's/.*\((swift-[0-9.]+-RELEASE)\).*/\1/p' | head -1)"
SWIFT_SDK="${STARLING_WASM_SDK:-${SWIFT_TAG}_wasm}"
if ! swift sdk list 2>/dev/null | grep -qx "$SWIFT_SDK"; then
    VERSION="${SWIFT_TAG#swift-}"; VERSION="${VERSION%-RELEASE}"
    cat >&2 <<EOF
error: Swift SDK '$SWIFT_SDK' is not installed.

  curl -LO https://download.swift.org/swift-$VERSION-release/wasm-sdk/$SWIFT_TAG/${SWIFT_TAG}_wasm.artifactbundle.tar.gz
  swift sdk install ${SWIFT_TAG}_wasm.artifactbundle.tar.gz \\
      --checksum \$(swift package compute-checksum ${SWIFT_TAG}_wasm.artifactbundle.tar.gz)
EOF
    exit 1
fi

SCRATCH="$REPO/web/.build"
STAGE="$REPO/.stage-web"

if [ "$BUILD" = 1 ]; then
    swift build --package-path "$REPO/web" --scratch-path "$SCRATCH" \
        --swift-sdk "$SWIFT_SDK" -c "$CONFIG" --product "$TARGET"
fi

WASM="$SCRATCH/$CONFIG/$TARGET.wasm"
[ -f "$WASM" ] || { echo "error: $WASM was not built" >&2; exit 1; }

mkdir -p "$STAGE/skwasm" "$STAGE/fonts"
install -m 644 "$REPO/web/host/index.html" "$REPO/web/host/starling.js" "$STAGE/"
install -m 644 "$WASM" "$STAGE/app.wasm"
install -m 644 "$REPO/sdk/Sources/Flutter/Terminal/Fonts/DejaVuSans.ttf" "$STAGE/fonts/"

# Keyed by revision, so changing SKWASM_REV refetches and nothing else does.
CACHE="$REPO/web/.skwasm/$SKWASM_REV"
if [ ! -s "$CACHE/skwasm.wasm" ] || [ ! -s "$CACHE/skwasm.js" ]; then
    mkdir -p "$CACHE"
    for f in skwasm.js skwasm.wasm; do
        curl -fsSL -o "$CACHE/$f" \
            "https://www.gstatic.com/flutter-canvaskit/$SKWASM_REV/$f"
    done
fi
install -m 644 "$CACHE/skwasm.js" "$CACHE/skwasm.wasm" "$STAGE/skwasm/"

echo "staged  $STAGE"
echo "  app.wasm     $(wc -c < "$STAGE/app.wasm" | tr -d ' ') bytes ($CONFIG, $SWIFT_SDK)"
echo "  skwasm.wasm  $(wc -c < "$STAGE/skwasm/skwasm.wasm" | tr -d ' ') bytes (${SKWASM_REV:0:11})"

if [ "$SERVE" = 1 ]; then
    echo "serving http://localhost:$PORT/  (ctrl-c to stop)"
    # Python's server has known .wasm as application/wasm since 3.8, which
    # compileStreaming insists on.
    exec python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$STAGE"
fi
