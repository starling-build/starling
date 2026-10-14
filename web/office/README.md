# Office web examples

Writer, Slides, and Sheets open useful, editable fictional garden documents on
launch. They are bundled with the apps, not exposed as landing-page downloads:

- `examples/garden-brief.docx`: a three-page garden handbook.
- `examples/garden-presentation.pptx`: a nine-slide community pitch.
- `examples/garden-budget.xlsx`: five tabs for planning, exploring, and editing.

## Features to try

The examples demonstrate the major supported feature families with usable content.
They are not an exhaustive test of every formula, shape preset, or formatting option.
Features that require an action (such as find/replace, undo, and presenting) have
short “Try it” prompts. Unsupported features are not advertised.

| App / location | Demonstrated features |
| --- | --- |
| Writer, page 1 | Title/subtitle and heading styles, bold/italic runs, embedded picture and caption, bullets, headers, footer and live page-number field |
| Writer, page 2 | Styled schedule table, numbered list, hyperlink, explicit page break; prompts for navigation, find/replace, and undo |
| Writer, page 3 | Heading hierarchy, merged table cells, quotation, superscript/subscript and strikethrough; prompts for formatting and saving |
| Slides, 1–2 | Editable column chart, picture, text boxes, theme/layout parts, speaker notes on every slide |
| Slides, 3 | Editable chevrons, click-to-wipe entrance and fade transition; try in Slide Show |
| Slides, 4–5 | Editable table; a real SmartArt process with source data and cached vector drawing, movable/resizable and preserved on save |
| Slides, 6–8 | Line, area, bar, pie, scatter and doughnut charts, each with data (seven chart types including the cover) |
| Slides, 9 | WordArt warp, rotated preset shape, hyperlink; prompts for layouts, slide show and presenter view |
| Sheets, Garden budget | Filterable table, currency, formulas, named range, conditional formatting and data bars, validation, frozen row/column, linked column chart |
| Sheets, Season | Dates, percentage formulas, color scales, row outlines, line chart, print layout and page fields |
| Sheets, Volunteers | Table/filter/sort, dropdown and integer validation, frozen headings, internal hyperlink, pie chart |
| Sheets, Explore | SUM, SUMIF, COUNTIF, AVERAGE, MAX, ROUND, XLOOKUP, IFERROR, LET, a named LAMBDA; spilling UNIQUE, SEQUENCE, FILTER and SORT formulas |
| Sheets, Protected plan | Unlocked input cells, locked formulas, no-password sheet protection, cross-sheet named reference and percentage calculation |

## Regenerate and verify

```sh
python3 -m venv /tmp/office-examples-venv
/tmp/office-examples-venv/bin/pip install -r build/tools/office-examples-requirements.txt
/tmp/office-examples-venv/bin/python build/tools/office-examples.py
/tmp/office-examples-venv/bin/python build/tools/office-example-previews.py
```

The second script needs a native OfficeApp release build (override `--office-app`).
It renders the actual documents through Office and refreshes the three landing
PNG previews. PDFs are temporary rendering intermediates, not website downloads.
The site-plan illustration is original, generated with the examples, and embedded
in Writer and Slides. Keep preview dimensions/captions in the HTML synchronized.

`test/office-examples-web.py` checks all three real browser startups and saved
packages: Writer pictures/tables/header/footer/link; nine slides, seven charts,
SmartArt, notes, WordArt and animation; five worksheets with validation, formats,
protection and evaluated formulas. Use `--writer-url`, `--slides-url`, and
`--sheets-url` for local builds. The browser slide show was checked before and after revealing the final chevron
on slide 3. It uses Wipe: Fade currently leaves a black background in the browser
and is not used as the entrance showcase. Source files were also accepted cleanly by
PowerPoint (nine slides) and Excel (five sheets).

## Startup

`build/tools/office-web-start.py SITE writer|slides|sheets` configures a staged
`web/host/index.html` with the example's argument and `initialFiles` entry, then
copies the file to that site's `examples/` directory. The URL includes a content
hash, so changing the example invalidates browser caches. Run it after setting
other page details such as title and WASM URL. It is used by `build/web-deploy.sh`
and `build/office-web-preview.sh`. The browser editor consumes the supplied bytes
through `PickedFile.take`, without prompting for a file or triggering a download.

File → New still starts blank. A reload opens a fresh copy of the bundled example;
use the editor's Save command to keep edits. No user document is changed by the
opening example. For local previews and publishing, see `ui/openoffice/README.md`.
