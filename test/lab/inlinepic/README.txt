Lab inlinepic (lenovo-2). Print every docs/*.docx with Word for Windows to PDF (names NAME-orig.pdf in one folder),
then:  python3 meas.py THAT_FOLDER > INLINEPIC-WORD.tsv   (needs pymupdf). Question: after each inline picture Word adds
4.5-10.7 pt before the next picture's line (ours 0); which property decides it? Variants listed in build.py's header.
