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

Sources: Poppins, Work Sans and Libre Franklin from github.com/google/fonts
(`ofl/`; Work Sans and Libre Franklin as fixed weights cut from the
variable fonts with fontTools' instancer), Selawik 1.01
(github.com/microsoft/Selawik releases; "Selawik Doc" so as not to meet the
chrome's own Selawik), TeX Gyre 2.5 OpenType from CTAN
(fonts/tex-gyre/opentype).

