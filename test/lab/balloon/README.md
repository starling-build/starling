# lab balloon

Question: in Word for Windows' print of delins.docx, the wrapped second line of the item "Advanced Indexing Techniques with
Apache Lucene - Michael Busch. March 25th @ 14:00" has its three margin balloons in the order Field Code Changed, Formatted,
Formatted; every other item (Apache Droids too, which also wraps) has Formatted, Formatted, Field Code Changed. Which
property of the line decides it? `gen.py OUTDIR` writes the 12 documents in `docs/` (the ov* ones make the balloon column long, so that balloons stand far below their anchors, as in delins) (see its header). Print each to PDF in
Word for Windows (page 1 is enough; one page each) and send the PDFs back as `balloon-<name>.pdf`.

Our render of w1 prints F, F, C for all three items. Things to read in each print: the order of balloons per anchor line,
and for each balloon the x where its leader meets the text (leader: 425,y -> 405,anchorY -> x).

Result of the first 8 (Windows 01QbbApP): every anchor, even the wrapped item's, prints Formatted, Formatted, Field Code Changed. So wrapping
is not it. In delins the odd group stands where the column is pushed far below its anchors (balloons 129 pt under their lines); the
ov* documents test that.
