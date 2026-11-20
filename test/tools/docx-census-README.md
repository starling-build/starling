# docx-census.py

Feature census and dedupe report over the Word corpus (756 + LO). Removes nothing.

    python3 test/tools/docx-census.py OUTDIR [--trace T.tsv] [--no-history] [--body-protect all|none]
                                      [--stage NAME=DIR ...]

Outputs: dedupe.tsv, report.md, census.json; with --stage also stage.tsv, stage.json.
Report from the last run: docs/plans/word-corpus-dedupe.md. Layer C (rules reached) needs a
`docx-sweep.sh -t` trace via --trace; none was available at the first run.

## Traps
- docx-features.py's multiprocessing pool cannot be unpickled when the file is loaded with importlib: load it with jobs=1.
- docProps/app.xml page counts are unreliable (80 documents read 0): take page budgets from the batch manifests (pages_est / pages_ours).
- A board-only commit that names a document is not a fix aimed at it: the replay's "aimed" test uses only non-board commit messages.
