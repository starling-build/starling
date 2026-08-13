#!/usr/bin/env bash
# Build the desktop — sdk first, then everything that consumes it — into ONE
# shared scratch directory.
#
#   build/build-all.sh [--config release|debug] [--no-apps] [--apps "A B"]
#
# WHY ONE SCRATCH DIRECTORY
#
# sdk/ is a path dependency of all twelve packages here: the shell and every
# app. SwiftPM compiles a path dependency separately for each package that
# consumes it, into that package's own .build — so built the ordinary way, one
# `swift build` per package, this tree ends up holding TWELVE copies of the
# framework. Eleven are thrown away, and stage.sh has to pick one.
#
# That is not only waste, it is a bug factory. The staged copy was the shell's,
# so an sdk/ change reached whichever app you rebuilt and NOT the framework
# that app loads at runtime — and when the change was to the body of an
# existing function rather than to the API, nothing failed anywhere. The fix
# simply did not appear on screen. Three sessions went to that.
#
# `--scratch-path` makes SwiftPM build the sdk targets once and every other
# package reuse them. Measured on this box, release, from cold:
#
#     one .build per package            shared scratch path
#     ------------------------          -------------------
#     framework, 12x     ~19 min        sdk (framework)      135 s
#     (~100 s per app)                  shell                 38 s
#                                       ten apps          1-7 s each
#                                       ------------------------
#                                       total              ~3.5 min
#
# and exactly ONE libFlutterShared.so exists afterwards, so "which copy is the
# real one" stops being a question anyone can get wrong. Verified: no package
# relinks the framework after sdk/ builds it, and re-running the shell after
# all ten apps is a 1.6 s no-op — they agree on flags rather than thrashing.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${STARLING_SCRATCH:-$REPO/.build-shared}"
CONFIG=release
APPS=""
DO_APPS=1

while [ $# -gt 0 ]; do
    case "$1" in
        --config) CONFIG="$2"; shift 2 ;;
        --apps)   APPS="$2"; shift 2 ;;
        --no-apps) DO_APPS=0; shift ;;
        -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
        *) echo "build-all: unknown option $1" >&2; exit 2 ;;
    esac
done

SWIFT="${SWIFT:-swift}"
command -v "$SWIFT" >/dev/null 2>&1 || {
    echo "build-all: no swift on PATH" >&2; exit 1; }

build() {   # build <label> <package-path> [extra args...]
    local label="$1" path="$2"; shift 2
    printf '  %-18s' "$label"
    local start=$SECONDS out
    if out=$("$SWIFT" build -c "$CONFIG" --package-path "$path" \
                      --scratch-path "$SCRATCH" "$@" 2>&1); then
        printf '%4ss\n' "$((SECONDS - start))"
    else
        printf 'FAILED\n'
        # Only the errors: a full SwiftPM log buries them under the -pthread
        # warnings every package in this tree emits.
        echo "$out" | grep -E "error:" | head -5 | sed 's/^/      /'
        return 1
    fi
}

echo "building into $SCRATCH ($CONFIG)"

# sdk first, and explicitly, so the framework has one build and one place to
# fail. Everything below reuses these targets rather than recompiling them.
build "sdk" "$REPO/sdk" --product FlutterShared
build "shell" "$REPO/shell"

if [ "$DO_APPS" = 1 ]; then
    if [ -z "$APPS" ]; then
        for d in "$REPO"/apps/*/; do
            [ -f "$d/Package.swift" ] && APPS="$APPS $(basename "$d")"
        done
    fi
    fails=0
    for a in $APPS; do
        build "$a" "$REPO/apps/$a" || fails=$((fails + 1))
    done
    [ "$fails" -eq 0 ] || { echo "build-all: $fails package(s) failed" >&2; exit 1; }
fi

echo "  one framework: $(find "$SCRATCH" -name libFlutterShared.so | wc -l)"
