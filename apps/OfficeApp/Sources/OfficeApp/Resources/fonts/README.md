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
sets it in the real face. Regular, Bold, Italic and Bold Italic, Version 1.04 (2048 upem, 2299 glyphs in
Regular), the build Word's print is set in, so its advances are Word's. Licence: Apache 2.0
(NotoSans-1.04-LICENSE.txt). Source: Microsoft Office cloud font cache, Monotype build for Google
(FontCache/4/CloudFonts/Noto Sans under %LOCALAPPDATA%, taken 2026-11-01). AOSP (external/noto-fonts)
does not carry 1.04: its earliest copy, android-6.0.0_r1 other/NotoSans-Regular.ttf, is 1.05 with 2188 glyphs.
Replaces the OFL 2.x release (NotoSans-LICENSE.txt is kept for that release; it no longer covers these files).
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


## Noto CJK and script faces (2026-11-01)

The faces a document's East Asian, Arabic, Hebrew, Thai and Devanagari text is drawn
with, and that any glyph the named face lacks falls back to, so that a render does not
depend on the fonts a machine happens to have installed. All SIL OFL 1.1
(Noto-OFL-LICENSE.txt). `fonts.tsv` is the table (file, face index in a collection,
family, weight, script, role, glyph-fallback order, bytes, sha256) the desktop registers
from and the web build's manifest reads; `fonts-aliases.tsv` maps Word's font names
(SimSun, PMingLiU, MS Gothic ...) to a family. CJK collections: faces 0 JP, 1 KR, 2 SC,
3 TC, 4 HK, each loaded under its own family name by face index (`LoadFontFromFileFace`).
Regular and Bold only. KaiTi / 楷体 have no OFL Kai face and take Noto Serif CJK SC.

Sources, unchanged from the release named:

| Files | Source |
|---|---|
| NotoSansCJK-Regular.ttc, -Bold.ttc | github.com/notofonts/noto-cjk, tag Sans2.004, 03_NotoSansCJK-OTC.zip |
| NotoSerifCJK-Regular.ttc, -Bold.ttc | github.com/notofonts/noto-cjk, tag Serif2.003, 04_NotoSerifCJKOTC.zip |
| the CJK files above | byte-identical to Ubuntu's `fonts-noto-cjk` 1:20240730 |
| NotoSansArabic, NotoNaskhArabic, NotoSansHebrew, NotoSerifHebrew, NotoSansThai, NotoSansDevanagari (Regular, Bold) | Ubuntu `fonts-noto-core` 20201225 (the 2020-12 Noto snapshot) |
| NotoColorEmoji-Pictographs.ttf | Ubuntu `fonts-noto-color-emoji` (NotoColorEmoji.ttf, sha256 9fd0a3d0ce84d77e3185dfbae77bd1abf3926aa49a032e354d076c4f17151f10) cut down by `build/tools/subset-emoji.py` (fonttools, throwaway venv) to the characters whose Unicode Emoji_Presentation is Yes, plus ZWJ, space and CR (less the plain shapes used as bullets, U+26AB and kin): a modified version of the Noto font under a new name (OFL). It goes AHEAD of DejaVu Sans in the glyph fallback so emoji draw in colour, while text-style symbols (U+263A, U+2714, U+2764 ...) stay on the outline faces. Desktop and web both use only this file |
| NotoColorEmoji-Variation.ttf | The same source cut by `build/tools/subset-emoji.py ... --text-bases` to the Emoji=Yes characters that are NOT Emoji_Presentation (U+2764, U+263A, U+2714, U+2600, U+00A9 ...; 210 code points, no ASCII), family "Noto Color Emoji Variation", fallback_order 0 (never in the glyph fallback): the layout draws a character in it only when U+FE0F follows (`RichLayout+Emoji.swift`, tables from `build/tools/emoji-ranges.py`). |

