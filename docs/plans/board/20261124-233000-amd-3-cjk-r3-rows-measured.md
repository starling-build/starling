# amd-3 2026-11-24: set rows of faces the print box lacks (PR #2589; planner spec 20261124-053241-amd-opus)
Two Excel labs (lab/cjk-rows, lab/cjk-rows2). Coded by property:
- 돋움 11: 8 dots a point (6 dots a screen pixel), gridSet in SheetPrintMetrics.
- 新細明體 12: the table's 130/43 dots per 192-dpi pixel (setScreenRow), the set height held in quarter screen pixels (50.1 -> 50.0625 -> 403 dots).
- In a scaled print (set scale below 100, no fit-to-page) the dots are round(dots100 x scale), half up (30.375 pt at 58%: 142).
Faces that are installed (Malgun 11, 游ゴシック) keep the fitted row ratio. 100% and fit-to-page prints keep the old factor (spec says the gate looks wrong for 100%: open, zh-7e25946f47 to check customHeight).
r3 sweep: 65.90 -> 67.25 (ko 59.55 -> 61.86, ja 76.07 -> 76.10, zh 73.14 -> 73.13). Worst down: ko-2e5ffc47af -6.6, zh-d1309d0d07 -5.3, ja-b2b6de54b1 -4.7, ko-c83474ffb9 -4.3.
Unit test: SheetsPrintTests.testSetRowsOfMissingCjkFacesPrintOnTheirOwnGrid (planner's 505, 501, 142 cases + 403/234/202).
