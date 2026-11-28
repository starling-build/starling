// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

/// What the chrome shows about the selection. Compared before setState so
/// keystrokes that change nothing visible in the ribbon cost no rebuild.
struct ToolbarSummary: Equatable {
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var superscript = false
    var `subscript` = false
    var fontFamily: String? = nil
    var fontSize: Double? = nil
    var heading: Int? = nil
    var styleId = RichNamedStyle.normalId
    /// The selected picture, if any: its paragraph and shown size in points.
    var imageIndex: Int? = nil
    /// Set when the selected picture sits in a line of text (then `imageIndex` is its paragraph).
    var inlineImageID: String? = nil
    var imageWidth = 0.0
    var imageHeight = 0.0
    var imageHasNatural = false
    /// The picture's proportions are kept when it is resized (RichDocumentController.pictureAspectLock).
    var imageAspectLock = true
    var inCell = false
    /// The document revision: every edit changes it, so chrome that shows
    /// a value the rest of the summary does not carry (a spinner) rebuilds.
    var revision = 0
    var painting = false
    var list: ListKind? = nil
    var alignment: ParagraphAlignment = .left
    var lineSpacing = 1.0
    var canUndo = false
    var canRedo = false
    var hasSelection = false
    var words = 0
    var characters = 0
    var paragraph = 0
    var paragraphs = 0
}

/// What the window holds: a Writer document, a Slides deck or a Sheets
/// workbook. One app opens all three (docs/plans/slides.md, sheets.md);
/// the ribbon and the body follow the kind.
enum DocumentKind: Equatable {
    case document
    case presentation
    case workbook

    var appName: String {
        switch self { case .document: return "Writer"; case .presentation: return "Slides"; case .workbook: return "Sheets" }
    }
    var untitled: String {
        switch self { case .document: return "Document1"; case .presentation: return "Presentation1"; case .workbook: return "Book1" }
    }

    /// The kind a file opens as, by its extension.
    static func kind(forPath path: String) -> DocumentKind {
        switch path.pathExtension.lowercased() {
        case "pptx", "ppt", "pps", "pot": return .presentation
        case "xls", "xlsx", "csv", "tsv": return .workbook
        default: return .document
        }
    }
}

enum ViewMode: Equatable {
    case printLayout
    case webLayout
    case readMode
}

/// The open document, and everything the chrome needs to read or ask for.
/// One object shared by the shell and every ribbon/backstage widget; the
/// shell sets the `on*` callbacks and rebuilds when `summary` changes.
final class OfficeSession {
    private let _leakProbe = LeakProbe("OfficeSession")
    let kind: DocumentKind
    /// The text the chrome acts on. Writer's document; in Slides, the text
    /// body being edited (the shell points this at it), so the Font and
    /// Paragraph groups, undo and the clipboard work unchanged.
    var controller = OfficeSession.makeController() {
        didSet { controller.onHistory = { ScreenReader.announce($0) } }
    }
    private static func makeController() -> RichDocumentController {
        let c = RichDocumentController()
        c.onHistory = { ScreenReader.announce($0) }
        return c
    }
    /// The line the Borders menu applies to a cell's sides (table layout tab).
    var cellPen = CellBorderLine()
    /// The deck, in Slides.
    let deck: DeckController?
    /// The workbook, in Sheets.
    let workbook: WorkbookController?
    var theme: RichTextTheme = {
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        // The document keeps Word's font names; this picks the shipped
        // clone each is drawn with (OfficeFonts, Resources/fonts/README.md).
        theme.fontFamilyResolver = OfficeFonts.drawn
        theme.faceResolver = OfficeFonts.face
        theme.complexFaceResolver = OfficeFonts.complexFace
        theme.complexFaceKeepsDigits = OfficeFonts.complexFaceKeepsDigits
        theme.averageCharWidth = OfficeFonts.averageCharWidth
        theme.winLineBox = OfficeFonts.standInWinBox
        theme.capOverWinAscent = OfficeFonts.standInCapOverWinAscent
        theme.symbolGlyphs = { face, text in face.map { Metafile.symbols(text, face: $0) } ?? text }
        theme.isSymbolFace = { Metafile.isSymbolFace($0) }
        theme.symbolAdvance = Metafile.symbolAdvance
        theme.wordRules = true
        // (Letters one by one: Word sets a face's ligatures only where a
        // run asks for them, `w14:ligatures` — "Section" is no "ti" in Headers.)
        theme.disablesLigatures = true
        return theme
    }()

