# Starling Office: compatibility, one document at a time

A 3–5 minute narrated walkthrough of incremental Microsoft Office compatibility work. The revised film starts with the rendering problem and demonstrates the complete reference-PDF → Starling-PDF → raster-diff → code-fix → rerun workflow. It uses real PDF exports and unmodified comparator masks, with readable crops, before/after comparisons, captions, and a dated development timeline. It is an engineering walkthrough, not a recording of someone operating the applications.

## Snapshot and deliverables

- Source: `origin/office`, fetched on 2026-10-16 and frozen at `16902499` (use `artifacts/office-compatibility/provenance.json` for the complete SHA).
- Working branch: `office-compatibility-video`; separate checkout, preserving existing worktrees and their edits.
- Video: `artifacts/office-compatibility/starling-office-compatibility.mp4` (1920×1080, 24 fps, H.264/AAC).
- Narration: `narration.wav`; generated with macOS Samantha at 160 words per minute. This is a replaceable synthetic voice track, not the project author's voice.
- Captions: `captions.srt`, also burned into the video and included as an optional MP4 subtitle track.
- Storyboard: `storyboard.jpg`; full-resolution chapter frames under `frames/`.
- Narration and on-screen text: [`scenes.json`](scenes.json).
- Timings: `timeline.json`; exact source files, hashes, and export commands: `provenance.json`.
- Fresh per-page comparison commands, stdout and comparator hash: `diffs/manifest.json`; original three-panel PNGs and logs under `diffs/`.
- Earlier-cut historical aggregate values remain in `metrics.json`; they are not narrated in this revision.

## What each comparison demonstrates

### Slides: a chart's theme, text and legend

File: `test/corpus/pptx/decks/lo-tdf149985.pptx`, a LibreOffice test fixture. Microsoft reference: the corresponding PDF in `test/corpus/pptx/powerpoint`, exported by PowerPoint for Mac 16.113 on 2026-10-08.

The earlier Starling PDF is an archived local sweep-27 output, `~/starling-ppt-check/app27/pdf/lo-tdf149985.pdf`. The current PDF is freshly exported by the frozen build. The earlier PDF does not embed a build SHA; the film labels it “earlier,” without claiming an exact commit or that it immediately preceded the listed changes. Several intervening changes contributed to the current picture.

The October 13 sequence is recorded in `docs/plans/slides.md` and these commits:

