# The .pptx corpus, and PowerPoint's rendering of it

What the Slides painter is measured against: 561 real decks, and for 553
of them the PDF that Microsoft PowerPoint itself exports. A sweep draws
every deck with this app and counts the pixels that differ from
PowerPoint's page; the scores in `docs/plans/slides.md` are those.

    decks/         the decks, as downloaded (2026-10-01)
    powerpoint/    NAME-orig.pdf — PowerPoint's export of decks/NAME.pptx
    baseline.tsv   each deck's score at the last recorded sweep (27, 2026-10-11)
    SHA256SUMS     of decks/, to tell a changed deck from a changed painter

They are in the repository because the second half cannot be downloaded.
The decks could be fetched again (`test/pptx-corpus.py` does), but
PowerPoint's PDFs took a Mac with PowerPoint, its one-time folder
permission and a run over every deck — and a score only means something
against the same references, from the same PowerPoint.

## Running a sweep

    test/pptx-app-render.sh                       # every deck, into ~/starling-ppt-check/app
    test/pptx-app-render.sh WORK                  # … into WORK
    test/pptx-app-render.sh test/corpus/pptx/decks test/corpus/pptx/powerpoint WORK NAME.pptx …

`WORK/render.tsv` gets a row per deck (pages, worst page, mean), and
`WORK/pairs/` a side-by-side PNG — PowerPoint, this app, the difference —
for every page over 0.5%. Rows already in `render.tsv` are skipped, so a
sweep resumes; delete a row to redo a deck. It needs a release build
(`OFFICE_APP` names another binary) and takes about ten minutes.

To compare with the baseline:

    join -t$'\t' test/corpus/pptx/baseline.tsv <(sort WORK/render.tsv) \
      | sed -E 's/summary pages=[0-9]+ worst=[0-9.]+% mean=//g; s/%//g' \
      | awk -F'\t' '$3-$2 > 0.15 || $2-$3 > 0.15 { printf "%-60s %6.2f -> %6.2f\n", $1, $2, $3 }'

A score is a ranking more than a measure. Font rasterisation and where a
hairline lands cost a deck one to three points on their own, so the
number says where to look and the pair image says what is wrong. When a
change is deliberate, write the new sweep over `baseline.tsv` in the same
commit, with the sweep's number in the plan.

## Sweeping off a Mac

The page diff is CoreGraphics on a Mac (`test/pdf-diff.swift`) and MuPDF
anywhere else (`test/pdf-diff.py`; `pip install pymupdf numpy pillow`),
and the two do not draw the same PDF alike: MuPDF leaves an enlarged
picture unsmoothed where CoreGraphics seems to interpolate it, and
text-heavy decks score about a point lower. So `baseline.tsv` is the Mac's, and
`baseline-mupdf.tsv` is MuPDF's, from Windows, against the same
PowerPoint PDFs. The same sweep 27 scored both ways, 2026-10-11: mean
2.95% by MuPDF where the Mac has 3.01%, 418 of 553 decks within 0.15 of
each other. (The file holds sweep 30, 2.85%, which has no Mac run yet.)
Compare a sweep with the baseline of its own rasteriser. The decks furthest apart are
pictures drawn much larger than their pixels (`lo-tdf146223`, a 2×2 JPEG
over a slide, +6.3; `lo-tdf93830`'s icons, +3.1) and photographs whose
edges resample differently (`lo-tdf157793`, 0 → 2.5).

On Windows the scripts run under Git Bash, with a release build from
`sdk\tools\build-windows.ps1 -PackagePath apps\OfficeApp -Product
OfficeApp -Configuration release`, the engine's out directory on `PATH`
(for `flutter_engine.dll`) and `STARLING_ICU` naming its `icudtl.dat`.

On Linux the sweep takes what `build/build-all.sh` makes, with nothing to
set: `PYTHON=~/venv/bin/python test/pptx-app-render.sh WORK` where the
system's python3 has no pymupdf. It scores as Windows does — sweep 29's
2.90%, 551 of 553 decks within 0.15 (2026-10-11). The engine must have
been generated since PDF export went in: an out directory whose `args.gn`
still says `skia_enable_pdf = false` writes an empty file, and every deck
reports `could not write`. Set it to `true`, `gn gen`, rebuild.

## PowerPoint's side

`powerpoint/` was exported on 2026-10-08 by PowerPoint for Mac 16.113 on
macOS 27, through `test/pptx-powerpoint-render.sh` (AppleScript drives
File → Export → PDF). Eight decks have no PDF: seven fuzzer cases
PowerPoint will not open, and `keyframes.pptx`.

Regenerate it only when there is a reason — a new PowerPoint that draws
differently, or a deck added — and then all of it, since half-new
references make sweeps incomparable:

    test/pptx-powerpoint-render.sh test/corpus/pptx/decks OUT_DIR ~/starling-ppt-check
    cp ~/starling-ppt-check/*-orig.pdf test/corpus/pptx/powerpoint/

(PowerPoint's sandbox writes only into the one folder it was granted,
hence `~/starling-ppt-check`; see the script's header.) Record the
PowerPoint version here when you do, and run a sweep for a new baseline.

Two places where PowerPoint for Mac and the file format disagree are
written down in the plan rather than matched: an `ExtTextOut` opaque box
in a WMF, and `lo-tdf113163`, which it exports black.

## Where the decks come from, and their licences

None of these files is ours. They are test data that two projects
publish, copied here unchanged, and each stays under the licence and
copyright it came with:

| names | from | licence of the source repository |
|---|---|---|
| no prefix (85) and `clusterfuzz-*` (10) | Apache POI, `test-data/slideshow` | Apache License 2.0 |
| `lo-*` (403) | LibreOffice core, `sd/qa/unit/data/pptx` | Mozilla Public License 2.0 |
| `oox-*` (63) | LibreOffice core, `oox/qa/unit/data` | Mozilla Public License 2.0 |

The prefixes were added on download to keep the sources apart; strip
`lo-` or `oox-` for the upstream name. Many are attachments from those
projects' bug reports, and some of POI's are presentations collected
from the public web (the ones named for a site); their authors hold the
copyright, and they are here only as inputs to a rendering test, as
they are upstream. The `clusterfuzz-*` files are deliberately broken.
`powerpoint/*.pdf` are renderings of the same decks and carry the same
terms.

If you hold the rights to one of these and want it gone, removing the
deck and its PDF and dropping its row from `baseline.tsv` is all it
takes; the gate does not depend on any one of them.
