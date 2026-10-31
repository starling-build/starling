#!/usr/bin/env bash
# Build a Starling app for the browser and assemble the page that runs it.
#
#   build/web-app.sh [target] [--serve] [--debug] [--no-build] [--check]
#                    [--package DIR]
#
# Default target: CounterApp. Any executable the sdk/ manifest defines under
# STARLING_WASM works; WebPixels is milestone 0 of docs/plans/wasm.md, skwasm
# driven directly with no framework. An app package of its own (apps/*) is
# built with --package: `build/web-app.sh OfficeApp --package apps/OfficeApp`.
#
# Fonts: skwasm sees no system fonts, so every face the app draws with is
# staged into fonts/ and listed in fonts/manifest.json with its family
# name(s). The first entry is also the fallback for any family nobody
# loaded. Office document families can be deferred until first use.
# Defaults cover the framework; an app package's Resources/fonts
# is added under the families inside the files (Office's Liberation faces).
#
# This is stage.sh's counterpart for the web, and for ios-app.sh's reason: the
# thing cannot run out of .build. A .wasm is not a page — it needs the module
# that renders for it, the JavaScript that introduces the two, and the fonts,
# all reachable over HTTP from one directory:
#
#   .stage-web/                   (.stage-web-<Package> for --package)
#     index.html  starling.js     web/host/, verbatim
#     app.wasm                    the Swift module
#     skwasm/skwasm.{js,wasm}     Flutter's renderer, built from our engine
#     fonts/                      skwasm cannot see system fonts
#
# skwasm is built from starling-engine, not fetched: ours carries Starling's
# additions — PDF export (lib/web_ui/skwasm/pdf.cpp) and Word's fractional
# line heights (text/paragraph_style.cpp over patches/skia-fractional-line-
# heights.patch), without which a document's lines round to whole units and
# break pages unlike the native app. See below and docs/BUILDING.md §1.7.
#
# --check is the size gate (docs/plans/wasm-size.md): the link records why
# each archive member was pulled in, and the build FAILS if the legacy
# Foundation module or ICU is among them, or if app.wasm is over BUDGET.
# The framework's budget (CounterApp's) goes down as the plan lands and is
# never raised; OfficeApp has a ceiling of its own (see --check below).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="CounterApp"
CONFIG="release"
SERVE=0
BUILD=1
CHECK=0
PACKAGE="sdk"
# Release app.wasm, bytes, as staged (after wasm-opt when it is installed).
# History: 60 MB when the gate was added; 20.3 MB once the legacy Foundation
# module was off the link (phase 1); 11.6 MB with -Osize and wasm-opt
# (phase 2). The budget assumes wasm-opt; without it the check says so.
BUDGET=12000000
PORT="${STARLING_WEB_PORT:-8137}"

# The flutter/flutter commit starling-engine's `starling` branch forked from:
#   git -C engine merge-base origin/starling <any upstream branch>
SKWASM_REV="${STARLING_SKWASM_REV:-df87ee3db00df61d882f99e655a3dc5f8387f806}"

while [ $# -gt 0 ]; do
    case "$1" in
        --serve)    SERVE=1 ;;
        --check)    CHECK=1 ;;
        --package)  PACKAGE="$2"; shift ;;
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

# One scratch and one stage per package, so the size gate's CounterApp
# build does not overwrite a staged Office that test/office-layout.sh is
# about to drive.
SCRATCH="$REPO/.build-web"
STAGE="$REPO/.stage-web"
if [ "$PACKAGE" != sdk ]; then
    SCRATCH="$REPO/.build-web-$(basename "$PACKAGE")"
    STAGE="$REPO/.stage-web-$(basename "$PACKAGE")"
fi

# The web build of an app that reads zip files compiles zlib itself.
if [ -f "$REPO/$PACKAGE/Sources/CZlib/shim.h" ]; then
    "$REPO/build/tools/fetch-zlib.sh" "$REPO/$PACKAGE/Vendor/zlib" >/dev/null
fi

WHY="$SCRATCH/why-extract.tsv"
LINK_FLAGS=()
if [ "$CHECK" = 1 ]; then
    LINK_FLAGS=(-Xlinker "--why-extract=$WHY")
    # The record is written by the link, so make sure there is one.
    rm -f "$WHY" "$SCRATCH/$CONFIG/$TARGET.wasm"
