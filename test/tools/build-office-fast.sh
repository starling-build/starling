#!/bin/bash
# test/tools/build-office-fast.sh [SCRATCH] — release OfficeApp without whole-module optimization.
# Cold 305 s instead of 772 s; an edit that changes OfficeText's interface 254 s instead of 586 s
# (a body-only edit is ~185 s either way). Checked on 2026-11-01 at dbee8cf1e: all 1,349 Word
# documents (756 + 593 LibreOffice) print BYTE-IDENTICAL PDFs to the default build, and the sweep
# is no slower. Slides is gated too (amd-7, 2026-11-01, tip 120672010): all 555 decks print byte-identical
# --deck-pdf output to the default build, same scores.
# Needs STARLING_ENGINE_OUT etc. exported as in the AMD README. SCRATCH defaults to .build-shared.
set -e
cd "$(dirname "$0")/../.."
exec swift build -c release --package-path apps/OfficeApp --scratch-path "${1:-$PWD/.build-shared}" \
  --product OfficeApp -Xswiftc -no-whole-module-optimization
