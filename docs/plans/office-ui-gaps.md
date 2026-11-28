# Office UI gaps: what we draw but cannot edit, and the order to fix it

Draft 1, amd-opus, 2026-11-24. Planner document; nothing here is coded yet.

The Office app draws nearly every feature of a .docx, .pptx or .xlsx. Its UI
edits only a part of them. This plan lists each feature, what a user can do
with it today, how often real files use it, how Word, PowerPoint and Excel
do it, and the order to build the missing pieces.

## 0. How to read this

| Item | Meaning |
| --- | --- |
| Share | Share of evaluation-corpus files using the feature (amd-8 census, `/data/s/amd-8/census/`, 2026-11-24: 4,858 docx, 1,603 pptx, 2,082 xlsx). `n/c` = the census does not count it (see section 9). The held-out set was not touched. |
| Today | What the UI allows: **V** view, **S** select, **E** edit content, **I** insert new, **F** format, **D** delete. A missing letter is the gap. |
| Saved | `yes` written from the model; `kept` the file's XML is written back untouched; `LOST` dropped on save; `LOST on edit` kept until the user touches the object, then dropped. |
| Reference | Where the Microsoft app has it (tab > group > control, dialog, shortcut, default). From memory of Office 2021/365; items marked (?) are on the confirm list in section 8. We copy behaviour and layout logic, never icons or artwork. |
| Pri | P0 = an edit or a save destroys data today. P1 = met in over about 20% of files or in every editing session. P2 = 5 to 20%. P3 = under 5% or specialist. |
| Evidence | From three code audits on 2026-11-24 (read, not run). Seven surprising claims were spot-checked against the code. Anything marked (unverified) must be checked on screen by the worker before coding. |

Shared facts that shape the plan:

| Fact | Consequence |
| --- | --- |
| Writer and Sheets have no dialogs at all, only inline bars and flyouts. Slides has one modal dialog (Header & Footer). | Most gaps need a dialog. Build one shared tabbed dialog shell first (phase 0). |
| Slides has no right-click menu on the canvas, no Format Shape pane, and its Font and Paragraph buttons work only while the caret is in text. | A selected shape cannot be formatted. This is the largest single Slides gap. |
| No unit test builds the ribbon, shell, menus or key handlers. The in-app script player (`OFFICE_SCRIPT`) is macOS only. | "Driver check" needs a harness that runs on the Linux build box (phase 0, question Q1). |
| All three editors write an object back untouched only while the user has not changed it. Once changed, it is rewritten from the model, and what the model does not hold is dropped. | Every new editing command widens what users can destroy. The P0 list comes first. |
| Legacy files: 290 .doc (5.6% of Word files), 305 .ppt (15.9%), 432 .xls (17.1%). The .xls reader exists but the open panel leaves .xls out. | One small PR opens .xls from the UI. .doc and .ppt are reader work, outside this plan. |

## 1. P0: edits and saves that destroy data today

Fix these before adding commands. Each is one PR with a round-trip unit test.

| ID | App | What breaks | Share exposed | Fix |
| --- | --- | --- | --- | --- |
| W-P0-1 | Writer | Resizing a picture rewrites it as a plain inline picture: floating position, wrap, crop, rotation, alt text and effects are lost. If the "picture" is really a shape, text box, chart or equation, the rewrite may write broken image data (unverified). | floating pictures 34.5%, shapes 25 to 33%, text boxes 22.9% | Patch only the extent in the kept XML. Refuse resize for non-picture objects until W-OBJ lands. |
| W-P0-2 | Writer | Editing the header or footer strip replaces the default header or footer (formatting, pictures, tables) with plain text. | footers 44.7%, headers 36.2% | Edit headers and footers in place as rich text (W-HF-1); until then, warn and keep the original when only fields changed. |
| W-P0-3 | Writer | Margins, orientation, size and columns are not undoable, do not mark the document changed and do not trigger AutoSave. They apply to the last section only. | every doc | Route page setup through the controller's undo; make it act on the current section. |
| W-P0-4 | Writer | Saving loses: underline kind (all become single), double strike, text glow/shadow/outline, character-style names, named table styles (flattened), content controls (unwrapped at read), most fields (TOC, REF, SEQ, MERGEFIELD, FORMTEXT, FORMDROPDOWN become plain text), picture bullets (unverified). | fields 39.9%, content controls 19.6%, table styles 96.4% | One PR per item: keep the XML the model cannot hold, as the other kept parts do. |
| W-P0-5 | Writer | Shift+Cmd+V is taken by Format Painter, so "paste as plain text" cannot be reached by key. | every session | Word uses Ctrl+Shift+C / Ctrl+Shift+V for copy and paste format and Ctrl+Alt+V for Paste Special. Keep the painter keys; give plain paste Ctrl+Alt+V and the Paste Options menu (W-CLIP-1). |
| S-P0-1 | Slides | Moving, resizing or typing in a shape rewrites it and drops: hyperlinks, vertical text, wrap off, tab stops, right-to-left, character spacing, East Asian font, text outline and gradient text, preset adjust values (rounded corners, arrow heads go back to default), click actions, alt text, probably equations. | shapes 89.1%, hyperlinks 22.5%, vertical text 7.3% | A move or resize must patch the frame in the kept XML, not rewrite. Then carry each listed property in the model, one PR each. |
| S-P0-2 | Slides | Applying a theme to an opened deck drops that deck's masters and layouts on save. | masters in 100% | Recolour the file's theme part; never swap templates on an opened deck. |
| S-P0-3 | Slides | Sections are probably stale after save (slide ids renumbered), comments probably lost, picture recolour lost when the picture is cropped or rotated, notes saved as plain text (unverified where marked in the audit). | notes 46.9%, sections 5.6%, comments 0.9% | Keep slide ids; keep comment parts; write notes as rich text. |
| S-P0-4 | Slides | Buttons that do nothing: Format Painter, Font Color > More Colours, Show/Hide marks, status-bar Fit, Cmd+G (shows "comes with milestone S6"). | every session | Wire or hide. |
| X-P0-1 | Sheets | Rich text inside a cell is saved as plain text. | rich strings 36.3% | Write the runs back. |
| X-P0-2 | Sheets | Split (unfrozen) panes are lost on save. Theme colours are written back as fixed RGB. | split 0.5% | Keep the pane element; keep theme colour references. |
| X-P0-3 | Sheets | Title-bar Undo and Redo are probably always disabled (the shell never reports undo state; check on screen). The Find box says "Search document". | every session | Set the summary from the workbook controller. |
| X-P0-4 | Sheets | .xls cannot be opened from the UI although the reader exists. Delete Sheet does not ask. Changing a chart type drops formatting the model does not hold. | .xls 17.1% | Add .xls to the open filter (saves as .xlsx); confirm before deleting a sheet. |

## 2. Writer

### 2.1 Feature by feature

