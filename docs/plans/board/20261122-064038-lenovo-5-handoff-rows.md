# lenovo-5 handoff: Slides table row pitch by end mark face (2026-11-22)

d8e0c8b24e01bab038532c1879d375f8dd6100402642fd59d445eb9fd8161775 p10 21.24 to 13.58 (rows no longer 0.1 pt short).
Labs lab/tbl-rows (round 1, 2; PowerPoint prints in word-win/). Findings:
- Row pitch does not grow with row count or banding/borders; it is constant per row.
- The end-of-paragraph mark's SIZE makes no difference (10/14/20/28 pt all equal). Its FACE does: a Calibri mark under Times text at 107%+ adds 0.2 (8 pt) to 0.4 pt (18 pt), i.e. the first-line loss k takes the taller of text face and mark face (Calibri 1.2207 em gives k 0.041, others 1.149 em give 0.0717; fits all 13 lab2 pages within 0.1 pt).
- Left: Calibri TEXT rows at 100% are not measured; our engine uses 1.2 em for Calibri in cells (PowerPoint 1.2207): not touched.
- d8e0c8b2 p10 still 13.6: the rest is not row pitch (not looked at).
