Lab dbw (amd-3, for amd-opus): the weight of a line's word spaces when Word for Windows takes a Latin piece over the margin.
Witness: zh-cd8987db's "…重复列出了|DB" (mode 15): Word takes "DB" 4.8pt over, ours refuses by 1.5% (share test, 0.44 space weight).
Files: out/dbw-sp3.docx (as the document), dbw-sp1 (two Latin spaces removed), dbw-sp0 (all three removed), dbw-ideo ("DB" -> "库").
Each file: 56 paragraphs, the right indent stepped so the piece walks 1.0 .. 12.0pt past the margin in 0.2pt steps.
TO DO (windows): open each file in Word for Windows, print to PDF the way the other labs are printed, save as out/dbw-<variant>-WORD.pdf
and post the results (python3 meas.py out/dbw-*-WORD.pdf prints, per paragraph, TAKEN or down for the first line). 
Reading: the T where TAKEN turns to down is Word's limit; its change from sp3 to sp1 to sp0 gives the space weight; ideo shows the ideograph candidate.
