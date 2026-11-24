# amd-6 HANDOFF: 99cfc5554d6e legends (PRs #2690 grid, #2696 hatched keys)

Landed/queued: (1) wrapped Word legend rows stand as a grid of equal columns, also in a legend with a manual box (the old rule excluded boxes, so it never fired); line-series entries follow the same pitch. p3 col 2 text ends within 0.4 pt of Word. (2) Keys of pattern-filled series are hatched and outlined (sphere, openDmnd on p3/p4).
wide-ab clean both (0 up/down, 7 sets); ChartTests 42/0.
Not a bug: the "uniform 2 pt in-row text offset" is Carlito's taller line box vs Calibri; baselines agree within 0.3 pt.
Open on this doc:
- p4 single-row legend (bar key entry + line key entry, box w 0.84): Word's gap between the two entries is about 10.6 pt wider than ours (ours 10.4 pt, Word ~21 pt), block shifted 2.7 pt right of centre. p3 grid pitch is also ~3.7 pt short of Word's (118.4 vs 114.7). Both suggest the entry spacing is larger in Word than our 13.9/11.8 formula gives for line-key combo legends; one chart is not enough for a rule. Needs a lab (legend with 2 entries, bar+line, vary box width).
- p3 vertical axis title: bottom matches Word, top 0.7 pt different (size, not offset). The earlier "1.2 pt low" is not reproduced.
- Word legend key is ~1.4 pt right and 1 pt wider than ours.