    init(kind: DocumentKind = .document) {
        // The drawing hooks (floating-picture reader, object painters) were set only once a chart, equation or group was
        // read: until then In Line with Text -> Square (ribbon, menu, keyboard bar) silently did nothing.
        WriterCharts.installHooks()
        self.kind = kind
        self.deck = kind == .presentation ? DeckController() : nil
        self.workbook = kind == .workbook ? WorkbookController() : nil
        controller.clipboardCodec = OfficeClipboardCodec()
        controller.maxPastedImageWidth = pageSetup.contentWidth
    }

    var summary = ToolbarSummary()
    /// Which contextual tab the selected image gets: a drawn shape or text box has Shape Format, a picture Picture Format.
    func imageTab(at index: Int?, inline id: String? = nil) -> RibbonTab {
        guard let i = index, i < controller.document.paragraphs.count,
              let image = id.map({ controller.document.paragraphs[i].inlineImages[$0] }) ?? controller.document.paragraphs[i].image else { return .pictureFormat }
        return image.outline != nil || image.textBox != nil ? .shapeFormat : .pictureFormat
    }
    var imageTab: RibbonTab { imageTab(at: summary.imageIndex, inline: summary.inlineImageID) }
    var zoom = 1.0
    var pageSetup = PageSetup.letter
    /// The paper page of the section the caret is in (the last section's is `pageSetup`).
    func sectionSetup() -> PageSetup {
        let mark = controller.sectionMark(containing: controller.selection.focus.paragraph)
        return (mark < 0 ? pageSetup : (controller.document.paragraphs[mark].style.sectionPage ?? pageSetup)).physical
    }
    /// Page Setup from the ribbon: one undoable step on the caret's section.
    func applyPageSetup(_ p: PageSetup) {
        controller.setPageSetup(p, lastSetup: pageSetup)
        syncPageSetup()
    }
    /// A Columns preset on the caret's section (unequal widths and the line between as Word's menu leaves them).
    func applyColumns(_ preset: ColumnsValues.Preset) {
        var p = sectionSetup(), v = ColumnsValues(p)
        v.apply(preset)
        v.apply(to: &p)
        onPageSetup?(p)
    }
    /// The last section's page follows the document (undo and redo change it).
    func syncPageSetup() {
        if let last = controller.document.lastSectionPage, last != pageSetup { pageSetup = last }
    }
    var viewMode = ViewMode.printLayout
    var showRuler = true
    var showNavigation = false
    var showStyles = false
    var showMarks = false
    /// Spelling: misspelled words get Word's red underline as they are shown.
    var checkSpelling = true
    /// AutoSave: on, a titled document writes itself after every pause in
    /// editing. Off by default — a file opened to read must not change on
    /// disk — while every document keeps a recovery copy beside it. On by
    /// default on iPad, where documents save themselves (Pages, Keynote) and
    /// there is no Cmd+S habit to lean on; the toggle stays. It writes only
    /// after an edit, so a document opened to read is still left alone.
    /// OFFICE_AUTOSAVE=1 / 0 forces it either way, so a test can watch a file
    /// change without finding the toggle.
    var autoSave: Bool = {
        if let forced = ProcessInfo.processInfo.environment["OFFICE_AUTOSAVE"], !forced.isEmpty { return forced == "1" }
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }()
    /// Format Painter: the character style picked up, applied to the next
    /// selection and then dropped.
    var paintedStyle: FormatSample? = nil
    /// Double-clicked on: stays on for several applications until Esc.
    var paintSticky = false
    var lastPainterPress = 0.0
    var pageInfo = (page: 1, count: 1)