- [515f4659](https://github.com/starling-build/starling/commit/515f4659): use the chart's own theme override.
- [7bdd9f8e](https://github.com/starling-build/starling/commit/7bdd9f8e): preserve title size, weight, color and line breaks.
- [70c6bd7a](https://github.com/starling-build/starling/commit/70c6bd7a): value-axis steps, label sizing and number formats.
- [730f2328](https://github.com/starling-build/starling/commit/730f2328): labels sourced from cells.
- [51852676](https://github.com/starling-build/starling/commit/51852676): legend size, stacking order and position.

The film does not claim this chart now matches perfectly. It retains the differences visible in the actual exports.

### Writer: blank lines that displace the following page

File: `test/corpus/docx/docs/IllustrativeCases.docx`, from the Apache POI test collection. The reference PDF is Word's actual print in `test/corpus/docx/word`.

The two historical Starling PDFs are `~/starling-doc-check-starling-ios/np17/pdf/IllustrativeCases.pdf` and the corresponding `np18` output. `s18.log` identifies this document's line-match change from 76.0 to 100.0. Both logs are copied beside the frozen PDFs. [f4cc1940](https://github.com/starling-build/starling/commit/f4cc1940), dated October 15, explains the rule and the 9.2 pt versus 12.65 pt empty-line height. Both images show page four with the identical crop and scale.

The narration discusses the heading and table position rather than claiming complete compatibility from a line-matching score. That metric has positional tolerances, excludes horizontal placement, and is not a comprehensive correctness test. The historical “before” PDF also has a trailing page that the line-based report does not count; the revised film independently checks the PDFs: before has five pages, after and Word have four. The pixel comparator reports the extra fifth page as missing in reference A.

### Sheets: category names and percentages outside a pie

File: `test/corpus/xlsx/books/chart-piechart_outside.xlsx`, from the LibreOffice test collection. The Excel reference comes from `test/corpus/xlsx/excel`, made with Excel for Windows 16.0 build 20430 and Microsoft Print to PDF. See the corpus README for the printer, display-scale and paper-size settings.

The earlier Starling PDF is `~/starling-xls-check/ours0/chart-piechart_outside.pdf`. The current PDF is freshly exported from the frozen branch. The introductory side-by-side uses independently enlarged chart excerpts for readability. The following diff scene uses exactly the same crop from each original comparator pane. Its score is calculated on the entire page, not the displayed crop. The earlier export has one page; the reference and current export have two.

[d96594ce](https://github.com/starling-build/starling/commit/d96594ce), October 16, implements pie/doughnut label content, positions, individual layout, formatting, boxes and leader lines. [a2e8ef05](https://github.com/starling-build/starling/commit/a2e8ef05) preserves stated chart text sizes. Other intervening fixes also affect colors, geometry and printing. Remaining label-text and percentage differences are acknowledged in the narration. The current output displays Canada as 6% versus the reference’s 7%, and clips some labels; the film leaves those differences visible.

## The daily development examples

| Date (commit author date) | Example | Evidence |
|---|---|---|
| October 12 | Sheet printing, chart sheets, fit-to-pages and fitted rows | `87b3cc2c`, `docs/plans/sheets.md` |
| October 13 | Chart theme, title, axis, labels and legend | Five Slides commits above |
| October 14 | Floating pictures and wrapped text in Writer | `e9ad2983`, `docs/plans/office.md` |
| October 15 | Empty-line heights restore the following page's positions | `f4cc1940` |
| October 16 | Pie chart labels and printer-dot rounding | `d96594ce`, `f905f3a9`, `48f60950`, `5b281a09` |

The discarded print-area hypothesis is recorded under “Tried and taken back” in `docs/plans/sheets.md`: `FormatConditionTests` improved from 29.6% to 6.0%, but `lo-user_defined_function` gained eleven unwanted pages. This is a historical engineering note, not a newly rerun experiment.

## Measurement boundaries

The revised film reruns `test/pdf-diff.py` on six frozen PDF pairs, all with PyMuPDF at scale 2 (144 dpi). It marks pixels where the maximum absolute RGB-channel difference exceeds 32. The displayed red masks are extracted directly from the tool's generated PNGs. Identical crops are applied to all three panes in each diff scene; displayed percentages always describe complete pages.

| Example | Page | Earlier differing pixels | After/current differing pixels |
|---|---|---|---|
| Slides chart | 1 | 13.05% | 2.08% |
| Writer line height | 4 | 7.50% | 3.81% |
| Sheets pie labels | 1 | 16.53% | 3.42% |

These are fresh measurements of selected files, not a full-corpus sweep or feature-support percentages. Historical outputs lack embedded build SHAs; the README and provenance distinguish them from current exports. The Slides and Sheets pairs span multiple improvements, not isolated single-commit experiments. The Writer pair is corroborated by the archived logs and the line-height commit.

The comparator renders onto the reference page's pixel dimensions; a differently sized second page is stretched to that canvas. The selected matching pages have equal PDF dimensions. Missing pages count as 100% different in file summaries. Font and rasterization differences contribute to the masks. We use the same comparator on both sides of each before/after measurement, without mixing CoreGraphics scores. This is visual comparison, not PDF-byte equality. Small differences below the threshold are not marked. Similarity does not establish formula correctness, editability or save-back fidelity; the narration explicitly separates these concerns.

The export-tool scene explains the existing repository automation; it does not claim to record Microsoft applications running live. Microsoft references are retained from the original corpus exports. `prepare.py` freshly exports the three selected files using Starling. Word's helper operates the print dialog; PowerPoint's helper saves as PDF; the Excel Windows helper uses COM `ExportAsFixedFormat`. See the corpus READMEs for how the frozen reference sets were generated and their settings.

## Rebuild the film

Requires macOS (`say`), ffmpeg with libx264, Python with Pillow/PyMuPDF/NumPy, and a release OfficeApp built from the frozen source snapshot. Use a virtual environment for Python dependencies.

```sh
python docs/videos/office-compatibility/narrate.py
python docs/videos/office-compatibility/prepare.py
python docs/videos/office-compatibility/diffs.py
python docs/videos/office-compatibility/render.py
```

`prepare.py` needs the local archived exports listed above for its first run. Once `assets/` has been frozen, run `diffs.py`, `narrate.py` and `render.py` to rebuild without operating Office applications. Re-recording with a human voice requires updating the sentence timings; the script and chapters remain editable. Narration caching includes a hash of the text and voice settings. Rendering encodes to a temporary MP4 before atomically replacing the served video.

The current export build reuses the existing Starling engine libraries; the video is not validation of a newly rebuilt engine. Only the three selected files are freshly exported for this film. Existing historical measurements and logs are labeled separately.

## Credits and publication copy

Document excerpts are shown to explain specific interoperability defects. Test fixtures retain their original authorship and terms: Apache POI test data (Apache-2.0 repository) and LibreOffice test data (MPL-2.0 repository), with individual source documents retaining their authors' rights. The corresponding corpus READMEs are included with the frozen assets. Starling's implementation and test scripts are available in the public repository.

Suggested title: **How we're improving Microsoft Office compatibility in Starling — one document at a time**

Suggested description:

> How do we make documents look like they do in Microsoft Office? Build a broad test collection, keep Microsoft-generated reference PDFs, export the same files from Starling, then compare the pages pixel by pixel. This walkthrough shows the actual comparison command and red difference masks, followed by real chart and text-layout fixes—and the remaining gaps.
>
> Development snapshot: October 16, 2026. Early software; visible gaps remain. The comparisons use actual PDF exports, with historical and current results labeled. Narration is synthesized.
>
> Try the apps: https://openoffice.starling.build/
>
> Code and issue reports: https://github.com/starling-build/starling
