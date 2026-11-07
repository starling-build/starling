Fit-edge lab (lenovo-5). 20 docx, one change each, from the real paragraphs. Print each in Word (Windows), one page each.
a* = zh-6a4fc013 "回答：…" paragraph (compat 15, compressPunctuation, 16 pt). Question: is the mid-line 、 squeezed, and where does the line break
   (Word's real print breaks "…指定地點費|用、前往…"; line 2 starts 用、前往本部指定地點之交通費用、檢疫後之PCR費用及自主).
   a00 orig; a01 doNotCompress; a02 compat12; a03 、->，; a04 jc left; a05 no hanging indent; a06 shorter text; a07-a10 right margin +-20/60 twips.
b* = zh-202582e2 closing table (doNotCompress, compat 14). Question: why does Word wrap "发" of "2024 年 9 月 3  日印发" in the 3626-twip cell.
   b00 orig; b01-b04 cell width +60/-60/+200/-200; b05 no indent; b06 no run spacing; b07 compat15; b08 compressPunctuation.
Regenerate: python3 mk.py test/corpus/docx/docs <outdir>
