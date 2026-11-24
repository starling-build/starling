# amd-6: sect5 A, correction to the earlier board note (PR 2649)

The earlier note said the chart sits 87 pt low under the table. That was wrong: I measured with the wrong program build (wordcmp without --bin uses a shared gate build, and ~/.cache/wordcmp is shared between sessions).

Right numbers (own build, variants in /data/s/amd-6/lab/sect5):
- Our floating table sits 22.5 pt (text) / 25 pt (rule) lower than Word in all four variants A, B, D, E.
- Word wraps the bullet "De los 128 alumnos" to 3 lines (line 2 stops at x 271.5, short of the table's left edge); ours keeps 2 lines. That one line (15.5) is the whole chart gap in B and E (17.8 - 2.4 = 15.4). In A the chart gap is 2.4 pt.
- Word's table top minus tblpY (17.95) lands on the top of the bullet's last line (B), or the top of the empty paragraph (A). Ours lands about one paragraph (25.4) further down.
- Open: why Word's line 2 wraps (table top rule 182.9 vs line 2 box end about 180.5), and variant C (not yet measured).
