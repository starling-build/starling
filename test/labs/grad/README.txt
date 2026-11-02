Lab grad (lenovo-2): gradient stops that sit at the SAME position, in PowerPoint for Windows.
grad-lab.pptx, one slide, 20 rectangles in a 5x4 grid, row by row; each says its number and name inside (white 10pt). Colours R=FF0000 B=0000FF G=00FF00; stop positions in percent.
L = linear, ang 0 (left to right), scaled 0.  R = radial, path circle, fillToRect centre (50/50/50/50).
1-8 two stops at one position p: p=0, 30, 50, 100 (La/Ra), colour R first then B.
9-20 three stops, two coinciding: b R0 B50 G50 | c R50 B50 G100 | d R0 B30 G30 | e R30 B30 G100 | f R0 B100 G100 | g R0 B0 G100 (each L then R).
Please print the slide to PDF as usual (the PowerPoint-for-Windows print) and push it with a PNG at 100 dpi to this branch.
Question: how does PowerPoint fill each shape? For every shape, say where the red, blue and green begin and end along the line (linear) or the radius (radial), and whether any hard edge shows.
