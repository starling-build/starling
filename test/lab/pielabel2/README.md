# Lab: pielabel again, with labels of 1, 2, 3 and 5 lines

48 one-pie documents `docs/pie-<180|220|270|300>-<ctr|inEnd|bestFit>-<1|2|3|5>line.docx`: as lab pielabel, but both
slices' labels are their own rich text of N lines (Alpha, Bravo, Charlie, Delta, Echo), 16 pt bold Times, white.
Question: where does Word put the label's centre for each label height, and is it inside or outside the pie?

Print each to PDF with Word (PDFs stay out of git), then for each print report for both labels the centre of each
text line relative to the pie centre (127.8, 229.6 on the page; R 53.4), in points, +x right, +y down —
`python measure.py <folder>` of lab pielabel does this for the 270/300 pies; for 180/220 take the centre from the
two slices' bounding boxes together, as before. A label printed outside the pie is the answer too: give where.
