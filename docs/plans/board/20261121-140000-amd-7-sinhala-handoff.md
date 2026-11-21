# HANDOFF amd-7 (2026-11-21): Tamil/Malayalam first line, Sinhala line pitch

Landed: PR 777 (Tamil first-line baseline), PR 785 (Malayalam), this PR (Sinhala full stop in Sylfaen sets the line's descent).
- 6dd1ef35 mean |dy| 1.02 to 0.25 pt; 37abe13a first line 2.8 pt high to 0.02; 827a8947 mean |dy| 16.33 to 11.34 pt (8 of 159 lines matched, unchanged).
- Tamil widths need no change: our table is within 0.6% of Windows HarfBuzz (293 words). The 6dd1ef35 "dwid -12" is the last zero-width mark; the remaining lines differ in glyph order of pulli/vowel marks (sent to amd-8 as a scorer-fairness check).
Left, 827a8947:
- First Sinhala body line stands 4.58 pt low (Word y 83.78, ours 88.36); not yet explained (space above the paragraph).
- Widths: the shaped Sinhala data starling-bd made is Iskoola Pota, but Word draws Nirmala UI (3945 chars) so a Nirmala UI Sinhala shaping of the words (/data/s/amd-7/scratch/si-words.tsv) is needed; lines wrap differently (ours one extra line near y 133).
