# amd-3: print-grid wrap rule closed, not landed (2026-11-23)

HANDOFF. The float-tie fix (#2037) is the whole gain. The print-grid fit (wrap on the 600-dpi dot grid) adds nothing on top of it.

Margin windows from Excel prints (dots, fractional ppem = size x 600/72 x scale, room = floor(column dots - M)):
100% 24.5-27.5 (52716 column of 500 dots: M <= 26, since "e@yahoo.de" 474 fits); 81% 19.5-22; 66% (16.56, 17.56]; 50% 13-13.75.
All fit M = 26 x scale (about 8.1 screen px x scale). With it 52716 stays 99.0 and CVLKRA's painted lines match Excel.

Why it is not landed: with M = 26 x scale CVLKRA fell 94.7 to 73.9. Cause: rows 31, 54, 64, 75, 82, 86 of the KYC sheet (all in the 105 px column) got one line less than Excel's row height, while the painted lines match. Excel's ROW HEIGHT there follows the screen-grid fit (old rule), only the printed breaks follow the print grid (e.g. "DETAILS" 199 dots fits the print room, but the row is still 6 lines).
Taking the taller of the two row fits restores CVLKRA 94.7, 52716 99.0, LIBRE 90.3, but the 88-book mean is 93.56 vs 93.58 base and patriarch drops 99.5 to 97.4. No net gain, so nothing landed.
Open: painted line breaks of a wrapped cell could follow the print grid while the row height stays screen-fit (paint path not touched). Patch: /data/s/amd-3/sh/printgrid3-hyb.patch (env-read debug, not landable as is).