    var path: String? = nil { didSet { if path != oldValue { onPathChanged?(path) } } }
    /// Told when the document's file changes (open, Save As, New): the window's host keeps track of which window has
    /// which file (OfficeScene.setDocumentPath).
    var onPathChanged: ((String?) -> Void)?
    var dirty = false
    /// A hosted document's name (HostedDocument), in place of a file's.
    var titleOverride: String? = nil
    var title: String {
        titleOverride ?? path.map { $0.lastPathComponent } ?? kind.untitled
    }
    /// Set for a hosted document: the owner to go back to, by name, and
    /// the way back. The title bar shows "Back to <owner>" when set.
    var hostName: String? = nil
    var hostReturnLabel: String? = nil
    var onClose: (() -> Void)?

    // Set by the shell.
    var onZoom: ((Double) -> Void)?
    var onViewMode: ((ViewMode) -> Void)?
    var onToggleRuler: (() -> Void)?
    var onToggleAspectLock: (() -> Void)?
    var onToggleNavigation: (() -> Void)?
    var onToggleStyles: (() -> Void)?
    var onToggleMarks: (() -> Void)?
    var onToggleSpelling: (() -> Void)?
    var onFormatPainter: (() -> Void)?
    var onToggleAutoSave: (() -> Void)?
    var onPrint: (() -> Void)?
    /// Opens the keyboard-shortcut list.
    var onShortcuts: (() -> Void)?
    var onPageSetup: ((PageSetup) -> Void)?
    var onBackstage: ((Bool) -> Void)?
    var onNew: (() -> Void)?
    /// What was asked for while the document had unsaved changes — a new
    /// one, another file — held until Backstage's question is answered.
    var unsavedPrompt: (() -> Void)? = nil
    /// Hosted documents save to their owner, which may answer asynchronously.
    /// Invoke the continuation only after a successful save of current edits.
    var onSaveBeforeLeaving: ((@escaping () -> Void) -> Void)?
    /// Run `action`, which replaces the open document: at once when there
    /// is nothing to lose, otherwise after Backstage has asked.
    func replacing(_ action: @escaping () -> Void) {
        guard dirty else { action(); return }
        unsavedPrompt = action
        onBackstage?(true)
    }

    /// "Don't Save" was the answer: the recovery copy kept beside the
    /// document (or in the untitled slot) goes with the changes, or the
    /// next launch would restore what was just let go.
    func discardRecoveryCopy() {
        // Hosted documents never create the untitled file's recovery copy.
        guard hostName == nil else { return }
        if let browser = OfficeHost.browserRecovery { browser.discard(); return }
        #if !os(WASI)
        let ext: String
        switch kind {
        case .document: ext = "docx"
        case .presentation: ext = "pptx"
        case .workbook: return   // Sheets keeps none
        }
        try? FileManager.default.removeItem(atPath: path.map { $0 + "~" } ?? OfficeRecovery.untitled(ext))
        #endif
    }

    /// The app's own chords from inside a text field — the find box, a
    /// chart's data cell, the name box: Save, Open, New, Print, Find and
    /// Replace go where they go from the document. Only those: a field's
    /// editing chords (copy, paste, undo) are its own business.
    func routeFieldChords() {
        FluentTextBox.unhandledCommandChord = { [weak self] key, shift in
            guard let self, let letter = KeyChordTracker.letter(key.logical) else { return false }
            switch letter {
            case "s": if shift { self.onSaveAs?() } else { self.onSave?() }
            case "o": self.onOpen?()
            case "n": self.replacing { [weak self] in self?.onNew?() }
            case "p": self.onPrint?()
            case "f": self.onFind?(false)
            case "h": self.onFind?(true)
            default: return false
            }
            return true
        }
    }

