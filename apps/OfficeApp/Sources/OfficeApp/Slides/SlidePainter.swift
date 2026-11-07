// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// One painter for a slide at any size: the thumbnail pane, the slide show
// and PDF export all draw through it, and the editing canvas uses the same
// text measurement to anchor its live editors. Thumbnails cannot be the
// canvas widget shrunk inside a RepaintBoundary — interior repaint
// boundaries paint nothing in this framework (RenderObject.swift,
// `_compositeChild`) — so they are drawn, not composited.

import Flutter
import OfficeText
import FlutterSwiftBridge
import Foundation

/// Laid-out text bodies, reused while the words, the width and the scale
/// stay put.
final class SlideTextCache {
    private struct Entry {
        let revision: Int
        let width: Double
        let scale: Double
        let fontScale: Double
        /// The text theme laid out with: a new one (a theme applied) is a miss.
        let theme: ObjectIdentifier
        let layout: RichLayout
    }
    private var _entries: [ObjectIdentifier: Entry] = [:]
    private var _images: [String: Image] = [:]
    /// The pixel sizes (width << 32 | height) of the pictures decoded from a
    /// JPEG: the ones PowerPoint for Windows marks smooth in its PDF.
    nonisolated(unsafe) static var jpegSizes: Set<UInt64> = []
    /// Sizes of tiled pictures with an alpha mask that PowerPoint still marks smooth.
    nonisolated(unsafe) static var alphaSmooth: Set<UInt64> = []
    static func noteJpeg(_ bytes: [UInt8], _ image: Image) {
        if bytes.starts(with: [0xFF, 0xD8]) { jpegSizes.insert(UInt64(image.width) << 32 | UInt64(image.height)) }
    }
    private var _decoding: Set<String> = []
    /// Called when a picture finishes decoding: repaint.
    var onImageDecoded: (() -> Void)?
    /// Another cache whose decoded pictures this one uses (the show's text
    /// is laid out at its own size; its pictures are the editor's).
    weak var imageSource: SlideTextCache?

    /// The decoded picture, or nil while it decodes (the request starts
    /// here, once).
    func image(_ attachment: ImageAttachment) -> Image? {
        if let source = imageSource { return source.image(attachment) }
        if let image = _images[attachment.id] { return image }
        // A metafile is drawing calls, not pixels: `metafile(_:)` plays it.
        if let known = _metafiles[attachment.id] {
            if known != nil { return nil }
        } else if Metafile.isMetafile(attachment.data) {
            return nil
        }
        if _decoding.contains(attachment.id) || _undecodable.contains(attachment.id) { return nil }
        _decoding.insert(attachment.id)
        var bytes = [UInt8](attachment.data)
        // (A TIFF, which the codec does not read, as the BMP of its pixels.)
        if Tiff.isTiff(bytes), let bmp = Tiff.bmp(bytes) { bytes = bmp }
        let id = attachment.id
        Task { @MainActor [weak self] in
            var decoded: Image? = nil
            if let codec = try? await instantiateImageCodec(bytes) {
                decoded = (try? await codec.getNextFrame())?.image
                codec.dispose()
            }
            // (A damaged PNG, made whole as PowerPoint reads it.)
            if decoded == nil, let fixed = Png.repaired(bytes), let codec = try? await instantiateImageCodec(fixed) {
                decoded = (try? await codec.getNextFrame())?.image
                codec.dispose()
            }
            guard let self else { decoded?.dispose(); return }
            self._decoding.remove(id)
            if let decoded {
                Self.noteJpeg(bytes, decoded)
                if self._images[id] == nil { self._images[id] = decoded } else { decoded.dispose() }
                self.onImageDecoded?()
            } else if self._images[id] == nil {
                // Asked once: a picture nothing here can decode (a TIFF or
                // a JPEG XR in the browser) would otherwise be decoded
                // again on every paint, and waited for by every export.
                self._undecodable.insert(id)
            }
        }
        return nil
    }

    /// Decode a picture and come back when it is there (or cannot be) —
    /// an export's way in. It awaits the decode itself rather than
    /// starting one and polling for it, so the wait is the decode's own
    /// length and a picture that cannot be decoded costs nothing twice.
    @MainActor
    func decodeNow(_ attachment: ImageAttachment) async {
        if let source = imageSource { await source.decodeNow(attachment); return }
        let id = attachment.id
        guard _images[id] == nil, !_undecodable.contains(id), !Metafile.isMetafile(attachment.data) else { return }
        var decoded: Image? = nil
        var bytes = [UInt8](attachment.data)
        if Tiff.isTiff(bytes), let bmp = Tiff.bmp(bytes) { bytes = bmp }
        if let codec = try? await instantiateImageCodec(bytes) {
            decoded = (try? await codec.getNextFrame())?.image
            codec.dispose()
        }
        if decoded == nil, let fixed = Png.repaired(bytes), let codec = try? await instantiateImageCodec(fixed) {
            decoded = (try? await codec.getNextFrame())?.image
            codec.dispose()
        }
        if let decoded {
            Self.noteJpeg(bytes, decoded)
            if _images[id] == nil { _images[id] = decoded; onImageDecoded?() } else { decoded.dispose() }
        } else if _images[id] == nil {
            _undecodable.insert(id)
        }
    }

    private var _scaled: [String: Image] = [:]
    /// `image` redrawn at w by h pixels.
    func scaled(_ image: Image, _ w: Int, _ h: Int) -> Image? {
        let key = "\(ObjectIdentifier(image).hashValue)/\(w)x\(h)"
        if let known = _scaled[key] { return known }
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, Double(w), Double(h)))
        let paint = Paint()
        paint.filterQuality = .medium
        canvas.drawImageRect(image, Rect.fromLTWH(0, 0, Double(image.width), Double(image.height)), Rect.fromLTWH(0, 0, Double(w), Double(h)), paint)
        guard let out = recorder.endRecording().toImageSync(width: w, height: h) else { return nil }
        _scaled[key] = out
        return out
    }

    private var _withAlpha: [String: Image] = [:]
    /// `image` redrawn at its own size with `alpha` applied to its pixels.
    func withAlpha(_ image: Image, _ alpha: Double) -> Image? {
        let key = "\(ObjectIdentifier(image).hashValue)/\(alpha)"
        if let known = _withAlpha[key] { return known }
        let recorder = NativePictureRecorder()
        let canvas = NativeCanvas(recorder: recorder, cullRect: Rect.fromLTWH(0, 0, Double(image.width), Double(image.height)))
        let w = Double(image.width), h = Double(image.height)
        let paint = Paint()
        paint.color = Color(0xFFFFFFFF).withOpacity(alpha)
        canvas.drawImageRect(image, Rect.fromLTWH(0, 0, w, h), Rect.fromLTWH(0, 0, w, h), paint)
        guard let baked = recorder.endRecording().toImageSync(width: image.width, height: image.height) else { return nil }
        _withAlpha[key] = baked
        return baked
    }

    /// Pictures whose decode failed.
    private var _undecodable: Set<String> = []
    func isUndecodable(_ attachment: ImageAttachment) -> Bool {
        imageSource?.isUndecodable(attachment) ?? _undecodable.contains(attachment.id)
    }

    private var _metafiles: [String: Metafile?] = [:]

    /// The picture as a played metafile, when its bytes are a WMF or an
    /// EMF (parsed once; nil for any other picture, or one that draws
    /// nothing this app reads).
    func metafile(_ attachment: ImageAttachment) -> Metafile? {
        if let source = imageSource { return source.metafile(attachment) }
        if let known = _metafiles[attachment.id] { return known }
        let played = Metafile.isMetafile(attachment.data) ? Metafile(attachment.data, id: attachment.id) : nil
        _metafiles[attachment.id] = .some(played)
        return played
    }

    /// PowerPoint's autofit steps, largest first.
    static let autofitSteps = [1.0, 0.925, 0.85, 0.775, 0.7, 0.625, 0.55, 0.475, 0.4, 0.325, 0.25]

    /// The largest step at which `shape`'s text fits its box. With
    /// `wholeWords`, a step that would break a word across lines does not
    /// count as fitting (a SmartArt shape shrinks its text until the words
    /// are whole, as PowerPoint lays it out).
    static func autofitScale(_ shape: SlideShape, wholeWords: Bool = false) -> Double {
        guard let text = shape.text, let theme = shape.textTheme else { return 1 }
        func fits(_ scale: Double) -> Bool {
            // (The geometry's share of the insets stays: an oval's text
            // was fitted to a box wider than its inscribed one, 53 pt where
            // PowerPoint's is 49.)
            let ins = shape.insets(atFontScale: scale)
            let room = shape.frame.height - ins.top - ins.bottom
            let width = max(1, shape.frame.width - ins.left - ins.right)
            // Measured at a twentieth of a point: lines laid out in whole
            // points round 64.8 down to 64, and a diagram's text came out
            // a point larger than PowerPoint's (59 where its own is 58) —
            // or round 18.65 up to 19, and customGeo's 17 lines of 17 pt
            // took 335 of a 330 pt box that PowerPoint fills to 326.
            let res = 20.0
            let layout = RichLayout(theme: theme, paragraphCount: text.document.paragraphs.count)
            layout.scale = res / theme.pixelsPerPoint
            layout.fontScale = scale
            layout.spacingFollowsFont = shape.insetsFollowFont
            layout.width = width * res
            layout.ensureLaidOut(text.document)
            let height = layout.totalHeight / res
            return height <= room + 0.5 / res && (!wholeWords || widestWord(text.document, theme, scale: scale) <= width + 0.5)
        }
        // A diagram laid out here (its margins follow its font) shrinks by
        // whole points down to its rule's 5 pt, as PowerPoint sets its
        // text — 43, 30, 12 — not by the 7.5% steps of a text box's
        // autofit, which stop at a quarter (cycleMatrix's side boxes were
        // 16 where PowerPoint's are 12).
        if shape.insetsFollowFont, wholeWords,
           let nominal = text.document.paragraphs.first?.runs.first?.style.fontSize, nominal > 5 {
            if fits(1) { return 1 }
            var lo = 5, hi = Int(nominal.rounded(.down)) - 1, best = 5
            while lo <= hi {
                let mid = (lo + hi) / 2
                if fits(Double(mid) / nominal) { best = mid; lo = mid + 1 } else { hi = mid - 1 }
            }
            return Double(best) / nominal
        }
        for scale in autofitSteps where fits(scale) { return scale }
        return autofitSteps.last!
    }

    /// The widest single word of the document at `scale`, as laid out.
    private static func widestWord(_ doc: RichDocument, _ theme: RichTextTheme, scale: Double) -> Double {
        var widest = 0.0
        for p in doc.paragraphs {
            let style = theme.textStyle(for: p.runs.first?.style ?? CharStyle(), in: p.style, scale: scale / theme.pixelsPerPoint)
            for word in p.text.split(separator: " ") where !word.isEmpty {
                let tp = TextPainter(text: TextSpan(text: String(word), style: style), textDirection: .ltr)
                tp.layout(minWidth: 0, maxWidth: .infinity)
                widest = max(widest, tp.width)
                tp.dispose()
            }
        }
        return widest
    }

    /// The body of `shape` laid out at `pxPerPt` device pixels per point.
    func layout(_ shape: SlideShape, pxPerPt: Double) -> RichLayout? {
        guard let text = shape.text, let theme = shape.textTheme else { return nil }
        let width = max(1, (shape.frame.width - shape.drawInsets.left - shape.drawInsets.right) * pxPerPt)
        // The fitted size scales the letters alone: the indents and the box
        // stay the file's.
        let scale = pxPerPt / theme.pixelsPerPoint
        let key = ObjectIdentifier(text)
        if let e = _entries[key], e.revision == text.revision, e.width == width, e.scale == scale, e.fontScale == shape.fontScale,
           e.theme == ObjectIdentifier(theme) {
            return e.layout
        }
        func laidOut(_ w: Double) -> RichLayout {
            let l = RichLayout(theme: theme, paragraphCount: text.document.paragraphs.count)
            l.scale = scale
            l.fontScale = shape.fontScale
            l.spacingFollowsFont = shape.insetsFollowFont
            l.width = w
            if shape.columns > 1, !shape.noWrap {
                // Columns are the layout's pages: one "page" the size of
                // the text's room, cut into columns, each filled to the
                // bottom before the next. (A page is in points of the
                // layout's own scale, which the fitted size is part of.)
                let k = pxPerPt / (theme.pixelsPerPoint * scale)
                let room = max(1, shape.frame.height - shape.drawInsets.top - shape.drawInsets.bottom)
                var page = PageSetup(width: w / pxPerPt * k, height: room * k, marginTop: 0, marginBottom: 0,
                                     marginLeft: 0, marginRight: 0, gap: 0)
                page.columns = shape.columns
                page.columnGap = shape.columnGap * k
                l.pageSetup = page
                l.width = max(1, (w - shape.columnGap * pxPerPt * Double(shape.columns - 1)) / Double(shape.columns))
            }
            l.ensureLaidOut(text.document)
            return l
        }
        var layout = laidOut(width)
        if shape.noWrap {
            // Unwrapped text is as wide as its longest line: the narrowest
            // width at which it has no more lines than at no limit at all
            // (found by widening — the layout says how many lines, not how
            // wide), so paragraphs still align with one another across it.
            func lines(_ l: RichLayout) -> Int {
                (0 ..< l.count).reduce(0) { $0 + l.geometry($1).painter.computeLineMetrics().count }
            }
            let free = lines(laidOut(1_000_000))
            var w = width
            while lines(layout) > free, w < 1_000_000 {
                w *= 1.15
                layout = laidOut(w)
            }
        }
        _entries[key] = Entry(revision: text.revision, width: width, scale: scale, fontScale: shape.fontScale, theme: ObjectIdentifier(theme),
                              layout: layout)
        return layout
    }

    /// Where the first line starts below the shape's top edge, in pixels:
    /// the top inset plus whatever the vertical anchor leaves above the text.
    /// Text taller than the box overflows the way the anchor points (down
    /// for top, both ways for middle, up for bottom), so this can be
    /// negative, as PowerPoint's can.
    func textTop(_ shape: SlideShape, pxPerPt: Double) -> Double {
        let top = shape.drawInsets.top * pxPerPt
        guard let layout = layout(shape, pxPerPt: pxPerPt) else { return top }
        let room = (shape.frame.height - shape.drawInsets.top - shape.drawInsets.bottom) * pxPerPt
        // In columns the text is as tall as its tallest column.
        let height = layout.isPaged
            ? layout.pieces.map { $0.reduce(0) { $0 + $1.height } }.max() ?? 0 : layout.totalHeight
        // (A last line over single does not count its extra foot: see `trailingExtra`.)
        let dropped = layout.isPaged || shape.anchor == .top ? 0 : shape.text.map { layout.trailingExtra($0.document) } ?? 0
        let spare = room - (height - dropped)
        switch shape.anchor {
        case .top: return top
        case .middle: return top + spare / 2
        case .bottom: return top + spare
        }
    }

    /// A shape body's stacked text (`bodyPr vert="wordArtVert"`, `"wordArtVertRtl"`), as PowerPoint prints it (lab
    /// wordartvert): every character upright in a square place 1.414 em on a side, one under the other from the
    /// top of the box (a space takes its place), the next column to the right (to the left for Rtl) once the box's
    /// height is used; a paragraph starts a column of its own. The columns stand together at the start side
    /// (`anchor` top), in the middle (centre) or at the far side (bottom); more than fit run past the box.
    static func paintStacked(_ shape: SlideShape, _ r: Rect, _ px: Double, _ canvas: Canvas, _ cache: SlideTextCache) -> Bool {
        guard let layout = cache.layout(shape, pxPerPt: px) else { return false }
        let ins = shape.drawInsets
        let left = r.left + ins.left * px, top = r.top + ins.top * px
        let width = r.width - (ins.left + ins.right) * px, height = r.height - (ins.top + ins.bottom) * px
        struct Place { var glyph: TextPainter; var column: Int; var row: Int; var size: Double }
        var places: [Place] = []
        var pitches: [Double] = []
        var column = 0
        for i in 0 ..< layout.count {
            guard let root = layout.geometry(i).painter.text else { continue }
            let text = Array(root.toPlainText(includeSemanticsLabels: false, includePlaceholders: true).utf16)
            var styles: [Flutter.TextStyle?] = []
            func walk(_ span: InlineSpan, _ inherited: Flutter.TextStyle?) {
                guard let t = span as? TextSpan else { styles.append(inherited); return }
                let own = inherited.map { $0.merge(t.style) } ?? t.style
                if let s = t.text { styles.append(contentsOf: repeatElement(own, count: s.utf16.count)) }
                for child in t.children ?? [] { walk(child, own) }
            }
            walk(root, nil)
            guard styles.count == text.count, !text.isEmpty else { continue }
            var row = 0
            var k = 0
            var started = false
            while k < text.count {
                let size = styles[k]?.fontSize ?? 18
                let perColumn = max(1, Int(height / (1.414 * size) + 1e-6))
                if row >= perColumn { row = 0; column += 1 }
                if !started { started = true; while pitches.count <= column { pitches.append(1.414 * size) } }
                while pitches.count <= column { pitches.append(1.414 * size) }
                let unit = text[k]
                let end = (unit >= 0xD800 && unit <= 0xDBFF && k + 1 < text.count) ? k + 2 : k + 1
                if unit != 0x20 && unit != 0x00A0 {
                    let g = TextPainter(text: TextSpan(text: String(decoding: text[k ..< end], as: UTF16.self),
                                                       style: styles[k]?.copyWith(letterSpacing: 0)), textDirection: .ltr)
                    g.layout()
                    places.append(Place(glyph: g, column: column, row: row, size: size))
                }
                row += 1
                k = end
            }
            if started { column += 1 }
        }
        guard !places.isEmpty else { return false }
        let block = pitches.reduce(0, +)
        let rtl = shape.textStacked < 0
        // The block's start edge: where the first column stands.
        var start: Double
        switch shape.anchor {
        case .top: start = rtl ? left + width : left
        case .middle: start = rtl ? left + width / 2 + block / 2 : left + width / 2 - block / 2
        case .bottom: start = rtl ? left + block : left + width - block
        }
        var offsets: [Double] = []
        var x = 0.0
        for w in pitches { offsets.append(x); x += w }
        for pl in places {
            let pitch = pitches[pl.column]
            let colLeft = rtl ? start - offsets[pl.column] - pitch : start + offsets[pl.column]
            let gx = colLeft + pitch / 2 - pl.glyph.width / 2
            let baseline = top + Double(pl.row) * pitch + pitch / 2 + 0.45 * pl.size
            pl.glyph.paint(canvas, Offset(gx, baseline - pl.glyph.computeDistanceToActualBaseline(.alphabetic)))
            pl.glyph.dispose()
        }
        return true
    }


    /// Where the text's column starts right of the shape's left edge, in
    /// pixels: the left inset — less what unwrapped text wider than its box
    /// hangs out on that side (none of it for text aligned left, half
    /// centred, all of it aligned right).
    func textLeft(_ shape: SlideShape, pxPerPt: Double) -> Double {
        let left = shape.drawInsets.left * pxPerPt
        guard shape.noWrap || shape.anchorCentred, shape.kind != .table, let layout = layout(shape, pxPerPt: pxPerPt),
              let doc = shape.text?.document else { return left }
        let room = (shape.frame.width - shape.drawInsets.left - shape.drawInsets.right) * pxPerPt
        let flowOver = layout.width - room
        // Centred as a block (`anchorCtr`): the widest line's span in the
        // middle of the room, the others aligned within it — hanging out
        // both sides alike when it is wider.
        if shape.anchorCentred {
            var lo = Double.infinity, hi = -Double.infinity
            for i in 0 ..< layout.count {
                let g = layout.geometry(i)
                for m in g.painter.computeLineMetrics() where m.width > 0 {
                    lo = min(lo, g.textLeft + m.left); hi = max(hi, g.textLeft + m.left + m.width)
                }
            }
            return hi > lo ? left + room / 2 - (lo + hi) / 2 : left
        }
        guard shape.noWrap else { return left }
        // (A single line comes back from the layout as wide as the room, so
        // its overhang is measured on the line itself: how-we-refactor's "R"
        // in an 18 pt square, centred in PowerPoint's print, 3.6 in; ours 7.2.)
        var over = flowOver
        if over <= 0 {
            var widest = 0.0
            for i in 0 ..< layout.count {
                for m in layout.geometry(i).painter.computeLineMetrics() { widest = max(widest, m.width) }
            }
            over = widest - room
        }
        guard over > 0 else { return left }
        switch doc.paragraphs.first?.style.alignment {
        case .center?: return left - over / 2
        case .right?: return left - over
        default: return left
        }
    }

    /// Another deck is being loaded: nothing kept here is about it. The
    /// entries are keyed by object identity, and a new deck's text bodies
    /// are allocated where the old one's were freed — so without this a
    /// body can find the previous deck's layout under its own address
    /// (same revision 0, same width) and be drawn with those line breaks.
    func reset() {
        _entries.removeAll()
        _metafiles.removeAll()
        _images.removeAll()
        _decoding.removeAll()
        _undecodable.removeAll()
    }

    func forget(_ shapes: [SlideShape]) {
        for s in shapes { if let t = s.text { _entries[ObjectIdentifier(t)] = nil } }
    }
}

