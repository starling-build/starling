Lab p3pv (amd-2 for windows): where a 3-D WordArt word pivots as its depth grows (Wordart3D's "a third of the depth" fit rests on one deck).
Please print P.pptx (generate: python3 test/labs/p3pv/gen.py test/labs/p3pv/in; already in test/labs/p3pv/in/) to PDF (Print to PDF, one page per slide) AND export each slide as a PNG at 2400x1350 named P-NNN.png; commit PDF + PNGs under test/labs/p3pv/prints/, branch wip/lab-p3pv-prints.
Questions: (1) word at extrusionH 0/9/18/36/72 under lat 20 lon 330: how far the front face moves as depth grows (pivot at front, middle or back); (2) six cameras at depth 36; (3) the same for a plain rectangle (control); (4) a 1 pt contour.
Cells are read row-major, three to a row. The word is Arial bold 66 pt, no shape fill, 3-D inside bodyPr with textPlain warp.