    /// Where a key goes when nothing has the keyboard. Focus is left with
    /// nobody whenever a field that had it goes away — Save As closing
    /// after a save, a chart's data cell, a bar dismissed — and from then
    /// on every key, shortcuts included, was dropped until something was
    /// clicked. `home` names the document's own focus node, or nil while
    /// something is laid over the document (Backstage, a show, a dialog)
    /// and its keys are not the document's to take.
    func homeForKeys(_ home: @escaping () -> FocusNode?) {
        if let token = _homeToken { FocusManager.instance.removeKeyInterceptor(token) }
        _homeToken = FocusManager.instance.addKeyInterceptor { _ in
            // One interceptor per window, and each acts only when its own window has the keys: otherwise the last
            // window to register would take (or silently drop) the other's keys.
            let focus = FocusManager.instance
            if focus.focusedNode == nil, let node = home(), node.currentScope == focus.keyScope { node.requestFocus() }
            return false   // never consumed here: the key goes on to its new home
        }
    }
    private var _homeToken: Int? = nil
    deinit { if let token = _homeToken { FocusManager.instance.removeKeyInterceptor(token) } }

    /// The window's own close asks too, where the host lets the app answer
    /// one: a modified document keeps the window and puts the question.
    func guardWindowClose() {
        appShouldCloseWindow = { [weak self] in
            guard let self, self.dirty, let close = hostCloseWindow else { return true }
            self.replacing(close)
            return false
        }
    }
    /// Start the other kind (a deck from Writer, a document from Slides).
    var onNewKind: ((DocumentKind) -> Void)?
    /// Open a file of the other kind: the root swaps shells.
    var onOpenKind: ((DocumentKind, String) -> Void)?
    // Slides.
    var onSlideShow: ((Bool) -> Void)?   // true = from the current slide
    var onInsertTextBox: (() -> Void)?
    var onInsertShape: ((ShapePreset) -> Void)?
    var onBackgroundPicture: (() -> Void)?
    /// Slides: Shape Fill > Picture (false) or Texture (true) wants a picture file.
    var onShapeFillPicture: ((Bool) -> Void)?
    var onInsertTable: ((Int, Int) -> Void)?
    /// Slide Show → Presenter View, from the current slide.
    var onPresenterView: (() -> Void)?
    /// Slide Show → Set Up Slide Show, Custom Shows and Rehearse Timings.
    var onSetUpShow: (() -> Void)?
    var onCustomShows: (() -> Void)?
    /// Add Section (false) or Rename Section (true): the Slides shell opens its name box.
    var onSectionName: ((Bool) -> Void)?
    /// Open (true) or close (false) Slide Master view.
    var onMasterView: ((Bool) -> Void)?
    var onLayoutName: (() -> Void)?
    var onRehearse: (() -> Void)?
    /// Show or hide the Animation Pane (Slides).
    var onAnimationPane: (() -> Void)?
    /// Show or hide the Selection Pane (Slides).
    var onSelectionPane: (() -> Void)?
    var onFormatShape: (() -> Void)?
    var onFormatBackground: (() -> Void)?
    /// Show (true) or hide the selected chart's data grid.
    var onChartData: ((Bool) -> Void)?
    /// Normal view (false) or Slide Sorter (true).
    var onSlidesView: ((Bool) -> Void)?
    var onSlidesNotesPage: (() -> Void)?
    /// Outline view: the slides' titles and body text as one editable list.
    var onSlidesOutline: (() -> Void)?
    var slidesOutline = false
    var slidesSorter = false
    /// Undo and redo when the kind has more history than the text (a deck).
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onOpen: (() -> Void)?
    var onSave: (() -> Void)?
    var onSaveAs: (() -> Void)?
    var onExport: ((String) -> Void)?
    /// Export a format and hand the copy to the host's share sheet instead of its file picker.
    var onShare: ((String) -> Void)?
    var onFind: ((Bool) -> Void)?       // true = replace bar too
    var onInsertPicture: (() -> Void)?
    /// Insert → Audio / Video: the same file list, showing sound and movie files.
    var onInsertMedia: ((_ video: Bool) -> Void)?
    var pickingMedia = false
    var onChangePicture: (() -> Void)?
    var onHeaderFooter: (() -> Void)?
    /// True while the header and footer strip is open (the Header & Footer tab shows); closing it as its Close button.
    var headerFooterOpen = false
    var onCloseHeaderFooter: (() -> Void)?
    /// Opens the Slide Size dialog, with this size typed in (nil: the deck's own).
    var onSlideSize: ((Size?) -> Void)?
    /// Slides View > Zoom: open the Zoom dialog.
    var onZoomDialog: (() -> Void)?
    /// Slides Picture Format > Alt Text: open the dialog for the selected picture.
    var onAltText: (() -> Void)?
    var onTextOptions: (() -> Void)?
    var onLink: (() -> Void)?
    /// W-FN-1: insert a footnote or endnote at the caret and open its text; edit the note the caret is next to.
    var onInsertNote: ((NoteReference.Kind) -> Void)?
    /// W-FD-2: a table of contents made with these options, the Custom Table of Contents dialog, and brought up to date
    /// (page numbers only, or the whole table).
    var onInsertContents: ((ContentsOptions) -> Void)?
    var onContentsDialog: (() -> Void)?
    var onUpdateContents: ((Bool) -> Void)?
    var onEditNote: (() -> Void)?
    /// W-FN-1: the Footnote and Endnote dialog, and Next Footnote.
    var onNoteOptions: (() -> Void)?
    var onNextNote: ((NoteReference.Kind) -> Void)?
    var onSymbolDialog: (() -> Void)?
    var onMoreColors: (() -> Void)?
    /// Slides: More Colors… of Shape Fill (false) or Shape Outline (true).
    var onMoreShapeColor: ((Bool) -> Void)?
    var onParagraphDialog: (() -> Void)?
    var onFontDialog: (() -> Void)?
    var onPageSetupDialog: (() -> Void)?
    /// Layout > Columns > More Columns.
    var onColumnsDialog: (() -> Void)?
    var onInsertTableDialog: (() -> Void)?
    var onSplitCellDialog: (() -> Void)?
    /// Writer's Draw Table / Eraser: the active table tool ("draw", "erase" or nil) and the ribbon's way to switch it.
    var tableTool: String?
    var onTableTool: ((String?) -> Void)?
    /// Convert Text to Table (true) or Table to Text (false).
    var onConvertTextTableDialog: ((Bool) -> Void)?
    var onFormulaDialog: (() -> Void)?
    var onSortTableDialog: (() -> Void)?
    var onTablePropertiesDialog: (() -> Void)?
    var onBordersShadingDialog: (() -> Void)?
    var onPictureDialog: ((PictureDialogKind) -> Void)?
    /// Opens the Set Numbering Value prompt.
    var onNumberingValueDialog: (() -> Void)?
    var onDateTimeDialog: (() -> Void)?
    var onPropertiesDialog: (() -> Void)?
    var onUpdateFields: (() -> Void)?
    /// Opens Define New Number Format (false) or Define New Bullet (true).
    var onListFormatDialog: ((Bool) -> Void)?
    var onNewStyleDialog: (() -> Void)?
    var onModifyStyle: ((String) -> Void)?
    /// Slides: Cut / Copy / Paste of the selected shapes. Each returns true
    /// when it handled the command, false to fall through to the text path.
    var onShapeCopy: (() -> Bool)?
    var onShapeCut: (() -> Bool)?
    var onShapePaste: (() -> Bool)?
    /// Slides: Select All picks every shape on the slide when no text is being edited (true when it did).
    var onShapeSelectAll: (() -> Bool)?
    /// Paste from the system clipboard; true = plain text only.
    var onPaste: ((Bool) -> Void)?
    /// Paste Options (W-ED-1): paste the clipboard in the chosen way.
    var onPasteMode: ((RichDocumentController.PasteMode) -> Void)?
    /// Paste Special (W-ED-1): the dialog of the clipboard's formats.
    var onPasteSpecial: (() -> Void)?
    var onStatus: ((String) -> Void)?   // transient status-bar message

