// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Paint": moved out of RichLayout.swift by test/tools/split-richlayout.py (a pure move, so that
// the parts compile side by side).

import Flutter
import FlutterSwiftBridge
import Foundation

extension RichLayout {

    // MARK: Pictures

    /// Draws an object the layout keeps but cannot draw itself (a chart),
    /// in its box: the attachment, the canvas, the box (px) and pixels per
    /// point; true where it drew it. Process-wide, like
    /// `RichTextTheme.glyphFallback`: an app answers for the kinds of
    /// object it knows.
    public nonisolated(unsafe) static var objectPainter: ((ImageAttachment, any Canvas, Rect, Double) -> Bool)? = nil
    /// Whether `objectPainter` draws an object: one it draws floats and
    /// is wrapped round as a picture is (`_wrapBoxes`).
    public nonisolated(unsafe) static var drawsObject: ((ImageAttachment) -> Bool)? = nil
    /// An object's size laid out again to the width it has (points), where
    /// it is wider than its line and can be: a display equation broken
    /// over lines. nil keeps its own size. `objectPainter` then draws the
    /// form that fits the rectangle it is given.
    public nonisolated(unsafe) static var objectFitter: ((ImageAttachment, Double) -> (width: Double, height: Double, baseline: Double)?)? = nil

    /// What `objectPainter` draws for an object with no picture — or one
    /// whose picture it draws itself (`drawsObject`: a metafile no codec
    /// reads) — in `rect`; true where it drew it.
    func _insetBox(_ image: ImageAttachment, _ box: Rect) -> Rect {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, let inset = image.inset else { return box }
        return Rect.fromLTRB(box.left + box.width * inset.left, box.top + box.height * inset.top,
                             box.right - box.width * inset.right, box.bottom - box.height * inset.bottom)
    }

    func _paintObject(_ image: ImageAttachment, _ rect0: Rect, _ canvas: any Canvas) -> Bool {
        let rect = _insetBox(image, rect0)
        guard theme.wordRules, image.data.isEmpty || Self.drawsObject?(image) == true, let paint = Self.objectPainter else { return false }
        canvas.save()
        defer { canvas.restore() }
        return paint(image, canvas, rect, theme.pixelsPerPoint * scale)
    }

    /// Inline pictures in a turned (vertical) cell: Word draws them upright, centred on where the turned line holds them.
    @inline(never)
    func _paintVerticalCellPictures(_ i: Int, _ g: ParagraphGeometry, _ canvas: any Canvas, _ c: _CellGeo, _ origin: Offset, _ document: RichDocument) {
        guard theme.wordRules, i < _inline.count, !_inline[i].isEmpty, let all = g.painter.inlinePlaceholderBoxes else { return }
        for k in 0..<_inline[i].count {
            let image = _inline[i][k]
            guard image.float == nil, let decoded = _decoded[image.id], k < _inlineBoxes[i].count else { continue }
            let slot = _inlineBoxes[i][k]
            guard slot < all.count else { continue }
            let b = all[slot].toRect().shift(origin)
            let cx: Double, cy: Double
            // Word centres the picture on the text's own column (em box), not on the taller placeholder box.
            let doc = document.paragraphs[i]
            let em = _px(doc.runs.last(where: { $0.length > 0 })?.style.fontSize ?? _named(doc, document)?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize)
            // The placeholder adds nothing across the line (its box sits on the baseline), so the em column's centre is half an em from it.
            let lift = em / 2
            if c.direction == .up {
                cx = c.colLeft + (b.top + b.bottom) / 2 + lift
                cy = c.rowTop + (c.rowSpan > 1 ? c.turnedPart ?? c.rowHeight : c.ownRowHeight) - (b.left + b.right) / 2
            } else {
                cx = c.colLeft + c.colWidth - (b.top + b.bottom) / 2 + lift
                cy = c.rowTop + (b.left + b.right) / 2
            }
            let w = _px(image.width), h = b.right - b.left
            let rect = Rect.fromLTRB(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
            _drawPicture(decoded, image, rect, canvas)
        }
    }

    /// Floating drawings anchored in a vertical-text cell. The turned block returns before the paragraph's
    /// object loop, so these (dx2 729fb556's arrow groups) were never drawn; they sit in page coordinates.
    @inline(never)
    func _paintVerticalCellFloats(_ i: Int, _ g: ParagraphGeometry, _ canvas: any Canvas) {
        guard theme.wordRules, i < _inline.count, !_inline[i].isEmpty else { return }
        for image in _inline[i] {
            let key = "\(image.id)"
            guard let float = image.float, !float.takesRoom, _decoded[image.id] == nil, image.textBox == nil,
                  !_behindDrawn.contains(key) else { continue }
            _paintOutline(image, _floatRect(float, image, g, i), canvas)
        }
    }

    /// A kept shape's line or box (`ImageAttachment.outline`), in `rect`
    /// — or what `objectPainter` draws for it, and then true.
    @discardableResult
    func _paintOutline(_ image: ImageAttachment, _ rect: Rect, _ canvas: any Canvas) -> Bool {
        guard theme.wordRules else { return false }
        let drawn = _paintObject(image, rect, canvas)
        guard let outline = image.outline else { return drawn }
        if outline.kind == .box, let fill = outline.fill {
            let paint = Paint()
            paint.style = .fill
            paint.color = fill
            // (Blurred — `a:blur`, F14's left box: Word's print spreads its
            // edge over the radius either side.)
            if outline.blur > 0 { paint.maskFilter = MaskFilter(blur: .normal, _px(outline.blur) / 2) }
            canvas.drawRect(rect, paint)
            // (An inner shadow, as Slides draws one: the dark beyond the
            // box, moved and blurred, seen only inside it — F14's right
            // box, dark along its bottom and right in Word's print. Its
            // dir 45° is the way the shadow falls inside, so the dark
            // outside comes in from that side: moved against it.)
            if let ish = outline.innerShadow {
                let dx = -_px(ish.dx), dy = -_px(ish.dy)
                let around = Path()
                around.fillType = .evenOdd
                around.addRect(rect.inflate(_px(ish.blur) * 2 + abs(dx) + abs(dy) + 2))
                around.addRect(rect)
                let p = Paint()
                p.style = .fill
                p.isAntiAlias = true
                p.color = ish.color
                if ish.blur > 0 { p.maskFilter = MaskFilter(blur: .normal, _px(ish.blur) / 2) }
                canvas.save()
                canvas.clipRect(rect)
                canvas.translate(dx, dy)
                canvas.drawPath(around, p)
                canvas.restore()
            }
        }
        guard let color = outline.color else { return drawn }
        let stroke = Paint()
        stroke.style = .stroke
        stroke.strokeWidth = max(1, _px(outline.width))
        stroke.color = color
        switch outline.kind {
        case .box: canvas.drawRect(rect, stroke)
        case .line:
            canvas.drawLine(outline.flipped ? rect.bottomLeft : rect.topLeft, outline.flipped ? rect.topRight : rect.bottomRight, stroke)
        }
        return drawn
    }

    /// Whether a picture of the document — the body's, a header's or
    /// footer's, a text box's — is still being decoded: what is painted
    /// before that is a grey box in its place. An export waits on this.
    public var hasPendingImages: Bool {
        !_decoding.isEmpty || _headerFooterCache.values.contains { $0.layout.hasPendingImages }
            || _textBoxCache.values.contains { $0.layout.hasPendingImages }
    }

    /// The pixel sizes (width << 32 | height) of the pictures decoded from a
    /// JPEG, and of those from anything else: Word for Windows marks a JPEG's
    /// picture smooth in its PDF (`/Interpolate true`) and a PNG's not.
    nonisolated(unsafe) public static var jpegSizes: Set<UInt64> = []
    nonisolated(unsafe) public static var otherPictureSizes: Set<UInt64> = []

    /// The document's tiled page background (`w:background` with a VML
    /// `v:fill type="tile"`): the picture and the size one tile is drawn at
    /// (its pixels at the file's own dpi, as Word prints it: bib-chernigovka's
    /// 128 pixel parchment is 122.88pt at 75 dpi), or nil.
    func _pageTileSource(_ document: RichDocument) -> (ImageAttachment, Double, Double)? {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, let xml = document.backgroundXML,
              xml.containsSubstring("type=\"tile\""), let at = xml.rangeOfSubstring("r:id=\"") else { return nil }
        let rest = xml[at.upperBound...]
        guard let q = rest.firstIndex(of: "\"") else { return nil }
        let id = String(rest[..<q])
        guard let rel = document.backgroundRels.first(where: { $0.id == id && !$0.external }),
              let data = document.keptParts["word/" + rel.target] ?? document.keptParts[rel.target], data.count > 24 else { return nil }
        let b = [UInt8](data.prefix(32))
        var dpiX = 96.0, dpiY = 96.0
        // (A JFIF header's density, when it says dots per inch or per centimetre.)
        if b.count >= 18, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF, b[3] == 0xE0, b[6] == 0x4A, b[7] == 0x46 {
            let dx = Double(Int(b[14]) << 8 | Int(b[15])), dy = Double(Int(b[16]) << 8 | Int(b[17]))
            if b[13] == 1, dx > 0, dy > 0 { dpiX = dx; dpiY = dy }
            else if b[13] == 2, dx > 0, dy > 0 { dpiX = dx * 2.54; dpiY = dy * 2.54 }
        }
        // (One attachment for the layout's life: its id is what the decoded picture is kept under.)
        if let kept = _tileSource, kept.0.data == data { return kept }
        let made = (ImageAttachment(data: data, width: 1, height: 1, name: "tile"), dpiX, dpiY)
        _tileSource = made
        return made
    }

    func _paintPageTile(_ p: Int, _ canvas: any Canvas, _ document: RichDocument) {
        if theme.wordRules, RichTextTheme.wordWindowsPages, let c = document.backgroundColor {
            let fill = Paint()
            fill.color = Color(Int64(0xFF000000) | Int64(c))
            fill.style = .fill
            canvas.drawRect(pageRect(p), fill)
        }
        guard let (att, dpiX, dpiY) = _pageTileSource(document) else { return }
        _ensureDecoded(att)
        guard let decoded = _decoded[att.id] else { return }
        let tw = _px(Double(decoded.width) * 72 / dpiX), th = _px(Double(decoded.height) * 72 / dpiY)
        guard tw > 1, th > 1 else { return }
        let page = pageRect(p)
        let src = Rect.fromLTWH(0, 0, Double(decoded.width), Double(decoded.height))
        canvas.save()
        canvas.clipRect(page, clipOp: .intersect, doAntiAlias: false)
        var y = page.top
        while y < page.bottom {
            var x = page.left
            while x < page.right {
                canvas.drawImageRect(decoded, src, Rect.fromLTWH(x, y, tw, th), Paint())
                x += tw
            }
            y += th
        }
        canvas.restore()
    }

    func _ensureDecoded(_ image: ImageAttachment) {
        // (An attachment with no picture in it — a drawn shape kept for
        // the file — is nothing to decode.)
        if _decoded[image.id] != nil || _decoding.contains(image.id) || image.data.isEmpty { return }
        _decoding.insert(image.id)
        let bytes = [UInt8](image.data)
        let id = image.id
        Task { @MainActor [weak self] in
            var decoded: Image? = nil
            do {
                let codec = try await instantiateImageCodec(bytes)
                let frame = try await codec.getNextFrame()
                codec.dispose()
                decoded = frame.image
                if let d = decoded {
                    let key = UInt64(d.width) << 32 | UInt64(d.height)
                    if bytes.starts(with: [0xFF, 0xD8]) { RichLayout.jpegSizes.insert(key) } else { RichLayout.otherPictureSizes.insert(key) }
                }
            } catch {
                if ProcessInfo.processInfo.environment["STARLING_RICHTEXT_PERF"] != nil {
                    FileHandle.standardError.write(Data("image \(id): not decoded: \(error) (\(bytes.count) bytes, \(bytes.prefix(8)))\n".utf8))
                }
                decoded = nil
            }
            guard let self else { decoded?.dispose(); return }
            self._decoding.remove(id)
            if let decoded {
                self._decoded[id] = decoded
                self.onNeedsRepaint?()
            }
        }
    }

    /// The picture's box for paragraph `i` in document space, or nil.
    public func imageRect(_ i: Int) -> Rect? {
        guard i < count, let size = _imageSize[i] else { return nil }
        let g = geometry(i)
        if theme.wordRules, i < _floats.count, let float = _floats[i], !float.takesRoom, i < _floatImages.count, let image = _floatImages[i] {
            return _floatRect(float, image, g, i)
        }
        // (One that takes the room under it, set from the "column" of a table's cell and centred, is
        // centred in the cell: lo-eb12e7d4 p13's second figure, over its cell in Word's print.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, i < _floats.count, let float = _floats[i], float.takesRoom,
           float.horizontalFrom == "column", float.horizontalAlign == "center", i < _cells.count, let d = _cells[i] {
            return Rect.fromLTWH(d.colLeft + (d.colWidth - size.width) / 2, g.inkTop + (i < _imageDrop.count ? _imageDrop[i] : 0), size.width, size.height)
        }
        // (Lower by its line's grid extra, `_layoutParagraph`.)
        // (And in from its left as its paragraph aligns it.)
        return Rect.fromLTWH(g.textLeft + (i < _imageShift.count ? _imageShift[i] : 0), g.inkTop + (i < _imageDrop.count ? _imageDrop[i] : 0),
                             size.width, size.height)
    }

    // MARK: Geometry queries (call ensureLaidOut first)

    public var totalHeight: Double { _flowHeight }

    public func geometry(_ i: Int) -> ParagraphGeometry {
        ParagraphGeometry(painter: _painters[i]!, top: _tops[i], height: _heights[i],
                          textTop: _tops[i] + _spaceBefore[i], inkShift: i < _inkShift.count ? _inkShift[i] : 0,
                          textLeft: _textLeft[i], textWidth: _textWidth[i])
    }

    public func listLabel(_ i: Int, _ document: RichDocument) -> String? {
        if !_listValid || _listLabels.count != document.paragraphs.count { _renumberLists(document) }
        return _listLabels[i]
    }

    /// Index of the paragraph containing document y (clamped to the ends).
    /// Inside a table row this is some member of the row; `paragraphIndex(at:)`
    /// picks the cell by x.
    public func paragraphIndex(atY y: Double) -> Int {
        guard !_rowTops.isEmpty else { return 0 }
        if y < 0 { return 0 }
        var lo = 0
        var hi = _rowTops.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if _rowTops[mid] <= y { lo = mid } else { hi = mid - 1 }
        }
        // The search lands on the last row member with that top; step back
        // to the row's first member so callers see the whole row.
        while lo > 0, let c = _cells[lo], let d = _cells[lo - 1], c.table == d.table, c.row == d.row { lo -= 1 }
        return lo
    }

