# lenovo-5: OPEN, slide 3-D bar box pad vs plot height (after PR 1724)

The pad kept inside the laid plot (2.7 pt top + 1.7 pt foot, 4.4 in all) was fitted on plot height 222.1 pt only (lab bar3d-series: 24 prints, all one height; fit pad 6.9, lab's own pads 5.4, real LIBRE_OFFICE p2-p10 want 4.4). Whether the pad is fixed or scales with the plot height is untested; one-series charts are not covered. Next step if wanted: lab with plot heights 120 / 222 / 330 pt, 3 series, gapDepth 150.
Reruns after #1573, #1624, #1687 merged: 99f6ddd1 p12 text baselines within 0.2 pt of PowerPoint (rows and names); the remaining misses are the symbol glyphs (circle, triangle) 3 to 8 pt high (lenovo-2's symbol font). tblrow2: median baseline -0.13 pt.