fi
# An app package gets the whole framework; the SDK's own examples leave
# RichText/ out (sdk/Package.swift says why).
RICHTEXT=""
[ "$PACKAGE" = sdk ] || RICHTEXT=1
# Ubuntu 26.04: the toolchain's wasm-ld wants libxml2.so.2, which 26.04 no
# longer has. bootstrap.sh's compat symlink sits in the toolchain's runtime
# directory, which swift's own tools search and wasm-ld does not — so the
# link dies with "unable to execute command" and no mention of a library.
if [ "$(uname -s)" = Linux ]; then
    TOOLCHAIN_LIB="$(dirname "$(readlink -f "$(command -v swift)")")/../lib/swift/linux"
    if [ -e "$TOOLCHAIN_LIB/libxml2.so.2" ] && ! ldconfig -p | grep -q 'libxml2\.so\.2 '; then
        export LD_LIBRARY_PATH="$TOOLCHAIN_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    fi
fi
if [ "$BUILD" = 1 ]; then
    STARLING_WASM=1 STARLING_WASM_RICHTEXT="$RICHTEXT" \
        swift build --package-path "$REPO/$PACKAGE" --scratch-path "$SCRATCH" \
        --swift-sdk "$SWIFT_SDK" -c "$CONFIG" --product "$TARGET" ${LINK_FLAGS[@]+"${LINK_FLAGS[@]}"}
fi

WASM="$SCRATCH/$CONFIG/$TARGET.wasm"
[ -f "$WASM" ] || { echo "error: $WASM was not built" >&2; exit 1; }

mkdir -p "$STAGE/skwasm" "$STAGE/fonts"
install -m 644 "$REPO/web/host/index.html" "$REPO/web/host/starling.js" "$REPO/web/host/keymap.js" "$REPO/web/host/font-loader.js" "$STAGE/"
# binaryen's optimizer takes a third off Swift's output (15 MB of code to
# 9 MB in the first measurement), in ten seconds. Optional: without it the
# page is the same page, larger. `brew install binaryen` / `apt install
# binaryen`. Skipped for debug builds, which want their names and DWARF.
if [ "$CONFIG" = release ] && command -v wasm-opt >/dev/null; then
    # The features named are the ones the Swift SDK's wasm32-wasip1 target
    # emits; --strip-all removed the target_features section wasm-opt
    # would otherwise read them from.
    wasm-opt -Oz --enable-bulk-memory --enable-nontrapping-float-to-int \
        --enable-sign-ext --enable-mutable-globals --enable-reference-types \
        --enable-multivalue -o "$STAGE/app.wasm" "$WASM"
    chmod 644 "$STAGE/app.wasm"
else
    install -m 644 "$WASM" "$STAGE/app.wasm"
    [ "$CONFIG" = release ] && echo "wasm-opt not installed: app.wasm is unoptimized (brew install binaryen)"