    /// The paragraph under a document-space point: the row by y, then the
    /// cell by x, then the paragraph within the cell's stack by y.
    public func paragraphIndex(at point: Offset) -> Int {
        let i = paragraphIndex(atY: point.dy)
        guard let c = _cells[i] else { return i }
        var best = i
        var j = i
        var hit = false
        while j < _cells.count, let d = _cells[j], d.table == c.table, d.row == c.row {
            if point.dx >= d.colLeft && point.dx < d.colLeft + d.colWidth {
                // In this column: the paragraph whose block spans y, else the last.
                best = j
                hit = true
                if point.dy < _tops[j] + _heights[j] { return j }
            }
            j += 1
        }
        if !hit {
            // No cell of this row under x: a cell from a row above spans here.
            var k = i - 1
            while k >= 0, let d = _cells[k], d.table == c.table {
                if d.rowSpan > 1, d.row + d.rowSpan > c.row, point.dx >= d.colLeft, point.dx < d.colLeft + d.colWidth {
                    var m = k
                    while m > 0, let e = _cells[m - 1], e.table == d.table, e.row == d.row, e.column == d.column { m -= 1 }
                    var last = m
                    while last + 1 < _cells.count, let e = _cells[last + 1], e.table == d.table, e.row == d.row, e.column == d.column { last += 1 }
                    for q in m ... last where point.dy < _tops[q] + _heights[q] { return q }
                    return last
                }
                k -= 1
            }
        }
        return best
    }

    /// The row's box in document space for a cell paragraph, else nil.
    public func rowRect(_ i: Int) -> Rect? {
        guard i < _cells.count, let c = _cells[i] else { return nil }
        let widths = _columnWidths[c.table] ?? []
        return Rect.fromLTWH(0, c.rowTop, widths.reduce(0, +), c.ownRowHeight)
    }

    /// Paragraphs whose blocks intersect the vertical range.
    public func paragraphs(intersecting top: Double, _ bottom: Double) -> Range<Int> {
        guard !_tops.isEmpty else { return 0 ..< 0 }
        let first = paragraphIndex(atY: top)
        var last = paragraphIndex(atY: bottom)
        while last < _tops.count - 1, let c = _cells[last], let d = _cells[last + 1], c.table == d.table, c.row == d.row { last += 1 }
        if last < _tops.count - 1 { last += 1 }
        return first ..< min(_tops.count, last + 1)
    }

    /// A turned cell's "at least" line: Word puts all of the line's extra height above
    /// the text, which is `_inkShift` where the paragraph is laid out horizontally and
    /// was left out of the turned origin (lab vlab1: atLeast 480 at 12 pt printed the
    /// text 14.55 from the cell's edge, ours 11.38 — the shift is the missing half).
    func _turnedInkShift(_ i: Int, _ document: RichDocument) -> Double {
        let p = document.paragraphs[i]
        guard theme.wordRules, RichTextTheme.wordWindowsPages, p.style.lineHeightIsMinimum,
              p.style.lineHeightPoints != nil, let run = p.runs.first else { return 0 }
        // (The painter centres the extra over its own line; Word puts all of it above, so the
        // other half is half of what "at least" adds to the baseline over the text's own line.)
        let named = _named(p, document)
        let pitch = _offGrid(i, document) ? nil : _grid(i, document).pitch
        let hinted = run.style.fontHint == "eastAsia"
        let ea = p.text.contains { Self.isEastAsian($0, hinted: hinted) }
        var natural = p.style
        natural.lineHeightPoints = nil
        guard let with = theme.baseline(for: run.style, in: p.style, named: named, eastAsian: ea, gridPitch: pitch, centresInLine: document.spacesForUnderline),
              let without = theme.baseline(for: run.style, in: natural, named: named, eastAsian: ea, gridPitch: pitch, centresInLine: document.spacesForUnderline),
              with > without else { return 0 }
        return _px(with - without) / 2
    }

    /// A turned cell's paragraph, laid out in its own horizontal space and
    /// painted turned a quarter about the corner it reads from (see
    /// `_paintParagraph`): where the painter's origin lies in that space,
    /// and the maps between that space and the page's.
    func _turnedFrame(_ i: Int, _ document: RichDocument) -> (origin: Offset, toPage: (Rect) -> Rect, toLocal: (Offset) -> Offset)? {
        guard i >= 0, i < _cells.count, let c = _cells[i], c.vertical, i < document.paragraphs.count else { return nil }
        let height = c.rowSpan > 1 ? c.turnedPart ?? c.rowHeight : c.ownRowHeight
        let short = c.rowSpan > 1 && !c.wrapsPart ? c.rowHeight - height : 0
        let aligned = document.paragraphs[i].style.alignment
        let indent = _px(document.paragraphs[i].style.indentLeft)
        let fromStart = document.paragraphs[i].style.eastAsian["w:jc"] == nil && (aligned == .left || aligned == .justify)
        let along = c.alongStart + indent
            - short * (aligned == .center ? 0.5 : aligned == .right ? 1 : 0)
            - (theme.wordRules && fromStart && c.direction == .down && indent > 0.01 ? min(indent, _px(2.25)) : 0)
        let origin = Offset(along, c.across + _spaceBefore[i] + _turnedInkShift(i, document))
        if c.direction == .up {
            // (x, y) -> (colLeft + y, rowTop + height - x)
            let ox = c.colLeft, oy = c.rowTop + height
            return (origin,
                    { r in Rect.fromLTRB(ox + r.top, oy - r.right, ox + r.bottom, oy - r.left) },
                    { p in Offset(oy - p.dy, p.dx - ox) })
        }
        // (x, y) -> (colLeft + colWidth - y, rowTop + x)
        let ox = c.colLeft + c.colWidth, oy = c.rowTop
        return (origin,
                { r in Rect.fromLTRB(ox - r.bottom, oy + r.left, ox - r.top, oy + r.right) },
                { p in Offset(p.dy - oy, ox - p.dx) })
    }

    /// Caret rectangle in document space.
    public func caretRect(_ pos: RichPosition, _ document: RichDocument) -> Rect {
        let i = max(0, min(pos.paragraph, count - 1))
        if let box = imageRect(i) {
            return Rect.fromLTWH(box.left - 2, box.top, 2, box.height)
        }
        let g = geometry(i)
        let para = document.paragraphs[i]
        let offset = para.text.isEmpty ? 0 : max(0, min(pos.offset, para.length))
        let lineH = g.painter.preferredLineHeight
        let proto = Rect.fromLTWH(0, 0, 2, lineH)
        let map = _map(i)
        let o = g.painter.getOffsetForCaret(TextPosition(offset: map.painter(offset)), proto)
        let h = g.painter.getFullHeightForCaret(TextPosition(offset: map.painter(offset)), proto)
        if let t = _turnedFrame(i, document) {
            // (A turned cell's caret is a line across its text's run.)
            return t.toPage(Rect.fromLTWH(t.origin.dx + o.dx, t.origin.dy + o.dy, 2, h > 0 ? h : lineH))
        }
        return Rect.fromLTWH(g.textLeft + o.dx, g.inkTop + o.dy, 2, h > 0 ? h : lineH)
    }

    /// Highlight rectangles for a selection, in document space.
    public func selectionRects(_ sel: RichSelection, _ document: RichDocument) -> [Rect] {
        guard !sel.isCollapsed else { return [] }
        if let block = sel.block {
            // Whole cells: each selected cell's box, once per cell.
            var rects: [Rect] = []
            var seen: Set<String> = []
            // One rect per row a cell covers: a rect starting in a row maps
            // through that row's page piece, which ends at the row's bottom.
            var rowGeo: [Int: (top: Double, height: Double)] = [:]
            for i in document.paragraphs.indices {
                if let c = _cells[i], c.table == block.table, c.firstInRow { rowGeo[c.row] = (c.rowTop, c.ownRowHeight) }
            }
            for i in document.paragraphs.indices {
                guard let c = _cells[i], let ref = document.paragraphs[i].cell, block.contains(ref) else { continue }
                let key = "\(c.row),\(c.column)"
                if seen.contains(key) { continue }
                seen.insert(key)
                for r in c.row ..< c.row + c.rowSpan {
                    guard let g = rowGeo[r] else { continue }
                    rects.append(Rect.fromLTWH(c.colLeft, g.top, c.colWidth, g.height))
                }
            }
            return rects
        }
        let a = document.clamped(sel.start)
        let b = document.clamped(sel.end)
        var rects: [Rect] = []
        for i in a.paragraph ... b.paragraph {
            let g = geometry(i)
            let para = document.paragraphs[i]
            let lo = i == a.paragraph ? a.offset : 0
            let hi = i == b.paragraph ? b.offset : para.length
            if let box = imageRect(i) {
                rects.append(box)
                continue
            }
            if para.text.isEmpty || hi <= lo {
                // A selected empty paragraph (or the newline at a paragraph
                // end inside a multi-paragraph selection) shows as a sliver.
                if i != b.paragraph || para.text.isEmpty {
                    let c = caretRect(RichPosition(paragraph: i, offset: lo), document)
                    rects.append(Rect.fromLTWH(c.left, c.top, 6, c.height))
                }
                continue
            }
            // Clamp each box to the paragraph's body. The builder's `.max`
            // boxes overshoot the line grid by the fraction the line height
            // was rounded away (a 28pt line at spacing 1.0 is 37.33px laid
            // out as 37, so the first box starts at -0.33). A rect that
            // starts above its paragraph belongs, by y, to the paragraph
            // before it — canvasRects then clipped it to that paragraph's
            // bottom and the first line of a selection drew as a hairline.
            let bodyHeight = g.painter.height
            let map = _map(i)
            for box in g.painter.getBoxesForSelection(
                TextSelection(baseOffset: map.painter(lo), extentOffset: map.painter(hi)),
                boxHeightStyle: .max) {
                let top = max(0, box.top)
                let bottom = min(bodyHeight, box.bottom)
                guard bottom > top else { continue }
                if let t = _turnedFrame(i, document) {
                    rects.append(t.toPage(Rect.fromLTRB(t.origin.dx + box.left, t.origin.dy + top,
                                                        t.origin.dx + box.right, t.origin.dy + bottom)))
                    continue
                }
                rects.append(Rect.fromLTRB(g.textLeft + box.left, g.inkTop + top,
                                           g.textLeft + box.right, g.inkTop + bottom))
            }
            if _turnedFrame(i, document) != nil { continue }
            if i != b.paragraph, let last = rects.last {
                // Extend past the line end to show the newline is included.
                rects[rects.count - 1] = Rect.fromLTRB(last.left, last.top, last.right + 6, last.bottom)
            }
        }
        return rects
    }

    /// The position nearest a point in document space.
    public func position(at point: Offset, _ document: RichDocument) -> RichPosition {
        guard count > 0 else { return .start }
        let i = paragraphIndex(at: point)
        let g = geometry(i)
        let para = document.paragraphs[i]
        if para.text.isEmpty { return RichPosition(paragraph: i, offset: 0) }
        var local = Offset(point.dx - g.textLeft, min(max(point.dy - g.inkTop, 0), g.painter.height - 0.01))
        if let t = _turnedFrame(i, document) {
            let q = t.toLocal(point)
            local = Offset(q.dx - t.origin.dx, min(max(q.dy - t.origin.dy, 0), g.painter.height - 0.01))
        }
        let tp = g.painter.getPositionForOffset(local)
        return RichPosition(paragraph: i, offset: para.alignedOffset(max(0, min(_map(i).paragraph(tp.offset), para.length))))
    }

    /// Start and end offsets of the visual line holding `pos`.
    public func lineBounds(_ pos: RichPosition, _ document: RichDocument) -> (start: Int, end: Int) {
        let i = max(0, min(pos.paragraph, count - 1))
        let para = document.paragraphs[i]
        if para.text.isEmpty { return (0, 0) }
        let g = geometry(i)
        let map = _map(i)
        let bound = g.painter.getLineBoundary(TextPosition(offset: map.painter(max(0, min(pos.offset, para.length)))))
        let r = (start: map.paragraph(bound.start), end: map.paragraph(bound.end))
        var end = r.end
        // Exclude the soft-wrap space / hard newline at the end of the line
        // so End lands before it, as editors do.
        if end > r.start && end <= para.length && end > 0 {
            let idx = String.Index(utf16Offset: end - 1, in: para.text)
            if idx < para.text.endIndex, para.text[idx].isWhitespace, end < para.length { end -= 1 }
        }
        return (max(0, r.start), max(r.start, min(end, para.length)))
    }

