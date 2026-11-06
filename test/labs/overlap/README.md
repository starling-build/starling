Lab for windows: two overlapping floats, both allowOverlap=1, same paragraph (A first).
12 docs in docs/: behindDoc 0/1 x wrap square/tight/none x picture/textbox.
A at column +0,+0 (200x100pt); B at +100pt,+30pt (overlaps A by 100x70pt). Page 1 of each.
Question: does Word keep B at +100pt (allowOverlap honoured) or move it clear of A?
Our rule today: an allowOverlap=1, behindDoc=0 float is not pushed; behindDoc=1 is (zh-37b6536f).
Regenerate: python3 test/labs/overlap/make.py test/labs/overlap/docs
