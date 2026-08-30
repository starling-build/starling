#!/usr/bin/env bash
# Starling test suite.
#
#   test/run.sh              static checks + unit tests   (~2s, no GPU)
#   test/run.sh --build      also compile every package and the .deb
#   test/run.sh --sdk        also run sdk/ tests (see the caveat below)
#   test/run.sh --functional also run the live-desktop checks
#                            (needs root and a free GPU — stop the display
#                            manager first; delegates to test/functional.sh)
#
# The default tier is the one meant to run on every change: it needs no
# compositor, no GPU and no network, and it targets the failure mode that has
# actually cost this project time — two places that must agree, silently
# disagreeing. See test/lint.py for what that means concretely.
#
# Not covered here (see the tiers in the release checklist): driving a live
# desktop, installing real vendor apps, and the VM install/login gate.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUILD=0
SDK=0
FUNCTIONAL=0
for arg in "$@"; do
    case "$arg" in
        --build)      BUILD=1 ;;
        --sdk)        SDK=1 ;;
        --functional) FUNCTIONAL=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

fails=0
step() {
    echo
    echo "── $1 ─────────────────────────────────────────────────────"
}

# The functional tier needs root (/dev/uinput), but `swift` lives in the
# invoking user's swiftly toolchain and root cannot see it — running the whole
# gate under sudo would otherwise skip every Swift step in silence, which is
# how it first reported PASS on tests that never ran.
as_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        sudo -u "$SUDO_USER" -H -- "$@"
    else
        "$@"
    fi
}

# ...and sudo does not carry the user's PATH either, so `swift` has to be
# resolved by absolute path or the Swift steps silently find nothing to run.
SWIFT="$(command -v swift 2>/dev/null || true)"
if [ -z "$SWIFT" ] && [ -n "${SUDO_USER:-}" ]; then
    SWIFT="$(eval echo "~$SUDO_USER")/.local/share/swiftly/toolchains/*/usr/bin/swift"
    SWIFT="$(ls -1 $SWIFT 2>/dev/null | head -1)"
fi
if [ -z "$SWIFT" ]; then
    echo "warning: no swift toolchain found — Swift steps will fail" >&2
    SWIFT=swift
fi
# `swiftc` sits beside `swift` in the same toolchain, and needs resolving for
# exactly the same reason: the standalone compiles below are invoked as the
# user, whose PATH sudo has already discarded.
SWIFTC="${SWIFT}c"
[ -x "$SWIFTC" ] || SWIFTC=swiftc

step "static checks"
python3 "$REPO/test/lint.py" || fails=$((fails + 1))

# The emulator core is plain C with no dependencies, so its conformance
# suite (widths, grapheme clusters, joining rules, identity queries —
# every case a once-live bug) compiles and runs in well under a second.
step "unit tests: terminal core"
CONF_BIN=$(mktemp /tmp/starling-conformance.XXXXXX)
(gcc -O1 -std=c99 -I "$REPO/sdk/Sources/CTerminalCore/include" \
     "$REPO/test/core/conformance.c" \
     "$REPO/sdk/Sources/CTerminalCore/starling_term.c" \
     -o "$CONF_BIN" && "$CONF_BIN" | tail -1 | grep -q "all passed" \
     && echo "  ✔ terminal core conformance: all passed" \
     || { "$CONF_BIN" 2>/dev/null | grep FAIL; false; }) || fails=$((fails + 1))
rm -f "$CONF_BIN"

# The layout blob's codec (docs/plans/remote-workspace.md). Compiled standalone
# the same way the core conformance suite above is, and for the same reason:
# termd stores this blob and never validates it, so nothing else can catch a
# format drift. PaneLayout.swift imports nothing but Foundation precisely so
# this can compile it without the app or the SDK.
step "unit tests: pane layout codec"
# Compiled AS THE USER: the whole script runs under sudo for the functional
# tier, and swiftc is not on root's PATH (sudo's secure_path drops the
# toolchain). With stderr suppressed below, a root run failed this step
# silently and looked like a broken codec.
LAYOUT_BIN=$(as_user mktemp /tmp/starling-layout.XXXXXX)
(as_user "$SWIFTC" -O -o "$LAYOUT_BIN" "$REPO/test/layout/layout-test.swift" \
     "$REPO/apps/TerminalApp/Sources/TerminalApp/PaneLayout.swift" 2>/dev/null \
     && "$LAYOUT_BIN" | tail -1 | grep -q "all layout checks passed" \
     && echo "  ✔ pane layout codec: all passed" \
     || { "$LAYOUT_BIN" 2>/dev/null | grep FAIL; false; }) || fails=$((fails + 1))
rm -f "$LAYOUT_BIN"

