# PowerPoint for Windows' export of the decks

NAME-orig.pdf is Microsoft PowerPoint for Windows' PDF export of
../decks/NAME.pptx, printed 2026-10-31 with `test/pptx-powerpoint-pdf.ps1`.

    PowerPoint   Microsoft 365 (O365HomePremRetail), 16.0.20527.20088
    decks        561
    printed      559 (536 ok, 23 "pdf repaired": opened through OpenAndRepair)
    failed       2 -- PowerPoint refuses them even with repair:
                 clusterfuzz-testcase-minimized-POIFuzzer-5205835528404992, keyframes

Each deck was printed alone in a fresh PowerPoint (killed before and after each
deck, under a lock, 180 s timeout); no crash or timeout occurred.
`results.tsv` has name, verdict, seconds, PDF bytes per deck. A failed deck has
no PDF here.

The Mac set in ../powerpoint/ (553 files, from PowerPoint for Mac) is separate
and unchanged.
