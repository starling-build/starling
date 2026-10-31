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

## Reprinting faster: one PowerPoint for several decks

`test/pptx-powerpoint-pdf.ps1` attaches to a running PowerPoint and leaves it
running, so a reprint need not restart PowerPoint between decks. Checked
2026-10-31: 22 decks (plain, "pdf repaired", multi-page and font/image-heavy,
including the 28-page and two 23-page ones) printed back to back in ONE
instance, then compared page by page at 100 dpi with the fresh-instance PDFs
here: all 22 identical, every page, same page counts. So batches of at least 22
decks per instance carry no state that changes the output. A deck that hangs
PowerPoint still needs the timeout and a kill. Time: about 7 s a deck in one
instance (the 89 s one is lo-animation-sound-external), against about 8 s a
deck in this run (it killed and restarted PowerPoint each deck, plus a 1 s
pause), so the gain is small -- most of the cost is Open and SaveAs, not the
restart.
