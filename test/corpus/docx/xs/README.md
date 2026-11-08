# xs — tier 1.5 Word gate set: fixed stratified sample of dx2, 130 documents

Two documents per language (65 languages), the two of a pair with different document types, chosen
deterministically (SHA-256 order) from dx2 minus xd, minus render problems, at most 25 pages.
BLOCKING in land.sh like xb/xa/xd (v2 and vis v2 drops). The full dx2 set is tier 2 (report only,
scored every round by test/tools/dx2-round.sh). Documents and prints are NOT in git:
$STARLING_CORPUS/staging/xs/{docs,word-win} (symlinks into staging/dx2). manifest.tsv: stem, SHA-256,
language, type, pages. Scores: scores/linux/xs.*. First-pass prints; re-seeded at the second print round.
