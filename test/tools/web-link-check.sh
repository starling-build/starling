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
# Exit 0 = both clean. Exit 1 = a lint hit or a NEW build/link error (the log is printed, tailed).
#   A build failure that BASE_REF itself has too (same error lines) is only warned about (exit 0), so a
#   broken tip does not block every landing for an error that is not theirs. The base's result is cached per
#   sha in $WEB_BASE_CACHE (default /data/landlock/webbase), so the base is built once; it is built in a
#   worktree at $WEB_BASE_DIR (default $ROOT/.webbase).
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
build_in() {   # build_in DIR LOG: wasm build+link of DIR's OfficeApp; prints the error signature on failure
  local d=$1 log=$2
  [ -f "$d/apps/OfficeApp/Sources/CZlib/shim.h" ] && (cd "$d" && build/tools/fetch-zlib.sh apps/OfficeApp/Vendor/zlib >/dev/null 2>&1)
  (cd "$d" && STARLING_WASM=1 STARLING_WASM_RICHTEXT=1 swift build --package-path apps/OfficeApp --scratch-path "$d/.build-web-OfficeApp" \
     --swift-sdk "${STARLING_WASM_SDK:-${SDKTAG}_wasm}" -c release --product OfficeApp) > "$log" 2>&1
}
sig_of() { grep -aE "error:|undefined symbol" "$1" | sed -E 's#/[^ ]*\.build-web-OfficeApp/##; s#^[^ ]*/(apps|sdk)/#\1/#' | cut -c1-200 | sort -u; }
LOG=${WEB_LINK_LOG:-$ROOT/.build-web-OfficeApp.log}
if build_in "$ROOT" "$LOG"; then
  echo "[web-link-check] wasm build and link OK"; exit $rc
fi
echo "[web-link-check] WASM BUILD/LINK FAILED ($LOG):"; grep -aE "error:|undefined symbol" "$LOG" | head -8 | cut -c1-220
# is the failure the base's own? (cached per base sha; built once, in a worktree)
CACHE=${WEB_BASE_CACHE:-/data/landlock/webbase}; mkdir -p "$CACHE" 2>/dev/null
BSHA=$(git rev-parse "$BASE" 2>/dev/null) || { rc=1; exit $rc; }
(
  flock 9
  if [ ! -f "$CACHE/$BSHA.sig" ]; then
    BD=${WEB_BASE_DIR:-$ROOT/.webbase}
    if [ -d "$BD" ]; then git -C "$BD" checkout -q -f --detach "$BSHA"; else git worktree add -q -f --detach "$BD" "$BSHA"; fi
    echo "[web-link-check] building the base $BSHA once, to see whether this failure is its own (cached)..." >&2
    if build_in "$BD" "$LOG.base"; then : > "$CACHE/$BSHA.sig.tmp"; else sig_of "$LOG.base" > "$CACHE/$BSHA.sig.tmp"; [ -s "$CACHE/$BSHA.sig.tmp" ] || echo "unreadable-failure" > "$CACHE/$BSHA.sig.tmp"; fi
    mv "$CACHE/$BSHA.sig.tmp" "$CACHE/$BSHA.sig"
  fi
) 9> "$CACHE/$BSHA.lock"
NEW=$(sig_of "$LOG" | grep -vxFf "$CACHE/$BSHA.sig" 2>/dev/null)
if [ ! -s "$CACHE/$BSHA.sig" ]; then
  echo "[web-link-check] the base $BSHA builds and links: this failure is NEW"; rc=1
elif [ -n "$NEW" ]; then
  echo "[web-link-check] the base also fails, but these errors are NEW:"; echo "$NEW" | head -6 | cut -c1-220; rc=1
else
  echo "[web-link-check] WARNING: the base $BSHA fails the wasm link with the same error(s); not this landing's. Not blocking."
fi
exit $rc
