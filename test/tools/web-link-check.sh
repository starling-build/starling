#!/bin/bash
# Copyright the Starling authors
# SPDX-License-Identifier: Apache-2.0
# web-link-check.sh [BASE_REF] — will this tree still BUILD AND LINK for the web (wasm)?
#
# The web build has no legacy Foundation, and a violation compiles on Linux and in the wasm
# COMPILE step, and fails only at the wasm link (undefined symbol ...Foundation...range(of:...)).
# Rounds 299-301 found one three rounds late, so land.sh runs this before it pushes anything
# that touches sdk/ or apps/OfficeApp/Sources.
#
#   1. lint (seconds): lines ADDED since BASE_REF in OfficeApp/sdk sources that use a call known to
#      need legacy Foundation: String .contains("literal") / .range(of:) / .replacingOccurrences /
#      .components(separatedBy:) / .trimmingCharacters / String(format:) / NSLock /
#      FileHandle.standardError. A hit is reported, and the build below still runs.
#   2. the same `swift build` build/web-app.sh runs for apps/OfficeApp, compile AND link, with its
#      own scratch (.build-web-OfficeApp, incremental after the first run, ~12 min cold) and nothing
#      staged. It needs the wasm Swift SDK (build/web-app.sh says how to install it).
# Exit 0 = both clean. Exit 1 = a lint hit or a build/link error (the log is printed, tailed).
# LINT_ONLY=1 stops after step 1.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd); cd "$ROOT"
BASE=${1:-origin/office}
export PATH=$HOME/.local/share/swiftly/toolchains/6.2.4/usr/bin:$PATH
rc=0

# 1. lint on added lines (a literal-argument .contains on a String resolves to Foundation's range(of:))
PAT='\.range\(of:|\.replacingOccurrences\(|\.components\(separatedBy:|\.trimmingCharacters\(|String\(format:|NSLock\(|FileHandle\.standardError|\.contains\("'
HITS=$(git diff -U0 "$BASE"...HEAD -- 'apps/OfficeApp/Sources/*.swift' 'sdk/Sources/*.swift' 2>/dev/null \
  | awk '/^\+\+\+ b\//{f=substr($0,7)} /^@@/{split($3,a,","); n=substr(a[1],2)+0; next} /^\+[^+]/{print f":"n": "substr($0,2); n++} /^\+$/{n++}' \
  | grep -E "$PAT" | grep -v -E '^[^:]*(Tests?|Native|Linux)[^:]*:' | cut -c1-200)
if [ -n "$HITS" ]; then
  echo "[web-link-check] LINT: added lines that need legacy Foundation (the wasm link will fail on them):"
  echo "$HITS" | head -20
  echo "[web-link-check] use containsSubstring()/rangeOfSubstring() (sdk helpers), OfficeLock, no String(format:)/trimmingCharacters; keep debug traces native-only"
  rc=1
fi
[ "${LINT_ONLY:-}" = 1 ] && exit $rc

# 2. build + link
SDKTAG=$(swift --version 2>&1 | sed -nE 's/.*\((swift-[0-9.]+-RELEASE)\).*/\1/p' | head -1)
swift sdk list 2>/dev/null | grep -qx "${STARLING_WASM_SDK:-${SDKTAG}_wasm}" || { echo "[web-link-check] wasm Swift SDK not installed: skipped the build (lint result only)"; exit $rc; }
if [ "$(uname -s)" = Linux ]; then
  TL="$(dirname "$(readlink -f "$(command -v swift)")")/../lib/swift/linux"
  [ -e "$TL/libxml2.so.2" ] && ! ldconfig -p | grep -q 'libxml2\.so\.2 ' && export LD_LIBRARY_PATH="$TL${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
[ -f apps/OfficeApp/Sources/CZlib/shim.h ] && build/tools/fetch-zlib.sh apps/OfficeApp/Vendor/zlib >/dev/null 2>&1
LOG=${WEB_LINK_LOG:-$ROOT/.build-web-OfficeApp.log}
if STARLING_WASM=1 STARLING_WASM_RICHTEXT=1 swift build --package-path apps/OfficeApp --scratch-path "$ROOT/.build-web-OfficeApp" \
     --swift-sdk "${STARLING_WASM_SDK:-${SDKTAG}_wasm}" -c release --product OfficeApp > "$LOG" 2>&1; then
  echo "[web-link-check] wasm build and link OK"
else
  echo "[web-link-check] WASM BUILD/LINK FAILED ($LOG):"; grep -aE "error:|undefined symbol" "$LOG" | head -8 | cut -c1-220; rc=1
fi
exit $rc
