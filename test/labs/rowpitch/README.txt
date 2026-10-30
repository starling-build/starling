Lab rowpitch (lenovo-3, for macos): the pitch of table rows in Word for Windows — 317-twip rows with 0.25pt rules
come out 16.08pt apart in Word's print of lo tdf152298, 16.10 in ours (0.7pt over 36 rows).
1. python3 test/labs/rowpitch/build.py            (writes the nine documents in docx/, already committed)
2. print each document in docx/ with Word for Windows (word-win mode) into one folder DIR
3. python3 test/labs/rowpitch/meas.py DIR         (per document: mean pitch to 0.001pt, spread, running total)
Our own prints give 15.850 / 16.100 / 16.350 for atLeast 317 with no rule / sz 2 / sz 4, and 13.800 / 14.050 / 14.300 auto.
