Lab p57 (amd-perf, for windows): zh-447f1d5c p57. Word wraps 的 off a line that fits to the hundredth.
Three docs, each = 51 copies of that paragraph's first line (real runs / 的 in its own run / one run) with jc both and the RIGHT INDENT
stepped from -30 to +20 twips (steps.txt), so the available width runs 442.2+1.5 .. 442.2-1.0 pt; the last paragraph of each is a
left-aligned natural-width copy (right indent -3000).
Please print each to PDF in Word (Windows, same 仿宋_GB2312/宋体 fonts as the source document) and send back the three PDFs.
Read-out: for each of the 51 paragraphs, does the first line end in 的 (kept) or in 码 (refused)?  Ours flips between -29 and +1 twips...
(ours keeps 的 up to right indent +0, refuses from +1).  Original doc: test/corpus/docx/docs/zh-447f1d5c...docx, Word print in word-win.

ROUND 2 (amd-perf): Word refuses from right indent 0, ours from +1. To find which property of this paragraph removes the tie tolerance
that lab tie (宋体, 19 CJK) showed, five docs b0..b4, each 13 copies of the line, right indent -6..+6 twips (steps2.txt):
b0 control (as p57-real), b1 宋体 instead of 仿宋_GB2312, b2 the three compat flags doNotWrapTextWithPunct/doNotUseEastAsianBreakRules/
useAltKinsokuLineBreakRules removed, b3 brackets 《》（） replaced by ideographs, b4 auto line spacing instead of exact 560.
Same read-out as P57-WORD.tsv (line 1 ends in 的 kept / 码 refused, per right indent).