# The conformance suite above proves the GRID is right. This proves the grid
# can be SEEN: the engine has no system font fallback, so a codepoint missing
# from every loaded face paints nothing while the cell holds the right
# character and the cursor advances over it correctly. Both tests above pass
# on a terminal drawing a blank screen, and the benchmark rewards it — not
# drawing is cheaper. Two of these shipped: Roboto Mono has no box drawing at
# all, and braille (every TUI spinner) was in none of the four faces.
step "glyph coverage: what a TUI draws"
GLYPH_OUT=$(mktemp /tmp/starling-glyph.XXXXXX)
(python3 "$REPO/test/bench/glyph-gate.py" > "$GLYPH_OUT" 2>&1 \
     && echo "  ✔ every TUI drawing group resolves to a loaded face" \
     || { grep -E "GAP|FAIL|glyph-gate:" "$GLYPH_OUT" | head -5; false; }) \
     || fails=$((fails + 1))
rm -f "$GLYPH_OUT"

# The remote-session daemon (docs/plans/remote-terminal.md) is plain C too,
# and its promise — a session outlives its client, a reattach at a byte
# offset resumes exactly — is a protocol test over a unix socket, no GPU and
# no display. It is the whole feature in thirteen checks.
step "unit tests: termd (remote sessions)"
(make -s -C "$REPO/termd" >/dev/null 2>&1 \
     && python3 "$REPO/termd/test-termd.py" | tail -1 | grep -q "all termd checks passed" \
     && echo "  ✔ termd: sessions survive their client" \
     || { python3 "$REPO/termd/test-termd.py" 2>&1 | grep -E "FAIL"; false; }) \
     || fails=$((fails + 1))

# The client half of a workspace (docs/plans/remote-workspace.md), against a
# real daemon on a private socket — the test above proves termd's half over a
# socketpair, and this one is the only place the Swift framing, the child
# transport and the daemon are all made to agree at once. Compiled standalone
# like the layout codec above, which is why RemoteWorkspace.swift and
# TermdLink.swift pull in nothing but Foundation.
step "unit tests: workspaces (the client's half)"
# As the user, for the same reason as the layout codec above.
WS_DIR=$(as_user mktemp -d /tmp/starling-wstest.XXXXXX)
(as_user "$SWIFTC" -O -o "$WS_DIR/workspace-test" "$REPO/test/workspace/workspace-test.swift" \
     "$REPO/sdk/Sources/Flutter/Terminal/TermdLink.swift" \
     "$REPO/sdk/Sources/Flutter/Terminal/RemoteWorkspace.swift" \
     "$REPO/apps/TerminalApp/Sources/TerminalApp/PaneLayout.swift" 2>/dev/null \
     && STARLING_TERMD_SOCKET="$WS_DIR/sock" "$WS_DIR/workspace-test" \
            "$REPO/termd/starling-termd" | tail -1 \
            | grep -q "all workspace checks passed" \
     && echo "  ✔ workspaces: an arrangement outlives the connection that wrote it" \
     || { STARLING_TERMD_SOCKET="$WS_DIR/sock" "$WS_DIR/workspace-test" \
              "$REPO/termd/starling-termd" 2>&1 | grep -E "FAIL"; false; }) \
     || fails=$((fails + 1))
rm -rf "$WS_DIR"

step "unit tests: registry"
(cd "$REPO/registry" && as_user "$SWIFT" test 2>&1 \
    | grep -vE "libxml2.so.2: no version information" \
    | grep -E "Executed [0-9]+ tests|error:|failed") || fails=$((fails + 1))

# power/ and audio/ are swift-testing, not XCTest — pure Swift, no C++
# interop, so they dodge the sdk's swift-testing/26.04 problem described
# below.
step "unit tests: power"
(cd "$REPO/power" && as_user "$SWIFT" test 2>&1 \
    | grep -vE "libxml2.so.2: no version information" \
    | grep -E "Test run with|error:|failed") || fails=$((fails + 1))

step "unit tests: audio"
(cd "$REPO/audio" && as_user "$SWIFT" test 2>&1 \
    | grep -vE "libxml2.so.2: no version information" \
    | grep -E "Test run with|error:|failed") || fails=$((fails + 1))

# The one shared package that cannot even COMPILE off Linux: CVaapiEncoder
# includes <va/va.h>, and VA-API exists where a Linux GPU stack does. Guarded
# on the header the way the clipboard bridge below is, and for the same
# reason — a suite that reports FAIL for a dependency the platform does not
# have is a suite people learn to read past, and the next real failure goes
# with it. The build tier (--build) is where a Linux box proves it compiles.
step "unit tests: record"
if [ -f /usr/include/va/va.h ]; then
    (cd "$REPO/record" && as_user "$SWIFT" test 2>&1 \
        | grep -vE "libxml2.so.2: no version information" \
        | grep -E "Test run with|error:|failed") || fails=$((fails + 1))
