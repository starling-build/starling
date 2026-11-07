# Corpus census prototype (amd-opus, 2026-11-07): throwaway, not a tool

The scripts behind the numbers in docs/plans/word-corpus-curation.md. They
work, but they are rough: start from them, don't land them as they are. Run them
from the repo root. S is any scratch folder; every script reads and writes
there.

    S=/tmp/census; mkdir -p $S
    python3 test/tools/docx-features.py --out $S/f756.json
    python3 test/tools/docx-features.py --docs test/corpus/docx/lo/docs --out $S/flo.json   # lo-b35c1eb6 fails: width "612pt"
    python3 test/tools/corpus-census-proto/census.py  $S     # layer A (+ fonts): duplicates, subset drop list, witness counts -> $S/census-out.json
    python3 test/tools/corpus-census-proto/backtest.py $S    # history replay of census-out.json over committed scores/linux/{756,lo}.v2
    python3 test/tools/corpus-census-proto/textfp.py $S/text.json   # layer B tokens: punctuation/symbol/space code points, sizes
    python3 test/tools/corpus-census-proto/census2.py $S     # A + B + fonts -> census-out.json (overwrites); then backtest.py again
    python3 test/tools/corpus-census-proto/xcensus.py        # witness counts for the extra XML features (fields, kashida, bidi, ...)

Known shortcuts to fix in the real tool:
- scores come from scores/linux/*.combined (format: " 100.0%  lines a/b  pages c/d  key");
- fonts are the authored names, not mapped through word-win-font-map.tsv;
- no witness floor, no protections inside census.py (the board/canary check was done ad hoc:
  protect only docs named in entries that are NOT DONE/LANDED; a bare name grep protects 154 of 244);
- backtest counts a move at >= 0.05 points and ignores who the fix targeted (check commit subjects);
- census2.py is census.py patched by string replace (see the plan for the intended token layers);
- layer C (RuleTrace hits from docx-sweep.sh -t) is not in yet.
