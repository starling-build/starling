#!/usr/bin/env bash
# Run the FlutterSwift test suite.
#
#   tools/run-tests.sh [extra swift-test args...]
#
# A plain `swift test` does not work on Ubuntu 26.04, for the same reason
# documented around `glibcMathCompat` in Package.swift: the 6.2.4 toolchain is an
# ubuntu24.04 build, and under C++ interop 26.04's libstdc++ 15 headers make
# Foundation's _CStdlib.h pull <cmath> textually against the prebuilt `std`
# module ("redefinition of 'acos'"). Two extra things are needed on top of the
# manifest's own compat flags:
#
#  1. swift-testing ships Testing, _Testing_Foundation and _TestDiscovery as
#     *textual* .swiftinterface only — XCTest, by contrast, ships a binary
#     .swiftmodule. An interface has to be recompiled in the importing target's
#     context, and ours are C++-interop, so that rebuild hits the clash before
#     ever reaching our code. Compiling them once here, outside C++ interop,
#     yields binary modules the test build consumes as-is, so no rebuild happens.
#     Unavoidable even for an all-XCTest target: SwiftPM's generated test runner
#     opens with `#if canImport(Testing) import Testing #endif`.
#
#  2. The compat flags have to reach *every* frontend invocation, not just our
#     targets. SwiftPM generates the runner and the test-discovery module itself,
#     and those carry none of a target's swiftSettings while still inheriting C++
#     interop — so the manifest's per-target settings cannot cover them. Passing
#     the flags through -Xswiftc does.
#
# Keep these flags in step with `glibcMathCompat` in Package.swift.
set -euo pipefail

SDK="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT="${SWIFT:-swift}"
PREBUILT="$SDK/.build/swift-testing-prebuilt"

COMPAT_CFLAGS=(-Xcc -D_GLIBCXX_MATH_H -Xcc -include -Xcc /usr/include/math.h)

# Only needed for the known-bad pairing the manifest gates on: libstdc++ 15+.
# Same heuristic as needsGlibcMathCompat(), same override.
needs_compat() {
    case "${FLUTTER_SWIFT_GLIBC_MATH_COMPAT:-}" in
        0) return 1 ;;
        "") ;;
        *) return 0 ;;
    esac
    [ "$(uname -s)" = Linux ] || return 1
    [ -f /usr/include/math.h ] || return 1
    local newest=0 d
    for d in /usr/include/c++/*; do
        d="$(basename "$d")"
        case "$d" in ''|*[!0-9]*) continue ;; esac
        [ "$d" -gt "$newest" ] && newest="$d"
    done
    [ "$newest" -ge 15 ]
}

# Build binary .swiftmodule files for the interface-only swift-testing modules.
# Idempotent: skipped once the cache is populated.
prebuild_swift_testing() {
    [ -f "$PREBUILT/Testing.swiftmodule" ] && return 0
    local info res triple
    info="$("${SWIFT}c" -print-target-info 2>/dev/null)"
    res="$(printf '%s' "$info" | sed -n 's/.*"runtimeResourcePath": *"\([^"]*\)".*/\1/p' | head -1)"
    # Derived, never hardcoded: the interface file is named after the triple, so a
    # wrong guess silently matches nothing and the prebuild is a no-op that only
    # shows up later as the <cmath> clash it was supposed to prevent.
    triple="$(printf '%s' "$info" | sed -n 's/.*"unversionedTriple": *"\([^"]*\)".*/\1/p' | head -1)"
    [ -n "$res" ] && [ -n "$triple" ] || {
        echo "error: could not read the Swift resource dir / target triple" >&2
        return 1
    }
    mkdir -p "$PREBUILT"
    local built=0 m iface
    # _TestDiscovery and _Testing_Foundation first: Testing imports them.
    for m in _TestDiscovery _Testing_Foundation Testing; do
        iface="$res/linux/$m.swiftmodule/$triple.swiftinterface"
        [ -f "$iface" ] || continue
        "${SWIFT}c" -frontend -compile-module-from-interface \
            -target "$triple" -module-name "$m" -I "$PREBUILT" \
            -o "$PREBUILT/$m.swiftmodule" "$iface"
        built=$((built + 1))
    done
    [ "$built" -gt 0 ] || {
        echo "error: no swift-testing interfaces found under $res/linux for $triple" >&2
        return 1
    }
    return 0
}

ARGS=()
if needs_compat; then
    prebuild_swift_testing
    ARGS+=(-Xswiftc -I -Xswiftc "$PREBUILT")
    # Each flag needs its own -Xswiftc: prefixing the array in place yields one
    # word per flag with the space embedded, which swift silently ignores.
    for f in "${COMPAT_CFLAGS[@]}"; do ARGS+=(-Xswiftc "$f"); done
fi

# ${ARGS[@]+"${ARGS[@]}"} rather than "${ARGS[@]}": on any platform that does not
# need the compat flags ARGS is empty, and bash 3.2 — which is the
# /usr/bin/env bash on macOS — treats expanding an empty array under `set -u` as
# an unbound variable and dies before running a single test. bash 4.4 and newer
# made that legal, which is why Linux never saw it.
exec "$SWIFT" test ${ARGS[@]+"${ARGS[@]}"} "$@"
