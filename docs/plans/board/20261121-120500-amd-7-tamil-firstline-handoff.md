# HANDOFF amd-7 2026-11-21: Tamil first-line baseline (PR 777, merged)

Landed: a first line of Tamil letters now stands on Nirmala UI's 1.079 em ascent. Cause: `_indicFirstLineAscent` (RichLayout+Paragraph.swift) tested `Self._indic`, which leaves out Tamil (0B80-0BFF); now `Self._isIndic`.
Numbers (mean |dy| before to after): xd 6dd1ef35 1.02 to 0.25 (53 to 56 of 202 lines); dx2 2dabcb04 1.26 to 0.11, 31287591 1.15 to 0.10, 407581a4 1.51 to 0.12, f896e232 2.01 to 0.61. Hindi 02bdf459, 28c56054, Tamil c016493b unchanged.
Trap: the per-span ascentOverride (even x1.3) does NOT move a first line's baseline; the paragraph-level `target` logic in RichLayout+Paragraph.swift (~3255) decides it. Check there first.
Left: 6dd1ef35 still 146 lines missing (text differs / widths: dwid -12 on lines 1-2, Tamil pair widths); Malayalam 37abe13a and Sinhala 827a8947 are -2.8 / +4.6 pt off (same family, not touched); f896e232 mean dy 0.61; c016493b 6 of 421.
Not started from the brief: #614/#678, #626, #649, #666/#673, #692, #694, #756 widths/footer tab.
