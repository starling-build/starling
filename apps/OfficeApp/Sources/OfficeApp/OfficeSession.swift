// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
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
    var imageWidth = 0.0
    var imageHeight = 0.0
    var imageHasNatural = false
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

/// What the window holds: a Writer document or a Slides deck. One app opens
/// both (docs/plans/slides.md); the ribbon and the body follow the kind.
enum DocumentKind: Equatable {
    case document
    case presentation

    var appName: String { self == .document ? "Writer" : "Slides" }
    var untitled: String { self == .document ? "Document1" : "Presentation1" }
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
    let kind: DocumentKind
    /// The text the chrome acts on. Writer's document; in Slides, the text
    /// body being edited (the shell points this at it), so the Font and
    /// Paragraph groups, undo and the clipboard work unchanged.
    var controller = RichDocumentController()
    /// The deck, in Slides.
    let deck: DeckController?
    var theme: RichTextTheme = {
        let theme = RichTextTheme(fontFamily: OfficeFonts.defaultFamily)
        // The document keeps Word's font names; this picks the shipped
        // clone each is drawn with (OfficeFonts, Resources/fonts/README.md).
        theme.fontFamilyResolver = OfficeFonts.substitute
        return theme
    }()

    init(kind: DocumentKind = .document) {
        self.kind = kind
        self.deck = kind == .presentation ? DeckController() : nil
        controller.clipboardCodec = OfficeClipboardCodec()
        controller.maxPastedImageWidth = pageSetup.contentWidth
    }

    var summary = ToolbarSummary()
    var zoom = 1.0
    var pageSetup = PageSetup.letter
    var viewMode = ViewMode.printLayout
    var showRuler = true
    var showNavigation = false
    var showMarks = false
    /// Spelling: misspelled words get Word's red underline as they are shown.
    var checkSpelling = true
    /// AutoSave: on, a titled document writes itself after every pause in
    /// editing. Off by default — a file opened to read must not change on
    /// disk — while every document keeps a recovery copy beside it.
    var autoSave = false
    /// Format Painter: the character style picked up, applied to the next
    /// selection and then dropped.
    var paintedStyle: CharStyle? = nil
    var pageInfo = (page: 1, count: 1)

    var path: String? = nil
    var dirty = false
    var title: String {
        path.map { $0.lastPathComponent } ?? kind.untitled
    }

    // Set by the shell.
    var onZoom: ((Double) -> Void)?
    var onViewMode: ((ViewMode) -> Void)?
    var onToggleRuler: (() -> Void)?
    var onToggleNavigation: (() -> Void)?
    var onToggleMarks: (() -> Void)?
    var onToggleSpelling: (() -> Void)?
    var onFormatPainter: (() -> Void)?
    var onToggleAutoSave: (() -> Void)?
    var onPrint: (() -> Void)?
    var onPageSetup: ((PageSetup) -> Void)?
    var onBackstage: ((Bool) -> Void)?
    var onNew: (() -> Void)?
    /// Start the other kind (a deck from Writer, a document from Slides).
    var onNewKind: ((DocumentKind) -> Void)?
    /// Open a file of the other kind: the root swaps shells.
    var onOpenKind: ((DocumentKind, String) -> Void)?
    // Slides.
    var onSlideShow: ((Bool) -> Void)?   // true = from the current slide
    var onInsertTextBox: (() -> Void)?
    var onInsertShape: ((ShapePreset) -> Void)?
    var onBackgroundPicture: (() -> Void)?
    var onInsertTable: ((Int, Int) -> Void)?
    /// Slide Show → Presenter View, from the current slide.
    var onPresenterView: (() -> Void)?
    /// Show or hide the Animation Pane (Slides).
    var onAnimationPane: (() -> Void)?
    /// Show (true) or hide the selected chart's data grid.
    var onChartData: ((Bool) -> Void)?
    /// Normal view (false) or Slide Sorter (true).
    var onSlidesView: ((Bool) -> Void)?
    var slidesSorter = false
    /// Undo and redo when the kind has more history than the text (a deck).
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onOpen: (() -> Void)?
    var onSave: (() -> Void)?
    var onSaveAs: (() -> Void)?
    var onExport: ((String) -> Void)?
    var onFind: ((Bool) -> Void)?       // true = replace bar too
    var onInsertPicture: (() -> Void)?
    var onHeaderFooter: (() -> Void)?
    var onLink: (() -> Void)?
    var onMoreColors: (() -> Void)?
    var onModifyStyle: ((String) -> Void)?
    /// Paste from the system clipboard; true = plain text only.
    var onPaste: ((Bool) -> Void)?
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