/// Draws one shape (no text) in slide coordinates at `pxPerPt` — a layer
/// of the editing canvas, so that shapes and their live editors stack in
/// the slide's z-order.
final class ShapePainter: CustomPainter {
    let shape: SlideShape
    let px: Double
    let revision: Int
    let cache: SlideTextCache
    let theme: DeckTheme

    init(shape: SlideShape, px: Double, revision: Int, cache: SlideTextCache, theme: DeckTheme) {
        self.shape = shape
        self.px = px
        self.revision = revision
        self.cache = cache
        self.theme = theme
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        SlidePainter.paintShape(shape, canvas, pxPerPt: px, cache: cache, theme: theme, text: false)
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? ShapePainter else { return true }
        return old.shape !== shape || old.revision != revision || old.px != px || old.theme != theme
    }
}

/// Draws a slide scaled so that it fills `size`.
final class SlidePainter: CustomPainter {
    let slide: Slide
    let theme: DeckTheme
    let slideSize: Size
    let revision: Int
    let cache: SlideTextCache
    /// Only the background (the editing canvas draws shapes as layers).
    let shapesOnly: Bool
    /// Whether an object the deck cannot draw gets a labelled box: the
    /// editor shows one; a show and an export show nothing there, as
    /// PowerPoint shows nothing for what it cannot draw either.
    let placeholders: Bool
    /// Entrances under way in the show; shapes absent are drawn whole.
    let reveals: ShapeReveals

    init(slide: Slide, theme: DeckTheme, slideSize: Size, revision: Int, cache: SlideTextCache,
         shapesOnly: Bool = false, reveals: ShapeReveals = ShapeReveals(), placeholders: Bool = true) {
        self.slide = slide
        self.theme = theme
        self.slideSize = slideSize
        self.revision = revision
        self.cache = cache
        self.shapesOnly = shapesOnly
        self.reveals = reveals
        self.placeholders = placeholders
        super.init()
    }

