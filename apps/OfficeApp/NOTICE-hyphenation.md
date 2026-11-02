# Hyphenation patterns

`Sources/OfficeText/HyphenationData.swift` embeds Liang/TeX hyphenation
patterns from the hyph-utf8 project (https://github.com/hyphenation/tex-hyphen,
`patterns/txt/`). Each language keeps its own licence; the notices are in the
upstream `hyph-<lang>.tex` files and must travel with any redistribution.

| language | licence (as stated upstream) |
|---|---|
| en-US | Copyright Gerard D.C. Kuiken; copying and distribution permitted provided the notice is retained |
| en-GB | MIT (Wujastyk, Toal) |
| nl | MIT (Piet Tutelaers) |
| de-1996 | MIT |
| es | MIT/X11 (Javier Bezos) |
| fr | MIT (Flipo, Gaulle, Reutenauer) |

Only en-US is switched on (`Hyphenator.enabled`): it is the one language
Word for Windows' reference prints show hyphenating. The rest await labs.
Regenerate the data file from the upstream `.pat.txt`/`.hyp.txt` files.
