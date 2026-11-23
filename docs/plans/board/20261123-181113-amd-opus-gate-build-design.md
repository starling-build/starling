# amd-opus: where the gate BUILD time goes, and what to change (DESIGN, nothing changed)

Asked by starling-bd for the user, 2026-11-23. Measured at main 9dc226d7d in my own scratch, gate flags
(-no-whole-module-optimization -incremental), -j 8, machine load 140-400 (so absolute seconds are high; compare ratios).
Raw logs: /data/s/amd-opus/gb (harness exp.sh, per-process sampler).

## What is already in place (so not proposed again)
No whole-module optimisation; -incremental; a separate scratch per side (build / basebuild); base binary cached per
(engine, sha) and shared by all runners; a prebuild per main push; a warm build of main after each gate.

## Measurements
| case | wall | what ran |
|---|---|---|
| no change | 25 s (amd-8: 5 s at -j 32) | planning only |
| body-only edit, RichLayout+Paragraph+Funcs.swift | 64 s (amd-8, Calc.swift: 49 s) | 2 OfficeText files, 0 OfficeApp |
| add ONE PRIVATE func to that file | 409 s and 439 s (two runs) | 10 OfficeText + 176-201 OfficeApp files |
| cold (amd-8, -j 32, load 397) | 541 s | 678 files |
| last 15 gate PR builds with a timing line | 13, 263-462 (12 of them), 1302, 1689 s | |

Inside the 409 s rebuild: 1,565 CPU-seconds of OfficeApp compiles; "emit module OfficeApp" one serial process, 330-368 s
in the loaded build (48 s run alone at load 158); Docx.swift 220 s, Chart.swift 180 s, PptxReader.swift 85 s, each one process.

Docx.swift (10,544 lines) compiled alone, three ways at the same time: as the gate does 235 s; without debug info 225 s;
-Onone 85 s. Type-checking its bodies is 75 s of it (one function 18 s), the optimiser about 150 s.
A 6-line file compiles in 0.9 s, so there is no fixed per-process cost worth batching (batch mode would not help).
OfficeApp emit-module alone: 48 s, of which 18 s is type-checking WordArt._paint (WordArt.swift:441 and its local
function at :602) and 1.3 s Chart.swift:4520; everything else is under 0.4 s.

## Findings
1. THE NORMAL GATE BUILD IS THE WIDE REBUILD, not the one-file case. 12 of 15 gate builds took 263-462 s; only one took
   13 s. A gate compiles the difference between its scratch's last build and (PR + current main); with about 20 merges an
   hour that difference nearly always holds a new declaration in OfficeText. (Inferred from the times; the gate's
   "compiled:" list only shows file names that happen to appear in the log, so it cannot confirm it.)
2. Why one private func rebuilds all of OfficeApp (driver's own trace, -driver-show-incremental, 201 files "Invalidated
   externally"): the driver treats the whole OfficeText module as ONE node. When its interface hash changes, every
   OfficeApp file that uses any name OfficeText provides is rebuilt, and OfficeText provides '<', '==', extensions on
   Dictionary and on Color, so that is nearly every file. Cross-module incremental is already on; no flag narrows this.
3. Once everything rebuilds, the wall time is set by a few serial steps: the two emit-module steps, then Docx.swift.
   More -j does not shorten them, and they are the steps that suffer most when the box is loaded.
4. Engine swap = cold build on every scratch (build-office-fast.sh wipes all objects when libflutter_engine.so's size
   or mtime changes). But no Swift compile reads the engine tree: every include path in the OfficeApp compile is under
   sdk/ (in git); the engine is a link input only. The wipe is wider than needed. (amd-perf's segfault after an engine
   update is real but its cause was never named: stale objects, or a scratch built against another engine PATH.)
5. The 1302 s and 1689 s builds both say "base built here" at load 177-204: a wide PR rebuild and a wide base build
   running at once (-j 30 each). I did not get the runner logs, so "engine wipe" is not confirmed for them.
6. Debug info (-g is on in the gate build) costs 4% of compile time. Not worth changing alone.

## Options, in the order I would do them
A. Split the three long files (Docx.swift 10.5k lines, Slides/Chart.swift 10k, PptxReader.swift) into files of about
   2,500 lines (extensions, pure moves). They then compile in parallel instead of 220 / 180 / 85 s each in a row.
   Expected: wide rebuild at the gate's -j 24 falls from about 300-450 s to about 150-200 s (ESTIMATE: the CPU total stays
   1,565 s; the critical path becomes emit-module plus the largest piece). Risk: conflicts with open PRs touching those
   files (do it in one quiet window, git mv style, one PR per file); private members used across the split must become
   fileprivate-free (internal). Output should be unchanged; check Word 756 + Slides byte-identical before merging.
B. Move WordArt._paint's local function/types to file scope (amd-perf did the same for OfficeText on 11-21).
   Measured gain: 18 of the 48 s of OfficeApp emit-module, on every wide rebuild. Small, safe, one file.
C. Engine stamp: key it on the engine PATH plus a hash of sdk/Sources/*Bridge*/include (the only engine-facing inputs
   to a compile), and on a .so change alone delete only the linked OfficeApp so it relinks. Keep the smoke test (it
   already wipes and fails loudly on a crashing binary). Gain: one cold build (541 s idle-ish, up to 1689 s loaded) per
   scratch per engine push becomes a relink; with 2 scratches per runner and about 3 engine pushes a day that is the
   whole fleet rebuilding cold 3 times a day, at the same moment. Risk: the unnamed segfault; the smoke test covers it.
D. Never run the base build beside the PR build. When the base is not cached, build the base FIRST (other runners
   wait on the sha lock as now), then the PR; or give the two half the jobs each. Two wide builds at once on a loaded
   box is what the 1302/1689 s runs have in common. Gain not measured.
E. OfficeText split (amd-perf's design 20261122-075714): the only thing that removes the wide rebuild itself. Finding 2
   says the facade must be narrow AND must not carry the operators and the Dictionary/Color extensions, or OfficeApp
   still rebuilds. Big refactor; do A-D first and re-measure.
F. -Onone gate binary: compile 2.8x faster on Docx.swift (85 s against 235 s), but renders slower (not measured) and
   the gate would test code the release does not ship. Not recommended unless a render-time test shows the gate total
   still falls; identical output is NOT checked.
G. Not worth doing: batch mode (0.9 s fixed cost per file); dropping -g (4%); caching PR binaries per commit (a PR's
   merge commit is new on every main move, so no hits; the base is already cached); ccache-style object reuse (a Swift
   object depends on every file of its module, so keys almost never match).

## Not explained
- "emit module OfficeApp" took 330-368 s inside the loaded -j 8 build but 48 s alone at load 158. Probably CPU
  starvation of a serial step, not proven. Worth one timing on an idle runner (amd-8).
- How often a gate really hits the wide rebuild: add the true count to the gate log (count "Compiling" lines in
  build.log, not file names) and the split of emit-module / longest compile, then findings 1 and 5 can be checked.
