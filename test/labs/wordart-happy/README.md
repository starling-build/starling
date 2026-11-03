# wordart-happy — two-line WordArt, warped and not (owner: lenovo-3, WordArt placement)

Question: the bitmap deck's "Happy / Birthday" (Arial Black 14 pt, textDeflateInflate adj 24108)
drifts 1-2.5 pt per letter from PowerPoint. Is that the warp's mapping, or plain glyph placement?

`wordart-happy-lab.pptx` (22 slides, made by `gen.py`; slide names in `slides.txt`): each has one red
hairline box 330x250 pt holding "Happy" / "Birthday" (one paragraph each), Arial Black.
- 1-2: 14 pt, warped (textDeflateInflate 24108) and unwarped (textNoShape).
- 3-20: 24 / 40 / 72 pt x line spacing 80 / 100 / 120 %, each warped then unwarped.
- 21-22: "Happy" alone at 40 pt, warped then unwarped (per-letter x against the two-line case).

## Windows: please
Open in PowerPoint for Windows, print to PDF, export every page as PNG at 2400x1350 (2.5 px/pt),
named `L-NNN.png`, and commit them to `test/labs/wordart-happy/prints/` on branch `wip/lab-wordart-happy`.

## Measure
Per letter x and ink top/bottom of each line, PowerPoint vs ours; unwarped pairs say whether glyph
placement alone drifts, warped pairs whether the mapping adds to it. Also amd-4's note: PowerPoint's
"Happy" arches less and its letters are a little bigger/wider than ours. Do not re-fit `linePitch`.
