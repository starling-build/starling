#!/usr/bin/env bash
# Fetches zlib's sources for the web build of apps that read zip files.
#
#   build/tools/fetch-zlib.sh [dir]        default apps/OfficeApp/Vendor/zlib
#
# Everywhere else CZlib is the system library. The WASI sysroot has none,
# so the web build compiles zlib itself, from the upstream tarball, into a
# SwiftPM C target the app's manifest declares under STARLING_WASM. Not
# committed (Vendor/ is ignored), like sdk/Vendor for ConPTY: the tarball is
# the source of truth, this script the recipe. zlib is the zlib license.
set -euo pipefail
VERSION="1.3.1"
SHA256="9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"
DIR="${1:-$(cd "$(dirname "$0")/../.." && pwd)/apps/OfficeApp/Vendor/zlib}"

if [ -f "$DIR/include/zlib.h" ] && [ -f "$DIR/VERSION" ] && [ "$(cat "$DIR/VERSION")" = "$VERSION" ]; then
    exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/zlib.tar.gz" "https://github.com/madler/zlib/releases/download/v$VERSION/zlib-$VERSION.tar.gz"
echo "$SHA256  $TMP/zlib.tar.gz" | shasum -a 256 -c - >/dev/null
tar -xzf "$TMP/zlib.tar.gz" -C "$TMP"
rm -rf "$DIR"
mkdir -p "$DIR/include"
# The library proper; gz*.c (file I/O) and the examples are left out.
for f in adler32 compress crc32 deflate infback inffast inflate inftrees trees uncompr zutil; do
    cp "$TMP/zlib-$VERSION/$f.c" "$DIR/"
done
cp "$TMP/zlib-$VERSION"/*.h "$DIR/"
# The public pair goes where SwiftPM looks for a C target's headers; the
# rest stay private beside the sources.
mv "$DIR/zlib.h" "$DIR/zconf.h" "$DIR/include/"
cp "$TMP/zlib-$VERSION/LICENSE" "$DIR/"
echo "$VERSION" > "$DIR/VERSION"
echo "zlib $VERSION in $DIR"
