# amd-7: Slides chart labels from cells (lo-tdf149985)
- Blank PowerPoint references: 23 of 25 are really empty slides (we are blank too, 0.00); the damaged-zip decks (clusterfuzz POIXSLFFuzzer, Divino_Revelado) are unscoreable. Reported to starling-bd.
- Fixed: a series that shows labels only through "value from cells" (showVal 0, c15 range) drew nothing; now drawn. A slide's stacked column label at "inEnd" stands 1.0125 x size under its segment top (PowerPoint print: baseline 16.3 pt under at 12 pt, 2 columns agree to 0.05 pt). One deck has this; size scaling is assumed, not measured.
- Sweep 0.7282 to 0.7281, one deck changes (tdf149985 1.50 to 1.47), ChartTests 28 pass.
- Left in tdf149985: column shadows and the $1.4B ellipse (raster-vs-vector look). Other chart decks (radar, pie, line, bar, scatter 0.7-1.3) differ by label/axis half-pixels; aascu 5864 worst pages are text, not charts.
