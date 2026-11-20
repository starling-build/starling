# xb — interim Word gate set (batch B, admitted, printed): 188 documents

The admitted batch-B documents (docs/plans/word-corpus-stage.tsv: every row except "NOT ADMIT", i.e. "admit" and
"redundant, kept") that have a Windows Word print: 188 (191 admitted, less docx-ab94b38c and kor-z23967513, removed
for length, and jpn-z19987559-2cbb2b, which Word cannot open). Scored by docx-pair.sh / land.sh like 756 and lo (v2, v1, combined/vis) and BLOCKING on
v2 drops: it is the gate that sees RTL, Indic, ja/ko and Greek text. It joins the corpus swap later.

The documents and prints are NOT in git. They sit in the cache, `$STARLING_CORPUS/staging/xb/{docs,word-win}`
(default /data/corpus-cache; symlinks into staging/new-b). `manifest.tsv` lists each stem and the document's
SHA-256; check with `test/tools/corpus-cache.sh check xb` (`STARLING_MANIFESTS=test/corpus/docx`).
Scores: test/corpus/docx/scores/linux/xb.{v2,v1,vis,combined}.