    /// The position one line up or down from `pos`, keeping `x` (document
    /// space) — or nil at the document's top/bottom edge.
    public func verticalNeighbour(of pos: RichPosition, x: Double, down: Bool,
                                  _ document: RichDocument) -> RichPosition? {
        let c = caretRect(pos, document)
        let probeY = down ? c.bottom + 1 : c.top - 1
        if probeY < 0 || probeY >= totalHeight { return nil }
        return position(at: Offset(x, probeY), document)
    }
    func _behindPictures(_ i: Int) -> [ImageAttachment] {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, i < _inline.count, _cells[i] == nil else { return [] }
        return _inline[i].filter { image in
            guard let float = image.float, !float.takesRoom, !float.wraps, !float.bandsPage, _decoded[image.id] != nil else { return false }
            return image.sourceXML?.containsSubstring("behindDoc=\"1\"") == true
        }
    }

    /// Word's box for a bordered paragraph (lab bdr2, bdr3 over Word for
    /// Windows): the shading fills it inside the lines, the lines stand 1.4pt further out than
    /// the text and its space, and a box of joined paragraphs is one, the sides unbroken down it.
    func _boxSpan(_ i: Int, _ g: ParagraphGeometry, _ document: RichDocument) -> (top: Double, bottom: Double, extra: Double)? {
        guard theme.wordRules, RichTextTheme.wordWindowsPages,
              let b = document.paragraphs[i].style.borders, document.paragraphs[i].cell == nil else { return nil }
        let joinPrev = _bordersJoin(i - 1, i, document), joinNext = _bordersJoin(i, i + 1, document)
        let textBottom = g.textTop + g.painter.height
        var top = g.textTop - (joinPrev ? 0 : b.top.map { _px($0.space) } ?? 0)
        var bottom = textBottom + (joinNext ? 0 : b.bottom.map { _px($0.space) } ?? 0)
        if joinNext, i + 1 < count {
            let n = document.paragraphs[i + 1].style
            if !n.pageBreakInline, !n.pageBreakBefore { bottom = max(bottom, geometry(i + 1).textTop) }
        }
        top = min(top, g.textTop) - _droppedBefore(i, document)
        return (top, bottom, _px(1.4))
    }

    /// The space before a paragraph that opens a page the break ending the
    /// paragraph above made goes from the flow at the page's top, but its box stays: the shading
    /// and the sides run up over it (lab bdr3 b3, before 40: the sides start
    /// 40 above the margin, 32.04 against 72; b2, which opens with its own
    /// break, has none of it).
    /// The paragraph above is nothing but the page break (an empty paragraph): Word then treats the
    /// page as opened by flow, the box top 75 against the margin 72 (lab sbox b1e; b1t, with text
    /// above the break, runs up over the dropped space).
    func _afterBareBreak(_ i: Int, _ document: RichDocument) -> Bool {
        guard i > 0, i < document.paragraphs.count else { return false }
        let p = document.paragraphs[i - 1]
        return p.text.isEmpty && p.image == nil && p.cell == nil && p.style.borders == nil
    }

    func _droppedBefore(_ i: Int, _ document: RichDocument) -> Double {
        let st = document.paragraphs[i].style
        guard theme.wordRules, RichTextTheme.wordWindowsPages, (document.compatibilityMode ?? 12) >= 14,
              st.pageBreakBefore, st.breakEndsPrevious, !st.pageBreakInline, i < _spaceBefore.count,
              !_afterBareBreak(i, document) else { return 0 }
        return max(0, _spaceBefore[i])
    }

    func _paintShading(_ i: Int, _ canvas: any Canvas, _ document: RichDocument, part: PagePiece.Part = .all) {
        if _shadingFloats, part != .rules {
            let g = geometry(i)
            for image in _behindPictures(i) {
                guard let float = image.float, let decoded = _decoded[image.id] else { continue }
                _drawPicture(decoded, image, _floatRect(float, image, g, i), canvas)
                _behindDrawn.insert("\(image.id)")
            }
        }
        if part != .rules, let fill = document.paragraphs[i].style.fill, i < count {
            // The paragraph's own shading, text area wide.
            let g = geometry(i)
            let paint = Paint()
            paint.style = .fill
            paint.color = fill
            var height = g.painter.height
            // (Run on over the space to the next paragraph where it has the
            // same shading and edges: Word shades a block of such paragraphs
            // whole, and lo-4dc8da49's blue stands unbroken down the page
            // where ours left a white strip between the lines.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, _cells[i] == nil, i + 1 < count, i + 1 < document.paragraphs.count,
               _cells[i + 1] == nil, document.paragraphs[i + 1].style.fill == fill, document.paragraphs[i + 1].image == nil {
                let n = geometry(i + 1)
                let gap = n.textTop - (g.textTop + g.painter.height)
                if gap > 0.01, gap < _px(36), abs(n.textLeft - g.textLeft) < 0.5, abs(n.textWidth - g.textWidth) < 0.5 { height += gap }
            }
            if _emptyBreakFragment(i, document) {
                canvas.drawRect(Rect.fromLTRB((g.textLeft - _px(1.4)).rounded(), g.textTop.rounded(), (g.textLeft + g.textWidth + _px(1.4)).rounded(), (g.textTop + g.painter.height).rounded()), paint)
            } else             if let box = _boxSpan(i, g, document), let b = document.paragraphs[i].style.borders {
                let l = g.textLeft - (b.left.map { _px($0.space) } ?? 0) - box.extra
                let r = g.textLeft + g.textWidth + (b.right.map { _px($0.space) } ?? 0) + box.extra
                canvas.drawRect(Rect.fromLTRB(l.rounded(), box.top.rounded(), r.rounded(), box.bottom.rounded()), paint)
            } else {
            canvas.drawRect(Rect.fromLTWH(g.textLeft.rounded(), g.textTop.rounded(), g.textWidth.rounded(), height.rounded()), paint)
            }
        }
        if part != .text, let c = _cells[i], c.firstInRow, let ts = document.tableStyles[c.table] {
            // The row's shading, under every cell of the row: the header's,
            // or a band's.
            let header = c.row == 0 && ts.headerRow
            let bodyRow = c.row - (ts.headerRow ? 1 : 0)
            let color: Color? = header ? (ts.headerFill ?? (theme.wordRules ? nil : theme.textColor.withOpacity(0.06)))
                : (bodyRow % 2 == 0 ? ts.bandFill : ts.bandAltFill)
            if let color {
                let fill = Paint()
                fill.style = .fill
                fill.color = color
                let width = (_columnWidths[c.table] ?? []).reduce(0, +)
                let left = c.colLeft - (_columnWidths[c.table] ?? []).prefix(c.column).reduce(0, +)
                // A cell whose own fill is fully transparent says "no fill"
                // (PowerPoint's `a:noFill` on a cell of a banded table): the
                // row's shading stops at its edges rather than showing through.
                var holes: [(Double, Double)] = []
                var j = i
                while j < count, j < document.paragraphs.count, let cj = _cells[j], cj.table == c.table, cj.row == c.row {
                    if let own = document.paragraphs[j].cell?.fill, own.alpha == 0 {
                        holes.append((cj.colLeft, cj.colLeft + cj.colWidth))
                    }
                    j += 1
                }
                // Nor over a cell from a row above that spans down into
                // this one with a fill of its own: drawn first, it was
                // covered by this row's band (tdf149785's "Key Functions",
                // a header cell two rows tall).
                var k = i - 1
                // (Back fifty rows at most: a long table stays linear.)
                while k >= 0, let ck = _cells[k], ck.table == c.table, ck.row >= c.row - 50 {
                    if ck.rowSpan > 1, ck.row < c.row, ck.row + ck.rowSpan > c.row,
                       let own = document.paragraphs[k].cell?.fill, own.alpha > 0 {
                        holes.append((ck.colLeft, ck.colLeft + ck.colWidth))
                    }
                    k -= 1
                }
                holes.sort { $0.0 < $1.0 }
                if holes.isEmpty {
                    canvas.drawRect(Rect.fromLTWH(left.rounded(), c.rowTop.rounded(), width.rounded(), c.ownRowHeight.rounded()), fill)
                }
                var from = left
                for (l, r) in holes.isEmpty ? [] : holes + [(left + width, left + width)] {
                    if l > from {
                        canvas.drawRect(Rect.fromLTRB(from.rounded(), c.rowTop.rounded(), l.rounded(),
                                                      (c.rowTop + c.ownRowHeight).rounded()), fill)
                    }
                    from = max(from, r)
                }
            }
        }
        // The cell's own shading, over the row's; every paragraph of the
        // cell paints it (the same rectangle, so no seam).
        // (For a row that parts over two pages, all its cells' with the
        // rules; its members' own pieces are their text alone.)
        var members = part == .text ? i ..< i : i ..< i + 1
        if part == .rules, let c = _cells[i] {
            var j = i
            while j < count, j < document.paragraphs.count, let d = _cells[j], d.table == c.table, d.row == c.row { j += 1 }
            members = i ..< j
        }
        for k in members {
            guard let c = _cells[k], let color = document.paragraphs[k].cell?.fill else { continue }
            let fill = Paint()
            fill.style = .fill
            fill.color = color
            let height = c.rowSpan > 1 ? c.rowHeight : c.ownRowHeight
            canvas.drawRect(Rect.fromLTWH(c.colLeft.rounded(), c.rowTop.rounded(), c.colWidth.rounded(), height.rounded()), fill)
        }
    }

    /// `theme.baselineShift` for paragraph `i`, in pixels of its first
    /// run's size.
    /// How far each line of paragraph `i` is moved (`cellLineShift`), in
    /// layout pixels; empty for a paragraph outside a table, a turned
    /// cell's, or where the theme moves none.
    func _cellLineShifts(_ i: Int, _ g: ParagraphGeometry, _ document: RichDocument) -> [Double] {
        guard let shift = theme.cellLineShift, i < _cells.count, let c = _cells[i], c.direction == .horizontal else { return [] }
        var k = i
        while k > 0, let d = _cells[k - 1], d.table == c.table, d.row == c.row, d.column == c.column { k -= 1 }
        let top = geometry(k).textTop, at = g.inkTop + _baselineShift(i, document), pt = _px(1)
        guard pt > 0 else { return [] }
        return g.painter.computeLineMetrics().map { shift((at + $0.baseline - top) / pt) * pt }
    }

    /// `painter` drawn at `at` line by line, each moved by its shift and
    /// cut to a band from a quarter of the way past the line above's
    /// baseline to the same past its own (a line outside its band is
    /// left out whole, not drawn under the cut).
    func _paintShiftedLines(_ painter: TextPainter, at: Offset, _ shifts: [Double], _ canvas: any Canvas) {
        let lines = painter.computeLineMetrics()
        for (k, m) in lines.enumerated() where k < shifts.count {
            let y = at.dy + m.baseline
            let above = k == 0 ? -1_000_000 : y - (m.baseline - lines[k - 1].baseline) * 3 / 4
            let below = k == lines.count - 1 ? 1_000_000 : y + (lines[k + 1].baseline - m.baseline) / 4
            canvas.save()
            canvas.clipRect(Rect.fromLTRB(-1_000_000, above + shifts[k], 1_000_000, below + shifts[k]))
            canvas.translate(0, shifts[k])
            painter.paint(canvas, at)
            canvas.restore()
        }
    }

    /// Restore a fixed frame's overflowing indent without moving ink from
    /// a later line. Tight lines can overlap: separate text passes, rather
    /// than clipping the whole paragraph into horizontal bands.
    func _paintFixedBoxFirstLine(_ i: Int, _ painter: TextPainter, at: Offset,
                                         _ shifts: [Double], _ canvas: any Canvas) -> Bool {
        guard i < _boxFirstLineShift.count, _boxFirstLineShift[i] > 0,
              let frame = _fixedTextFrame else { return false }
        let length = painter.plainText.utf16.count
        let end = painter.getLineBoundary(TextPosition(offset: 0)).end
        guard end > 0, end <= length else { return false }
        var first = painter
        var rest: TextPainter?
        if end < length {
            // Keys 0/1 belong to scaled runs. These masks use the same
            // line boundary for the lifetime of this immutable painter.
            guard let onlyFirst = _clearedPainter(painter, [end..<length], key: 2,
                                                  clearBackgroundAndDecoration: true),
                  let onlyRest = _clearedPainter(painter, [0..<end], key: 3,
                                                 clearBackgroundAndDecoration: true) else { return false }
            first = onlyFirst
            rest = onlyRest
        }
        canvas.save()
        // (A turned box is not clipped: zh-b24b396a's "30" labels have the
        // "3" at the indent, past the box's 7.8pt, in the text of Word's
        // print, as the box's own paint does not clip.)
        if !_turnedBox {
            canvas.clipRect(Rect.fromLTRB(frame.left, -1_000_000, frame.right, 1_000_000),
                            clipOp: .intersect, doAntiAlias: false)
        }
        canvas.translate(_boxFirstLineShift[i], shifts.first ?? 0)
        first.paint(canvas, at)
        canvas.restore()
        if let rest {
            if shifts.isEmpty { rest.paint(canvas, at) }
            else { _paintShiftedLines(rest, at: at, shifts, canvas) }
        }
        return true
    }