fi
rm -f "$STAGE"/fonts/*.ttf
# The upstream Fluent font contains thousands of unused size variants. Keep
# all SDK-exposed icons in a verified subset; normal builds need no FontTools.
python3 "$REPO/build/tools/subset-web-icons.py" --check
# url=family[|family…] entries; an empty family takes the name inside the
# file. The FIRST family is the page's default: what text with no family
# gets, where a desktop would use the system UI font. Selawik is the
# Fluent style's face (metric-compatible with Segoe UI) and the desktop
# shell's, and its semibold cut is registered under the same family so
# bold text gets a real weight rather than a synthesized one. DejaVu Sans
# stays for glyph coverage — braille, box drawing, ⌘ — as it does natively:
# a trailing `!` marks a family as a glyph fallback, tried for characters
# the requested family lacks.
FONTS=(
    "$REPO/sdk/Sources/FluentSystemIcons/Resources/Selawik-Regular.ttf=Selawik"
    "$REPO/sdk/Sources/FluentSystemIcons/Resources/Selawik-Semibold.ttf=Selawik Semibold|Selawik"
    "$REPO/sdk/Sources/Flutter/Terminal/Fonts/DejaVuSans.ttf=DejaVu Sans!"
    "$REPO/sdk/Sources/CupertinoIcons/Resources/CupertinoIcons.ttf=CupertinoIcons"
    "$REPO/web/fonts/FluentSystemIcons-Regular.ttf=FluentSystemIcons"
)
if [ -d "$REPO/$PACKAGE/Sources/$TARGET/Resources/fonts" ]; then
    for f in "$REPO/$PACKAGE/Sources/$TARGET/Resources/fonts"/*.ttf "$REPO/$PACKAGE/Sources/$TARGET/Resources/fonts"/*.otf; do
        [ -e "$f" ] || continue
        family=""
        if [ "$TARGET" = OfficeApp ]; then
            # Keep the default document face eager. The paragraph builder asks
            # for the other families only when document/UI text uses them.
            case "$(basename "$f")" in
                Carlito-*) family="Carlito" ;;
                Caladea-*) family="Caladea?" ;;
                LiberationSans-*) family="Liberation Sans?" ;;
                LiberationSerif-*) family="Liberation Serif?" ;;
                LiberationMono-*) family="Liberation Mono?" ;;
                DejaVuSans-*) family="DejaVu Sans?" ;;
                # Slides' free faces (OfficeFonts.slideFaces), by weight.
                Poppins-Regular*|Poppins-Bold*|Poppins-Italic*) family="Poppins?" ;;
                Poppins-Light*) family="Poppins Light?" ;;
                Poppins-Medium*) family="Poppins Medium?" ;;
                Poppins-SemiBold*) family="Poppins SemiBold?" ;;
                Poppins-Black*) family="Poppins Black?" ;;
                WorkSans-Light*) family="Work Sans Light?" ;;
                WorkSans-Medium*) family="Work Sans Medium?" ;;
                WorkSans-*) family="Work Sans?" ;;
                LibreFranklin-Medium*) family="Libre Franklin Medium?" ;;
                LibreFranklin-*) family="Libre Franklin?" ;;
                SelawikDoc-Light*) family="Selawik Doc Light?" ;;
                SelawikDoc-Semilight*) family="Selawik Doc Semilight?" ;;
                SelawikDoc-Semibold*) family="Selawik Doc Semibold?" ;;
                SelawikDoc-*) family="Selawik Doc?" ;;
                TeXGyreCursor-*) family="TeX Gyre Cursor?" ;;
                TeXGyreAdventor-*) family="TeX Gyre Adventor?" ;;
                TeXGyrePagella-*) family="TeX Gyre Pagella?" ;;
            esac
        fi
        FONTS+=("$f=$family")
        # (Liberation Sans and Serif once more as a Word document's lines
        # take them, their line gap over the ascent: OfficeFonts.wordSans.)
        if [ "$TARGET" = OfficeApp ]; then
            case "$(basename "$f")" in
                LiberationSans-*|LiberationSerif-*)
                    word="$STAGE/fonts-word/$(basename "$f" | sed 's/^Liberation\(Sans\|Serif\)-/Liberation\1Word-/')"
                    mkdir -p "$STAGE/fonts-word"
                    python3 "$REPO/build/tools/font-gap-above.py" "$f" "$word"
                    case "$(basename "$f")" in
                        LiberationSans-*) FONTS+=("$word=Liberation Sans Word?") ;;
                        *) FONTS+=("$word=Liberation Serif Word?") ;;
                    esac ;;
            esac
        fi
    done
fi
{
    echo "["
    first=1
    for entry in "${FONTS[@]}"; do
        src="${entry%%=*}"; family="${entry#*=}"
        fallback=""
        case "$family" in *\?) family="${family%?}"; fallback=', "lazy": true' ;; esac
        case "$family" in *!) family="${family%!}"; fallback=', "fallback": true' ;; esac
        install -m 644 "$src" "$STAGE/fonts/"
        [ "$first" = 1 ] || echo ","
        first=0
        if [ -n "$family" ]; then
            printf '  {"url": "fonts/%s", "families": ["%s"]%s}' "$(basename "$src")" "${family//|/\", \"}" "$fallback"
        else
            printf '  {"url": "fonts/%s", "families": []}' "$(basename "$src")"
        fi
    done
    echo
    echo "]"
} > "$STAGE/fonts/manifest.json"

# skwasm, built from our engine (docs/BUILDING.md §1.7 has emsdk):
#     cd engine/src && ./flutter/tools/gn --wasm --runtime-mode release
#     ./flutter/third_party/gn/gn --root=. gen out/wasm_release
#     ninja -C out/wasm_release flutter_web_sdk/canvaskit/skwasm.{js,wasm}
# STARLING_SKWASM_DIR names another directory holding the pair (a worktree
# whose engine link is an iOS checkout points it at the desktop engine's).
# STARLING_SKWASM_DIR=published takes Google's prebuilt one instead: the app
# starts, but PDF export is off and lines round to whole units, so
# test/office-layout.sh fails against native — for a quick look only.
# A build of ours older than the exports this app calls is refused, not
# staged: it would load, and quietly lay text out as Google's does.
OWN="${STARLING_SKWASM_DIR:-$REPO/engine/src/out/wasm_release/flutter_web_sdk/canvaskit}"
if [ "$OWN" != published ]; then
    if [ ! -s "$OWN/skwasm.wasm" ] || [ ! -s "$OWN/skwasm.js" ]; then
        echo "no skwasm built at $OWN — build it (docs/BUILDING.md §1.7), or set STARLING_SKWASM_DIR" >&2
        exit 1
    fi
    for export in pdf_write paragraphStyle_setFractionalLineHeights textStyle_setScaleX textStyle_setBaselineShift paragraphStyle_addLineIndent textStyle_setMetricsOverride paragraph_getGlyphInkBounds; do
        grep -q "$export" "$OWN/skwasm.js" || { echo "skwasm at $OWN predates $export — rebuild it (docs/BUILDING.md §1.7)" >&2; exit 1; }
    done
    CACHE="$OWN"
    SKWASM_LABEL="skwasm built here"
else
    # Keyed by revision, so changing SKWASM_REV refetches and nothing else does.
    CACHE="$REPO/web/.skwasm/$SKWASM_REV"
    if [ ! -s "$CACHE/skwasm.wasm" ] || [ ! -s "$CACHE/skwasm.js" ]; then
        mkdir -p "$CACHE"
        for f in skwasm.js skwasm.wasm; do
            curl -fsSL -o "$CACHE/$f" \
                "https://www.gstatic.com/flutter-canvaskit/$SKWASM_REV/$f"
        done
    fi
    SKWASM_LABEL="skwasm ${SKWASM_REV:0:11}, published: no PDF export, lines rounded"
fi
install -m 644 "$CACHE/skwasm.js" "$CACHE/skwasm.wasm" "$STAGE/skwasm/"

# Precompressed, for a server that sends them (build/tools/web-serve.py
# does; so does any CDN). brotli is the one worth installing: a third
# smaller than gzip on this module. gzip is always there.
for f in "$STAGE/app.wasm" "$STAGE/skwasm/skwasm.wasm"; do
    rm -f "$f.br" "$f.gz"
    if command -v brotli >/dev/null; then brotli -q 9 -o "$f.br" "$f"; fi
    gzip -9 -k -f "$f"
done

echo "staged  $STAGE  ($CONFIG, $SWIFT_SDK; $SKWASM_LABEL)"
if [ "$CHECK" = 1 ]; then
    # A --check without a build has no fresh why-extract; say so rather
    # than pass on a stale one.
    [ -s "$WHY" ] || { echo "error: --check needs a build (drop --no-build)" >&2; exit 1; }
    # The budget is CounterApp's — the framework alone, near enough. An app
    # gets its own code on top; Office (4.4k lines, zlib) was 0.6 MB more.
    # OfficeApp is the whole suite now (Writer, Sheets, Slides, PDF export):
    # 21.3 MB on 2026-10-25, when the user accepted a bigger Office download,
    # so it has its own ceiling rather than the framework's plus 2 MB.
    case "$TARGET" in
        CounterApp) ;;
        OfficeApp) BUDGET=24000000 ;;
        *) BUDGET=$((BUDGET + 2000000)) ;;
    esac
    [ "$CONFIG" = release ] || BUDGET=$((BUDGET * 4))
    command -v wasm-opt >/dev/null || BUDGET=$((BUDGET * 2))
    python3 "$REPO/build/tools/wasm-size.py" "$STAGE/app.wasm" --why "$WHY" --budget "$BUDGET"
else
    python3 "$REPO/build/tools/wasm-size.py" "$STAGE/app.wasm"
fi
python3 "$REPO/build/tools/wasm-size.py" "$STAGE/skwasm/skwasm.wasm" | head -1
for f in "$STAGE/app.wasm.br" "$STAGE/app.wasm.gz"; do
    [ -f "$f" ] && printf "  %7.2f MB  %s\n" "$(echo "$(wc -c < "$f") / 1000000" | bc -l)" "$(basename "$f")"
done

if [ "$SERVE" = 1 ]; then
    echo "serving http://localhost:$PORT/  (ctrl-c to stop)"
    exec python3 "$REPO/build/tools/web-serve.py" "$STAGE" "$PORT"
fi
