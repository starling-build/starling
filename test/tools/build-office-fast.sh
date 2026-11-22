#!/bin/bash
# test/tools/build-office-fast.sh [SCRATCH] — release OfficeApp without whole-module optimization.
# Cold 305 s instead of 772 s; an edit that changes OfficeText's interface 254 s instead of 586 s
# (a body-only edit is ~185 s either way). Checked on 2026-11-01 at dbee8cf1e: all 1,349 Word
# documents (756 + 593 LibreOffice) print BYTE-IDENTICAL PDFs to the default build, and the sweep
# is no slower. Slides is gated too (amd-7, 2026-11-01, tip 120672010): all 555 decks print byte-identical
# --deck-pdf output to the default build, same scores.
# BUILD_INCREMENTAL=1 adds -incremental (SwiftPM release builds are otherwise NOT incremental: all 210 files
# recompile every time). The render gate sets it for the base AND the PR build; a body edit then recompiles 1-4 files
# (42-50 s with link) instead of ~115 s; an interface change still rebuilds dependents (~4 min). Keep the scratch and
# source paths stable between builds.
# Needs STARLING_ENGINE_OUT etc. exported as in the AMD README. SCRATCH defaults to .build-shared.
# Priority (amd-perf, 2026-11-21, starling-bd): load was 470 on 192 cores, so the render gate lost the CPU to developers' builds
# and A/B runs. Everything run by hand is niced (children inherit it); a render-gate (RENDER_GATE=1) keeps normal priority.
if [ -z "${RENDER_GATE:-}" ] && [ -z "${STARLING_NICED:-}" ]; then export STARLING_NICED=1; exec nice -n 10 $(command -v ionice >/dev/null && echo ionice -c3) "$0" "$@"; fi
set -e
cd "$(dirname "$0")/../.."
SCR="${1:-$PWD/.build-shared}"
swift build ${BUILD_JOBS:+-j $BUILD_JOBS} -c release --package-path apps/OfficeApp --scratch-path "${1:-$PWD/.build-shared}" \
  --product OfficeApp -Xswiftc -no-whole-module-optimization ${BUILD_INCREMENTAL:+-Xswiftc -incremental}
# Smoke test (amd-perf, 2026-11-22): an incremental build once produced an OfficeApp that segfaulted on every deck
# while a plain build was fine. Run one small deck through the fresh binary; a crash fails the build loudly and
# removes the incremental state so the next build is clean. Skipped when no corpus deck is present.
APP="$SCR/x86_64-unknown-linux-gnu/release/OfficeApp"
SMOKE=$(ls test/corpus/pptx-wordart/*.pptx /data/corpus-cache/test/corpus/pptx-wordart/*.pptx 2>/dev/null | head -1)
if [ -n "$SMOKE" ] && [ -x "$APP" ]; then
  if ! "$APP" --deck-pdf "$SMOKE" "$(mktemp -u)".pdf >/dev/null 2>&1; then
    echo "build-office-fast: SMOKE TEST FAILED: the new OfficeApp crashes on $SMOKE. Wiping its incremental state; rebuild (a clean build is slower)." >&2
    rm -rf "$SCR"/x86_64-unknown-linux-gnu/release/OfficeApp.build "$SCR"/x86_64-unknown-linux-gnu/release/OfficeApp
    exit 1
  fi
fi