    /// Where paragraph `i`'s painter is drawn from, down the layout: its
    /// ink top moved by its face's baseline share. (Slides set each line
    /// on PowerPoint's whole points from it.)
    public func drawnTextTop(_ i: Int, _ document: RichDocument) -> Double {
        geometry(i).inkTop + _baselineShift(i, document)
    }

    func _baselineShift(_ i: Int, _ document: RichDocument) -> Double {
        guard theme.singleLineHeight != nil else { return 0 }
        let p = document.paragraphs[i]
        guard let run = p.runs.first else { return 0 }
        if let points = p.style.lineHeightPoints, !p.style.lineHeightIsMinimum, let share = theme.exactLineDescentShare {
            // A line of so many points has its baseline a fixed share of
            // it down, whatever the face: the engine's own sets it by the
            // drawn face's share.
            let name = run.style.fontFamily ?? theme.fontFamily
            let family = name.map { theme.fontFamilyResolver?($0) ?? $0 }
            let drawn = theme.descentShare(family: family, bold: run.style.bold, italic: run.style.italic)
            var below = share
            if let least = theme.exactLineDescentOfSize, points > 0 {
                var size = run.style.fontSize ?? document.styles.resolve(p.style)?.char.fontSize
                    ?? document.styles[RichNamedStyle.normalId]?.char.fontSize ?? theme.fontSize
                if fontScale != 1 { size = max(1, (size * fontScale).rounded()) }
                below = max(share, least * size / points)
                // (PowerPoint for Windows, lab p3ls: up to single's height the
                // line keeps its natural depth below the baseline, so the
                // whole of the spacing lies above; over single it takes
                // 0.255 of the extra and 0.072 of the size besides below, the
                // first baseline never nearer than 0.755 of the size to the
                // line's top. Whatever the size and the face.)
                if let natural = theme.singleLineHeight, theme.exactLinesAsPowerPoint {
                    let single = natural * size
                    let depth = drawn * single
                    var foot = depth
                    if points > single { foot += 0.072 * size + 0.255 * (points - single) }
                    foot = min(foot, points + depth - 0.755 * size) - 0.012 * size
                    return _px(points * drawn - foot)
                }
            }
            return _px(points * (drawn - below))
        }
        let k = theme.baselineShift(for: run.style, in: p.style, depth: _mixedFace[i]?.depth)
        guard k != 0 else { return 0 }
        if let mixed = _mixedFace[i] { return k * _px(mixed.size) }
        var size = run.style.fontSize ?? document.styles.resolve(p.style)?.char.fontSize
            ?? document.styles[RichNamedStyle.normalId]?.char.fontSize ?? theme.fontSize
        if fontScale != 1 { size = max(1, (size * fontScale).rounded()) }
        return k * _px(size)
    }

    /// Slides: how much of the last line's foot, over single's, does not count toward the text's height. PowerPoint
    /// (lab verdana-ls, Verdana and Calibri at 18-40 pt, 110%): a line over single has its extra above it, and the
    /// text of a centred or bottom-anchored box stands as if the last line's foot were the single line's own, so
    /// the foot `baselineShift` models is dropped back to the natural depth. In pixels; 0 elsewhere.
    public func trailingExtra(_ document: RichDocument) -> Double {
        guard theme.exactLinesAsPowerPoint, let single = theme.singleLineHeight else { return 0 }
        guard let i = document.paragraphs.lastIndex(where: { !$0.runs.isEmpty }) else { return 0 }
        let p = document.paragraphs[i]
        guard p.style.lineHeightPoints == nil, let run = p.runs.last else { return 0 }
        let multiple = max(0.1, p.style.lineSpacing - theme.lineSpacingReduction)
        guard multiple > 1 else { return 0 }
        let name = run.style.fontFamily ?? theme.fontFamily
        let family = name.map { theme.fontFamilyResolver?($0) ?? $0 }
        let drawn = theme.descentShare(family: family, bold: run.style.bold, italic: run.style.italic)
        let depth = _mixedFace[i]?.depth ?? name.flatMap { theme.ownDescentShare?($0) } ?? drawn
        let natural = single * depth
        let foot = 0.25 * (multiple * single) + max(0.013 - 0.07 * depth, natural - 0.25 * single)
        guard foot > natural else { return 0 }
        var size = run.style.fontSize ?? document.styles.resolve(p.style)?.char.fontSize
            ?? document.styles[RichNamedStyle.normalId]?.char.fontSize ?? theme.fontSize
        if fontScale != 1 { size = max(1, (size * fontScale).rounded()) }
        if let mixed = _mixedFace[i], mixed.size > 0 { size = mixed.size }
        return (foot - natural) * _px(size)
    }

    /// The lines of paragraph `piece.paragraph` that `piece` holds, as a
    /// painter of their own, where they stand below the paragraph's first
    /// line, and whether they begin it — or nil when the piece is the
    /// whole paragraph (or the paragraph is one this does not take
    /// apart: a table cell's, one with a picture in it).
    ///
    /// For PowerPoint's columns. A piece is otherwise the whole paragraph
    /// seen through a window, which is exact while lines keep to their
    /// boxes; at a spacing under single they do not — the next line's
    /// ascenders stand in the last line's box, and showed as a row of
    /// specks under the foot of a column.
    func _linesPainter(_ piece: PagePiece, _ document: RichDocument)
        -> (painter: TextPainter, top: Double, first: Bool, paragraph: RichParagraph)? {
        let i = piece.paragraph
        guard theme.singleLineHeight != nil, _cells[i] == nil, i >= _inline.count || _inline[i].isEmpty else { return nil }
        let g = geometry(i)
        let p = document.paragraphs[i]
        let from = piece.flowTop - g.textTop, to = piece.flowBottom - g.textTop
        let whole = g.painter.height
        guard from > 0.5 || to < whole - 0.5, !p.text.isEmpty else { return nil }
        let start = from <= 0.5 ? 0 : g.painter.getLineBoundary(g.painter.getPositionForOffset(Offset(1, from + 1))).start
        let end = to >= whole - 0.5 ? p.length : g.painter.getLineBoundary(g.painter.getPositionForOffset(Offset(1, to - 1))).end
        guard end > start else { return nil }
        var head = p
        _ = head.split(at: min(end, p.length))
        let lines = start > 0 ? head.split(at: start) : head
        let (span, inline, inserts) = _span(for: lines, at: nil, document, textWidth: g.textWidth)
        // (Only where the painter's text is the paragraph's own, offset
        // for offset: nothing put in for Word's line rules.)
        guard inline.isEmpty, inserts.isEmpty else { return nil }
        var align = Self._textAlign(p.style.alignment)
        if p.style.rightToLeft {
            switch p.style.alignment {
            case .left: align = .right
            case .right: align = .left
            default: break
            }
        }
        let painter = TextPainter(text: span, textAlign: align, textDirection: p.style.rightToLeft ? .rtl : .ltr)
        painter.fractionalLineHeights = g.painter.fractionalLineHeights
        painter.layout(minWidth: g.textWidth, maxWidth: g.textWidth)
        let top = start == 0 ? 0 : g.painter.getOffsetForCaret(TextPosition(offset: start), Rect.zero).dy
        return (painter, top, start == 0, lines)
    }

    /// The raised and lowered runs of `p`, drawn where they belong: each
    /// stretch of one on a line again in its own style, up by three
    /// tenths of the size it was shrunk from, or down by a fifth —
    /// PowerPoint's and Word's superscript and subscript. `painter` is
    /// the paragraph's (or its lines'), painted at `origin`, in which the
    /// runs hold their place unseen.
    /// `leading`: only the stretches that open their line (true), or
    /// only the others (false). Those that open a line are drawn before
    /// it, so a PDF holds them in reading order: Word's print of a note
    /// reads "i Endnote" and ours read "Endnote i" (endnotes,
    /// Bug54849), the mark drawn after its line.
    func _paintScripts(_ p: RichParagraph, _ painter: TextPainter, at origin: Offset,
                               _ canvas: any Canvas, _ document: RichDocument, map: _OffsetMap? = nil, leading: Bool? = nil) {
        guard p.runs.contains(where: { $0.style.script != .normal }) else { return }
        // (Drawn in their line already, shifted: `textStyle`.)
        if theme.wordRules, NativeParagraphBuilder.supportsBaselineShift { return }
        let named = document.styles.resolve(p.style)
        let units = Array(p.text.utf16)
        var pos = 0
        for run in p.runs {
            let from = pos, to = min(units.count, pos + run.length)
            pos += run.length
            guard run.style.script != .normal, to > from else { continue }
            let style = theme.textStyle(for: run.style, in: p.style, named: named, normal: document.styles[RichNamedStyle.normalId]?.char, scale: scale, fontScale: fontScale)
            // The size it was shrunk from (the style's is 65% of it).
            var plain = run.style
            plain.script = .normal
            let full = theme.scriptSizeWholeUp || RichTextTheme.wordWindowsPages
                ? theme.textStyle(for: plain, in: p.style, named: named, normal: document.styles[RichNamedStyle.normalId]?.char, scale: scale, fontScale: fontScale).fontSize ?? 0
                : (style.fontSize ?? 0) / 0.65
            // (Measured on PowerPoint's page: 7.0 pt up and 5.0 down at 24 pt.
            // Word raises one further: 3.6pt over 10pt text and 4.08 over
            // 11 and 12pt in its prints — every note mark of endnotes,
            // footnotes, bug65649 and three more, Calibri and Times alike
            // — 0.355 of the size within its 0.24pt raster, where 0.3 set
            // them 0.6pt low.)
            let ratio = full > 0 ? (style.fontSize ?? 0) / full : 0.65
            let up = theme.wordRules ? (ratio < 0.6 ? 1 - ratio : 0.355) : 0.3
            let dy = run.style.script == .superscript ? -up * full : 0.2 * full
            var a = from
            while a < to {
                // To the end of the run or of its line, whichever is first.
                // (The painter's offsets are the paragraph's but for what
                // the layout put in: `map`.)
                let line = painter.getLineBoundary(TextPosition(offset: map?.painter(a) ?? a))
                let b = max(a + 1, min(to, map?.paragraph(line.end) ?? line.end))
                if let leading {
                    // (Opening its line: nothing but spaces before it there.)
                    let lineStart = map?.paragraph(line.start) ?? line.start
                    let opens = (lineStart ..< a).allSatisfy { $0 < units.count && (units[$0] == 0x20 || units[$0] == 0x09) }
                    if opens != leading { a = b; continue }
                }
                let boxes = painter.getBoxesForSelection(TextSelection(baseOffset: map?.painter(a) ?? a,
                                                                       extentOffset: (map?.painter(b - 1) ?? b - 1) + 1))
                if let box = boxes.first {
                    let text = String(decoding: units[a ..< b], as: UTF16.self)
                    // At the face's own height, as the box it stood in unseen
                    // is: the two then share a baseline.
                    // (Its shadow with it: the one held in the line casts none.)
                    var shown = run.style
                    shown.script = .normal
                    let shadows = theme.textStyle(for: shown, in: p.style, named: named,
                                                  normal: document.styles[RichNamedStyle.normalId]?.char,
                                                  scale: scale, fontScale: fontScale).shadows
                    let plain = TextStyle(color: style.color, fontSize: style.fontSize, fontWeight: style.fontWeight,
                                          fontStyle: style.fontStyle, letterSpacing: style.letterSpacing,
                                          shadows: shadows,
                                          fontFeatures: style.fontFeatures, decoration: style.decoration,
                                          decorationColor: style.decorationColor, fontFamily: style.fontFamily,
                                          fontFamilyFallback: style.fontFamilyFallback)
                    let tp = TextPainter(text: TextSpan(text: text, style: plain), textDirection: p.style.rightToLeft ? .rtl : .ltr)
                    tp.layout(minWidth: 0, maxWidth: Double.infinity)
                    tp.paint(canvas, Offset(origin.dx + box.toRect().left, origin.dy + box.toRect().top + dy))
                    tp.dispose()
                }
                a = b
            }
        }
    }

    /// The order a paragraph's anchored objects are painted in: Word stacks them by
    /// wp:anchor relativeHeight, not by where they stand in the text (2263e221: a group
    /// written after a white box, but with the higher relativeHeight, stands over it).
    /// Inline items and objects without a height keep their places.
    @inline(never)
    func _floatPaintOrder(_ i: Int) -> [Int] {
        let items = _inline[i]
        let all = Array(items.indices)
        guard theme.wordRules, RichTextTheme.wordWindowsPages, items.count > 1 else { return all }
        var slots: [Int] = [], heights: [Int: Int64] = [:]
        for k in all {
            guard items[k].float != nil, let xml = items[k].sourceXML,
                  let r = xml.rangeOfSubstring("relativeHeight=\"") else { continue }
            var n: Int64 = 0, any = false
            for c in xml[r.upperBound...] {
                guard let d = c.wholeNumberValue, c.isASCII else { break }
                n = n * 10 + Int64(d); any = true
            }
            if any { slots.append(k); heights[k] = n }
        }
        guard slots.count > 1 else { return all }
        let sorted = slots.sorted { (heights[$0] ?? 0, $0) < (heights[$1] ?? 0, $1) }
        var out = all
        for (slot, k) in zip(slots, sorted) { out[slot] = k }
        return out
    }

