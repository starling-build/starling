# Every WordArt bend, and PowerPoint's printing of each

Five decks, eight bends a slide, all forty of `a:prstTxWarp`'s presets at
their default adjust values — and `warpsN-orig.pdf`, PowerPoint's own
export of each. They exist because the .pptx corpus has only a dozen of
the forty, and a bend drawn from memory of what it looks like is a guess:
these are what `Slides/WordArt.swift` was fitted against, page 2 of each.

    warps1   Plain, Stop, Triangle, Triangle Inverted, Chevron, Chevron Inverted, Ring Inside, Ring Outside
    warps2   Arch Up, Arch Down, Circle, Button, and their four Pours
    warps3   Curve Up, Curve Down, Can Up, Can Down, Wave 1, Wave 2, Double Wave 1, Wave 4
    warps4   Inflate, Deflate, their Bottoms and Tops, Deflate-Inflate, Deflate-Inflate-Deflate
    warps5   Fade Right, Left, Up, Down, Slant Up, Down, Cascade Up, Down

Not part of `test/corpus/pptx` and not swept with it: its baselines and
counts are of decks as downloaded, against PowerPoint for Mac. To look at
one:

    OfficeApp --deck-pdf test/corpus/pptx-wordart/warps2.pptx ours.pdf
    python3 test/pdf-diff.py test/corpus/pptx-wordart/warps2-orig.pdf ours.pdf pairs 1

## Where they come from

Each is `test/corpus/pptx/decks/lo-tdf114848.pptx` (a LibreOffice test
document, MPL 2.0) with the eight WordArt shapes of its second slide
given another preset and a label; the other slides are as they were. The
PDFs are PowerPoint for Windows 16.0 (build 20430), 2026-10-12, through
`test/pptx-powerpoint-pdf.ps1` — run as a scheduled task in the desktop
session (`schtasks /create … /it /rl limited`): over SSH PowerPoint
answers "insufficient memory" to every deck.

The text of every shape is the preset's name, one line. A bend that
treats its lines differently (Button, Deflate-Inflate, Deflate-Inflate-
Deflate) is therefore seen here with one line only.