    func summarize() -> ToolbarSummary {
        let c = controller
        var s = ToolbarSummary()
        s.bold = c.selectionAll { $0.bold }
        s.italic = c.selectionAll { $0.italic }
        s.underline = c.selectionAll { $0.underline }
        s.strikethrough = c.selectionAll { $0.strikethrough }
        s.superscript = c.selectionAll { $0.script == .superscript }
        s.subscript = c.selectionAll { $0.script == .subscript }
        let cs = c.currentCharStyle
        s.fontFamily = cs.fontFamily
        s.fontSize = cs.fontSize
        let ps = c.currentParagraphStyle
        s.heading = ps.heading
        s.styleId = c.currentNamedStyleId
        s.inCell = c.isInCell
        s.revision = c.revision
        s.painting = paintedStyle != nil
        if let i = c.selectedImageIndex, let image = c.document.paragraphs[i].image {
            s.imageIndex = i
            s.imageWidth = image.width
            s.imageHeight = image.height
            s.imageHasNatural = image.naturalWidth != nil
            s.imageAspectLock = c.pictureAspectLock
        } else if let hit = c.selectedInlineImage, let image = c.document.paragraphs[hit.paragraph].inlineImages[hit.id] {
            s.imageIndex = hit.paragraph
            s.inlineImageID = hit.id
            s.imageWidth = image.width
            s.imageHeight = image.height
            s.imageHasNatural = image.naturalWidth != nil
            s.imageAspectLock = c.pictureAspectLock
        }
        s.list = ps.list
        s.alignment = ps.alignment
        s.lineSpacing = ps.lineSpacing
        s.canUndo = c.canUndo
        s.canRedo = c.canRedo
        s.hasSelection = c.hasSelection
        s.words = c.document.wordCount
        s.characters = c.document.characterCount
        s.paragraph = c.caret.paragraph + 1
        s.paragraphs = c.document.paragraphs.count
        return s
    }

