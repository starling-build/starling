# Lab: where Word puts a pie's inside labels in a big slice

24 one-pie documents (`docs/pie-<big slice degrees>-<ctr|inEnd|bestFit>-<short|long>.docx`): the large slice
spans 180, 220, 270 or 300 degrees, first slice angle 0, labels inside, 16 pt bold Times, white.
`short` shows the percent ("50%"), `long` shows the category name ("Large slice with a long name").

For the Windows session: print each to PDF with Word (no PDF into git), put the PDFs in one folder, run
`python measure.py <folder>`, and paste its output to the coordinator / amd-1. It prints the pie's centre and
radius and each label's text-box centre relative to the pie centre, in points.
Regenerate the documents: `python gen.py <lo-9fa3dedd1f1d716a.docx> docs`.
