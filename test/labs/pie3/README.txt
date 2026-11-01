Lab pie3 -- where Word puts a data label on a 3-D pie: one model, not more fitted rules (Linux lo5, 2026-11-01, starling-bd's order).
Background: zh-27a874b7 (89.2) and zh-d62da4dd (91.0) miss only their 3-D pie labels, 1-15pt off. Our renderer has about ten
lab-fitted rules for them; lab pie3d (windows-1) gave one slice angle per share. Here the unknowns are crossed: we want ONE projection
(an ellipse with depth, tilt and rotation) that explains label positions for any share, rotation, tilt and position setting.
Each document = 12 pages, 2 charts a page, 24 charts. Each chart = one 3-D pie of TWO slices (the labelled one, share s %, and 'rest'),
no title, no legend, frame 400.6 x 216pt (5088255 x 2743200 EMU, as in zh-d62da4dd), only the first slice labelled with its unique
category name (the text 'PNNSSRRR': NN document, SS share, RRR rotY), no leader lines, no fill on the label.
Variables: share s = 8, 21, 45 (%); rotY = 0, 45, 90, ... 315 (3-D rotation about the vertical axis: with no first-slice angle in a 3-D pie
this is what turns the slices; it sets where the slice's middle stands); rotX (elevation) = 30 (documents 01-04), 15 (05-08), 45 (09-12);
label position dLblPos = bestFit, inEnd, outEnd, ctr (the four documents of each rotX, in that order). perspective 30, rAngAx 0.
Files: pie3-NN-xROTX-POS.docx. usage: build.py OUTDIR regenerates them (the charts carry literal data, no workbook; if Word refuses to
open one without its workbook, say so and we will add an embedded one).
Print each to PDF with Word for Windows, then: analyze.py PDF-or-DIR > table. Send the table (TSV, one row per chart) or just the PDFs.
Our own table, same columns: PIE3-OURS.tsv. Columns: doc, id, share, rotX, rotY, pos, label centre x,y and size w,h, the pie picture's
box x0,y0,x1,y1 (the raster Word draws, or the union of its paths), dx,dy = label centre minus that box's centre.
Most useful first: documents 01-03 (rotX 30: bestFit, inEnd, outEnd), then 05-07 (rotX 15), 09-11 (rotX 45), then the ctr ones.
Needs PyMuPDF. Also useful and cheap, if you can: the same chart with rotY 0 and rotX 30 at shares 3, 5, 12, 28, 36, 60 (bestFit and outEnd).
