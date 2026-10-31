# Bundled document fonts

The faces a document is drawn with, on every platform, so that a file lays
out the same here as in Word and the same on Linux, macOS, Windows and the
web. None of them is a font Word uses; each is a metric-compatible clone of
one — the same advance widths, so lines break in the same places — under
an open licence:

| In the document | Drawn with | Licence |
|---|---|---|
| Arial, Helvetica | Liberation Sans | Liberation-LICENSE.txt (OFL) |
| Times New Roman | Liberation Serif | " |
| Courier New | Liberation Mono | " |
| Calibri | Carlito | Carlito-LICENSE.txt (OFL) |
| Cambria | Caladea | Caladea-LICENSE.txt (Apache 2.0) |
| Verdana | DejaVu Sans | DejaVu-LICENSE.txt (Bitstream Vera's) |

The document keeps the name it came with ("Times New Roman" stays "Times
New Roman", and is written back as such); `OfficeFonts.substitute` picks
the face at render time. This is how Google Docs handles the same fonts.
There is no system-font path at all: a family not in this table draws
with the nearest of the six, and on Linux and the web there is nothing
else to draw with.

DejaVu Sans is the one that is not a clone: it and Verdana come of the
same design, and its widths are within a hundredth of Verdana's word for
word (measured on a PowerPoint page), which is what keeps the lines.

Sources: DejaVu 2.37 (dejavu-fonts.github.io; `-Italic` here is its
Oblique), Liberation 2.x (github.com/liberationfonts), Carlito
(github.com/googlefonts/carlito), Caladea 1.002 (the 2013 ChromeOS
`crosextrafonts-20130214` release).

Caladea must be that release and no later one. The build on
github.com/huertatipografica/Caladea (1.001, 1000 units to the em, the one
Google Fonts serves) kept the name and dropped the widths: its text runs
3 to 6 percent narrower than Cambria's, so a justified paragraph takes a
word more on a line than Word gives it. It was bundled here until
2026-10-13. Check a replacement against Word's own Cambria before
trusting the name.

## Noto Sans (2026-10-30)

A document that names "Noto Sans" (LibreOffice's test files do) is drawn with Noto Sans itself, not a
stand-in: the clone table above has nothing close to its widths, and Word's print of those files
sets it in the real face. Regular, Bold, Italic and Bold Italic, the hinted 2.x release from
github.com/notofonts/notofonts.github.io (fonts/NotoSans/hinted/ttf), OFL: NotoSans-LICENSE.txt.
Loaded with the extra faces below under the family "Noto Sans"; `OfficeFonts.substitute` maps the name.

## Slides' free faces (2026-10-17)

Families PowerPoint decks name that none of the six clones draws well,
each its own font or the nearest free design, used by Slides only
(`SlideFonts.resolve`; the widths, where the face is a stand-in, are the
original's — `SlideFontWidths`):

| In the deck | Drawn with | Licence |
|---|---|---|
| Poppins (Light, Medium, SemiBold, Black) | Poppins itself | Poppins-LICENSE.txt (OFL) |
| Work Sans (Light, Medium) | Work Sans itself | WorkSans-LICENSE.txt (OFL) |
| Segoe UI (Light, Semilight, Semibold) | Selawik, Microsoft's free Segoe UI stand-in, as "Selawik Doc" | Selawik-LICENSE.txt (OFL) |
| Franklin Gothic (Book, Medium) | Libre Franklin | LibreFranklin-LICENSE.txt (OFL) |
| Courier New, Courier | TeX Gyre Cursor (a Courier design, 0.6 em) | TeXGyre-LICENSE.txt (GUST Font License) |
| Century Gothic | TeX Gyre Adventor | " |
| Palatino Linotype, Book Antiqua | TeX Gyre Pagella | " |
| Arial Black | Archivo Black (Google Fonts; Arial Black's widths) | ArchivoBlack-LICENSE.txt (OFL) |

Sources: Poppins, Work Sans and Libre Franklin from github.com/google/fonts
(`ofl/`; Work Sans and Libre Franklin as fixed weights cut from the
variable fonts with fontTools' instancer), Selawik 1.01
(github.com/microsoft/Selawik releases; "Selawik Doc" so as not to meet the
chrome's own Selawik), TeX Gyre 2.5 OpenType from CTAN
(fonts/tex-gyre/opentype).

## 仿宋: Starling FangSong (2026-10-18)

Chinese government documents set their body text in 仿宋 (FangSong), most
often named 仿宋_GB2312. No platform this app runs on carries a FangSong it
may bundle, and Chinese text otherwise falls to the system's face (PingFang
on a Mac, a sans). `StarlingFangSong-Regular.ttf` is **Zhuque Fangsong**
(朱雀仿宋, github.com/TrionesType/zhuque, release v0.212, a technical
preview; SIL Open Font License 1.1, no Reserved Font Name;
StarlingFangSong-LICENSE.txt) re-metricked to FangSong's widths and
renamed, as the licence asks of a modified font:

- its ASCII each in a half-em cell, centred (FangSong's Latin is monospaced
  at 0.5 em), the space half an em;
- its curly quotes a full em, “ ‘ at the cell's right and ” ’ at its left;
- the full-width forms it lacks (＜ ２ ｍ …) made from its half-width ones;
- its Latin kerning (GPOS) dropped; its vertical metrics those of Liberation
  Sans, the stand-in it replaces, so no line moves;
- subset to GB2312, every character the corpus's documents use, ASCII,
  Latin-1, general and CJK punctuation and the full-width forms (9,202
  characters, 5.7 MB).

Every advance is FangSong's (Word for Mac's DFonts Fangsong.ttf, and
Office's cloud build 5.02 on Windows), so it changes the drawing of a 仿宋
run and not its layout. `OfficeFonts.fangSongFamily` picks it for 仿宋 and
FangSong; outside `OFFICE_WORD_FONTS=mac` for 仿宋_GB2312 and the 方正仿宋
names too (Word for Mac sets those in YaHei, and its prints are the
references). Rebuild with `build/tools/starling-fangsong.py ZHUQUE.ttf
OUT.ttf`, then `pyftsubset … --unicodes-file=build/tools/starling-fangsong-unicodes.txt
--layout-features='*'`.

Measured 2026-10-18 against Word's prints: on the 26 corpus documents Word
sets largely in FangSong, the page difference fell from 7.32% to 6.54%
(zh-76d361b2 9.74 to 7.60, zh-8186c98d 8.29 to 6.24); the line match and
every page count are as before, but for a few documents whose table rows
the PDF reader now groups otherwise (zh-998727df 100 to 98.4; five others
up by half a point).

