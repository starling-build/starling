# amd-perf: OfficeText rebuild result (build task closed, no code change)

Result of design note #1482 and the follow-up probes. Nothing was moved.

- No split: the OfficeText layout module alone is 153 s of the ~253 s after one new declaration; the 177 OfficeApp files are ~100 s. A perfect split saves about 40%, and needs ~35 layout members behind a facade. Not worth the churn.
- Why 39 of 77 OfficeText files recompile: it does NOT depend on what is added. A brand-new unused enum, a free function, an internal member and a public member all recompile the same 39 files. A body-only edit recompiles 1. So the compiler's incremental logic reruns every file that is not a pure data file whenever the module's declarations change; the name added is irrelevant.
- Not skipped by naming style or placing the declaration elsewhere: no cheap fix exists. Cross-module incremental flag is rejected by this toolchain (swift-build crashes on it); the incremental trace flag prints nothing under SwiftPM.
- Practical advice: keep edits body-only where possible (about 53 s); a new declaration costs 4-5 minutes whatever it is. Batch declaration changes into one build.
- Earlier work on the build task: fast-build crash guard (engine stamp and smoke test), two slow-to-type-check expressions split (byte-identical on 1948 docs).