The script faces are the 2020 snapshot, not the newest notofonts releases, on purpose:
those are what a Linux machine's glyph fallback drew until now, and the 2021-2026
releases (Arabic v2.013/v2.021, Hebrew v3.001, Thai v2.002, Devanagari v2.007) changed
the shaped output enough to move rtl, zh-6a4fc013 (Thai) and others in the line pair.
Moving to them is a separate, measured step. The 2020 snapshot has no upstream release
asset to download (notofonts' releases begin later), so its provenance is the distro
package plus the sha256 below. The WebAssembly build should fetch these lazily, not ship
them in the page: about 105 MB together.

Thai is in the glyph-fallback chain (fallback_order 9). Before it was, zh-6a4fc013's Thai
was drawn as missing-glyph boxes, which the line pair counts as matching any character; that
is where its old 91.7 came from. With real Thai the document scores about 54 in the pair.
That is honest: the Thai is measured with a size scale of 0.82 (616 lines on 27 pages, as
Word's print), but Thai lines still break in other places than Word's (Word breaks at Thai
word boundaries). Thai line breaking is the open item.

sha256:

    b76b0433203017ca80401b2ee0dd69350349871c4b19d504c34dbdd80541690a  NotoSansCJK-Regular.ttc
    faa5f3656a78b2e2d450d27fe8382c778bc2b6bb5ea29c986664a6a435056ceb  NotoSansCJK-Bold.ttc
    5d9c31a059600193c9d7968a998bde886ccdc77e934006ad243b41794c496a7d  NotoSerifCJK-Regular.ttc
    1505ee3b9c0890fae6302ee0e9c6fd74d690f4a55a6ace1d9944f3f6352d622d  NotoSerifCJK-Bold.ttc
    504d7407d86875acf7d04dfaa0fd7524d0b8797723bc4aa18022f29db25b0b6e  NotoSansArabic-Regular.ttf
    ded6fc7359ca36d15d7aab9ef0c066e21ce48b26a069994d6602fa2cb9a1b952  NotoSansArabic-Bold.ttf
    8c67eaa2f0086872628fc3f7f760386f83c8be5c5e9a1ba3a38891237b2ac7cb  NotoNaskhArabic-Regular.ttf
    b5cbcb561b4b540ff11d7b6934577dbbbbb9e1d152d47f6f31f19176d58ff39c  NotoNaskhArabic-Bold.ttf
    436900d5ad77d33e4234247f3076eaecd25b92b9bea0519514f684140e3566a7  NotoSansHebrew-Regular.ttf
    d3b01343f71e8a93fffb84c345a1aecbaf4694b98d0eaace916cb9eac9e6dcd3  NotoSansHebrew-Bold.ttf
    789b7e7e3ff4d95a5e105872a385db12c50c08b60ad5b773d25a3bec86621abf  NotoSerifHebrew-Regular.ttf
    95150a28d438cba6c79393ef18ad06f39a8b53a7d457e61d8c9d585176ef36da  NotoSerifHebrew-Bold.ttf
    dfbd5ed0f1e68c3cbc51aa08f646d1ab0e68e7c4ceab70a69e465225ff701f93  NotoSansThai-Regular.ttf
    97bbc8ea98328325285f2f552228c7aac1db39d8f38f0096a61ba7df1f1f780e  NotoSansThai-Bold.ttf
    79a470365ccb210fa3c7d8d8ff2e005ef9d983cfd067f735a0caf7e15070ca9f  NotoSansDevanagari-Regular.ttf
    77ad688cfe1dc55185bf4edb4db3c614202c65dd23a1463ad0e23fc52bcc9a5c  NotoSansDevanagari-Bold.ttf
    2babe375f708225a6cfc6fe870bba15cdfbadc260d4bb96040413310608b64a2  NotoColorEmoji-Pictographs.ttf
    8ccdc7cca6515eaa4e9e15573a95dc28d508088a6bba05ca30bbdcea07fb2d5f  NotoColorEmoji-Variation.ttf

## DejaVu Math TeX Gyre

`DejaVuMathTeXGyre.ttf` (fallback_order 9, family "DejaVu Math TeX Gyre", the name WriterMath
asks for) is the maths face; it keeps the pi in lo-6e71a4d5. Added by amd-4. Licence as Debian
lists it for DejaVu (Bitstream Vera terms); the TeX Gyre side originates with the GUST e-foundry.