else
    echo "  SKIPPED — no VA-API headers (apt install libva-dev)"
fi

step "unit tests: clipboard bridge"
# The bridge's bounded pipe I/O — the part that keeps a slow or wedged peer
# from turning a paste into a hang. Plain C over pipes: no compositor, no GPU,
# no display, so it belongs in this tier rather than the functional one.
# WLCLIP_TIMEOUT_MS is shortened so the deadline cases cost milliseconds.
if [ -f /usr/include/wayland-client.h ]; then
    # Traversable by the unprivileged user: this whole script runs under sudo
    # for the functional tier, so mktemp -d makes a ROOT-owned 0700 directory
    # and the `as_user` run below then fails with "command not found" — which
    # reads as a broken test rather than as a permissions problem.
    clip_dir="$(mktemp -d)"
    chmod 755 "$clip_dir"
    clip_bin="$clip_dir/clipboard_bridge_test"
    if "${CC:-cc}" -O1 -DWLCLIP_TIMEOUT_MS=150 -o "$clip_bin" \
            "$REPO/test/clipboard_bridge_test.c" \
            "$REPO/sdk/Sources/WaylandClipboardBridge/wlr-data-control-unstable-v1-protocol.c" \
            -I "$REPO/sdk/Sources/WaylandClipboardBridge" \
            -lwayland-client -lpthread 2>&1 | grep -E "error|warning: implicit"; then
        fails=$((fails + 1))          # compiler said something worth reading
    fi
    if [ -x "$clip_bin" ]; then
        as_user "$clip_bin" || fails=$((fails + 1))
    else
        echo "  did not build"; fails=$((fails + 1))
    fi
    rm -rf "$(dirname "$clip_bin")"
else
    echo "  SKIPPED — no wayland-client headers (apt install libwayland-dev)"
fi

step "xdg-open routing"
python3 "$REPO/test/xdg_open_routing.py" || fails=$((fails + 1))

step "computer use: MCP framing"
python3 "$REPO/test/computeruse/mcp_framing.py" || fails=$((fails + 1))

step "unit tests: time"
(cd "$REPO/time" && as_user "$SWIFT" test 2>&1 \
    | grep -vE "libxml2.so.2: no version information" \
    | grep -E "Test run with|error:|failed") || fails=$((fails + 1))

# sdk/'s test targets cannot be run with a plain `swift test` on Ubuntu 26.04:
# the 6.2.4 toolchain is an ubuntu24.04 build, and under C++ interop 26.04's
# libstdc++ 15 headers make Foundation's _CStdlib.h pull <cmath> textually
# against the prebuilt std module ("redefinition of 'acos'"). swift-testing
# ships as a textual .swiftinterface, so it gets recompiled in our interop
# context and hits that before reaching any of our code.
#
# The workaround — prebuild those modules outside interop, and pass the compat
# flags to every frontend invocation — now lives with the framework, in
# sdk/tools/run-tests.sh. Delegate to it rather than keeping a second copy: the
# copy that used to live here hardcoded an x86_64 triple, so on aarch64 it
# matched no interface, prebuilt nothing, and reported success.
if [ "$SDK" = 1 ]; then
    step "unit tests: sdk"
    (cd "$REPO/sdk" && as_user env SWIFT="$SWIFT" ./tools/run-tests.sh 2>&1 \
        | grep -vE "libxml2.so.2: no version information" \
        | grep -E "Test run with [0-9]+ tests|Executed [0-9]+ tests|error:|failed" \
        | tail -5) \
        || fails=$((fails + 1))
else
    step "unit tests: sdk — SKIPPED"
    echo "  run with --sdk (needs a one-off swift-testing module prebuild on 26.04)."
fi

# An app that vendors a prebuilt native library built for another architecture
# cannot link, and nothing in this repo can make it. apps/ImageViewerApp ships an
# x86-64 .deps/pdfium/lib/libpdfium.so, so on arm64 it dies with
# `cannot find -lpdfium` — ld does say "skipping incompatible" first, but that
# scrolls past and the error names a missing library rather than a wrong one.
#
# Skipped by *architecture*, not by name: there is no list of app ids here to
# drift out of step with the registry, and the moment a matching libpdfium.so is
# dropped in, the app builds again with no change to this file. Announced rather
# than silent — a package that stops being built without saying so is how you
# ship a desktop with a missing app.
#
# It has covered more than one package: host/.deps/lib/libglfw.so.3.4 is a
# committed aarch64 binary, so anything linking -lglfw was unbuildable on
# x86-64 too. Nothing here names any of them — drop in a matching library and
# the package builds again with no change to this file.
#
# The host's ELF machine word is read off /bin/true instead of mapping uname -m
# to an ELF name, so this needs no architecture table either.
elf_machine() { readelf -h "$1" 2>/dev/null | sed -n 's/^ *Machine: *//p'; }
HOST_MACHINE="$(elf_machine /bin/true)"