    override func paint(_ canvas: any Canvas, _ size: Size) {
        let px = size.width / slideSize.width
        Self.paintFill(slide.background ?? slide.inheritedBackground ?? theme.backgroundFill,
                       Rect.fromLTWH(0, 0, size.width, size.height), canvas, cache: cache, pxPerPt: px)
        canvas.save()
        canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height))
        let area = Rect.fromLTWH(0, 0, size.width, size.height)
        let backdrop = slide.background ?? slide.inheritedBackground ?? theme.backgroundFill
        // The master's and layout's own shapes, part of the backdrop.
        for shape in slide.decorations {
            Self.paintShape(shape, canvas, pxPerPt: px, cache: cache, theme: theme, text: true, slide: area, backdrop: backdrop,
                            placeholders: placeholders)
        }
        if !shapesOnly {
            for shape in slide.shapes {
                let f = shape.frame
                let box = Rect.fromLTWH(f.left * px, f.top * px, f.width * px, f.height * px)
                let draw = {
                    Self.paintShape(shape, canvas, pxPerPt: px, cache: self.cache, theme: self.theme, text: true,
                                    paragraphs: self.reveals.paragraphs[shape.id], slide: area, backdrop: backdrop,
                                    placeholders: self.placeholders)
                }
                if let r = reveals.whole[shape.id] {
                    Self.reveal(r, box, slide: area, canvas, draw)
                } else {
                    draw()
                }
            }
        }
        canvas.restore()
    }

    /// Draw `draw` (which paints within `box`) as far into entrance `r` as
    /// it has got: nothing at 0, all of it at 1. `slide` is the slide's
    /// rectangle in the same coordinates, which Fly In comes in from beyond.
    /// The text of a box with each line's baseline on a whole point down
    /// from the top of its text, as PowerPoint sets them: the AES deck's
    /// 16.8 pt lines print 17, 17, 16, 17, 17 apart, never 16.8, the
    /// pattern repeating every five. Each line is drawn in its own band
    /// (from a quarter of the way past the line above's baseline to the
    /// same past its own), moved to its point. (PowerPoint's points lie
    /// 0.1 pt below whole ones from the text's top, and its print then
    /// rounds each down to its 1/300 in raster, 0.12 pt on average: so a
    /// line is drawn 0.02 pt above a whole one. Four decks fitted, every
    /// line of their long boxes. The whole point nearest our own line,
    /// not the nearest of PowerPoint's points: ours stand a little high,
    /// and 3289 lines across the decks land within 0.15 pt 2807 times
    /// so, 2669 times by its points.)
    /// Not for a box in columns, whose lines stand side by side. Turned
    /// text (`vert`, a turned diagram frame) is snapped along its own
    /// lines, as laid out (eaVertAnchor 1.22 → 0.46).
    /// False: lines keep their laid-out pitch. PowerPoint for Windows does not
    /// snap them (au.asn.aes p8: 16.80 pt between every Verdana 14 line).
    nonisolated(unsafe) static var snapsLinesToPoints = false

    static func paintOnWholePoints(_ layout: RichLayout, _ doc: RichDocument, _ canvas: any Canvas, pxPerPt px: Double,
                                   visible: Rect) {
        var baselines: [Double] = []
        for i in 0 ..< min(layout.count, doc.paragraphs.count) {
            let top = layout.drawnTextTop(i, doc)
            for m in layout.geometry(i).painter.computeLineMetrics() { baselines.append(top + m.baseline) }
        }
        baselines.sort()
        guard !baselines.isEmpty, px > 0 else {
            layout.paint(canvas, visible: visible, document: doc, selection: nil, caret: nil)
            return
        }
        for (k, y) in baselines.enumerated() {
            let pt = y / px
            let dy = (pt.rounded() - 0.02 - pt) * px
            let above = k == 0 ? -1_000_000 : baselines[k - 1] + (y - baselines[k - 1]) / 4
            let below = k == baselines.count - 1 ? 1_000_000 : y + (baselines[k + 1] - y) / 4
            canvas.save()
            canvas.clipRect(Rect.fromLTRB(-1_000_000, above + dy, 1_000_000, below + dy))
            canvas.translate(0, dy)
            layout.paint(canvas, visible: Rect.fromLTRB(visible.left, above, visible.right, below), document: doc,
                         selection: nil, caret: nil)
            canvas.restore()
        }
    }

    static func reveal(_ r: ShapeReveal, _ box: Rect, slide: Rect, _ canvas: any Canvas, _ draw: () -> Void) {
        guard r.progress > 0 else { return }
        guard r.progress < 1 else { draw(); return }
        let t = r.progress
        let e = 1 - pow(1 - t, 3)
        canvas.save()
        func faded(_ alpha: Double, _ bounds: Rect) {
            let p = Paint()
            p.color = Color(Int((max(0, min(1, alpha)) * 255).rounded()) << 24)
            canvas.saveLayer(bounds, p)
            draw()
            canvas.restore()
        }
        switch r.effect {
        case .appear:
            draw()
        case .fade:
            faded(t, box.inflate(4))
        case .flyIn:
            var dx = 0.0, dy = 0.0
            switch r.direction {
            case .bottom: dy = (slide.bottom - box.top) * (1 - e)
            case .top: dy = (slide.top - box.bottom) * (1 - e)
            case .left: dx = (slide.left - box.right) * (1 - e)
            case .right: dx = (slide.right - box.left) * (1 - e)
            }
            canvas.translate(dx, dy)
            draw()
        case .wipe:
            let clip: Rect
            switch r.direction {
            case .bottom: clip = Rect.fromLTRB(box.left - 4, box.bottom - box.height * t, box.right + 4, box.bottom + 4)
            case .top: clip = Rect.fromLTRB(box.left - 4, box.top - 4, box.right + 4, box.top + box.height * t)
            case .left: clip = Rect.fromLTRB(box.left - 4, box.top - 4, box.left + box.width * t, box.bottom + 4)
            case .right: clip = Rect.fromLTRB(box.right - box.width * t, box.top - 4, box.right + 4, box.bottom + 4)
            }
            canvas.clipRect(clip)
            draw()
        case .zoom:
            let c = box.center
            canvas.translate(c.dx, c.dy)
            canvas.scale(max(0.01, e), max(0.01, e))
            canvas.translate(-c.dx, -c.dy)
            faded(t, box.inflate(4))
        }
        canvas.restore()
    }

    static func paintShape(_ shape: SlideShape, _ canvas: any Canvas, pxPerPt px: Double,
                           cache: SlideTextCache, theme: DeckTheme, text: Bool,
                           paragraphs: [Int: ShapeReveal]? = nil, slide: Rect? = nil, backdrop: SlideFill? = nil,
                           placeholders: Bool = true) {
        if shape.invisible { return }
        let f = shape.frame
        let r = Rect.fromLTWH(f.left * px, f.top * px, f.width * px, f.height * px)
        canvas.save()
        if shape.rotation != 0 {
            let c = r.center
            canvas.translate(c.dx, c.dy)
            canvas.rotate(shape.rotation * .pi / 180)
            canvas.translate(-c.dx, -c.dy)
        }
        if let scene = shape.scene3d, scene.isFlatTurn, scene.rev != 0 {
            // A camera that only revolves: the shape turned the other way.
            let c = r.center
            canvas.translate(c.dx, c.dy)
            canvas.rotate(-scene.rev * .pi / 180)
            canvas.translate(-c.dx, -c.dy)
        }
        // The outline as drawn, for the effects round it.
        func effectOutline() -> Path {
            // (A preset's evaluated path first: it has the shape's adjust
            // values, where the preset's name alone draws its defaults —
            // customGeo's three pie slices each cast a three-quarter pie.)
            if shape.pictureGeometry == nil, let free = shape.opaque?.freeform { return Self.combinedPath(free, r) }
            if shape.pictureGeometry == nil, let g = shape.customPath {
                // (Its parts together: a can's lid lies over its body.)
                let path = Path()
                for sub in g.subpaths where sub.fill { path.addPath(FreeformGeometry.path(sub, in: r), Offset.zero) }
                return path
            }
            if let g = shape.pictureGeometry ?? shape.preset ?? shape.inheritedPreset, !g.isLine {
                return PresetGeometry.path(g.rawValue, in: r) ?? Self.geometryPath(g, r)
            }
            if let free = shape.opaque?.freeform ?? shape.customPath { return Self.combinedPath(free, r) }
            let p = Path()
            p.addRect(r)
            return p
        }
        // (Not for a shape filled with a picture: its shadow is the shadow
        // of what the picture paints — tdf128596's ticks on nothing — and
        // the outline's showed grey through the gaps.)
        if let sh = shape.shadow, shape.picture != nil || shape.fill != nil || shape.fillStyle != nil,
           shape.fillStyle?.image == nil {
            // The outline's blurred copy, where the shadow falls: offset on
            // the page, not turned with the shape (rotWithShape="0", as
            // PowerPoint writes its shadows).
            let outline = effectOutline()
            let a = -shape.rotation * .pi / 180
            let dx = (sh.dx * cos(a) - sh.dy * sin(a)) * px, dy = (sh.dx * sin(a) + sh.dy * cos(a)) * px
            let p = Paint()
            p.style = .fill
            p.isAntiAlias = true
            // As see-through as a plain fill is.
            let through = shape.picture == nil && shape.fillStyle == nil ? Double(shape.fill?.alpha ?? 255) / 255 : 1
            p.color = sh.color.withOpacity(Double(sh.color.alpha) / 255 * through)
            if sh.blur > 0 { p.maskFilter = MaskFilter(blur: .normal, sh.blur * px / 2) }
            canvas.save()
            canvas.translate(dx, dy)
            if sh.scale != 1 {
                // Scaled about the point of the box its alignment names.
                let at = Offset(r.left + r.width * sh.anchor.dx, r.top + r.height * sh.anchor.dy)
                canvas.translate(at.dx, at.dy)
                canvas.scale(sh.scale, sh.scale)
                canvas.translate(-at.dx, -at.dy)
            }
            if shape.picture == nil, shape.flipH || shape.flipV {
                // A mirrored shape's shadow falls from the mirrored outline (cycleMatrix's third wedge).
                let c = r.center
                canvas.translate(c.dx, c.dy)
                canvas.scale(shape.flipH ? -1 : 1, shape.flipV ? -1 : 1)
                canvas.translate(-c.dx, -c.dy)
            }
            if let line = shape.outline, shape.outlineWidth > 0, line.alpha > 0, shape.picture == nil,
               let body = shape.fill, body.alpha > 0, shape.fillStyle == nil {
                // The silhouette that casts is the fill and its outline together (a title bar's thick white
                // border is part of the bar the shadow falls from: customGeo's titles print darker under
                // the border, 188 against 219): both drawn opaque in one layer, which lays down the shadow's
                // opacity once over their union.
                let layer = Paint()
                layer.color = Color(Int(p.color.alpha) << 24)
                canvas.saveLayer(r.inflate(sh.blur * px * 2 + shape.outlineWidth * px + 4), layer)
                let solid = Paint()
                solid.style = .fill
                solid.isAntiAlias = true
                solid.color = p.color.withOpacity(1)
                solid.maskFilter = p.maskFilter
                canvas.drawPath(outline, solid)
                solid.style = .stroke
                solid.strokeWidth = max(0.5, shape.outlineWidth * px)
                solid.strokeJoin = Self.join(shape.outlineJoin)
                canvas.drawPath(outline, solid)
                canvas.restore()
            } else {
                canvas.drawPath(outline, p)
            }
            canvas.restore()
        } else if let sh = shape.shadow, let style = shape.fillStyle, style.image != nil, shape.picture == nil {
            // A shape filled with a picture casts the shadow of what the
            // picture paints: tdf128596's ticks, each with its own soft
            // shadow, which is what makes them read bold in PowerPoint.
            let a = -shape.rotation * .pi / 180
            let dx = (sh.dx * cos(a) - sh.dy * sin(a)) * px, dy = (sh.dx * sin(a) + sh.dy * cos(a)) * px
            let layer = Paint()
            layer.colorFilter = ColorFilter(mode: sh.color, .srcIn)
            if sh.blur > 0 { layer.imageFilter = ImageFilterFactory.blur(sigmaX: sh.blur * px / 2, sigmaY: sh.blur * px / 2) }
            canvas.saveLayer(r.inflate(sh.blur * px * 2 + abs(dx) + abs(dy)), layer)
            canvas.translate(dx, dy)
            canvas.clipPath(effectOutline())
            paintFill(style, r, canvas, cache: cache, pxPerPt: px, turn: shape.rotation)
            canvas.restore()
        }
        if let rad = shape.glowRadius, rad > 0, let color = shape.glowColor {
            // A glow: the outline grown by its radius and blurred, behind
            // the shape.
            let p = Paint()
            p.style = .stroke
            p.isAntiAlias = true
            p.strokeWidth = rad * px
            p.strokeJoin = .round
            p.color = color
            p.maskFilter = MaskFilter(blur: .normal, rad * px / 4)
            let outline = effectOutline()
            // Round the shape as filled — or, with no fill, round its line
            // alone: tdf141058's red frame has a white glow, and filled it
            // hid the text behind the frame.
            let filled = shape.fill != nil || shape.fillStyle != nil || shape.picture != nil
            if !filled { p.strokeWidth = (rad * 2 + shape.outlineWidth) * px }
            canvas.drawPath(outline, p)
            if filled {
                p.style = .fill
                canvas.drawPath(outline, p)
            }
        }
        // A soft edge: the shape drawn in a layer of its own, and the band
        // inside its outline faded out of it before it is put down.
        let softEdge = shape.softEdge.map { $0 * px }
        if let softEdge { canvas.saveLayer(r.inflate(softEdge), Paint()) }
        // A picture on a solid turned by the camera: the solid is drawn
        // first and the picture goes onto its turned front.
        let picture3D = shape.picture != nil && shape.scene3d.map { !$0.isFlatTurn } == true && shape.chart == nil && shape.opaque == nil
        let drawPicture: () -> Void = {
          guard let image = shape.picture else { return }
          do {
            if let metafile = cache.metafile(image) {
                // A WMF or EMF, as vectors: the whole picture placed so that
                // the crop's share of it fills the frame.
                let c = shape.crop ?? .zero
                let place = Self.inset(r, shape.pictureInset)
                let spanX = 1 - c.left - c.right, spanY = 1 - c.top - c.bottom
                let whole = spanX > 0 && spanY > 0 ? Rect.fromLTWH(
                    place.left - c.left / spanX * place.width, place.top - c.top / spanY * place.height,
                    place.width / spanX, place.height / spanY) : place
                canvas.save()
                canvas.clipRect(r)
                if let g = shape.pictureGeometry, !g.isLine {
                    canvas.clipPath(PresetGeometry.path(g.rawValue, in: r) ?? Self.geometryPath(g, r))
                } else if let outline = shape.customPath {
                    canvas.clipPath(Self.combinedPath(outline, r))
                }
                if let style = shape.fillStyle { paintFill(style, r, canvas, cache: cache, pxPerPt: px, turn: shape.rotation) }
                if shape.flipH || shape.flipV {
                    let c = r.center
                    canvas.translate(c.dx, c.dy)
                    canvas.scale(shape.flipH ? -1 : 1, shape.flipV ? -1 : 1)
                    canvas.translate(-c.dx, -c.dy)
                }
                // Its recolouring as a bitmap's — duotone, transparency,
                // levels — over the played drawing as a whole: customGeo's
                // WMF signposts under an accent1 duotone print blue in
                // PowerPoint, and were their own black and yellow.
                let recoloured = shape.pictureDuotone != nil || shape.pictureAlpha < 1 || shape.pictureLevels != nil
                if recoloured {
                    canvas.saveLayer(r, Self.imagePaint(alpha: shape.pictureAlpha, duotone: shape.pictureDuotone, levels: shape.pictureLevels))
                }
                metafile.paint(canvas, in: whole, image: { cache.image($0) }, font: OfficeFonts.substitute,
                               change: shape.pictureColorChange)
                if recoloured { canvas.restore() }
                canvas.restore()
            } else if let decoded = cache.image(image) {
                let w = Double(decoded.width), h = Double(decoded.height)
                let c: EdgeInsets = {
                    let c0 = shape.crop ?? .zero
                    // PowerPoint cuts a cropped picture to whole pixels (customGeo p36: 991 x 614 taken at
                    // (152, 265) of a 1280 x 1024 PNG with l=11.852% t=25.887% r=10.76% b=14.165%, zero
                    // error against the source) and stretches that to the frame: the start rounds, the span rounds.
                    var l = c0.left, rr = c0.right, t = c0.top, bt = c0.bottom
                    if l >= 0, rr >= 0, l > 0 || rr > 0, w * (1 - l - rr) >= 1 {
                        let x0 = (l * w).rounded(), span = (w * (1 - l - rr)).rounded()
                        if span >= 1 { l = x0 / w; rr = (w - x0 - span) / w }
                    }
                    if t >= 0, bt >= 0, t > 0 || bt > 0, h * (1 - t - bt) >= 1 {
                        let y0 = (t * h).rounded(), span = (h * (1 - t - bt)).rounded()
                        if span >= 1 { t = y0 / h; bt = (h - y0 - span) / h }
                    }
                    return EdgeInsets(left: l, top: t, right: rr, bottom: bt)
                }()
                // `a:fillRect`: the picture's place within the frame.
                let frame = r
                let place = Self.inset(r, shape.pictureInset)
                // A negative crop pads: the picture sits inside the frame.
                let src = Rect.fromLTRB(max(0, c.left) * w, max(0, c.top) * h,
                                        w - max(0, c.right) * w, h - max(0, c.bottom) * h)
                let spanX = 1 - c.left - c.right, spanY = 1 - c.top - c.bottom
                let r = spanX > 0 && spanY > 0 ? Rect.fromLTRB(
                    place.left + (max(0, c.left) - c.left) / spanX * place.width,
                    place.top + (max(0, c.top) - c.top) / spanY * place.height,
                    place.left + (1 - max(0, c.right) - c.left) / spanX * place.width,
                    place.top + (1 - max(0, c.bottom) - c.top) / spanY * place.height) : place
                canvas.save()
                if shape.pictureInset != .zero { canvas.clipRect(frame) }
                if let g = shape.pictureGeometry, !g.isLine {
                    canvas.clipPath(PresetGeometry.path(g.rawValue, in: frame) ?? Self.geometryPath(g, frame))
                } else if let outline = shape.customPath {
                    canvas.clipPath(Self.combinedPath(outline, frame))
                }
                if let style = shape.fillStyle { paintFill(style, frame, canvas, cache: cache, pxPerPt: px, turn: shape.rotation) }
                if shape.flipH || shape.flipV {
                    let c = frame.center
                    canvas.translate(c.dx, c.dy)
                    canvas.scale(shape.flipH ? -1 : 1, shape.flipV ? -1 : 1)
                    canvas.translate(-c.dx, -c.dy)
                }
                // A crop is the whole picture drawn clipped, as PowerPoint
                // prints it: a cut copy is sampled from another origin,
                // and customGeo's 138 dpi screenshots of small print
                // came out a different grey in every letter.
                let paint = imagePaint(alpha: shape.pictureAlpha, duotone: shape.pictureDuotone, levels: shape.pictureLevels)
                if src.width > 0, src.height > 0, src.width < w || src.height < h {
                    let sx = r.width / src.width, sy = r.height / src.height
                    canvas.clipRect(r)
                    canvas.drawImageRect(decoded, Rect.fromLTWH(0, 0, w, h),
                                         Rect.fromLTWH(r.left - src.left * sx, r.top - src.top * sy, w * sx, h * sy), paint)
                } else {
                    // PowerPoint's PDF holds an uncropped picture shrunk to 200 pixels an inch
                    // (a 3508 px picture over 841.6 pt is 2337; 1890 over 204.1 pt is 567).
                    var shown = decoded
                    if shape.pictureInset == .zero, shape.pictureDuotone == nil, shape.pictureLevels == nil, shape.pictureAlpha >= 1, !Self.pngHasAlpha(image.data),
                       c.left == 0, c.right == 0, c.top == 0, c.bottom == 0, px > 0 {
                        let nw = Int((r.width / px * 200 / 72).rounded(.down)), nh = Int((r.height / px * 200 / 72).rounded(.down))
                        if nw >= 1, nh >= 1, nw < decoded.width, nh < decoded.height, let small = cache.scaled(decoded, nw, nh) { shown = small }
                    }
                    canvas.drawImageRect(shown, shown === decoded ? src : Rect.fromLTWH(0, 0, Double(shown.width), Double(shown.height)), r, paint)
                }
                canvas.restore()
            } else {
                let p = Paint()
                p.style = .fill
                p.color = Color(0xFFEDEDED)
                canvas.drawRect(r, p)
            }
          }
        }
        if !picture3D { drawPicture() }
        if let chart = shape.chart {
            if let style = shape.fillStyle { paintFill(style, r, canvas, cache: cache, pxPerPt: px, turn: shape.rotation) }
            var onSlide = chart
            onSlide.onSlide = true
            ChartPainter.paint(onSlide, canvas, r, pxPerPt: px, theme: theme)
        }
        if shape.chart != nil {
            // The chart's own drawing, over it.
            for sub in shape.rendered {
                paintShape(sub, canvas, pxPerPt: px, cache: cache, theme: theme, text: text, slide: slide, backdrop: backdrop,
                           placeholders: placeholders)
            }
        }
        if shape.fillsWithBackground, let backdrop, let slide {
            // A window onto the slide's background, in the shape's outline.
            canvas.save()
            if let freeform = shape.opaque?.freeform ?? shape.customPath {
                canvas.clipPath(Self.combinedPath(freeform, r))
            } else if let preset = shape.preset ?? shape.inheritedPreset, !preset.isLine {
                canvas.clipPath(geometryPath(preset, r))
            } else {
                canvas.clipRect(r)
            }
            paintFill(backdrop, slide, canvas, cache: cache, pxPerPt: px)
            canvas.restore()
        }
        // A mirrored shape (`flipH`/`flipV`) draws its outline and fill
        // mirrored; its text stays upright, as PowerPoint keeps it.
        let mirrored = shape.picture == nil && (shape.flipH || shape.flipV)
        func mirror() {
            canvas.save()
            let c = r.center
            canvas.translate(c.dx, c.dy)
            canvas.scale(shape.flipH ? -1 : 1, shape.flipV ? -1 : 1)
            canvas.translate(-c.dx, -c.dy)
        }
        // A freeform's path, or a preset's as evaluated from its definition
        // (`customPath`): drawn contour by contour, each filled and stroked
        // as the definition says.
        let freeform = shape.opaque?.freeform ?? (shape.picture == nil && shape.chart == nil ? shape.customPath : nil)
        // A shape with depth: its solid, in place of the flat outline.
        var solid = false
        if shape.scene3d != nil, shape.chart == nil, shape.opaque == nil {
            let outline: Path
            if let freeform { outline = Self.combinedPath(freeform, r) }
            else if let p = shape.preset ?? shape.inheritedPreset ?? shape.pictureGeometry, !p.isLine { outline = PresetGeometry.path(p.rawValue, in: r) ?? geometryPath(p, r) }
            else { outline = Path(); outline.addRect(r) }
            if mirrored { mirror() }
            solid = Extrusion.paint(shape, outline: outline, r, canvas, pxPerPt: px, onFront: picture3D ? drawPicture : nil)
            if mirrored { canvas.restore() }
        }
        if solid {
        } else if let freeform {
            if mirrored { mirror() }
            // A freeform along its own path, in the shape's fill and line.
            if let style = shape.fillStyle {
                // A gradient or picture, within every filled subpath at once.
                canvas.save()
                let outline = Self.combinedPath(freeform, r)
                canvas.clipPath(outline)
                let named = (shape.preset ?? shape.inheritedPreset)?.rawValue
                if style.path == .shape, Self.shapePathIsCircle(named) {
                    var circle = style
                    circle.path = .circle
                    paintFill(circle, r, canvas, cache: cache, pxPerPt: px, turn: shape.rotation)
                } else if style.path == .shape, style.stops.count >= 2, style.overlay == nil {
                    Self.paintShapePath(style, outline, r, canvas, ellipse: named == "ellipse")
                } else {
                    paintFill(style, r, canvas, cache: cache, pxPerPt: px, turn: shape.rotation)
                }
                canvas.restore()
            }
            // Every fill, then every outline — PowerPoint's order whatever
            // the paths': lo-cshapes' chartStar lists its lines before the
            // box they lie on, and shows them over it.
            for sub in freeform.subpaths {
                let path = FreeformGeometry.path(sub, in: r)
                if sub.fill, shape.fillStyle == nil, let fill = shape.fill, shape.preset?.isOpenPath != true {
                    let p = Paint()
                    p.style = .fill
                    p.isAntiAlias = true
                    p.color = FreeformGeometry.toned(fill, sub.tone)
                    canvas.drawPath(path, p)
                }
            }
            for sub in freeform.subpaths {
                let path = FreeformGeometry.path(sub, in: r)
                if sub.stroke, let line = shape.outline {
                    let p = Paint()
                    p.style = .stroke
                    p.isAntiAlias = true
                    p.strokeWidth = max(0.5, shape.outlineWidth * px)
                    p.strokeJoin = Self.join(shape.outlineJoin)
                    p.strokeCap = shape.outlineCap == "rnd" ? .round : shape.outlineCap == "sq" ? .square : .butt
                    p.color = line
                    canvas.drawPath(Self.dashed(path, shape.outlineDash, width: p.strokeWidth, capped: shape.outlineCap == "rnd" || shape.outlineCap == "sq"), p)
                    // A connector's arrowheads, at its path's two ends.
                    if shape.headEnd != nil || shape.tailEnd != nil, let ends = Self.pathEnds(sub, in: r) {
                        let base = max(shape.outlineWidth, 2) * px
                        if let e = shape.headEnd { Self.lineEnd(e, tip: ends.start, from: ends.startFrom, base: base, paint: p, canvas) }
                        if let e = shape.tailEnd { Self.lineEnd(e, tip: ends.end, from: ends.endFrom, base: base, paint: p, canvas) }
                    }
                }
            }
            if mirrored { canvas.restore() }
        } else if shape.opaque != nil, !shape.rendered.isEmpty {
            // The object's own drawing (a SmartArt's), shape by shape.
            let clips = shape.opaque?.clipsRendering ?? false
            if clips { canvas.save(); canvas.clipRect(r) }
            for sub in shape.rendered {
                paintShape(sub, canvas, pxPerPt: px, cache: cache, theme: theme, text: text, slide: slide, backdrop: backdrop,
                           placeholders: placeholders)
            }
            if clips { canvas.restore() }
        } else if let opaque = shape.opaque, placeholders {
            // What the deck cannot draw yet: a labelled box where it sits.
            let p = Paint()
            p.style = .fill
            p.color = Color(0xFFF1F3F6)
            canvas.drawRect(r, p)
            p.style = .stroke
            p.strokeWidth = 1
            p.color = Color(0xFF9AA4B2)
            canvas.drawRect(r, p)
            let tp = TextPainter(text: TextSpan(text: opaque.label, style: Flutter.TextStyle(
                color: Color(0xFF5A6472), fontSize: max(6, 14 * px), fontFamily: OfficeFonts.sans)),
                textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: max(1, r.width))
            tp.paint(canvas, Offset(r.center.dx - tp.width / 2, r.center.dy - tp.height / 2))
            tp.dispose()
        }
        let preset = shape.preset ?? shape.inheritedPreset ?? (shape.picture != nil ? shape.pictureGeometry : nil)
        let path: Path? = preset.flatMap { $0.isLine ? nil : (PresetGeometry.path($0.rawValue, in: r) ?? geometryPath($0, r)) }
        let drawnAlready = freeform != nil || solid
        if mirrored { mirror() }
        // (A table's fill lies under its rows and no further: where the
        // rows come out shorter than the frame, none of it shows below.)
        var area = r
        if shape.kind == .table, shape.fill != nil || shape.fillStyle != nil, let layout = cache.layout(shape, pxPerPt: px) {
            area = Rect.fromLTWH(r.left, r.top, r.width, min(r.height, layout.totalHeight))
        }
        if let style = shape.fillStyle, !drawnAlready, shape.chart == nil, shape.picture == nil {
            // A gradient or picture fill, within the shape's outline.
            canvas.save()
            if let path { canvas.clipPath(path) } else { canvas.clipRect(area) }
            if style.path == .shape, Self.shapePathIsCircle(preset?.rawValue) {
                var circle = style
                circle.path = .circle
                paintFill(circle, area, canvas, cache: cache, pxPerPt: px, turn: shape.rotation)
            } else if style.path == .shape, let path, preset?.rawValue != "rect", style.stops.count >= 2, style.overlay == nil {
                Self.paintShapePath(style, path, area, canvas, ellipse: preset?.rawValue == "ellipse")
            } else {
                paintFill(style, area, canvas, cache: cache, pxPerPt: px, turn: shape.rotation)
            }
            canvas.restore()
        } else if let fill = shape.fill, shape.preset?.isOpenPath != true, !drawnAlready {
            let p = Paint()
            p.style = .fill
            p.isAntiAlias = true
            p.color = fill
            if let path { canvas.drawPath(path, p) } else { canvas.drawRect(area, p) }
        }
        if let ish = shape.innerShadow, shape.fill != nil || shape.fillStyle != nil, shape.picture == nil,
           shape.preset?.isOpenPath != true {
            // An inner shadow: everything outside the outline, blurred and
            // offset, seen only inside it (tdf99030's dark-edged box).
            let inside = path ?? { let q = Path(); q.addRect(area); return q }()
            let a = -shape.rotation * .pi / 180
            let dx = (ish.dx * cos(a) - ish.dy * sin(a)) * px, dy = (ish.dx * sin(a) + ish.dy * cos(a)) * px
            let spread = ish.blur * px * 2 + abs(dx) + abs(dy) + 2
            let around = Path()
            around.fillType = .evenOdd
            around.addRect(area.inflate(spread))
            around.addPath(inside, Offset.zero)
            let p = Paint()
            p.style = .fill
            p.isAntiAlias = true
            p.color = ish.color
            if ish.blur > 0 { p.maskFilter = MaskFilter(blur: .normal, ish.blur * px / 2) }
            canvas.save()
            canvas.clipPath(inside)
            canvas.translate(dx, dy)
            canvas.drawPath(around, p)
            canvas.restore()
        }
        // (Not a dark-edged one: bnc862510_5's grey box and tdf145528's
        // matrix print flat but for their own lines.)
        // (A dark-edged bevel under the flat rig, SmartArt's quick style (8200 x 38100
        // EMU): PowerPoint's print has a dark line as wide as the bevel centred on the
        // edge, so the shape prints half a pixel larger all round: lab-sa-matrix and
        // tdf145528's Windows print, 150 dpi.)
        if let bevel = shape.bevel, bevel.material == "dkEdge", bevel.rig == "flat", bevel.width < 2, shape.fill != nil,
           shape.fillStyle == nil, shape.picture == nil, shape.preset?.isOpenPath != true, shape.scene3d == nil {
            let outline = path ?? { let q = Path(); q.addRect(area); return q }()
            RuleTrace.hit("slide-dkedge-flat-bevel-is-a-dark-line-on-the-edge")
            let rim = Paint()
            rim.style = .stroke
            rim.isAntiAlias = true
            rim.strokeWidth = bevel.width * px
            rim.color = Color(0x66000000)
            canvas.drawPath(outline, rim)
        }
        // (A SmartArt metal bevel (quick style 3d3, 7 x 16 pt): PowerPoint's print is a grey
        // outline pixel, then a light band about 4 px deep fading into the fill.)
        if let bevel = shape.bevel, bevel.diagram, shape.fill != nil, shape.fillStyle == nil, shape.picture == nil,
           shape.preset?.isOpenPath != true {
            let outline = path ?? { let q = Path(); q.addRect(area); return q }()
            RuleTrace.hit("slide-diagram-metal-bevel-is-a-thin-rim")
            canvas.save()
            canvas.clipPath(outline)
            for depth in [2.0, 1.5, 1.0, 0.5] {
                let band = Paint()
                band.style = .stroke
                band.isAntiAlias = true
                band.strokeWidth = px * depth * 2
                band.color = Color(0x1AFFFFFF)
                canvas.drawPath(outline, band)
            }
            canvas.restore()
            let edge = Paint()
            edge.style = .stroke
            edge.isAntiAlias = true
            edge.strokeWidth = px * 0.5
            edge.color = Color(0x99606060)
            canvas.drawPath(outline, edge)
        } else if let bevel = shape.bevel, bevel.material != "dkEdge", let fill = shape.fill, shape.fillStyle == nil,
           shape.picture == nil, shape.preset?.isOpenPath != true {
            let outline = path ?? { let q = Path(); q.addRect(area); return q }()
            if bevel.material == "translucentPowder" || !Extrusion.paintBevel(bevel, outline, area, canvas, pxPerPt: px, fill: fill) {
                Self.paintBevel(bevel, outline, area, canvas, pxPerPt: px, fill: fill)
            }
        }
        if let line = shape.outline, !drawnAlready, let sh = shape.shadow, shape.fill == nil, shape.fillStyle == nil,
           shape.picture == nil {
            // An outline alone casts its own shadow, blurred: lineStyle's
            // connector, the 2007 theme's soft shadow under it in
            // PowerPoint's print.
            let a = -shape.rotation * .pi / 180
            let dx = (sh.dx * cos(a) - sh.dy * sin(a)) * px, dy = (sh.dx * sin(a) + sh.dy * cos(a)) * px
            let p = Paint()
            p.style = .stroke
            p.isAntiAlias = true
            p.strokeWidth = max(0.5, shape.outlineWidth * px)
            p.strokeJoin = Self.join(shape.outlineJoin)
            p.color = sh.color.withOpacity(Double(sh.color.alpha) / 255 * Double(line.alpha) / 255)
            if sh.blur > 0 { p.maskFilter = MaskFilter(blur: .normal, sh.blur * px / 2) }
            canvas.save()
            canvas.translate(dx, dy)
            if shape.preset?.isLine == true {
                canvas.drawLine(Offset(r.left, r.top), Offset(r.right, r.bottom), p)
            } else if let path {
                canvas.drawPath(path, p)
            } else {
                canvas.drawRect(r, p)
            }
            canvas.restore()
        }
        if let line = shape.outline, !drawnAlready {
            let p = Paint()
            p.style = .stroke
            p.isAntiAlias = true
            p.strokeWidth = max(0.5, shape.outlineWidth * px)
            p.strokeJoin = Self.join(shape.outlineJoin)
            p.strokeCap = shape.outlineCap == "rnd" ? .round : shape.outlineCap == "sq" ? .square : .butt
            p.color = line
            if let g = shape.outlineFill, let shader = Self.gradientShader(g, r) { p.shader = shader }
            if let dash = shape.outlineDash {
                // Dashed: the outline's path cut into the pattern's pieces.
                let outline: Path
                if shape.preset?.isLine == true {
                    outline = Path()
                    outline.moveTo(r.left, r.top)
                    outline.lineTo(r.right, r.bottom)
                } else if let path {
                    outline = path
                } else {
                    outline = Path()
                    outline.addRect(r)
                }
                canvas.drawPath(Self.dashed(outline, dash, width: p.strokeWidth, capped: shape.outlineCap == "rnd" || shape.outlineCap == "sq"), p)
            } else if shape.preset?.isLine == true {
                // From its start to its end, stopping inside a filled head.
                var a = Offset(r.left, r.top), b = Offset(r.right, r.bottom)
                let base = max(shape.outlineWidth, 2) * px
                func pulled(_ tip: Offset, from other: Offset, _ e: LineEnd?) -> Offset {
                    guard let e, ["triangle", "stealth"].contains(e.kind) else { return tip }
                    let d = Offset(tip.dx - other.dx, tip.dy - other.dy), len = (d.dx * d.dx + d.dy * d.dy).squareRoot()
                    guard len > 1e-6 else { return tip }
                    let back = min(len / 2, e.length * base * 0.8)
                    return Offset(tip.dx - d.dx / len * back, tip.dy - d.dy / len * back)
                }
                let a0 = a, b0 = b
                a = pulled(a0, from: b0, shape.headEnd)
                b = pulled(b0, from: a0, shape.tailEnd)
                canvas.drawLine(a, b, p)
                if let e = shape.headEnd { Self.lineEnd(e, tip: a0, from: b0, base: base, paint: p, canvas) }
                if let e = shape.tailEnd { Self.lineEnd(e, tip: b0, from: a0, base: base, paint: p, canvas) }
            } else if let compound = shape.outlineCompound, shape.preset?.isOpenPath != true {
                Self.compoundOutline(path ?? { let q = Path(); q.addRect(r); return q }(), compound, p, canvas)
            } else if let path {
                canvas.drawPath(path, p)
            } else {
                canvas.drawRect(r, p)
            }
        }
        if mirrored { canvas.restore() }
        if let softEdge {
            let p = Paint()
            p.style = .stroke
            p.isAntiAlias = true
            // (Measured on lo-shape-soft-edges: PowerPoint's fade is half
            // gone 0.73 of the radius in and spreads over 0.9 of it.)
            p.strokeWidth = softEdge * 2
            p.blendMode = .dstOut
            p.maskFilter = MaskFilter(blur: .normal, softEdge * 0.4)
            canvas.drawPath(effectOutline(), p)
            canvas.restore()
        }
        // Vertical text (`bodyPr vert`): laid out in the frame turned a
        // quarter — its width the frame's height, its insets turned with
        // it — and drawn turned back (eaVertAnchor's six boxes).
        var tr = r
        let keptFrame = shape.frame, keptInsets = shape.insets
        if shape.textTurn != 0 {
            let c = r.center
            canvas.translate(c.dx, c.dy)
            canvas.rotate(Double(shape.textTurn) * .pi / 2)
            canvas.translate(-c.dx, -c.dy)
            tr = Rect.fromCenter(center: c, width: r.height, height: r.width)
            shape.frame = Rect.fromCenter(center: keptFrame.center, width: keptFrame.height, height: keptFrame.width)
            let i = keptInsets
            shape.insets = shape.textTurn > 0
                ? EdgeInsets(left: i.top, top: i.right, right: i.bottom, bottom: i.left)
                : EdgeInsets(left: i.bottom, top: i.left, right: i.top, bottom: i.right)
        }
        defer { shape.frame = keptFrame; shape.insets = keptInsets }
        // (An empty table still has its rows' fills and borders to draw.)
        if text, shape.textStacked != 0, !shape.isEmptyText, SlideTextCache.paintStacked(shape, r, px, canvas, cache) {
            // Stacked text (`wordArtVert`): every character upright, one to a square place down the box.
        } else if text, !shape.isEmptyText, shape.warp != nil, WordArt.paint(shape, tr, canvas, pxPerPt: px, cache: cache) {
            // WordArt: fitted to the box and bent, not laid out in it.
        } else if text, !shape.isEmptyText || shape.kind == .table, let layout = cache.layout(shape, pxPerPt: px), let doc = shape.text?.document {
            let ox = tr.left + cache.textLeft(shape, pxPerPt: px), oy = tr.top + cache.textTop(shape, pxPerPt: px)
            canvas.translate(ox, oy)
            if shape.textSpin != 0 {
                // Turned about the middle of the text area, not of its lines
                // (labs vertrot and flip: `vert` at 180° lands where `vert270`
                // at 0° does, about the box's middle; a flipV box's text the
                // same half turn).
                let c = Offset(tr.center.dx - ox + (shape.insets.left - shape.insets.right) / 2 * px,
                               tr.center.dy - oy + (shape.insets.top - shape.insets.bottom) / 2 * px)
                canvas.translate(c.dx, c.dy)
                canvas.rotate(shape.textSpin * .pi / 180)
                canvas.translate(-c.dx, -c.dy)
            }
            if shape.textRev != 0 {
                // Turned about the middle of the text as set.
                var lo = Double.infinity, hi = -Double.infinity
                for i in 0 ..< layout.count {
                    let g = layout.geometry(i)
                    for m in g.painter.computeLineMetrics() where m.width > 0 {
                        lo = min(lo, g.textLeft + m.left); hi = max(hi, g.textLeft + m.left + m.width)
                    }
                }
                let c = Offset(hi > lo ? (lo + hi) / 2 : layout.width / 2, layout.totalHeight / 2)
                canvas.translate(c.dx, c.dy)
                canvas.rotate(shape.textRev * .pi / 180)
                canvas.translate(-c.dx, -c.dy)
            }
            let visible = Rect.fromLTWH(0, -10_000, layout.width, layout.totalHeight + 20_000)
            if shape.textSpin == 0, let ground = doc.paragraphs.lazy.flatMap({ $0.runs }).filter({ ($0.style.color?.alpha ?? 255) > 0 }).compactMap({ $0.style.shadow }).first(where: { $0.ground != nil }),
               let mm = ground.ground {
                // A shadow cast on the ground: the letters scaled and
                // skewed about a corner of the text's box, blurred, in the
                // shadow's colour, under them (tdf114848's title).
                RuleTrace.hit("slide-text-ground-shadow-is-the-letters-skewed")
                let layer = Paint()
                layer.colorFilter = ColorFilter(mode: ground.color, .srcIn)
                if ground.blur > 0 { layer.imageFilter = ImageFilterFactory.blur(sigmaX: ground.blur * px / 2, sigmaY: ground.blur * px / 2) }
                canvas.saveLayer(Rect.fromLTWH(-ox - 2000, -oy - 2000, tr.width + 4000, tr.height + 4000), layer)
                // (Each line cast about its own box — PowerPoint's print puts
                // a two-line title's shadows at each line's foot — the offset
                // taken before the flattening, so it is flattened too.)
                for pi in 0 ..< layout.count {
                    let g = layout.geometry(pi)
                    for m in g.painter.computeLineMetrics() where m.width > 0 {
                        let top = g.top + m.baseline - m.ascent, bottom = g.top + m.baseline + m.descent
                        let left = g.textLeft + m.left, right = left + m.width
                        let at = Offset(left + (right - left) * ground.anchor.dx, top + (bottom - top) * ground.anchor.dy)
                        canvas.save()
                        canvas.translate(ground.dx * px, ground.dy * px)
                        canvas.translate(at.dx, at.dy)
                        canvas.transform([mm[0], mm[3], 0, 0, mm[2], mm[1], 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
                        canvas.translate(-at.dx, -at.dy)
                        // (The cut is of the letters being cast, this line's alone, not of where the shadow lands.)
                        canvas.clipRect(Rect.fromLTRB(-10_000, top - 1, 10_000, bottom + 1))
                        layout.paint(canvas, visible: visible, document: doc, selection: nil, caret: nil)
                        canvas.restore()
                    }
                }
                canvas.restore()
            }
            if let paragraphs, !paragraphs.isEmpty {
                // Built by paragraph: each paragraph's band drawn on its own,
                // as far into its entrance as it has got.
                let area = (slide ?? Rect.fromLTWH(0, 0, 10_000, 10_000)).shift(Offset(-ox, -oy))
                for i in 0 ..< layout.count {
                    let g = layout.geometry(i)
                    let band = Rect.fromLTRB(-10_000, g.top, 10_000, g.top + g.height)
                    let draw = {
                        canvas.save()
                        canvas.clipRect(band)
                        layout.paint(canvas, visible: visible, document: doc, selection: nil, caret: nil)
                        canvas.restore()
                    }
                    if let rv = paragraphs[i] {
                        Self.reveal(rv, Rect.fromLTWH(0, g.top, layout.width, g.height), slide: area, canvas, draw)
                    } else {
                        draw()
                    }
                }
            } else if Self.snapsLinesToPoints, shape.kind != .table, shape.columns <= 1, shape.textSpin == 0, shape.textRev == 0,
                      abs(shape.rotation.truncatingRemainder(dividingBy: 90)) < 0.01 {
                // (Not in a box turned other than by quarters: under such a
                // turn a band's cut leaves every line's text in the PDF —
                // tdf149538_upright's held its 26 letters twelve times.)
                Self.paintOnWholePoints(layout, doc, canvas, pxPerPt: px, visible: visible)
            } else {
                layout.paint(canvas, visible: visible, document: doc, selection: nil, caret: nil)
            }
            // Picture bullets (`buBlip`): each in its bullet's place on its
            // first line, as tall as the bullet would be, centred where a
            // "●" stands — the marker the layout left empty.
            for i in 0 ..< min(layout.count, doc.paragraphs.count) {
                let para = doc.paragraphs[i]
                guard let picture = para.style.bulletPicture, para.style.list != nil, !para.text.isEmpty,
                      let decoded = cache.image(picture), decoded.width > 0 else { continue }
                let g = layout.geometry(i)
                let theme = shape.textTheme
                let slot = (theme?.listIndent ?? 18) * px
                // 0.71 of the bullet's size — its share of the first run's —
                // its foot on the baseline: tdf114913's 28 pt line has a
                // 20 pt picture, and tdf90626's 47% of 32 pt and 151% of
                // 10 pt are both 10.7 pt.
                let first = para.runs.first?.style.fontSize ?? theme?.fontSize ?? 18
                let size = 0.714 * (para.style.bulletScale ?? 1) * first * shape.fontScale * px
                let hang = g.textLeft - slot + para.style.firstLineIndent * px
                let baseline = g.inkTop + g.painter.computeDistanceToActualBaseline(.alphabetic)
                let w = size * Double(decoded.width) / Double(max(1, decoded.height))
                let x = hang >= g.textLeft - 0.01 ? hang : min(hang, g.textLeft - w - 4 * px)
                let box = Rect.fromLTWH(x, baseline - size, w, size)
                canvas.drawImageRect(decoded, Rect.fromLTWH(0, 0, Double(decoded.width), Double(decoded.height)), box, Self.imagePaint(alpha: 1, duotone: nil))
            }
        }
        canvas.restore()
    }

    /// The shader of a gradient fill over `r` — under `pre` when it is
    /// drawn through a transform of its own (a WordArt glyph's), so the
    /// gradient stays the area's. Column-major 4×4s.
    static func gradientShader(_ fill: SlideFill, _ r: Rect, pre: [Double]? = nil) -> Shader? {
        guard fill.stops.count >= 2 else { return nil }
        func mul(_ a: [Double]?, _ b: [Double]) -> [Double] {
            guard let a else { return b }
            var m = [Double](repeating: 0, count: 16)
            for c in 0 ..< 4 { for r in 0 ..< 4 { for k in 0 ..< 4 { m[c * 4 + r] += a[k * 4 + r] * b[c * 4 + k] } } }
            return m
        }
        // (A path gradient blends evenly in sRGB, as Windows PowerPoint prints
        // it: lo-tdf154858's green / yellow / green ellipse has a yellow ring at
        // half the corner radius and green again beyond it, where the linear-
        // light blend of the Mac prints held a yellow plateau. Linear gradients
        // keep the linear-light blend — tdf105739's red to green is 91% off
        // blended evenly.)
        let (colors, positions) = fill.squared ? Self.squaredRamp(fill.stops)
            : fill.even || fill.undirected || fill.path != nil ? (fill.stops.map(\.color), fill.stops.map(\.position))
                                            : Self.linearLight(fill.stops, eased: fill.eased, shifted: false)
        if let path = fill.path, r.width > 0, r.height > 0 {
            // From the focus out to the circle through the area's four
            // corners: a two-point gradient, its focus placed by the
            // fill-to rectangle's insets — l / (l + r) across, t / (t + b)
            // down, the rectangle's centre when it is a point (as it
            // usually is). GeomLec1's background (l 65%, b 98%) starts at
            // the top right corner and ends on that circle to within a
            // third of a percent of PowerPoint's ramp everywhere; a circle
            // round the rectangle's centre was grey where PowerPoint's is
            // black. A focus outside the area (a theme's light from above
            // the slide) is a circle round it out to the farthest corner,
            // squeezed to the area's proportions as before.
            _ = path
            let f = fill.fillTo
            // (A circle from the middle of its tile rectangle: lab gradpath.)
            if path == .circle, fill.tile != nil || Self.cornerFocus(f) {
                let t = fill.tile ?? Rect.fromLTRB(0, 0, 1, 1)
                let area = Rect.fromLTRB(r.left + t.left * r.width, r.top + t.top * r.height,
                                         r.left + t.right * r.width, r.top + t.bottom * r.height)
                return Gradient(radial: area.center, radius: max(1, hypot(area.width, area.height) / 2), colors: colors,
                                colorStops: positions, matrix4: pre, focal: area.center, focalRadius: 0)
            }
            let focus = Self.pathFocus(f), fx = focus.dx, fy = focus.dy
            if (0 ... 1).contains(fx), (0 ... 1).contains(fy) {
                return Gradient(radial: r.center, radius: max(1, hypot(r.width, r.height) / 2), colors: colors,
                                colorStops: positions, matrix4: pre,
                                focal: Offset(r.left + fx * r.width, r.top + fy * r.height), focalRadius: 0)
            }
            let c = Offset(r.left + (f.left + f.right) / 2 * r.width, r.top + (f.top + f.bottom) / 2 * r.height)
            let corners = [Offset(r.left, r.top), Offset(r.right, r.top), Offset(r.left, r.bottom), Offset(r.right, r.bottom)]
            let sy = r.width / r.height
            let radius = corners.map { hypot($0.dx - c.dx, ($0.dy - c.dy) * sy) }.max() ?? 1
            return Gradient(radial: Offset(c.dx, c.dy * sy), radius: max(1, radius), colors: colors,
                            colorStops: positions,
                            matrix4: mul(pre, [1, 0, 0, 0, 0, 1 / sy, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]))
        } else {
            let a = fill.angle * .pi / 180
            if fill.scaled, r.width > 0, r.height > 0 {
                // Laid out in the unit square and stretched onto the
                // area with it.
                let half = (abs(cos(a)) + abs(sin(a))) / 2
                let d = Offset(cos(a) * half, sin(a) * half)
                return Gradient(linear: Offset(0.5 - d.dx, 0.5 - d.dy), to: Offset(0.5 + d.dx, 0.5 + d.dy),
                                colors: colors, colorStops: positions,
                                matrix4: mul(pre, [r.width, 0, 0, 0, 0, r.height, 0, 0, 0, 0, 1, 0, r.left, r.top, 0, 1]))
            } else {
                let c = r.center
                let half = (abs(cos(a)) * r.width + abs(sin(a)) * r.height) / 2
                let d = Offset(cos(a) * half, sin(a) * half)
                if let pre {
                    return Gradient(linear: Offset(c.dx - d.dx, c.dy - d.dy), to: Offset(c.dx + d.dx, c.dy + d.dy),
                                    colors: colors, colorStops: positions, matrix4: pre)
                }
                return Gradient(linear: Offset(c.dx - d.dx, c.dy - d.dy), to: Offset(c.dx + d.dx, c.dy + d.dy),
                                colors: colors, colorStops: positions)
            }
        }
    }

    /// A fill-to point at a corner of the area: a circle gradient is drawn from the middle all the same
    /// (lab gradpath: all four corners print as the centred circle).
    static func cornerFocus(_ f: Rect) -> Bool {
        let p = pathFocus(f)
        return (p.dx < 0.01 || p.dx > 0.99) && (p.dy < 0.01 || p.dy > 0.99)
    }

    /// Where a path gradient starts, in fractions of its area: the
    /// fill-to rectangle's insets in proportion — l / (l + r) across,
    /// t / (t + b) down — which is the rectangle itself when it is a point.
    static func pathFocus(_ fillTo: Rect) -> Offset {
        func ratio(_ a: Double, _ b: Double) -> Double { a + b > 1e-9 ? a / (a + b) : 0.5 }
        // (A rectangle that is not a point — its insets not adding to the
        // whole across and down — is the area's middle: Windows PowerPoint
        // prints GeomLec1's background (l 65%, b 98%) as a circle round the
        // middle, where the Mac's started at the top right corner.)
        let across = fillTo.left + 1 - fillTo.right, down = fillTo.top + 1 - fillTo.bottom
        if abs(across - 1) > 0.01 || abs(down - 1) > 0.01, across >= 0, down >= 0, across <= 1, down <= 1 { return Offset(0.5, 0.5) }
        return Offset(ratio(fillTo.left, 1 - fillTo.right), ratio(fillTo.top, 1 - fillTo.bottom))
    }

    /// An outline's join as the file names it (`SlideShape.outlineJoin`),
    /// round where it names none — 223 of PowerPoint's thick strokes in
    /// the prints are joined round, most of them in lines that say nothing
    /// (the diagrams' boxes, tdf114848's), and ours were all mitred.
    static func join(_ name: String?) -> StrokeJoin {
        switch name {
        case "round": return .round
        case "bevel": return .bevel
        case "miter": return .miter
        default: return .round
        }
    }

    /// A preset dash's pieces, on and off by turns, in widths of its line
    /// (DrawingML's: "dash" 4 on 3 off, "sysDot" 1 and 1, …).
    static func dashPattern(_ name: String?) -> [Double]? {
        if let name, name.hasPrefix("cust:") {
            let widths = name.dropFirst(5).split(separator: ",").compactMap { Double($0) }.map { max(0.05, $0) }
            return widths.count >= 2 ? widths : nil
        }
        switch name {
        case "dot": return [1, 3]
        case "dash": return [4, 3]
        case "lgDash": return [8, 3]
        case "dashDot": return [4, 3, 1, 3]
        case "lgDashDot": return [8, 3, 1, 3]
        case "lgDashDotDot": return [8, 3, 1, 3, 1, 3]
        case "sysDash": return [3, 1]
        case "sysDot": return [1, 1]
        case "sysDashDot": return [3, 1, 1, 1]
        case "sysDashDotDot": return [3, 1, 1, 1, 1, 1]
        default: return nil
        }
    }

    /// `path` cut into the dash `name`'s pieces for a line `width` wide —
    /// the path itself for a solid line. Each contour starts on a dash.
    /// `capped`: the line's ends are round or square, which PowerPoint
    /// counts inside each dash — a dash 4 widths long stays 4 overall, its
    /// start cap reaching half a width before its place, and a dot (one
    /// width) is a round cap's circle alone (lo-tdf134053_dashdot's
    /// dash-dot line, rounded: 0.74 → 0.07).
    static func dashed(_ path: Path, _ name: String?, width: Double, capped: Bool = false) -> Path {
        guard let pattern = dashPattern(name), width > 0 else { return path }
        let pieces = pattern.map { $0 * width }
        let out = Path()
        for metric in path.computeMetrics() {
            var at = 0.0, i = 0
            while at < metric.length {
                let len = pieces[i % pieces.count]
                if i % 2 == 0 {
                    let from = at
                    let to = capped ? max(from + 0.01, at + len - min(len, width)) : at + len
                    if from < metric.length { out.addPath(metric.extractPath(from, min(metric.length, to)), Offset.zero) }
                }
                at += len
                i += 1
            }
        }
        return out
    }

    /// A colour, gradient or picture filling `r`. `turn` is the degrees
    /// the canvas is turned about the shape's centre, which a pattern
    /// (tiles laid from the slide's corner) undoes: PowerPoint keeps a
    /// turned shape's pattern square to the slide (tdf107608).
    /// A top bevel over a shape's plain fill, as PowerPoint prints the
    /// 2007 theme's intense effect (5 × 2 pt under a three-point light) on
    /// 60810's diagram boxes: the face lifted 7%; a band of light a point
    /// and a half inside the top edge that adds about 68 to every channel
    /// (the yellow's blue 9 → 78, its green to full), fading out by the
    /// bevel's width; the sides and foot darkened toward three quarters at
    /// the edge, back within two or three points. A shallower bevel is
    /// lit as much less as it is less steep: tdf155412's 15 × 3 pt bar
    /// shows a pale facet, not a white one. Sized by the bevel's width,
    /// whatever its rig.
    static func paintBevel(_ b: ShapeBevel, _ outline: Path, _ box: Rect, _ canvas: any Canvas, pxPerPt px: Double, fill: Color) {
        let w = min(b.width * px, min(box.width, box.height) / 2)
        guard w > 0.25 * px else { return }
        let k = min(1, b.height / b.width / 0.4)
        // A powder material lays white over the face: translucentPowder prints
        // as 0.70 of the fill and 30% white under the chilly rig (customGeo's
        // headers, PowerPoint's print) and 0.60 and 51% under threePt (Lab B).
        var fill = fill
        if b.material == "translucentPowder" {
            let (mul, white) = b.rig == "threePt" ? (0.60, 0.51) : (0.70, 0.30)
            func ch(_ v: Int) -> Int { min(255, Int((Double(v) * mul + 255 * white).rounded())) }
            fill = Color(argb: fill.alpha, ch(fill.red), ch(fill.green), ch(fill.blue))
        }
        func shade(_ f: (Int) -> Double) -> Color {
            Color(rgbo: Int(max(0, min(255, f(fill.red))).rounded()), Int(max(0, min(255, f(fill.green))).rounded()),
                  Int(max(0, min(255, f(fill.blue))).rounded()), Double(fill.alpha) / 255)
        }
        canvas.save()
        canvas.clipPath(outline)
        let lift = Paint()
        lift.style = .fill
        lift.color = shade { Double($0) * (1 + 0.07 * k) }
        canvas.drawRect(box, lift)
        let rim = Paint()
        rim.style = .stroke
        rim.isAntiAlias = true
        rim.strokeWidth = 0.6 * w
        rim.color = Color(rgbo: 0, 0, 0, 0.42 * k)
        rim.maskFilter = MaskFilter(blur: .normal, 0.12 * w)
        canvas.drawPath(outline, rim)
        // (The light along the top: the outline stroked a little down,
        // seen only in the band the bevel's width under the top.)
        canvas.save()
        canvas.clipRect(Rect.fromLTRB(box.left - w, box.top - w, box.right + w, box.top + w))
        let light = Paint()
        light.style = .stroke
        light.isAntiAlias = true
        light.strokeWidth = 0.5 * w
        light.color = shade { Double($0) * (1 + 0.07 * k) + 68 * k }
        light.maskFilter = MaskFilter(blur: .normal, 0.22 * w)
        canvas.translate(0, 0.3 * w)
        canvas.drawPath(outline, light)
        canvas.restore()
        canvas.restore()
    }

    /// The presets whose `path="shape"` PowerPoint prints as a circle gradient (lab gradshape: the ellipse
    /// the right arrow; an ellipse, a star and a heart nest their own outline instead).
    static func shapePathIsCircle(_ preset: String?) -> Bool { preset == "rightArrow" }

    /// The colour a path gradient has `u` of the way from its focus (0) to its edge (1).
    static func pathRampColor(_ colors: [Color], _ positions: [Double]) -> (Double) -> Color {
        func at(_ u: Double) -> Color {
            guard let j = positions.firstIndex(where: { $0 >= u }) else { return colors.last! }
            if j == 0 { return colors[0] }
            let a = positions[j - 1], b = positions[j]
            let k = b > a ? (u - a) / (b - a) : 0
            func ch(_ c: Color, _ sh: Int) -> Double { Double((c.value >> sh) & 0xFF) }
            func m(_ sh: Int) -> Int64 { Int64((ch(colors[j - 1], sh) * (1 - k) + ch(colors[j], sh) * k).rounded()) }
            let al = Int64((Double(colors[j - 1].alpha) * (1 - k) + Double(colors[j].alpha) * k).rounded())
            return Color(al << 24 | m(16) << 16 | m(8) << 8 | m(0))
        }
        return at
    }

    /// `path="shape"` on a shape that is not a box: the outline itself, shrunk toward the fill-to point
    /// in as many steps, each in the colour that far along (PowerPoint's print of lab gradshape: nested
    /// ellipses, stars, hearts; with a corner point the copies crowd into that corner).
    static func paintShapePath(_ fill: SlideFill, _ outline: Path, _ r: Rect, _ canvas: any Canvas, ellipse: Bool = false) {
        let (colors, positions) = fill.squared ? Self.squaredRamp(fill.stops) : (fill.stops.map(\.color), fill.stops.map(\.position))
        let at = pathRampColor(colors, positions)
        let f = fill.fillTo
        // (An ellipse keeps to its middle whatever the fill-to point, as a circle does: lab gradshape.)
        let mid = ellipse && cornerFocus(f)
        let fx = r.left + (mid ? 0.5 : (f.left + f.right) / 2) * r.width, fy = r.top + (mid ? 0.5 : (f.top + f.bottom) / 2) * r.height
        let p = Paint()
        p.style = .fill
        p.color = at(1)
        canvas.drawRect(r, p)
        let steps = 96
        for k in 0 ... steps {
            let t = 1 - Double(k) / Double(steps)
            p.color = at(t)
            canvas.save()
            canvas.translate(fx, fy)
            canvas.scale(t, t)
            canvas.translate(-fx, -fy)
            canvas.drawPath(outline, p)
            canvas.restore()
        }
    }

    static func paintFill(_ fill: SlideFill, _ r: Rect, _ canvas: any Canvas, cache: SlideTextCache, pxPerPt: Double = 1,
                          turn: Double = 0) {
        if let overlay = fill.overlay {
            // The fill and its overlay in a layer of their own, the overlay
            // blended into the fill alone, not into what lies behind it.
            var base = fill
            base.overlay = nil
            canvas.saveLayer(r, Paint())
            paintFill(base, r, canvas, cache: cache, pxPerPt: pxPerPt)
            let blend = Paint()
            switch overlay.blend {
            case "mult": blend.blendMode = .multiply
            case "screen": blend.blendMode = .screen
            case "darken": blend.blendMode = .darken
            case "lighten": blend.blendMode = .lighten
            default: blend.blendMode = .srcOver
            }
            canvas.saveLayer(r, blend)
            paintFill(overlay.fill, r, canvas, cache: cache, pxPerPt: pxPerPt)
            canvas.restore()
            canvas.restore()
            return
        }
        // A rectangle's path gradient (`path="rect"`, or `"shape"` on a
        // box): rectangles from the fill-to rectangle out to the area's
        // edges, each in the colour that far along — a slide shaded to its
        // title (tdf114848's, light along the whole title box and darker
        // toward every edge, where a circle round the middle had it).
        if fill.path == .rect || fill.path == .shape, fill.stops.count >= 2, r.width > 0, r.height > 0 {
            let (colors, positions) = fill.squared ? Self.squaredRamp(fill.stops)
                : fill.even || fill.path != nil ? (fill.stops.map(\.color), fill.stops.map(\.position))
                                                : Self.linearLight(fill.stops, eased: fill.eased, shifted: false)
            let at = Self.pathRampColor(colors, positions)
            let f = fill.fillTo
            // (`fillTo` holds the fill-to rectangle's edges as fractions across and down: its right and
            // bottom are `1 - r` and `1 - b`. A corner point, l 100% b 100%, once read as r.left to r.right
            // — an inverted box — and drew solid; lab gradpath.)
            // (Laid out in the tile rectangle where there is one, and clipped to the area: lab gradpath.)
            // (The tile rectangle is where the boxes end; the fill-to point stays measured on the area itself.)
            var t0 = Rect.fromLTRB(0, 0, 1, 1)
            if let t = fill.tile { t0 = t }
            let outer = Rect.fromLTRB(r.left + t0.left * r.width, r.top + t0.top * r.height,
                                      r.left + t0.right * r.width, r.top + t0.bottom * r.height)
            let inner = Rect.fromLTRB(r.left + f.left * r.width, r.top + f.top * r.height,
                                      r.left + f.right * r.width, r.top + f.bottom * r.height)
            let steps = 96
            let p = Paint()
            p.style = .fill
            canvas.save()
            canvas.clipRect(r)
            p.color = at(1)
            canvas.drawRect(r, p)
            for k in 0 ... steps {
                let t = 1 - Double(k) / Double(steps)
                let box = Rect.fromLTRB(inner.left + (outer.left - inner.left) * t, inner.top + (outer.top - inner.top) * t,
                                        inner.right + (outer.right - inner.right) * t, inner.bottom + (outer.bottom - inner.bottom) * t)
                p.color = at(t)
                canvas.drawRect(box, p)
            }
            canvas.restore()
            return
        }
        let p = Paint()
        p.style = .fill
        p.color = fill.color ?? Color(0xFFFFFFFF)
        if let shader = Self.gradientShader(fill, r) {
            p.shader = shader
            // The paint's own alpha scales the shader: a first stop that is
            // transparent must not make the whole gradient so.
            p.color = Color(0xFFFFFFFF)
        }
        // A picture fill has nothing under it: one drawn half transparent
        // shows what lies behind, not white (the Concourse theme's corner).
        if fill.image == nil || fill.color != nil || p.shader != nil { canvas.drawRect(r, p) }
        if let image = fill.image, let metafile = cache.metafile(image) {
            // A WMF or EMF as the fill: its drawing played over the area
            // (stretched, or into its `a:fillRect`), as vectors; not tiled —
            // a metafile has no pixel size to tile at.
            let recoloured = fill.imageAlpha < 1 || fill.duotone != nil || fill.imageLevels != nil
            if recoloured { canvas.saveLayer(r, imagePaint(alpha: fill.imageAlpha, duotone: fill.duotone, levels: fill.imageLevels)) }
            metafile.paint(canvas, in: Self.inset(r, fill.imageInset), image: { cache.image($0) }, font: OfficeFonts.substitute)
            if recoloured { canvas.restore() }
        }
        if let image = fill.image, let drawn = cache.image(image) {
            // A picture with its own transparency is drawn from a copy with
            // the transparency in its pixels, as PowerPoint writes it (a new
            // picture in the PDF, with an alpha channel, not the JPEG).
            let baked = fill.imageAlpha < 1 && fill.duotone == nil && fill.imageLevels == nil ? cache.withAlpha(drawn, fill.imageAlpha) : nil
            var decoded = baked ?? drawn
            // (A tiled PNG with its own transparency is written as a colour
            // picture with a mask and marked smooth, as a JPEG is: lo-page_transparent_bitmap's
            // brick tile, PowerPoint's PDF; a lone PNG with alpha stays lossless and sharp.)
            if let b = baked, fill.tiled, !fill.isPattern { let k = UInt64(b.width) << 32 | UInt64(b.height); SlideTextCache.jpegSizes.insert(k); SlideTextCache.alphaSmooth.insert(k) }
            let paint = baked != nil ? imagePaint(alpha: 1, duotone: nil) : imagePaint(alpha: fill.imageAlpha, duotone: fill.duotone, levels: fill.imageLevels)
            let tw = max(1, Double(decoded.width) * 0.75 * fill.tileScale * pxPerPt)
            let th = max(1, Double(decoded.height) * 0.75 * fill.tileScaleY * pxPerPt)
            // PowerPoint's PDF holds a tiled picture shrunk to 200 pixels an
            // inch (a 484 x 290 picture on a 69.7 x 48.7 pt tile is 193 x 135).
            if fill.tiled, !fill.isPattern, fill.duotone == nil, fill.imageLevels == nil {
                let nw = Int(tw / pxPerPt * 200 / 72), nh = Int(th / pxPerPt * 200 / 72)
                if nw >= 1, nh >= 1, nw < decoded.width, nh < decoded.height, let small = cache.scaled(decoded, nw, nh) { decoded = small }
            }
            let src = Rect.fromLTWH(0, 0, Double(decoded.width), Double(decoded.height))
            // A tile larger than the area is cropped, not fitted: Windows
            // PowerPoint lays ececapstonespring2012's 1600x1200 px background
            // at 96/in, 1200 pt wide on a 794 pt slide.
            if fill.tiled {
                // At the picture's own size (96/in) times the tile scale,
                // from the one tile the alignment and offset place, back
                // to the area's top left edge and on past its bottom right.
                canvas.save()
                canvas.clipRect(r)
                var r = r
                if fill.tileAnchored, turn != 0 {
                    // Untouched by the turn: tiles over what the turned
                    // area covers, square to the slide.
                    let c = r.center, a = turn * .pi / 180
                    canvas.translate(c.dx, c.dy)
                    canvas.rotate(-a)
                    canvas.translate(-c.dx, -c.dy)
                    let w = abs(r.width * cos(a)) + abs(r.height * sin(a)), h = abs(r.width * sin(a)) + abs(r.height * cos(a))
                    r = Rect.fromLTWH(c.dx - w / 2, c.dy - h / 2, w, h)
                }
                let x0 = fill.tileAnchored ? 0 : r.left + (r.width - tw) * fill.tileAlign.dx + fill.tileOffset.dx * pxPerPt
                let y0 = fill.tileAnchored ? 0 : r.top + (r.height - th) * fill.tileAlign.dy + fill.tileOffset.dy * pxPerPt
                var y = y0 - ((y0 - r.top) / th).rounded(.up) * th
                while y < r.bottom {
                    var x = x0 - ((x0 - r.left) / tw).rounded(.up) * tw
                    while x < r.right {
                        canvas.drawImageRect(decoded, src, Rect.fromLTWH(x, y, tw, th), paint)
                        x += tw
                    }
                    y += th
                }
                canvas.restore()
            } else if fill.imageInset != .zero {
                // `a:fillRect`: stretched into its place within the area.
                canvas.save()
                canvas.clipRect(r)
                canvas.drawImageRect(decoded, src, Self.inset(r, fill.imageInset), paint)
                canvas.restore()
            } else {
                canvas.drawImageRect(decoded, src, r, paint)
            }
        }
    }

    /// `r` inset by fractions of its own size from each edge.
    /// A PNG with an alpha channel (colour type 4 or 6, or a tRNS chunk): PowerPoint's PDF
    /// keeps it at its own pixels (lo-tdf95932: 996 px over 325.9 pt, 220/in, with a soft mask).
    static func pngHasAlpha(_ data: Data) -> Bool {
        let b = [UInt8](data.prefix(4096))
        guard b.count > 33, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 else { return false }
        if b[25] == 4 || b[25] == 6 { return true }
        let t: [UInt8] = [0x74, 0x52, 0x4E, 0x53]
        var i = 33
        while i + 8 <= b.count {
            if Array(b[(i + 4)..<(i + 8)]) == t { return true }
            let n = Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
            i += 12 + n
        }
        return false
    }

    static func inset(_ r: Rect, _ f: EdgeInsets) -> Rect {
        guard f != .zero else { return r }
        return Rect.fromLTRB(r.left + f.left * r.width, r.top + f.top * r.height,
                             r.right - f.right * r.width, r.bottom - f.bottom * r.height)
    }

    /// The paint for a picture: its transparency, and a duotone as a colour
    /// matrix (luminance maps from the first colour to the second).
    static func imagePaint(alpha: Double, duotone: [Color]?, levels: [Double]? = nil) -> Paint {
        let p = Paint()
        p.filterQuality = .medium
        if alpha < 1 { p.color = Color(0xFFFFFFFF).withOpacity(alpha) }
        var matrix = levels
        if let d = duotone, d.count == 2 {
            func ch(_ c: Color, _ sh: Int) -> Double { Double((c.value >> sh) & 0xFF) }
            var m: [Double] = []
            for sh in [16, 8, 0] {
                let lo = ch(d[0], sh), hi = ch(d[1], sh), k = hi - lo
                m += [0.299 * k / 255, 0.587 * k / 255, 0.114 * k / 255, 0, lo]
            }
            m += [0, 0, 0, 1, 0]
            // The levels first, then the duotone over what they give.
            matrix = levels.map { Self.compose(m, $0) } ?? m
        }
        if let matrix { p.colorFilter = ColorFilter(matrix: matrix) }
        return p
    }

    /// The 4×5 colour matrix that applies `b`, then `a`.
    static func compose(_ a: [Double], _ b: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: 20)
        for r in 0 ..< 4 {
            for c in 0 ..< 5 {
                var v = c == 4 ? a[r * 5 + 4] : 0
                for k in 0 ..< 4 { v += a[r * 5 + k] * b[k * 5 + c] }
                out[r * 5 + c] = v
            }
        }
        return out
    }

    /// The presets `geometryPath` draws as themselves (at their default
    /// adjust values) when a shape has no evaluated path; a shape read from
    /// a file has one for every preset in `PresetDefinitions`.
    static let drawablePresets: Set<String> = [
        "rect", "roundRect", "round2DiagRect", "ellipse", "flowChartConnector", "flowChartTerminator", "triangle",
        "rtTriangle", "diamond", "flowChartDecision", "parallelogram", "flowChartInputOutput", "hexagon", "homePlate",
        "chevron", "plus", "mathPlus", "mathMinus", "mathEqual", "mathNotEqual", "mathMultiply", "mathDivide",
        "leftArrow", "upArrow", "downArrow", "leftBrace", "rightBrace",
        "leftBracket", "rightBracket", "rightArrow", "star5", "wedgeRectCallout", "line",
    ]

    /// A straight band `width` wide from `a` to `b`, added to `path` wound
    /// the way `addRect` winds (clockwise on screen), so bands and boxes in
    /// one path fill as their union rather than cutting holes where they
    /// cross.
    static func band(_ path: Path, _ a: Offset, _ b: Offset, _ width: Double) {
        let len = max(1e-6, hypot(b.dx - a.dx, b.dy - a.dy))
        let n = Offset(-(b.dy - a.dy) / len * width / 2, (b.dx - a.dx) / len * width / 2)
        var pts = [Offset(a.dx - n.dx, a.dy - n.dy), Offset(a.dx + n.dx, a.dy + n.dy),
                   Offset(b.dx + n.dx, b.dy + n.dy), Offset(b.dx - n.dx, b.dy - n.dy)]
        var area = 0.0
        for i in pts.indices { let p = pts[i], q = pts[(i + 1) % 4]; area += p.dx * q.dy - q.dx * p.dy }
        if area < 0 { pts.reverse() }
        path.addPolygon(pts, true)
    }

    /// Every filled subpath of a freeform as one path (its holes cut).
    static func combinedPath(_ g: FreeformGeometry, _ r: Rect) -> Path {
        let path = Path()
        path.fillType = .evenOdd
        for sub in g.subpaths where sub.fill { path.addPath(FreeformGeometry.path(sub, in: r), Offset.zero) }
        return path
    }

    /// PowerPoint blends gradient stops in linear light, so the middle of
    /// red-to-green is a bright orange, not the sRGB midpoint's brown. The
    /// shader blends in sRGB; these are the stops with linear-light
    /// in-betweens spelled out, so it lands where PowerPoint does.
    ///
    /// `shifted` (no longer asked for): as PowerPoint for MAC's export shows
    /// it — Windows PowerPoint's prints are plain sRGB, with no such shift
    /// (aascu 5864's blue band 0,0,121 .. 0,0,252, not 9,48,254), so none
    /// of the corpus' references want it now. The Mac export writes such a
    /// gradient's blend as linear values tagged "Generic RGB Linear", whose
    /// primaries are not sRGB's, so every colour of it — the stops too —
    /// prints a little off: pure blue as 9,48,254, red as 255,39,0
    /// (aascu 5864's blue band, tdf105739's red to green; the profile's
    /// own matrix, `Self.genericLinear`).
    static func linearLight(_ stops: [SlideFill.GradientStop], eased: Bool = false, shifted: Bool = false) -> ([Color], [Double]) {
        func lin(_ v: Int) -> Double { let c = Double(v) / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func srgb(_ l: Double) -> Int { let c = l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055; return Int((max(0, min(1, c)) * 255).rounded()) }
        func part(_ c: Color, _ sh: Int) -> Int { (c.value >> sh) & 0xFF }
        func packed(_ alpha: Int, _ l: (Double, Double, Double)) -> Color {
            var (r, g, b) = l
            if shifted {
                let m = Self.genericLinear
                (r, g, b) = (m[0] * l.0 + m[1] * l.1 + m[2] * l.2, m[3] * l.0 + m[4] * l.1 + m[5] * l.2, m[6] * l.0 + m[7] * l.1 + m[8] * l.2)
            }
            let value: Int = (alpha << 24) | (srgb(r) << 16) | (srgb(g) << 8) | srgb(b)
            return Color(value)
        }
        func linear(_ c: Color) -> (Double, Double, Double) { (lin(part(c, 16)), lin(part(c, 8)), lin(part(c, 0))) }
        var colors: [Color] = [], positions: [Double] = []
        for i in 0 ..< stops.count {
            let s = stops[i]
            if i > 0 {
                let a = stops[i - 1]
                // (An eased blend bends more, and takes more in-betweens.)
                let steps = eased ? 16 : 8
                let from = linear(a.color), to = linear(s.color)
                for k in 1 ..< steps {
                    let at = Double(k) / Double(steps)
                    let t = eased ? (1 - cos(.pi * at)) / 2 : at
                    let aa = Double(part(a.color, 24)), sa = Double(part(s.color, 24))
                    let alpha = Int((aa * (1 - t) + sa * t).rounded())
                    colors.append(packed(alpha, (from.0 * (1 - t) + to.0 * t, from.1 * (1 - t) + to.1 * t, from.2 * (1 - t) + to.2 * t)))
                    positions.append(a.position + (s.position - a.position) * at)
                }
            }
            colors.append(shifted ? packed(part(s.color, 24), linear(s.color)) : s.color)
            positions.append(s.position)
        }
        return (colors, positions)
    }

    /// Apple's "Generic RGB Linear" to sRGB, both in linear light: the
    /// profile's D50 primaries (its rXYZ, gXYZ, bXYZ) into sRGB's, as a
    /// viewer converts them. Row-major.
    static let genericLinear: [Double] = [1.02419807, -0.02755359, 0.00291467,
                                          0.02069563, 0.949455, 0.03060898,
                                          -0.00206945, -0.00198748, 1.00323661]

    /// A `gamma` gradient's stops (`SlideFill.squared`) with in-betweens:
    /// each blend in sRGB, leaving the lighter of its two stops as the
    /// square of the way along.
    /// How far along a `gamma` blend has gone from its lighter stop at `t` (0 to 1): PowerPoint's print
    /// of the 45541 decks' backgrounds (102 -> 47 and 205 -> 94 in green) holds to the light end, then
    /// falls fastest past the middle: a tenth of the way at a quarter, 0.38 at half, 0.79 at three quarters.
    static func gammaEase(_ t: Double) -> Double {
        let xs = [0.0, 0.25, 0.5, 0.75, 1.0], ys = [0.0, 0.10, 0.385, 0.79, 1.0]
        let i = min(3, max(0, Int(t * 4)))
        return ys[i] + (ys[i + 1] - ys[i]) * (t - xs[i]) / 0.25
    }

    static func squaredRamp(_ stops: [SlideFill.GradientStop]) -> ([Color], [Double]) {
        func part(_ c: Color, _ sh: Int) -> Double { Double((c.value >> sh) & 0xFF) }
        func light(_ c: Color) -> Double { 0.2126 * part(c, 16) + 0.7152 * part(c, 8) + 0.0722 * part(c, 0) }
        var colors: [Color] = [], positions: [Double] = []
        for i in 0 ..< stops.count {
            let s = stops[i]
            if i > 0 {
                let a = stops[i - 1]
                let fromLight = light(a.color) >= light(s.color)
                let steps = 16
                for k in 1 ..< steps {
                    let at = Double(k) / Double(steps)
                    let t = fromLight ? Self.gammaEase(at) : 1 - Self.gammaEase(1 - at)
                    func ch(_ sh: Int) -> Int { Int((part(a.color, sh) * (1 - t) + part(s.color, sh) * t).rounded()) }
                    colors.append(Color((ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)))
                    positions.append(a.position + (s.position - a.position) * at)
                }
            }
            colors.append(s.color)
            positions.append(s.position)
        }
        return (colors, positions)
    }

    /// The outline of a preset shape filling `r`, with PowerPoint's default
    /// adjustments.
    /// An arrowhead at `tip`, the line coming from `from`: PowerPoint's
    /// sizes, its width and length multiples of the line's width with the
    /// width taken as 2 pt at least (`base`) — a medium head on a ¾ or
    /// ½ pt line is 6 pt wide and long in its print (cooper's, lo-
    /// connectors'), on a 3¼ pt one about 10 (customGeo's).
    static func lineEnd(_ e: LineEnd, tip: Offset, from: Offset, base: Double, paint line: Paint, _ canvas: any Canvas) {
        let d = Offset(tip.dx - from.dx, tip.dy - from.dy), len = (d.dx * d.dx + d.dy * d.dy).squareRoot()
        guard len > 1e-6 else { return }
        let u = Offset(d.dx / len, d.dy / len), n = Offset(-u.dy, u.dx)
        let w = e.width * base / 2, l = e.length * base
        func at(_ along: Double, _ across: Double) -> Offset {
            Offset(tip.dx + u.dx * along + n.dx * across, tip.dy + u.dy * along + n.dy * across)
        }
        let p = Paint()
        p.isAntiAlias = true
        p.color = line.color
        let path = Path()
        switch e.kind {
        case "arrow":
            // Open: two strokes back from the tip, at the line's width.
            p.style = .stroke
            p.strokeWidth = line.strokeWidth
            p.strokeCap = .round
            p.strokeJoin = .round
            let s = at(-l, w), t = at(-l, -w)
            path.moveTo(s.dx, s.dy); path.lineTo(tip.dx, tip.dy); path.lineTo(t.dx, t.dy)
            canvas.drawPath(path, p)
            return
        case "stealth":
            let s = at(-l, w), m = at(-l * 0.5, 0), t = at(-l, -w)
            path.moveTo(tip.dx, tip.dy); path.lineTo(s.dx, s.dy); path.lineTo(m.dx, m.dy); path.lineTo(t.dx, t.dy); path.close()
        case "diamond":
            let f = at(l / 2, 0), s = at(0, w), k = at(-l / 2, 0), t = at(0, -w)
            path.moveTo(f.dx, f.dy); path.lineTo(s.dx, s.dy); path.lineTo(k.dx, k.dy); path.lineTo(t.dx, t.dy); path.close()
        case "oval":
            canvas.save()
            canvas.translate(tip.dx, tip.dy)
            canvas.rotate(atan2(u.dy, u.dx))
            p.style = .fill
            canvas.drawOval(Rect.fromLTRB(-l / 2, -w, l / 2, w), p)
            canvas.restore()
            return
        default:   // "triangle"
            let s = at(-l, w), t = at(-l, -w)
            path.moveTo(tip.dx, tip.dy); path.lineTo(s.dx, s.dy); path.lineTo(t.dx, t.dy); path.close()
        }
        p.style = .fill
        canvas.drawPath(path, p)
    }

    /// A closed outline drawn as two or three lines (`cmpd`): the full
    /// stroke with its gaps taken out. The gaps, as shares of the width
    /// from the outer edge (−½) to the inner (½), are PowerPoint's —
    /// ShapeLineProperties' 5 pt thinThick is 1 pt out, 1 pt gap, 3 pt in.
    static func compoundOutline(_ path: Path, _ compound: String, _ line: Paint, _ canvas: any Canvas) {
        let gaps: [(Double, Double)]
        switch compound {
        case "dbl": gaps = [(-1.0 / 6, 1.0 / 6)]
        case "thickThin": gaps = [(0.1, 0.3)]
        case "thinThick": gaps = [(-0.3, -0.1)]
        case "tri": gaps = [(-0.3, -0.1), (0.1, 0.3)]
        default: canvas.drawPath(path, line); return
        }
        let w = line.strokeWidth
        let b = path.getBounds().inflate(w * 2 + 4)
        canvas.saveLayer(b, Paint())
        canvas.drawPath(path, line)
        let erase = Paint()
        erase.style = .stroke
        erase.isAntiAlias = true
        erase.blendMode = .dstOut
        erase.color = Color(0xFF000000)
        for (a0, b0) in gaps {
            let a = a0 * w, bb = b0 * w
            if a < 0 && bb > 0 {
                // Across the middle (dbl's): symmetric, rubbed out whole.
                erase.strokeWidth = 2 * max(-a, bb)
                canvas.drawPath(path, erase)
                continue
            }
            // On one side: rubbed out to its far edge, the line put back
            // up to its near edge, inside or outside the outline only.
            canvas.save()
            if a >= 0 {
                canvas.clipPath(path)
            } else {
                let outside = Path()
                outside.fillType = .evenOdd
                outside.addRect(b)
                outside.addPath(path, Offset.zero)
                canvas.clipPath(outside)
            }
            let far = max(abs(a), abs(bb)), near = min(abs(a), abs(bb))
            erase.strokeWidth = 2 * far
            canvas.drawPath(path, erase)
            if near > 0 {
                let back = Paint()
                back.style = .stroke
                back.isAntiAlias = true
                back.color = line.color
                back.strokeWidth = 2 * near
                canvas.drawPath(path, back)
            }
            canvas.restore()
        }
        canvas.restore()
    }

    /// A path's two ends and the points they come from (the next point,
    /// or a curve's control point), for its arrowheads.
    static func pathEnds(_ s: FreeformGeometry.Subpath, in r: Rect)
        -> (start: Offset, startFrom: Offset, end: Offset, endFrom: Offset)? {
        func at(_ u: Double, _ v: Double) -> Offset { Offset(r.left + u * r.width, r.top + v * r.height) }
        var pts: [(Offset, Offset)] = []   // (point, the control it leaves toward / arrives from)
        var current: Offset? = nil
        var firstOut: Offset? = nil
        var lastIn: Offset? = nil
        var start: Offset? = nil
        for c in s.commands {
            switch c {
            case .move(let u, let v): current = at(u, v); start = current
            case .line(let u, let v):
                let p = at(u, v)
                if firstOut == nil { firstOut = p }
                lastIn = current; current = p
            case .quad(let u1, let v1, let u, let v):
                if firstOut == nil { firstOut = at(u1, v1) }
                lastIn = at(u1, v1); current = at(u, v)
            case .cubic(let u1, let v1, let u2, let v2, let u, let v):
                if firstOut == nil { firstOut = at(u1, v1) }
                lastIn = at(u2, v2); current = at(u, v)
            default: break
            }
        }
        _ = pts
        guard let s0 = start, let f0 = firstOut, let e = current, let l = lastIn else { return nil }
        return (s0, f0, e, l)
    }

    static func geometryPath(_ preset: ShapePreset, _ r: Rect) -> Path {
        let path = Path()
        let w = r.width, h = r.height, l = r.left, t = r.top
        let ss = min(w, h)
        switch preset.rawValue {
        case "roundRect":
            path.addRRect(RRect(fromRectAndRadius: r, Radius(circular: ss * 0.1667)))
        case "round2DiagRect":
            path.addRRect(RRect(fromLTRBAndCorners: l, t, r.right, r.bottom,
                                topLeft: Radius(circular: ss * 0.1667), topRight: .zero,
                                bottomRight: Radius(circular: ss * 0.1667), bottomLeft: .zero))
        case "ellipse", "flowChartConnector":
            path.addOval(r)
        case "flowChartTerminator":
            path.addRRect(RRect(fromRectAndRadius: r, Radius(circular: h / 2)))
        case "triangle":
            path.addPolygon([Offset(l + w / 2, t), Offset(r.right, r.bottom), Offset(l, r.bottom)], true)
        case "rtTriangle":
            path.addPolygon([Offset(l, t), Offset(r.right, r.bottom), Offset(l, r.bottom)], true)
        case "diamond", "flowChartDecision":
            path.addPolygon([Offset(l + w / 2, t), Offset(r.right, t + h / 2), Offset(l + w / 2, r.bottom),
                             Offset(l, t + h / 2)], true)
        case "parallelogram", "flowChartInputOutput":
            let k = ss * 0.25
            path.addPolygon([Offset(l + k, t), Offset(r.right, t), Offset(r.right - k, r.bottom), Offset(l, r.bottom)], true)
        case "hexagon":
            let k = ss * 0.25
            path.addPolygon([Offset(l + k, t), Offset(r.right - k, t), Offset(r.right, t + h / 2),
                             Offset(r.right - k, r.bottom), Offset(l + k, r.bottom), Offset(l, t + h / 2)], true)
        case "homePlate":
            let k = ss * 0.5
            path.addPolygon([Offset(l, t), Offset(r.right - k, t), Offset(r.right, t + h / 2),
                             Offset(r.right - k, r.bottom), Offset(l, r.bottom)], true)
        case "chevron":
            let k = ss * 0.5
            path.addPolygon([Offset(l, t), Offset(r.right - k, t), Offset(r.right, t + h / 2),
                             Offset(r.right - k, r.bottom), Offset(l, r.bottom), Offset(l + k, t + h / 2)], true)
        case "mathMinus":
            path.addRect(Rect.fromLTWH(l + w * 0.1, t + h * (0.5 - 0.1176), w * 0.8, h * 0.2352))
        case "mathEqual", "mathNotEqual":
            // Two bars 73.49% wide, each 23.52% tall, 11.76% apart (the
            // preset's defaults); "not equal" adds a stroke through them
            // at 110°, running the full height.
            let dx = w * 0.36745, bar = h * 0.2352, gap = h * 0.0588
            let vc = t + h / 2
            path.addRect(Rect.fromLTRB(l + w / 2 - dx, vc - gap - bar, l + w / 2 + dx, vc - gap))
            path.addRect(Rect.fromLTRB(l + w / 2 - dx, vc + gap, l + w / 2 + dx, vc + gap + bar))
            if preset.rawValue == "mathNotEqual" {
                let ang = 110.0 * .pi / 180
                let dir = Offset(cos(ang), sin(ang))
                let top = (t - vc) / dir.dy, bottom = (r.bottom - vc) / dir.dy
                Self.band(path, Offset(l + w / 2 + dir.dx * top, t), Offset(l + w / 2 + dir.dx * bottom, r.bottom), bar)
            }
        case "mathMultiply":
            // An X along the diagonals: arms 23.52% of the short side thick,
            // reaching 48% of the diagonal out from the centre.
            let th = ss * 0.2352, diag = hypot(w, h), reach = diag * 0.48 / 2 + th / 2
            let c = r.center
            for d in [Offset(w / diag, h / diag), Offset(w / diag, -h / diag)] {
                Self.band(path, Offset(c.dx - d.dx * reach, c.dy - d.dy * reach),
                          Offset(c.dx + d.dx * reach, c.dy + d.dy * reach), th)
            }
        case "mathDivide":
            // A bar with a dot above and below it (the preset's defaults).
            let dx = w * 0.36745, dy = h * 0.1176, gap = h * 0.0588, rad = h * 0.1176
            let vc = t + h / 2
            path.addRect(Rect.fromLTRB(l + w / 2 - dx, vc - dy, l + w / 2 + dx, vc + dy))
            path.addOval(Rect.fromCircle(center: Offset(l + w / 2, vc - dy - gap - rad), radius: rad))
            path.addOval(Rect.fromCircle(center: Offset(l + w / 2, vc + dy + gap + rad), radius: rad))
        case "plus", "mathPlus":
            let k = ss * 0.25
            path.addPolygon([Offset(l + k, t), Offset(r.right - k, t), Offset(r.right - k, t + k), Offset(r.right, t + k),
                             Offset(r.right, r.bottom - k), Offset(r.right - k, r.bottom - k), Offset(r.right - k, r.bottom),
                             Offset(l + k, r.bottom), Offset(l + k, r.bottom - k), Offset(l, r.bottom - k),
                             Offset(l, t + k), Offset(l + k, t + k)], true)
        case "leftArrow":
            let head = ss * 0.5
            path.addPolygon([Offset(r.right, t + h * 0.25), Offset(l + head, t + h * 0.25), Offset(l + head, t),
                             Offset(l, t + h / 2), Offset(l + head, r.bottom), Offset(l + head, t + h * 0.75),
                             Offset(r.right, t + h * 0.75)], true)
        case "upArrow", "downArrow":
            let head = ss * 0.5
            let up = preset.rawValue == "upArrow"
            let tip = up ? t : r.bottom, base = up ? t + head : r.bottom - head, tail = up ? r.bottom : t
            path.addPolygon([Offset(l + w * 0.25, tail), Offset(l + w * 0.25, base), Offset(l, base),
                             Offset(l + w / 2, tip), Offset(r.right, base), Offset(l + w * 0.75, base),
                             Offset(l + w * 0.75, tail)], true)
        case "leftBrace", "rightBrace":
            // Two quarter curls each side of a point, as PowerPoint's brace.
            let left = preset.rawValue == "leftBrace"
            let x0 = left ? r.right : l, x1 = left ? l + w / 2 : r.right - w / 2, x2 = left ? l : r.right
            let q = min(h * 0.083, w)
            path.moveTo(x0, t)
            path.quadraticBezierTo(x1, t, x1, t + q)
            path.lineTo(x1, t + h / 2 - q)
            path.quadraticBezierTo(x1, t + h / 2, x2, t + h / 2)
            path.quadraticBezierTo(x1, t + h / 2, x1, t + h / 2 + q)
            path.lineTo(x1, r.bottom - q)
            path.quadraticBezierTo(x1, r.bottom, x0, r.bottom)
        case "leftBracket", "rightBracket":
            let left = preset.rawValue == "leftBracket"
            let x0 = left ? r.right : l, x1 = left ? l : r.right
            path.moveTo(x0, t); path.lineTo(x1, t); path.lineTo(x1, r.bottom); path.lineTo(x0, r.bottom)
        case _ where preset.rawValue.hasPrefix("bentConnector") || preset.rawValue.hasPrefix("curvedConnector"):
            path.moveTo(l, t); path.lineTo(l + w / 2, t); path.lineTo(l + w / 2, r.bottom); path.lineTo(r.right, r.bottom)
        case "rightArrow":
            let head = min(w, h) * 0.5
            let shaftTop = t + h * 0.25, shaftBottom = t + h * 0.75
            path.addPolygon([
                Offset(l, shaftTop), Offset(r.right - head, shaftTop), Offset(r.right - head, t),
                Offset(r.right, t + h / 2), Offset(r.right - head, r.bottom), Offset(r.right - head, shaftBottom),
                Offset(l, shaftBottom),
            ], true)
        case "star5":
            let c = r.center
            var points: [Offset] = []
            for i in 0 ..< 10 {
                let angle = -Double.pi / 2 + Double(i) * Double.pi / 5
                let k = i % 2 == 0 ? 1.0 : 0.382
                points.append(Offset(c.dx + cos(angle) * w / 2 * k, c.dy + sin(angle) * h / 2 * k))
            }
            path.addPolygon(points, true)
        case "wedgeRectCallout":
            // The tail leaves the bottom edge and points below-left, outside
            // the frame, as PowerPoint's default callout does.
            path.addPolygon([
                Offset(l, t), Offset(r.right, t), Offset(r.right, r.bottom),
                Offset(l + w * 0.4167, r.bottom), Offset(l + w * 0.2917, t + h * 1.125),
                Offset(l + w * 0.1667, r.bottom), Offset(l, r.bottom),
            ], true)
        default:
            // rect, flowChartProcess and every preset not drawn exactly yet.
            path.addRect(r)
        }
        return path
    }

    override func shouldRepaint(_ oldDelegate: CustomPainter) -> Bool {
        guard let old = oldDelegate as? SlidePainter else { return true }
        return old.slide !== slide || old.revision != revision || old.slideSize != slideSize
            || old.shapesOnly != shapesOnly
    }
}

/// Reports the size it is laid out at, one frame later. The framework has
/// no LayoutBuilder; this is the smallest thing that lets a widget fit its
/// content to the space it was given (the slide canvas zooms to fit).
final class SizeReporter: SingleChildRenderObjectWidget {
    let onSize: (Size) -> Void
    /// The box itself, for mapping window coordinates into it (pointer
    /// events here carry only window positions).
    let onBox: ((RenderBox) -> Void)?

    init(onSize: @escaping (Size) -> Void, onBox: ((RenderBox) -> Void)? = nil, child: Widget?) {
        self.onSize = onSize
        self.onBox = onBox
        super.init(key: nil, child: child)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        let box = _RenderSizeReporter(onSize: onSize)
        onBox?(box)
        return box
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        (renderObject as! _RenderSizeReporter).onSize = onSize
        onBox?(renderObject as! RenderBox)
    }
}

private final class _RenderSizeReporter: RenderProxyBox {
    var onSize: (Size) -> Void
    private var _reported: Size? = nil

    init(onSize: @escaping (Size) -> Void) {
        self.onSize = onSize
        super.init()
    }

    override func performLayout() {
        super.performLayout()
        let s = size
        guard s != _reported else { return }
        _reported = s
        // Not during layout: the callback rebuilds.
        FrameCallbackScheduler.shared.addPostFrameCallback { [weak self] _ in
            self?.onSize(s)
        }
        PlatformDispatcher.instance.scheduleFrame()
    }
}
