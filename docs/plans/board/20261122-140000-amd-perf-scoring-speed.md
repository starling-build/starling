# amd-perf: scoring step and slow ko decks (2026-11-22)

Landed or open, all with identical output:
- PR 1727: pixel diff 2607 s to 427 s CPU over 676 decks (numpy started one spinning thread per core; now one). Scores byte-identical.
- PR 1730: line match digests page images once per document. Scores identical on 671 decks. Picture-heavy decks ~20% cheaper (ko-87d15438 30.9 s to 24.5 s). Whole-set gain small under load.
- Line match remaining cost is in MuPDF: text extraction ~35%, get_drawings ~20%, fz_run_page 5%. Python side is the per-glyph colour check (_one_colour) ~14%.

Slow ko decks (12-27 s render): profile is flat. Biggest single item is the engine's PDF deflate (longest_match + deflate_slow ~13%); lowering its level would change bytes, so not done. The rest is spread over Swift retain/release and string indexing (each under 4%). No byte-identical win of size found; parked.