    /// A paragraph's drop caps alone, painted in the pass after the page's body.
    func _paintDropCaps(_ i: Int, _ canvas: any Canvas, _ document: RichDocument) {
        guard i < _inline.count, !_inline[i].isEmpty, let all = geometry(i).painter.inlinePlaceholderBoxes else { return }
        let g = geometry(i)
        for k in _inline[i].indices where _inline[i][k].isDropCap {
            let slot = _inlineBoxes[i][k]
            guard slot < all.count else { continue }
            let image = _inline[i][k]
            var rect = all[slot].toRect().shift(Offset(g.textLeft, g.inkTop))
            if let float = image.float, !float.takesRoom { rect = _floatRect(float, image, g, i) }
            else if image.float == nil { continue }
            if _decoded[image.id] != nil { continue }
            _paintOutline(image, rect, canvas)
            if let inside = _textBox(image, document), let text = image.textBox {
                _paintTurnedTextBox(inside, text, image, rect, canvas)
            }
        }
    }

    /// Word for Windows draws the rule under a table cell's closing underlined
    /// spaces, up to the cell's right edge (zh-e61c3dff's form row, "联系方式"
    /// and eight of them: 337-379 in its print; zh-77bd4900's "□其他" and
    /// twelve: 661-709, the rest hanging past the edge unseen). The engine
    /// hangs spaces that end a line and drops their decoration, and making them
    /// take room moved lines in a dozen documents, so the rule is drawn here
    /// over the spaces the line leaves where they are: whole spaces that fit.
    func _paintClosingUnderline(_ i: Int, _ g: ParagraphGeometry, at textAt: Offset, _ canvas: any Canvas, _ document: RichDocument) {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, i < document.paragraphs.count else { return }
        let p = document.paragraphs[i]
        guard p.cell != nil, p.style.alignment == .left, p.text.hasSuffix(" "), p.runs.last?.style.underline == true else { return }
        let units = Array(p.text.utf16)
        var closing = units.count
        while closing > 0, units[closing - 1] == 0x20 { closing -= 1 }
        guard closing > 0 else { return }
        func leafStyle(_ span: InlineSpan, _ inherited: TextStyle?) -> TextStyle? {
            guard let text = span as? TextSpan else { return inherited }
            let own = text.style ?? inherited
            if let children = text.children, let last = children.last { return leafStyle(last, own) }
            return own
        }
        guard let root = g.painter.text, let style = leafStyle(root, nil), style.decoration?.contains(.underline) == true else { return }
        let before = _map(i).painter(closing - 1)
        guard let box = g.painter.getBoxesForSelection(TextSelection(baseOffset: before, extentOffset: before + 1), boxHeightStyle: .max).last else { return }
        let one = TextPainter(text: TextSpan(text: " ", style: style), textDirection: .ltr)
        one.layout(minWidth: 0, maxWidth: 10_000)
        let spaceWidth = one.width
        one.dispose()
        guard spaceWidth > 0.1 else { return }
        let n = min(units.count - closing, Int(((g.textWidth - box.right) / spaceWidth).rounded(.down)))
        guard n > 0 else { return }
        let rule = TextPainter(text: TextSpan(text: String(repeating: " ", count: n) + "\u{2060}", style: style),
                               textDirection: .ltr, strutStyle: g.painter.strutStyle)
        rule.layout(minWidth: 0, maxWidth: 10_000_000)
        rule.paint(canvas, Offset(textAt.dx + box.right, textAt.dy + box.top))
        rule.dispose()
    }

    /// A Symbol-font bullet drawn as "•" by a stand-in: the glyph itself, scaled and moved at paint time (nothing of the
    /// advance or the line changes) so its dot is Symbol's. Word's prints (dx2, 600 bullets at 9 to 14 pt): a round dot
    /// 0.355 em across, its foot 0.099 em above the baseline, its left edge 0.052 em in. The stand-ins': Liberation Sans
    /// 0.271 across, foot 0.188, left 0.042; Liberation Serif 0.240, 0.204, 0.062; Carlito's (Calibri's) is already Word's.
    @inline(never)
    func _paintMarker(_ marker: TextPainter, _ at: Offset, _ p: RichParagraph, _ document: RichDocument, label: String, _ canvas: any Canvas) {
        guard theme.wordRules, label == "\u{2022}" || label == "\u{F0B7}", _levelNumberFonts(p, document).latin?.lowercased() == "symbol",
              let top = marker.text as? TextSpan, let style = top.style ?? (top.children?.first as? TextSpan)?.style, let fs = style.fontSize, fs > 0, let family = style.fontFamily?.lowercased() else {
            marker.paint(canvas, at); return
        }
        guard family.containsSubstring("liberation") else { marker.paint(canvas, at); return }
        RuleTrace.hit("word-symbol-bullet-dot-drawn-in-calibri-shape")
        let dot = TextPainter(text: TextSpan(text: top.text ?? label, style: style.copyWith(fontFamily: "Carlito")), textAlign: .left, textDirection: .ltr, strutStyle: marker.strutStyle)
        dot.layout()
        let down = marker.computeDistanceToActualBaseline(.alphabetic) - dot.computeDistanceToActualBaseline(.alphabetic)
        dot.paint(canvas, Offset(at.dx, at.dy + down))
    }

