Lab rowpitch2 (lenovo-3, for macos): the follow-up of rowpitch for CELL-level rules (lo tdf152298: 16.08 a row in Word's print).
1. python3 test/labs/rowpitch2/build.py   (writes the twelve documents in docx/, already committed)
2. print each with Word for Windows (word-win mode) into one folder DIR
3. python3 test/labs/rowpitch2/meas.py DIR   (mean pitch to 0.001pt, spread, total, first row)
