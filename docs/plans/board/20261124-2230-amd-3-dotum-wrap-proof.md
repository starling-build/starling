# amd-3 — Dotum/Gulim wrapped lines: per-book proof (2026-11-24)

Change: wrapped 돋움/굴림 lines step font size + 1.2 pt (Excel print); wrapped Dotum/Gulim lines stand on the first line's baseline whatever fallback face draws them. ko-d7d378fab4 wrapped heading 82.7 to 80.3 (Excel 80.5).

Per book (changed lines vs Excel, base vs branch). Approved by starling-bd: ko-42a497609b, ko-4fb28b444b, ko-0dc128b613, ko-9b8e6da4cf, xls-0453e2c911, ko-5491765fc4.
- ko-6af1014e7e: measured in-row (gap to the row border) 115 closer, 21 farther. Its rows start 5.4 pt low on page 3 (separate gap).
- ko-5cd059ba8a, ko-3c099ac411, ko-5491765fc4: the rule adds 0.2 pt to an existing 3.5 pt error. In Excel the 돋움체 (DotumChe) cells sit 2.0 pt above the row bottom (= Dotum descent), ours 5.5.
- ko-bd08a67985: rows 4-5 pt off from Excel (row/page gap).

OPEN (after the Malgun 1.0 pt item): 돋움체/굴림체 have no metrics alias. Mapping them to dotum/gulim makes 77 lines closer but some wrapped lines jump 10 pt: needs its own look. ko-5491765fc4 page 1: 147 pieces vs 50 in Excel (rows and page breaks differ).

REVISED 2026-11-26 (amd-3): the 0.90/0.21 em Dotum/Gulim print ascent/descent is dropped. It alone caused the seven gate drops on #2724 (ko-6e04814c1a, ko-946b4369d3, ko-899b5a1ed3, ko-ddfd8fcaf3, ko-413a9bf564, ko-3e21a7574c, ko-798a51aaa6): ko-946b4369d3 p2 (Dotum 16, rows of 22, centred) was 0.0 pt from Excel on main and 3.6 pt high with it. Without it ko-d7d378fab4 keeps its gain (91.8 to 94.1). Over the 646 ko books with prints: mean 66.52 to 67.09 either way; drops 37 to 10.
Tried and not taken: later wrapped lines on the FIRST line's baseline (instead of X's): offset-free spread slightly better (2.37 to 2.35) but 20 drops and ko-d7d378fab4 back to 90.6. ko-8de89f56bd (Gulim 10 at 0.876, 3-line cells) falls 40 to 10: its lines stand 2.3-4.7 pt off Excel either way, a pre-existing single-line centre error (~2.5 pt) that base matched by luck; OPEN.

REVISED AGAIN 2026-11-26 (amd-3): a wrapped Dotum/Gulim cell's lines are placed by its FIRST line's painter (y0 and the shared baseline), not "X"'s. Placed by "X", a centred pair stood ~1.5 pt above the same cell's single line (ko-fb58b17f97: Excel 162.4/169.6 about 166.0; ours 159.8/166.9 about a single 164.8). Now 646 ko books: mean 66.52 to 66.83; offset-free spread 2.411 to 2.345 (best of the four variants tried); ko-fb58b17f97 92.1 to 94.7, ko-17d190666b, ko-4fb28b444b, ko-541b5f7dc7, ko-98c94a5974, ko-d87f0d25f0, ko-3eeec4b4ea back to base.
Drops left (all with Excel's line step now matched; an older uniform offset shows): ko-71a79aae45 50.0 to 16.7, ko-8de89f56bd 40.0 to 10.0 (Gulim centred line 2.6 pt high), ko-dad252097d 32.4 to 20.6, ko-798a51aaa6 18.4 to 8.2 (3-7 pt page offset), ko-d7dcc6aa32 39.1 to 30.4, ko-5cc3ffaf97 5.9 to 0.0 and smaller ones in books 5-14 pt off already. OPEN: the offsets themselves.