    func _paintParagraph(_ i: Int, _ canvas: any Canvas, _ document: RichDocument, part: PagePiece.Part = .all,
                                 lines: (painter: TextPainter, top: Double, first: Bool, paragraph: RichParagraph)? = nil) {
        let g = geometry(i)
        if let lines, !lines.first {
            // Lines from inside the paragraph: no marker, no rules — the text alone.
            let at = Offset(g.textLeft, g.textTop + lines.top + _baselineShift(i, document))
            _paintScripts(lines.paragraph, lines.painter, at: at, canvas, document, leading: true)
            lines.painter.paint(canvas, at)
            _paintScripts(lines.paragraph, lines.painter, at: at, canvas, document, leading: false)
            _paintRuby(lines.paragraph, lines.painter, at: at, canvas, document, index: i)
            _paintEmphasis(lines.paragraph, lines.painter, at: at, canvas, document, index: i)
            return
        }
        if part != .text, let c = _cells[i], c.firstInRow {
            // The table's switch, refined by its own sides and by each
            // cell's: a side a cell states wins, then the table's side
            // for that position (outer or inside), then the switch.
            let ts = document.tableStyles[c.table]
            let tableOn = (ts?.borders ?? true) && !(theme.wordRules && ts?.bordersFromCells == true)
            let te = ts?.edges
            func on(_ cell: Bool?, _ table: Bool?) -> Bool { cell ?? table ?? tableOn }
            let stroke = Paint()
            stroke.style = .stroke
            stroke.strokeWidth = max(1, _px(ts?.borderWidth ?? 0.5).rounded())
            // (Outset rules with the colour left "auto" are grey in Word's print — 9F9F9F, one
            // 0.75pt line between rows — bib-chernigovka's tables; black here was most of its diff.)
            let outsetGrey = theme.wordRules && RichTextTheme.wordWindowsPages && ts?.borderColor == nil && ts?.borderStyle == "outset"
            stroke.color = ts?.borderColor ?? (outsetGrey ? Color(0xFF9F9F9F) : theme.wordRules && RichTextTheme.wordWindowsPages ? Color(0xFF000000) : theme.textColor.withOpacity(0.6))
            // Every line lies inside the row (the paint is clipped to the
            // row's page piece, so a stroke centred on the row's bottom
            // edge lost its outer half and the table's last row had no
            // bottom border). Rows share edges: a row draws its bottom and
            // only the first row its top; columns draw their left and only
            // the last its right. A cell's own edge lines (the file's
            // lnL…lnB) replace the style's rule on that edge: drawn at
            // their width and colour, or not at all.
            let widths = _columnWidths[c.table] ?? []
            let rowTop = c.rowTop.rounded()
            let rowBottom = (c.rowTop + c.ownRowHeight).rounded()
            let tableLeft = (c.colLeft - widths.prefix(c.column).reduce(0, +)).rounded()
            let right = (tableLeft + widths.reduce(0, +)).rounded()
            // Is this the table's last row? (Its bottom is then the outer
            // bottom side, not an inside one.)
            var probe = i
            while probe < _cells.count, let d = _cells[probe], d.table == c.table, d.row == c.row { probe += 1 }
            let lastRow = !(probe < _cells.count && _cells[probe]?.table == c.table)
            // A cell's own line on an edge (the file's lnL…lnB, with its
            // own width and colour) replaces the rule there: drawn centred
            // on the edge, or not at all for a hidden one.
            // (The table's line on that side at its own width: lab `ef2b`
            // (Word 16 Mac), a 2.25pt bottom under 0.5pt sides and inside
            // lines, drawn 0.5 where Word's print has the heavy line.)
            func line(_ own: CellRef.CellLine?, _ ruled: Bool, _ from: Offset, _ to: Offset, inward: Offset, side: String, cell: CellRef? = nil, cellSide: String = "") {
                if let own {
                    guard let color = own.color, own.width > 0 else { return }
                    let p = Paint()
                    p.style = .stroke
                    p.strokeWidth = max(1, _px(own.width))
                    p.color = color
                    var from = from, to = to
                    var clipBottom = rowBottom
                    if theme.wordRules, RichTextTheme.wordWindowsPages, abs(from.dy - to.dy) < 0.01 {
                        // (A cell's own line is the same box as the table's: 0.96 of its width, a horizontal
                        // one hanging below the edge, a vertical one centred.)
                        RuleTrace.hit("word-table-rule-is-a-box-0.96-wide-hanging-below-a-horizontal-edge")
                        from = Offset(from.dx, from.dy + p.strokeWidth / 2)
                        to = Offset(to.dx, to.dy + p.strokeWidth / 2)
                        clipBottom += p.strokeWidth
                    }
                    if theme.wordRules, RichTextTheme.wordWindowsPages { p.strokeWidth *= 0.96 }
                    canvas.save()
                    canvas.clipRect(Rect.fromLTRB(-1e6, rowTop, 1e6, clipBottom))
                    if theme.cellLinesPastCorners, (to - from).distance > 0 {
                        let along = (to - from) * (p.strokeWidth / 2 / (to - from).distance)
                        from = from - along
                        to = to + along
                    }
                    if let dash = own.dash, dash.count >= 2 {
                        // Dashed along the edge, from its start.
                        let length = (to - from).distance
                        let pieces = dash.map { max(0.5, $0 * p.strokeWidth) }
                        var at = 0.0, k = 0
                        while at < length {
                            let end = min(length, at + pieces[k % pieces.count])
                            if k % 2 == 0 { canvas.drawLine(from + (to - from) * (at / length), from + (to - from) * (end / length), p) }
                            at = end
                            k += 1
                        }
                    } else {
                        canvas.drawLine(from, to, p)
                    }
                    canvas.restore()
                } else if ruled {
                    // (A double, or thin-and-thick, rule — the cell's own side over the table's — as its lines:
                    // zh-e51c31a7's 1.5pt double cell sides are two 1.5pt lines in Word's print, one 0.5pt here.)
                    var cellWidth: Double? = nil
                    if theme.wordRules, RichTextTheme.wordWindowsPages, !cellSide.isEmpty {
                        let said = cell.flatMap { Self._cellSide($0.bordersXML, cellSide) ?? Self._cellSide($0.rowBordersXML, cellSide) }
                        let style = said?.style ?? ts?.edgeStyles[side] ?? ts?.borderStyle
                        let width = said?.width ?? ts?.edgeWidths[side] ?? ts?.borderWidth ?? 0.5
                        let parts = Self._ruleLines(style, width)
                        if parts.count > 1, said != nil || ts?.edgeStyles[side] != nil || ts?.borderStyle != nil, side != "insideH", side != "insideV" {
                            RuleTrace.hit("word-table-compound-rule-is-drawn-as-its-lines")
                            let room = _px(Self._ruleRoom(style, width))
                            let centred = side == "insideH" || side == "insideV"
                            let cp = Paint()
                            cp.style = .stroke
                            cp.color = stroke.color
                            canvas.save()
                            canvas.clipRect(Rect.fromLTRB(-1e6, rowTop - (centred ? room : 0), 1e6, rowBottom + (centred ? room : 0)))
                            // (A rule between two cells is one band both cells draw alike: the first part
                            // above or left, the next below or right — zh-8f70b676's thick-and-thin
                            // separators, the thick line over the thin one in Word's print.)
                            let sign: Double = inward.dx + inward.dy > 0 ? 1 : -1
                            // (Each line a box 0.96 of its width, the gaps 0.96 too, from the same outer edge:
                            // zh-e2dc9dce p25's 1.5pt double is 1.44 + 1.44 gap + 1.44 in Word's print.)
                            for part in parts {
                                cp.strokeWidth = _px(part.width) * 0.96
                                // (The lines run from the text outward, so from the table's outer edge inward the first is the farthest:
                                // zh-20c1d74a p28's thickThin bottom is the thin line over the thick one in Word's print.)
                                let dist = centred ? sign * (-room + _px(part.at) * 0.96 + cp.strokeWidth / 2) : room * 0.96 - _px(part.at) * 0.96 - cp.strokeWidth / 2
                                canvas.drawLine(from + inward * dist, to + inward * dist, cp)
                            }
                            canvas.restore()
                            return
                        }
                        // (A single rule the cell states thicker than the table's is that thick: zh-fec5fa30's calendar
                        // cells say 2.25pt, "auto", under a table of 0.5pt, and Word's print has the heavy line.)
                        if let said, said.style == "single", _px(said.width).rounded() > (ts?.edgeWidths[side].map { max(1, _px($0).rounded()) } ?? stroke.strokeWidth) {
                            RuleTrace.hit("word-table-cell-rule-states-its-own-width")
                            cellWidth = max(1, _px(said.width).rounded())
                        }
                    }
                    let p = Paint()
                    p.style = .stroke
                    p.strokeWidth = cellWidth ?? ts?.edgeWidths[side].map { max(1, _px($0).rounded()) } ?? stroke.strokeWidth
                    p.color = stroke.color
                    // (The table's top and bottom lines wholly inside the room
                    // its first and last rows keep for them, as Word draws
                    // them: `ef2b`'s 2.25pt bottom at 782.40-784.56 in Word's
                    // print, under a row ending at 784.55 — centred on the
                    // edge, its lower half was cut off with the row; and
                    // zh-77bd4900's p3 tables open under a 2.16pt line at
                    // 68.64, ours at 67.6.)
                    var into = theme.wordRules && (side == "bottom" || side == "top") ? max(0.5, p.strokeWidth / 2) : 0.5
                    // (As a box: a heavy top line's top on the edge, a heavy bottom line's bottom on it, and one
                    // between rows with its top on the edge. zh-77bd4900 p3's 2.25pt lines: boxes' tops at 68.64,
                    // 104.78, 124.94, 161.06 under edges 68.7, 104.8, 125.0, 161.1.)
                    let heavyBox = theme.wordRules && RichTextTheme.wordWindowsPages && p.strokeWidth >= _px(2) && p.strokeWidth < _px(5)
                    if heavyBox, side == "top" { into = 0 }
                    if heavyBox, side == "bottom" { into = p.strokeWidth * 0.96 }
                    if heavyBox, side == "insideH", inward.dy < 0 {
                        RuleTrace.hit("word-heavy-inside-rule-is-a-box-hanging-below-the-row-edge")
                        canvas.save()
                        canvas.clipRect(Rect.fromLTRB(-1e6, rowTop, 1e6, rowBottom + p.strokeWidth))
                        let q = Offset(0, p.strokeWidth / 2)
                        p.strokeWidth *= 0.96
                        canvas.drawLine(from + q, to + q, p)
                        canvas.restore()
                        return
                    }
                    if theme.wordRules, RichTextTheme.wordWindowsPages, side == "insideH", inward.dy < 0, p.strokeWidth >= _px(2) {
                        // (A heavy rule between two rows is one band centred on their edge, half in each:
                        // lo-5b86b731's 6pt inside rules, 3pt of each under the clip to the row above.)
                        RuleTrace.hit("word-heavy-inside-rule-is-centred-on-the-row-edge")
                        canvas.save()
                        canvas.clipRect(Rect.fromLTRB(-1e6, rowTop, 1e6, rowBottom + p.strokeWidth / 2))
                        canvas.drawLine(from, to, p)
                        canvas.restore()
                        return
                    }
                    var a = from + inward * into, b = to + inward * into
                    if theme.wordRules, RichTextTheme.wordWindowsPages {
                        // (Word's print draws a table rule as a filled box 0.96 of its width: a vertical one
                        // centred on the edge, a horizontal one hanging below it. Measured on zh-ab9cbe66,
                        // zh-5251dd23, zh-e2dc9dce, zh-37b6536f: width 0.48/0.72/0.96/1.44/2.16 for
                        // 0.5/0.75/1/1.5/2.25, a horizontal box's top on our centre line.)
                        RuleTrace.hit("word-table-rule-is-a-box-0.96-wide-hanging-below-a-horizontal-edge")
                        if abs(a.dy - b.dy) < 0.01 {
                            a = Offset(a.dx, a.dy + p.strokeWidth / 2)
                            b = Offset(b.dx, b.dy + p.strokeWidth / 2)
                        }
                        p.strokeWidth *= 0.96
                    }
                    canvas.drawLine(a, b, p)
                }
            }
            // Whether the cell of this row whose left side stands at `x`
            // draws it.
            func leftDrawn(at x: Double) -> Bool {
                var n = i
                while n < _cells.count, let e = _cells[n], e.table == c.table, e.row == c.row {
                    if abs(e.colLeft.rounded() - x) < 1 { return on(e.edges?.left, te?.insideV) }
                    n += 1
                }
                return false
            }
            // A double or thin-and-thick rule a cell states on its top (or
            // its row's does): between two rows it is one band, laid wholly
            // below the row's top — the heavy line first, the thin one under
            // it — as the table's own top edge is. zh-8f70b676's group
            // separators: 138.9-141.0 and 141.7-142.5 under a row ending at
            // 138.8, in Word's print; one 0.75pt line here.
            func bandTop(_ ref: CellRef?) -> (style: String, width: Double)? {
                guard theme.wordRules, RichTextTheme.wordWindowsPages, let ref,
                      let said = Self._cellSide(ref.bordersXML, "top") ?? Self._cellSide(ref.rowBordersXML, "top"),
                      Self._ruleLines(said.style, said.width).count > 1 else { return nil }
                return said
            }
            // (The same for the bottom the row above states: where both rows
            // state a compound rule, Word draws the upper row's, its lines
            // from the text outward — zh-20c1d74a p28's thickThin bottom over
            // a thinThick top is a thin line, then the thick one.)
            func bandBottom(_ ref: CellRef?) -> (style: String, width: Double)? {
                guard theme.wordRules, RichTextTheme.wordWindowsPages, let ref,
                      let said = Self._cellSide(ref.bordersXML, "bottom") ?? Self._cellSide(ref.rowBordersXML, "bottom"),
                      Self._ruleLines(said.style, said.width).count > 1 else { return nil }
                return said
            }
            func bandAbove(_ d: _CellGeo) -> (style: String, width: Double)? {
                var q = i - 1
                while q >= 0, let e = _cells[q], e.table == c.table, e.row >= c.row - 1 {
                    if e.row == c.row - 1, e.colLeft < d.colLeft + d.colWidth - 1, d.colLeft < e.colLeft + e.colWidth - 1,
                       let b = bandBottom(document.paragraphs[q].cell) { return b }
                    q -= 1
                }
                return nil
            }
            func paintEdges(_ d: _CellGeo, ref: CellRef?, bottomHere: Bool, ownTop: Bool) {
                let cellRight = (d.colLeft + d.colWidth).rounded()
                var bandBelow = false
                if bottomHere, !lastRow {
                    var q = probe
                    while q < _cells.count, let e = _cells[q], e.table == c.table, e.row == c.row + 1 {
                        if e.column == d.column, bandTop(document.paragraphs[q].cell) != nil || bandBottom(ref) != nil { bandBelow = true }
                        q += 1
                    }
                }
                if c.row > 0, d.row == c.row, let band = bandAbove(d) ?? bandTop(ref) {
                    RuleTrace.hit("word-table-compound-rule-between-rows-is-one-band-below-the-edge")
                    let cp = Paint()
                    cp.style = .stroke
                    cp.color = stroke.color
                    canvas.save()
                    canvas.clipRect(Rect.fromLTRB(-1e6, rowTop, 1e6, rowBottom))
                    for part in Self._ruleLines(band.style, band.width) {
                        cp.strokeWidth = _px(part.width) * 0.96
                        let y = rowTop + _px(part.at) * 0.96 + cp.strokeWidth / 2
                        canvas.drawLine(Offset(d.colLeft, y), Offset(cellRight, y), cp)
                    }
                    canvas.restore()
                }
                line(d.borders.left, on(d.edges?.left, d.column == 0 ? te?.left : te?.insideV),
                     Offset(d.colLeft, rowTop), Offset(d.colLeft, rowBottom), inward: Offset(1, 0), side: d.column == 0 ? "left" : "insideV", cell: ref, cellSide: "left")
                // The row above drew this cell's top, unless the cell has
                // its own line there (on the first row it covers).
                if (c.row == 0 && d.row == 0) || (ownTop && d.borders.top != nil) {
                    line(d.borders.top, c.row == 0 && d.row == 0 && on(d.edges?.top, te?.top),
                         Offset(d.colLeft, rowTop), Offset(cellRight, rowTop), inward: Offset(0, 1), side: c.row == 0 && d.row == 0 ? "top" : "insideH", cell: ref, cellSide: "top")
                }
                if bottomHere, !bandBelow {
                    // (A merged cell whose own sides state no bottom but whose
                    // last continuation cell does: Word draws that line.
                    // zh-31d580df p27's three merged groups had no rule between.)
                    var said = d.edges?.bottom
                    if said == nil, d.rowSpan > 1, theme.wordRules, let last = ref?.continuationEdges.last, last?.bottom == true {
                        said = true
                        RuleTrace.hit("zh-31d580df-merged-cell-bottom-from-last-continuation")
                    }
                    line(d.borders.bottom, on(said, lastRow ? te?.bottom : te?.insideH),
                         Offset(d.colLeft, rowBottom), Offset(cellRight, rowBottom), inward: Offset(0, -1), side: lastRow ? "bottom" : "insideH", cell: ref, cellSide: "bottom")
                }
                if cellRight >= right - 0.5 {
                    line(d.borders.right, on(d.edges?.right, te?.right),
                         Offset(right, rowTop), Offset(right, rowBottom), inward: Offset(-1, 0), side: "right", cell: ref, cellSide: "right")
                } else if d.borders.right != nil {
                    line(d.borders.right, false, Offset(cellRight, rowTop), Offset(cellRight, rowBottom), inward: Offset(-1, 0), side: "insideV")
                } else if theme.wordRules, d.edges?.right == true, !leftDrawn(at: cellRight) {
                    // (A cell's own right side where the cell beside it
                    // draws no left: Word draws the line either cell
                    // states. zh-91e44bcb's tables give each cell a right
                    // and a bottom and no left or top, and stood without
                    // a line between their columns.)
                    line(nil, true, Offset(cellRight, rowTop), Offset(cellRight, rowBottom), inward: Offset(-1, 0), side: "insideV")
                }
                // A cell's diagonal rules (`w:tl2br`, `w:tr2bl`), corner to
                // corner of the cell as the row stands.
                if theme.wordRules, d.rowSpan == 1 || bottomHere {
                    for (name, down) in [("tl2br", true), ("tr2bl", false)] {
                        guard let side = Self._cellSide(ref?.bordersXML, name) else { continue }
                        let dp = Paint()
                        dp.style = .stroke
                        dp.color = Self._cellSideColor(ref?.bordersXML, name) ?? Color(0xFF000000)
                        dp.strokeWidth = _px(side.width)
                        let top = d.rowSpan == 1 ? rowTop : rowTop - (rowBottom - rowTop) * Double(d.rowSpan - 1)
                        canvas.drawLine(Offset(down ? d.colLeft : cellRight, top), Offset(down ? cellRight : d.colLeft, rowBottom), dp)
                    }
                }
            }
            // Each cell of the row draws its edges; a cell from above that
            // spans into this row draws its left edge here too, and its
            // bottom on its last row.
            var j = i
            var lastColumn = -1
            while j < _cells.count, let d = _cells[j], d.table == c.table, d.row == c.row {
                if d.column != lastColumn {
                    paintEdges(d, ref: document.paragraphs[j].cell, bottomHere: d.rowSpan - 1 <= d.ghostRows, ownTop: true)
                    lastColumn = d.column
                }
                j += 1
            }
            var k = i - 1
            var seen: Set<Int> = []
            while k >= 0, let d = _cells[k], d.table == c.table {
                if d.rowSpan > 1, d.row < c.row, d.row + d.rowSpan > c.row, !seen.contains(d.column) {
                    seen.insert(d.column)
                    paintEdges(d, ref: document.paragraphs[k].cell, bottomHere: d.row + d.rowSpan - 1 <= c.row + c.ghostRows, ownTop: false)
                }
                k -= 1
            }
        }
        if part == .rules { return }
        if theme.wordRules, i < document.paragraphs.count, document.paragraphs[i].style.lineCollapsed, document.paragraphs[i].image == nil { return }
        if _markUnderNestedTable(i, document) { return }
        if let image = document.paragraphs[i].image, let box = imageRect(i) {
            let turnedBox = _decoded[image.id] == nil && image.textBox != nil && _horizontalBoxOnVerticalPage(i, image)
            let drawn = _decoded[image.id] == nil && !turnedBox && _paintOutline(image, box, canvas)
            if let decoded = _decoded[image.id] {
                let clipped = _clipToCell(i, image, box, canvas)
                _drawPicture(decoded, image, box, canvas)
                _paintFrame(image, box, canvas)
                if clipped { canvas.restore() }
            } else if let inside = _textBox(image, document), let text = image.textBox {
                // A text box: its text, set inside it.
                if !_paintHorizontalBoxOnVerticalPage(i, inside, text, image, box, canvas) {
                    _paintTurnedTextBox(inside, text, image, box, canvas)
                }
            } else if !drawn, !(theme.wordRules && image.float.map({ !$0.takesRoom }) == true) {
                // (No stand-in for a floating object the editor cannot
                // draw: it would lie over the text it floats beside.)
                let paint = Paint()
                paint.style = .fill
                paint.color = Color(0x22808080)
                canvas.drawRect(box, paint)
            }
            // A list item that is a picture alone has its number too, on
            // the picture's line, at its foot: chartex's third bullet
            // stands beside its chart's lower edge in Word's print, where
            // ours drew none.
            var bare = document.paragraphs[i]
            bare.image = nil
            if theme.wordRules, image.float == nil, let label = listLabel(i, document), let wl = _wordList(bare, document) {
                let marker = _marker(i, bare, document, label: label, strut: nil)
                let at = g.textLeft + _px(wl.first)
                marker.paint(canvas, Offset(wl.format?.justification == "right" ? at - marker.width : at,
                                            box.bottom - marker.computeDistanceToActualBaseline(.alphabetic)))
                marker.dispose()
            }
            return
        }
        if let c = _cells[i], c.vertical, c.direction == .down, document.paragraphs[i].cell?.stackedUpright == true,
           _paintStacked(i, g.painter, c, document, canvas) {
            return
        }
        if let c = _cells[i], c.vertical {
            // The block painted in its own horizontal space, turned a
            // quarter about the cell's corner it reads from: text reading
            // up starts at the bottom-left corner with its lines stacking
            // rightwards, text reading down at the top-right corner with
            // its lines stacking leftwards.
            let height = c.rowSpan > 1 ? c.turnedPart ?? c.rowHeight : c.ownRowHeight
            canvas.save()
            if c.direction == .up {
                canvas.translate(c.colLeft, c.rowTop + height)
                canvas.rotate(-Double.pi / 2)
            } else {
                canvas.translate(c.colLeft + c.colWidth, c.rowTop)
                canvas.rotate(Double.pi / 2)
            }
            // (Laid out along the whole merge, set in its part on the
            // page: what the merge loses past the page's foot comes off
            // as its alignment shares it out.)
            let short = c.rowSpan > 1 && !c.wrapsPart ? c.rowHeight - height : 0
            let aligned = document.paragraphs[i].style.alignment
            // (Its line starts 2.25pt short of its indent in Word's print —
            // lab `tr`: 3.4 under the row's top at ind 113, 17.7 at 400.)
            // (A line set from its start only: not one distributed down
            // the cell — zh-701eda18's "個人申請" stands where it did.)
            // (Nor one with space before it: zh-8f9b19f4's "性别" (ind 154, 208 twips before) and
            // zh-264d7516's "被征地农户人员" (ind 1013, 207 before) start the whole 2.25 down in
            // Word's print, where ours stood 2.1 and 2.4 above it.)
            let indent = _px(document.paragraphs[i].style.indentLeft)
            let fromStart = document.paragraphs[i].style.eastAsian["w:jc"] == nil && (aligned == .left || aligned == .justify)
            let along = c.alongStart + indent
                - short * (aligned == .center ? 0.5 : aligned == .right ? 1 : 0)
                - (theme.wordRules && fromStart && c.direction == .down && indent > 0.01 && !c.wrapsPart && !(_spaceBefore[i] > 0.01) ? min(indent, _px(2.25)) : 0)
            let origin = Offset(along, c.across + _spaceBefore[i] + _turnedInkShift(i, document))
            if c.direction == .down, document.paragraphs[i].cell?.uprightIdeographs == true,
               _paintUpright(g.painter, at: origin, canvas, distribute: document.paragraphs[i].style.eastAsian["w:jc"] == "distribute", justify: theme.wordRules && aligned == .justify && document.paragraphs[i].style.eastAsian["w:jc"] == nil, mixed: true, centred: aligned == .center) {
                canvas.restore()
                _paintVerticalCellPictures(i, g, canvas, c, origin, document)
                _paintVerticalCellFloats(i, g, canvas)
                return
            }
            g.painter.paint(canvas, origin)
            canvas.restore()
            _paintVerticalCellPictures(i, g, canvas, c, origin, document)
            _paintVerticalCellFloats(i, g, canvas)
            return
        }
        if let b = document.paragraphs[i].style.borders, !_vanishes(document.paragraphs[i], document), !_emptyBreakFragment(i, document) {
            // Word's paragraph borders: each edge a line its `space` away
            // from the text, the horizontal ones spanning the text width
            // (plus the side edges' own gaps).
            let textBottom = g.textTop + g.painter.height
            let leftExt = b.left.map { _px($0.space + $0.width) } ?? 0
            let rightExt = b.right.map { _px($0.space + $0.width) } ?? 0
            let box = _boxSpan(i, g, document)
            let out = box?.extra ?? 0
            let x0 = (g.textLeft - leftExt - out).rounded(), x1 = (g.textLeft + g.textWidth + rightExt + out).rounded()
            func stroke(_ l: BorderLine) -> Paint {
                let p = Paint()
                p.style = .stroke
                p.strokeWidth = max(1, _px(l.width).rounded())
                p.color = l.color ?? (theme.wordRules && RichTextTheme.wordWindowsPages ? Color(0xFF000000) : theme.textColor)
                return p
            }
            // (A compound line's lines from the text outward.)
            func compound(_ l: BorderLine, from inner: Double, outward: Double) {
                for part in Self._ruleLines(l.style, l.width) {
                    let p = stroke(l)
                    p.strokeWidth = _px(part.width)
                    let y = inner + outward * _px(part.at + part.width / 2)
                    canvas.drawLine(Offset(x0, y), Offset(x1, y), p)
                }
            }
            if let l = b.top, l.style != "none", !(theme.wordRules && _bordersJoin(i - 1, i, document)) {
                if Self._ruleLines(l.style, l.width).count > 1 {
                    compound(l, from: g.textTop - _px(l.space), outward: -1)
                } else {
                    let y = (g.textTop - _px(l.space) - _px(l.width) / 2).rounded() + 0.5
                    canvas.drawLine(Offset(x0, y), Offset(x1, y), stroke(l))
                }
            }
            if let l = b.bottom, l.style != "none", !(theme.wordRules && _bordersJoin(i, i + 1, document)) {
                if Self._ruleLines(l.style, l.width).count > 1 {
                    compound(l, from: textBottom + _px(l.space), outward: 1)
                } else {
                    let y = (textBottom + _px(l.space) + _px(l.width) / 2).rounded() - 0.5
                    canvas.drawLine(Offset(x0, y), Offset(x1, y), stroke(l))
                }
            }
            var y0 = b.top.map { g.textTop - _px($0.space + Self._ruleRoom($0.style, $0.width)) } ?? g.textTop
            var y1 = b.bottom.map { textBottom + _px($0.space + Self._ruleRoom($0.style, $0.width)) } ?? textBottom
            if let box {
                // (One box: no top line or room under a joined edge, the sides on to the next
                // paragraph's text where it follows on the page.)
                if _bordersJoin(i - 1, i, document) { y0 = g.textTop }
                if _bordersJoin(i, i + 1, document) { y1 = box.bottom }
                y0 -= _droppedBefore(i, document)
            }
            if let l = b.left, l.style != "none" {
                let x = (g.textLeft - _px(l.space) - _px(l.width) / 2 - out).rounded() + 0.5
                canvas.drawLine(Offset(x, y0), Offset(x, y1), stroke(l))
            }
            if let l = b.right, l.style != "none" {
                let x = (g.textLeft + g.textWidth + _px(l.space) + _px(l.width) / 2 + out).rounded() - 0.5
                canvas.drawLine(Offset(x, y0), Offset(x, y1), stroke(l))
            }
        }
        // (A cell's line moved, its marker with it.)
        var shifts = lines == nil ? _cellLineShifts(i, g, document) : []
        if shifts.isEmpty, lines == nil, i < _lineLift.count, !_lineLift[i].isEmpty { shifts = _lineLift[i] }
        if shifts.isEmpty, lines == nil, let pair = Self._paired(g.painter) { shifts = pair.shifts }
        if let first = shifts.first { canvas.save(); canvas.translate(0, first) }
        if let label = listLabel(i, document), theme.marksEmptyListItems || !document.paragraphs[i].text.isEmpty {
            let p = document.paragraphs[i]
            if let wl = _wordList(p, document) {
                // As Word sets it: from the first line's offset, or up to
                // it where the level's numbers are set to the right.
                let marker = _marker(i, p, document, label: label, strut: g.painter.strutStyle)
                var at = g.textLeft + _px(wl.first) + (_besideLabelShift[i] ?? 0)
                // (Centred or set right, the number goes with its line:
                // "第一章 总则" is centred whole. The box it stands in
                // is the first thing on that line.)
                if p.style.alignment == .center || p.style.alignment == .right, _lead(i) > 0,
                   let first = g.painter.computeLineMetrics().first {
                    at = g.textLeft + first.left
                }
                // (A right-to-left paragraph's number stands at its right: its right edge
                // is the first line's start, the text's right edge and the hang.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, p.style.rightToLeft, p.cell == nil, !_mirrored.contains(i) {
                    at = g.textLeft + g.textWidth - _px(wl.first) - marker.width
                    marker.paint(canvas, Offset(at, g.inkTop))
                    marker.dispose()
                } else {
                // (A bullet that would hang wholly left of its table cell is not drawn by Word (a part outside is cut off by the cell): lab bulind, left=0 with the level's hanging in a cell, no bullet in the print; 28c56054.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell != nil, label == "\u{2022}" || label == "\u{F0B7}", at + marker.width <= g.textLeft - _px(wl.left) + _px(0.01) {
                    RuleTrace.hit("word-cell-bullet-hanging-out-of-the-cell-is-not-drawn")
                } else {
                // (A number stands on its line's baseline, as the text does: hin-z18479909's "1." in Kokila's
                // tall line (Latin digits, no Indic letter) stood 7.8pt below its text, whose line is the
                // Indic face's; the marker's own line has no such depth.)
                var markerDown = 0.0
                if theme.wordRules, RichTextTheme.wordWindowsPages, p.cell == nil {
                    let d = g.painter.computeDistanceToActualBaseline(.alphabetic) - marker.computeDistanceToActualBaseline(.alphabetic)
                    if d < -_px(0.5) { markerDown = d; RuleTrace.hit("word-list-number-on-its-lines-baseline") }
                }
                _paintMarker(marker, Offset(wl.format?.justification == "right" ? at - marker.width : at, g.inkTop + markerDown), p, document, label: label, canvas)
                }
                marker.dispose()
                }
            } else {
            var markerChar = theme.markersAtHang ? Self._slidesMarkerChar(p.runs[0].style) : p.runs[0].style
            if let c = p.style.bulletColor { markerChar.color = c }
            if let f = p.style.bulletStandInFamily ?? p.style.bulletFontFamily { markerChar.fontFamily = f }
            let k = (p.style.bulletScale ?? 1) * (p.style.bulletStandInScale ?? 1)
            if k != 1 {
                markerChar.fontSize = (markerChar.fontSize ?? _named(p, document)?.char.fontSize ?? theme.fontSize) * k
            }
            let markerStyle = theme.textStyle(for: markerChar, in: p.style, named: _named(p, document), normal: _normalChar(document), scale: scale, fontScale: fontScale)
            // (On the paragraph's strut, so that the marker's baseline
            // is the text's.)
            let marker = TextPainter(text: TextSpan(text: label, style: markerStyle),
                                     textAlign: .right, textDirection: .ltr, strutStyle: g.painter.strutStyle)
            let slot = _px(theme.listIndent)
            // On the first line's baseline: a marker of another size (a
            // bullet at 80%) has its own, higher or lower than the text's.
            func top() -> Double {
                g.textTop + _baselineShift(i, document) + g.painter.computeDistanceToActualBaseline(.alphabetic)
                    - marker.computeDistanceToActualBaseline(.alphabetic)
            }
            if !theme.markersAtHang, let own = _listIndents(p, document), own.hanging > 0 {
                // Where the file hangs it: the number starts that far
                // back from the text, as Word sets it.
                marker.textAlign = .left
                marker.layout(minWidth: 0, maxWidth: max(1, slot * 8))
                let hang = g.textLeft - _px(own.hanging)
                marker.paint(canvas, Offset(min(hang, g.textLeft - marker.width), top()))
            } else if theme.markersAtHang {
                // At the hang, and never over the text — or, with no hang at
                // all, at the first line's start, the text after it (its
                // lead, above).
                marker.layout(minWidth: 0, maxWidth: max(1, slot * 4))
                let hang = g.textLeft - slot + _px(p.style.firstLineIndent)
                if p.style.bulletAtEnd {
                    // Mirrored: the text's right edge, the hang's distance out.
                    marker.textAlign = .left
                    marker.layout(minWidth: 0, maxWidth: max(1, slot * 4))
                    marker.paint(canvas, Offset(g.textLeft + g.textWidth + (g.textLeft - hang) - marker.width, top()))
                } else if hang >= g.textLeft - 0.01, !p.text.isEmpty {
                    marker.textAlign = .left
                    marker.layout(minWidth: 0, maxWidth: max(1, slot * 4))
                    marker.paint(canvas, Offset(hang, top()))
                } else {
                    // On the first line's baseline, as PowerPoint sets it: from
                    // the line's top, a bullet at 80% stood four points high
                    // (45541's), and a stand-in face's glyph more.
                    // (A hanging bullet of a centred or right paragraph goes with its line, the text's start less
                    // the hang: lo-tdf128550's four items, `marL` 40.5pt over `indent` -40.5pt, centred in a
                    // 824pt box, have PowerPoint's bullet at 440.4, 40.5 before the text at 480.9; ours stood
                    // at the box's edge, 104.)
                    var along = 0.0
                    if p.style.alignment == .center || p.style.alignment == .right, let first = g.painter.computeLineMetrics().first { along = first.left }
                    // (A bullet wider than its hang stays at the hang, the text pushed past it: `lead`.)
                    let wide = marker.width > g.textLeft - hang + 0.01
                    marker.paint(canvas, Offset((wide ? hang : min(hang, g.textLeft - marker.width - 4)) + along, top()))
                }
            } else if theme.wordRules, !document.readFromFile {
                // No level of its own yet: where the file it is saved to
                // will hang it, half the indent back from the text.
                marker.textAlign = .left
                marker.layout(minWidth: 0, maxWidth: max(1, slot * 8))
                marker.paint(canvas, Offset(min(g.textLeft - slot / 2, g.textLeft - marker.width), top()))
            } else {
                marker.layout(minWidth: slot - 8, maxWidth: slot - 8)
                marker.paint(canvas, Offset(g.textLeft - slot, g.inkTop))
            }
            marker.dispose()
            }
        }
        if !shifts.isEmpty { canvas.restore() }
        let textAt = Offset(g.textLeft, g.inkTop + _baselineShift(i, document))
        func drawLeader(_ leader: (offset: Int, fill: String)) {
            let p = document.paragraphs[i]
            let named = _named(p, document)
            let map = _map(i)
            do {
                guard let box = g.painter.getBoxesForSelection(
                    TextSelection(baseOffset: map.painter(leader.offset), extentOffset: map.painter(leader.offset) + 1), boxHeightStyle: .max).first,
                      box.right - box.left > 1 else { return }
                var at = 0
                var run = p.runs[0].style
                for r in p.runs { if leader.offset < at + r.length { run = r.style; break }; at += r.length }
                let style = theme.textStyle(for: run, in: p.style, named: named, normal: _normalChar(document), scale: scale, fontScale: fontScale,
                                            gridPitch: _offGrid(i, document) ? nil : _grid(i, document).pitch)
                let one = TextPainter(text: TextSpan(text: leader.fill, style: style), textDirection: .ltr)
                one.layout(minWidth: 0, maxWidth: 10_000)
                let n = Int(((box.right - box.left) / max(0.5, one.width)).rounded(.down))
                one.dispose()
                guard n > 0 else { return }
                let fill = TextPainter(text: TextSpan(text: String(repeating: leader.fill, count: n), style: style),
                                       textDirection: .ltr, strutStyle: g.painter.strutStyle)
                fill.layout(minWidth: 0, maxWidth: 10_000_000)
                fill.paint(canvas, Offset(g.textLeft + box.right - fill.width, g.inkTop + box.top))
                fill.dispose()
            }
        }
        var leadersPainted = false
        _paintScripts(lines?.paragraph ?? document.paragraphs[i], lines?.painter ?? g.painter, at: textAt, canvas, document,
                      map: lines == nil ? _map(i) : nil, leading: true)
        if let lines {
            lines.painter.paint(canvas, textAt)
        } else if !_paintScaled(i, g, canvas, document) {
            if _paintFixedBoxFirstLine(i, g.painter, at: textAt, shifts, canvas) {
                // The first line and the remaining text were painted separately.
            } else if shifts.isEmpty, i < _leaders.count, _leaders[i].count == 1,
               let box = g.painter.getBoxesForSelection(
                    TextSelection(baseOffset: _map(i).painter(_leaders[i][0].offset), extentOffset: _map(i).painter(_leaders[i][0].offset) + 1),
                    boxHeightStyle: .max).first, box.right - box.left > 1 {
                // In reading order: what comes before the tab, its dots,
                // then the rest, so the text a reader takes from the page
                // runs as it reads rather than leaving the dots at the end.
                let far = 1e7, top = textAt.dy + box.top, bottom = textAt.dy + box.bottom
                for (k, clip) in [Rect.fromLTRB(-far, -far, far, top),
                                  Rect.fromLTRB(-far, top, textAt.dx + box.left, bottom)].enumerated() {
                    canvas.save(); canvas.clipRect(clip, clipOp: .intersect, doAntiAlias: false)
                    g.painter.paint(canvas, textAt); canvas.restore()
                    if k == 1 { drawLeader(_leaders[i][0]) }
                }
                for clip in [Rect.fromLTRB(textAt.dx + box.right, top, far, bottom), Rect.fromLTRB(-far, bottom, far, far)] {
                    canvas.save(); canvas.clipRect(clip, clipOp: .intersect, doAntiAlias: false)
                    g.painter.paint(canvas, textAt); canvas.restore()
                }
                leadersPainted = true
            } else if shifts.isEmpty, let shift = _unseenShift[i], case let length = g.painter.plainText.utf16.count,
                      case let end = g.painter.getLineBoundary(TextPosition(offset: 0)).end, end > 0, end < length,
                      let onlyFirst = _clearedPainter(g.painter, [end..<length], key: 4, clearBackgroundAndDecoration: true),
                      let onlyRest = _clearedPainter(g.painter, [0..<end], key: 5, clearBackgroundAndDecoration: true) {
                // (A first line held past the cell by its indent: only it stands where Word's does,
                // the lines after it at the paragraph's own place.)
                onlyFirst.paint(canvas, Offset(textAt.dx + shift, textAt.dy))
                onlyRest.paint(canvas, textAt)
            } else if shifts.isEmpty, _verticalBody(i), _paintUpright(g.painter, at: textAt, canvas, mixed: true) {
                // (A vertical section's lines: each ideograph upright down its column, as Word prints them.)
            } else if shifts.isEmpty { g.painter.paint(canvas, _unseenShift[i].map { Offset(textAt.dx + $0, textAt.dy) } ?? textAt) } else { _paintShiftedLines(g.painter, at: textAt, shifts, canvas) }
        }
        _paintScripts(lines?.paragraph ?? document.paragraphs[i], lines?.painter ?? g.painter, at: textAt, canvas, document,
                      map: lines == nil ? _map(i) : nil, leading: false)
        _paintRuby(lines?.paragraph ?? document.paragraphs[i], lines?.painter ?? g.painter, at: textAt, canvas, document,
                   map: lines == nil ? _map(i) : nil, index: i)
        _paintEmphasis(lines?.paragraph ?? document.paragraphs[i], lines?.painter ?? g.painter, at: textAt, canvas, document,
                       map: lines == nil ? _map(i) : nil, index: i)
        if lines == nil { _paintClosingUnderline(i, g, at: textAt, canvas, document) }
        if !leadersPainted, i < _leaders.count, !_leaders[i].isEmpty {
            // A leader fills its tab: the character over and over, up to
            // the text the tab leads to.
            for leader in _leaders[i] { drawLeader(leader) }
        }
        if i < _inline.count, !_inline[i].isEmpty, let all = g.painter.inlinePlaceholderBoxes {
            for k in _floatPaintOrder(i) {
                let slot = _inlineBoxes[i][k]
                guard slot < all.count else { continue }
                let box = all[slot]
                let image = _inline[i][k]
                var rect = box.toRect().shift(Offset(g.textLeft, g.inkTop))
                if let real = _pageFill[image.id], image.float == nil {
                    let down = _lineCentre[image.id] ?? 0
                    rect = Rect.fromLTRB(rect.left, rect.top + down, rect.right, rect.top + down + real)
                }
                if _behindDrawn.contains("\(image.id)") { continue }
                // (An equation on a line the 1.5-spacing rule moved down goes down with the line's text:
                // jpn-z22855378-6fca0f's 'Δx≫σ' stood 9.6pt above its text's baseline.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, image.float == nil, image.name == "m:oMath",
                   let pair = Self._paired(g.painter) {
                    let raw = Self._rawLineBottoms(g.painter), mid = box.toRect().top + box.toRect().height / 2
                    if pair.shifts.count == raw.count, let line = raw.firstIndex(where: { mid < $0 }) {
                        rect = rect.shift(Offset(0, pair.shifts[line]))
                    }
                }
                if theme.wordRules, let float = image.float, !float.takesRoom {
                    // A floating object, from its paragraph by its place:
                    // a picture, or a text box's text; one that cannot
                    // be drawn is left out.
                    if image.textBox?.fitsText == true { _ = _textBox(image, document) }
                    rect = _floatRect(float, image, g, i)
                    // (Word writes a drop cap's text after the page's body text, so a reader of the page finds
                    // it as one run at the end: lo-e6dce9d6's "- – — ".)
                    if _dropCapPass == 1, image.isDropCap { continue }
                    if _decoded[image.id] == nil {
                        _paintOutline(image, rect, canvas)
                        if let inside = _textBox(image, document), let text = image.textBox {
                            self._paintTurnedTextBox(inside, text, image, rect, canvas, clips: true)
                        }
                        continue
                    }
                }
                let paint = Paint()
                if theme.wordRules, image.float == nil {
                    let room = _pictureRoom(image)
                    // (Not its left, in a frame placed on the page: the drawing stands at
                    // the frame's x, effect extent or none — lab frame.)
                    let framedOnPage = document.paragraphs[i].style.frame.map { $0.verticalAnchor == "page" && $0.horizontalAnchor == "page" } ?? false
                    rect = Rect.fromLTRB(rect.left + (framedOnPage ? 0 : room.left), rect.top + room.top, rect.right - room.right, rect.bottom - room.bottom)
                }
                if _dropCapPass == 1, image.isDropCap { continue }
                if let decoded = _decoded[image.id] {
                    let clipped = _clipToCell(i, image, rect, canvas)
                    _drawPicture(decoded, image, rect, canvas)
                    _paintFrame(image, rect, canvas)
                    if clipped { canvas.restore() }
                } else if let inside = _textBox(image, document), let text = image.textBox {
                    // (A text box in the line keeps its fill and outline as a floating one does:
                    // lo-ffef711a's two boxes, red and blue fills, stood bare in ours.)
                    if theme.wordRules { _paintOutline(image, rect, canvas) } else { _ = _paintObject(image, rect, canvas) }
                    _paintTurnedTextBox(inside, text, image, rect, canvas)
                } else if theme.wordRules, image.name == "checkbox" || image.name == "checkbox-on", let outline = image.outline {
                    // (A form's check box: see where it is set. Stroked
                    // inside its square, as Word's 0.72 line is; a ticked
                    // one crossed corner to corner.)
                    let stroke = Paint()
                    stroke.style = .stroke
                    stroke.strokeWidth = _px(outline.width)
                    stroke.color = outline.color ?? theme.textColor
                    canvas.drawRect(rect, stroke)
                    if image.name == "checkbox-on" {
                        canvas.drawLine(rect.topLeft, rect.bottomRight, stroke)
                        canvas.drawLine(rect.bottomLeft, rect.topRight, stroke)
                    }
                } else if !_paintObject(image, rect, canvas) {
                    // (An object in the line that the app draws — chartex's
                    // line chart, a space after it — is drawn as one alone in
                    // its paragraph is; any other, a grey stand-in.)
                    paint.style = .fill
                    paint.color = Color(0x22808080)
                    canvas.drawRect(rect, paint)
                }
            }
        }
        _paintSpelling(i, g, canvas, document)
        if theme.showMarks, !document.paragraphs[i].isImage {
            let end = caretRect(RichPosition(paragraph: i, offset: document.paragraphs[i].length), document)
            let style = theme.textStyle(for: CharStyle(color: theme.textColor.withOpacity(0.45)),
                                        in: document.paragraphs[i].style, scale: scale)
            let mark = TextPainter(text: TextSpan(text: document.paragraphs[i].cell == nil ? "\u{00B6}" : "\u{00A4}", style: style),
                                   textAlign: .left, textDirection: .ltr)
            mark.layout(minWidth: 0, maxWidth: 40)
            mark.paint(canvas, Offset(end.left + 1, end.top + (end.height - mark.height) / 2))
            mark.dispose()
        }
    }
}

