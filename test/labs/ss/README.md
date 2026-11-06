Lab ss (lenovo-2, 2026-11-06): why do bold spaces after a bold heading shrink in zh-6c447317?
Real paragraph "第二十七条  以上各项补贴…" (16pt TNR + eastAsia font, exact 29pt, firstLine 2 chars, justified,
text width 415.3pt, compat settings.xml present). Headings are 第<甲..壬><一..九>条: letter = variant, kanji = step.
Variants (rows of 9 paragraphs each, steps = right indent 0,0.5,..,4pt, so line 1 overhangs 0.7..4.7pt):
 A bold head + 2 bold spaces (the real case)   B all regular   C bold head, regular spaces   D regular head, bold spaces
 E one bold space   F same as A but on line 2 (22-char plain prefix)   G Latin "AB" after the spaces
 H spaces with rFonts hint=eastAsia   J body bold too
Docs: ss-c14-fs (compat 14, 仿宋_GB2312 = the real case), ss-c15-fs (compat 15), ss-c14-fangsong (仿宋),
ss-c14-simsun (宋体), ss-c14-fs-nobal (compat 14 without balanceSingleByteDoubleByteWidth).
Question: per variant and step, does Word take the 18th char "保" on line 1 (spaces shrink) and how wide are the spaces?
Please print each docx to PDF in Word and send the PDFs (or word rows).
