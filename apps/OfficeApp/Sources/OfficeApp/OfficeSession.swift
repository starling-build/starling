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

enum ViewMode: Equatable {
    case printLayout
    case webLayout
    case readMode
}

/// The open document, and everything the chrome needs to read or ask for.
/// One object shared by the shell and every ribbon/backstage widget; the
/// shell sets the `on*` callbacks and rebuilds when `summary` changes.
final class OfficeSession {
    let controller = RichDocumentController()
    let theme = RichTextTheme(fontFamily: OfficeFonts.sans)

    init() {
        controller.clipboardCodec = OfficeClipboardCodec()
        controller.maxPastedImageWidth = pageSetup.contentWidth
    }

    var summary = ToolbarSummary()
    var zoom = 1.0
    var pageSetup = PageSetup.letter
    var viewMode = ViewMode.printLayout
    var showRuler = true
    var showNavigation = false
    var pageInfo = (page: 1, count: 1)

    var path: String? = nil
    var dirty = false
    var title: String {
        path.map { ($0 as NSString).lastPathComponent } ?? "Document1"
    }

    // Set by the shell.
    var onZoom: ((Double) -> Void)?
    var onViewMode: ((ViewMode) -> Void)?
    var onToggleRuler: (() -> Void)?
    var onToggleNavigation: (() -> Void)?
    var onPageSetup: ((PageSetup) -> Void)?
    var onBackstage: ((Bool) -> Void)?
    var onNew: (() -> Void)?
    var onOpen: (() -> Void)?
    var onSave: (() -> Void)?
    var onSaveAs: (() -> Void)?
    var onExport: ((String) -> Void)?
    var onFind: ((Bool) -> Void)?       // true = replace bar too
    var onInsertPicture: (() -> Void)?
    var onHeaderFooter: (() -> Void)?
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