extension RichLayout {
    /// A horizontal text box anchored in a vertical section: the page is laid out turned a quarter, so the box is
    /// stood back up on the paper (`_verticalBody`).
    @inline(never)
    func _horizontalBoxOnVerticalPage(_ i: Int, _ image: ImageAttachment) -> Bool {
        guard theme.wordRules, _verticalBody(i) else { return false }
        guard let f = image.float, !f.takesRoom, f.horizontalFrom == "column", f.horizontalAlign == nil,
              f.verticalFrom == "margin" || f.verticalFrom == "paragraph",
              i < _pieceStart.count, _pieceStart[i] < _allPieces.count else { return false }
        return true
    }

    func _paintHorizontalBoxOnVerticalPage(_ i: Int, _ inside: _HeaderFooter, _ text: RichTextBox, _ image: ImageAttachment, _ box: Rect, _ canvas: any Canvas) -> Bool {
        guard _horizontalBoxOnVerticalPage(i, image), text.textDirection == .horizontal, let f = image.float else { return false }
        let pc = _allPieces[_pieceStart[i]]
        let setup = _setup(ofParagraph: i)
        let page = pageRect(pc.page)
        let ppx = theme.pixelsPerPoint * scale
        // (Paper points: x runs from the left edge, y from the top; the layout's y is the paper's x turned.)
        let w = box.width / ppx, h = box.height / ppx
        let lineRight = setup.height - (setup.marginTop + pc.pageY / ppx)
        let px0 = lineRight + f.x
        let top = setup.marginLeft
        var py0 = top + f.y
        if f.verticalFrom == "margin" {
            switch f.verticalAlign {
            case "center": py0 = top + (setup.contentWidth - h) / 2 + f.y
            case "bottom": py0 = top + setup.contentWidth - h + f.y
            default: break
            }
        }
        // (The canvas here is cut to the page, in layout orientation: its clip's corner is the page's origin.)
        let base = canvas.getLocalClipBounds()
        guard abs(base.width - setup.width * ppx) < 2, abs(base.height - setup.height * ppx) < 2 else { return false }
        canvas.save()
        canvas.translate(py0 * ppx + base.left, (setup.height - px0) * ppx + base.top)
        canvas.rotate(-Double.pi / 2)
        _ = _paintOutline(image, Rect.fromLTWH(0, 0, w * ppx, h * ppx), canvas)
        _paintTurnedTextBox(inside, text, image, Rect.fromLTWH(0, 0, w * ppx, h * ppx), canvas, clips: false)
        canvas.restore()
        return true
    }
}
