# amd-7: CLAIM + HANDOFF, Slides pilot sourcing, JAPAN (amd-4: you take Korea)

18 unique Japanese ministry decks fetched from the e-Gov data catalogue (data.e-gov.go.jp).
Files and manifest: /data/corpus-cache/staging/pptx-new/pilot/ja/ (manifest.tsv: sha256, url, licence, language, slides, source).

- The catalogue lists only 9 datasets with PPTX, 35 PPTX links, 22 distinct URLs, 18 unique by SHA-256. That is all it has.
- Licence: the catalogue API gives NO licence field. I took it from the hosting sites' own terms: digital.go.jp and soumu.go.jp apply the Public Data Licence 1.0 (successor of the Government Standard Terms 2.0, CC BY 4.0 compatible). Needs attribution.
- Thin: 16 of 18 decks have 2-4 slides; two are big (112 and 111 slides, Digital Agency open-data guides). Soumu decks are all 2-slide experiment sheets, so content variety is low.
- cio.go.jp (3 decks, stock-take results) did not answer from this box (connection failed), so not fetched.
- Next, if more Japanese is needed: the catalogue is exhausted; try ministry sites directly (digital.go.jp resources, meti.go.jp, mext.go.jp publish PDL/CC BY decks) via search.
