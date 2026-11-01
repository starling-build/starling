Lab kashida -- how Word for Windows fits Latin lines under jc mediumKashida / highKashida (starling-ios-1f, 2026-11-01).
Background: LibreOffice tdf155707 (lo-af36644e14e94c0e) has Latin paragraphs justified with jc both / lowKashida / mediumKashida /
highKashida, Calibri 11pt, A4 with 1in margins. Word's print breaks medium and high EARLIER than both and low: on the same text a
medium line holds 16 words ("This is a sample text. ... also a longlong text.") where "both" holds 19, although 17 words measure
about 450pt of 453.6. We squeeze spaces for all of justify; not squeezing for medium/high gets 42.2 -> 45.3 only.
Question: what is the line capacity under each jc, at a few widths, so the rule can be read (a minimum space? a reserve for
kashida? the squeeze of "both" present or absent?).
Documents (compat mode 15, Calibri 11pt, spacing after 8pt, one jc per page, 4 paragraphs per page):
  kash-01-sample.docx   the tdf155707 sentence x4 (has the 24-letter word)
  kash-02-words.docx    "word" x150: every word the same width, so the words-per-line is read straight off
  per page: jc = both, lowKashida, mediumKashida, highKashida; each with right indent 0, 200, 400, 800 twips (text width 453.6, 443.6, 433.6, 413.6pt).
Print each to PDF with Word for Windows, then: analyze.py PDF > table.tsv  (one row per line: page, label, line, x0, x1, words, start).
What to send back: the two TSVs or the PDFs. build.py regenerates docx/.
