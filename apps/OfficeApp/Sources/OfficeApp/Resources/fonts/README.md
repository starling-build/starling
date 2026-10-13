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
