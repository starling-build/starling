# amd-perf: OfficeText interface churn and a module split (DESIGN ONLY, nothing moved)

Status: design for starling-bd to read. No code is moved until it is approved.

## Measurements (one-file edit, incremental release build, machine load 110-290)
| edit in RichLayout+EastAsian.swift | time | files recompiled |
|---|---|---|
| body-only change | 53 s | 1 OfficeText, 0 OfficeApp |
| add one INTERNAL func | 253-290 s | 39 OfficeText + 177 OfficeApp |
| add one PUBLIC func | 291 s | 39 OfficeText + 177 OfficeApp |

- Public or internal makes no difference: any new declaration recompiles about 216 files.
- Only 12 of the 184 OfficeApp files mention RichLayout, yet 177 rebuild. So the rebuild is coarse (every file of a dependent module that imports a changed module), not needed.
- 37 of the last 120 OfficeText commits (31%) add or change a declaration, so about one in three layout commits pays about 5 minutes instead of about 1.
- Tried: swift driver's cross-module incremental flag. This toolchain's swift-build rejects it (crash, unknown argument). Dead end.

## Proposal
Split OfficeText into two modules:
1. OfficeTextCore: stable types and protocols that OfficeApp uses (document model, run and paragraph types, parser results, a small layout protocol or facade). Changes rarely.
2. OfficeTextLayout: RichLayout*, EastAsian, Span, Paint and the rest that churn. OfficeApp reaches it only through the facade, so OfficeApp rebuilds only when the facade changes.

Expected gain: a declaration change in layout code costs only the layout module (roughly 40 files, estimated 60-100 s) and no OfficeApp files. Saves about 3-4 minutes on about 1 in 3 layout commits. Body-only edits stay at about 53 s.

## Risks (this touches everyone)
1. Many internal declarations must become public, and files move. Open PRs touching OfficeText will conflict. Needs a quiet window and git mv.
2. The shipped build uses whole-module optimisation. Across a module boundary, inlining and generic specialisation are lost: layout speed could regress. Must be measured on the real release build.
3. The 12 OfficeApp files that use RichLayout need a facade; getting it wrong silently changes behaviour.
4. wasm build and the unit tests (-enable-testing) must keep working.
5. Package.swift has C++ interop and compatibility flags per module; both modules need them.

## Proof plan
- Byte-identical PDFs on the 1948-file docx/pptx list (byte.sh) against a base built from the same tip, before and after each step.
- Land in small steps: (a) move leaf types to Core, (b) add the facade, (c) move layout. Each step byte-identical and timed.
- Check runtime of a large deck render before and after (step 2 risk).

## Cheaper things to try first (no code moved)
- Drop -enable-testing in the fast build only, and see whether the dependents rebuild less.
- Find out why dependents rebuild when 165 of them never use the changed type.
