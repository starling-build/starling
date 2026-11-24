# amd-3: why the wrap rule misfired (2026-11-24)

- The painter's wrap already wants room for the space after the text: text of 255 px wraps at a room of 261 and fits at 262 (xls-4e608c8c8a header, Arial 10). So "pad + following space" built on top of the painter counts the space twice. xls-4e608c8c8a lost its one-line headers for that reason.
- Retried as a flat 12 px pad on GDI faces (no space term): 6 books up (fr-5d2a45c29c 38.6 to 76.3), 30 down (ru-52c8f08254 92.1 to 23.1, fr-3c0d6287b4 92.3 to 32.2, en-0d2926cfb2 56.0 to 0.5: Times 12). Reverted. The pad is not one constant for every face and size.
- Lab: lab/wrapfit2/wrapfit2.xlsx (5 sheets: Calibri 11, Times New Roman 12, Arial 12, Calibri 9, Verdana 10; 6 columns of width 10 to 60; 60 rows of wrapped text each, no row heights). Need Excel's row height of every row (sheet, row, RowHeight) as in wrapfit1.
