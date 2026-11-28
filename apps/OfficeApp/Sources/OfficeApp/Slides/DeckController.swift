// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

// MARK: - Snapshots (undo)

/// A large value held by reference (copy on write): a `ShapeState` is copied many times a read, and its
/// big fields (a text body 4.3 KB, a chart 4.4 KB, fills 1.3 KB) made it 27 KB, so a recursive reader's frame
/// held dozens of copies (375 to 864 KB a group level in a release build; ja-85c85cb794 overflowed the stack).
@propertyWrapper
struct Boxed<Value: Equatable>: Equatable {
    private final class Ref { let value: Value; init(_ value: Value) { self.value = value } }
    private var ref: Ref
    init(wrappedValue: Value) { ref = Ref(wrappedValue) }
    var wrappedValue: Value {
        get { ref.value }
        set { ref = Ref(newValue) }
    }
    static func == (a: Boxed, b: Boxed) -> Bool { a.ref === b.ref || a.ref.value == b.ref.value }
}

/// Everything a shape is, as a value: what undo stores and restores.
struct ShapeState: Equatable {
    var id: Int
    var name: String
    var kind: ShapeKind
    var frame: Rect
    var rotation: Double
    var fill: Color?
    var outline: Color?
    var outlineWidth: Double
    var anchor: TextAnchor
    var insets: EdgeInsets
    var prompt: String?
    @Boxed var text: RichDocument?
    var font: String?
    var size: Double
    var color: Color
    var listIndent: Double
    var phType: String? = nil
    var phIdx: String? = nil
    var fillScheme: String? = nil
    /// The same for the outline (`SchemeColor`).
    var outlineScheme: String? = nil
    var themeStyle = false
    var quickStyle: ShapeQuickStyle? = nil
    /// A picture's crop, as fractions cut from each edge.
    var crop: EdgeInsets? = nil
    var flipH = false
    var flipV = false
    /// Lock aspect ratio (`noChangeAspect`): nil until set, when a picture counts as locked and any other shape as free.
    var aspectLock: Bool? = nil
    var aspectLocked: Bool {
        if let l = aspectLock { return l }
        if case .picture = kind { return true }
        return false
    }
    var pictureGeometry: ShapePreset? = nil
    var pictureAlpha = 1.0
    var pictureDuotone: [Color]? = nil
    var pictureLevels: [Double]? = nil
    var pictureColorChange: [Color]? = nil
    var pictureInset = EdgeInsets.zero
    var fillsWithBackground = false
    var inheritedPreset: ShapePreset? = nil
    var customPath: FreeformGeometry? = nil
    var adjusts: [String: Double] = [:]
    var connAnchor: [Int: Rect] = [:]
    @Boxed var fillStyle: SlideFill? = nil
    var invisible = false
    var fileId: Int? = nil
    var sourceXML: String? = nil
    @Boxed var sourceText: RichDocument? = nil
    var sourcePart: String? = nil
    @Boxed var sourceChart: Chart? = nil
    var field: SlideField? = nil
    var group: ShapeGroup? = nil
    var keptLine: KeptLine? = nil
    var altText: String? = nil
    /// The alt text's title (`cNvPr title`): a short name for the object.
    var altTitle: String? = nil
    var link: String? = nil
    var linkTip: String? = nil
    var keptPicture: KeptPicture? = nil
    var autofit = false
    var fontScale = 1.0
    /// A chart's own drawing (`c:userShapes`), drawn over it, never written.
    var chartDrawing: [ShapeState] = []
    var insetsFollowFont = false
    var sizeGroup: String? = nil
    var keepsSize = false
    var generatedHang = false
    var outlineDash: String? = nil
    var outlineJoin: String? = nil
    var outlineCap: String? = nil
    var media: MediaClip? = nil
    @Boxed var outlineFill: SlideFill? = nil
    var headEnd: LineEnd? = nil
    var tailEnd: LineEnd? = nil
    var connStart: ShapeConn? = nil
    var connEnd: ShapeConn? = nil
    /// As read: the file's `cNvPr` ids (not yet deck ids), resolved once the slide's shapes are known.
    var pendingConnStart: ShapeConn? = nil
    var pendingConnEnd: ShapeConn? = nil
    var outlineCompound: String? = nil
    var textTurn = 0
    var textStacked = 0
    var uprightIdeographs = false
    var sidewaysDigits = false
    var textSpin = 0.0
    var textRev = 0.0
    var textScene: Scene3D? = nil
    var naturalLines = false
    var shadow: CharShadow? = nil
    var reflection: Reflection? = nil
    var innerShadow: CharShadow? = nil
    var glowRadius: Double? = nil
    var glowColor: Color? = nil
    var softEdge: Double? = nil
    var bevel: ShapeBevel? = nil
    var shapeInsets = EdgeInsets.zero
    /// A diagram shape turned a quarter whose text frame is turned back
    /// upright: that frame, and the text's own insets — drawn as a box of
    /// its own over the shape (never written; a diagram's drawing is not).
    var uprightBox: Rect? = nil
    var uprightInsets = EdgeInsets.zero
    var noWrap = false
    var anchorCentred = false
    var bodyVert: String? = nil
    var bodyWrap: String? = nil
    var fitRule: String? = nil
    var keepsFirstSpace = false
    var columns = 1
    var columnGap = 0.0
    var warp: TextWarp? = nil
    var runLooks: [[RunLook]] = []
    var scene3d: Scene3D? = nil
    var camera: String? = nil
    var lineReduction = 0.0
    var keptLook: KeptLook? = nil
    /// Set for a text shape read from a file: see `ReadShape`.
    var readShape: ReadShape? = nil
}

extension ShapeState {
    var chart: Chart? {
        if case .chart(let c) = kind { return c }
        return nil
    }
}

struct SlideState: Equatable {
    var id: Int
    var layout: SlideLayoutKind
    var hidden: Bool
    var section: String? = nil
    var masterRole: MasterRole? = nil
    var hideMasterShapes = false
    var clrMapOvrXML: String? = nil
    var extLstXML: String? = nil
    var cSldExtLstXML: String? = nil
    var controlsXML: String? = nil
    var custDataXML: String? = nil
    var decorations: [ShapeState] = []
    var notes: RichDocument
    var shapes: [ShapeState]
    var layoutPart: String? = nil
    var backgroundXML: String? = nil
    var background: SlideFill? = nil
    var inheritedBackground: SlideFill? = nil
    var sourcePart: String? = nil
    var transition = SlideTransition()
    var timingXML: String? = nil
    var footerFrames: [String: Rect] = [:]
    var animations: [ShapeAnimation] = []
    var sourceAnimations: [ShapeAnimation]? = nil
    /// The file part whose comments this slide shows: its own source part, or the one it was copied from.
    var commentsFrom: String? = nil
    /// The source part slide-level kept things are carried from.
    var carryPart: String? { commentsFrom ?? sourcePart }
    /// The notes as read; while `notes` still equals them the save keeps the file's own notes page.
    var sourceNotes: RichDocument? = nil
}

struct DeckState: Equatable {
    var slides: [SlideState]
    var current: Int
    var slideSize: Size
    /// Undo restores the look too: applying a theme is one step.
    var theme: DeckTheme? = nil
    var ownTemplates: Bool? = nil
    var recolourTheme: Bool? = nil
    /// `p:presentation firstSlideNum`: the number the first slide shows in a slide-number field (PowerPoint prints 0 when a deck says 0).
    var firstSlideNum = 1
    /// The background Apply to All wrote on the master (solid or gradient); nil leaves the file's own.
    var masterBackground: SlideFill? = nil
    /// How the last Slide Size change scaled the content; the writer scales the file's own master and layouts the same way.
    var slideScaling: DeckController.SlideScaling? = nil
    var show = ShowSettings()
    var customShows: [CustomShow] = []
    var sections: [SlideSection] = []
    /// The show settings as read: while `show` still equals them, the file's
    /// own `p:showPr` is saved as it was, spellings of the defaults included.
    var sourceShow: ShowSettings? = nil
}

/// Every change to a deck goes through here. Listeners hear about slide
/// edits and about typing in any text body (thumbnails and anchored text
/// both follow the words), and `revision` moves on each.
///
/// Undo is by snapshot: each edit pushes the deck as it was. Text typed in
/// a body has its own undo inside the body's controller while it is being
/// edited; when editing ends (or any deck edit interrupts it) the whole
/// session becomes one deck step, so ⌘Z after leaving a box takes its
/// typing back as PowerPoint does.
final class DeckController: ChangeNotifier {
    private let _leakProbe = LeakProbe("DeckController")
    var slides: [Slide] = []
    var current = 0 {
        didSet {
            if current != oldValue, slides.indices.contains(current) {
                ScreenReader.announce("Slide \(current + 1) of \(slides.count)")
            }
        }
    }
    /// The slide in points: 16:9 Widescreen by default, PowerPoint's own
    /// default since 2013 (13.333 x 7.5 in).
    private(set) var slideSize = Size(960, 540)
    private(set) var firstSlideNum = 1
    /// Set Up Slide Show, and the custom shows; both saved with the deck.
    private(set) var show = ShowSettings()
    private(set) var sourceShow: ShowSettings? = nil
    private(set) var customShows: [CustomShow] = []
    /// The deck's sections, in order; empty when it has none.
    private(set) var sections: [SlideSection] = []
    /// Apply to All: the master's background, which every slide without its own shows and every new slide inherits.
    private(set) var masterBackground: SlideFill? = nil
    private(set) var slideScaling: SlideScaling? = nil
    var theme = DeckTheme()
    private(set) var revision = 0
    /// The table pen and the drawing tool (not part of the document: no undo step, nothing saved).
    var tablePen = TablePen()
    /// A pen stroke is down: its edits share one undo step (saved by the first edge that changes something).
    var _penStrokeOpen = false
    var _penStrokeSaved = false
    var tableTool: TableTool = .none { didSet { if tableTool != oldValue { notifyListeners() } } }
    enum TableTool { case none, draw, erase }

    // MARK: View zoom (not part of the document: no undo step, nothing saved)

    /// Pixels per point the editing canvas draws at, or nil to fit the slide
    /// to the window. 96/72 px per point is 100 %.
    private(set) var viewScale: Double? = nil
    /// The scale "fit" gives at the canvas's current size (the canvas writes it).
    var viewFitScale = 0.0
    /// How far a zoomed-in slide is dragged off centre, in pixels.
    private(set) var viewPan = Offset.zero
    static let pxPerPercent = 96.0 / 72.0 / 100.0
    static let zoomSteps: [Double] = [10, 25, 33, 50, 66, 75, 100, 125, 150, 200, 300, 400]

    /// The zoom in percent as drawn now.
    var viewPercent: Int {
        Int(((viewScale ?? viewFitScale) / DeckController.pxPerPercent).rounded())
    }
    var viewIsFit: Bool { viewScale == nil }

    /// Notes Page view: each slide shown as a printed notes page (the slide
    /// above, its notes below). A way of looking, like zoom: no undo, not saved.
    private(set) var notesPageView = false
    func setNotesPageView(_ on: Bool) {
        guard on != notesPageView else { return }
        notesPageView = on
        notifyListeners()
    }

    func notifyViewChanged() { notifyListeners() }

    func fitView() {
        guard viewScale != nil || viewPan != .zero else { return }
        viewScale = nil; viewPan = .zero
        notifyListeners()
    }

    /// A zoom of `percent` (10...400); the slide stays centred unless panned.
    func setViewZoom(percent: Double) {
        let p = max(10, min(400, percent))
        viewScale = p * DeckController.pxPerPercent
        if p <= 100 * viewFitScale / (96.0 / 72.0) { viewPan = .zero }
        notifyListeners()
    }

    /// The next step of the zoom ladder above (or below) the zoom shown now.
    func stepViewZoom(_ direction: Int) {
        let now = Double(viewPercent)
        let next = direction > 0
            ? (DeckController.zoomSteps.first { $0 > now + 0.5 } ?? 400)
            : (DeckController.zoomSteps.last { $0 < now - 0.5 } ?? 10)
        setViewZoom(percent: next)
    }

    /// Ctrl (Cmd) and the wheel: rolled away from the user (a negative delta) zooms in a step, towards the user out. View state: no undo.
    func wheelZoom(_ dy: Double) {
        guard dy != 0 else { return }
        stepViewZoom(dy < 0 ? 1 : -1)
    }

    func panView(dx: Double, dy: Double) {
        guard viewScale != nil else { return }
        viewPan = Offset(viewPan.dx + dx, viewPan.dy + dy)
        notifyListeners()
    }
    /// Moves on every change to the content (not on selection or moving
    /// between slides): what "unsaved" compares against.
    var edits = 0
    /// The file the deck was read from, kept whole so a save can write its
    /// masters, layouts, theme and anything not modelled back untouched.
    private(set) var package: PptxPackage? = nil
    /// Set while Slide Master view is open (see MasterView.swift).
    var masterView: MasterViewState? = nil
    /// Write with our own master, layouts and theme even though the deck
    /// came from a file — set once a theme of ours is applied. The package
    /// still supplies kept objects' parts.
    private(set) var ownTemplates = false
    /// A theme of ours was applied to a deck read from a file: the file's masters
    /// and layouts stay, and its theme part is recoloured with this theme's
    /// colours and fonts on save.
    private(set) var recolourTheme = false
    /// Shapes selected on the current slide, in selection order.
    var selection: [SlideShape] = []
    private var _nextId = 1

    private var _undo: [DeckState] = []
    private var _redo: [DeckState] = []
    private var _session: (state: DeckState, revisions: [ObjectIdentifier: Int])? = nil
    private var _sessionWanted = false
    private static let _undoLimit = 100

    override init() {
        super.init()
        newDeck()
    }

    var currentSlide: Slide { slides[current] }
    var canUndo: Bool { !_undo.isEmpty || _sessionChanged }
    var canRedo: Bool { !_redo.isEmpty }

    // MARK: Deck

    /// A fresh deck: one title slide, and no history.
    func newDeck() {
        for slide in slides { _unwatch(slide) }
        slides = [_makeSlide(.titleSlide)]
        slideSize = Size(960, 540)
        theme = DeckTheme()
        package = nil
        ownTemplates = false
        recolourTheme = false
        current = 0
        selection = []
        _undo = []
        _redo = []
        _session = nil
        _changed()
    }

    /// Replace the deck with one read from a file: its slides, size, theme
    /// and the package to write back through. No history.
    func load(_ state: DeckState, theme: DeckTheme, package: PptxPackage?) {
        for slide in slides { _unwatch(slide) }
        slides = []
        self.theme = theme
        self.package = package
        ownTemplates = package == nil
        recolourTheme = false
        _undo = []
        _redo = []
        _session = nil
        _loading = true
        restore(state)
        _loading = false
        // A glued connector drawn by the file stays as stored until a shape it is glued to moves or Reroute runs.
        for slide in slides {
            for s in slide.shapes where s.keptLine != nil && (s.connStart != nil || s.connEnd != nil) {
                for c in [s.connStart, s.connEnd] {
                    if let c, let t = slide.shapes.first(where: { $0.id == c.shape }) { s.connAnchor[c.shape] = t.frame }
                }
            }
        }
        current = 0
    }
    var _loading = false

    /// How the slides' shapes follow a new slide size (PowerPoint's Maximize and Ensure Fit): both keep each shape's
    /// proportions and put its centre at the same place on the new slide, and scale the text (sizes, line spacing,
    /// indents) by the same factor. Maximize scales by the larger of the two ratios (content may run off the slide),
    /// Ensure Fit by the smaller (everything still fits).
    enum SlideScaling: Equatable { case maximize, ensureFit }

    func setSlideSize(_ size: Size, scaling: SlideScaling = .ensureFit) {
        guard size != slideSize else { return }
        _checkpoint()
        let sx = size.width / slideSize.width
        let sy = size.height / slideSize.height
        let k = Self.slideScale(from: slideSize, to: size, scaling)
        for slide in slides {
            for shape in slide.shapes {
                let f = shape.frame
                let w = f.width * k, h = f.height * k
                shape.frame = Rect.fromLTWH((f.left + f.width / 2) * sx - w / 2, (f.top + f.height / 2) * sy - h / 2, w, h)
                _scaleText(of: shape, by: k)
            }
        }
        slideSize = size
        slideScaling = scaling
        _changed()
    }

    /// The one factor a shape and its text are scaled by.
    static func slideScale(from old: Size, to new: Size, _ scaling: SlideScaling) -> Double {
        let sx = new.width / old.width, sy = new.height / old.height
        return scaling == .maximize ? max(sx, sy) : min(sx, sy)
    }

    /// A shape's text at `k` times its size: the sizes the runs state, the size the shape's own look gives the rest,
    /// line spacing in points, space before and after, indents and the box's margins.
    private func _scaleText(of shape: SlideShape, by k: Double) {
        guard k != 1, let text = shape.text else { return }
        var doc = text.document
        for i in doc.paragraphs.indices {
            doc.paragraphs[i].style.indentLeft *= k
            doc.paragraphs[i].style.indentRight *= k
            doc.paragraphs[i].style.firstLineIndent *= k
            doc.paragraphs[i].style.spaceBefore *= k
            doc.paragraphs[i].style.spaceAfter *= k
            doc.paragraphs[i].style.lineHeightPoints = doc.paragraphs[i].style.lineHeightPoints.map { $0 * k }
            for j in doc.paragraphs[i].runs.indices {
                doc.paragraphs[i].runs[j].style.fontSize = doc.paragraphs[i].runs[j].style.fontSize.map { $0 * k }
            }
        }
        // A table's grid goes with its frame: column widths and any row heights it states.
        for id in Array(doc.tableColumns.keys) { doc.tableColumns[id] = doc.tableColumns[id]?.map { $0 * k } }
        for id in Array(doc.tableStyles.keys) {
            guard var ts = doc.tableStyles[id] else { continue }
            ts.rowHeights = ts.rowHeights.mapValues { $0 * k }
            doc.tableStyles[id] = ts
        }
        text.load(doc)
        shape.insets = EdgeInsets(left: shape.insets.left * k, top: shape.insets.top * k,
                                  right: shape.insets.right * k, bottom: shape.insets.bottom * k)
        if let tt = shape.textTheme {
            let fresh = _textTheme(font: tt.fontFamily ?? theme.bodyFont, size: tt.fontSize * k, color: tt.textColor)
            fresh.listIndent = tt.listIndent * k
            fresh.faceResolver = tt.faceResolver
            fresh.omitsLeadingSpace = tt.omitsLeadingSpace
            fresh.singleLineHeight = tt.singleLineHeight
            fresh.headingColor = tt.headingColor
            shape.textTheme = fresh
        }
    }

    // MARK: Slides

    func select(_ index: Int) {
        let i = max(0, min(slides.count - 1, index))
        slideSelectionIds = []
        guard i != current else { return }
        if let si = sectionIndex(ofSlide: i), sections[si].collapsed { sections[si].collapsed = false }
        current = i
        selection = []
        _changed()
    }

    /// A new slide after the current one. With no layout given it follows
    /// PowerPoint: after the title slide comes Title and Content, otherwise
    /// the current slide's layout repeats.
    @discardableResult
    func addSlide(_ layout: SlideLayoutKind? = nil) -> Slide {
        _checkpoint()
        let base = slides.isEmpty ? SlideLayoutKind.titleSlide : currentSlide.layout
        let kind = layout ?? (base == .titleSlide ? .titleAndContent : base)
        let slide = _makeSlide(kind)
        // Same master, same footer positions.
        if !slides.isEmpty { slide.footerFrames = currentSlide.footerFrames }
        let at = slides.isEmpty ? 0 : current + 1
        slides.insert(slide, at: at)
        _adoptSection(at ..< at + 1)
        current = at
        selection = []
        slideSelectionIds = []
        _changed()
        return slide
    }

