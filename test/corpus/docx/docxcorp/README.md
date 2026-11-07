# docxcorp.us picks (manifest only)
The .docx files are not in git: docxcorp.us files carry no per-file licence (ODC-BY covers the collection;
each document's copyright stays with its author). `test/tools/fetch-docxcorp.sh` rebuilds the cache
(/data/docx-corpus-cache/docxcorp/<doc_id>.docx) from `manifest.tsv` and checks each file's sha256.
Groups: thin = Japanese, Korean, Hebrew, Thai, Hindi, Tamil, Bengali; seq = long English with SEQ captions.
All picks: <=40 pages in our Windows-mode render, no DATE/TIME fields, no emails/phones found.
