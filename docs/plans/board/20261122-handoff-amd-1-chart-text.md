# amd-1 HANDOFF: East Asian chart text (2026-11-22)

Landed / open:
- PR #1287 (open, auto-merge on): slide bar-chart category names wrap by the room left of a placed plot, or up to half the area when the layout is automatic. ja 805ac359 p10 names on one line (99.4 to 100), 7d329933 92.0 to 93.4, bab9be95 93.0 to 93.7; 81d28d42, ko-e114b968 and 24 other chart decks unchanged or up.

Left (ko/ab1bf295 p6 plot gap), measured against the print:
- Plot top is 5.8 pt too high, bottom 4.4 pt too low, left edge 4.5 pt too far left (label gap 12.2 in print vs about 8.5 ours).
- amd-3's Malgun patch (/data/s/amd-3/w1/malgun-wip.patch: Hangul 1.0 em, line 1.329 em) is not enough alone; matched lines do not rise.
- It is a column chart, auto layout, legend at foot. The plot rules are in Chart.swift near the non-horizontal branch ("left = ... 11.1 * k", "bottom = ... tallest + 7.6 * k"), so the gaps there are Latin-calibrated and need a Malgun line-height share.
- Only one witness template so far; ko-110d1602 p6 is a second (print baseline 434, patched ours 434 but its title moved).
- Next: ko-e114b968 p23, then ko/c03ed80e, then rank East Asian chart pages. ko-5d22ca73 (picture deck) still open.
