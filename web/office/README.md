# Office web examples

The public Writer, Slides, and Sheets builds open a useful, editable document
on launch. These fictional examples are bundled with the apps, not exposed as
landing-page downloads:

- `examples/garden-brief.docx`: headings, lists, and a styled schedule table.
- `examples/garden-presentation.pptx`: four slides, a chart, and speaker notes.
- `examples/garden-budget.xlsx`: formulas, filters, currency formatting, and a chart.

`build/tools/office-web-start.py SITE writer|slides|sheets` configures a staged
`web/host/index.html` with the example's argument and `initialFiles` entry, then
copies the file to that site's `examples/` directory. Run it after setting other
page details such as title and WASM URL. It is used by `build/web-deploy.sh` and
`build/office-web-preview.sh`. The browser editor consumes the supplied bytes
through `PickedFile.take`, without prompting for a file or triggering a download.

File → New still starts blank. A reload opens a fresh copy of the bundled example;
use the editor's Save command to keep edits. No user document is changed by the
opening example. For local previews and publishing, see `ui/openoffice/README.md`.