    /// The size the Font group shows: the run's own, else the heading's,
    /// else the document default.
    var effectiveFontSize: Double {
        if let size = summary.fontSize { return size }
        if let size = controller.document.styles[summary.styleId]?.char.fontSize { return size }
        if let h = summary.heading, h >= 1 {
            return theme.headingSizes[min(h, theme.headingSizes.count) - 1]
        }
        return theme.fontSize
    }

    var effectiveFontFamily: String {
        summary.fontFamily ?? controller.document.styles[summary.styleId]?.char.fontFamily ?? theme.fontFamily ?? ""
    }
}

/// The style sheet a new document starts with: Word's, with Code in the
/// bundled monospace face.
enum OfficeStyles {
    static let sheet: RichStyleSheet = {
        var sheet = RichStyleSheet.word
        if var code = sheet["Code"] {
            code.char.fontFamily = OfficeFonts.mono
            sheet["Code"] = code
        }
        return sheet
    }()
}

/// Word's colour palettes, by name.
enum OfficeColors {
    static let text: [(String, Color)] = [
        ("Automatic", Color(0xFF1B1B1B)), ("Dark Red", Color(0xFFC00000)), ("Red", Color(0xFFFF0000)),
        ("Orange", Color(0xFFFFC000)), ("Yellow", Color(0xFFFFFF00)), ("Light Green", Color(0xFF92D050)),
        ("Green", Color(0xFF00B050)), ("Light Blue", Color(0xFF00B0F0)), ("Blue", Color(0xFF0070C0)),
        ("Dark Blue", Color(0xFF002060)), ("Purple", Color(0xFF7030A0)), ("Gray", Color(0xFF7F7F7F)),
        ("White", Color(0xFFFFFFFF)),
    ]
    static let highlight: [(String, Color)] = [
        ("Yellow", Color(0xFFFFFF00)), ("Bright Green", Color(0xFF00FF00)), ("Turquoise", Color(0xFF00FFFF)),
        ("Pink", Color(0xFFFF00FF)), ("Blue", Color(0xFF0000FF)), ("Red", Color(0xFFFF0000)),
        ("Dark Blue", Color(0xFF000080)), ("Teal", Color(0xFF008080)), ("Green", Color(0xFF008000)),
        ("Violet", Color(0xFF800080)), ("Dark Red", Color(0xFF800000)), ("Dark Yellow", Color(0xFF808000)),
        ("Gray 50%", Color(0xFF808080)), ("Gray 25%", Color(0xFFC0C0C0)), ("Black", Color(0xFF000000)),
    ]
}