    /// A copy of a slide with new ids, its animations aimed at the copies of
    /// its shapes. Not yet in the deck.
    func _cloneSlide(_ source: Slide) -> Slide {
        let shapes = source.shapes.map { _copy($0) }
        let copy = Slide(id: _id(), layout: source.layout, shapes: shapes,
                         notes: _textController(source.notes.document))
        copy.hidden = source.hidden
        copy.section = source.section
        copy.masterRole = source.masterRole
        copy.hideMasterShapes = source.hideMasterShapes
        copy.clrMapOvrXML = source.clrMapOvrXML
        copy.controlsXML = source.controlsXML
        copy.custDataXML = source.custDataXML
        copy.decorations = source.decorations.map { _make(_state($0)) }
        var map: [Int: Int] = [:]
        for (a, b) in zip(source.shapes, shapes) { map[a.id] = b.id }
        copy.animations = source.animations.compactMap { a in
            map[a.shapeId].map { var c = a; c.shapeId = $0; return c }
        }
        copy.transition = source.transition
        copy.footerFrames = source.footerFrames
        copy.layoutPart = source.layoutPart
        copy.commentsFrom = source.commentsFrom ?? source.sourcePart
        return copy
    }

    func duplicateSlide(_ index: Int) {
        guard slides.indices.contains(index) else { return }
        _checkpoint()
        let copy = _cloneSlide(slides[index])
        _watch(copy)
        slides.insert(copy, at: index + 1)
        _adoptSection(index + 1 ..< index + 2)
        current = index + 1
        selection = []
        slideSelectionIds = []
        _changed()
    }

    // MARK: Several slides at once

    /// The slides picked in the thumbnail pane or the sorter, by id (empty
    /// means just the current one). Ids, so a move or an undo cannot leave it
    /// pointing at the wrong slide.
    var slideSelectionIds: Set<Int> = []
    private var _slideAnchor = 0

    /// The picked slides' positions, in order; the current slide is always one.
    var selectedSlides: [Int] {
        var r = slides.indices.filter { slideSelectionIds.contains(slides[$0].id) }
        if !r.contains(current) && slides.indices.contains(current) { r.append(current); r.sort() }
        return r
    }

    /// Click (one slide), shift-click (a range from the last plain click) or
    /// ctrl-click (add or drop one). A view setting, like the zoom: no undo.
    func selectSlide(_ index: Int, extend: Bool = false, toggle: Bool = false) {
        guard slides.indices.contains(index) else { return }
        if extend {
            let lo = min(_slideAnchor, index), hi = max(_slideAnchor, index)
            slideSelectionIds = Set(slides[lo...hi].map(\.id))
            current = index
            selection = []
            _changed()
        } else if toggle {
            var picked = Set(selectedSlides.map { slides[$0].id })
            let id = slides[index].id
            if picked.contains(id) {
                guard picked.count > 1 else { return }
                picked.remove(id)
                slideSelectionIds = picked
                if index == current, let other = selectedSlides.last { current = other }
            } else {
                picked.insert(id)
                slideSelectionIds = picked
                current = index
            }
            _slideAnchor = index
            selection = []
            _changed()
        } else {
            let was = !slideSelectionIds.isEmpty
            slideSelectionIds = []
            _slideAnchor = index
            if index == current { if was { notifyListeners() } } else { select(index) }
        }
    }

    func selectAllSlides() {
        slideSelectionIds = Set(slides.map(\.id))
        notifyListeners()
    }

    /// Delete the picked slides (the deck keeps at least one). One undo step.
    func deleteSelectedSlides() {
        var picked = selectedSlides
        guard !picked.isEmpty, slides.count > 1 else { return }
        if picked.count == slides.count { picked.removeFirst() }
        _checkpoint()
        let keepId = slides[current].id
        for i in picked.reversed() { _unwatch(slides[i]); slides.remove(at: i) }
        current = slides.firstIndex { $0.id == keepId } ?? max(0, min(picked[0], slides.count - 1))
        slideSelectionIds = []
        selection = []
        _changed()
    }

    /// Hide the picked slides, or show them when all are hidden already.
    func toggleHiddenSelected() {
        let picked = selectedSlides
        guard !picked.isEmpty else { return }
        let hide = !picked.allSatisfy { slides[$0].hidden }
        _checkpoint()
        for i in picked { slides[i].hidden = hide }
        _changed()
    }

    /// Move the picked slides as a block so the first of them lands at `to`
    /// (a position in the deck as it will be). One undo step.
    func moveSelectedSlides(to: Int) {
        let picked = selectedSlides
        guard !picked.isEmpty else { return }
        let moving = picked.map { slides[$0] }
        var rest = slides
        for i in picked.reversed() { rest.remove(at: i) }
        let at = max(0, min(rest.count, to))
        var result = rest
        result.insert(contentsOf: moving, at: at)
        guard result.map(\.id) != slides.map(\.id) else { return }
        _checkpoint()
        let keepId = slides[current].id
        slides = result
        _adoptSection(at ..< at + moving.count)
        current = slides.firstIndex { $0.id == keepId } ?? 0
        slideSelectionIds = moving.count > 1 ? Set(moving.map(\.id)) : []
        _changed()
    }

    /// Copies of the picked slides, ready to paste (this deck's own images).
    private(set) var slideClipboard: [Slide] = []
    var canPasteSlides: Bool { !slideClipboard.isEmpty }
    /// What the last slide copy put under `DeckController.slidesMime` on the system clipboard: finding it there
    /// again means the clipboard still holds this deck's slides (see SlidesClipboard.swift).
    private(set) var slideClipboardToken: String? = nil
    /// The last slide paste, for its Paste Options button (SlidesClipboard.swift).
    var _lastSlidesPaste: SlidesPasteRecord? = nil

    /// Copy the picked slides. The system clipboard gets them too, as a deck of their own, so another window or
    /// process can paste them.
    func copySlides() {
        slideClipboard = selectedSlides.map { _cloneSlide(slides[$0]) }
        let token = DeckController.nextShapesToken()
        slideClipboardToken = token
        Clipboard.setData(slidesClipboardData(token: token))
    }

    func cutSlides() {
        copySlides()
        if slides.count > selectedSlides.count { deleteSelectedSlides() }
    }

    /// The clipboard's slides after the last picked one, which become the pick.
    func pasteSlides() {
        guard !slideClipboard.isEmpty else { return }
        _insertSlides(slideClipboard.map { _cloneSlide($0) }, at: (selectedSlides.last ?? current) + 1)
    }

    /// Put `copies` (new slides, not yet in the deck) in at `at`, in one undo step; they become the pick.
    func _insertSlides(_ copies: [Slide], at index: Int) {
        guard !copies.isEmpty else { return }
        _checkpoint()
        var at = max(0, min(slides.count, index))
        let first = at
        for copy in copies { _watch(copy); slides.insert(copy, at: at); at += 1 }
        _adoptSection(first ..< at)
        current = at - 1
        slideSelectionIds = copies.count > 1 ? Set(copies.map(\.id)) : []
        _slideAnchor = first
        selection = []
        _changed()
    }

    /// The slides of another deck (`state`, read in `source`'s theme), made over as slides of this one, not yet
    /// in it. Use Destination Theme: they take this deck's theme, background and fonts, as a new slide would.
    /// Keep Source Formatting: they keep their own look: the background their master gave them is spelled out on
    /// each, their colours stop following a theme, and the master's own shapes stay drawn behind them.
    /// Nothing that names a part of the other file comes along (its layouts, comments, controls, tags).
    func _foreignSlides(_ state: DeckState, theme source: DeckTheme, package: PptxPackage?, way: SlidePasteWay) -> [Slide] {
        let scratch = DeckController()
        scratch.load(state, theme: source, package: package)
        return scratch.slides.map { s in
            let copy = _cloneSlide(s)
            copy.layoutPart = nil
            copy.commentsFrom = nil
            copy.section = nil
            copy.clrMapOvrXML = nil
            copy.controlsXML = nil
            copy.custDataXML = nil
            copy.background = s.background
            switch way {
            case .keepSource:
                if copy.background == nil { copy.background = s.inheritedBackground ?? source.backgroundFill }
                for shape in copy.shapes { shape.fillScheme = nil; shape.outlineScheme = nil }
            default:
                copy.decorations = []
                copy.hideMasterShapes = false
                copy.inheritedBackground = masterBackground
                for shape in copy.shapes { restyleShape(shape, from: source, to: theme) }
            }
            return copy
        }
    }

    /// Duplicate Slide with several picked: copies of all of them, in order, after the last picked one, and the
    /// copies become the pick (as PowerPoint does). One undo step. One picked slide is `duplicateSlide`.
    func duplicateSelectedSlides() {
        let picked = selectedSlides
        guard picked.count > 1 else { return duplicateSlide(current) }
        _checkpoint()
        var at = picked.last! + 1
        let first = at
        let copies = picked.map { _cloneSlide(slides[$0]) }
        for copy in copies { _watch(copy); slides.insert(copy, at: at); at += 1 }
        _adoptSection(first ..< at)
        current = at - 1
        slideSelectionIds = Set(copies.map(\.id))
        _slideAnchor = first
        selection = []
        _changed()
    }

    func deleteSlide(_ index: Int) {
        guard slides.indices.contains(index), slides.count > 1 else { return }
        _checkpoint()
        _unwatch(slides[index])
        slides.remove(at: index)
        if index < current || current >= slides.count { current = max(0, current - 1) }
        selection = []
        slideSelectionIds = []
        _changed()
    }

    // MARK: Outline view

    /// The deck as the Outline view lists it: each slide's title and the paragraphs of its body.
    var outlineEntries: [OutlineEntry] { slides.map { Self._outlineEntry($0) } }

    private static func _outlineEntry(_ slide: Slide) -> OutlineEntry {
        let title = slide.shapes.first { $0.role == .title || $0.role == .ctrTitle }
        let body = slide.shapes.first { $0.role == .body || $0.role == .subTitle }
        var entry = OutlineEntry(title: (title?.text?.document.paragraphs.map(\.text) ?? []).joined(separator: " "), slideId: slide.id)
        for p in body?.text?.document.paragraphs ?? [] where !(p.text.isEmpty && p.image != nil) {
            entry.body.append(OutlineLine(level: p.style.listLevel + 1, text: p.text))
        }
        // A body holding only its one empty paragraph is a slide with no body lines.
        if entry.body.count == 1, entry.body[0].text.isEmpty { entry.body = [] }
        return entry
    }

    /// True while one run of outline typing is being folded into a single undo step.
    private var _outlineOpen = false

    /// The Outline view lost focus or closed: the next outline change is a new undo step.
    func endOutlineEdit() { _outlineOpen = false }

    /// Make the slides match the outline `new`. Slides whose entry did not change are left alone; an edited entry changes only
    /// the text that differs (so its formatting stays); an entry with no slide gets a new Title and Content slide, and a slide
    /// whose entry went is deleted. The whole run of typing is one undo step.
    func applyOutline(_ new: [OutlineEntry]) {
        let old = outlineEntries
        guard old != new, !new.isEmpty else { return }
        let steps = Outline.diff(old: old, new: new)
        if !_outlineOpen { _checkpoint(); _outlineOpen = true }
        let before = slides
        let currentSlide = slides.indices.contains(current) ? slides[current] : nil
        var result: [Slide] = []
        var lastKept: Slide? = nil
        for step in steps {
            switch step {
            case .keep(let o):
                result.append(before[o]); lastKept = before[o]
            case .edit(let o, let n):
                _setOutline(new[n], on: before[o], was: old[o])
                result.append(before[o]); lastKept = before[o]
            case .insert(let n):
                let slide = _makeSlide(.titleAndContent)
                if let ref = lastKept ?? before.first { slide.footerFrames = ref.footerFrames }
                _setOutline(new[n], on: slide, was: OutlineEntry(title: ""))
                result.append(slide)
            case .delete(let o):
                _unwatch(before[o])
            }
        }
        if result.isEmpty { return }
        slides = result
        if let currentSlide, let at = slides.firstIndex(where: { $0 === currentSlide }) { current = at }
        else { current = min(current, slides.count - 1) }
        selection = []
        slideSelectionIds = []
        _changed()
    }

    private func _setOutline(_ entry: OutlineEntry, on slide: Slide, was old: OutlineEntry) {
        if entry.title != old.title, let shape = slide.shapes.first(where: { $0.role == .title || $0.role == .ctrTitle }), let text = shape.text {
            text.load(Self._retext(text.document, [entry.title], levels: nil))
        }
        guard entry.body != old.body else { return }
        var body = slide.shapes.first { $0.role == .body || $0.role == .subTitle }
        if body == nil, !entry.body.isEmpty {
            // A slide with no body placeholder gains one: its layout becomes Title and Content.
            let at = slides.firstIndex { $0 === slide }
            if let at { applyLayout(.titleAndContent, to: at) }
            body = slide.shapes.first { $0.role == .body || $0.role == .subTitle }
        }
        if let text = body?.text {
            text.load(Self._retext(text.document, entry.body.map(\.text), levels: entry.body.map { $0.level - 1 }))
        }
    }

    /// `doc` with its paragraphs replaced by `lines`: a line unchanged from the paragraph at the same place stays as it was
    /// (runs and all); a changed one takes that paragraph's look, or the last one's.
    private static func _retext(_ doc: RichDocument, _ lines: [String], levels: [Int]?) -> RichDocument {
        var out = doc
        out.paragraphs = lines.enumerated().map { i, line in
            let model = doc.paragraphs.indices.contains(i) ? doc.paragraphs[i] : doc.paragraphs.last
            var p = RichParagraph(text: line, style: model?.style ?? .body)
            if let levels { p.style.listLevel = max(0, levels[i]) }
            if let model, model.text == line, model.style.listLevel == p.style.listLevel { return model }
            if !line.isEmpty { p.runs = [Run(length: line.count, style: model?.runs.first?.style ?? .plain)] }
            return p
        }
        if out.paragraphs.isEmpty { out.paragraphs = [RichParagraph(text: "", style: doc.paragraphs.first?.style ?? .body)] }
        return out
    }

    func moveSlide(_ from: Int, to: Int) {
        guard slides.indices.contains(from) else { return }
        let target = max(0, min(slides.count - 1, to))
        guard target != from else { return }
        _checkpoint()
        let slide = slides.remove(at: from)
        slides.insert(slide, at: target)
        _adoptSection(target ..< target + 1)
        current = target
        _changed()
    }

    /// The current slide's transition, or every slide's.
    func setTransition(_ kind: SlideTransition.Kind? = nil, direction: SlideTransition.Direction? = nil,
                       duration: Double? = nil, vertical: Bool? = nil, inward: Bool? = nil, zoomIn: Bool? = nil,
                       advanceOnClick: Bool? = nil, advanceAfter: Double?? = nil, all: Bool = false) {
        _checkpoint()
        for slide in all ? slides : [currentSlide] {
            var t = all ? currentSlide.transition : slide.transition
            if let kind { t.kind = kind }
            if let direction { t.direction = direction }
            if let duration { t.duration = max(0.1, min(10, duration)) }
            if let vertical { t.vertical = vertical }
            if let inward { t.inward = inward }
            if let zoomIn { t.zoomIn = zoomIn }
            if let advanceOnClick { t.advanceOnClick = advanceOnClick }
            if let advanceAfter { t.advanceAfter = advanceAfter.map { max(0, min(86400, $0)) } }
            // (Advance Slide alone leaves a transition this app cannot draw as it was read.)
            if kind != nil || direction != nil || duration != nil || vertical != nil || inward != nil || zoomIn != nil { t.raw = nil }
            slide.transition = t
        }
        _changed()
    }

    /// A custom show played from the Custom Shows dialog, for this one run: the file's range is not touched.
    private(set) var playingCustom: Int? = nil
    func playCustomShow(_ id: Int?) { playingCustom = id }

    /// Rehearse Timings kept: each rehearsed slide advances after the seconds it was on screen
    /// (by deck index), and the show goes by timings. One undo step.
    func applyRehearsal(_ times: [Int: Double]) {
        guard !times.isEmpty else { return }
        _checkpoint()
        for (i, t) in times where slides.indices.contains(i) {
            slides[i].transition.advanceAfter = max(0.1, (t * 10).rounded() / 10)
        }
        show.useTimings = true
        _changed()
    }

    func setShow(_ settings: ShowSettings) {
        guard settings != show else { return }
        _checkpoint()
        show = settings
        _changed()
    }

    /// Replace the custom shows (Custom Shows dialog: new, edit, copy, delete).
    /// A show the range pointed at, now gone, sends the range back to all slides.
    func setCustomShows(_ shows: [CustomShow]) {
        guard shows != customShows else { return }
        _checkpoint()
        customShows = shows
        if case .custom(let id) = show.range, !shows.contains(where: { $0.id == id }) { show.range = .all }
        _changed()
    }

    /// The slide indices the show plays, in order: the range (all, from-to,
    /// or a custom show's own order) with hidden slides left out. A custom
    /// show plays a hidden slide it lists, as PowerPoint does.
    func showOrder() -> [Int] {
        switch playingCustom.map({ ShowSettings.Range.custom($0) }) ?? show.range {
        case .all: return slides.indices.filter { !slides[$0].hidden }
        case .slides(let from, let to):
            let lo = max(1, min(from, to)), hi = min(slides.count, max(from, to))
            guard lo <= hi else { return [] }
            return (lo - 1 ..< hi).filter { !slides[$0].hidden }
        case .custom(let id):
            guard let cs = customShows.first(where: { $0.id == id }) else { return slides.indices.filter { !slides[$0].hidden } }
            return cs.slides.compactMap { sid in slides.firstIndex { $0.id == sid && !$0.hidden } }
        }
    }

    // MARK: Sections

    /// The slides just put at `range` join the section of the slide before them (the one after, at the top of the deck). Does nothing while the deck has no sections.
    private func _adoptSection(_ range: Range<Int>) {
        guard !sections.isEmpty, !range.isEmpty else { return }
        let tag: String? = range.lowerBound > 0 ? slides[range.lowerBound - 1].section
            : (range.upperBound < slides.count ? slides[range.upperBound].section : sections[0].guid)
        for i in range { slides[i].section = tag ?? sections[0].guid }
    }

    /// The slide indices in section `index`.
    func slides(inSection index: Int) -> [Int] {
        guard sections.indices.contains(index) else { return [] }
        return slides.indices.filter { slides[$0].section == sections[index].guid }
    }

    /// The index of the section the slide at `slide` is in.
    func sectionIndex(ofSlide slide: Int) -> Int? {
        guard slides.indices.contains(slide), let g = slides[slide].section else { return nil }
        return sections.firstIndex { $0.guid == g }
    }

    /// Start a new section at slide `index`: it takes that slide and the rest of its section. The first section a deck gets also makes a "Default Section" for any slides before it.
    func addSection(at index: Int, name: String = "Untitled Section", guid: String = DeckController.newSectionGuid()) {
        guard slides.indices.contains(index) else { return }
        _checkpoint()
        if sections.isEmpty {
            let first = SlideSection(guid: DeckController.newSectionGuid(), name: "Default Section")
            sections = [first]
            for s in slides { s.section = first.guid }
        }
        guard let si = sectionIndex(ofSlide: index) else { return }
        // At the first slide of a section the old one is left empty; PowerPoint keeps it, so do we.
        let run = slides(inSection: si)
        let moved = run.filter { $0 >= index }
        sections.insert(SlideSection(guid: guid, name: name), at: si + 1)
        for i in moved { slides[i].section = guid }
        _changed()
    }

    func renameSection(_ index: Int, to name: String) {
        guard sections.indices.contains(index) else { return }
        let n = name.trimmingWhitespace()
        guard !n.isEmpty, n != sections[index].name else { return }
        _checkpoint()
        sections[index].name = n
        _changed()
    }