# Every .so a package could link against: its own vendored .deps — both the
# .deps/<name>/lib layout ImageViewerApp uses and the flatter .deps/lib one —
# plus any .deps directory its manifest names. That last case is what this
# missed once: a package can link a library out of ANOTHER package's .deps
# (host/.deps/lib holds the vendored libglfw), so looking only under
# "$1"/.deps found nothing and the intended skip became a hard build failure.
vendored_libs() {
    local pkg="$1" d
    ls "$pkg"/.deps/*/lib/*.so "$pkg"/.deps/lib/*.so 2>/dev/null
    grep -oE '"[^"]*\.deps[^"]*"' "$pkg/Package.swift" 2>/dev/null | tr -d '"' \
        | sort -u | while read -r d; do
            ls "$pkg/$d"/*.so "$pkg/$d"/lib/*.so 2>/dev/null
        done
}

# Prints "<lib> (<its arch>, host is <ours>)" and succeeds when a vendored
# library cannot be linked on this host; fails silently when all of them can.
vendored_arch_mismatch() {
    local lib m
    for lib in $(vendored_libs "$1" | sort -u); do
        [ -f "$lib" ] || continue
        m="$(elf_machine "$lib")"
        [ -n "$m" ] && [ -n "$HOST_MACHINE" ] && [ "$m" != "$HOST_MACHINE" ] && {
            printf '%s (%s, host is %s)\n' "$(basename "$lib")" "$m" "$HOST_MACHINE"
            return 0
        }
    done
    return 1
}

if [ "$BUILD" = 1 ]; then
    step "build: sdk + shell + apps"
    # Into ONE scratch tree, sdk first — build/build-all.sh explains why, and
    # it is the difference between ~3.5 min and ~19 min: sdk/ is a path
    # dependency of all twelve packages, and SwiftPM compiles one copy per
    # consuming package unless they share a scratch path.
    SCRATCH="${STARLING_SCRATCH:-$REPO/.build-shared}"
    for pkg in sdk shell apps/*/; do
        [ -f "$REPO/$pkg/Package.swift" ] || continue
        name=$(basename "$pkg")
        if mismatch=$(vendored_arch_mismatch "$REPO/$pkg"); then
            echo "  skip  $name — vendored $mismatch"
            continue
        fi
        sdk_only=""
        [ "$pkg" = sdk ] && sdk_only="--product FlutterShared"
        out=$(as_user "$SWIFT" build -c release --package-path "$REPO/$pkg" \
                      --scratch-path "$SCRATCH" $sdk_only 2>&1)
        # Every package builds on Linux, including the macOS-only ones: they
        # select a placeholder target off macOS (see apps/DSATool/Package.swift)
        # rather than failing to compile. So a build error here is a real one —
        # this used to swallow anything mentioning `no such module 'AppKit'`,
        # which would also have hidden a genuine AppKit leak into a Linux path.
        if [ $? -eq 0 ]; then
            echo "  ok    $name"
        else
            echo "  FAIL  $name"
            echo "$out" | grep -E "error:" | head -3 | sed 's/^/        /'
            fails=$((fails + 1))
        fi
    done

    step "package"
    # Packaging needs ~500 MB (a 227 MB stage, the same again as the package
    # root, then the .deb). /tmp is a tmpfs here and is mounted with usrquota, so
    # on a box where it is small or the user is near their quota this step fails
    # with EDQUOT no matter what the code does. Point it somewhere else rather
    # than lose the release gate to the environment.
    PKG_OUT="${STARLING_PKG_OUT:-/tmp/starling-test-pkg}"
    pkg_err=$(as_user "$REPO/build/package-desktop.sh" "$PKG_OUT" 2>&1 >/dev/null) \
        && pkg_ok=1 || pkg_ok=0
    if [ "$pkg_ok" = 1 ]; then
        echo "  ok    .deb builds"
    else
        echo "  FAIL  .deb"
        # Surfaced, not swallowed: this used to redirect stderr to /dev/null, so
        # a disk-quota failure and a genuine packaging bug looked identical.
        echo "$pkg_err" | grep -E "error|Error|No such file|quota" | head -3 \
            | sed 's/^/        /'
        fails=$((fails + 1))
    fi
fi

if [ "$FUNCTIONAL" = 1 ]; then
    step "functional (live desktop)"
    if [ "$(id -u)" -ne 0 ]; then
        echo "  needs root for /dev/uinput — re-run with sudo"
        fails=$((fails + 1))
    else
        "$REPO/test/functional.sh" || fails=$((fails + 1))
    fi
fi

echo
if [ "$fails" -eq 0 ]; then
    echo "PASS"
    exit 0
fi
echo "FAIL — $fails step(s)"
exit 1
