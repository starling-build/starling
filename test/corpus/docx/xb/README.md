# xb — interim Word gate set (batch B, admitted, printed)

The admitted batch-B documents (docs/plans/word-corpus-stage.tsv: action "admit", printed "yes") that have a
Windows Word print. Scored by docx-pair.sh / land.sh like 756 and lo (v2, v1, combined/vis) and BLOCKING on
v2 drops: it is the gate that sees RTL, Indic, ja/ko and Greek text. It joins the corpus swap later.

The documents and prints are NOT in git. They sit in the cache, `$STARLING_CORPUS/staging/xb/{docs,word-win}`
(default /data/corpus-cache; symlinks into staging/new-b). `manifest.tsv` lists each stem and the document's
SHA-256; check with `test/tools/corpus-cache.sh check xb` (`STARLING_MANIFESTS=test/corpus/docx`).
Scores: test/corpus/docx/scores/linux/xb.{v2,v1,vis,combined}.
