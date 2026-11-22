# HANDOFF amd-perf: OfficeApp incremental build (first pass)
- Incremental fast build works. One-file body edit, warm scratch: SlidePainter.swift 35 s; OfficeText (RichLayout+EastAsian) 95 s; no-op 0.4-13 s. Cold 8 min on a loaded box (500 s).
- Fast-build segfault: NOT reproduced. My fresh build and lenovo-2's current scratch (both fast and plain) run decks. lenovo-2 never ran it; the report has no scratch/deck. Likely cause if it recurs: stale incremental state. Needs the original scratch + command from whoever saw it.
- Added: build-office-fast.sh now runs one deck through the new binary; a crash fails the build loudly and wipes the incremental state.
- The "-incremental ignored (requires output file map)" warning appears at link only; harmless.
- Left: type-check hot spots (-warn-long-function-bodies), splitting OfficeText; 3 before/after timings.
- UPDATE: lenovo-2's crashed binary was overwritten at 05:10 (its crash.txt has no backtrace), so no repro. Likely cause: the engine library is rebuilt in place (lenovo-2's at 03:25) and its path is baked into the link; incremental/SwiftPM do not notice an engine change, so an older scratch kept stale objects. build-office-fast.sh now stamps the engine (path, size, mtime) in the scratch and wipes object state when it differs. First build of a scratch with no stamp is not covered.
