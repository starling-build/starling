# amd-6: turned-name cut, planner rule (2026-11-24)

On PR #2591. The cap is the height of the turned name's box, (length + line height) x sin 45, as amd-opus's spec (20261124-095528-amd-opus-rotcap.md): plot left to Word, box <= (H - 21.7 - legend band 22.9 - title band 26.1) / 2; hand-set inner plot, box <= min((H - 21.7)/2, H - axisY - 10.2); hand-set outer plot, half its outer height.
- sa1 c11d31f3 chart 4 now keeps its 157.9 pt name whole, as Word does.
- Wide A/B (origin/main vs head, 7 sets): no drops. Unit tests: ChartTests 41, 0 failures.
- Open: 60 and 90 degree turns, title band measured once (14 pt).
- Next for amd-6: sect5 variant A (the chart is put under the floating table instead of beside it; table 22.5 pt low).
