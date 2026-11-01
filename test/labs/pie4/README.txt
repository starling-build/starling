Lab pie4 (Linux lenovo-2, 2026-11-01, starling-bd's order): follows lab pie3 (wip/lab-pie3), whose answers fit the centre labels of a 3-D pie to 0.44pt with one camera (eye 4.65 radii) and left three things open.
Lab pie4: what lab pie3 could not tell (all its labels were one size, perspective 30, no explosion).
Three families of documents, each chart a 3-D pie of two slices (the labelled one, share s %, and 'rest'), no title/legend,
frame 400.6 x 216pt, rAngAx 0, only the first slice labelled with its category name, no leader lines, no fill.
  A  label SIZE      (pie4-A-<pos>.docx, pos = inEnd, outEnd, bestFit): rotX 30, perspective 30; share 21 and 45; rotY 0/90/180/270;
                     label text of 5 sizes: 'Qnnnn' + filler to 5, 7, 10, 16 characters, and a 3-line label (words).
  B  PERSPECTIVE     (pie4-B-persp.docx): dLblPos ctr; perspective 0, 30, 60, 90, 150; rotX 30; share 21 and 45; rotY 0/90/180/270.
  C  EXPLOSION       (pie4-C-expl.docx): dLblPos ctr; explosion 0, 25, 50 on the labelled slice only, and the same on both; perspective 30,
                     rotX 30; share 21 and 45; rotY 0/90/180/270.
Print each to PDF with Word for Windows, then: analyze.py PDF-or-DIR > table  (send the TSV, or just the PDFs).
usage: build.py OUTDIR
Regenerate: python3 build.py OUTDIR. PIE4-OURS.tsv is our own table (same columns), for comparing.
What each family answers: A the label-size terms of inEnd/outEnd/bestFit (the pie3 labels were all 42.8 x 12.2); B eye as a function of c:perspective (pie3 had only 30); C the explosion offset of a slice (lo-4d273731 explodes 22/25).
208 charts, 5 documents, 104 pages. Print each to PDF with Word for Windows (windows).