    /// Remove the section and keep its slides: they join the section before it (the one after, for the first). The last section going leaves a deck with none.
    func removeSection(_ index: Int) {
        guard sections.indices.contains(index) else { return }
        _checkpoint()
        let gone = sections.remove(at: index)
        if sections.isEmpty {
            for s in slides { s.section = nil }
        } else {
            let into = sections[max(0, index - 1)].guid
            for s in slides where s.section == gone.guid { s.section = into }
        }
        _changed()
    }

    func removeAllSections() {
        guard !sections.isEmpty else { return }
        _checkpoint()
        sections = []
        for s in slides { s.section = nil }
        _changed()
    }

    /// Remove the section and its slides (the deck keeps at least one slide).
    func removeSectionAndSlides(_ index: Int) {
        guard sections.indices.contains(index) else { return }
        let run = slides(inSection: index)
        guard run.count < slides.count else { return }
        _checkpoint()
        let keepId = slides[current].id
        for i in run.reversed() { _unwatch(slides[i]); slides.remove(at: i) }
        sections.remove(at: index)
        current = slides.firstIndex { $0.id == keepId } ?? max(0, min(run[0], slides.count - 1))
        slideSelectionIds = []
        selection = []
        _changed()
    }

    /// Move section `index` up or down one place, its slides with it.
    func moveSection(_ index: Int, by delta: Int) {
        let to = index + delta
        guard sections.indices.contains(index), sections.indices.contains(to), delta != 0 else { return }
        _checkpoint()
        let keepId = slides[current].id
        var groups = sections.map { sec in slides.filter { $0.section == sec.guid } }
        let sec = sections.remove(at: index), grp = groups.remove(at: index)
        sections.insert(sec, at: to)
        groups.insert(grp, at: to)
        slides = groups.flatMap { $0 }
        current = slides.firstIndex { $0.id == keepId } ?? 0
        _changed()
    }

    func setSectionCollapsed(_ index: Int, _ collapsed: Bool) {
        guard sections.indices.contains(index), sections[index].collapsed != collapsed else { return }
        sections[index].collapsed = collapsed
        notifyListeners()
    }

    /// Collapse All / Expand All.
    func setAllSectionsCollapsed(_ collapsed: Bool) {
        guard sections.contains(where: { $0.collapsed != collapsed }) else { return }
        for i in sections.indices { sections[i].collapsed = collapsed }
        notifyListeners()
    }

    /// A section id as PowerPoint writes it: a braced upper-case GUID.
    static func newSectionGuid() -> String {
        func hex(_ n: Int) -> String { (0 ..< n).map { _ in String(Int.random(in: 0 ..< 16), radix: 16, uppercase: true) }.joined() }
        return "{\(hex(8))-\(hex(4))-4\(hex(3))-A\(hex(3))-\(hex(12))}"
    }

    func toggleHidden(_ index: Int) {
        guard slides.indices.contains(index) else { return }
        _checkpoint()
        slides[index].hidden.toggle()
        _changed()
    }

    /// Re-lay a slide onto another layout. Text moves by role and order:
    /// the title stays the title, the n-th body the n-th body; a body the
    /// new layout has no room for keeps its text in a placeholder of its own
    /// at the old position, as PowerPoint does.
    func applyLayout(_ layout: SlideLayoutKind, to index: Int) {
        guard slides.indices.contains(index) else { return }
        let slide = slides[index]
        guard slide.layout != layout else { return }
        _checkpoint()
        _relay(slide, onto: layout.placeholders.map { _makeShape($0) })
        slide.layout = layout
        _changed()
    }

    /// Lay a slide's placeholders onto `fresh` (the new layout's empty ones).
    private func _relay(_ slide: Slide, onto fresh: [SlideShape]) {
        let old = slide.shapes
        var oldTitle = old.first { $0.role == .title || $0.role == .ctrTitle }
        var oldBodies = old.filter { $0.role == .body || $0.role == .subTitle }
        var next: [SlideShape] = []
        for shape in fresh {
            let isTitle = shape.role == .title || shape.role == .ctrTitle
            let donor: SlideShape?
            if isTitle { donor = oldTitle; oldTitle = nil } else { donor = oldBodies.isEmpty ? nil : oldBodies.removeFirst() }
            if let donor, !donor.isEmptyText, let text = donor.text, let target = shape.text {
                target.load(text.document)
            }
            next.append(shape)
        }
        // Leftovers with text survive where they were; empty ones go.
        for shape in ([oldTitle].compactMap { $0 } + oldBodies) where !shape.isEmptyText {
            next.append(shape)
        }
        // Everything that is not a placeholder (text boxes, shapes,
        // pictures) stays on top, untouched.
        next.append(contentsOf: old.filter { $0.role == nil })
        for shape in old where !next.contains(where: { $0 === shape }) { _unwatch(shape) }
        slide.shapes = next
        for shape in next { _watch(shape) }
        selection = []
    }

    /// The layouts the file itself carries (empty for a deck of ours).
    var fileLayouts: [FileLayout] { package?.fileLayouts() ?? [] }

    /// Put a slide on one of the file's own layouts (`FileLayout.part`), or,
    /// with the slide's own layout part, put the layout's frames back (Reset).
    /// Rule: placeholders take the layout's position, size and look; the text,
    /// its runs and lists, and every non-placeholder shape stay; a placeholder
    /// the layout has and the slide lacks comes back empty. One undo step.
    @discardableResult
    func applyFileLayout(_ part: String, to index: Int) -> Bool {
        guard slides.indices.contains(index), let package,
              let preview = PptxReader.layoutPreview(package, layout: part) else { return false }
        _checkpoint()
        let slide = slides[index]
        let fresh: [SlideShape] = preview.shapes.filter { if case .placeholder = $0.kind { return true } else { return false } }.map { st in
            var st = st
            st.id = _id()
            st.sourceXML = nil; st.readShape = nil; st.sourcePart = nil; st.fileId = nil
            return _make(st)
        }
        _relay(slide, onto: fresh)
        slide.layoutPart = part
        slide.layout = preview.layout
        slide.decorations = preview.decorations.map { _make($0) }
        slide.inheritedBackground = preview.inheritedBackground
        _changed()
        return true
    }

    // MARK: Selection

    func selectShapes(_ shapes: [SlideShape]) {
        let mine = shapes.filter { s in currentSlide.shapes.contains { $0 === s } }
        guard mine.count != selection.count || zip(mine, selection).contains(where: { $0 !== $1 }) else { return }
        selection = mine
        if mine.count == 1, let one = mine.first { ScreenReader.announce(spokenShape(one)) }
        _notify()
    }

    /// What a screen reader says when a shape is selected: its name, what it is, the start of its text (or its alt
    /// text), where it sits on the slide, and its place in the Tab order: "Title 1, title, Quarterly review,
    /// top centre, 1 of 3".
    func spokenShape(_ s: SlideShape) -> String {
        var kind: String
        switch s.kind {
        case .placeholder(let r): kind = r == .body ? "content placeholder" : r == .subTitle ? "subtitle" : "title"
        case .textBox: kind = "text box"
        case .geometry: kind = "shape"
        case .picture: kind = "picture"
        case .table: kind = "table"
        case .chart: kind = "chart"
        case .opaque: kind = "object"
        }
        var parts = [s.name.isEmpty ? kind : s.name, kind]
        if let alt = s.altText, !alt.isEmpty { parts.append(alt) }
        else if let t = s.text, s.kind != .table {
            let words = t.document.paragraphs.map { $0.text }.joined(separator: " ").split(separator: " ", omittingEmptySubsequences: true)
            if !words.isEmpty { parts.append(words.prefix(8).joined(separator: " ") + (words.count > 8 ? "…" : "")) }
        }
        let cx = (s.frame.left + s.frame.width / 2) / max(slideSize.width, 1)
        let cy = (s.frame.top + s.frame.height / 2) / max(slideSize.height, 1)
        let v = cy < 1.0 / 3 ? "top" : cy > 2.0 / 3 ? "bottom" : "middle"
        let h = cx < 1.0 / 3 ? "left" : cx > 2.0 / 3 ? "right" : "centre"
        parts.append(v == "middle" && h == "centre" ? "centre" : v == "middle" ? h : h == "centre" ? v : v + " " + h)
        if let i = currentSlide.shapes.firstIndex(where: { $0 === s }) { parts.append("\(i + 1) of \(currentSlide.shapes.count)") }
        return parts.joined(separator: ", ")
    }

    /// Shift/Ctrl+click: `shape` joins the selection, or leaves it when it is
    /// already in. Selection only (not an edit, so not an undo step).
    func toggleSelected(_ shape: SlideShape) {
        if isSelected(shape) { selectShapes(selection.filter { $0 !== shape }) }
        else { selectShapes(selection + [shape]) }
    }

    /// `shapes` added to the selection (those already in it stay where they are).
    func addToSelection(_ shapes: [SlideShape]) {
        selectShapes(selection + shapes.filter { s in !isSelected(s) })
    }

    func isSelected(_ shape: SlideShape) -> Bool { selection.contains { $0 === shape } }

    /// "Select Multiple" (the touch stand-in for holding Shift or Ctrl): while on, a tap on a shape adds it to the selection or,
    /// if it is in already, removes it, and a tap on the empty slide keeps the selection. A mode of the view, not an edit.
    private(set) var selectMultiple = false

    func setSelectMultiple(_ on: Bool) {
        guard on != selectMultiple else { return }
        selectMultiple = on
        _notify()
    }

    // MARK: Shapes

