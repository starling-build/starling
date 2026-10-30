Lab gridcells (lenovo-3, for macos): where Word for Windows places an autofit table whose tblGrid is wider or
narrower than its cells (lo tdf96749: Word centres it by the cells, 506.8pt, in a grid of 522.4pt; ours is 5.7pt left).
1. python3 test/labs/gridcells/build.py           (writes the nine documents in docx/, already committed)
2. print each document in docx/ with Word for Windows (word-win mode) into one folder DIR
3. python3 test/labs/gridcells/meas.py DIR        (per document: leftmost/rightmost rule x and the letters' x)
See build.py's header for what each g-document is and the question it asks.
