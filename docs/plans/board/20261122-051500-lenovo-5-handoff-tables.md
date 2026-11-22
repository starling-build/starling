# lenovo-5 HANDOFF: Slides tables (2026-11-22)

- Themed Style 1/2 (white rule after first column, soft shadow): already in PRs #1363, #1367. #1367 blocked on lo-numfmt line score 55.6 -> 44.4; that deck has no table at all (0.13% pixels), so I believe it is noise; gate rerun requested.
- Medium Style 4 (#1381): the old captured definitions for 5 ids (Medium 4 Accent 5/6, Medium 3 Accent 1, two more) had one deck's colours baked in and no inner rules, and beat the family ones. Families now win; hand-written Medium Style 2 and the literal ones still win over families. Print: lab tstyles page 11, Accent 6 now orange with all rules.
- e89e63a8 p31: positions of the fullwidth digits match Word within 0.4 pt and wraps match; nothing left to fix there.
- Table page ranking (811 table pages, 163 decks of full + pilot + old, our pdf vs Word, MuPDF pixel diff, mean 9.4%): /data/s/lenovo-5/table-rank.tsv (score, deck stem, slide). Worst: 7f68063e p10-12 (was my Medium Style 2 regression, fixed in #1381, now 11-13%), eb107c07 p13/16/3/4, d776ec3f p26, b986e846 p2, ko-d12a6adbc p19, 65a1be73 p13, ko-e114b968 p53. Run before the Medium Style 2 fix, so decks using Medium Style 2 are overstated.
- Next: look at eb107c07 and d776ec3f pairs (pairs in /data/s/lenovo-5/tsweep/pd-<stem>/).