    /// The text theme and paragraph style of a text box made here: the deck's text-box defaults (`DeckTheme.textBoxFont`
    /// and the rest), else the theme's body font at 18 pt in its text colour, left aligned.
    func _textBoxLook() -> (theme: RichTextTheme, style: RichParagraphStyle, size: Double) {
        let size = theme.textBoxSize ?? 18
        let look = _textTheme(font: theme.textBoxFont ?? theme.bodyFont, size: size, color: theme.textBoxColor ?? theme.text)
        var style = RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0)
        switch theme.textBoxAlign {
        case "ctr": style.alignment = .center
        case "r": style.alignment = .right
        case "just": style.alignment = .justify
        default: break
        }
        return (look, style, size)
    }

    /// Plain text pasted onto the slide: a text box holding it, one paragraph a line, with its top left at `at` (where
    /// the shapes it was copied from were) or else in the middle of the slide.
    @discardableResult func addTextBox(text: String, at: Rect? = nil) -> SlideShape {
        _checkpoint()
        let (theme, style, size) = _textBoxLook()
        let lines = text.replacingAll("\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        let h = (Double(lines.count) * size * 1.2 + 7.2).rounded(.up)
        var w = (slideSize.width * 0.6).rounded()
        var frame = Rect.fromLTWH(((slideSize.width - w) / 2).rounded(), max(0, ((slideSize.height - h) / 2).rounded()), w, h)
        if let at {
            if at.width >= 72 { w = at.width }
            frame = Rect.fromLTWH(at.left, at.top, w, h)
        }
        let shape = SlideShape(id: _id(), name: "TextBox \(_nextId)", kind: .textBox, frame: frame,
                               text: _textController(RichDocument(paragraphs: lines.map { RichParagraph(text: String($0), style: style) })),
                               textTheme: theme)
        // It sizes itself to its text (spAutoFit), as PowerPoint's text boxes do: lines that wrap make it taller.
        if let fitted = SlideTextCache.fittedHeight(shape) { shape.frame = Rect.fromLTWH(frame.left, frame.top, w, fitted) }
        currentSlide.shapes.append(shape)
        _watch(shape)
        selection = [shape]
        _changed()
        return shape
    }

    /// Whether `shape`'s box follows its text's height (spAutoFit; a text box that states no fit does too).
    static func resizesToText(_ s: SlideShape) -> Bool {
        !s.autofit && (s.fitRule == "a:spAutoFit" || (s.fitRule == nil && s.kind == .textBox))
    }

    func addTextBox(at frame: Rect) -> SlideShape {
        _checkpoint()
        let (theme, style, _) = _textBoxLook()
        let shape = SlideShape(id: _id(), name: "TextBox \(_nextId)", kind: .textBox, frame: frame,
                               text: _textController(RichDocument(paragraphs: [RichParagraph(text: "", style: style)])),
                               textTheme: theme)
        currentSlide.shapes.append(shape)
        _watch(shape)
        selection = [shape]
        _changed()
        return shape
    }

    /// A drawn shape from the gallery, centred on the slide, in the theme's
    /// first accent with white text — PowerPoint's default look.
    /// A shape chosen from the gallery: the next drag on the slide draws it, a click places it one inch square.
    private(set) var pendingInsert: ShapePreset? = nil

    func beginInsert(_ preset: ShapePreset) { pendingInsert = preset; notifyListeners() }
    func cancelInsert() { if pendingInsert != nil { pendingInsert = nil; notifyListeners() } }

    /// The drag that draws the pending shape ended: its box runs from `a` to `b` (a square or a 45-degree line with
    /// `keepProportions`); a click, with nothing dragged, drops a 1 in (72 pt) box with its corner there.
    @discardableResult
    func placeInsert(_ preset: ShapePreset, from a: Offset, to b: Offset, keepProportions: Bool) -> SlideShape {
        pendingInsert = nil
        var b = b
        let dragged = abs(b.dx - a.dx) >= 4 || abs(b.dy - a.dy) >= 4
        if preset.isElbow {
            if !dragged { b = Offset(a.dx + 96, a.dy + 48) }
            else if keepProportions { b = Offset(b.dx, a.dy + (b.dy < a.dy ? -1 : 1) * abs(b.dx - a.dx)) }
            return addShape(preset, frame: nil, ends: (a, b))
        }
        if !dragged { b = Offset(a.dx + (preset.isLine ? 72 : 72), a.dy + (preset.isLine ? 0 : 72)) }
        else if keepProportions {
            if preset.isLine {
                let l = ((b.dx - a.dx) * (b.dx - a.dx) + (b.dy - a.dy) * (b.dy - a.dy)).squareRoot()
                let ang = ((atan2(b.dy - a.dy, b.dx - a.dx)) / (Double.pi / 4)).rounded() * (Double.pi / 4)
                b = Offset(a.dx + l * cos(ang), a.dy + l * sin(ang))
            } else {
                let side = max(abs(b.dx - a.dx), abs(b.dy - a.dy))
                b = Offset(a.dx + (b.dx < a.dx ? -side : side), a.dy + (b.dy < a.dy ? -side : side))
            }
        }
        let frame = preset.isLine ? Rect.fromLTRB(a.dx, a.dy, b.dx, b.dy)
                                  : Rect.fromLTRB(min(a.dx, b.dx), min(a.dy, b.dy), max(a.dx, b.dx), max(a.dy, b.dy))
        return addShape(preset, frame: frame)
    }

    @discardableResult
    func addShape(_ preset: ShapePreset, frame given: Rect? = nil, ends: (Offset, Offset)? = nil) -> SlideShape {
        _checkpoint()
        pendingInsert = nil
        let w = preset.isLine ? 192.0 : 144.0
        let h = preset.isLine ? 0.0 : (preset == .rightArrow ? 72.0 : 108.0)
        let frame = given ?? Rect.fromLTWH((slideSize.width - w) / 2, (slideSize.height - h) / 2, w, h)
        let accent = self.theme.accents[0]
        let theme = _textTheme(font: self.theme.bodyFont, size: 18, color: Color(0xFFFFFFFF))
        let style = RichParagraphStyle(alignment: .center, spaceAfter: 0, lineSpacing: 1.0)
        let open = preset.isOpenPath
        let shape = SlideShape(id: _id(), name: "\(preset.name) \(_nextId)", kind: .geometry(preset), frame: frame,
                               text: preset.isLine || preset.isElbow ? nil
                                   : _textController(RichDocument(paragraphs: [RichParagraph(text: "", style: style)])),
                               textTheme: preset.isLine || preset.isElbow ? nil : theme, anchor: .middle)
        shape.fill = open ? nil : accent
        // PowerPoint's default shape style: accent1 fill, an accent1 shade 50%
        // outline (a line takes plain accent1), saved as the style's refs.
        shape.outline = open ? accent : Self.shadeLinear(accent, 0.5)
        shape.fillScheme = "accent1"
        shape.themeStyle = true
        shape.outlineWidth = open ? 1.5 : 1
        if preset.rawValue == "straightConnector1" { shape.tailEnd = LineEnd(kind: "triangle", width: 3, length: 3) }
        if preset.isElbow {
            let c = Offset(slideSize.width / 2, slideSize.height / 2)
            let e = ends ?? (Offset(c.dx - 72, c.dy - 36), Offset(c.dx + 72, c.dy + 36))
            shape.apply(ElbowRoute.make(from: e.0, to: e.1, leaving: nil, arriving: nil, curved: preset.rawValue.hasPrefix("curved")))
        }
        currentSlide.shapes.append(shape)
        _watch(shape)
        selection = [shape]
        _changed()
        return shape
    }

    /// A picture, centred, at its natural size shrunk to fit four fifths of
    /// the slide.
    @discardableResult
    /// A picture in the middle of the slide, or filling `at` (a picture of copied shapes, where they were).
    func addPicture(_ image: ImageAttachment, naturalSize: Size, at: Rect? = nil) -> SlideShape {
        _checkpoint()
        var w = naturalSize.width, h = naturalSize.height
        let fit = min(1, slideSize.width * 0.8 / max(w, 1), slideSize.height * 0.8 / max(h, 1))
        w *= fit; h *= fit
        let shape = SlideShape(id: _id(), name: "Picture \(_nextId)", kind: .picture(image),
                               frame: at ?? Rect.fromLTWH((slideSize.width - w) / 2, (slideSize.height - h) / 2, w, h),
                               text: nil, textTheme: nil)
        currentSlide.shapes.append(shape)
        selection = [shape]
        _changed()
        return shape
    }

    /// A sound or movie: its poster frame as the picture, the file riding along.
    @discardableResult
    func addMedia(_ clip: MediaClip, poster: ImageAttachment, size: Size) -> SlideShape {
        let shape = addPicture(poster, naturalSize: size)
        // A second clip does not land on the first: step down and right, as a duplicate does, until the centre is free.
        let others = currentSlide.shapes.filter { $0 !== shape }
        var step = 0.0
        let cx = shape.frame.left + shape.frame.width / 2, cy = shape.frame.top + shape.frame.height / 2
        while step < 18 * 20, others.contains(where: {
            abs($0.frame.left + $0.frame.width / 2 - cx - step) < 1 && abs($0.frame.top + $0.frame.height / 2 - cy - step) < 1 }) { step += 18 }
        if step > 0 { shape.frame = shape.frame.shift(Offset(step, step)) }
        shape.name = (clip.isVideo ? "Video " : "Audio ") + "\(_nextId)"
        shape.media = clip
        shape.altText = clip.name
        return shape
    }

    /// A clip's real first frame takes the place of its generic poster (one undo step is not spent on it).
    func replacePoster(_ shape: SlideShape, png: Data, width: Int, height: Int, frame: Rect) {
        guard case .picture(let old) = shape.kind else { return }
        // A new attachment, so a new id: the painter caches decoded pictures by id and would keep the old poster.
        let image = ImageAttachment(data: png, width: Double(width), height: Double(height), name: old.name,
                                    naturalWidth: Double(width), naturalHeight: Double(height))
        shape.kind = .picture(image)
        shape.frame = frame
        _changed()
    }

    // MARK: Animations

    /// The current slide's animations can be edited here (not kept as the
    /// file had them).
    var canAnimate: Bool { !currentSlide.animationsKept }

    /// The selected shapes' entrance animations, in slide order.
    var selectedAnimations: [ShapeAnimation] {
        currentSlide.animations.filter { a in selection.contains { $0.id == a.shapeId } }
    }

    /// The gallery: each selected shape gets `effect` (nil takes its
    /// animation away) — every paragraph of a build by paragraph — keeping
    /// its place, start and timing; a shape without one goes to the end, on
    /// a click.
    func setEntrance(_ effect: ShapeAnimation.Effect?) {
        guard canAnimate, !selection.isEmpty else { return }
        _checkpoint()
        let slide = currentSlide
        for shape in selection {
            let mine = slide.animations.indices.filter { slide.animations[$0].shapeId == shape.id }
            guard !mine.isEmpty else {
                if let effect { slide.animations.append(ShapeAnimation(shapeId: shape.id, effect: effect)) }
                continue
            }
            guard let effect else {
                slide.animations.removeAll { $0.shapeId == shape.id }
                continue
            }
            for i in mine {
                let was = slide.animations[i].effect
                slide.animations[i].effect = effect
                if was == .appear || effect == .appear { slide.animations[i].duration = effect.defaultDuration }
            }
        }
        _changed()
    }

    /// Effect Options → Sequence: the selected text shapes' entrances as
    /// one object, or a paragraph at a time (the first as the shape's
    /// start, the rest on clicks), as PowerPoint offers it.
    func setByParagraph(_ on: Bool) {
        guard canAnimate else { return }
        let slide = currentSlide
        let shapes = selection.filter { s in s.text != nil && slide.animations.contains { $0.shapeId == s.id } }
        guard !shapes.isEmpty else { return }
        _checkpoint()
        for shape in shapes {
            guard let at = slide.animations.firstIndex(where: { $0.shapeId == shape.id }) else { continue }
            let first = slide.animations[at]
            slide.animations.removeAll { $0.shapeId == shape.id }
            var entries: [ShapeAnimation] = []
            if on {
                let paras = shape.text?.document.paragraphs ?? []
                for (i, p) in paras.enumerated() where !p.text.isEmpty {
                    var a = first
                    a.paragraph = i
                    if !entries.isEmpty { a.start = .onClick; a.delay = 0 }
                    entries.append(a)
                }
            }
            if entries.isEmpty { var a = first; a.paragraph = nil; entries = [a] }
            slide.animations.insert(contentsOf: entries, at: min(at, slide.animations.count))
        }
        _changed()
    }

    /// Whether the selection's text comes in a paragraph at a time.
    var selectionByParagraph: Bool {
        selectedAnimations.contains { $0.paragraph != nil }
    }

    /// Change the selected shapes' animations: start, direction, timing.
    func editAnimations(_ edit: (inout ShapeAnimation) -> Void) {
        guard canAnimate, !selectedAnimations.isEmpty else { return }
        _checkpoint()
        let slide = currentSlide
        for i in slide.animations.indices where selection.contains(where: { $0.id == slide.animations[i].shapeId }) {
            edit(&slide.animations[i])
        }
        _changed()
    }

    /// Move animation `index` of the current slide one place earlier (-1)
    /// or later (+1).
    func moveAnimation(_ index: Int, by step: Int) {
        let slide = currentSlide
        let to = index + step
        guard canAnimate, slide.animations.indices.contains(index), slide.animations.indices.contains(to) else { return }
        _checkpoint()
        slide.animations.swapAt(index, to)
        _changed()
    }

    func removeAnimation(_ index: Int) {
        let slide = currentSlide
        guard canAnimate, slide.animations.indices.contains(index) else { return }
        _checkpoint()
        slide.animations.remove(at: index)
        _changed()
    }

    // MARK: Find

    /// Replace every occurrence of `query` in the deck's text — shapes,
    /// tables and notes — as one undo step; returns how many.
    @discardableResult
    func replaceEverywhere(_ query: String, with replacement: String) -> Int {
        let count = matches(query).count
        guard count > 0 else { return 0 }
        _checkpoint()
        for i in slides.indices {
            for body in textStops(i) { body.controller.replaceAll(query, with: replacement) }
        }
        _changed()
        return count
    }

    /// Replace every match of `pattern` in the deck's text (shapes, tables, notes) as one undo step; returns how many.
    @discardableResult
    func replaceEverywhere(_ pattern: TextPattern, with template: String) -> Int {
        let count = matches(pattern).count
        guard count > 0 else { return 0 }
        _checkpoint()
        for i in slides.indices {
            for body in textStops(i) { body.controller.replaceAll(pattern, with: template) }
        }
        _changed()
        return count
    }

    // MARK: Header and footer

    /// PowerPoint's Header & Footer settings for slides.
    struct HeaderFooter: Equatable {
        var date = false
        /// The date as fixed text; nil updates automatically (a field).
        var fixedDate: String? = nil
        var slideNumber = false
        /// Footer text; nil for none.
        var footer: String? = nil
        var skipTitleSlides = false
    }

    static let footerTypes = ["dt", "ftr", "sldNum"]

    /// What `slide` shows now: where the dialog starts.
    func headerFooter(of slide: Slide) -> HeaderFooter {
        var hf = HeaderFooter()
        for shape in slide.shapes {
            switch shape.phType {
            case "dt":
                hf.date = true
                if shape.field == nil { hf.fixedDate = shape.text?.document.plainText() ?? "" }
            case "ftr": hf.footer = shape.text?.document.plainText() ?? ""
            case "sldNum": hf.slideNumber = true
            default: break
            }
        }
        hf.skipTitleSlides = slides.contains { $0.layout == .titleSlide }
            && slides.filter { $0.layout == .titleSlide }.allSatisfy { s in !s.shapes.contains { Self.footerTypes.contains($0.phType ?? "") } }
            && slides.contains { s in s.shapes.contains { Self.footerTypes.contains($0.phType ?? "") } }
        return hf
    }

    /// Date, footer and slide number placed (or taken away) on the current
    /// slide or every slide, where the slide's layout keeps them. One undo
    /// step.
    func applyHeaderFooter(_ hf: HeaderFooter, toAll: Bool) {
        _checkpoint()
        let targets = toAll ? slides : [currentSlide]
        for slide in targets {
            let removed = slide.shapes.filter { Self.footerTypes.contains($0.phType ?? "") }
            for shape in removed { _unwatch(shape) }
            slide.shapes.removeAll { Self.footerTypes.contains($0.phType ?? "") }
            if hf.skipTitleSlides && slide.layout == .titleSlide { continue }
            var add: [SlideShape] = []
            if hf.date {
                let field = hf.fixedDate == nil ? SlideField(type: "datetime1", id: SlideField.newId()) : nil
                add.append(_footerShape("dt", text: hf.fixedDate ?? "", field: field, slide: slide))
            }
            if let text = hf.footer { add.append(_footerShape("ftr", text: text, field: nil, slide: slide)) }
            if hf.slideNumber {
                add.append(_footerShape("sldNum", text: "", field: SlideField(type: "slidenum", id: SlideField.newId()), slide: slide))
            }
            for shape in add { _watch(shape) }
            slide.shapes += add
        }
        selection = selection.filter { s in slides.contains { $0.shapes.contains { $0 === s } } }
        _changed()
    }

    /// PowerPoint's own positions on a 16:9 slide, scaled to this one.
    private func _footerFrame(_ type: String, slide: Slide) -> Rect {
        if let f = slide.footerFrames[type] { return f }
        let sx = slideSize.width / 960, sy = slideSize.height / 540
        let left: Double, width: Double
        switch type {
        case "dt": left = 66; width = 216
        case "ftr": left = 318; width = 324
        default: left = 678; width = 216
        }
        return Rect.fromLTWH(left * sx, 500.5 * sy, width * sx, 28.75 * sy)
    }

    private func _footerShape(_ type: String, text: String, field: SlideField?, slide: Slide) -> SlideShape {
        let align: ParagraphAlignment = type == "dt" ? .left : type == "ftr" ? .center : .right
        let style = RichParagraphStyle(alignment: align, spaceBefore: 0, spaceAfter: 0, lineSpacing: 0.9)
        let doc = RichDocument(paragraphs: [RichParagraph(text: text, style: style)])
        let name = type == "dt" ? "Date Placeholder" : type == "ftr" ? "Footer Placeholder" : "Slide Number Placeholder"
        let shape = SlideShape(id: _id(), name: "\(name) \(_nextId)", kind: .placeholder(.body),
                               frame: _footerFrame(type, slide: slide), text: _textController(doc),
                               textTheme: _textTheme(font: theme.bodyFont, size: 12, color: theme.subtle),
                               anchor: .middle)
        shape.phType = type
        shape.phIdx = type == "dt" ? "10" : type == "ftr" ? "11" : "12"
        shape.field = field
        return shape
    }

    // MARK: Charts

    /// A chart of `type` on PowerPoint's sample data, centred, three fifths
    /// of the slide each way.
    @discardableResult
    func addChart(_ type: ChartType) -> SlideShape {
        _checkpoint()
        let w = (slideSize.width * 0.6).rounded(), h = (slideSize.height * 0.6).rounded()
        let shape = SlideShape(id: _id(), name: "Chart \(_nextId)", kind: .chart(.sample(type)),
                               frame: Rect.fromLTWH(((slideSize.width - w) / 2).rounded(), ((slideSize.height - h) / 2).rounded(), w, h),
                               text: nil, textTheme: nil)
        currentSlide.shapes.append(shape)
        selection = [shape]
        _changed()
        return shape
    }

    /// The one selected chart, for the Chart Design tab and the data grid.
    /// Whether the selection holds a shape that PowerPoint's Shape Format tab acts on: a drawn shape, a
    /// placeholder or a text box (pictures, tables and charts have their own tabs).
    var selectionHasShape: Bool {
        selection.contains { s in
            switch s.kind {
            case .placeholder, .textBox, .geometry: return true
            default: return false
            }
        }
    }

    var selectedChart: SlideShape? {
        selection.count == 1 && selection[0].chart != nil ? selection[0] : nil
    }

    private var _chartEdit: (key: String, at: Int)? = nil

    /// A chart's data or settings replaced: one undo step — or, with
    /// `coalesce`, one step for a run of edits with the same key and nothing
    /// in between (typing into one cell of the data grid).
    func setChart(_ shape: SlideShape, _ chart: Chart, coalesce key: String? = nil) {
        guard shape.chart != nil, shape.chart != chart else { return }
        if let key, let last = _chartEdit, last.key == key, last.at == edits {
            edits += 1
        } else {
            _checkpoint()
        }
        _chartEdit = key.map { ($0, edits) }
        shape.kind = .chart(chart)
        _changed()
    }

    /// The selected pictures back to their natural proportions (the width
    /// kept), and uncropped.
    func resetPictures() {
        let pics = selection.filter { $0.picture != nil }
        guard !pics.isEmpty else { return }
        _checkpoint()
        for s in pics {
            guard let img = s.picture else { continue }
            s.crop = nil
            if let nw = img.naturalWidth, let nh = img.naturalHeight, nw > 0 {
                s.frame = Rect.fromLTWH(s.frame.left, s.frame.top, s.frame.width, s.frame.width * nh / nw)
            }
        }
        _changed()
    }

    /// Change Picture: the selected pictures show `image` instead, at its own proportions, as large as fits in the old
    /// frame and centred on it (PowerPoint keeps the picture's place and size this way). The crop goes, since it cut the
    /// old picture; outline, effects, alt text and animations stay. One undo step.
    func changePictures(to image: ImageAttachment) {
        let pics = selection.filter { $0.picture != nil }
        guard !pics.isEmpty else { return }
        _checkpoint()
        let nw = image.naturalWidth ?? image.width, nh = image.naturalHeight ?? image.height
        for s in pics {
            s.kind = .picture(image)
            s.crop = nil
            guard nw > 0, nh > 0 else { continue }
            let f = s.frame, fit = min(f.width / nw, f.height / nh)
            let w = nw * fit, h = nh * fit
            s.frame = Rect.fromLTWH(f.left + (f.width - w) / 2, f.top + (f.height - h) / 2, w, h)
        }
        _changed()
    }

    /// Set the alt text and its title on the selected shapes, whatever their kind (empty clears). One undo step.
    func setAltText(_ text: String, title: String = "") {
        guard !selection.isEmpty else { return }
        let value = text.isEmpty ? nil : text, head = title.isEmpty ? nil : title
        guard selection.contains(where: { $0.altText != value || $0.altTitle != head }) else { return }
        _checkpoint()
        for s in selection { s.altText = value; s.altTitle = head }
        _changed()
    }

    // MARK: Links (the shared Insert Hyperlink dialog)

    /// The slides a link can jump to: the key the file records ("slide:<part>"; "new:<id>" for a slide added here) and a title.
    func slideLinkTargets() -> [(key: String, title: String)] {
        slides.enumerated().map { i, sl in
            let name = sl.titleText
            return (sl.sourcePart ?? "new:\(sl.id)", "Slide \(i + 1)" + (name.isEmpty ? "" : ": " + name))
        }
    }

    /// The click action of the first selected shape (whole-shape link), for the dialog to start from.
    var selectedShapeLink: (link: String?, tip: String?) {
        guard let s = selection.first else { return (nil, nil) }
        return (s.link, s.linkTip)
    }

    /// Link every selected shape (nil or empty clears it). One undo step. False with no shape selected.
    @discardableResult
    func setShapeLink(_ link: String?, tip: String?) -> Bool {
        guard !selection.isEmpty else { return false }
        let value = (link?.isEmpty ?? true) ? nil : link
        let tipValue = value == nil || (tip?.isEmpty ?? true) ? nil : tip
        guard selection.contains(where: { $0.link != value || $0.linkTip != tipValue }) else { return true }
        _checkpoint()
        for s in selection { s.link = value; s.linkTip = tipValue }
        _changed()
        return true
    }

    /// The alt text of the first selected picture, for the dialog to start from.
    var selectedAltText: String? { selection.first?.altText }
    var selectedAltTitle: String? { selection.first?.altTitle }

    // MARK: Text box options (S-TX-2)

    /// What a shape's text box says about its text: where the text sits, which way it runs, whether it wraps, how it fits, its margins, its columns.
    struct TextOptions: Equatable {
        enum Direction { case horizontal, rotate90, rotate270, stacked }
        enum Fit { case none, shrink, resize }
        var anchor: TextAnchor = .top
        var direction = Direction.horizontal
        var wrap = true
        var fit = Fit.none
        var insets = EdgeInsets(left: 7.2, top: 3.6, right: 7.2, bottom: 3.6)
        var columns = 1
        var columnGap = 0.0
    }

    private var _textShapes: [SlideShape] { selection.filter { $0.text != nil && $0.picture == nil } }

    /// A table's look switches: the header row's fill and the banded rows.
    struct TableOptions: Equatable {
        var headerRow = true
        var bandedRows = true
        var firstColumn = false
        var lastColumn = false
        var totalRow = false
        var bandedColumns = false
    }

    /// The look switches of the selected table, nil when none is selected.
    var selectedTableOptions: TableOptions? {
        guard let s = selection.first, s.kind == .table, let id = s.tableId, let doc = s.text?.document else { return nil }
        let st = doc.tableStyles[id] ?? TableStyle()
        // Banding is on when the two band colours differ: a file with banding off
        // reads back with both set to the table's own background.
        return TableOptions(headerRow: st.headerRow, bandedRows: st.bandRows ?? (st.bandFill != nil && st.bandFill != st.bandAltFill),
                            firstColumn: st.firstColumn, lastColumn: st.lastColumn, totalRow: st.totalRow, bandedColumns: st.bandedColumns)
    }

    /// Shade cells of the selected table (nil clears the shading back to the
    /// style's): one undo step. `block` names the cells; nil means every cell.
    func setTableShading(_ color: Color?, block: CellBlock? = nil) {
        guard let s = selection.first, s.kind == .table, let id = s.tableId, let text = s.text else { return }
        var doc = text.document
        var changed = false
        for i in doc.paragraphs.indices {
            guard var c = doc.paragraphs[i].cell, c.table == id, block.map({ $0.contains(c) }) ?? true,
                  c.fill != color else { continue }
            c.fill = color
            doc.paragraphs[i].cell = c
            changed = true
        }
        guard changed else { return }
        _checkpoint()
        text.load(doc)
        _changed()
    }

    /// Format the selected shapes' text as PowerPoint does with the shapes selected and no caret in them (S-TX-1): `body`
    /// runs on all of each shape's text, and the whole change is one undo step. Shapes whose text it leaves as it was are untouched.
    func formatSelectedText(_ body: (RichDocumentController) -> Void) {
        var changed: [(RichDocumentController, RichDocument)] = []
        for text in selection.compactMap(\.text) {
            let work = RichDocumentController(document: text.document)
            work.selectAll()
            body(work)
            if work.document != text.document { changed.append((text, work.document)) }
        }
        guard !changed.isEmpty else { return }
        _checkpoint()
        for (text, doc) in changed { text.load(doc) }
        _changed()
    }

    /// Set the selected table's header row and banded rows: one undo step.
    /// Turning one back on restores the theme-accent look.
    /// A table style from the gallery: a colour for the emphasised cells and
    /// bands (the theme's six accents, dark grey), or `.plain`: no fills, dark
    /// text, black grid.
    enum TableLook: Equatable {
        case plain
        case accent(Int)
        /// Any other built-in style, by its id (Themed, Light, Medium 1/3/4, Dark, in every colour).
        case builtin(String)

        /// The PowerPoint built-in table style it names: "No Style, Table Grid", or "Medium Style 2 - Accent N".
        var styleId: String {
            switch self {
            case .plain: return "{5940675A-B579-460E-94D1-54222C63F5DA}"
            case .accent(let i):
                return DeckController.mediumStyle2Ids[min(max(i, 0), 5)]
            case .builtin(let id): return id
            }
        }
    }

    /// "Medium Style 2 - Accent 1" to "- Accent 6".
    static let mediumStyle2Ids = ["{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}", "{21E4AEA4-8DFA-4A89-87EB-49C32662AFE0}",
                                  "{F5AB1C69-6EDB-4FF4-983F-18BD219EF322}", "{00A15C55-8517-42AA-B614-E9B94910E393}",
                                  "{7DF18680-E054-41AD-8BC1-D1AEF772440D}", "{93296810-A885-4BE3-A3E7-6D5BEEA58F35}"]

    /// The colour a gallery choice paints with; nil for plain.
    func tableLookColor(_ l: TableLook) -> Color? {
        switch l {
        case .plain: return nil
        case .accent(let i): return theme.accents[min(max(i, 0), theme.accents.count - 1)]
        case .builtin: return nil
        }
    }

    /// Give the selected table a gallery style: one undo step. Header, band
    /// and column switches stay as they are; the user's own shading stays too.
    func applyTableLook(_ l: TableLook) { setTableOptions(selectedTableOptions ?? TableOptions(), look: l) }

    func setTableOptions(_ o: TableOptions, look chosen: TableLook? = nil) {
        guard let s = selection.first, s.kind == .table, let id = s.tableId, let text = s.text,
              chosen != nil || o != selectedTableOptions else { return }
        _checkpoint()
        var doc = text.document
        // A table in (or moving to or from) a family drawn from the style's definition.
        let oldId = doc.tableStyles[id]?.styleId
        if let sid = chosen?.styleId ?? oldId, DeckController.drawsFromDefinition(sid) || DeckController.drawsFromDefinition(oldId) {
            dressTable(&doc, shape: s, tableId: id, styleId: sid, options: o)
            text.load(doc)
            _changed()
            return
        }
        var st = doc.tableStyles[id] ?? TableStyle()
        // The colour the table is painted with now: the header's fill (the
        // gallery's pick, or the theme's first accent when none is kept).
        let oldAccent = st.headerFill ?? theme.accents[0]
        if let chosen { st.styleId = chosen.styleId }
        let plain = chosen == .plain || (chosen?.styleId).map { $0 == TableLook.plain.styleId } == true
        let base = chosen.flatMap { tableLookColor($0) } ?? oldAccent
        let look = tableStyle(accent: base)
        st.headerRow = o.headerRow
        st.bandRows = plain ? o.bandedRows : nil
        if chosen != nil {
            st.headerFill = o.headerRow && !plain ? look.headerFill : nil
            st.bandFill = o.bandedRows && !plain ? look.bandFill : nil
            st.bandAltFill = o.bandedRows && !plain ? look.bandAltFill : nil
            st.borderColor = plain ? Color(0xFF000000) : Color(0xFFFFFFFF)
        } else {
            st.headerFill = o.headerRow ? (st.headerFill ?? look.headerFill) : nil
            st.bandFill = o.bandedRows ? (st.bandFill ?? look.bandFill) : nil
            st.bandAltFill = o.bandedRows ? (st.bandAltFill ?? look.bandAltFill) : nil
        }
        // Emphasised cells (header row, total row, first and last column) are
        // white bold on the accent; banded columns tint every other column.
        // The fills are baked per cell: a fill that is one of our two
        // generated colours is ours to move, any other is the user's shading.
        let was = selectedTableOptions ?? TableOptions()
        st.totalRow = o.totalRow; st.firstColumn = o.firstColumn; st.lastColumn = o.lastColumn; st.bandedColumns = o.bandedColumns
        let cells = doc.paragraphs.compactMap { $0.cell }.filter { $0.table == id }
        let maxRow = cells.map { $0.row + $0.rowSpan - 1 }.max() ?? 0
        let maxCol = cells.map { $0.column + $0.span - 1 }.max() ?? 0
        func emphasised(_ c: CellRef, _ t: TableOptions) -> Bool {
            (c.row == 0 && t.headerRow) || (c.row + c.rowSpan - 1 == maxRow && t.totalRow)
                || (c.column == 0 && t.firstColumn) || (c.column + c.span - 1 == maxCol && t.lastColumn)
        }
        let white = Color(0xFFFFFFFF), accent = look.headerFill, tint = DeckController.tint(base, 0.40)
        let ink: Color? = plain ? nil : white
        for i in doc.paragraphs.indices {
            guard var c = doc.paragraphs[i].cell, c.table == id else { continue }
            let wasE = emphasised(c, was), nowE = emphasised(c, o)
            if wasE != nowE || (chosen != nil && nowE) {
                var runs = doc.paragraphs[i].runs.isEmpty ? [Run(length: doc.paragraphs[i].text.count)] : doc.paragraphs[i].runs
                for j in runs.indices {
                    if nowE {
                        runs[j].style.bold = true
                        if runs[j].style.color == nil || runs[j].style.color == white { runs[j].style.color = ink }
                    } else { runs[j].style.bold = false; if runs[j].style.color == white { runs[j].style.color = nil } }
                }
                doc.paragraphs[i].runs = runs
            }
            // A fill the style gave (ours to move) goes; one the user set stays.
            if c.styleFilled == true { c.fill = nil; c.styleFilled = nil }
            let headerCell = c.row == 0 && o.headerRow
            if c.fill == nil, !headerCell, !plain {
                if nowE { c.fill = accent; c.styleFilled = true }
                else if o.bandedColumns, c.column - (o.firstColumn ? 1 : 0) >= 0, (c.column - (o.firstColumn ? 1 : 0)) % 2 == 0 { c.fill = tint; c.styleFilled = true }
            }
            doc.paragraphs[i].cell = c
        }
        doc.tableStyles[id] = st
        text.load(doc)
        _changed()
    }

    /// The options of the first selected shape that holds text.
    var selectedTextOptions: TextOptions? {
        guard let s = _textShapes.first else { return nil }
        var o = TextOptions()
        o.anchor = s.anchor
        o.direction = s.textStacked != 0 ? .stacked : s.textTurn > 0 ? .rotate90 : s.textTurn < 0 ? .rotate270 : .horizontal
        o.wrap = !s.noWrap
        o.fit = s.autofit ? .shrink : (s.fitRule == "a:spAutoFit" || (s.fitRule == nil && s.kind == .textBox)) ? .resize : .none
        o.insets = s.insets
        o.columns = s.columns
        o.columnGap = s.columnGap
        return o
    }

    /// Sets the text options of every selected shape that holds text, as one undo step.
    func setTextOptions(_ o: TextOptions) {
        let shapes = _textShapes
        guard !shapes.isEmpty else { return }
        guard let was = selectedTextOptions, was != o || shapes.count > 1 else { return }
        _checkpoint()
        for s in shapes {
            s.anchor = o.anchor
            s.textTurn = o.direction == .rotate90 ? 1 : o.direction == .rotate270 ? -1 : 0
            s.textStacked = o.direction == .stacked ? 1 : 0
            s.uprightIdeographs = false
            s.sidewaysDigits = false
            s.bodyVert = o.direction == .rotate90 ? "vert" : o.direction == .rotate270 ? "vert270" : o.direction == .stacked ? "wordArtVert" : "horz"
            s.noWrap = !o.wrap
            s.bodyWrap = o.wrap ? "square" : "none"
            s.autofit = o.fit == .shrink
            s.fitRule = o.fit == .shrink ? "a:normAutofit" : o.fit == .resize ? "a:spAutoFit" : "a:noAutofit"
            s.insets = o.insets
            s.columns = max(1, o.columns)
            s.columnGap = o.columnGap
        }
        _changed()
    }

    /// Picture Format > Crop: the selected picture's handles crop it instead of resizing it, until Crop is pressed
    /// again, Enter or Esc, or the selection moves on (as PowerPoint applies the crop on a click away).
    private weak var _cropping: SlideShape? = nil
    var cropping: SlideShape? {
        guard let s = _cropping, selection.count == 1, selection.first === s, s.picture != nil else { return nil }
        return s
    }

    func beginCrop() {
        guard selection.count == 1, let s = selection.first, s.picture != nil else { return }
        _cropping = s
        _notify()
    }

    func endCrop() {
        guard _cropping != nil else { return }
        _cropping = nil
        _notify()
    }

    /// The crop after a crop handle moved the frame from `old` to `new` (the picture stays where it is on the
    /// slide): the edges the handle moved cut the picture by as much, at the picture's scale. `handle` is one of
    /// the eight frame handles; a negative share pads, as PowerPoint's outward crop does.
    static func cropAfterHandle(_ crop: EdgeInsets?, old: Rect, new: Rect, handle: Int) -> EdgeInsets {
        let c = crop ?? .zero
        let (hx, hy) = SlideCanvasState.handleUnits[handle]
        let fullW = old.width / max(1 - c.left - c.right, 0.001), fullH = old.height / max(1 - c.top - c.bottom, 0.001)
        let dw = (old.width - new.width) / max(fullW, 0.001), dh = (old.height - new.height) / max(fullH, 0.001)
        return EdgeInsets(left: c.left + (hx == 0 ? dw : 0), top: c.top + (hy == 0 ? dh : 0),
                          right: c.right + (hx == 1 ? dw : 0), bottom: c.bottom + (hy == 1 ? dh : 0))
    }

    /// A crop handle's drag (`beginFrameEdit` gives the drag its history entry): the frame shows less or more of the
    /// picture, which stays put.
    func setCropLive(_ shape: SlideShape, crop0: EdgeInsets?, frame0: Rect, frame: Rect, handle: Int) {
        guard frame.width >= 1, frame.height >= 1 else { return }
        let c = Self.cropAfterHandle(crop0, old: frame0, new: frame, handle: handle)
        shape.crop = c == .zero ? nil : c
        shape.frame = frame
        _changed(keepSession: true)
    }

    /// The crop after the picture slid `by` (points, in the picture's own axes) under its crop frame: what it cuts
    /// on one side it gives back on the other, so the picture keeps its size and the frame its place.
    static func cropAfterPan(_ crop: EdgeInsets?, frame: Rect, by d: Offset) -> EdgeInsets {
        let c = crop ?? .zero
        let fullW = frame.width / max(1 - c.left - c.right, 0.001), fullH = frame.height / max(1 - c.top - c.bottom, 0.001)
        let sx = d.dx / max(fullW, 0.001), sy = d.dy / max(fullH, 0.001)
        return EdgeInsets(left: c.left - sx, top: c.top - sy, right: c.right + sx, bottom: c.bottom + sy)
    }

    /// A drag inside a picture in crop mode (`beginFrameEdit` gives it its history entry).
    func setCropPanLive(_ shape: SlideShape, crop0: EdgeInsets?, by d: Offset) {
        let c = Self.cropAfterPan(crop0, frame: shape.frame, by: d)
        shape.crop = c == .zero ? nil : c
        _changed(keepSession: true)
    }

    /// The selected pictures' transparency, 0-100 % (Picture Format > Transparency): one undo step.
    func setPictureTransparency(_ percent: Double) {
        let pics = selection.filter { $0.picture != nil }
        guard !pics.isEmpty else { return }
        let alpha = 1 - max(0, min(100, percent)) / 100
        guard pics.contains(where: { $0.pictureAlpha != alpha }) else { return }
        _checkpoint()
        for s in pics { s.pictureAlpha = alpha }
        _changed()
    }

    func cropPictures(aspect: Double) {
        let pics = selection.filter { $0.picture != nil }
        guard !pics.isEmpty, aspect > 0 else { return }
        _checkpoint()
        for s in pics {
            guard let img = s.picture else { continue }
            let nw = img.naturalWidth ?? s.frame.width, nh = img.naturalHeight ?? s.frame.height
            let natural = nw / max(nh, 0.001)
            var c = EdgeInsets.zero
            if natural > aspect {
                let cut = (1 - aspect / natural) / 2
                c = EdgeInsets(left: cut, top: 0, right: cut, bottom: 0)
            } else {
                let cut = (1 - natural / aspect) / 2
                c = EdgeInsets(left: 0, top: cut, right: 0, bottom: cut)
            }
            s.crop = c
            // The cropped picture fits inside the box it had, centred.
            let f = s.frame
            let w = min(f.width, f.height * aspect), h = w / aspect
            s.frame = Rect.fromLTWH(f.center.dx - w / 2, f.center.dy - h / 2, w, h)
        }
        _changed()
    }

    /// PowerPoint's default table look in the theme's first accent: a
    /// filled header with white bold text, banded rows, white rules.
    func tableStyle(accent: Color) -> TableStyle {
        TableStyle(borders: true, headerRow: true, headerFill: accent,
                   bandFill: Self.tint(accent, 0.40), bandAltFill: Self.tint(accent, 0.20),
                   borderColor: Color(0xFFFFFFFF))
    }

    /// A table centred on the slide, a column 144 pt wide (at most four
    /// fifths of the slide across), rows as tall as their text.
    @discardableResult
    func addTable(rows: Int, columns: Int) -> SlideShape {
        _checkpoint()
        let rows = max(1, rows), cols = max(1, columns)
        let id = UUID().uuidString
        var paragraphs: [RichParagraph] = []
        let header = CharStyle(bold: true, color: Color(0xFFFFFFFF))
        for r in 0 ..< rows {
            for c in 0 ..< cols {
                var p = RichParagraph(text: "", runs: r == 0 ? [Run(length: 0, style: header)] : nil,
                                      style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0))
                p.cell = CellRef(table: id, row: r, column: c)
                paragraphs.append(p)
            }
        }
        var doc = RichDocument(paragraphs: paragraphs)
        var firstStyle = tableStyle(accent: theme.accents[0])
        firstStyle.styleId = Self.mediumStyle2Ids[0]
        doc.tableStyles[id] = firstStyle
        let w = min(slideSize.width * 0.8, Double(cols) * 144)
        let h = Double(rows) * 30
        let shape = SlideShape(id: _id(), name: "Table \(_nextId)", kind: .table,
                               frame: Rect.fromLTWH((slideSize.width - w) / 2, (slideSize.height - h) / 2, w, h),
                               text: _textController(doc),
                               textTheme: _textTheme(font: theme.bodyFont, size: 18, color: theme.text))
        shape.insets = EdgeInsets(left: 0, top: 0, right: 0, bottom: 0)
        shape.fillScheme = "accent1"
        currentSlide.shapes.append(shape)
        _watch(shape)
        selection = [shape]
        _changed()
        return shape
    }

    /// A table's height follows its rows: no undo step of its own, it is
    /// part of the typing that grew it.
    func fitHeight(_ shape: SlideShape, _ height: Double) {
        guard abs(shape.frame.height - height) > 0.5 else { return }
        let f = shape.frame
        shape.frame = Rect.fromLTWH(f.left, f.top, f.width, height)
        revision += 1
        notifyListeners()
    }

    /// A table's width follows its grid once an edit changes the grid (Column Width, Table Size, a column inserted):
    /// no undo step of its own, as `fitHeight`.
    func fitWidth(_ shape: SlideShape, _ width: Double) {
        guard abs(shape.frame.width - width) > 0.5 else { return }
        let f = shape.frame
        shape.frame = Rect.fromLTWH(f.left, f.top, width, f.height)
        revision += 1
        notifyListeners()
    }

    /// A table's columns as drawn: the grid it states, else equal columns across its frame.
    static func drawnGrid(_ shape: SlideShape) -> [Double] {
        guard let doc = shape.text?.document, let id = shape.tableId else { return [] }
        let cols = doc.paragraphs.compactMap(\.cell).filter { $0.table == id }.map { $0.column + $0.span }.max() ?? 0
        guard cols > 0 else { return [] }
        if let g = doc.tableColumns[id], g.count == cols { return g }
        let w = shape.frame.width - shape.insets.left - shape.insets.right
        return Array(repeating: w / Double(cols), count: cols)
    }

    /// Table Size's Lock Aspect Ratio (`graphicFrameLocks noChangeAspect`): one undo step.
    func setAspectLock(_ shape: SlideShape, _ on: Bool) {
        guard shape.aspectLocked != on else { return }
        _checkpoint()
        shape.aspectLock = on
        _changed()
    }

    static func tint(_ c: Color, _ amount: Double) -> Color {
        let v = c.value
        func mix(_ x: Int) -> Int { Int(Double(x) * amount + 255 * (1 - amount)) }
        return Color(0xFF00_0000 | Int64((mix((v >> 16) & 0xFF) << 16) | (mix((v >> 8) & 0xFF) << 8) | mix(v & 0xFF)))
    }

    /// `c` composited over an opaque `under` by its own alpha; the result
    /// is opaque.
    static func blend(_ c: Color, over under: Color) -> Color {
        let v = c.value, u = under.value
        let a = Double((v >> 24) & 0xFF) / 255
        func mix(_ sh: Int) -> Int {
            let top = Double((v >> sh) & 0xFF), bottom = Double((u >> sh) & 0xFF)
            return Int((top * a + bottom * (1 - a)).rounded())
        }
        let r = mix(16), g = mix(8), b = mix(0)
        let rgb: Int = (r << 16) | (g << 8) | b
        return Color(0xFF00_0000 | Int64(rgb))
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for shape in selection { _unwatch(shape) }
        currentSlide.shapes.removeAll { s in selection.contains { $0 === s } }
        selection = []
        _changed()
    }

    /// Copies of the selection, nudged down and right, selected in its place.
    func duplicateSelection(offset: Double = 18) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        let copies = selection.map { _copy($0, offset: offset, keepGroup: true) }
        _regroupCopies(copies)
        _renameCopies(copies)
        currentSlide.shapes.append(contentsOf: copies)
        for c in copies { _watch(c) }
        selection = copies
        _changed()
    }

    /// The selection as values, for the shape clipboard.
    func copySelection() -> [ShapeState] { selection.map(_state) }

    // The deck's own shape clipboard. It belongs to the deck because a
    // picture names an image the deck holds: pasted into another deck it
    // would name nothing.
    private(set) var shapeClipboard: [ShapeState] = []
    private(set) var _pasteCount = 0
    /// The last paste onto a slide, for the Paste Options button (SlidesClipboard.swift).
    var _lastSlidePaste: SlidePasteRecord? = nil
    /// An undone shape paste gives its offset back, so the next one lands where it did.
    func _unpasteShapes() { _pasteCount = max(0, _pasteCount - 1) }
    var canPasteShapes: Bool { !shapeClipboard.isEmpty }
    /// What the last copy put under `DeckController.shapesMime` on the system clipboard: finding it there again
    /// means the clipboard still holds this deck's shapes (see SlidesClipboard.swift).
    private(set) var shapeClipboardToken: String? = nil

    /// Copy the selected shapes. False when none are selected. The system clipboard gets them too: their text, a
    /// picture of them, and a token naming this deck's copy.
    @discardableResult func copyShapes() -> Bool {
        guard !selection.isEmpty else { return false }
        shapeClipboard = copySelection(); _pasteCount = 0
        let token = DeckController.nextShapesToken()
        shapeClipboardToken = token
        Clipboard.setData(shapesClipboardData(token: token))
        return true
    }

    /// Copy, then delete: one undo step.
    @discardableResult func cutShapes() -> Bool {
        guard copyShapes() else { return false }
        deleteSelection()
        return true
    }

    /// Paste the shape clipboard. Each paste of the same copy lands a step
    /// further down and right, so a second paste does not hide the first.
    @discardableResult func pasteShapes() -> Bool {
        guard canPasteShapes else { return false }
        _pasteCount += 1
        paste(shapeClipboard, offset: 18 * Double(_pasteCount))
        return true
    }

    func paste(_ states: [ShapeState], offset: Double = 18) {
        guard !states.isEmpty else { return }
        _checkpoint()
        var pasted: [SlideShape] = []
        for var s in states {
            s.id = _id()
            s.fileId = nil
            s.frame = s.frame.shift(Offset(offset, offset))
            let shape = _make(s)
            pasted.append(shape)
            _watch(shape)
        }
        _regroupCopies(pasted)
        _renameCopies(pasted)
        currentSlide.shapes.append(contentsOf: pasted)
        selection = pasted
        _changed()
    }

    // Moves and resizes come in three calls so a drag is one undo step and
    // every frame between is cheap: begin (checkpoint), live updates (no
    // history), end.

    func beginFrameEdit() { _checkpoint() }

    func setFramesLive(_ frames: [(SlideShape, Rect)]) {
        detachLines(moving: frames.map(\.0))
        for (shape, frame) in frames { shape.frame = frame }
        _changed(keepSession: true)
    }

    /// The drag is over: typing after it is a step of its own.
    func endFrameEdit() { _changed() }

    /// A drag of the yellow handle on an elbow's middle run (the drag has its own history entry, from `beginFrameEdit`).
    func setElbowRunLive(_ shape: SlideShape, _ key: String, alongWidth: Bool, to p: Offset) {
        shape.setElbowAdjust(key, alongWidth: alongWidth, to: p)
        _changed(keepSession: true)
    }

    /// A drag of a preset's yellow handle (`beginFrameEdit` gives the drag its history entry).
    func setAdjustHandleLive(_ shape: SlideShape, _ index: Int, to p: Offset) {
        shape.setAdjustHandle(index, to: p)
        _changed(keepSession: true)
    }

    /// Sets a preset shape's adjust values (corner radius, arrow head...) as one step of history.
    func setAdjusts(_ shape: SlideShape, _ values: [String: Double]) {
        guard shape.preset != nil, values != shape.adjusts else { return }
        _checkpoint()
        shape.setAdjusts(values)
        _changed()
    }

    func setRotationLive(_ shape: SlideShape, _ degrees: Double) {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        shape.rotation = d
        _changed(keepSession: true)
    }

    func nudgeSelection(dx: Double, dy: Double) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        detachLines(moving: Array(selection))
        for s in selection { s.frame = s.frame.shift(Offset(dx, dy)) }
        _changed()
    }

    // MARK: Size and position (S-SH-6)

    /// Sets the selected shapes' width and/or height, keeping each one's top left corner. With the
    /// aspect lock on, the side not given follows in proportion. One undo step.
    func setSize(width: Double? = nil, height: Double? = nil) {
        guard !selection.isEmpty, width != nil || height != nil else { return }
        _checkpoint()
        for s in selection {
            var w = width ?? s.frame.width, h = height ?? s.frame.height
            if s.aspectLocked, s.frame.width > 0, s.frame.height > 0 {
                if let width, height == nil { h = width * s.frame.height / s.frame.width }
                else if let height, width == nil { w = height * s.frame.width / s.frame.height }
            }
            s.frame = Rect.fromLTWH(s.frame.left, s.frame.top, max(1, w), max(1, h))
        }
        _changed()
    }

    /// Scales the selected shapes to `width` and/or `height` percent of their scale base (the size they had when first
    /// scaled), keeping each top left corner. With the aspect lock on, the other side takes the same percentage.
    func setScale(width: Double? = nil, height: Double? = nil) {
        guard !selection.isEmpty, width != nil || height != nil else { return }
        _checkpoint()
        for s in selection {
            let base = s.scaleBase ?? Size(s.frame.width, s.frame.height)
            s.scaleBase = base
            var wp = width ?? s.frame.width / base.width * 100, hp = height ?? s.frame.height / base.height * 100
            if s.aspectLocked { if let width, height == nil { hp = width } else if let height, width == nil { wp = height } }
            s.frame = Rect.fromLTWH(s.frame.left, s.frame.top, max(1, base.width * wp / 100), max(1, base.height * hp / 100))
        }
        _changed()
    }

    /// Moves the selection so the top left of its box sits at `left`, `top` (either may be left out).
    func setPosition(left: Double? = nil, top: Double? = nil) {
        guard let box = _selectionBounds, left != nil || top != nil else { return }
        _checkpoint()
        let d = Offset((left ?? box.left) - box.left, (top ?? box.top) - box.top)
        for s in selection { s.frame = s.frame.shift(d) }
        _changed()
    }

    /// Sets the turn of every selected shape, in degrees.
    func setRotation(_ degrees: Double) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        for s in selection { s.rotation = d }
        _changed()
    }

    /// Turns the aspect lock on or off for the selected shapes.
    func setAspectLock(_ on: Bool) {
        guard !selection.isEmpty, selection.contains(where: { $0.aspectLocked != on }) else { return }
        _checkpoint()
        for s in selection { s.aspectLock = on }
        _changed()
    }

    /// The box around the selection, drawn at the frames' own (unrotated) extents.
    private var _selectionBounds: Rect? {
        guard var r = selection.first?.frame else { return nil }
        for s in selection.dropFirst() {
            r = Rect.fromLTRB(min(r.left, s.frame.left), min(r.top, s.frame.top),
                              max(r.right, s.frame.right), max(r.bottom, s.frame.bottom))
        }
        return r
    }

    /// Mirrors the selection about its common centre. Each shape's own flip
    /// toggles and its turn reverses, so a lone shape flips in place.
    func flipSelection(horizontal: Bool) {
        guard let box = _selectionBounds else { return }
        _checkpoint()
        let c = box.center
        for s in selection {
            let f = s.frame
            let m = f.center
            let n = horizontal ? Offset(2 * c.dx - m.dx, m.dy) : Offset(m.dx, 2 * c.dy - m.dy)
            s.frame = Rect.fromLTWH(n.dx - f.width / 2, n.dy - f.height / 2, f.width, f.height)
            if horizontal { s.flipH.toggle() } else { s.flipV.toggle(); s.textSpin = (s.textSpin + 180).truncatingRemainder(dividingBy: 360) }
            // The geometry's text rectangle mirrors with the shape; the text itself does not.
            if s.shapeInsets != .zero {
                s.insets = s.insets.mirroringShare(s.shapeInsets, horizontal: horizontal, vertical: !horizontal)
                s.shapeInsets = s.shapeInsets.mirroringShare(s.shapeInsets, horizontal: horizontal, vertical: !horizontal)
            }
            var d = (-s.rotation).truncatingRemainder(dividingBy: 360)
            if d < 0 { d += 360 }
            s.rotation = d
        }
        _changed()
    }

    /// Turns the selection by `degrees` (clockwise) about its common centre.
    func rotateSelection(by degrees: Double) {
        guard let box = _selectionBounds else { return }
        _checkpoint()
        let c = box.center
        let a = degrees * Double.pi / 180
        let (sn, cs) = (sin(a), cos(a))
        for s in selection {
            if selection.count > 1 {
                let f = s.frame
                let m = f.center
                let dx = m.dx - c.dx, dy = m.dy - c.dy
                let n = Offset(c.dx + dx * cs - dy * sn, c.dy + dx * sn + dy * cs)
                s.frame = Rect.fromLTWH(n.dx - f.width / 2, n.dy - f.height / 2, f.width, f.height)
            }
            var d = (s.rotation + degrees).truncatingRemainder(dividingBy: 360)
            if d < 0 { d += 360 }
            s.rotation = d
        }
        _changed()
    }

    /// Shapes picked lately in the Shapes gallery, newest first (not part of the document, not undone).
    private(set) var recentShapes: [ShapePreset] = []
    func useRecentShape(_ preset: ShapePreset) {
        recentShapes.removeAll { $0 == preset }
        recentShapes.insert(preset, at: 0)
        if recentShapes.count > ShapeGridMenuItem.columns { recentShapes.removeLast() }
        _notify()
    }

    /// Colours picked lately in Shape Fill and Outline (not part of the document, not undone).
    var recentShapeColors = RecentColors()
    /// The selected shapes as they were before a Shape Styles entry was previewed on them (S-SH-4).
    var _quickStylePreview: [(SlideShape, ShapeState)]? = nil
    /// Set while the eyedropper waits for a click on the slide (false: for the fill, true: for the outline).
    var eyedropperFor: Bool? = nil

    /// Gives the selected shapes a picture, texture (a tiled picture), pattern or gradient fill.
    /// `fill` is what the painter draws; the plain colour stands in where the file cannot say more.
    func setFillStyle(_ style: SlideFill) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection where s.preset?.isLine != true {
            s.fillStyle = style
            s.fill = style.color ?? style.stops.first?.color ?? s.fill ?? Color(0xFFFFFFFF)
            s.fillScheme = nil
            s.keptLook?.fillReplaced = true
        }
        _changed()
    }

    func setPictureFill(_ image: ImageAttachment, tiled: Bool = false) {
        var f = SlideFill(image: image)
        f.tiled = tiled
        setFillStyle(f)
    }

    func setPatternFill(_ preset: String, foreground: Color, background: Color) {
        setFillStyle(PatternFill.fill(preset: preset, foreground: foreground, background: background))
    }

    /// The straight-line gradient the Format Shape pane shows: the first selected shape's, or nil when it has none
    /// (a radial or path gradient is left to the file).
    var selectionGradient: SlideFill? {
        guard let f = selection.first(where: { $0.preset?.isLine != true })?.fillStyle,
              f.image == nil, f.stops.count >= 2, f.path == nil else { return nil }
        return f
    }

    /// Changes the gradient of every selected shape, giving one that has none a two-stop gradient from its colour.
    /// One undo step. A shape with a radial or path gradient, which this editor cannot show, is left alone.
    func editGradient(_ edit: (inout SlideFill) -> Void) {
        let targets = selection.filter { $0.preset?.isLine != true && $0.fillStyle?.path == nil }
        guard !targets.isEmpty else { return }
        _checkpoint()
        for s in targets {
            var g: SlideFill
            if let f = s.fillStyle, f.image == nil, f.stops.count >= 2 { g = f }
            else {
                let base = s.fill ?? theme.accents[0]
                g = SlideFill(color: base, stops: [.init(position: 0, color: base), .init(position: 1, color: Self.darker(base))], angle: 90)
            }
            edit(&g)
            g.stops.sort { $0.position < $1.position }
            g.color = g.stops.first?.color
            s.fillStyle = g
            s.fill = g.color
            s.fillScheme = nil
            s.keptLook?.fillReplaced = true
        }
        _changed()
    }

    /// A stop in the middle of the widest gap, in the colour the gradient has there.
    func addGradientStop() {
        editGradient { g in
            var best = (0.0, 0.0)
            for (a, b) in zip(g.stops, g.stops.dropFirst()) where b.position - a.position > best.1 - best.0 { best = (a.position, b.position) }
            let at = (best.0 + best.1) / 2
            g.stops.append(.init(position: at, color: SlideFill.colorAt(g.stops, at)))
        }
    }

    /// Takes stop `index` out; a gradient keeps at least two.
    func removeGradientStop(at index: Int) {
        guard let g = selectionGradient, g.stops.count > 2, g.stops.indices.contains(index) else { return }
        editGradient { $0.stops.remove(at: index) }
    }

    func reverseGradient() {
        editGradient { g in g.stops = g.stops.reversed().map { .init(position: 1 - $0.position, color: $0.color) } }
    }

    func setFill(_ color: Color?, scheme: String? = nil) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection where s.preset?.isLine != true {
            s.fill = color
            s.fillScheme = scheme
            s.fillStyle = nil              // a gradient or picture gives way to the chosen fill
            s.keptLook?.fillReplaced = true
        }
        _changed()
    }

    /// Fill transparency in percent (0 solid, 100 clear) on the selected shapes that have a fill.
    func setFillTransparency(_ percent: Double) {
        let a = Int(((100 - min(100, max(0, percent))) / 100 * 255).rounded())
        let targets = selection.filter { $0.preset?.isLine != true && $0.fill != nil }
        guard !targets.isEmpty else { return }
        _checkpoint()
        for s in targets {
            s.fill = Color((a << 24) | (s.fill!.value & 0xFFFFFF))
            if var g = s.fillStyle, g.image == nil, g.stops.count >= 2, g.path == nil {
                // A gradient keeps its colours; the transparency goes on each stop.
                for i in g.stops.indices { g.stops[i].color = Color((a << 24) | (g.stops[i].color.value & 0xFFFFFF)) }
                g.color = g.stops.first?.color
                s.fillStyle = g
            } else { s.fillStyle = nil }
            s.keptLook?.fillReplaced = true
        }
        _changed()
    }

    // MARK: Design

    /// Restyle the deck with one of our themes. Placeholders take its fonts
    /// and text colour, shapes coloured from the old theme take the new
    /// one's, and text that simply followed the old theme follows this one.
    /// A deck read from a file keeps its own masters and layouts; its theme part is recoloured.
    func applyTheme(_ new: DeckTheme) {
        _checkpoint()
        let old = theme
        theme = new
        // The deck's own text-box face, size and alignment stay (the presentation says them, not the theme); a
        // colour taken from the old theme's slot goes with it.
        if new.textBoxFont == nil && new.textBoxSize == nil && new.textBoxAlign == nil {
            theme.textBoxFont = old.textBoxFont; theme.textBoxSize = old.textBoxSize; theme.textBoxAlign = old.textBoxAlign
        }
        // A deck from a file keeps its masters and layouts; only its theme part is recoloured.
        let fromFile = package != nil
        if fromFile { recolourTheme = true } else { ownTemplates = true }
        for slide in slides {
            if !fromFile {
                slide.layoutPart = nil
                slide.backgroundXML = nil
                if let bg = slide.background, bg.image == nil { slide.background = nil }
            }
            slide.inheritedBackground = nil
            for shape in slide.shapes { restyleShape(shape, from: old, to: new) }
        }
        _changed()
    }

    /// `shape` as it would look had it been made in `new` rather than `old`: colours from `old`'s slots take
    /// `new`'s, and text that followed `old`'s fonts and colours follows `new`'s (Design > Themes, and a paste in
    /// Use Destination Theme).
    func restyleShape(_ shape: SlideShape, from old: DeckTheme, to new: DeckTheme) {
        // A Shape Styles entry is redrawn whole in the new colours, its text included, unless its fill or
        // line was changed since.
        if let q = shape.quickStyle, Self._showsLook(shape, q.look(tableStyleColors(old))) { _giveQuickStyle(q, to: shape) }
        else if shape.kind == .table, shape.fillScheme?.hasPrefix("accent") == true, let id = shape.tableId, let text = shape.text {
            var doc = text.document
            let kept = doc.tableStyles[id]?.styleId
            doc.tableStyles[id] = tableStyle(accent: new.accents[0])
            doc.tableStyles[id]?.styleId = kept
            text.load(doc)
        } else if let scheme = shape.fillScheme, let c = SchemeColor.resolve(scheme, slots: new.slots) {
            let plainAccent = SchemeColor.parse(scheme).map { $0.slot >= 4 && $0.mod == 100 && $0.off == 0 } ?? false
            if shape.preset?.isLine == true { shape.outline = c } else {
                shape.fill = c
                if plainAccent { shape.outline = shape.themeStyle ? Self.shadeLinear(c, 0.5) : Self.darker(c) }
            }
        }
        if let scheme = shape.outlineScheme, let c = SchemeColor.resolve(scheme, slots: new.slots) { shape.outline = c }
        guard let tt = shape.textTheme, let text = shape.text else { return }
        let heading = shape.role == .title || shape.role == .ctrTitle
        if shape.role != nil || shape.kind == .textBox {
            let fresh = _textTheme(font: heading ? new.headingFont : new.bodyFont, size: tt.fontSize,
                                   color: shape.quickStyle.map { $0.look(tableStyleColors(new)).text }
                                       ?? (tt.textColor == old.subtle ? new.subtle : new.text))
            fresh.listIndent = tt.listIndent
            shape.textTheme = fresh
        }
        // Runs that spelled out the old theme's look follow the new one.
        var doc = text.document
        var touched = false
        for p in doc.paragraphs.indices {
            for r in doc.paragraphs[p].runs.indices {
                var st = doc.paragraphs[p].runs[r].style
                if st.color == old.text || st.color == old.subtle { st.color = nil; touched = true }
                if st.fontFamily == old.headingFont || st.fontFamily == old.bodyFont { st.fontFamily = nil; touched = true }
                doc.paragraphs[p].runs[r].style = st
            }
        }
        if touched { text.load(doc) }
    }

    /// The current slide's background, or every slide's; nil returns to
    /// the theme's.
    func setBackground(_ fill: SlideFill?, all: Bool = false) {
        _checkpoint()
        // Apply to All writes the master (new slides and layouts pick it up) and clears every slide's own
        // background, as PowerPoint does. A picture is written once, on the master.
        if all, let fill {
            masterBackground = fill
            for slide in slides { slide.background = nil; slide.backgroundXML = nil; slide.inheritedBackground = fill }
        } else if all, fill == nil {
            masterBackground = nil
            for slide in slides { slide.background = nil; slide.backgroundXML = nil; slide.inheritedBackground = nil }
        } else {
            for slide in all ? slides : [currentSlide] {
                slide.background = fill
                slide.backgroundXML = nil
            }
        }
        _changed()
    }

    func setOutline(_ color: Color?, scheme: String? = nil) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection {
            s.outline = color
            s.outlineScheme = scheme
            s.outlineFill = nil
            s.keptLook?.lineReplaced = true
        }
        _changed()
    }

    /// The dash style of the selected shapes' lines: nil for solid, else a preset name ("dash", "sysDot"...).
    func setOutlineDash(_ dash: String?) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection { s.outlineDash = dash; s.keptLook?.dashEdited = true }
        _changed()
    }

    /// The arrowhead at a line's start (`start`) or end of the selected shapes: nil for none. Sizes stay as they were, else medium.
    func setLineEnd(start: Bool, kind: String?) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection {
            let old = start ? s.headEnd : s.tailEnd
            let e = kind.map { LineEnd(kind: $0, width: old?.width ?? 3, length: old?.length ?? 3) }
            if start { s.headEnd = e } else { s.tailEnd = e }
            s.keptLook?.endsEdited = true
        }
        _changed()
    }

    /// The shape shadow of the selection: nil for none. A file shape's other effects (glow, reflection...) stay.
    func setShadow(_ shadow: CharShadow?) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection { s.shadow = shadow; s.keptLook?.effectsEdited = true }
        _changed()
    }

    /// The 3-D Rotation preset of the selection (`a:camera prst`; "orthographicFront" turns it off). A shape's depth,
    /// bevel and lights stay; only the camera changes.
    func setCamera(_ name: String) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection {
            s.camera = name
            s.scene3d = Extrusion.scene(camera: name, from: s.scene3d)
        }
        _changed()
    }

    func setOutlineWidth(_ width: Double) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        for s in selection { s.outlineWidth = width }
        _changed()
    }

    enum Arrange { case front, back, forward, backward }

    func arrange(_ how: Arrange) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        var shapes = currentSlide.shapes
        let picked = shapes.filter { s in selection.contains { $0 === s } }
        switch how {
        case .front:
            shapes.removeAll { s in picked.contains { $0 === s } }
            shapes.append(contentsOf: picked)
        case .back:
            shapes.removeAll { s in picked.contains { $0 === s } }
            shapes.insert(contentsOf: picked, at: 0)
        case .forward:
            for s in picked.reversed() {
                guard let i = shapes.firstIndex(where: { $0 === s }), i + 1 < shapes.count else { continue }
                shapes.swapAt(i, i + 1)
            }
        case .backward:
            for s in picked {
                guard let i = shapes.firstIndex(where: { $0 === s }), i > 0 else { continue }
                shapes.swapAt(i, i - 1)
            }
        }
        currentSlide.shapes = shapes
        _changed()
    }

    /// The Selection Pane's eye: shows or hides one shape (one undo step). A shape a hidden group hides
    /// stays hidden until the group is shown.
    func setHidden(_ shape: SlideShape, _ hidden: Bool) {
        guard shape.invisible != hidden else { return }
        _checkpoint()
        shape.invisible = hidden
        if hidden { selection.removeAll { $0 === shape } }
        _changed()
    }

    /// The Selection Pane's Show All and Hide All: every shape of the current slide at once, one undo step.
    func setAllHidden(_ hidden: Bool) {
        let shapes = currentSlide.shapes.filter { $0.invisible != hidden }
        guard !shapes.isEmpty else { return }
        _checkpoint()
        for shape in shapes { shape.invisible = hidden }
        if hidden { selection.removeAll() }
        _changed()
    }

    /// The Selection Pane's rename (the file's `cNvPr name`), one undo step. Blank names are refused, as PowerPoint
    /// puts the old name back; two shapes may share a name.
    @discardableResult func renameShape(_ shape: SlideShape, _ name: String) -> Bool {
        let n = name.trimmingWhitespace()
        guard !n.isEmpty else { return false }
        guard n != shape.name else { return true }
        _checkpoint()
        shape.name = n
        _changed()
        return true
    }

    /// The Selection Pane's reorder: one shape a step toward the front (`by` > 0) or the back, one undo step.
    func moveInStack(_ shape: SlideShape, by delta: Int) {
        var shapes = currentSlide.shapes
        guard let i = shapes.firstIndex(where: { $0 === shape }) else { return }
        let j = min(max(i + delta, 0), shapes.count - 1)
        guard j != i else { return }
        _checkpoint()
        shapes.remove(at: i)
        shapes.insert(shape, at: j)
        currentSlide.shapes = shapes
        _changed()
    }

    // MARK: Groups

    /// Every shape of the slide that shares `shape`'s group, in stacking order; the shape alone when it has none.
    func groupMembers(of shape: SlideShape) -> [SlideShape] {
        guard let key = shape.group?.key else { return [shape] }
        return currentSlide.shapes.filter { $0.group?.key == key }
    }

    /// The selection widened to whole groups: a group is moved, copied and ordered as one.
    func selectWholeGroup(of shape: SlideShape) { selectShapes(groupMembers(of: shape)) }

    /// Two or more shapes selected: they can be grouped.
    /// Why the selection cannot be grouped, or nil. A placeholder takes its frame from its layout, and a group
    /// would cut that link (PowerPoint does not group them either).
    var groupRefusal: String? {
        selection.contains { $0.role != nil } ? "Placeholders can't be grouped" : nil
    }
    var canGroup: Bool { groupRefusal == nil && selection.count >= 2 && Set(selection.map { $0.group?.key ?? -$0.id }).count >= 2 }
    /// Something selected belongs to a group.
    var canUngroup: Bool { selection.contains { $0.group != nil } }

    /// Group the selected shapes: they become adjacent at the top-most one's place in the stack and share one
    /// group, which the file writes as a `p:grpSp`. A group already among them is taken in whole, and its members
    /// join the new one (a group inside a group is one group: the deck keeps one level).
    func groupSelection() {
        guard canGroup else { return }
        _checkpoint()
        let old = Set(selection.compactMap { $0.group?.key })
        let all = currentSlide.shapes
        let picked = all.filter { s in selection.contains { $0 === s } || (s.group.map { old.contains($0.key) } ?? false) }
        let top = all.lastIndex { s in picked.contains { $0 === s } } ?? all.count - 1
        let before = all[...top].filter { s in !picked.contains { $0 === s } }.count
        var rest = all.filter { s in !picked.contains { $0 === s } }
        let key = (all.compactMap { $0.group?.key }.max() ?? 0) + 1
        let carried = picked.compactMap(\.group).first { $0.fillXML != nil }
        var number = 1
        let names = Set(all.compactMap { $0.group?.name })
        while names.contains("Group \(number)") { number += 1 }
        var g = ShapeGroup(fileId: nil, name: "Group \(number)", key: key)
        g.fillXML = carried?.fillXML
        g.fillColor = carried?.fillColor
        for s in picked { s.group = g }
        rest.insert(contentsOf: picked, at: before)
        currentSlide.shapes = rest
        selection = picked
        _changed()
    }

    /// Ungroup: every group touched by the selection dissolves, its members stay selected.
    func ungroupSelection() {
        guard canUngroup else { return }
        _checkpoint()
        let keys = Set(selection.compactMap { $0.group?.key })
        let members = currentSlide.shapes.filter { s in s.group.map { keys.contains($0.key) } ?? false }
        for s in members { s.group = nil }
        selection = members
        _changed()
    }

    /// A name not yet used on the slide: "Title" becomes "Title 2", "Group 1" becomes "Group 3" if 2 is taken.
    private func _freshName(_ name: String, taken: Set<String>) -> String {
        if !taken.contains(name) { return name }
        var base = name
        if let sp = name.lastIndex(of: " "), Int(name[name.index(after: sp)...]) != nil { base = String(name[..<sp]) }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// Copies get names of their own, as they get ids; a copied group too.
    private func _renameCopies(_ copies: [SlideShape]) {
        var taken = Set(currentSlide.shapes.map(\.name))
        for c in copies {
            c.name = _freshName(c.name, taken: taken)
            taken.insert(c.name)
        }
        var groupNames = Set(currentSlide.shapes.compactMap { $0.group?.name })
        var renamed: [Int: String] = [:]
        for c in copies {
            guard var g = c.group else { continue }
            if let known = renamed[g.key] { g.name = known } else {
                g.name = _freshName(g.name, taken: groupNames)
                groupNames.insert(g.name)
                renamed[g.key] = g.name
            }
            c.group = g
        }
    }

    /// Copies that keep their grouping get groups of their own, not the original's.
    private func _regroupCopies(_ copies: [SlideShape]) {
        var fresh: [Int: ShapeGroup] = [:]
        // One member copied alone is no group.
        var count: [Int: Int] = [:]
        for c in copies { if let k = c.group?.key { count[k, default: 0] += 1 } }
        for c in copies where c.group.map({ count[$0.key] == 1 }) ?? false { c.group = nil }
        var next = (currentSlide.shapes.compactMap { $0.group?.key }.max() ?? 0) + 1
        for c in copies {
            guard var g = c.group else { continue }
            if let known = fresh[g.key] { c.group = known; continue }
            g.key = next; g.fileId = nil; next += 1
            fresh[c.group!.key] = g
            c.group = g
        }
    }

    enum Align { case left, center, right, top, middle, bottom }

    /// Arrange > Align > Align to Slide (true) or Align Selected Objects (false, the default): what Align and Distribute
    /// measure against when several shapes are selected. One shape always goes by the slide. Kept for the session, as
    /// PowerPoint keeps it.
    private(set) var alignToSlide = false

    func setAlignToSlide(_ on: Bool) {
        guard alignToSlide != on else { return }
        alignToSlide = on
        notifyViewChanged()
    }

    /// Whether Align and Distribute go by the slide for the current selection.
    var alignsBySlide: Bool { selection.count == 1 || alignToSlide }

    /// The box Align and Distribute work within: the slide, or the box around the selection.
    private var _alignBox: Rect {
        alignsBySlide
            ? Rect.fromLTWH(0, 0, slideSize.width, slideSize.height)
            : selection.dropFirst().reduce(selection[0].frame) { $0.expandToInclude($1.frame) }
    }

    /// Distribute needs three shapes among themselves; by the slide, one is enough.
    var canDistribute: Bool { alignsBySlide ? !selection.isEmpty : selection.count >= 3 }

    /// Distribute Horizontally / Vertically: the shapes, in order of their centres, spaced with equal gaps from the
    /// first edge of the box to its last: the box around the selection (so the outermost shapes stay put), or the slide,
    /// whose edges the first and last then touch (one shape alone goes to its middle).
    func distribute(horizontal: Bool) {
        guard canDistribute else { return }
        _checkpoint()
        let box = _alignBox
        func start(_ r: Rect) -> Double { horizontal ? r.left : r.top }
        func size(_ r: Rect) -> Double { horizontal ? r.width : r.height }
        let order = selection.enumerated().sorted {
            let a = horizontal ? $0.element.frame.center.dx : $0.element.frame.center.dy
            let b = horizontal ? $1.element.frame.center.dx : $1.element.frame.center.dy
            return a != b ? a < b : $0.offset < $1.offset
        }.map(\.element)
        let lo = start(box), span = size(box)
        let total = order.reduce(0) { $0 + size($1.frame) }
        var at: Double, gap: Double
        if order.count == 1 {
            gap = 0; at = lo + (span - total) / 2
        } else {
            gap = (span - total) / Double(order.count - 1); at = lo
        }
        for s in order {
            let f = s.frame
            s.frame = horizontal ? Rect.fromLTWH(at, f.top, f.width, f.height) : Rect.fromLTWH(f.left, at, f.width, f.height)
            at += size(f) + gap
        }
        _changed()
    }

    /// One shape aligns to the slide; several align to the box around them, or to the slide with Align to Slide on.
    func align(_ how: Align) {
        guard !selection.isEmpty else { return }
        _checkpoint()
        let box = _alignBox
        for s in selection {
            let f = s.frame
            var x = f.left, y = f.top
            switch how {
            case .left: x = box.left
            case .center: x = box.left + (box.width - f.width) / 2
            case .right: x = box.right - f.width
            case .top: y = box.top
            case .middle: y = box.top + (box.height - f.height) / 2
            case .bottom: y = box.bottom - f.height
            }
            s.frame = Rect.fromLTWH(x, y, f.width, f.height)
        }
        _changed()
    }

    // MARK: Undo

    /// Editing of a text body began: its typing collects into one step.
    func beginTextSession() {
        _sessionWanted = true
        if _session == nil { _session = (snapshot(), _textRevisions()) }
    }

    /// Editing ended: the typing, if any, becomes one undo step.
    func endTextSession() {
        _flushSession()
        _sessionWanted = false
    }

    func undo() {
        _flushSession()
        guard let state = _undo.popLast() else { ScreenReader.announce("Nothing to undo"); return }
        ScreenReader.announce("Undo")
        _redo.append(snapshot())
        restore(state, keepSelection: true)
    }

    func redo() {
        _flushSession()
        guard let state = _redo.popLast() else { ScreenReader.announce("Nothing to redo"); return }
        ScreenReader.announce("Redo")
        _undo.append(snapshot())
        restore(state, keepSelection: true)
    }

    private var _sessionChanged: Bool {
        guard let s = _session else { return false }
        return _textRevisions() != s.revisions
    }

    private func _flushSession() {
        if let s = _session, _textRevisions() != s.revisions {
            _undo.append(s.state)
            if _undo.count > Self._undoLimit { _undo.removeFirst() }
            _redo.removeAll()
        }
        _session = nil
    }

    /// Called first by every edit: what the deck was becomes an undo step.
    func _checkpoint() {
        edits += 1
        _flushSession()
        _undo.append(snapshot())
        if _undo.count > Self._undoLimit { _undo.removeFirst() }
        _redo.removeAll()
    }

    func snapshot() -> DeckState {
        DeckState(slides: slides.map { slide in
            SlideState(id: slide.id, layout: slide.layout, hidden: slide.hidden, section: slide.section, masterRole: slide.masterRole,
                       hideMasterShapes: slide.hideMasterShapes, clrMapOvrXML: slide.clrMapOvrXML,
                       extLstXML: slide.extLstXML, cSldExtLstXML: slide.cSldExtLstXML,
                       controlsXML: slide.controlsXML, custDataXML: slide.custDataXML, decorations: slide.decorations.map(_state),
                       notes: slide.notes.document, shapes: slide.shapes.map(_state),
                       layoutPart: slide.layoutPart, backgroundXML: slide.backgroundXML,
                       background: slide.background, inheritedBackground: slide.inheritedBackground,
                       sourcePart: slide.sourcePart,
                       transition: slide.transition, timingXML: slide.timingXML,
                       footerFrames: slide.footerFrames, animations: slide.animations,
                       sourceAnimations: slide.sourceAnimations, commentsFrom: slide.commentsFrom ?? slide.sourcePart)
        }, current: current, slideSize: slideSize, theme: theme, ownTemplates: ownTemplates, recolourTheme: recolourTheme, firstSlideNum: firstSlideNum, masterBackground: masterBackground, slideScaling: slideScaling, show: show, customShows: customShows, sections: sections, sourceShow: sourceShow)
    }

    /// Put the deck back as `state` was. Objects that still exist are kept
    /// (and their text reloaded only when it differs), so an editor bound to
    /// a body stays bound. `keepSelection`: the selected shapes that are still on the current slide stay selected,
    /// as PowerPoint keeps them after an undo or redo (the ribbon then still shows their formatting).
    func restore(_ state: DeckState, keepSelection: Bool = false) {
        let selectedIds = keepSelection ? Set(selection.map(\.id)) : []
        var oldSlides: [Int: Slide] = [:]
        var oldShapes: [Int: SlideShape] = [:]
        for slide in slides {
            oldSlides[slide.id] = slide
            for shape in slide.shapes { oldShapes[shape.id] = shape }
        }
        var kept = Set<ObjectIdentifier>()
        var next: [Slide] = []
        for ss in state.slides {
            let shapes: [SlideShape] = ss.shapes.map { st in
                if let shape = oldShapes[st.id], shape.kind.sameObject(st.kind), (shape.text == nil) == (st.text == nil) {
                    _apply(st, to: shape)
                    kept.insert(ObjectIdentifier(shape))
                    return shape
                }
                let shape = _make(st)
                _watch(shape)
                return shape
            }
            let slide: Slide
            if let old = oldSlides[ss.id] {
                slide = old
                slide.shapes = shapes
                slide.layout = ss.layout
                kept.insert(ObjectIdentifier(slide))
                if slide.notes.document != ss.notes { slide.notes.load(ss.notes) }
            } else {
                slide = Slide(id: ss.id, layout: ss.layout, shapes: shapes, notes: _textController(ss.notes))
                slide.notes.addListener({ [weak self] in self?._textChanged() }, owner: self)
            }
            slide.hidden = ss.hidden
            slide.section = ss.section
            slide.masterRole = ss.masterRole
            slide.hideMasterShapes = ss.hideMasterShapes
            slide.clrMapOvrXML = ss.clrMapOvrXML
            slide.extLstXML = ss.extLstXML
            slide.cSldExtLstXML = ss.cSldExtLstXML
            slide.controlsXML = ss.controlsXML
            slide.custDataXML = ss.custDataXML
            if slide.decorations.map(_state) != ss.decorations { slide.decorations = ss.decorations.map(_make) }
            slide.layoutPart = ss.layoutPart
            slide.backgroundXML = ss.backgroundXML
            slide.background = ss.background
            slide.inheritedBackground = ss.inheritedBackground
            slide.sourcePart = ss.sourcePart
            slide.transition = ss.transition
            slide.timingXML = ss.timingXML
            slide.footerFrames = ss.footerFrames
            slide.animations = ss.animations
            slide.sourceAnimations = ss.sourceAnimations
            slide.commentsFrom = ss.commentsFrom
            next.append(slide)
        }
        for slide in slides {
            if !kept.contains(ObjectIdentifier(slide)) { slide.notes.removeListeners(owner: self) }
            for shape in slide.shapes where !kept.contains(ObjectIdentifier(shape)) { _unwatch(shape) }
        }
        slides = next
        slideSize = state.slideSize
        firstSlideNum = state.firstSlideNum
        masterBackground = state.masterBackground
        slideScaling = state.slideScaling
        show = state.show
        sourceShow = state.sourceShow
        customShows = state.customShows
        sections = state.sections
        if let t = state.theme { theme = t }
        if let o = state.ownTemplates { ownTemplates = o }
        if let r = state.recolourTheme { recolourTheme = r }
        current = max(0, min(state.current, slides.count - 1))
        selection = selectedIds.isEmpty || slides.isEmpty ? [] : slides[current].shapes.filter { selectedIds.contains($0.id) }
        _nextId = max(_nextId, (state.slides.flatMap { [$0.id] + $0.shapes.map(\.id) }.max() ?? 0) + 1)
        _changed()
    }

    func _state(_ s: SlideShape) -> ShapeState {
        var st = ShapeState(id: s.id, name: s.name, kind: s.kind, frame: s.frame, rotation: s.rotation,
                   fill: s.fill, outline: s.outline, outlineWidth: s.outlineWidth, anchor: s.anchor,
                   insets: s.insets, prompt: s.prompt, text: s.text?.document,
                   font: s.textTheme?.fontFamily, size: s.textTheme?.fontSize ?? 18,
                   color: s.textTheme?.textColor ?? theme.text, listIndent: s.textTheme?.listIndent ?? 18,
                   phType: s.phType, phIdx: s.phIdx, fillScheme: s.fillScheme, crop: s.crop,
                   flipH: s.flipH, flipV: s.flipV, aspectLock: s.aspectLock, pictureGeometry: s.pictureGeometry,
                   pictureAlpha: s.pictureAlpha, pictureDuotone: s.pictureDuotone, pictureColorChange: s.pictureColorChange,
                   pictureInset: s.pictureInset,
                   fillsWithBackground: s.fillsWithBackground, inheritedPreset: s.inheritedPreset,
                   customPath: s.customPath, fillStyle: s.fillStyle, invisible: s.invisible, fileId: s.fileId,
                   sourceXML: s.sourceXML, sourceText: s.sourceText, sourcePart: s.sourcePart,
                   sourceChart: s.sourceChart, field: s.field, group: s.group, keptLine: s.keptLine,
                   altText: s.altText, altTitle: s.altTitle, link: s.link, linkTip: s.linkTip, keptPicture: s.keptPicture, autofit: s.autofit, fontScale: s.fontScale,
                   insetsFollowFont: s.insetsFollowFont, keptLook: s.keptLook)
        // A read shape keeps its own XML and an edit patches only what changed, so a run says only what it
        // said in the file or what the user set: regenerating it would pin every resolved size, bold and
        // italic onto the run and stop it following its layout and master.
        st.readShape = s.readShape
        st.lineReduction = s.lineReduction
        st.pictureLevels = s.pictureLevels
        st.sizeGroup = s.sizeGroup
        st.generatedHang = s.generatedHang
        st.outlineDash = s.outlineDash
        st.outlineJoin = s.outlineJoin
        st.outlineCap = s.outlineCap
        st.media = s.media
        st.outlineFill = s.outlineFill
        st.outlineScheme = s.outlineScheme
        st.themeStyle = s.themeStyle
        st.quickStyle = s.quickStyle
        st.headEnd = s.headEnd
        st.connStart = s.connStart
        st.adjusts = s.adjusts
        st.connAnchor = s.connAnchor
        st.connEnd = s.connEnd
        st.outlineCompound = s.outlineCompound
        st.tailEnd = s.tailEnd
        st.textTurn = s.textTurn
        st.textStacked = s.textStacked
        st.uprightIdeographs = s.uprightIdeographs
        st.sidewaysDigits = s.sidewaysDigits
        st.textSpin = s.textSpin
        st.textRev = s.textRev
        st.textScene = s.textScene
        st.naturalLines = s.naturalLines
        st.shadow = s.shadow
        st.reflection = s.reflection
        st.innerShadow = s.innerShadow
        st.glowRadius = s.glowRadius
        st.glowColor = s.glowColor
        st.softEdge = s.softEdge
        st.bevel = s.bevel
        st.shapeInsets = s.shapeInsets
        st.noWrap = s.noWrap
        st.anchorCentred = s.anchorCentred
        st.bodyVert = s.bodyVert
        st.bodyWrap = s.bodyWrap
        st.fitRule = s.fitRule
        st.columns = s.columns
        st.columnGap = s.columnGap
        st.warp = s.warp
        st.runLooks = s.runLooks
        st.scene3d = s.scene3d
        st.camera = s.camera
        if case .chart = s.kind { st.chartDrawing = s.rendered.map(_state) }
        // ...but only while nothing beyond its place, name, link and text has changed since the read: a fill,
        // line, shadow or other look edit regenerates the shape, which merges the look it kept (`keptLook`).
        // (A master page patches every edit into its own XML: a layout's list styles are not modelled.)
        if !inMasterView, st.readShape != nil, let base = s.readState, !Self._onlyPatchableEdits(st, since: base) { st.readShape = nil }
        return st
    }

    /// Redraws without recording anything (a preview).
    func _redrawOnly() { revision += 1; notifyListeners() }

    /// Puts a shape back as `st` was, after a preview drew on it.
    func _restoreLook(_ st: ShapeState, to shape: SlideShape) { _apply(st, to: shape) }

    private func _apply(_ st: ShapeState, to shape: SlideShape) {
        shape.name = st.name
        shape.kind = st.kind
        shape.frame = st.frame
        shape.rotation = st.rotation
        shape.fill = st.fill
        shape.outline = st.outline
        shape.outlineWidth = st.outlineWidth
        shape.anchor = st.anchor
        shape.insets = st.insets
        shape.prompt = st.prompt
        shape.phType = st.phType
        shape.phIdx = st.phIdx
        // The text's look: a new theme object when it differs (undoing a
        // theme), never an edit in place.
        if st.text != nil, let tt = shape.textTheme,
           tt.fontFamily != st.font || tt.fontSize != st.size || tt.textColor != st.color || tt.listIndent != st.listIndent
            // (spcFirstLastPara="1" keeps the first paragraph's space before whatever the look: e01f56c5361e p35's box, space before 6 pt, sat 6 pt high.)
            || (st.keepsFirstSpace && tt.omitsLeadingSpace) {
            let fresh = _textTheme(font: st.font ?? theme.bodyFont, size: st.size, color: st.color)
            fresh.listIndent = st.listIndent
            if st.textTurn == 0, st.textStacked == 0 { fresh.faceResolver = { var f = SlideFonts.face($0, $1); f?.boldIdeographScale = nil; return f } }
            if st.keepsFirstSpace { fresh.omitsLeadingSpace = false }
            if st.naturalLines { Self.naturalLines(fresh, font: st.font ?? theme.bodyFont, doc: st.text) }
            shape.textTheme = fresh
        }
        shape.crop = st.crop
        shape.flipH = st.flipH
        shape.flipV = st.flipV
        shape.aspectLock = st.aspectLock
        shape.pictureGeometry = st.pictureGeometry
        shape.pictureAlpha = st.pictureAlpha
        shape.pictureDuotone = st.pictureDuotone
        shape.pictureLevels = st.pictureLevels
        shape.pictureColorChange = st.pictureColorChange
        shape.pictureInset = st.pictureInset
        shape.fillsWithBackground = st.fillsWithBackground
        shape.inheritedPreset = st.inheritedPreset
        shape.customPath = st.customPath
        shape.fillStyle = st.fillStyle
        shape.invisible = st.invisible
        if case .opaque(let o) = st.kind, !o.rendering.isEmpty {
            if shape.rendered.map(_state) != o.rendering {
                shape.rendered = o.rendering.map(_make)
                // A diagram's text is fitted to its shape, as PowerPoint
                // lays it out; the drawing part's size is only a cache.
                // (Laid out here, a diagram's words stay whole, as PowerPoint
                // fits them; a drawing part's text was fitted by PowerPoint.)
                // (A text box inside an AlternateContent branch (an equation's) is no diagram: its normAutofit with no fontScale means
                // PowerPoint printed it at full size, as 51f605f6 p22's body does, overflowing its box by design.)
                for r in shape.rendered where r.autofit && r.fontScale == 1 && !o.fromAlternate {
                    r.fontScale = SlideTextCache.autofitScale(r, wholeWords: r.insetsFollowFont)
                }
                // Laid out here, the shapes that start from one size end at
                // one size — the smallest any of them needed — as PowerPoint
                // keeps a diagram's nodes alike (`primFontSz op="equ"`, which
                // every built-in layout asks of its nodes).
                // (By the layout's own grouping where it names one: the
                // shapes one `op="equ"` constraint ties together.)
                var smallest: [String: Double] = [:]
                func nominal(_ r: SlideShape) -> String? {
                    guard r.autofit, r.insetsFollowFont else { return nil }
                    if let g = r.sizeGroup { return "g" + g }
                    return (r.text?.document.paragraphs.first?.runs.first?.style.fontSize).map { "s\($0)" }
                }
                for r in shape.rendered { if let n = nominal(r) { smallest[n] = min(smallest[n] ?? 1, r.fontScale) } }
                for r in shape.rendered { if let n = nominal(r), let s = smallest[n] { r.fontScale = s } }
                // A hang this layout generated from the unshrunk size follows
                // the size the text ended at (cycle-matrix's side boxes:
                // 8 pt in PowerPoint, not 22.5); a stated hang stays.
                for r in shape.rendered where r.generatedHang && r.autofit && r.fontScale < 1 {
                    if let tt = r.textTheme { tt.listIndent = max(4.5, tt.listIndent * r.fontScale) }
                }
            }
        } else if case .chart = st.kind, !st.chartDrawing.isEmpty {
            if shape.rendered.map(_state) != st.chartDrawing { shape.rendered = st.chartDrawing.map(_make) }
        } else if !shape.rendered.isEmpty {
            shape.rendered = []
        }
        shape.fileId = st.fileId
        shape.fillScheme = st.fillScheme
        shape.outlineScheme = st.outlineScheme
        shape.themeStyle = st.themeStyle
        shape.quickStyle = st.quickStyle
        shape.sourceXML = st.sourceXML
        shape.sourceText = st.sourceText
        shape.sourcePart = st.sourcePart
        shape.readShape = st.readShape
        shape.sourceChart = st.sourceChart
        shape.field = st.field
        shape.fieldShown = nil
        shape.group = st.group
        shape.keptLine = st.keptLine
        shape.keptPicture = st.keptPicture
        shape.altText = st.altText
        shape.altTitle = st.altTitle
        shape.link = st.link
        shape.linkTip = st.linkTip
        shape.autofit = st.autofit
        shape.fontScale = st.fontScale
        shape.insetsFollowFont = st.insetsFollowFont
        shape.sizeGroup = st.sizeGroup
        shape.generatedHang = st.generatedHang
        shape.outlineDash = st.outlineDash
        shape.outlineJoin = st.outlineJoin
        shape.outlineCap = st.outlineCap
        shape.media = st.media
        shape.outlineFill = st.outlineFill
        shape.headEnd = st.headEnd
        shape.connStart = st.connStart
        shape.adjusts = st.adjusts
        shape.connAnchor = st.connAnchor
        shape.connEnd = st.connEnd
        shape.outlineCompound = st.outlineCompound
        shape.tailEnd = st.tailEnd
        shape.textTurn = st.textTurn
        shape.textStacked = st.textStacked
        shape.uprightIdeographs = st.uprightIdeographs
        shape.sidewaysDigits = st.sidewaysDigits
        shape.textSpin = st.textSpin
        shape.textRev = st.textRev
        shape.textScene = st.textScene
        shape.naturalLines = st.naturalLines
        shape.shadow = st.shadow
        shape.innerShadow = st.innerShadow
        shape.reflection = st.reflection
        shape.glowRadius = st.glowRadius
        shape.glowColor = st.glowColor
        shape.softEdge = st.softEdge
        shape.bevel = st.bevel
        shape.shapeInsets = st.shapeInsets
        shape.noWrap = st.noWrap
        shape.anchorCentred = st.anchorCentred
        shape.bodyVert = st.bodyVert
        shape.bodyWrap = st.bodyWrap
        shape.fitRule = st.fitRule
        shape.columns = st.columns
        shape.columnGap = st.columnGap
        shape.warp = st.warp
        shape.runLooks = st.runLooks
        shape.scene3d = st.scene3d
        shape.camera = st.camera
        shape.lineReduction = st.lineReduction
        shape.textTheme?.lineSpacingReduction = st.lineReduction
        shape.keptLook = st.keptLook
        if let doc = st.text, let c = shape.text, c.document != doc { c.load(doc) }
        shape.readState = nil
        if st.readShape != nil { shape.readState = _state(shape) }
    }

    /// `now` differs from `base` only in its place, name, link or text.
    static func _onlyPatchableEdits(_ now: ShapeState, since base: ShapeState) -> Bool {
        var b = base
        b.frame = now.frame; b.rotation = now.rotation; b.flipH = now.flipH; b.flipV = now.flipV
        b.invisible = now.invisible; b.aspectLock = now.aspectLock
        b.name = now.name; b.link = now.link; b.linkTip = now.linkTip; b.text = now.text; b.readShape = now.readShape
        // A yellow handle's drag: the adjust values are patched into the shape's own `a:prstGeom`, and the outline
        // and text rectangle drawn from them follow (the text frame's own margins unchanged).
        b.adjusts = now.adjusts; b.customPath = now.customPath
        if now.insets.minusShare(now.shapeInsets) == base.insets.minusShare(base.shapeInsets) {
            b.insets = now.insets; b.shapeInsets = now.shapeInsets
        }
        return b == now
    }

    private func _make(_ st: ShapeState) -> SlideShape {
        let theme = st.text == nil ? nil : _textTheme(font: st.font ?? self.theme.bodyFont, size: st.size, color: st.color)
        theme?.listIndent = st.listIndent
        // (The emboldened ideograph's 0.983 step is a column's: along a horizontal line it steps a full em, lab vk against 1892a5a76df6 p207.)
        if st.textTurn == 0, st.textStacked == 0 { theme?.faceResolver = { var f = SlideFonts.face($0, $1); f?.boldIdeographScale = nil; return f } }
        if st.naturalLines, let theme { Self.naturalLines(theme, font: st.font ?? self.theme.bodyFont, doc: st.text) }
        if st.textTurn > 0, !st.uprightIdeographs, let theme { let own = theme.ownDescentShare; theme.ownDescentShare = { SlideFonts.sidewaysColumnShare($0) ?? own?($0) } }
        let shape = SlideShape(id: st.id, name: st.name, kind: st.kind, frame: st.frame,
                               text: st.text.map(_textController), textTheme: theme,
                               anchor: st.anchor, prompt: st.prompt)
        _apply(st, to: shape)
        return shape
    }

    // MARK: Building

    func _id() -> Int {
        defer { _nextId += 1 }
        return _nextId
    }

    private func _makeSlide(_ layout: SlideLayoutKind) -> Slide {
        let shapes = layout.placeholders.map(_makeShape)
        let notes = _textController(RichDocument(paragraphs: [
            RichParagraph(text: "", style: RichParagraphStyle(spaceAfter: 0, lineSpacing: 1.0)),
        ]))
        let slide = Slide(id: _id(), layout: layout, shapes: shapes, notes: notes)
        slide.inheritedBackground = masterBackground
        _watch(slide)
        return slide
    }

    private func _makeShape(_ spec: PlaceholderSpec) -> SlideShape {
        let sx = slideSize.width / 960
        let sy = slideSize.height / 540
        let f = spec.frame
        let theme = _textTheme(font: spec.heading ? self.theme.headingFont : self.theme.bodyFont,
                               size: spec.fontSize,
                               color: spec.subtle ? self.theme.subtle : self.theme.text)
        // PowerPoint's master: 90% line spacing, 10 pt before each body
        // paragraph, nothing after.
        let style = RichParagraphStyle(alignment: spec.alignment, spaceBefore: spec.bullets ? 10 : 0,
                                       spaceAfter: 0, lineSpacing: 0.9,
                                       list: spec.bullets ? .bullet : nil)
        let doc = RichDocument(paragraphs: [RichParagraph(text: "", style: style)])
        let shape = SlideShape(id: _id(), name: spec.name, kind: .placeholder(spec.role),
                               frame: Rect.fromLTWH(f.left * sx, f.top * sy, f.width * sx, f.height * sy),
                               text: _textController(doc), textTheme: theme, anchor: spec.anchor,
                               prompt: spec.prompt)
        shape.phType = spec.phType
        shape.phIdx = spec.phIdx
        // PowerPoint's placeholders shrink their text to fit.
        shape.autofit = true
        return shape
    }

    /// The scale an autofit shape's text is drawn at, as the shell measures
    /// it: not an edit of its own (the typing that needed it is).
    func setFontScale(_ shape: SlideShape, _ scale: Double) {
        guard shape.autofit, abs(shape.fontScale - scale) > 1e-6 else { return }
        shape.fontScale = scale
        revision += 1
        notifyListeners()
    }

    private func _copy(_ shape: SlideShape, offset: Double = 0, keepGroup: Bool = false) -> SlideShape {
        var st = _state(shape)
        st.id = _id()
        st.fileId = nil
        st.sourceXML = nil
        if !keepGroup { st.group = nil }
        st.keptLine = nil
        st.keptPicture = nil
        st.frame = st.frame.shift(Offset(offset, offset))
        return _make(st)
    }

    /// A diagram's text steps its lines at its face's own height (Calibri's
    /// 1.22, Courier New's 1.13), not the 1.2 of every other text:
    /// customGeo's 17 pt bullets at 90% stand 18.66 apart in PowerPoint's
    /// print, 0.9 of Calibri's line, and tdf149551's Courier ones 0.9 of
    /// Courier's.
    static func naturalLines(_ theme: RichTextTheme, font: String, doc: RichDocument? = nil) {
        // (Run by run, by the face each is drawn in; the box's own face
        // for what reads the theme's single line.)
        theme.faceLineHeight = SlideFonts.drawnNaturalHeight
        theme.naturalLinesPerFace = true
        let family = theme.fontFamilyResolver?(font) ?? font
        theme.namedLineHeight = { SlideFonts.diagramEastAsianLine($0)?.height }
        theme.ownDescentShare = { SlideFonts.diagramEastAsianLine($0)?.share ?? SlideFonts.ownDescentShare($0) }
        // (A box whose own text names an East Asian face stands on that face's line, whatever the box's default.)
        let named = doc?.paragraphs.lazy.flatMap { $0.runs }.filter { $0.length > 0 }
            .compactMap { r in [r.style.eastAsiaFontFamily, r.style.fontFamily].compactMap { $0 }.first { SlideFonts.diagramEastAsianLine($0) != nil } }.first
        theme.singleLineHeight = (named ?? font).flatMap { SlideFonts.diagramEastAsianLine($0)?.height } ?? SlideFonts.ownNaturalHeight(font) ?? theme.naturalLineHeight(family: family, bold: false, italic: false)
    }

    func _textTheme(font: String, size: Double, color: Color) -> RichTextTheme {
        let theme = RichTextTheme(fontFamily: font, fontSize: size, textColor: color, caretColor: color,
                                  headingColor: nil, listIndent: 18)
        theme.fontFamilyResolver = SlideFonts.resolve
        theme.baselineScalesWithSpacing = SlideFonts.isArabicLineFace
        theme.ownDescentShare = SlideFonts.ownDescentShare   // and sets a baseline by the face named
        theme.faceMissingOnWindows = { OfficeFonts.installed($0) == nil && SlideFonts.ownDescentShare($0) == nil && SlideFonts.diagramEastAsianLine($0) == nil }
        theme.uprightColumn = { SlideFonts.uprightColumn($0, bold: $1) }
        theme.uprightDigitAscent = { SlideFonts.uprightDigitAscent($0, bold: $1) }
        theme.faceResolver = SlideFonts.face                 // and sets Lucida Sans Unicode at its own widths
        // (A Japanese or Korean face PowerPoint has draws its kana, ideographs and Hangul in the bundled face of its own language,
        // not the glyph fallback's Simplified Chinese one: ja-9ce6e01e5f's MS PGothic 直 and 骨 printed in the Chinese forms.)
        theme.ideographFace = SlideFonts.ownIdeographFace
        theme.setsFaceAdvances = true
        theme.symbolAdvance = Metafile.symbolAdvance   // and sets a Symbol run's glyphs at the face's own advances
        theme.scriptSizeWholeUp = true      // and sets a raised run at two thirds of its size
        theme.scalesGlyphsToTables = true
        theme.measuresShownCaps = true      // and fits a run in capitals by its capitals
        theme.kernsByRun = true             // and kerns a run only from its `kern` size up
        // (No `cellLineShift`: PowerPoint for Windows keeps a cell's lines at their pitch, as it does a box's.)
        theme.cellLinesPastCorners = true   // and runs a cell's own lines half their width past its corners
        theme.exactLineDescentShare = 0.22  // and sets a line of so many points' baseline 0.78 down it, whatever the face
        theme.exactLineDescentOfSize = 0.25 // but no less than a quarter of its text's size above its foot
        theme.exactLinesAsPowerPoint = true
        theme.extraAboveShare = 0.7         // and puts 0.7 of a spacing over single's extra above the line
        theme.marksEmptyListItems = false   // PowerPoint shows no bullet on an empty paragraph
        theme.markersAtHang = true          // and puts the bullet at marL + indent
        theme.singleLineHeight = 1.2        // spaces lines by the size, not the face
        theme.exactSingleLineEm = { SlideFonts.exactSingleLineEm($0) }
        theme.omitsLeadingSpace = true      // and leaves out the space before a body's first paragraph
        theme.disablesLigatures = true      // and sets "tt" as two letters
        theme.outlineOverFill = true
        theme.officeLatinBreaks = true      // and parts Latin text at spaces and hyphens, not after "/"
        theme.advanceGrid = 0.125           // and sets each glyph on an eighth of a point, as its print does
        theme.advanceGridOfFaceTables = true
        theme.fontSizeGrid = 0.12           // at a size on 1/600 in, as its print shows (32 pt is 32.04)
        theme.tableRulesTakeRoom = false    // and draws a table's lines over its rows
        theme.collapsesParagraphSpacing = false   // and sets the space after AND the space before
        return theme
    }

    func _textController(_ doc: RichDocument) -> RichDocumentController {
        let c = RichDocumentController()
        c.clipboardCodec = OfficeClipboardCodec()
        c.load(doc)
        return c
    }

    static func darker(_ c: Color) -> Color { shade(c, 0.7) }

    /// DrawingML's `a:shade` as PowerPoint draws it: mixed with black in
    /// linear light (accent1 4472C4 at 50% is 2F528F).
    static func shadeLinear(_ c: Color, _ amount: Double) -> Color {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func srgb(_ l: Double) -> Double { l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055 }
        let v = c.value
        func ch(_ shift: Int64) -> Int64 {
            Int64((srgb(lin(Double((v >> shift) & 0xFF) / 255) * amount) * 255).rounded())
        }
        return Color(0xFF00_0000 | (ch(16) << 16) | (ch(8) << 8) | ch(0))
    }

    /// DrawingML's `shade`: each channel scaled toward black.
    static func shade(_ c: Color, _ amount: Double) -> Color {
        let v = c.value
        let r = Int(Double((v >> 16) & 0xFF) * amount), g = Int(Double((v >> 8) & 0xFF) * amount)
        let b = Int(Double(v & 0xFF) * amount)
        return Color(0xFF00_0000 | Int64((r << 16) | (g << 8) | b))
    }

    // MARK: Change tracking

    func _watch(_ slide: Slide) {
        slide.notes.addListener({ [weak self] in self?._textChanged() }, owner: self)
        for shape in slide.shapes { _watch(shape) }
    }

    func _watch(_ shape: SlideShape) {
        shape.text?.addListener({ [weak self] in self?._textChanged() }, owner: self)
    }

    private func _unwatch(_ slide: Slide) {
        slide.notes.removeListeners(owner: self)
        for shape in slide.shapes { _unwatch(shape) }
    }

    private func _unwatch(_ shape: SlideShape) {
        shape.text?.removeListeners(owner: self)
    }

    private func _textRevisions() -> [ObjectIdentifier: Int] {
        var r: [ObjectIdentifier: Int] = [:]
        for slide in slides {
            r[ObjectIdentifier(slide.notes)] = slide.notes.revision
            for c in slide.shapes.compactMap(\.text) { r[ObjectIdentifier(c)] = c.revision }
        }
        return r
    }

    private var _lastTextRevisions: [ObjectIdentifier: Int] = [:]

    /// Caret moves notify too; only a change to the words moves the deck on.
    private func _textChanged() {
        let now = _textRevisions()
        guard now != _lastTextRevisions else { return }
        _lastTextRevisions = now
        // A field showing its new value is not an edit.
        if _updatingFields { return }
        edits += 1
        revision += 1
        notifyListeners()
    }

    private func _notify() {
        revision += 1
        notifyListeners()
    }

    /// After an edit. An open text session restarts from here, so the edit
    /// and the typing after it are separate steps.
    private var _updatingFields = false

    /// Fields show what they stand for now: a slide number follows the
    /// slide's place, a date is today's. Text typed over a field makes it
    /// text, as in PowerPoint.
    private func _updateFields() {
        _updatingFields = true
        defer { _updatingFields = false }
        for (i, slide) in slides.enumerated() {
            for shape in slide.shapes {
                guard let field = shape.field, let c = shape.text else { continue }
                var doc = c.document
                let at = doc.paragraphs.firstIndex { !$0.text.isEmpty } ?? 0
                guard doc.paragraphs.indices.contains(at) else { continue }
                let shown = doc.paragraphs[at].text
                if let last = shape.fieldShown, last != shown {
                    shape.field = nil
                    shape.fieldShown = nil
                    continue
                }
                let want = field.value(slide: i + firstSlideNum)
                shape.fieldShown = want
                guard shown != want else { continue }
                let style = doc.paragraphs[at].runs.first?.style ?? CharStyle()
                doc.paragraphs[at].text = want
                doc.paragraphs[at].runs = [Run(length: want.utf16.count, style: style)]
                c.load(doc)
            }
        }
    }

    func _changed(keepSession: Bool = false) {
        followConnections()
        _updateFields()
        // A shape that went takes its animations with it.
        for slide in slides where !slide.animations.isEmpty {
            let ids = Set(slide.shapes.map(\.id))
            slide.animations.removeAll { !ids.contains($0.shapeId) }
        }
        if _sessionWanted && !keepSession && _session == nil {
            _session = (snapshot(), _textRevisions())
        }
        _lastTextRevisions = _textRevisions()
        revision += 1
        notifyListeners()
    }
}
