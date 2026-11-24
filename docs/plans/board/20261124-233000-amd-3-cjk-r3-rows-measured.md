# amd-3 2026-11-24: set-row factor measured (replaces fitted 0.967, PR #2579)
Two Excel labs (lab/cjk-rows, lab/cjk-rows2, Windows print). Set rows of faces NOT installed on the print box (돋움 11 -> Malgun, 新細明體 12 -> DFKai) print at 8 dots per point x print scale: 0.96 of nominal for 돋움 11 (73.5 pt -> 588 dots at 100/90/58), ~0.9655 for 新細明體 12 (50.1 pt -> 403 dots at 100, 234 at 58, 202 at 50). Installed faces (Malgun 11, 游ゴシック) keep the fitted rowScale.
Gated by printSetScaled (non-fit prints, scale < 100). Fit-to-page and 100% prints keep the old factor (open).
r3 sweep: 65.90 -> 67.25 (ko 59.55 -> 61.86, zh 73.14 -> 73.19, ja unchanged). Worst down: ko-2e5ffc47af -6.6, ko-c83474ffb9 -4.3, .xls ko small.
Unit test: SheetsPrintTests.testSetRowsOfMissingCjkFacesPrintAtEightDotsAPoint.
Next: Meiryo UI books intro-sentence wrap and 5 pt x offset (ja-d9ac78f0cb, ja-61c6327da4); rescore on engine 1a36a4fe3c8 first.
