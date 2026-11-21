# amd-11 HANDOFF: sa1 5e813226 p27 opener lift, labs flbare and flbare2 (2026-11-21)
Word prints (compat 15, landscape, floating TableGrid table, row 6 opens page 2):
- All cells of the opener row state top=nil (incl. the merged-down column): text sits at page top, 95.54.
- Any cell not stating nil (tops single, or a merged-down first column that states only its right edge, or no merge at all): +0.48, 96.02.
Cause in the engine: the merged-down (vMerge continuation) cell has no paragraph, so the "every cell says no top" test only saw the three restart cells and gave lift 0.
Fix: a cell merged down from above whose part of the row does not say top nil keeps the lift (_rowHasContinuedTopUnsaid; used by _pg_headLift and _rowOpensBare).
Result: flbare2 a_doc 17 to 30 of 30 lines, g_plaincol1 42 of 42; unit tests 836/0.
Left: 5e813226 p27 still 26.95 pt low in the whole doc because of the main regression amd-8 is bisecting; re-measure after it. flbare2 b/c/d/e/f stay at 20 of 30 (about 0.07 off, not touched here).