| ID | Feature | Share | Today | Saved | Gap | Word reference | Pri |
| --- | --- | --- | --- | --- | --- | --- | --- |
| W-CH-1 | Font, size, bold, italic, colour, highlight, super/subscript, change case, clear formatting, Format Painter | n/c (all) | V S E F | yes | Size list is fixed (cannot type 10.5); no complex-script or East Asian font choice | Home > Font. Size box accepts any value from 1 to 1638 in half points. | P1 |
| W-CH-2 | Font dialog: underline kind and colour, double strike, small caps, all caps, hidden, character spacing (scale, spacing, position, kerning) | n/c | V | partly LOST (W-P0-4) | No UI for any of it | Home > Font launcher, Ctrl+D. Tabs Font and Advanced. Latin and Asian font boxes when an Asian language is enabled. Ctrl+Shift+K small caps, Ctrl+Shift+A all caps, Ctrl+Shift+D double underline. | P1 |
| W-CH-3 | Text effects (glow, shadow, outline, gradient) | n/c | V | LOST | Keep on save first; UI later | Home > Font > Text Effects and Typography gallery. | P3 |
| W-CH-4 | East Asian: emphasis marks, ruby (phonetic guide), enclosed and combined characters, two lines in one, horizontal in vertical | ruby 1.2% | V | yes / kept | No UI | Home > Font > Phonetic Guide, Enclose Characters; Home > Paragraph > Asian Layout menu. Emphasis mark in the Font dialog. | P3 |
| W-CH-5 | Language of text | n/c | - | kept | Status bar shows a fixed "English (United States)" | Review > Language > Set Proofing Language; status bar shows the language at the caret. | P2 |
| W-PA-1 | Alignment, left and right indent, space before and after, line spacing multiples | n/c (all) | V S E F | yes | No distributed alignment; no first-line or hanging indent (controller method exists, no UI); no exact or at-least line spacing; ruler cannot be dragged | Home > Paragraph launcher: Paragraph dialog, tab Indents and Spacing (Alignment, Outline level, Left, Right, Special: none/First line/Hanging + By, Before, After, Line spacing: Single/1.5/Double/At least/Exactly/Multiple + At, "Don't add space between paragraphs of the same style"). Ruler markers drag. Ctrl+M indent, Ctrl+T hanging, Ctrl+1/2/5 spacing. | P1 |
| W-PA-2 | Keep with next, keep lines together, widow control, page break before | n/c | V (break before: I) | yes | No UI | Paragraph dialog, tab Line and Page Breaks: four check boxes; Widow/Orphan on by default. | P2 |
| W-PA-3 | Tab stops and leaders | 48.8% | V | yes | Tab key types a tab; no way to set a stop | Paragraph dialog > Tabs...: position, alignment (Left, Center, Right, Decimal, Bar), leader (none, dots, dashes, line), Set / Clear / Clear All, default stops 0.5 in. Click the ruler to add, drag to move, drag off to delete; the tab-kind box at the ruler's left end cycles kinds. | P1 |
| W-PA-4 | Paragraph borders and shading | n/c | V | yes | No UI | Home > Paragraph > Borders menu (Bottom, Top, Left, Right, None, All, Outside, Inside...) and Shading colour; Borders and Shading dialog with tabs Borders, Page Border, Shading. | P2 |
| W-PA-5 | Right-to-left paragraphs and runs | 9.4% | V | yes | No direction buttons | Home > Paragraph > Left-to-Right / Right-to-Left Text Direction (shown when an RTL language is enabled). Ctrl+Right Shift / Ctrl+Left Shift. | P2 |
| W-PA-6 | Column break; section breaks | column breaks 2.1%; multi-section n/c | V | yes / kept | **Done** 2026-11-27 (117fee437, a2f0da3b5): Layout > Breaks inserts Page, Column (Ctrl+Shift+Enter) and Next Page, Continuous, Even Page, Odd Page section breaks. Left: Text Wrapping break. | Layout > Breaks: Page, Column, Text Wrapping; Section Breaks: Next Page, Continuous, Even Page, Odd Page. Ctrl+Enter page, Ctrl+Shift+Enter column. | P2 |
| W-PA-7 | Drop cap, frames, snap to grid, East Asian line-break options | frames 9.5%, drop cap 0.1% | V | kept | No UI | Insert > Drop Cap (Dropped, In margin, options: lines 3, distance 0). Paragraph dialog tab Asian Typography. | P3 |
| W-ST-1 | Paragraph styles: gallery, apply, update to match, modify | custom styles 78.7% | V S F | yes | Modify strip lacks underline, indents, line spacing, next style, based on; no new style; no styles pane; headings 4 to 9 have no key | Home > Styles gallery; Styles pane (Alt+Ctrl+Shift+S); Modify Style dialog with Format menu (Font, Paragraph, Tabs, Border, Numbering...). Ctrl+Alt+1/2/3 headings. | P2 |
| W-ST-2 | Character styles; themes | theme 97.4% | V | names LOST / kept | No UI | Styles pane lists character and linked styles. Design > Themes, Colors, Fonts. | P3 |
| W-LI-1 | Bullets, numbering, library formats, level by Tab | lists 40.4%, multilevel 52.8% | V S E I F D | yes | No multilevel gallery; no restart or continue; no set value; no define-new format | Home > Paragraph > Multilevel List gallery; right-click a number: Restart at 1, Continue Numbering, Set Numbering Value...; Define New Number Format / New Bullet. | P1 |
| W-TB-1 | Tables: insert, rows, columns, merge, split, column drag, header row, delete, cell-range selection | tables 60.6%, merged 31.9% | V S E I F D | yes | Insert offers 5 fixed sizes, no grid or custom size; no row-height drag; no select row/column/table commands | Insert > Table: 10 x 8 grid, Insert Table... (columns 5, rows 2, AutoFit behaviour). Table Layout > Select. Table move handle at top left. | P1 |
| W-TB-2 | Table borders and shading, per cell and per side | 60.6% | V (one on/off toggle) | yes | No per-side borders, line style, width, colour; no cell shading | Table Design > Shading, Border Styles, Line Style, Line Weight (default 1/2 pt), Pen Color, Borders menu, Border Painter; Borders and Shading dialog. | P1 |
| W-TB-3 | Table properties: width and autofit, row height and "allow row to break", cell margins, table alignment and indent, vertical alignment in cells, text direction, repeat header rows | vertical text 7.4% | V | yes | No UI except Header Row | Table Layout > Properties: dialog tabs Table (width, alignment, indent, text wrapping None/Around), Row (height, At least/Exactly, allow break, repeat as header), Column, Cell (width, vertical alignment), Alt Text; Options (default cell margins 0 / 0.08 in). Layout > Alignment 3 x 3 grid, Text Direction, Cell Margins, AutoFit menu, Height and Width boxes, Distribute Rows. | P1 |
| W-TB-4 | Table styles | table styles 96.4% | V | flattened | No gallery | Table Design > Table Styles gallery; Table Style Options (Header Row, Total Row, Banded Rows, First Column, Last Column, Banded Columns). | P2 |
| W-TB-5 | Floating tables, nested tables | 14.2%, 6.0% | V (nested: text only) | kept until edited | Cannot move a table; nested table flattens when edited | Drag the table move handle; Table Properties > Text wrapping > Around > Positioning. | P2 |
| W-TB-6 | Sort; convert text to table and back; formula | n/c | - | - | No UI and no model | Table Layout > Data: Sort, Convert to Text, Formula. | P3 |
| W-PG-1 | Page size, orientation, margins | all | V F (presets) | last section only (W-P0-3) | **Mostly done** (ea124e28b, 145764407): Page Setup dialog (custom margins, header/footer distance, orientation, paper size, apply to this section or the whole document). Left: gutter, mirror margins, 2 pages per sheet, book fold (#3257 waits for amd-10). | Layout > Margins > Custom Margins: Page Setup dialog, tabs Margins (Top/Bottom/Left/Right, Gutter, Orientation, Multiple pages: Normal/Mirror margins/2 pages per sheet/Book fold, Apply to: Whole document/This section/This point forward), Paper, Layout (Section start, Different odd and even, Different first page, From edge header/footer 0.5 in, Vertical alignment, Line Numbers..., Borders...). | P1 |
| W-PG-2 | Columns | 5.0% | V F (1, 2, 3) | yes | **Done** 2026-11-27 (145764407): Layout > Columns gets Left, Right and More Columns (number, width and spacing per column, equal width, line between, apply to). | Layout > Columns > More Columns: presets One/Two/Three/Left/Right, number, Line between, width and spacing per column, Equal column width, Apply to. | P2 |
| W-PG-3 | Page borders, line numbering, document grid, vertical page direction, page colour, watermark | 2.7%, 0.6%, n/c, n/c | V | kept | No UI | Design > Page Borders, Page Color, Watermark; Layout > Line Numbers; Layout > Text Direction; Page Setup tab Document Grid (East Asian). | P3 |
| W-HF-1 | Headers and footers | 44.7% / 36.2% | V E (one plain line, in a strip) | LOST on edit (W-P0-2) | **Done** 2026-11-25 (e5838cd81, 1c05e45e5, 21c28ea0f): formatted headers and footers (bold, italic, size, colour, font, alignment, tabs, page fields) kept on save, edited in the header/footer strip; double-click a header or footer band opens it. Left: editing in place on the page, pictures and tables in them. | Double-click the header area to enter it; body dims; "Header" tag on the dashed line; Esc or double-click the body to leave. Insert > Header / Footer galleries and Edit Header. | P1 |
| W-HF-2 | Different first page, odd and even, link to previous, distance from edge, page number format and start | even/odd 5.3% | V | yes / kept | **Done** 2026-11-27 (d87ce56f7, 7600a6c36): Page Setup Layout tab: different first page, different odd and even pages, first page number, page number format (1, i, I, a, A), Link to Previous. | Header & Footer tab: Different First Page, Different Odd & Even Pages, Show Document Text, Link to Previous, Previous/Next, Header from Top, Footer from Bottom (0.5 in); Page Number > Top/Bottom/Margins/Current Position, Format Page Numbers (format, include chapter, Continue / Start at). | P2 |
| W-FN-1 | Footnotes and endnotes | 7.0% / 0.9% | V (mark can be deleted as text) | mark yes, body kept | **Mostly done** 2026-11-28 (82f226fb1, 1f574fdc3, 51b8ca1c0): insert footnote/endnote (Alt+Ctrl+F/D), edit the note, Next Footnote, Footnote and Endnote dialog (location, number format, start at, numbering), saved. Left: restart-each-page and below-text placement are saved but not laid out; a section's own note options; Convert; custom mark. | References > Insert Footnote (Alt+Ctrl+F), Insert Endnote (Alt+Ctrl+D), Next Footnote, Show Notes; launcher: location, columns, number format, start at, numbering Continuous / Restart each section / Restart each page. Double-click a mark jumps between mark and note. | P2 |
| W-FD-1 | Fields: page number, date, author | fields 39.9% | V I (page numbers only, in the strip) | few kept, most LOST (W-P0-4) | **Done** 2026-11-28 (this PR, with 28b234142, 6fc3d23b2): Insert > Quick Parts > Field (Author, Comments, Date, FileName, Keywords, LastSavedBy, NumPages, Page, Subject, Time, Title; date formats; Preserve formatting), Date & Time with Update automatically, F9 updates every kind (page, count, references, formulas, date, properties, file name), Shift+F9 / Alt+F9 codes, Ctrl+Shift+F9 unlink, grey shading at the caret. Left: field switches beyond \@ (e.g. \* roman on PAGE), the full Word field list. | Insert > Quick Parts > Field...; Insert > Date & Time (format list, "Update automatically"); F9 update, Shift+F9 toggle code, Alt+F9 all codes, Ctrl+Shift+F9 unlink. Grey shading when the caret is inside. | P2 |
| W-FD-2 | Table of contents | 4.4% | V | entries kept, TOC field LOST | **Done** 2026-11-25 (95f2bdc49, a378aed7b): References > Table of Contents (automatic tables, custom dialog), kept as a field on save; F9 inside it updates the table. | References > Table of Contents gallery, Custom Table of Contents (show levels 3, tab leader, right-align numbers, hyperlinks), Update Table (page numbers only / entire table). | P2 |
| W-FD-3 | Bookmarks, cross references, captions (SEQ) | 27.4%, REF 0.9%, SEQ 1.9% | - | bookmarks yes, REF/SEQ LOST | No UI | Insert > Bookmark (add, delete, go to); Insert > Cross-reference; References > Insert Caption. | P3 |
| W-LK-1 | Hyperlinks | 22.4% | V S E I F D | yes | Complete (Ctrl+K, edit, remove, follow). Missing: link to a heading or bookmark in this document | Insert > Link dialog: Existing File or Web Page, Place in This Document, E-mail Address; ScreenTip. | P3 |
| W-OB-1 | Pictures in their own paragraph | inline 26.6% | V S I F (size) D | kept / LOST on resize (W-P0-1) | No crop, rotate, alt text, replace, wrap choice | Picture Format: Crop (handles, aspect, to shape), Rotate menu, Height/Width with lock aspect, Alt Text pane, Change Picture, Reset Picture; Layout Options button beside the picture. Shift keeps aspect on side handles; corners keep it by default. | P1 |
| W-OB-2 | Pictures inline in text | 26.6% | V, select and delete as a character | yes | No handles, no Picture Format tab | Same as W-OB-1; an inline picture is selected with a click and gets the same tab. | P1 |
| W-OB-3 | Floating pictures: position, wrap | 34.5%; square 9.1%, tight 4.2%, top-bottom 4.2% | V | kept | Cannot select, move, change wrap, or anchor | Layout Options: In Line with Text; Square, Tight, Through, Top and Bottom, Behind Text, In Front of Text; Move with text / Fix position on page. Drag moves; anchor mark shows with marks on. Layout dialog (Position, Text Wrapping, Size). Arrange: Bring Forward, Send Backward, Align. | P1 |
| W-OB-4 | Shapes, text boxes, groups | VML 33.3%, DrawingML 25.0%, text boxes 22.9%, groups 5.8% | V | kept | Cannot select, move, resize, edit text-box text, insert or delete | Insert > Shapes gallery (drag to draw), Insert > Text Box > Draw Text Box. Click the border selects; click inside edits text. Shape Format tab: Shape Fill, Outline, Effects, Wrap Text, Position, Group, Rotate, Size. | P1 |
| W-OB-5 | WordArt, SmartArt, charts, equations, OLE objects | 9.1%, 0.8%, 3.6%, 2.0%, 2.1% | V | kept | Cannot select, move or delete; no editing | Insert > WordArt, SmartArt, Chart, Equation (Alt+=). Charts open a data sheet. | P3 (select/move/delete with W-OB-4: P2) |
| W-RV-1 | Comments | 1.4% | V (tint only) | kept | No comment pane, no add, reply, resolve, delete. Review tab says "Coming later". | Review > New Comment (Ctrl+Alt+M), Delete, Previous, Next, Show Comments; comments in the right margin; reply and resolve in the card. | P2 |
| W-RV-2 | Tracked changes | ins 1.2%, del 0.9%, moves 3.2%, tracking on 2.7% | V (marks) | yes | No Track Changes switch, no accept or reject; new edits are not tracked even when the file says tracking is on | Review > Track Changes (Ctrl+Shift+E), Display for Review (Simple Markup / All Markup / No Markup / Original), Accept, Reject, Previous, Next, Reviewing Pane. | P2 (must respect "tracking on": P1) |
| W-RV-3 | Content controls and form fields | 19.6%; FORMTEXT 1.9%, check box 1.1% | V (control removed at read) | LOST / check box yes | Cannot fill a form: no click on a check box, no dropdown, no date picker | Click toggles a check box; dropdown shows its list; date control shows a calendar; placeholder text clears on typing. Developer tab inserts them (insert is P3). | P2 |
| W-ED-1 | Clipboard | every session | V S E | - | No Paste Options (keep source, merge, text only, picture), no Paste Special | Home > Paste menu and the Paste Options button after a paste (Ctrl, then K/M/T); Ctrl+Alt+V Paste Special. | P1 |
| W-ED-2 | Find and replace | every session | complete basics | - | No match case, whole word, wildcards, format, special; no Go To | Navigation pane search (Ctrl+F); Find and Replace dialog (Ctrl+H) > More; Go To (Ctrl+G, F5). | P2 |
| W-ED-3 | Symbols | 2.5% | I (12 fixed) | yes | No symbol picker | Insert > Symbol > More Symbols: font, subset, recent, character code, Special Characters tab. | P3 |
| W-ED-4 | Selection of objects | - | text and picture paragraphs only | - | No selection for shapes, floats, text boxes, inline pictures (see W-OB) | Home > Select > Select Objects, Selection Pane. | with W-OB |
| W-ED-5 | Spelling, word count, zoom, views, navigation pane, undo, print, export | every session | complete | - | Spelling is macOS only; no print in the browser; ruler is display only (see W-PA-1, W-PA-3) | - | P3 |

### 2.2 Writer ranked (build order within Writer)

| Rank | Gap | Why here |
| --- | --- | --- |
| 1 | W-P0-1..5 | Data loss; W-OB and W-HF work depends on them. |
| 2 | W-OB-2, W-OB-1, W-OB-3, W-OB-4 (select, move, resize, delete, wrap, text-box text) | Floating pictures 34.5%, shapes 25 to 33%, text boxes 22.9%: a third of documents have objects a user cannot even click. |
| 3 | W-HF-1, then W-HF-2 | 44.7% of documents; today's edit destroys them. |
| 4 | W-TB-2, W-TB-3, W-TB-1 | Tables in 60.6%; borders, shading and sizes are what users change. |
| 5 | W-PA-1 (Paragraph dialog, ruler drag), W-PA-3 (tabs), W-CH-2 (Font dialog), W-CH-1 | Every document; the dialogs also unblock Modify Style. |
| 6 | W-LI-1, W-PG-1, W-ED-1 | Lists 40.4%; page setup per section; paste options. |
| 7 | W-RV-3 (fill forms), W-FD-1, W-FD-2, W-FN-1, W-PA-6 | 19.6%, 39.9%, 4.4%, 7.0%. |
| 8 | W-RV-2, W-RV-1, W-PA-4, W-PA-5, W-PA-2, W-ST-1, W-TB-4, W-TB-5, W-PG-2 | Review and the remaining formatting. |
| 9 | All P3 rows | Specialist. |

## 3. Slides

### 3.1 Feature by feature

| ID | Feature | Share | Today | Saved | Gap | PowerPoint reference | Pri |
| --- | --- | --- | --- | --- | --- | --- | --- |
| S-SL-1 | Slides: add, duplicate, delete, reorder, hide | all | V S I D | yes | No drag in the sorter; Hide only in the thumbnail menu; cannot copy or paste slides; no multi-slide selection (unverified) | Thumbnail pane and Slide Sorter: Shift/Ctrl+click, drag, Ctrl+C/V, Ctrl+D, Ctrl+M new slide. Slide Show > Hide Slide. | P1 |
| S-SL-2 | Sections | 5.6% | - | probably stale (S-P0-3) | No UI, no model | Home > Section: Add, Rename, Remove, Collapse All; section headers in the thumbnail pane. | P3 |
| S-SL-3 | Slide size | 16:9 48.7%, 4:3 39.6%, other 9.9% | V F (2 sizes) | yes | No custom size, no portrait, no "scale content?" choice | Design > Slide Size > Custom Slide Size: Slides sized for (list), Width, Height, Number slides from, Orientation; then Maximize / Ensure Fit. | P2 |
| S-LA-1 | Layouts | all (layouts used: title 58.8%, obj 45.1%, blank 29.1%, custom 25.5%) | V F (our 7 only) | yes | The file's own layouts are not offered; no Reset | Home > Layout gallery lists the deck's layouts with thumbnails; Home > Reset. | P1 |
| S-LA-2 | Masters and layout artwork, placeholders | 100% | V; placeholders S E D | kept | No Slide Master view; cannot insert a placeholder | View > Slide Master: edit master and layouts, Insert Placeholder, Close Master View. | P3 |
| S-TH-1 | Themes, variants, theme colours and fonts | all | V F (6 presets) | kept / our templates (S-P0-2) | The file's theme is not shown; no colour or font sets | Design > Themes gallery, Variants > Colors, Fonts, Effects, Background Styles. | P2 |
| S-BG-1 | Slide background | picture fill 68.9% (all objects), gradient 18.9% | V F (swatches, 2 gradients, picture, apply to all) | yes | No custom gradient, pattern, transparency, hide background graphics | Design > Format Background pane: Solid, Gradient, Picture or texture, Pattern, Hide background graphics, Transparency, Apply to All, Reset Background. | P2 |
| S-TX-1 | Text boxes and placeholders: insert, type | placeholders 63.6% | V S E I D | yes (after S-P0-1) | DONE: format a selected shape's text with no caret in it (Font and Paragraph commands, Clear Formatting, Cmd+B/I/U; 0709fe5fe), undo/redo keep the selection (b674bea1f). LEFT: Text Box inserts a fixed box, not drawn; double-click to edit not rechecked | Insert > Text Box then drag. With the shape selected (border solid), Font and Paragraph commands apply to all its text. F2 toggles text and shape selection. | P1 |
| S-TX-2 | Text box options: autofit, insets, columns, vertical anchor, text direction, wrap | autofit 62.8% / 39.6%, vertical text 7.3% | V (autofit automatic) | yes; vertical and wrap LOST on edit | DONE: model, writer and a Text Options dialog (autofit, insets, columns, vertical anchor, direction, wrap; 6c5a6c962). LEFT: Home > Align Text and Text Direction menus, the AutoFit Options button | Home > Paragraph > Align Text (Top, Middle, Bottom), Text Direction (Horizontal, Rotate 90, Rotate 270, Stacked), Columns. Format Shape > Text Options > Text Box: Vertical alignment, Text direction, Do not Autofit / Shrink text on overflow / Resize shape to fit text, margins (0.1 in left and right, 0.05 in top and bottom), Wrap text in shape, Columns. AutoFit Options button at the box's lower left. | P1 |
| S-TX-3 | Character and paragraph formatting in shapes | bullets 47.1% | V S E F (shared with Writer) | yes; tabs, RTL, spacing, East Asian font LOST on edit | No space before/after, character spacing, text shadow button, tabs, RTL, bullet colour and size | Home > Font: Shadow (S button), Character Spacing menu; Paragraph dialog: Before, After, Line Spacing, indents; Bullets and Numbering dialog (size % of text, colour, picture, start at). | P2 |
| S-TX-4 | Hyperlinks and click actions | 22.5% | V (as coloured text) | LOST on edit | Not in the model; no Link button | Insert > Link (Ctrl+K): web page, Place in This Document (slide list), e-mail; Insert > Action. In the show, a click follows the link. | P1 |
| S-SH-1 | Insert shapes | shapes 89.1% | I (8 of 187 presets) | yes | 179 presets render but cannot be inserted; inserted at a fixed size, not drawn | Home / Insert > Shapes gallery in groups: Recently Used, Lines, Rectangles, Basic Shapes, Block Arrows, Equation Shapes, Flowchart, Stars and Banners, Callouts, Action Buttons. Click then drag to size; Shift keeps proportions; single click inserts 1 in x 1 in. | P1 |
| S-SH-2 | Shape adjust handles (yellow) | n/c | - | LOST on edit | No handles | Yellow handles change corner radius, arrow head size, and so on. | P2 |
| S-SH-3 | Lines, connectors, arrowheads, dash | connectors 30.3% | V S move resize; I (plain line) | kept until changed | No arrow, dash or width UI (width method exists, no UI); no connectors that stay attached | Shape Outline menu: Weight (default 0.75 pt?), Dashes, Arrows. Connectors snap to connection points and follow shapes. | P1 |
| S-SH-4 | Shape fill and outline | all | F (15 swatches, none) | yes | No theme colour grid with tints, More Colors, eyedropper, gradient, picture, pattern, transparency | Shape Format > Shape Fill: Theme Colors (10 x 6), Standard Colors, No Fill, More Fill Colors, Eyedropper, Picture, Gradient, Texture. Format Shape pane > Fill & Line. | P1 |
| S-SH-5 | Shape effects: shadow, glow, reflection, soft edges, bevel, 3D | shadow 38.2%, 3D 15.5% | V | kept | No UI | Shape Format > Shape Effects menus with presets; Format Shape pane > Effects. | P2 |
| S-SH-6 | Format Shape pane and size/position | all | - | - | No pane; no numeric size, position, rotation; no lock aspect; no alt text | Right-click > Format Shape (pane at right, tabs Fill & Line, Effects, Size & Properties: Height, Width, Rotation, Scale, Lock aspect ratio, Position from Top Left Corner/Center, Text Box, Alt Text). Shape Format > Size boxes. | P1 |
| S-AR-1 | Selection | all | click, marquee, Cmd+A, Tab; Shift/Ctrl+click and Shift+marquee add (#2784); every selected shape shows its handles (18a6d6d75); dragging any of them resizes every selected shape about its own anchor (#3297); Selection Pane with show/hide and reorder (#2784) | - | Selection Pane: no rename, no Show All / Hide All (in progress, amd-6) | Shift+click or Ctrl+click adds or removes; Home > Select > Selection Pane (Alt+F10) with show/hide and reorder. | P1 |
| S-AR-2 | Move, resize, rotate, flip | all | drag, handles, rotate handle, arrow keys | yes | No Shift (keep aspect, constrain axis), Ctrl (from centre; Ctrl+drag copies), Alt (no snap); no flip; no rotate 90 | Arrange > Rotate: Rotate Right 90, Rotate Left 90, Flip Vertical, Flip Horizontal. Arrow keys nudge; Ctrl+arrow fine nudge; Alt+Left/Right rotates 15 degrees. | P1 |
| S-AR-3 | Order, align, distribute | all | order 4, align 6 | yes | No distribute; no Align to Slide / Align Selected Objects choice | Arrange > Align: six aligns, Distribute Horizontally, Distribute Vertically, Align to Slide, Align Selected Objects. | P2 |
| S-AR-4 | Group and ungroup | 36.5% | - (members select one by one) | yes | Cmd+G shows a "later" message; a group cannot be moved as one | Ctrl+G, Ctrl+Shift+G, Regroup. First click selects the group, second click a member. | P1 |
| S-AR-5 | Guides, grid, rulers | - | smart guides | - | No rulers, grid, fixed guides | View > Ruler, Gridlines, Guides; Grid and Guides dialog. | P3 |
| S-CM-1 | Right-click menu on the canvas | every session | none | - | No context menu on shapes, text or empty slide | Shape: Cut, Copy, Paste Options, Edit Text, Edit Points, Group, Bring to Front, Send to Back, Link, Save as Picture, Edit Alt Text, Size and Position, Format Shape; plus a mini toolbar (Style, Fill, Outline). Empty slide: Paste, Layout, Reset Slide, Grid and Guides, Ruler, Format Background. | P1 |
| S-PI-1 | Pictures | 67.2% | V S I D, crop to 5 ratios, reset | yes; recolour LOST on crop/rotate | DONE: Alt Text (S-PI-1a, 38ede0f93), Change Picture (S-PI-1b, 08749ab4f), Crop mode with crop handles (S-PI-1c, 0cadb27c9: Crop button, black handles cut the picture where it stands, Enter/Esc/click away applies, one undo step). LEFT: cut-away part shown as a faded picture (now grey shading), moving the picture under the crop frame, Crop to Shape, Fill, Fit, compress, corrections, picture styles; transparency presets (S-PI-1d, this PR; LEFT: the Format Picture pane's transparency slider) | Picture Format: Crop (black handles; Enter or click away applies), Crop to Shape, Aspect Ratio, Fill, Fit; Change Picture; Corrections, Color, Transparency; Picture Styles; Alt Text; Reset Picture & Size. | P1 |
| S-TB-1 | Tables | 35.5% | V S E I D; rows, columns, merge (Writer's tab) | rewritten | DONE: Table Design tab with the six style switches, Shading, Table Styles gallery, borders and pen, Reset to Table Style (S-TB-1a..f: c1130f957, 40d6a7acd, d27cda50f, 68411efd1, 5a5524291, 82821bb44). LEFT: fixed insert sizes; Layout tab's cell text alignment, row/column size boxes, cell margins | Table Design: styles gallery, Header Row / Total Row / Banded Rows / First Column / Last Column / Banded Columns, Shading, Borders, Pen. Layout: Height, Width, Distribute Rows/Columns, Align (3 horizontal, 3 vertical), Text Direction, Cell Margins. | P1 |
| S-CH-1 | Charts | 11.9% (bar 6.7%, line 3.7%, pie 3.1%) | V S E I F D (data pane, type, 4 element toggles) | yes; unmodelled styling LOST on edit | No legend position, series colours, axis options, fonts, styles | Chart Design: Add Chart Element menu, Quick Layout, Change Colors, Chart Styles, Switch Row/Column, Select Data, Edit Data. Format pane per element. | P2 |
| S-SM-1 | SmartArt | 14.8% | V S move D | kept | No text editing, no insert | Click a node to type; Text pane; SmartArt Design tab. Insert > SmartArt gallery. | P2 (edit text), P3 (insert) |
| S-WA-1 | WordArt and text warp | 24.6% | V | yes | No UI | Shape Format > WordArt Styles > Text Effects > Transform gallery; Insert > WordArt. | P3 |
| S-MD-1 | Audio and video | 1.0%, 0.9% | V (poster) S D | kept | No playback, no insert | Insert > Video, Audio; Playback tab. | P3 |
| S-NT-1 | Speaker notes | 46.9% | V E | plain text only (S-P0-3) | Formatting applies on screen but is not saved; no Notes Page view | Notes pane under the slide; View > Notes Page. | P1 (save), P3 (view) |
| S-CO-1 | Comments | 0.9% | - | probably LOST | No UI | Review > New Comment; Comments pane. | P3 (keep on save: P0) |
| S-HF-1 | Footer, date, slide number | slide number 20.6% | V E (dialog) | yes | Complete | Insert > Header & Footer dialog. | - |
| S-TR-1 | Transitions | 25.0% | V F (5 kinds, direction, duration, apply to all) | yes; others kept | Other kinds play as fade; no advance-after-time, no sound | Transitions gallery; Timing: Sound, Duration, On Mouse Click, After. | P3 |
| S-AN-1 | Animations | 43.7% | V S F D (5 entrance effects, pane, order, timing) | yes; unmodelled timing kept read-only | No emphasis, exit, motion paths; no trigger | Animations gallery (Entrance, Emphasis, Exit, Motion Paths), Add Animation, Animation Pane, Trigger, Animation Painter. | P3 |
| S-SS-1 | Slide show and presenter view | every session | complete basics | - | No laser pointer, pen, slide picker, zoom; links not followed (with S-TX-4) | Ctrl+L laser, Ctrl+P pen, G all slides, +/- zoom. | P2 |
| S-VW-1 | Views and zoom | every session | Normal, Sorter | - | No zoom at all (always fit); no outline view; Fit button does nothing | View > Zoom, Fit to Window; status bar zoom slider 10 to 400%; Ctrl+wheel. Outline View, Notes Page, Reading View. | P1 (zoom) |
| S-ED-1 | Clipboard | every session | shapes inside the app only; text | - | Shapes do not reach the system clipboard (cannot paste into Writer or another deck window); no slides; no paste picture from another app (unverified) | Ctrl+C/V between apps; Paste Options: Use Destination Theme, Keep Source Formatting, Picture, Keep Text Only. | P1 |
| S-ED-2 | Find, spelling, undo, export, print | every session | find, undo, PDF, pptx | - | No Find buttons on Home; Cmd+P not handled; no handouts or notes pages; no picture export; spelling macOS only | File > Print: Full Page Slides, Notes Pages, Outline, Handouts (1, 2, 3, 4, 6, 9 per page). | P2 |

### 3.2 Slides ranked

| Rank | Gap | Why here |
| --- | --- | --- |
| 1 | S-P0-1..4 | Any move destroys data in 89% of decks. |
| 2 | S-AR-1, S-AR-4, S-AR-2, S-CM-1 | Multi-select, groups (36.5%), modifier keys, right-click: the basics of a canvas editor. |
| 3 | S-TX-1 (format a selected shape), S-SH-6 (Format Shape pane), S-SH-4, S-SH-3 | The pane is where most later options live. |
| 4 | S-SH-1, S-PI-1, S-TB-1, S-LA-1 | Shapes 89.1%, pictures 67.2%, tables 35.5%, the deck's own layouts. |
| 5 | S-TX-2, S-TX-4, S-VW-1, S-ED-1, S-NT-1, S-SL-1 | Text box options, links 22.5%, zoom, clipboard. |
| 6 | S-SH-5, S-SH-2, S-AR-3, S-TX-3, S-BG-1, S-TH-1, S-SL-3, S-CH-1, S-SM-1, S-SS-1, S-ED-2 | P2. |
| 7 | P3 rows | Specialist. |

## 4. Sheets

### 4.1 Feature by feature

| ID | Feature | Share | Today | Saved | Gap | Excel reference | Pri |
| --- | --- | --- | --- | --- | --- | --- | --- |
| X-CE-1 | Cell entry, formula bar, pointing at ranges, F2, F4 | all | V S E | yes | No function name completion or argument hints; no coloured range references; no AutoComplete from the column; name box does not take defined names | Formula AutoComplete list under the cell (Tab accepts); argument tooltip; each reference coloured with a matching border on the grid; Alt+Down pick from list. | P1 |
| X-CE-2 | Functions | formulas 49.0%; SUM 25.6%, IF 16.3%, VLOOKUP 6.8% | I (46 of 243 from menus, AutoSum) | yes | No Insert Function dialog; AutoSum has no Average/Count/Max/Min menu; no Ctrl+Shift+Enter | Formulas > Insert Function (Shift+F3): search, category, list, Function Arguments dialog. AutoSum menu. Alt+= AutoSum. | P2 |
| X-CE-3 | Defined names | 55.9% | - | yes | No Name Manager, no define name, name box does not list or accept names | Formulas > Name Manager (Ctrl+F3): New, Edit, Delete, Refers to, Scope; Define Name; Create from Selection; name box dropdown lists names. | P1 |
| X-SE-1 | Selection | all | range, rows, columns, all | - | No multi-range (Ctrl+click) in the model; no Go To (F5 / Ctrl+G), Go To Special; no drag of the selection border to move cells | Ctrl+click adds a range; F5 Go To > Special (Blanks, Constants, Formulas, Visible cells only...). Drag the border moves, Ctrl+drag copies. | P2 |
| X-FI-1 | Fill | all | handle, Cmd+D/R, series by pattern | yes | No Auto Fill Options button (Copy Cells, Fill Series, Fill Formatting Only, Fill Without Formatting), Series dialog, Flash Fill | Home > Fill > Series...; Ctrl+E Flash Fill. | P2 |
| X-CL-1 | Clipboard | every session | copy, cut, paste (formats kept; HTML and TSV between apps) | - | No Paste Special: values, formulas, formats, column widths, transpose, operations, skip blanks | Ctrl+Alt+V dialog; Paste menu icons row; Paste Options button after a paste; Ctrl+Shift+V paste values. | P1 |
| X-FM-1 | Format Cells dialog | all | - | - | No dialog. It is the home of most gaps below. | Ctrl+1. Tabs: Number, Alignment, Font, Border, Fill, Protection. | P1 |
| X-FM-2 | Number formats | custom formats 59.9% | F (10 presets, $ % , decimals) | yes | No fraction, no custom code entry, no locale or currency symbol choice, no date format list | Number tab: Category list (General, Number, Currency, Accounting, Date, Time, Percentage, Fraction, Scientific, Text, Special, Custom), Decimal places, 1000 separator, Negative numbers, Symbol, Locale, Type box with Sample. | P1 |
| X-FM-3 | Font, fill, borders | fonts 99.6% | F (font, size, B I U S, 14 swatches, 4 border choices) | yes (theme colours become RGB) | No border line style, colour, left/right/outside/thick/inside; no More Colors; no double underline, super/subscript; no pattern fill | Home > Borders menu (13 presets, Draw Border, Line Color, Line Style, More Borders); Border tab: Style list, Color, Presets None/Outline/Inside, eight side buttons. | P1 |
| X-FM-4 | Alignment | merged 60.7% | F (left, center, right, top, middle, bottom, wrap, merge and center) | yes | No indent, justify, distributed, center across selection, shrink to fit (not in the model), orientation (only 90 and 180 degrees draw), Merge Across / Merge Cells | Home > Alignment: Orientation menu, Increase/Decrease Indent, Merge menu (Merge & Center, Merge Across, Merge Cells, Unmerge). Alignment tab: Horizontal, Vertical, Indent, Wrap text, Shrink to fit, Merge cells, Text direction, Orientation dial. | P1 |
| X-FM-5 | Rich text in a cell; phonetic guides | 36.3%; 13.7% | V | LOST (X-P0-1) / kept (unverified) | Cannot format part of a cell's text | While editing a cell, select characters and apply font commands. | P2 |
| X-FM-6 | Cell styles, format painter | dxf 25.8% | - | kept | No gallery, no painter | Home > Cell Styles gallery; Format Painter (double-click keeps it on). | P2 |
| X-RC-1 | Rows and columns: insert, delete, resize, autofit, hide | hidden 22.0% | V S I D F | yes | Whole rows and columns only (no shift cells right/down); no Ctrl++ / Ctrl+-; no width or height dialog | Home > Insert / Delete > Cells... (Shift cells right/down, Entire row/column); Format > Row Height, Column Width, Default Width. | P1 |
| X-RC-2 | Freeze, split, group | freeze 20.2%, outline 6.2% | freeze F; group F | yes; split LOST | No split | View > Split. | P3 |
| X-SH-1 | Sheet tabs | hidden sheets 13.6% | add, delete, rename, hide, unhide | yes | No reorder by drag, no Move or Copy, no tab colour (not even shown) | Drag a tab; Ctrl+drag copies; right-click: Insert, Delete, Rename, Move or Copy..., Protect Sheet, Tab Color, Hide, Unhide, Select All Sheets. | P1 |
| X-SH-2 | Protection | 17.3% | enforced, no UI | kept | Cannot protect or unprotect; a user of a protected sheet gets refusals with no way out | Review > Protect Sheet (password, allow list), Unprotect Sheet, Protect Workbook; Format Cells > Protection (Locked, Hidden). | P2 |
| X-DA-1 | Sort | sort state 6.5% | F (one key, A-Z, Z-A) | yes | No Sort dialog | Data > Sort: levels with Column, Sort On (Cell Values, Cell Color, Font Color), Order (A to Z, Z to A, Custom List), My data has headers, Options (case, left to right). | P1 |
| X-DA-2 | Filter | 12.1% | F (value list, search, sort, clear, reapply) | yes / kept | No number, text or date filters; no colour filter | Dropdown > Number Filters / Text Filters / Date Filters > Custom AutoFilter (two conditions, And/Or); Top 10. | P2 |
| X-DA-3 | Conditional formatting | 21.6% (expression 9.2%, cell value 8.5%, duplicates 5.2%, colour scale 0.9%, data bar 0.8%, icons 0.5%) | V | kept | No create, edit, clear | Home > Conditional Formatting: Highlight Cells Rules, Top/Bottom Rules, Data Bars, Color Scales, Icon Sets, New Rule (six rule types), Clear Rules, Manage Rules (list, order, Stop If True, Applies to). | P1 |
| X-DA-4 | Data validation | 23.2% (list 20.8%) | use only (dropdown, messages) | kept | No create or edit | Data > Data Validation: Settings (Allow: Any value, Whole number, Decimal, List, Date, Time, Text length, Custom; Data; Source; Ignore blank; In-cell dropdown), Input Message, Error Alert (Stop, Warning, Information). | P1 |
| X-DA-5 | Tables | 6.5% | grows when typing below | yes | No create, convert to range, style, total row, banding, resize | Ctrl+T Create Table (range, My table has headers); Table Design tab. | P2 |
| X-DA-6 | Remove duplicates, text to columns, subtotals, goal seek | n/c | - | - | No model, no UI | Data tab. | P3 |
| X-NT-1 | Notes and comments | 14.7%; threaded 1.2% | V E I D | yes | No show all notes; no threaded replies | Review > Notes > Show All Notes; Comments pane. | P3 |
| X-LK-1 | Hyperlinks | 9.8% | follow only | kept | No insert, edit, remove | Ctrl+K Insert Hyperlink (web, Place in This Document: cell and sheet, e-mail); right-click Edit / Remove Hyperlink. | P2 |
| X-CH-1 | Charts | 13.6% (bar 7.0%, line 4.2%, scatter 2.5%) | V S I D, move, resize, change type | kept / written when new | No data range edit, titles, axes, legend, colours | Chart Design > Select Data (range, series, switch row/column), Add Chart Element; the source range shows coloured on the grid and can be dragged. | P2 |
| X-OB-1 | Pictures, shapes, text boxes | drawings 43.8%, images 21.5% | V S D, move, resize | kept | No insert (picture path is an empty stub); shape text not editable; OLE and form controls not selectable | Insert > Pictures, Shapes, Text Box. | P2 |
| X-PV-1 | Pivot tables, slicers, sparklines, external links | 2.9%, 0.2%, 0.2%, 8.2% | V (pivot values; sparklines not drawn) | kept | No UI | PivotTable Fields pane; Data > Edit Links. | P3 |
| X-PR-1 | Page setup and print | page setup 78.3%, print areas and titles 42.1%, page breaks 19.1% | print and PDF of the active sheet | kept | No Page Layout tab; no print area, titles, scaling, margins, orientation, header/footer editing, page break preview; cannot print the whole workbook or a selection | Page Layout tab: Margins, Orientation, Size, Print Area (Set / Clear), Breaks, Print Titles, Scale to Fit (Width, Height, Scale), Sheet Options (Gridlines and Headings: View / Print). Page Setup dialog tabs Page, Margins, Header/Footer (Custom Header: Left, Center, Right sections with field buttons), Sheet. View > Page Break Preview (drag the blue lines). File > Print: Active Sheets / Entire Workbook / Selection. | P1 |
| X-VW-1 | View options | gridlines off 18.9%, RTL 1.1% | gridlines, zoom | yes | Zoom is not saved to or read from the file; no Show Formulas (Ctrl+`), headings toggle; RTL sheets are not mirrored | View > Show: Formula Bar, Gridlines, Headings; Formulas > Show Formulas; Page Layout > Sheet Right-to-Left. | P2 |
| X-ST-1 | Status bar | every session | Average, Count, Sum | - | No Min, Max, Numerical Count; no choice | Right-click the status bar to tick which show. | P3 |
| X-ED-1 | Find, undo, files | every session | find and replace, undo, xlsx, csv, PDF | - | Find has no options (match case, entire cell, within sheet/workbook, look in formulas/values); no .xls from the UI (X-P0-4) | Ctrl+F > Options. | P2 |

### 4.2 Sheets ranked

| Rank | Gap | Why here |
| --- | --- | --- |
| 1 | X-P0-1..4 | Rich text loss touches 36.3% of workbooks on any save. |
| 2 | X-FM-1 with X-FM-2, X-FM-3, X-FM-4 | Format Cells is the one dialog every user opens; custom formats 59.9%, merges 60.7%. |
| 3 | X-PR-1 | Page setup in 78.3%, print areas and titles in 42.1%. |
| 4 | X-CL-1, X-RC-1, X-SH-1, X-CE-1, X-CE-3 | Paste Special, insert cells, tab reorder, formula help, names 55.9%. |
| 5 | X-DA-4, X-DA-3, X-DA-1 | Validation 23.2%, conditional formats 21.6%, Sort dialog. |
| 6 | X-SH-2, X-FM-5, X-FM-6, X-DA-2, X-DA-5, X-LK-1, X-CH-1, X-OB-1, X-VW-1, X-CE-2, X-SE-1, X-FI-1, X-ED-1 | P2. |
| 7 | P3 rows | Specialist. |

## 5. Phases and owner areas

One owner area per worker, so two workers never edit the same file group.
Order between apps: Word, then Slides, then Sheets. Phase 0 and the P0 list
run in all three at once because they block the rest.

| Area | Owns (files) | Worker slot |
| --- | --- | --- |
| U-shared | Shared chrome: dialog shell, colour picker, spinner with units, context-menu helper, UI test harness (`OfficeChrome`, `Ribbon` helpers, new `Dialogs/`) | 1 |
| W-text | Writer characters, paragraphs, lists, styles, tabs, ruler | 1 |
| W-page | Writer page setup, sections, headers and footers, notes, fields, table of contents | 1 |
| W-table | Writer tables (also serves Slides tables through the shared tab) | 1 |
| W-object | Writer pictures, shapes, text boxes, wrap, anchors | 1 |
| W-review | Writer comments, tracked changes, forms, clipboard, find | 1 |
| S-canvas | Slides selection, arrange, groups, context menu, Format Shape pane, shapes gallery, lines | 1 |
| S-content | Slides text in shapes, links, pictures, tables, charts, SmartArt text | 1 |
| S-deck | Slides layouts, themes, backgrounds, size, zoom, views, notes, show, clipboard, print | 1 |
| X-cells | Sheets Format Cells, number formats, borders, alignment, rich text, paste special, insert cells, formula help | 1 |
| X-data | Sheets sort, filter, validation, conditional formats, tables, names, protection | 1 |
| X-page | Sheets page layout and print, sheet tabs, view options, charts, pictures, links | 1 |

| Phase | Goal | U-shared | Writer | Slides | Sheets |
| --- | --- | --- | --- | --- | --- |
| 0 | Safe to edit; tools to build on | Dialog shell (tabs, OK/Cancel, Enter/Esc, focus order); unit spinner (in, cm, pt, lines); full colour picker (theme tints grid, standard, More Colors); UI test harness (Q1); wire or hide dead buttons | W-P0-1..5 | S-P0-1..4 | X-P0-1..4 |
| 1 | The objects and dialogs most files need | Context-menu helper with mini toolbar | W-object: W-OB-2, 1, 3, 4. W-page: W-HF-1, W-PG-1. W-table: W-TB-2, 3, 1. W-text: W-PA-1, W-PA-3, W-CH-2, W-CH-1. W-review: W-ED-1 | S-canvas: S-AR-1, 4, 2, S-CM-1, S-SH-6, 4, 3, 1. S-content: S-TX-1, 2, 4, S-PI-1, S-TB-1. S-deck: S-LA-1, S-VW-1, S-ED-1, S-NT-1, S-SL-1 | X-cells: X-FM-1..4, X-CL-1, X-RC-1, X-CE-1. X-data: X-CE-3, X-DA-4, 3, 1. X-page: X-PR-1, X-SH-1 |
| 2 | The P2 rows | - | W-text: W-LI-1 (rest), W-PA-2, 4, 5, W-ST-1, W-CH-5. W-page: W-HF-2, W-FN-1, W-FD-1, 2, W-PA-6, W-PG-2. W-table: W-TB-4, 5. W-object: select/move/delete for W-OB-5. W-review: W-RV-3, 2, 1, W-ED-2 | S-canvas: S-SH-5, 2, S-AR-3. S-content: S-TX-3, S-CH-1, S-SM-1. S-deck: S-BG-1, S-TH-1, S-SL-3, S-SS-1, S-ED-2 | X-cells: X-FM-5, 6, X-CE-2, X-SE-1, X-FI-1. X-data: X-SH-2, X-DA-2, 5. X-page: X-LK-1, X-CH-1, X-OB-1, X-VW-1, X-ED-1 |
| 3 | Specialist (P3 rows) | - | East Asian layout, text effects, drop cap, bookmarks and cross references, page borders, watermark, symbols, table sort | Sections, master view, WordArt, media, more animations and transitions, guides | Pivot fields, sparklines, slicers, data tools, split, status bar choices |

Rules for each implementation PR (Sonnet workers):

| Rule | Detail |
| --- | --- |
| One feature per PR | One row ID from this plan (or one named part of it) in the PR title, e.g. "W-PA-3a: Tabs dialog". Land through `~/bin/pr.sh`. |
| Model first | A controller method that is undoable in one step, then the UI that calls it. No UI code changes the model directly. |
| Round trip | A unit test that opens a file with the feature, applies the command, saves, reopens, and checks the feature and its neighbours survived. Word, PowerPoint or Excel must open the result (send starling-bd the file when the XML is new). |
| Unit tests | Controller test for the command and its undo. A harness test that the button, menu item and key each reach the command (after Q1). |
| Driver check | A scripted run that performs the command through the real UI and saves a screenshot with the PR. |
| Reference first | Before coding a dialog, read its row here and the screenshot or notes from section 8. Copy fields, order, defaults, units and keys. Draw our own icons. |
| Shared rules | Shared code builds for the browser too: sdk string helpers, no legacy Foundation (see the global notes). Touch targets and keyboardless paths per section 6. |
| No silent loss | If a command must rewrite an object, it carries every property the reader read, or it is refused with a message. |

## 6. What the iPad needs differently

Audited 2026-11-27 on the iPad Pro 13-inch (M4) simulator, iOS 18.4, main 7b451668e, engine c4d419b6580, with the in-app touch driver (`STARLING_SPIKE_INPUT`, sdk/Sources/FlutterUIKit/UIKitScriptedInput.swift: events enter at the framework's pointer packet, so the Mac's mouse never moves). Screenshots are in `docs/plans/ipad-audit-20261127/`, 900 px wide. Docs used: lk.docx (Writer), em.pptx (Slides), em.xlsx (Sheets).

Status: **works** = seen working on the simulator; **partly** = seen, with the gap named; **missing** = absent (seen or read from code, said which); **not seen** = could not be exercised here, with why.

| Topic | Status | What the audit found | Screenshot |
| --- | --- | --- | --- |
| Context menu, Writer text | **works** | A 900 ms hold selects the word and opens the full menu (B/I/U, Cut, Copy, Paste and its three variants, Link, Select All). A two-finger tap opens the same menu at the caret. | `w-hold.png`, `w-twotap.png` |
| Context menu, Writer picture | **works** | The hold on a picture selects it (8 handles) and the menu gains Fit Picture to Width, Original Size, Delete Picture; the Picture Format tab opens. | `w-pichold.png` |
| Context menu, Writer table | **works** | Seen 2026-11-27 with the soft keyboard up (hardware keyboard off in the simulator): a hold in a cell selects it and opens the menu (Insert Row Above/Below, Column Left/Right, Delete Row/Column, Delete Table, Select All). It used to run under the keyboard (Delete Table and Select All unreachable); a menu opened over a docked soft keyboard now ends above it and the keyboard bar (`ContextMenu.keyboardCover`, `FlyoutController.showFlyout(bottomInset:)`). | `after-keybar-table-menu.png`, `after-sheets-menu-above-keyboard.png` |
| Context menu, Slides | **works** (after) | Before: a text hold gave only the system edit menu, a two-finger tap nothing, a thumbnail hold nothing. Now a hold or a two-finger tap in a text box, on a shape, on the empty slide, and on a slide thumbnail (rail and sorter) opens the desktop menu. | `after-slides-*.png` (before: `s-hold.png`, `s-twotap.png`, `s-thumbhold.png`) |
| Context menu, Sheets | **works** (after) | A hold on a cell and a two-finger tap open the full cell menu. Before: a hold on a row header selected the row and opened nothing. Now a hold or a two-finger tap on a row or column header opens its menu (Insert, Delete, Clear, Format Cells, AutoFit, Width/Height, Hide, Unhide). | `x-hold.png`, `x-twotap.png`, `after-sheets-rowhold.png`, `after-sheets-colhold.png`, `after-sheets-row2tap.png` |
| Dialogs | **works** | Dialogs are bottom sheets on touch with 44 pt fields. Seen with the soft keyboard up (Connect Hardware Keyboard off, real mouse click into a field): the keyboard's bar of buttons (EditorToolbar, 44 pt) covered the sheet's OK and Cancel; the sheet now sits above it (Insert Hyperlink in Writer, Series in Sheets). | `before-dialog-keyboard.png`, `after-dialog-above-keyboard.png`, `after-sheets-series-dialog-keyboard.png` |
| Format panes | **not seen** | Not exercised (Format Shape and Format Cells need a shape/cell selection flow the driver does not yet script). Code review: the pane is a fixed right-hand panel, with no slide-over or bottom-sheet variant. Treat as missing until seen. | |
| Ribbon collapse | **works** | A narrow window folds groups to icons then to one button each (`RibbonFit`, read from code and its tests; the simulator window is wide). At the 13-inch width the Slides Home tab clips its Drawing group's caption at the bottom edge (cosmetic). | `s-hold.png` |
| Keyboard bar per context | **works** | Seen with the soft keyboard: the bar's context buttons follow the selection. Writer table cell: insert/delete row and column, Merge Cells, Delete Table. Picture or shape (whole or in a line): Wrap Text menu (only where the ribbon offers it), Crop (pictures), Shape Fill and Outline colours (shapes), Fit to Width, Aspect Lock, Delete. Slides shape: Fill, Outline, Duplicate, Delete, Bring Forward, Send Backward. Sheets cell: AutoSum, Currency, Percent, Fill Color, Sort A-Z / Z-A, Clear, Format Cells. A button can hold a menu (`OfficeToolbarButton.children`). The bar shows only over a docked keyboard (a floating one gets none). | `after-keybar-wrap-menu.png`, `after-keybar-wrap-applied.png`, `after-keybar-slides-fill-menu.png`, `after-keybar-slides-fill-applied.png`, `after-keybar-sheets-fill-menu.png`, `after-keybar-sheets-fill-applied.png` |
| Shift / Ctrl touch equivalents | **partly** | Select Multiple now covers Sheets cells too: in Home → Editing, with it on a tap on a cell or a row/column heading extends the selection from its anchor, as Shift-click does (seen: D6 then a tap on G9 selects D6:G9, status bar shows Average/Sum). Aspect lock is a toggle in Picture Format → Size. Ctrl-drag copy still has no touch path (Duplicate only in the ribbon). | `after-sheets-select-multiple-cells.png`, `after-sheets-select-multiple-button.png` |
| Handles (44 pt) | **partly** | Seen: the picture's handles are drawn as 8 pt squares. Read from code: text handles reach 8–22 pt in touch mode (`_handleHit`, knob radius 7). Both are below 44 pt. No two-finger rotate. | `w-pichold.png` |
| Link and note cards | **works** (link) | A tap on a link shows a card with the address and Open / Edit / Remove. A cell note card was not seen. | `w-linktap.png` |
| Ruler and tab stops | **works** | Touch ruler (44 pt tall, nearest marker within 44 pt takes the finger, magnified readout; `RulerTests`). Seen 2026-11-27 by finger: a drag moves the first-line marker; a tap on empty ruler adds a tab stop of the kind in the box; a tap on the kind box cycles it (left, center, right…). | `after-ruler-drag.png`, `after-ruler-tabs.png` |
| Pictures, drag and drop | **works** | Insert > Pictures opens the system sheet (Photo Library / Files) in all three apps. A photo dragged from Photos in Split View onto Writer by a real mouse drag is inserted ("Inserted IMG_0111.jpeg"): a `UIDropInteraction` on the editor view copies it to a temp file and inserts it as Insert > Picture does. Not seen: the system pickers' own screens. | `after-picture-source-sheet.png`, `after-picture-drop-splitview.png` |
| Sheets cell entry | **works** (key row gained ^ % & < > " 2026-11-27, `after-sheets-keyrow.png`) | A numeric and formula key row (= + − * / ( ) : , $ F4) shows while editing a cell; a double tap on a cell enters edit mode (`after-sheets-doubletap-edit.png`); the first audit's miss was the driver, whose two `tap` commands could overlap on the slow debug simulator and read as a two-finger tap, so it now has `dtap`. The fill handle as a menu command: Fill Down / Fill Right are in the cell menu. | `x-keyrow.png` |
| Printing | **works** | File > Print > Print options > Print opens the system print sheet with page previews in Writer, Slides (Slides / Notes / Handouts) and Sheets; it prints the same PDF as Export (`PdfExport.write` / `SlidesPdf`). Not seen: an actual printer. | `after-print-writer.png`, `after-print-slides.png`, `after-print-sheets.png` |
| Spelling | **works** | Slides shows the red wavy line under "okrege" and the system suggestion strip; `TextChecker` is UIKit. | `s-hold.png` |
| Driver | **works** | `STARLING_SPIKE_INPUT` covers tap, hold, two-finger tap, drag, type and key inside the app, with logs through `simctl launch --console`. `OFFICE_DRIVE_EXPORT` remains the only export path. | |

**Order of fixes (each its own PR, with screenshots):**

1. ~~Slides: a context menu for a hold and a two-finger tap on text, a shape and a slide thumbnail (Sheets row/column header menu in the same area).~~ Done 2026-11-27, same PR as this audit.
2. ~~Dialogs as sheets, fields at 44 pt.~~ Done 2026-11-27: `DialogShell` rises from the bottom edge on touch devices, text fields are `Chrome.fieldHeight` (44 pt on iOS, 30 on desktop); `after-dialog-sheet.png`.
3. ~~44 pt handles for pictures, shapes and the ruler.~~ Done 2026-11-27: the hit areas were already up to 44 pt (picture, shape, ruler); the drawn handles are now 14 pt (rotate 18 pt) once a finger has touched; `after-handles-picture.png`, `after-handles-shape.png`.
4. ~~The remaining Shift/Ctrl touch equivalents~~ Done for Slides 2026-11-27: the lock-aspect-ratio checkbox was already in Format Shape (and the canvas honours it); Duplicate / Delete / More now sit over a selected shape (`after-touch-actions.png`, `after-touch-duplicate.png`); two fingers twisting turn a shape (`after-twist-rotate.png`). Still open: an aspect-lock toggle for Writer pictures (corner handles keep the ratio, edges do not), Duplicate beside Writer's and Sheets' selected objects, Shift-click ranges in Sheets cells.
5. ~~Format panes as a slide-over or bottom sheet.~~ Done 2026-11-27 (`PaneArrangement`): slide-over on a wide touch window, bottom sheet below 600 pt, docked under a pointer; `after-pane-slideover.png`, `after-pane-bottomsheet.png`. Not seen: Writer's Styles pane as a slide-over, a real Split View window.

## 7. Not in this plan

| Item | Where it belongs |
| --- | --- |
| Rendering fidelity (line breaks, pagination, fonts) | The Word, Slides and Sheets fidelity queues on the board. |
| Readers for .doc and .ppt | `docs/plans/ppt-reader.md` and a .doc plan. |
| Macros, scripting, co-authoring, mail merge runs | Not planned. |

## 8. Reference requests for the Windows box (exact list)

Screenshots at 100% zoom, English UI, default settings, one PNG per item; a
dialog with tabs needs one PNG per tab. Notes can replace a screenshot where
only a default value is asked. Batch A is needed for phases 0 and 1.

| Batch | App | Item |
| --- | --- | --- |
| A1 | Word | Font dialog: tabs Font and Advanced (with an East Asian language enabled if possible) |
| A2 | Word | Paragraph dialog: tabs Indents and Spacing, Line and Page Breaks, Asian Typography; the Tabs dialog |
| A3 | Word | Page Setup dialog: tabs Margins, Paper, Layout; the Columns dialog |
| A4 | Word | Table Properties dialog: tabs Table, Row, Column, Cell, plus Options (cell margins); Borders and Shading dialog: 3 tabs; Insert Table dialog; ribbon tabs Table Design and Layout (full width) |
| A5 | Word | Header editing state (page with the Header tag and dimmed body) and the Header & Footer ribbon tab; Format Page Numbers dialog |
| A6 | Word | A selected floating picture with the Layout Options flyout open; Layout dialog tabs Position, Text Wrapping, Size; ribbon tabs Picture Format and Shape Format; right-click menus for a picture, a shape, a text box, a table cell, plain text |
| A7 | Word | Paste Options button menu; Paste Special dialog; Home > Multilevel List gallery; right-click menu on a list number; Set Numbering Value dialog |
| A8 | PowerPoint | Format Shape pane: Fill & Line, Effects, Size & Properties (each section expanded), and Text Options > Text Box |
| A9 | PowerPoint | Right-click menus: shape, text being edited, picture, table cell, group, empty slide, thumbnail; the mini toolbar |
| A10 | PowerPoint | Shapes gallery (full, all groups); Shape Fill, Shape Outline (with Weight, Dashes, Arrows submenus) and Shape Effects menus; Arrange menu; Selection Pane |
| A11 | PowerPoint | Ribbon tabs Shape Format, Picture Format, Table Design, Table Layout (full width); Layout gallery of a real deck; Slide Size dialog; Insert Hyperlink dialog |
| A12 | PowerPoint | Notes: the exact effect of Shift, Ctrl and Alt on drag, resize and rotate; default size of a shape inserted with one click; default line weight and fill of a new shape; default text box insets |
| A13 | Excel | Format Cells dialog: tabs Number (each of the 12 categories), Alignment, Font, Border, Fill, Protection |
| A14 | Excel | Page Setup dialog: tabs Page, Margins, Header/Footer (and Custom Header), Sheet; ribbon tab Page Layout; Page Break Preview of a 2-page sheet |
| A15 | Excel | Paste Special dialog; Paste menu; Insert and Delete (cells) dialogs; right-click menus for a cell, a row header, a column header, a sheet tab; Move or Copy dialog |
| A16 | Excel | Data Validation dialog: 3 tabs with Allow = List; Conditional Formatting menu with each submenu; New Formatting Rule (each of the 6 rule types); Rules Manager; Sort dialog with 2 levels; Name Manager and New Name |
| A17 | Excel | A formula being typed: the function list, the argument tooltip, coloured range references |
| B1 | Word | References tab; Footnote and Endnote dialog; Table of Contents dialog; Review tab; a comment card; Track Changes display menu; Modify Style dialog; Styles pane; Borders menu; Breaks menu; Symbol dialog; Field dialog; Date and Time dialog |
| B2 | PowerPoint | Format Background pane; Design tab with Variants menus; Chart Design tab and Add Chart Element menu; Bullets and Numbering dialog; Paragraph dialog; Print pane layout list; Slide Master tab |
| B3 | Excel | Custom AutoFilter dialog and the Number/Text/Date Filters menus; Create Table dialog and Table Design tab; Protect Sheet dialog; Insert Hyperlink dialog; Select Data Source dialog; Find and Replace with Options; Go To Special; Series dialog; Cell Styles gallery; Insert Function and Function Arguments dialogs |

## 9. Open questions and census additions

| ID | For | Question |
| --- | --- | --- |
| Q1 | starling-bd | Driver check on Linux: the script player is macOS only and no test builds the ribbon or shells. Proposed phase-0 item for U-shared: a headless harness that builds the shell in a unit test, taps a control by its label and reads the model. OK as the standard "driver check", with the macOS scripts as a second line? |
| Q2 | starling-bd | The P0 list is reader/writer work more than UI work. Proposed: it goes first, to the same owner areas. Agree, or send it to the fidelity workers? |
| Q3 | starling-bd | Twelve owner areas are listed. How many Sonnet workers are available? With fewer, run U-shared, the five Writer areas and S-canvas first. |
| Q4 | amd-8 | Census additions that would firm up the ranking. Word: documents with more than one section; runs with underline kinds other than single, small caps, all caps, character spacing, highlight; paragraphs with borders or shading, keep-with-next, exact or at-least line spacing, first-line or hanging indent; pictures with crop or rotation; watermarks; documents with tracking switched on that also hold tracked marks. Slides: counts per preset shape name (to order the Shapes gallery), arrowheads and dashed lines, adjust values, tables with cell fills or borders, speaker notes with formatting. Sheets: non-default borders, wrap, rotation, indent, cell styles beyond Normal, number-format categories, rich text runs by kind, sheets with tab colours, workbooks with more than one sheet. |
| Q5 | mac-ipad | The audit should confirm or replace section 6, and list what the keyboard bar and touch menus offer today per context. |
