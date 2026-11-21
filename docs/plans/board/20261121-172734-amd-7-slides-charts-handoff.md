# amd-7 handoff: Slides charts (2026-11-21)
- Landed: #931 (cell-range labels, inEnd stacked label). #917 (percent spacing) merged earlier.
- Chart decks vs PowerPoint (worst page): radar 1.30, pie 0.96, line 0.77, bar 0.75, scatter 0.68, tdf169781 1.71, tdf149985 1.47. Left over in them: radar category labels 1-3 pt off (top label 3.3 pt low; one example, no rule), shadows on columns, half-pixel axis text. The big-score chart decks (aascu 5864, hbcu cooper) have their worst pages in text or pictures, not charts.
- Blank PowerPoint refs: 23 of 25 genuinely empty (ours blank, 0.00); damaged-zip decks (clusterfuzz POIXSLFFuzzer, Divino_Revelado) unscoreable: exclude. lo-tdf118776 (one text run, PowerPoint blank, we draw, 0.15) not yet looked at.
- Trap: test/pptx-app-render.sh uses apps/OfficeApp/.build/release/OfficeApp unless OFFICE_APP is set; the fast build writes .build-shared/release/OfficeApp, so set OFFICE_APP or you score a stale binary.
