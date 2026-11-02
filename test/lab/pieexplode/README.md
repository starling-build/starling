# lab pieexplode — a 3-D pie's pulled-out slices (amd-1 → windows)

16 docs, all lo-4d273731's chart (3-D pie, 56% / 44%, rotX 30, rotY 317, inner plot layout, manual label moves kept, legend right)
with only the pull (`c:explosion`) and the perspective changed. `gen.py SRC.docx OUTDIR` regenerates them.

    pie-<perspective 30|90>-<one|all>-<pull 0|10|25|50>.docx

- `one`: the pull on the 44% slice only (point 1); `all`: the same pull on the series and on both points.
- Print each with Word for Windows (PDF, 1 page each, as the pielabel labs).

## What I need from the print
The pie is a raster in the PDF, so measure its pixels (render at 4x, take the bounding box of non-white pixels
inside the chart frame, legend excluded): left, right, top, bottom of the whole pie (rim included), and
the same for the 44% slice alone if you can tell it apart by colour (peach). Also each of the two "56%" / "44%" label
centres from the text layer. One TSV: doc, pie L, R, T, B (pt on the page), then 56% x,y and 44% x,y.

## Why
Word's print of lo-4d273731 (pull 25, perspective 90) is 239 x 104 pt with its top 7pt under the plot's top; ours on the
camera that fits Word's 3-D boxes (perspective 90 = 1.5 radii) drew 175 x 150 and fell out of the frame. I fitted
"30 eye, flatter, higher" to that one chart. These tell whether the size follows the perspective, the pull, or
the pulled extent, so the fit becomes a rule.
