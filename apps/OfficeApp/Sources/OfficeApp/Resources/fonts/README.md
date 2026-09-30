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
| Cambria | Caladea | Caladea-LICENSE.txt (OFL) |

The document keeps the name it came with ("Times New Roman" stays "Times
New Roman", and is written back as such); `OfficeFonts.substitute` picks
the face at render time. This is how Google Docs handles the same fonts.
There is no system-font path at all: a family not in this table draws
with the nearest of the five, and on Linux and the web there is nothing
else to draw with.

Sources: Liberation 2.x (github.com/liberationfonts), Carlito
(github.com/googlefonts/carlito), Caladea (github.com/huertatipografica/Caladea).
