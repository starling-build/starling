# amd-7 Slides ja decks (20 owned) handoff 2026-11-21
Scored with test/pptx-line-match.py (PPT_REFS=pptx-full/powerpoint-win). Start: mean 86.2%.
- PR 1022: bodyPr spcFirstLastPara="1" keeps first paragraph's space before (PowerPoint prints it). mean 91.4%. 5cf98ad4 48.6->95.9, 6effb0bd 65.2->90.9, 5c600b44 74.4->94.3.
- Next PR: fullwidth forms U+FF01-FF60/FFE0-FFE6 are East Asian for face choice (a lone run "１" was measured in Latin face, 10pt too wide, wrapped 約７人に１人). mean 91.8%.
Left: 5c820695 78% (title two-line pitch PPT 52 vs ours 52.8 at 44pt MS PGothic, first line 3pt lower in PPT; p2 "予防が重要" line with many leading spaces + wrap), 054ae4d7 79.7, 505a93a9 82.3, 65a1be73 85.8 (253/317 lines: ours has fewer), 6dccea3b 89.8.
