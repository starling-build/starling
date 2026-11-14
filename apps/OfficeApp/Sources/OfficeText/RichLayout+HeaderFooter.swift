// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "HeaderFooter": moved out of RichLayout.swift by test/tools/split-richlayout.py (a pure move, so that
// the parts compile side by side).

import Flutter
import FlutterSwiftBridge
import Foundation

extension RichLayout {

    /// Whether a framed paragraph stands at a height on the page: its frame
    /// anchored to the page or its margin, or naming no anchor. (One that
    /// names a height and no anchor is read as on the margin, the schema's
    /// default: zh-90e0cea8's "发布" frame, which says only its y, prints
    /// 784.9pt down the page, 751 under a 16.9pt margin.)
    /// A frame the layout places on the page: one with no alignment, or
    /// aligned on the margins by a height it states.
    static func _framePlaced(_ f: ParagraphFrame) -> Bool {
        guard let a = f.verticalAlign else { return true }
        return f.verticalAnchor == "margin" && f.height != nil && (a == "top" || a == "center" || a == "bottom")
    }

    /// The room under a line's text in a paragraph set at a multiple of its
    /// single height: Word adds the extra below the text, so a table raised a
    /// few points over its anchor does not reach the line above it (lo-235e3561's
    /// 1.5-spaced heading, tblpY -73 twips: Word keeps it on page 1 over the table).
    static func _multipleSlack(_ st: RichParagraphStyle, _ height: Double) -> Double {
        guard RichTextTheme.wordWindowsPages, st.lineHeightPoints == nil, st.lineSpacing > 1.0 else { return 0 }
        return height * (1 - 1 / st.lineSpacing)
    }

    /// The room a table floating by the text keeps clear above it (`w:topFromText`, points),
    /// for one anchored to the text; 0 for none.
    static func _floatTopGap(_ ts: TableStyle) -> Double {
        guard let kept = ts.keptPosition, kept.containsSubstring("w:vertAnchor=\"text\""),
              let r = kept.rangeOfSubstring("w:topFromText=\"") else { return 0 }
        return (Double(kept[r.upperBound...].prefix { $0 == "-" || $0.isNumber }) ?? 0) / 20
    }

    /// A frame a style defines, of an exact height and a width, aligned on the margins
    /// with no anchor of its own: the text round it stands in the strips beside it.
    static func _stripFrame(_ style: RichParagraphStyle) -> Bool {
        guard let f = style.frame, f.width != nil, f.height != nil, f.verticalAnchor == "margin", f.verticalAlign != nil,
              let xml = style.frameXML, !xml.containsSubstring("w:vAnchor="), xml.containsSubstring("w:hRule=\"exact\""),
              !xml.containsSubstring("w:wrap=\"") || xml.containsSubstring("w:wrap=\"auto\"") else { return false }
        return true
    }

    /// The box in a paragraph that the text goes round and the page fixes: wrapped, in the
    /// text's way, aligned on the page or its margins both ways (`_floatRect`'s place).
    /// A wrapping shape set by its offsets from the paragraph and its column.
    static func _otherColumnsBox(_ p: RichParagraph) -> (image: ImageAttachment, float: ImageFloat)? {
        for image in p.inlineImages.inOrder + (p.image.map { [$0] } ?? []) {
            guard let float = image.float, float.wraps, !float.takesRoom, !float.bandsPage,
                  float.verticalFrom == "paragraph", float.verticalAlign == nil,
                  float.horizontalFrom == "column", float.horizontalAlign == nil, float.wrapSide == nil,
                  image.width > 0, image.height > 0 else { continue }
            return (image, float)
        }
        return nil
    }

    static func _pageBox(_ p: RichParagraph) -> (image: ImageAttachment, float: ImageFloat)? {
        guard p.cell == nil else { return nil }
        for image in p.inlineImages.inOrder + (p.image.map { [$0] } ?? []) {
            guard let float = image.float, float.wraps, !float.takesRoom, !float.bandsPage,
                  let a = float.verticalAlign, a == "top" || a == "center" || a == "bottom",
                  float.verticalFrom == "page" || float.verticalFrom == "margin",
                  float.horizontalFrom == "page" || float.horizontalFrom == "margin",
                  float.horizontalAlign != "inside", float.horizontalAlign != "outside",
                  float.heightShare == nil, image.textBox?.fitsText != true, image.width > 0, image.height > 0 else { continue }
            return (image, float)
        }
        return nil
    }

    /// A box in a header's or footer's paragraph that the body's text goes round.
    /// A header's or footer's paragraph's boxes placed against the page, in the order the file has
    /// them (wrapped round or not: one behind the text still moves another off it).
    static func _hfWrapBoxes(_ p: RichParagraph) -> [(image: ImageAttachment, float: ImageFloat)] {
        guard p.cell == nil else { return [] }
        // (By where their runs stand: the table is keyed by the images' ids, whose order is no order — two
        // header boxes of lo-db00fd9f came out either way round, and the page's text with them.)
        var place: [String: Int] = [:]
        var at = 0
        for r in p.runs {
            if let id = r.style.inlineImage, place[id] == nil { place[id] = at }
            at += r.length
        }
        let images = p.inlineImages.values.sorted { (place[$0.id] ?? Int.max, $0.seq) < (place[$1.id] ?? Int.max, $1.seq) }
            + (p.image.map { [$0] } ?? [])
        return images.compactMap { image in
            guard let float = image.float, float.verticalAlign == nil,
                  float.verticalFrom == "page" || float.verticalFrom == "margin" || (float.verticalFrom == "paragraph" && float.y >= 0),
                  image.width > 0, image.height > 0 else { return nil }
            return (image, float)
        }
    }

    /// Where a page's text must start below its header's boxes (pixels from the page's top), or
    /// nil. A box the text wraps round, in front of it, that reaches from above the top margin into
    /// the body and leaves no line's room at either side, holds the text under it; and a box that may
    /// not be overlapped (`allowOverlap` 0) that a box before it, also not to be overlapped, stands
    /// over, goes down under that one first. LibreOffice's lo-db00fd9f: an empty full-width box at
    /// 92.6-108.15 and a 56pt one behind the text at 99.75-156, both allowOverlap 0. Word for Windows'
    /// print (labs hdr, hdr2) sets the empty one under the other, 156.6-172.15, and the text under
    /// it: the empty first line at 181.3 and "nonumy…" at 208.8, where ours ran it at 132.8. With
    /// the empty box alone, the text goes under its 108.15 (144.7); with the other alone, it stays
    /// at the margin (134.9) — that one is behind the text.
    func _headerBoxFloor(_ hf: _HeaderFooter, _ setup: PageSetup) -> Double? {
        var boxes: [(top: Double, bottom: Double, x0: Double, x1: Double, front: Bool, solid: Bool, gap: Double)] = []
        var underOwnLine = false
        let marginTop = _px(setup.marginTop)
        let left = _px(setup.marginLeft + setup.gutter), across = _px(setup.contentWidth)
        for p in hf.document.paragraphs {
            for (image, float) in Self._hfWrapBoxes(p) {
                let xml = image.sourceXML ?? ""
                let w = _px(image.width), h = _px(image.height)
                // (Placed down from a header's paragraph, which stands at the header distance: zh 837ac08d's
                // 96pt picture, header distance 0, holds the text under it; from the margin it would not reach.)
                let origin = float.verticalFrom == "page" ? 0 : (float.verticalFrom == "paragraph" && float.verticalAlign == nil ? _px(setup.headerDistance) : marginTop)
                let top = origin + _px(float.y)
                if float.verticalFrom == "paragraph" && float.verticalAlign == nil { underOwnLine = true }
                let base = float.horizontalFrom == "page" ? 0 : left
                let span = float.horizontalFrom == "page" ? _px(setup.width) : across
                let x0: Double
                switch float.horizontalAlign {
                case "center": x0 = base + (span - w) / 2
                case "right": x0 = base + span - w
                case "left": x0 = base
                default: x0 = base + _px(float.x)
                }
                boxes.append((top, top + h, x0, x0 + w, (float.wraps || float.bandsPage) && !xml.containsSubstring("behindDoc=\"1\""),
                              xml.containsSubstring("allowOverlap=\"0\""), _px(float.distanceBottom)))
            }
        }
        guard !boxes.isEmpty else { return nil }
        let original = boxes
        for b in boxes.indices where boxes[b].solid {
            for _ in 0 ..< boxes.count {
                guard let a = boxes[..<b].first(where: { a in a.solid && a.x0 < boxes[b].x1 && boxes[b].x0 < a.x1
                    && a.top < boxes[b].bottom - 0.01 && boxes[b].top < a.bottom - 0.01 }) else { break }
                let h = boxes[b].bottom - boxes[b].top
                boxes[b].top = a.bottom
                boxes[b].bottom = a.bottom + h
            }
        }
        var floor: Double? = nil
        let room = _px(18)
        for (k, b) in boxes.enumerated() where b.front {
            guard original[k].top < marginTop, original[k].bottom > marginTop,
                  b.x0 - left < room, left + across - b.x1 < room else { continue }
            floor = max(floor ?? 0, b.bottom + b.gap)
        }
        // (A box the header's own paragraph stands against: that paragraph's line is set under it, and the
        // body starts below that line, not at the box: zh 837ac08d, Word's body 14pt lower than the box's foot.)
        if underOwnLine, let f = floor { floor = f + hf.height }
        if floor != nil { RuleTrace.hit("word-header-box-with-no-room-beside-it-holds-the-text-under-it") }
        return floor
    }

    static func _hfBox(_ p: RichParagraph) -> (image: ImageAttachment, float: ImageFloat)? {
        guard p.cell == nil else { return nil }
        // (The first in the file's order, not the image table's, which has none: `_hfWrapBoxes`.)
        var place: [String: Int] = [:]
        var at = 0
        for r in p.runs {
            if let id = r.style.inlineImage, place[id] == nil { place[id] = at }
            at += r.length
        }
        for image in p.inlineImages.values.sorted(by: { (place[$0.id] ?? Int.max, $0.seq) < (place[$1.id] ?? Int.max, $1.seq) }) + (p.image.map { [$0] } ?? []) {
            guard let float = image.float, float.wraps, !float.takesRoom, !float.bandsPage,
                  float.horizontalFrom != "rightMargin",
                  float.horizontalAlign != "inside", float.horizontalAlign != "outside",
                  float.heightShare == nil, image.textBox?.fitsText != true, image.width > 0, image.height > 0 else { continue }
            return (image, float)
        }
        return nil
    }

    /// A header box's height (pixels) as the body's wrap sees it: the stated one, or, for a
    /// wrapping `spAutoFit` box, its text's (Word shrinks it; the extent in the file is stale).
    @inline(never)
    func _fittedBoxHeight(_ image: ImageAttachment, _ document: RichDocument) -> Double {
        let stated = _px(image.height)
        guard theme.wordRules, RichTextTheme.wordWindowsPages, let box = image.textBox, box.autoHeight,
              let inside = _textBox(image, document) else { return stated }
        let fitted = inside.height + _px(box.insetTop + box.insetBottom)
        guard fitted > 0, fitted < stated else { return stated }
        RuleTrace.hit("word-header-autofit-box-wraps-the-body-at-its-text-height")
        return fitted
    }

    static func _onThePage(_ style: RichParagraphStyle) -> Bool {
        guard let frame = style.frame else { return false }
        return frame.verticalAnchor == "page" || frame.verticalAnchor == "margin" || !(style.frameXML ?? "").containsSubstring("w:vAnchor=")
    }
    /// Text boxes' own layouts, by attachment.
    /// The box for a run set as two lines in one (see `_span`): the
    /// first half of `chars` over the second, at half the run's size,
    /// as wide as the wider and as tall as the two lines are.
    func _combineBox(_ chars: [Character], _ run: CharStyle, _ p: RichParagraph, named: RichNamedStyle?,
                             _ document: RichDocument) -> ImageAttachment? {
        let size = run.fontSize ?? named?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
        let split = (chars.count + 1) / 2
        let key = "\(String(chars))|\(split)|\(size)|\(scale)|\(run.hashValue)"
        if let hit = _combineBoxes[key] { return hit }
        var half = run
        half.fontSize = size / 2
        half.keptXML = nil
        var lineStyle = RichParagraphStyle(alignment: .center, spaceAfter: 0, lineSpacing: 1.0)
        lineStyle.named = p.style.named
        let lines = [String(chars[..<split]), String(chars[split...])]
        let paragraphs = lines.map { RichParagraph(text: $0, runs: [Run(length: $0.utf16.count, style: half)], style: lineStyle) }
        var widest = 0.0
        for line in lines {
            let painter = TextPainter(text: TextSpan(text: line, style: theme.textStyle(for: half, in: lineStyle, named: named, normal: _normalChar(document),
                                                                                    scale: scale, eastAsian: true)), textDirection: .ltr)
            painter.layout(minWidth: 0, maxWidth: 1e7)
            widest = max(widest, painter.width)
            painter.dispose()
        }
        var box = RichTextBox(paragraphs: paragraphs)
        box.insetLeft = 0; box.insetTop = 0; box.insetRight = 0; box.insetBottom = 0
        // (As wide as its lines are set in the box, each run in its own
        // face: measured in the East Asian one alone, zh-c591c1fa's
        // "原訂2月28日發行之公報，因適" (7pt halves of 14pt 標楷體, its
        // digits Times) came out narrower than the box then set it, and
        // "適" wrapped to a third row Word's print does not have.)
        var probe = ImageAttachment(data: Data(), width: 1e5, height: 1, name: "combine")
        probe.textBox = box
        if let open = _textBox(probe, document) {
            for k in paragraphs.indices {
                widest = max(widest, open.layout.geometry(k).painter.computeLineMetrics().map { $0.width }.max() ?? 0)
            }
        }
        var image = ImageAttachment(data: Data(), width: widest / _px(1) + 0.05, height: 1, name: "combine")
        image.textBox = box
        guard let laid = _textBox(image, document) else { return nil }
        image.height = laid.height / _px(1)
        _combineBoxes[key] = image
        return image
    }

    func _canCorrectFixedBoxIndent(_ text: RichTextBox) -> Bool {
        // Upright ideographs use a separate painter. Word's rotated
        // unequal-inset frames also have another clip transform; measured
        // here are horizontal frames and zero-inset turned ones.
        theme.wordRules && text.hasFixedFrame && !text.fitsText && !text.fitsHeight && !text.growsToFit && text.parts.isEmpty
            && !text.uprightIdeographs
            && (text.textDirection == .horizontal
                || [text.insetLeft, text.insetTop, text.insetRight, text.insetBottom].allSatisfy { $0 == 0 })
    }

    /// How far a turned text box's lines are moved across its frame to stand in the
    /// middle of it, where the text is anchored there (`wps:bodyPr anchor="ctr"`).
    func _turnedSlack(_ inside: _HeaderFooter, _ text: RichTextBox, _ rect: Rect) -> Double? {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, text.anchor == "ctr", text.hasFixedFrame, text.parts.isEmpty, !text.uprightIdeographs else { return nil }
        let room = rect.width - _px(text.insetLeft + text.insetRight)
        let slack = room - inside.layout.totalHeight
        return slack > 0.01 ? slack / 2 : nil
    }

    /// A text box's text in a shape that is itself turned (`RichTextBox.shapeRotation`):
    /// the text is set in the shape's own frame, and turned with it about its centre
    /// — a shape turned 90° with its text read upward (`vert270`) reads across the
    /// page, in the middle of the shape (LibreOffice's tdf87924, an arrow turned
    /// to point down with "hello" level in it).
    func _paintTurnedTextBox(_ inside: _HeaderFooter, _ text: RichTextBox, _ image: ImageAttachment, _ rect: Rect, _ canvas: any Canvas, clips: Bool = true) {
        guard theme.wordRules, abs(text.shapeRotation) > 0.01 else {
            _paintTextBox(inside, text, rect, canvas, clips: clips)
            return
        }
        let c = rect.center
        canvas.save()
        canvas.translate(c.dx, c.dy)
        canvas.rotate(text.shapeRotation * Double.pi / 180)
        _paintTextBox(inside, text, Rect.fromLTWH(-rect.width / 2, -rect.height / 2, rect.width, rect.height), canvas, clips: clips)
        canvas.restore()
    }

    /// A text box's text in its box `rect`: from its insets, or turned a
    /// quarter about the corner it reads from (`RichTextBox.textDirection`)
    /// — reading up from the bottom-left inset corner, its lines stacking
    /// rightwards; reading down from the top-right, stacking leftwards.
    func _paintTextBox(_ inside: _HeaderFooter, _ text: RichTextBox, _ rect: Rect, _ canvas: any Canvas, clips: Bool = true) {
        canvas.save()
        // (Text past a box that keeps its size and bands its page is not
        // shown: zh-6d402586's box of revision dates, 158pt tall, holds ten
        // of its fifteen dates in Word's print, the rest hidden under its
        // foot; ours ran them down over "一、前言". A box wrapped none is cut
        // the same way: dx2 c67f3706's "（様式６）" box shows only "（様式" and
        // Word drops the wrapped "６）", with or without vertOverflow
        // (labs box6).)
        var cutsAtFoot = false
        if clips, theme.wordRules, text.textDirection == .horizontal, !text.fitsText, !text.fitsHeight, !text.growsToFit, text.parts.isEmpty {
            cutsAtFoot = true
            canvas.clipRect(Rect.fromLTRB(rect.left - 1_000_000, rect.top - 1_000_000, rect.right + 1_000_000, rect.bottom - _px(text.insetBottom)),
                            clipOp: .intersect, doAntiAlias: false)
        }
        // (A turned box that keeps its size, its first line indented past the line's length, cuts its text at its
        // edge: zh-b24b396a's "30" dimension labels, vert270 boxes 11.9pt wide and 7.8 long under a 15pt first-line
        // indent, set "3" past the foot and "0" on a second line half outside; Word's print shows neither the "3" nor
        // more than a 1.6pt sliver of the "0" (read at 300 dpi). Only where the indent outruns the line: the same
        // clip on every turned box took lines out of the text.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, text.textDirection != .horizontal, text.hasFixedFrame, !text.fitsText,
           !text.fitsHeight, !text.growsToFit, text.parts.isEmpty, !text.uprightIdeographs,
           [text.insetLeft, text.insetTop, text.insetRight, text.insetBottom].allSatisfy({ $0 == 0 }),
           let p0 = inside.document.paragraphs.first,
           inside.layout._px(inside.layout.firstLineIndent(p0, at: 0, inside.document)) > (text.textDirection == .up || text.textDirection == .down ? rect.height : rect.width) + 0.01 {
            RuleTrace.hit("turnedTextBoxCutsAtEdge")
            canvas.clipRect(rect, clipOp: .intersect, doAntiAlias: false)
        }
        // (A picture in the line bigger than a box that keeps its size is
        // cut at the box's edge: zh-701eda18 p6's 154x159pt emblem in a
        // 126x27pt box shows as nothing in Word's print; ours drew it whole.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, text.textDirection == .horizontal, !text.fitsText, !text.fitsHeight, !text.growsToFit,
           inside.layout._inline.contains(where: { $0.contains { $0.float == nil && _px($0.height) > rect.height * 1.5 } }) {
            RuleTrace.hit("textBoxCutsBigPicture")
            canvas.clipRect(rect, clipOp: .intersect, doAntiAlias: false)
        }
        switch text.textDirection {
        case .horizontal:
            canvas.translate(rect.left + _px(text.insetLeft), rect.top + _px(text.insetTop))
        case .up:
            canvas.translate(rect.left + _px(text.insetLeft), rect.bottom - _px(text.insetBottom))
            canvas.rotate(-Double.pi / 2)
            if let slack = _turnedSlack(inside, text, rect) { canvas.translate(0, slack) }
        case .down:
            canvas.translate(rect.right - _px(text.insetRight), rect.top + _px(text.insetTop))
            canvas.rotate(Double.pi / 2)
            if let slack = _turnedSlack(inside, text, rect) { canvas.translate(0, slack) }
        }
        // (Upright ideographs, `eaVert`: each paragraph of ideographs
        // stood up in its place, as a cell's — and the whole turned, as
        // `vert`, where any line holds something else.)
        if text.uprightIdeographs, text.textDirection == .down, inside.beside.isEmpty,
           _paintUprightBox(inside, canvas) {
            canvas.restore()
            return
        }
        // (The boxes of a group stacked in one flow are each cut at their own foot: dx2 2263e221's
        // 18pt "রিটার্ন রেজিস্টারের ক্রমিক নম্বর" box shows its first line only in Word's print and the
        // wrapped line, which our flow set under it, is neither drawn nor in Word's text layer.)
        if clips, theme.wordRules, RichTextTheme.wordWindowsPages, text.textDirection == .horizontal, text.parts.count > 1,
           !text.fitsText, !text.fitsHeight, !text.growsToFit, inside.beside.isEmpty {
            RuleTrace.hit("group-box-stacked-in-one-flow-cut-at-its-foot")
            canvas.restore()
            for (n, part) in text.parts.enumerated() {
                canvas.save()
                let top = n == 0 ? rect.top - 1_000_000 : rect.top + _px(part.top)
                let foot = rect.top + _px(part.top + part.height - text.insetBottom)
                canvas.clipRect(Rect.fromLTRB(rect.left - 1_000_000, top, rect.right + 1_000_000, foot), clipOp: .intersect, doAntiAlias: false)
                canvas.translate(rect.left + _px(text.insetLeft), rect.top + _px(text.insetTop))
                // (Each box shows its own paragraphs: the line one's text runs
                // down into the next box's band is that box's, not its own.)
                var band: (top: Double, bottom: Double)? = nil
                let tops = inside.layout._tops
                if part.first < tops.count {
                    let nextFirst = n + 1 < text.parts.count ? text.parts[n + 1].first : Int.max
                    band = (n == 0 ? -100_000 : tops[part.first] - 0.5, nextFirst < tops.count ? tops[nextFirst] - 0.5 : 100_000)
                }
                // (A shape before it whose text runs past its foot, that Word
                // clips there, does not push this one down: it stands where
                // its own box does.)
                if n > 0, part.first < tops.count {
                    let shift = _px(part.top - text.insetTop) - tops[part.first]
                    if shift < -0.01 { canvas.translate(0, shift) }
                }
                _paintBoxText(inside, canvas, band: band)
                canvas.restore()
            }
            return
        }
        _paintBoxText(inside, canvas)
        canvas.restore()
        if cutsAtFoot { _paintTextPastFoot(inside, text, rect, canvas) }
    }

    /// What the foot clip hides stays in the page's text layer, as in Word's
    /// print (hin-z14202734's clipped "Print-ISSN No" line is in Word's text
    /// layer on all five pages): drawn again, only under the foot, at 1/255.
    @inline(never)
    func _paintTextPastFoot(_ inside: _HeaderFooter, _ text: RichTextBox, _ rect: Rect, _ canvas: any Canvas) {
        canvas.save()
        // (A line the foot clip cuts through is drawn once, by the visible pass; the ghost starts under it.)
        let edge = rect.bottom - _px(text.insetBottom)
        var ghostTop = edge
        let originY = rect.top + _px(text.insetTop)
        let n = inside.document.paragraphs.count
        if inside.layout._painters.count >= n {
            for i in 0 ..< n {
                let g = inside.layout.geometry(i)
                for line in g.painter.computeLineMetrics() {
                    let top = originY + g.textTop + line.baseline - line.ascent
                    let bottom = originY + g.textTop + line.baseline + line.descent
                    if line.baseline + g.textTop + originY - line.ascent * 0.5 < edge, bottom > edge + 0.01, top < edge { ghostTop = max(ghostTop, bottom) }
                }
            }
        }
        canvas.clipRect(Rect.fromLTRB(rect.left - 1_000_000, ghostTop, rect.right + 1_000_000, rect.bottom + 1_000_000),
                        clipOp: .intersect, doAntiAlias: false)
        canvas.translate(rect.left + _px(text.insetLeft), rect.top + _px(text.insetTop))
        let ghost = Paint()
        ghost.color = Color(0x01000000)
        canvas.saveLayer(nil, ghost)
        _paintBoxText(inside, canvas)
        canvas.restore()
        canvas.restore()
    }

    /// A box's paragraphs with their ideographs upright, if every
    /// paragraph that holds text is ideographs and blanks.
    func _paintUprightBox(_ inside: _HeaderFooter, _ canvas: any Canvas) -> Bool {
        let layout = inside.layout
        let n = inside.document.paragraphs.count
        guard n > 0, layout._painters.count >= n else { return false }
        // (Every paragraph with an ideograph in it stood up — the rest of
        // it on its side — or none, the box turned whole as `vert`.)
        let texts = (0 ..< n).map { inside.document.paragraphs[$0].text }
        guard texts.contains(where: { $0.utf16.contains { $0 >= 0x2E80 && !($0 >= 0xD800 && $0 <= 0xDFFF) } }) else { return false }
        for i in 0 ..< n where !texts[i].isEmpty {
            let g = layout.geometry(i)
            if !layout._paintUpright(g.painter, at: Offset(g.textLeft, g.textTop), canvas, mixed: true) {
                g.painter.paint(canvas, Offset(g.textLeft, g.textTop))
            }
        }
        return true
    }

    /// A text box's text, at the canvas's origin: its flow, and any
    /// boxes of its group laid out beside it.
    func _paintBoxText(_ inside: _HeaderFooter, _ canvas: any Canvas, band: (top: Double, bottom: Double)? = nil) {
        let all = Rect.fromLTWH(-100_000, -100_000, 200_000, 200_000)
        inside.layout.paint(canvas, visible: band.map { Rect.fromLTRB(-100_000, $0.top, 100_000, $0.bottom) } ?? all, document: inside.document, selection: nil, caret: nil)
        for other in inside.beside {
            canvas.save()
            // (A box turned in its group, about its middle: zh-b24b396a's
            // "（全宗名称）", 8pt glyphs 58° up in Word's print.)
            if let turn = other.turn {
                canvas.translate(turn.x, turn.y)
                canvas.rotate(turn.degrees * Double.pi / 180)
                canvas.translate(-turn.x, -turn.y)
            }
            canvas.translate(0, other.dy)
            other.layout.paint(canvas, visible: all, document: other.document, selection: nil, caret: nil)
            canvas.restore()
        }
    }

    /// Where note `id` may part: the bottoms of its lines but the last,
    /// pixels from its top.
    /// (The bottoms of the lines' rows as the page counts them,
    /// `_lineBottoms`: the engine's own box of a strut's line can stand
    /// above its row — 0.45pt in zh-7a16a243's 10pt 標楷體 notes — and a note
    /// parted there kept that much less of its page, and its rest stood
    /// as much lower on the next, under a rule 1.63pt higher than Word's
    /// where an unparted note's is 1.16: page 7 then lost its last line,
    /// "6、依臺北市政府核定之本件細", and pages 8 to 16 ran a line late.)
    func _noteCuts(_ id: Int, width: Double, _ document: RichDocument) -> [Double] {
        guard let note = _note(id, width: width, document) else { return [] }
        var out: [Double] = []
        for k in note.document.paragraphs.indices {
            let g = note.layout.geometry(k)
            var bs = Self._lineBottoms(g.painter).map { g.textTop + $0 }
            // (A note under widow control parts with two lines at least on
            // each side, or at the end of a paragraph: xa gv-690391482c's
            // footnote 13, two lines, goes whole to page 9 in Word's print
            // where its mark's line ends page 8, and its footnote 24, five
            // lines, does not keep a first line alone on page 13 (its mark's
            // paragraph goes to page 14). Four lines part two and two: xd
            // e50792c2's footnote 7.)
            if theme.wordRules, note.document.paragraphs[k].style.widowControl, !document.widowControlSuspended, bs.count > 1 {
                let n = bs.count
                bs = bs.enumerated().filter { $0.offset != 0 && $0.offset != n - 2 }.map { $0.element }
            }
            out += bs
        }
        // (Not at its last line's bottom: that leaves nothing for the next
        // page, so it is no parting, and the note's space after counts as
        // part of it.)
        let lastBottom = out.max() ?? 0
        let cuts = out.sorted().filter { $0 > 0.5 && $0 < note.height - 0.5 && $0 < lastBottom - 0.5 }
        // (A note of a page of columns parts with two lines at least on each
        // side: Word's lab fn-cols-sweep, a mark's note that would keep one
        // line goes over with the mark's line whole.)
        return _slotNotes ? Array(cuts.dropFirst().dropLast()) : cuts
    }

    /// A sub-document of `paragraphs` that reads its settings from
    /// `document`, laid out `width` wide.
    func _subLayout(_ paragraphs: [RichParagraph], _ document: RichDocument, width: Double, onGrid: Bool = false) -> _HeaderFooter {
        var sub = RichDocument(paragraphs: paragraphs.isEmpty ? [RichParagraph()] : paragraphs)
        sub.styles = document.styles
        sub.fontUsb0 = document.fontUsb0
        // (The font table too: a note whose face the table names must not read as a face Word lacks, now that the file flag reaches it; dx2-class xd 4fabe1f2's Hamchorom footnotes.)
        sub.fontCharsets = document.fontCharsets
        sub.fontAlternates = document.fontAlternates
        sub.hasIndicText = document.hasIndicText
        sub.devanagariFirstRunMangal = document.devanagariFirstRunMangal
        // (A page break inside a note starts nothing new — the note is one
        // paragraph to Word, its line following at a line's pitch, none of
        // the paragraph's space between: lo-ccca8bf3's second endnote sets
        // its Latin line 16pt under the Hebrew one, ours 25.)
        if theme.wordRules {
            for k in sub.paragraphs.indices.dropFirst() where sub.paragraphs[k].style.pageBreakBefore && !sub.paragraphs[k].style.columnBreak {
                sub.paragraphs[k - 1].style.spaceAfter = 0
                sub.paragraphs[k].style.spaceBefore = 0
            }
        }
        // (Notes keep to the document's line grid, as a header does not;
        // their separator does not. Lab `fn` (Word for Windows, from
        // zh-344a8d08's package, linesAndChars at 22.85pt): its 10pt
        // notes stand 22.8pt a line where their style drops snapToGrid 0
        // and their face's 17.16 where it keeps it, and the separator,
        // Normal's 16pt in an empty paragraph, is one natural line either
        // way.)
        if onGrid {
            sub.lineGridPitch = document.lineGridPitch
            sub.characterGridSpace = document.characterGridSpace
            sub.characterGridCellBase = document.characterGridCellBase
        }
        sub.listFormats = document.listFormats
        sub.listCounterOf = document.listCounterOf
        sub.listRestarts = document.listRestarts
        sub.usesEastAsianLayout = document.usesEastAsianLayout
        sub.hasKana = document.hasKana
        sub.hangsLatinStops = document.hangsLatinStops
        sub.hangsStopsMinorEA = document.hangsStopsMinorEA
        sub.indentNotNumberingTabStop = document.indentNotNumberingTabStop
        sub.characterSpacingControl = document.characterSpacingControl
        sub.kernsPunctuation = document.kernsPunctuation
        sub.balancesSpaceWidth = document.balancesSpaceWidth
        sub.joinsHanAfterSpace = document.joinsHanAfterSpace
        sub.compatibilityMode = document.compatibilityMode
        sub.hangsHalf = document.hangsHalf
        sub.breakRulesOnlyForEastAsian = document.breakRulesOnlyForEastAsian
        sub.defaultLangXML = document.defaultLangXML
        sub.htmlAutoSpacing = document.htmlAutoSpacing
        sub.defaultTabStop = document.defaultTabStop
        sub.readFromFile = document.readFromFile
        let layout = RichLayout(theme: theme, paragraphCount: sub.paragraphs.count)
        layout.scale = scale
        layout.width = max(1, width)
        layout.ensureLaidOut(sub)
        return _HeaderFooter(layout: layout, document: sub)
    }

    /// Footnote `id` laid out `width` wide (pixels), or nil where the
    /// file has no such note. id -1 is the separator above them.
    func _note(_ id: Int, width: Double, _ document: RichDocument) -> _HeaderFooter? {
        let key = "\(id)|\(width)|\(scale)"
        if let hit = _noteCache[key] { return hit }
        let paragraphs: [RichParagraph]
        if id == -1 { paragraphs = document.footnoteSeparator } else if let p = document.footnotes[id] { paragraphs = p } else { return nil }
        let made = _subLayout(paragraphs, document, width: width, onGrid: theme.wordRules && id != -1)
        if _noteCache.count > 512 { _noteCache.removeAll() }
        _noteCache[key] = made
        return made
    }

    /// Endnote `id` laid out `width` wide, as `_note` does a footnote;
    /// id -1 is the separator above them.
    func _endnote(_ id: Int, width: Double, _ document: RichDocument) -> _HeaderFooter? {
        let key = "e\(id)|\(width)|\(scale)"
        if let hit = _noteCache[key] { return hit }
        let paragraphs: [RichParagraph]
        if id == -1 { paragraphs = document.endnoteSeparator } else if let p = document.endnotes[id] { paragraphs = p } else { return nil }
        let made = _subLayout(paragraphs, document, width: width, onGrid: theme.wordRules && id != -1)
        if _noteCache.count > 512 { _noteCache.removeAll() }
        _noteCache[key] = made
        return made
    }

    /// The paragraphs of the section that ends just before paragraph `i` (its last paragraph and those above it in
    /// the section), or nil where `i` does not begin a section.
    func _sectionEndingBefore(_ i: Int) -> Range<Int>? {
        guard i > 0, i < _sectionOf.count, _sectionOf[i] != _sectionOf[i - 1] else { return nil }
        var first = i - 1
        while first > 0, first - 1 < _sectionOf.count, _sectionOf[first - 1] == _sectionOf[i - 1] { first -= 1 }
        return first ..< i
    }

    /// The endnote ids whose marks are in `paragraphs`, in order.
    func _endnoteIDs(in paragraphs: Range<Int>, _ document: RichDocument) -> [Int] {
        var out: [Int] = []
        for k in paragraphs where k < document.paragraphs.count {
            for run in document.paragraphs[k].runs {
                if let n = run.style.note, n.kind == .endnote, document.endnotes[n.id] != nil, !out.contains(n.id) { out.append(n.id) }
            }
        }
        return out
    }

    /// Endnotes at a section's end take their room in the flow, under its last paragraph: the separator and the
    /// notes (Word for Windows, lo-99590fe5: the section's endnote stands between "Second section" and "Third
    /// section", which moves down by it).
    func _sectionEndnotesHeight(before i: Int, _ document: RichDocument) -> Double {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, document.endnotesAtSectionEnd, let range = _sectionEndingBefore(i) else { return 0 }
        let ids = _endnoteIDs(in: range, document)
        guard !ids.isEmpty else { return 0 }
        let width = _px(_setup(ofParagraph: i - 1).contentWidth)
        let notes = ids.compactMap { _endnote($0, width: width, document) }
        return notes.reduce(0.0) { $0 + $1.height } + (_endnote(-1, width: width, document)?.height ?? 0)
    }

    /// The endnotes in the order their marks come in the body.
    func _endnoteOrder(_ document: RichDocument) -> [Int] {
        guard !document.endnotes.isEmpty else { return [] }
        var out: [Int] = []
        for p in document.paragraphs {
            for run in p.runs {
                if let n = run.style.note, n.kind == .endnote, document.endnotes[n.id] != nil, !out.contains(n.id) { out.append(n.id) }
            }
        }
        return out
    }

    /// The footnotes whose marks paragraph `i` holds, in its order.
    func _footnotes(in i: Int, _ document: RichDocument) -> [Int] {
        guard i >= 0, i < document.paragraphs.count else { return [] }
        var out: [Int] = []
        for run in document.paragraphs[i].runs {
            if let n = run.style.note, n.kind == .footnote, document.footnotes[n.id] != nil, !out.contains(n.id) { out.append(n.id) }
        }
        // (A small table nested in a cell is a block laid out apart, and its
        // marks are its paragraph's: lo-f47abfe0's "Number of vesting lots"
        // marks footnote 2, which Word sets at page 1's foot, taking the
        // room of the next row; ours never set it.)
        if let box = document.paragraphs[i].image?.textBox, box.growsToFit {
            var stack = box.paragraphs
            while let q = stack.popLast() {
                for run in q.runs {
                    if let n = run.style.note, n.kind == .footnote, document.footnotes[n.id] != nil, !out.contains(n.id) { out.append(n.id) }
                }
                if let inner = q.image?.textBox, inner.growsToFit { stack.append(contentsOf: inner.paragraphs) }
            }
        }
        return out
    }

    /// Where footnote `id`'s mark stands in paragraph `i`'s flow: the top
    /// of the line that holds it, or nil.
    func _footnoteMarkTop(_ i: Int, _ id: Int, _ document: RichDocument) -> Double? {
        _footnoteMarkLine(i, id, document)?.top
    }

    /// The line that holds footnote `id`'s mark in paragraph `i`, in flow
    /// terms (its top and bottom), or nil.
    func _footnoteMarkLine(_ i: Int, _ id: Int, _ document: RichDocument) -> (top: Double, bottom: Double)? {
        var at = 0
        for run in document.paragraphs[i].runs {
            if let n = run.style.note, n.kind == .footnote, n.id == id {
                let g = geometry(i)
                let m = _map(i).painter(at)
                // (A mark raised out of its line, `_paintScripts`'s, has no
                // box of its own there: the character beside it stands on
                // its line. zh-344a8d08's footnotes 2 and 3 were taken for
                // marks of no line, reserved whole, and note 3's three
                // lines all stood on page 4, where Word's print parts it.)
                func boxOf(_ from: Int, _ to: Int) -> TextBox? {
                    guard from >= 0, to > from else { return nil }
                    return g.painter.getBoxesForSelection(TextSelection(baseOffset: from, extentOffset: to)).first
                }
                guard let box = boxOf(m, m + max(1, run.length)) ?? (theme.wordRules ? boxOf(m - 1, m) ?? boxOf(m + max(1, run.length), m + max(1, run.length) + 1) : nil)
                else { return nil }
                let lines = g.painter.computeLineMetrics()
                // (Where the line ends as the page counts it — on a grid,
                // its whole pitches, not the engine's own line: zh-344a8d08's
                // note 3 is marked in a 16pt line of two 22.85pt pitches,
                // 45.7, whose engine line is 37.5; the note fit under it by
                // 4pt in ours and goes over by 4 in Word's print.)
                let bottoms = theme.wordRules ? Self._lineBottoms(g.painter) : []
                var bottom = box.bottom
                for (k, metrics) in lines.enumerated() where metrics.lineNumber >= 0 {
                    let top = metrics.baseline - metrics.ascent
                    if box.top >= top - 0.5, box.top < top + metrics.height - 0.5 {
                        bottom = max(bottom, k < bottoms.count ? bottoms[k] : top + metrics.height)
                    }
                }
                return (g.textTop + box.top, g.textTop + bottom)
            }
            at += run.length
        }
        return nil
    }

    /// A text box's text, laid out at the box's width inside its insets.
    /// The paragraph an image with this id stands in, inline or as its
    /// own (the first one, if a copy stands in more).
    func _paragraphHolding(_ id: String, _ document: RichDocument) -> Int? {
        if _imageParagraphs == nil {
            var map: [String: Int] = [:]
            for (i, p) in document.paragraphs.enumerated() {
                if let image = p.image, map[image.id] == nil { map[image.id] = i }
                for image in p.inlineImages.inOrder where map[image.id] == nil { map[image.id] = i }
            }
            _imageParagraphs = map
        }
        return _imageParagraphs?[id]
    }

    func _textBox(_ image: ImageAttachment, _ document: RichDocument) -> _HeaderFooter? {
        guard theme.wordRules, let box = image.textBox else { return nil }
        let holding = _paragraphHolding(image.id, document)
        let grid = image.name == "combine" && !box.growsToFit ? (pitch: nil, chars: nil) : _grid(holding, document)
        // A fixed parent sets its nested table's available width. Word
        // keeps the child's preferred width, even when an inline picture
        // or a long word overflows it; a percentage is of the parent
        // cell, not the child's saved grid (nested-minima Word labs).
        let fixedParent = box.growsToFit && holding.flatMap { document.paragraphs[$0].cell }.map {
            _nestedInFixedTable || document.tableStyles[$0.table]?.fixedLayout == true
        } == true
        // (So does an autofitting one, at its column as fitted, which a
        // picture beside it may have narrowed: lab dr2/h's 100% child
        // holding a 150pt picture, beside a 306pt logo, ends at the page's
        // 552.8 in Word's print, where ours, at the child's saved 171.6,
        // ran 10pt past it. Not before its cell is laid out.)
        let fitted = box.growsToFit && holding.flatMap { document.paragraphs[$0].cell } != nil
            ? holding.flatMap { $0 < _textWidth.count && _textWidth[$0] > 0 ? _textWidth[$0] / _px(1) : nil } : nil
        let boxWidth = fixedParent && holding != nil ? _textWidth[holding!] / _px(1) : fitted ?? image.width
        // (An autofitting parent that spans its page's text already has no
        // room to give a child that would grow: Word keeps the child at its
        // saved grid and lets its content overflow. drawing.docx's p9
        // banner table, 171.6pt in the 467.8pt parent beside a 303.75pt
        // logo, holds a 177pt picture, and Word's print keeps the table and
        // its right-set banner at 171.6; ours grew it to 177 and the banner
        // stood 5.4pt right. A parent with room grows with the child — the
        // nested-minima labs' 200pt child in a 200pt autofitting parent,
        // 241.5 in Word's print.)
        var cap: Double? = nil
        if theme.wordRules, box.growsToFit, !fixedParent, let k = holding, let parent = document.paragraphs[k].cell,
           let columns = _columnWidths[parent.table], let setup = pageSetup,
           columns.reduce(0, +) >= _px(setup.contentWidth) - _px(1) {
            cap = _px(image.width)
        }
        let key = "\(image.id)|\(boxWidth)|\(fixedParent)|\(cap ?? 0)|\(scale)|\(box.hashValue)|\(grid.pitch ?? 0)|\(grid.chars ?? 0)"
        if let hit = _textBoxCache[key] { return hit }
        var sub = RichDocument(paragraphs: box.paragraphs)
        sub.styles = document.styles
        sub.fontUsb0 = document.fontUsb0
        sub.listFormats = document.listFormats
        sub.listCounterOf = document.listCounterOf
        sub.listRestarts = document.listRestarts
        sub.usesEastAsianLayout = document.usesEastAsianLayout
        sub.hasKana = document.hasKana
        sub.hangsLatinStops = document.hangsLatinStops
        sub.hangsStopsMinorEA = document.hangsStopsMinorEA
        sub.indentNotNumberingTabStop = document.indentNotNumberingTabStop
        sub.characterSpacingControl = document.characterSpacingControl
        sub.kernsPunctuation = document.kernsPunctuation
        sub.balancesSpaceWidth = document.balancesSpaceWidth
        sub.joinsHanAfterSpace = document.joinsHanAfterSpace
        sub.compatibilityMode = document.compatibilityMode
        sub.hangsHalf = document.hangsHalf
        sub.breakRulesOnlyForEastAsian = document.breakRulesOnlyForEastAsian
        sub.defaultLangXML = document.defaultLangXML
        sub.htmlAutoSpacing = document.htmlAutoSpacing
        sub.defaultTabStop = document.defaultTabStop
        sub.tableStyles = box.tableStyles
        sub.tableColumns = box.tableColumns
        // (A box's text keeps to its section's grid, as the page's does:
        // zh-454e2e29's nested form, its rows of 14pt 標楷體 two 18pt
        // pitches each in Word's print, came out 33pt short, and the
        // labels "人數", "官等" and "類別" of its diagonal header cell —
        // 12pt YaHei, two pitches, centred — stood 8pt high. The two
        // lines in one of `w:combine` stand on the line's own grid. The
        // section is the anchor's: zh-6cd1befe's flow chart stands in a
        // section of no grid, and on the last section's its 22pt title
        // went 4pt low.)
        sub.lineGridPitch = grid.pitch
        sub.characterGridSpace = grid.chars
        // (A group whose boxes stand beside one another — one starts
        // above the foot of the one before — cannot be one flow: each of
        // its later boxes is laid out alone and painted at its place.
        // zh-06c46ba9's tree of labels sets four boxes in a row, and the
        // flow stacked them, each under the last, 140pt down the page.)
        var parts = box.parts
        // (A group sized as a share of the margins' room: its boxes' tops
        // and heights go with it, as its coordinates scale.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, parts.count > 1, let fl = image.float, let share = fl.heightShare,
           image.height > 0, let k = holding {
            let setup = _setup(ofParagraph: k)
            let span = fl.heightFrom == "page" ? setup.height : setup.height - setup.marginTop - setup.marginBottom
            let ratio = share * span / image.height
            if ratio > 0, abs(ratio - 1) > 0.0001 {
                RuleTrace.hit("vml-group-height-is-a-share-of-the-margins")
                for n in parts.indices { parts[n].top *= ratio; parts[n].height *= ratio }
            }
        }
        var beside: [(layout: RichLayout, document: RichDocument, dy: Double, turn: (degrees: Double, x: Double, y: Double)?)] = []
        if parts.count > 1, (1 ..< parts.count).contains(where: { parts[$0].rotation != 0 || parts[$0].top < parts[$0 - 1].top + parts[$0 - 1].height - 0.5 }) {
            let all = sub.paragraphs
            for n in (parts[0].rotation != 0 ? 0 : 1) ..< parts.count where parts[n].first < all.count {
                let end = n + 1 < parts.count ? min(all.count, parts[n + 1].first) : all.count
                guard end > parts[n].first else { continue }
                var own = sub
                own.paragraphs = Array(all[parts[n].first ..< end])
                let alone = RichLayout(theme: theme, paragraphCount: own.paragraphs.count)
                alone.scale = scale
                alone.width = max(1, _px(image.width - box.insetLeft - box.insetRight))
                alone.ensureLaidOut(own)
                var dy = _px(parts[n].top - box.insetTop)
                if parts[n].atFoot { dy += _px(parts[n].height) - alone.totalHeight }
                if parts[n].inMiddle { dy += max(0, _px(parts[n].height) - alone.totalHeight) / 2 }
                beside.append((alone, own, dy, parts[n].rotation == 0 ? nil : (parts[n].rotation, _px(parts[n].pivotX), _px(parts[n].pivotY))))
            }
            sub.paragraphs = parts[0].rotation != 0 ? [] : Array(all[0 ..< min(all.count, parts[1].first)])
            parts = [parts[0]]
        }
        // (Each shape of a group is its own box in Word's print: the space
        // after the last paragraph of one does not push the next shape down.
        // dx2 2263e221's three stacked boxes, each with the default 8pt
        // after, stood 3.8pt low in ours.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, parts.count > 1 {
            for n in 1 ..< parts.count where parts[n].first > 0 && parts[n].first <= sub.paragraphs.count {
                sub.paragraphs[parts[n].first - 1].style.spaceAfter = 0
            }
        }
        var layout = RichLayout(theme: theme, paragraphCount: sub.paragraphs.count)
        layout.scale = scale
        layout._nestedInFixedTable = fixedParent
        layout._nestedBlock = box.growsToFit && holding.flatMap { document.paragraphs[$0].cell } != nil
        if theme.wordRules, RichTextTheme.wordWindowsPages, box.growsToFit, image.float == nil, let k = holding, let cell = document.paragraphs[k].cell {
            var above = 0.0
            var m = k - 1
            while m >= 0, let c = document.paragraphs[m].cell, c.table == cell.table, c.row == cell.row, c.column == cell.column {
                // (Not laid out yet, an empty paragraph is its mark's line.)
                if document.paragraphs[m].image?.float == nil {
                    above += m < _heights.count && _heights[m] > 0 ? _heights[m]
                        : document.paragraphs[m].text.isEmpty && document.paragraphs[m].image == nil ? _markLineHeight(m, document) : 0
                }
                m -= 1
            }
            var q = k + 1
            while q < document.paragraphs.count, let c = document.paragraphs[q].cell, c.table == cell.table, c.row == cell.row, c.column == cell.column {
                if let fi = document.paragraphs[q].image, let f = fi.float, f.fromCellTop, f.wraps, fi.textBox?.growsToFit == true,
                   let inside = _textBox(fi, document) {
                    let top = _px(f.y) - above
                    layout._avoidBands.append((top, top + inside.height + _px(fi.effectBottom + f.distanceBottom)))
                } else if let fi = document.paragraphs[q].image, let f = fi.float, f.againstText, f.wraps, fi.name == "table", fi.textBox?.growsToFit == true,
                          let inside = _textBox(fi, document) {
                    // (The lines between the block and its anchor, which are not laid out yet, count as one each.)
                    var between = 0.0
                    for mm in k + 1 ..< q where document.paragraphs[mm].image?.float == nil {
                        between += mm < _heights.count && _heights[mm] > 0 ? _heights[mm] : _markLineHeight(mm, document)
                    }
                    layout._followBands.append((_px(f.y) + between, inside.height + _px(fi.effectBottom + f.distanceBottom)))
                }
                q += 1
            }
            layout._avoidBands.sort { $0.top < $1.top }
        }
        layout._nestedNarrowed = fitted.map { $0 < image.width - 0.5 } ?? false
        layout._nestedCap = cap
        // (Turned, its lines run along the box's height.)
        layout._turnedBox = box.textDirection != .horizontal
        layout._inTextBox = true
        layout._boxText = true
        if _canCorrectFixedBoxIndent(box) {
            let inset = box.textDirection == .horizontal ? box.insetLeft
                : box.textDirection == .up ? box.insetBottom : box.insetTop
            let extent = box.textDirection == .horizontal ? boxWidth : image.height
            layout._fixedTextFrame = (-_px(inset), _px(extent - inset))
        }
        layout.width = box.textDirection == .horizontal ? max(1, _px(boxWidth - box.insetLeft - box.insetRight))
            : max(1, _px(image.height - box.insetTop - box.insetBottom))
        layout.ensureLaidOut(sub)
        // (A box of a fixed frame whose text is anchored in its middle or at
        // its foot stands there in Word for Windows' print: zh-291fcea7's
        // flowchart "4.人力資源管理資訊系統WebHR線上報送敘薪…" in its
        // multi-document shape, and "6.製發敘薪通知書" in its document
        // shape, stand 8 and 7.7pt lower than the top their text rectangle
        // gives; ours set them at the top.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, let anchor = box.anchor, box.textDirection == .horizontal, box.parts.isEmpty,
           box.hasFixedFrame, !box.fitsHeight, !box.growsToFit, !sub.paragraphs.isEmpty {
            let room = _px(image.height - box.insetTop - box.insetBottom)
            let slack = room - layout.totalHeight
            if slack > 0.01 {
                sub.paragraphs[0].style.spaceBefore += (anchor == "ctr" ? slack / 2 : slack) / _px(1)
                let width = layout.width
                layout = RichLayout(theme: theme, paragraphCount: sub.paragraphs.count)
                layout.scale = scale
                layout._boxText = true
                layout.width = width
                layout.ensureLaidOut(sub)
            }
        }
        // (The later boxes of a group, each from its own place in it:
        // its first paragraph set down to where the box stands, or to
        // where its text reaches the box's foot.)
        // (Measured at its text, and again until it stands there: the
        // space before it is shared with the space after the paragraph
        // above — another box's — and shapes-with-text's box under its
        // arrow stood 8pt high, the arrow's 8pt after taken out of it.)
        for (n, part) in parts.enumerated() where part.first < sub.paragraphs.count && part.first < layout._tops.count {
            let end = n + 1 < parts.count ? parts[n + 1].first : sub.paragraphs.count
            let own = layout._spaceBefore[part.first]
            for _ in 0 ..< 3 {
                let top = layout._tops[part.first]
                let bottom = end < layout._tops.count ? layout._tops[end] : layout.totalHeight
                var want = _px(part.top - box.insetTop)
                // (A box fitted to its text has no foot to stand at: it is as
                // tall as its text, which stands from its top. lab grp2,
                // lo-0622682c's bottom-anchored "TEXT3" box.)
                if part.atFoot { want += _px(part.height) - (bottom - top) }
                if part.inMiddle { want += max(0, _px(part.height) - (bottom - top)) / 2 }
                let delta = want + own - (top + layout._spaceBefore[part.first])
                guard delta > 0.01 else { break }
                sub.paragraphs[part.first].style.spaceBefore += delta / _px(1)
                let width = layout.width
                layout = RichLayout(theme: theme, paragraphCount: sub.paragraphs.count)
                layout.scale = scale
                layout._boxText = true
                layout.width = width
                layout.ensureLaidOut(sub)
            }
        }
        // (A box that takes its text's width: as wide as its longest
        // line — zh-1a3c7aa0's footer page number, in a 144pt box set
        // to fit its text and centred, stands at the page's middle in
        // Word's print, where the whole box centred put it 65pt left.)
        if box.fitsText, box.fitsOnce, let w = inheritedFitWidths[image.id] {
            // (A header's or footer's box as wide as on the first page it
            // is on — lab `ftD`, Word 16, 2026-10-15: zh-a4b0f6ea's
            // "— PAGE —", fit to its text without wrapping, first drawn
            // on page 2, wraps its closing dash under "— 10" on every
            // two-digit even page; numbered from 8, so that it first
            // stands on page 10, no even page wraps and the odd ones,
            // first on 9, all do. The cached result is not what it is
            // sized by: changing it changes nothing.)
            // (Wrapped only at a space: "-10-" in a box sized by "-1-"
            // runs out of it whole in Word's prints of zh-c3dd22c4,
            // zh-1563bd74, zh-9dd9ce6d and zh-1a3c7aa0, where the engine
            // parted it and the footer grew a line. The box is no
            // narrower than a paragraph's longest unbreakable piece.)
            // (Set in Latin faces alone, a paragraph is one piece and
            // runs out of the box whole: zh-01071d55's Times "- 10 -", 7pt
            // over, is drawn whole in Word's print, clipped at the box.
            // With a character in an East Asian face its spaces give half
            // their width before it parts — lab `vf` (Word 16,
            // 2026-10-18): zh-2e7ef069's 宋体 numberInDash box, sized by
            // "- 9 -", holds "- 10 -" to "- 99 -" whole, 7 over and its
            // two 7pt spaces halved, and parts "- 100 -", 14 over, at its
            // space; zh-5a9a85c6's VML "— 11 —" stands in the 49pt
            // "— 1 —" set, its 宋体 spaces halved, where zh-875759ff's first print,
            // its em dashes in YaHei and its spaces Times' 3.5pt, parts
            // before the closing dash. Not a closing space, which hangs,
            // and not one beside a character set as East Asian, which
            // gives nothing: zh-a4b0f6ea's "— 10 —", its dashes hinted
            // East Asian, parts, and so does zh-9bcea239's VML "—10—",
            // spaceless. Laid out whole, the line runs past the box, which
            // stands as wide as on its first page.)
            let room = w - _px(box.insetLeft + box.insetRight)
            var need = 0.0, whole = 0.0
            for k in 0 ..< sub.paragraphs.count {
                let g = layout.geometry(k)
                let para = sub.paragraphs[k]
                let named = layout._named(para, sub)
                // (With its right indent, as the box fitted each time
                // takes it — below: zh-9c162f26's "— PAGE —", a character
                // in from each side, its runs Times hinted "default", is
                // whole on every page of Word's print; widened for "— 10 —"
                // by its left indent alone, ours wrapped the closing dash.)
                let right = k < layout._textWidth.count ? max(0, layout.width - g.textLeft - layout._textWidth[k]) : 0
                let line = g.painter.maxIntrinsicWidth + g.textLeft + right
                let units = Array(para.text.utf16)
                var hintedAt = Set<Int>(), latinAt = Set<Int>(), eastAsianFace = false, at = 0
                for run in para.runs {
                    // (A run hinted East Asian whose East Asian face is itself a Latin one is set in it: zh-ee2d19e6's
                    // footer "— 10 —", dashes hinted East Asian over `w:eastAsia` "Times New Roman", stands whole in Word's
                    // print where zh-a4b0f6ea's, over a CJK face, parts.)
                    let eaIsLatin = run.style.eastAsiaFontFamily.flatMap { theme.faceResolver?($0, false) }?.isEastAsian == false
                    if run.style.fontHint == "eastAsia", !eaIsLatin { hintedAt.formUnion(at ..< at + run.length) }
                    if run.style.fontHint == "default" || (run.style.fontHint == "eastAsia" && eaIsLatin) { latinAt.formUnion(at ..< at + run.length) }
                    let latin = run.style.fontFamily ?? named?.char.fontFamily ?? theme.fontFamily
                    if theme.faceResolver?(latin, false)?.isEastAsian == true { eastAsianFace = true }
                    at += run.length
                }
                func setEastAsian(_ i: Int) -> Bool {
                    guard i >= 0, i < units.count, let scalar = Unicode.Scalar(units[i]) else { return false }
                    return Self.isEastAsian(Character(scalar), hinted: hintedAt.contains(i))
                }
                // (An em dash is the East Asian face's but where its run
                // says `w:hint` "default" in a DrawingML box: zh-57f1de0d's,
                // zh-08dc38da's and zh-f1f73836's "— 17 —", Times with that
                // hint, stand whole in Word's prints, where ours parted the
                // closing dash on every two-digit page. Not in VML's:
                // zh-875759ff's even pages, the same runs in a VML box sized
                // by "— 2 —", part "— 10" / "—".)
                let latinDashes = box.fitsAsDrawing ? latinAt : []
                // (A paragraph of a Chinese face with no space and no East Asian
                // character has nowhere to part: zh-0a56c942's page number "10", digits
                // in a 4.6pt box fitted by "9", is one line in Word's print where
                // ours set "1" over "0".)
                let anyEastAsian = (eastAsianFace && (!RichTextTheme.wordWindowsPages || units.contains(0x20))) || units.indices.contains { setEastAsian($0) || (units[$0] == 0x2014 && !latinDashes.contains($0)) }
                var spaces = 0.0
                if anyEastAsian, line > room + 0.5 {
                    let map = layout._map(k)
                    let end = units.lastIndex { $0 != 0x20 } ?? 0
                    // (A run of spaces is beside the dash when either end of the run is.)
                    func dashBeside(_ off: Int) -> Bool {
                        func dash(_ i: Int) -> Bool { i >= 0 && i < units.count && units[i] == 0x2014 && !latinDashes.contains(i) }
                        var a = off, b = off
                        while a > 0, units[a - 1] == 0x20 { a -= 1 }
                        while b + 1 < units.count, units[b + 1] == 0x20 { b += 1 }
                        return dash(a - 1) || dash(b + 1)
                    }
                    // (An un-hinted em dash is East Asian here too, and gives nothing beside it: zh-5be7e156's "—  11  —".)
                    for (off, u) in units.enumerated() where u == 0x20 && off < end && !setEastAsian(off - 1) && !setEastAsian(off + 1)
                        && !(RichTextTheme.wordWindowsPages && box.fitsAsDrawing && dashBeside(off)) {
                        let a = map.painter(off)
                        for b in g.painter.getBoxesForSelection(TextSelection(baseOffset: a, extentOffset: a + 1)) { spaces += b.right - b.left }
                    }
                }
                if !anyEastAsian || line - spaces / 2 <= room + 0.5 { whole = max(whole, line) }
                else { need = max(need, g.painter.minIntrinsicWidth + g.textLeft + right) }
            }
            layout.width = max(1, room, need.rounded(.up) + (need > 0 ? 1 : 0), whole.rounded(.up) + (whole > room + 0.5 ? 1 : 0))
            layout.ensureLaidOut(sub)
            _fitWidths["\(image.id)|\(box.hashValue)"] = max(room, need.rounded(.up) + (need > 0 ? 1 : 0)) + _px(box.insetLeft + box.insetRight)
        } else if box.fitsText {
            // (A paragraph with no space and no East Asian character stands on one line in a box
            // fitted to its text, wider than the box was sized for: zh-0a56c942's page number "10"
            // in a 4.6pt box fitted by "9", one line in Word's print, "1" over "0" here.)
            if theme.wordRules, RichTextTheme.wordWindowsPages {
                var wide = 0.0
                for k in 0 ..< sub.paragraphs.count where !sub.paragraphs[k].text.isEmpty
                    && !sub.paragraphs[k].text.unicodeScalars.contains(where: { ($0.value == 0x20 && !box.fitsOnce) || $0.value >= 0x2E80 }) {
                    let g = layout.geometry(k)
                    let right = k < layout._textWidth.count ? max(0, layout.width - g.textLeft - layout._textWidth[k]) : 0
                    wide = max(wide, g.painter.maxIntrinsicWidth + g.textLeft + right)
                }
                if wide > layout.width + 0.5 {
                    layout.width = wide.rounded(.up) + 1
                    layout.ensureLaidOut(sub)
                }
            }
            var natural = 0.0
            for k in 0 ..< sub.paragraphs.count {
                let g = layout.geometry(k)
                // (Its right indent too: zh-9e8c1a98's "— PAGE —" has a
                // character and a half in from each side of a box fitted
                // to it, and stands whole in Word's print; fitted to the
                // text and the left indent alone, its closing dash wrapped.)
                let right = k < layout._textWidth.count ? max(0, layout.width - g.textLeft - layout._textWidth[k]) : 0
                for line in g.painter.computeLineMetrics() { natural = max(natural, line.width + g.textLeft + right) }
            }
            if natural > 0, natural < layout.width - 0.5 {
                layout.width = natural.rounded(.up) + 1
                layout.ensureLaidOut(sub)
            }
            _fitWidths["\(image.id)|\(box.hashValue)"] = layout.width + _px(box.insetLeft + box.insetRight)
        }
        var made = _HeaderFooter(layout: layout, document: sub)
        made.beside = beside
        if _textBoxCache.count > 256 { _textBoxCache.removeAll() }
        _textBoxCache[key] = made
        return made
    }

    /// Where a floating object stands, in the layout's own space, given
    /// the paragraph it is anchored to: by its offsets from the column
    /// or the paragraph, or set left, centre or right in the column (or
    /// the page, where `frameMargins` says how far that reaches).
    func _floatRect(_ float: ImageFloat, _ image: ImageAttachment, _ g: ParagraphGeometry, _ i: Int) -> Rect {
        // (A fit-to-text box that outgrew its stored width stands as wide as its text: zh-2e7ef069's
        // "- 11 -" in a 36pt box is set from the margin at 479 in Word's print, 42pt in.)
        let fitted = image.textBox.flatMap { _fitWidths["\(image.id)|\($0.hashValue)"] }
        let w = theme.wordRules && RichTextTheme.wordWindowsPages && image.textBox?.fitsOnce == true
            ? (fitted ?? _px(image.width)) : min(_px(image.width), fitted ?? .infinity)
        var h = _px(image.height)
        // The page it stands on, in pixels: a header's or footer's from
        // the page it is painted on, a body paragraph's from its section.
        let page: (height: Double, top: Double, bottom: Double) = {
            if floatsFrames, regionTopOnPage != nil { return (regionPageHeight, regionMarginTop, regionMarginBottom) }
            let setup = _setup(ofParagraph: i)
            return (_px(setup.height), _px(setup.marginTop), _px(setup.marginBottom))
        }()
        // (A share of the page's or margins' height, its effects within
        // it: 60316's header divider is 105% of 684pt of margins, 718.2,
        // and Word's print draws its line 716.4 long over a 1.8pt bottom
        // effect, centred on the page — 36.9 to 753.3. Ours drew the
        // file's 99pt extent from the header's top.)
        if theme.wordRules, let share = float.heightShare, page.height > 0 {
            let span = float.heightFrom == "page" ? page.height : page.height - page.top - page.bottom
            h = max(0, share * span - _px(float.effectBottom))
        }
        // The band it is placed in, from the paragraph's column edge.
        let column = _flowWidth(i)
        var bandLeft = g.textLeft - _textLeftInColumn(i), bandWidth = column
        if float.horizontalFrom == "page" || float.horizontalFrom == "leftMargin" {
            let setup = _setup(ofParagraph: i)
            let margins = floatsFrames ? frameMargins : (setup.marginLeft + setup.gutter, setup.marginRight)
            // (The page's edge, not the cell's text: a box placed from the
            // page, anchored in a table's cell, stands that far from the page
            // however far in the cell's text is — LibreOffice's tdf130120, a
            // box 511.3pt from the page's edge, 14pt (the table's indent and
            // the paragraph's) too far right.)
            if theme.wordRules, i < _cells.count, _cells[i] != nil { bandLeft = 0 }
            bandLeft -= _px(margins.0)
            bandWidth += _px(margins.0 + margins.1)
            // (Aligned within the left margin: the strip from the page's edge to the text.
            // zh-147bdae0's "附件4" box, right in it, stands by the left edge in Word's print.)
            if float.horizontalFrom == "leftMargin" { bandWidth = _px(margins.0) }
        }
        // (From the right margin: the strip between the text area and the page's right edge. f896e232's "Tamil" box, aligned
        // left in it, stands at 524 in Word's print; ours set it from the column's left edge, 78.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, float.horizontalFrom == "rightMargin", i >= _cells.count || _cells[i] == nil {
            RuleTrace.hit("float-from-right-margin-stands-in-that-strip")
            let setup = _setup(ofParagraph: i)
            let margins = floatsFrames ? frameMargins : (setup.marginLeft + setup.gutter, setup.marginRight)
            bandLeft += bandWidth
            bandWidth = _px(margins.1)
        }
        // (The margin is the text area across all its columns, not the
        // column the anchor stands in: lo-7afc5602's box, aligned right to
        // the margin, stands at the page's right margin in a 2-column
        // section, 423pt where the column's edge put it at 137.)
        if _perSection, float.horizontalFrom == "margin", !floatsFrames, i >= _cells.count || _cells[i] == nil {
            let setup = _setup(ofParagraph: i)
            bandWidth = _px(setup.contentWidth)
        }
        // (From a cell's own edges, not its text's: a floating table nested
        // in a cell — see the reader's `w:tblpPr`.)
        // (Not from its paragraph's line, which floats before it may have
        // moved: the cell's place itself.)
        if float.horizontalFrom == "cell", let d = _cells[i] {
            bandLeft = d.colLeft
            bandWidth = d.colWidth
            // (One placed against the page, from the margin, stands at its cell's text, not the side gap's
            // distance: lo-5c5eb1f7's calculator, tblpY 3028 against the page, has its text at 109, the
            // cell's 98.6 and its 5.4 and the table's own 5.4; the side gap's 9 put ours 4pt right.)
            if float.fromCellText, float.fromCellTop, theme.wordRules, RichTextTheme.wordWindowsPages {
                RuleTrace.hit("nested-table-page-anchored-margin-stands-at-cell-text")
                bandLeft += d.pad.left
                bandWidth -= d.pad.left
            } else if float.fromCellText, theme.wordRules, RichTextTheme.wordWindowsPages {
                RuleTrace.hit("nested-table-margin-anchor-keeps-its-side-gap")
                bandLeft += _px(float.distanceLeft ?? 0)
                bandWidth -= _px(float.distanceLeft ?? 0) + _px(float.distanceRight ?? 0)
            }
        }
        // (An object set from the "column" in a table's cell is set from the cell: Word for Windows'
        // print of lo-eb12e7d4 p13 centres its two figures each over its own cell, side by side;
        // ours centred both on the column, one over the other.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, float.horizontalFrom == "column", float.horizontalAlign == "center",
           i < _cells.count, let d = _cells[i], d.colWidth > 0 {
            bandLeft = d.colLeft
            bandWidth = d.colWidth
        }
        var x: Double
        // ("Outside" is the page's outer edge — the right on an odd page,
        // the left on an even one — and "inside" the other: zh-a4b0f6ea's
        // page numbers, in a box aligned outside, stand left on page 10
        // and right on 11 in Word's print.)
        let outside = leftHandFloat ? "left" : "right", inside = leftHandFloat ? "right" : "left"
        let align = float.horizontalAlign == "outside" ? outside : float.horizontalAlign == "inside" ? inside : float.horizontalAlign
        switch align {
        case "center": x = bandLeft + (bandWidth - w) / 2 + (theme.wordRules && !float.wraps ? _px(float.effectCentreShift) : 0)
        case "right": x = bandLeft + bandWidth - w
        case "left": x = bandLeft
        default: x = bandLeft + _px(float.x)
        }
        if theme.wordRules, _floatColumnShift != 0, float.horizontalFrom == "page", float.horizontalAlign == nil { x -= _floatColumnShift }
        // (A table floating in a cell from the margin, set out past the cell's right edge, is drawn back to fit
        // it, and no further left than the cell: lo-9fa3dedd's 255pt Table3, tblpX +21pt in a 234pt cell, has
        // its left rule on the cell's, 333.4; ours put it 30pt in, with the offset and the side gap.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, float.horizontalFrom == "cell", float.fromCellText, !float.fromCellTop,
           float.horizontalAlign == nil, float.x > 0, i < _cells.count, let d = _cells[i], x + w > d.colLeft + d.colWidth + 0.01 {
            RuleTrace.hit("nested-table-past-the-cell-is-drawn-back-to-fit-it")
            x = max(d.colLeft, d.colLeft + d.colWidth - w)
        }
        if float.horizontalAlign == nil, float.horizontalFrom == "character" { x = g.textLeft + _px(float.x) }
        // (From the character's own place: in a line set centred or right the
        // line's first box, not the paragraph's edge — zh-f47b8a74 p58's
        // canvas, 111pt left of the "重大行政执法…" title's first character,
        // stood 31pt off the page.)
        if theme.wordRules, float.horizontalAlign == nil, float.horizontalFrom == "character",
           g.painter.textAlign == .center || g.painter.textAlign == .right,
           let first = g.painter.computeLineMetrics().first {
            x = g.textLeft + first.left + _px(float.x)
        }
        let pushed = i < _floatPush.count ? _floatPush[i] : 0
        var y = g.textTop - pushed + (float.verticalAlign == nil && ["paragraph", "line"].contains(float.verticalFrom) ? _px(float.y) : 0)
        // (From the paragraph's top, its space before and all: Word's
        // print of zh-799c91cd sets its "【附件一之9】" boxes, 18pt above
        // pages' first paragraphs with 14pt of space before them, 18pt
        // above the margin — ours stood 15.5pt lower, measured from the
        // text under that space.)
        // (But not from space a page's top took away: zh-27a874b7's page 3
        // opens with a paragraph 9pt before, dropped there, and its chart,
        // 27.3pt down, stands 27.3 under the margin in Word's print, with
        // the before or without it (lab ss); ours stood 9pt higher.)
        if theme.wordRules, float.verticalAlign == nil, float.verticalFrom == "paragraph" {
            var top = g.top
            // (Not where the line went under this float: its place is the paragraph's
            // top, and the flow there is the line below it.)
            if let piece = _allPieces.first(where: { $0.paragraph == i && !$0.repeated }), piece.flowTop > top, !((float.takesRoom || float.bandsPage) && pushed > 0) { top = piece.flowTop }
            // (A paragraph that runs on into another column or page: Word
            // measures from the top of the part of it the anchor's line is
            // in — lo-ff3b52d1's rectangle, anchored near the end of a
            // paragraph three columns long, stands 81pt under the top of the
            // column its line is in.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, _columns > 1, float.horizontalAlign == nil, i < _cells.count, _cells[i] == nil,
               i < _inline.count, let k = _inline[i].firstIndex(where: { $0.id == image.id }), k < _inlineBoxes[i].count,
               let all = g.painter.inlinePlaceholderBoxes, _inlineBoxes[i][k] < all.count {
                let at = g.inkTop + all[_inlineBoxes[i][k]].top
                let mine = _allPieces.filter { $0.paragraph == i && !$0.repeated }
                if mine.count > 1, let piece = mine.last(where: { $0.flowTop <= at + 0.01 }), piece.flowTop > top {
                    RuleTrace.hit("word-float-is-set-from-the-part-of-its-paragraph-its-line-is-in")
                    top = piece.flowTop
                }
            }
            y = top + _px(float.y)
            if _atPageTopNegativeOffset(i, image) { y = top }
            // (Not for a float that takes its band of the flow: dx2 hi 87097d3e's group, top-and-bottom, 11pt
            // of space before its paragraph, stands 45.4pt under the paragraph's top, space and all, as Word.)
            // (Mid-page, from the text under the space before it: zh-4e5fe46f p6's
            // table, in a box anchored in a paragraph 3.5pt before, stands 3.5pt
            // lower in Word's print than from the paragraph's top.)
            if RichTextTheme.wordWindowsPages, image.textBox != nil, let piece = _allPieces.first(where: { $0.paragraph == i && !$0.repeated }),
               piece.pageY > _pxMarginTop(piece.page) + 1, g.textTop > top, g.textTop - top < _px(40), !(float.takesRoom || float.bandsPage) { y = g.textTop + _px(float.y) }
        }
        // (From the line: the top of the line the anchor stands in, not the paragraph's first line — dx2 es 335fbcf8's crest, 28.4pt
        // under a line, anchored in the title's second line, stands 14.3pt lower in Word's print than from the title's top.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, float.verticalAlign == nil, float.verticalFrom == "line", float.wraps == false, pushed == 0,
           i < _cells.count, _cells[i] == nil, i < _inline.count, let k = _inline[i].firstIndex(where: { $0.id == image.id }),
           k < _inlineBoxes[i].count, let all = g.painter.inlinePlaceholderBoxes, _inlineBoxes[i][k] < all.count {
            let box = all[_inlineBoxes[i][k]]
            let mid = (box.top + box.bottom) / 2
            if let line = g.painter.computeLineMetrics().last(where: { $0.baseline - $0.ascent <= mid + 0.01 }), line.lineNumber > 0 {
                RuleTrace.hit("word-float-from-a-line-is-set-from-the-line-its-anchor-is-in")
                y += line.baseline - line.ascent
            }
        }
        // (… where the paragraph's own line went under a float of its that
        // left it no room, one in front of the text goes with the line
        // (lab anch, Word for Windows: when the float is wrapped tight or through; under a
        // square wrap the box stays at the paragraph, lo-7b8ccfbe):
        // zh-d62da4dd's empty paragraphs each hold a chart wrapped tight,
        // 27.3pt down, and a "單位：張(人)數,%" box, 32.1pt down, which
        // Word's print sets under the chart, at the line's new place —
        // ours set it over the chart, and its page ran long.)
        // (Not one that bands the page, top and bottom: it holds its own
        // place, and the line goes under it — lo's c4c60fcb, a chart group
        // 9.5pt under an empty line, drew 294pt too low.)
        if theme.wordRules, !float.wraps, !float.takesRoom, !float.bandsPage, float.verticalAlign == nil, float.verticalFrom == "paragraph", pushed > 0,
           i < _floatTight.count, _floatTight[i] { y += pushed }
        // (A table floating in a cell from the page or margin stands its offset
        // under the cell's top, not under the paragraph its anchor is in.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, float.fromCellTop, float.horizontalFrom == "cell", i < _cells.count, let d = _cells[i] {
            y = _rowTops[i] + d.pad.top + _px(float.y)
        }
        // (From the page or its margin, a stated offset is on the page
        // the paragraph starts: zh-799c91cd's envelope addresses a box
        // 308.8pt under the margin, which ours stood at its paragraph,
        // 60pt below Word's.)
        if theme.wordRules, float.verticalAlign == nil, ["margin", "page", "topMargin"].contains(float.verticalFrom),
           let piece = _allPieces.first(where: { $0.paragraph == i && !$0.repeated }) {
            let physical = piece.page / _columns
            let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : 0
            let onPage = _px(float.y) - (float.verticalFrom == "margin" ? 0 : insetTop)
            y = piece.flowTop + onPage - piece.pageY
        }
        // (In a header or footer, from the page itself: zh-7773163d's
        // page numbers are text boxes 778pt down the page, and Word's
        // print has them there; ours stood at the footer's top, 8.6pt
        // lower.)
        if theme.wordRules, floatsFrames, let region = regionTopOnPage, float.verticalAlign == nil,
           float.verticalFrom == "page" || float.verticalFrom == "margin" {
            y = _px(float.y) + (float.verticalFrom == "margin" ? regionMarginTop : 0) - region
        }
        // (Aligned top, centre or bottom on the page or within its
        // margins, the box and its bottom effect together: 60316's
        // divider, centred on the page.)
        if theme.wordRules, let a = float.verticalAlign, ["top", "center", "bottom"].contains(a),
           float.verticalFrom == "page" || float.verticalFrom == "margin", page.height > 0 {
            let top = float.verticalFrom == "page" ? 0 : page.top
            let span = float.verticalFrom == "page" ? page.height : page.height - page.top - page.bottom
            let whole = h + _px(float.effectBottom)
            let onPage = top + (a == "center" ? (span - whole) / 2 : a == "bottom" ? span - whole : 0)
            if floatsFrames, let region = regionTopOnPage {
                y = onPage - region
            } else if !floatsFrames, let piece = _allPieces.first(where: { $0.paragraph == i && !$0.repeated }) {
                let physical = piece.page / _columns
                let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : page.top
                y = piece.flowTop + onPage - insetTop - piece.pageY
            }
        }
        // (One that text wraps round, placed from a paragraph in a table
        // cell, stands no higher than the cell's top: zh-e4ef4c4d p5's
        // photos, wrapped tight and anchored 179.7 and 191.7pt above their
        // paragraphs, eight lines down their cells, are drawn at the row's
        // top in Word's print, where ours stood 11.7 and 23.7pt above the
        // row; drawing.docx p9's icon, wrapped square, 278.8 (ours 219.6).
        // One in front of the text or behind it is not held: zh-e49d7943's
        // "附件5" box stands 27.8pt over its table's first row in Word's
        // print. Every anchor in a cell in the corpus is `layoutInCell`.)
        // (So does one placed against the page from a cell, over the
        // cell: zh-ab9cbe66's flow charts, groups 0pt down their pages
        // anchored in a table's second row, wrapped tight, stand at that
        // row's top in Word's print, 120pt down; ours drew them over the
        // page's top margin. Not one out in the page's margin beside the
        // table: zh-d8247da5's two 14pt marks, wrapped through 29 and 49pt
        // down the page at its left edge, held to their rows cost 3 lines.)
        // (A table floating in a cell, set where an earlier one in the same
        // cell was set — same offsets, against the text — stands under it,
        // not over it: Word for Windows on LibreOffice's floattable-leak,
        // the second at the first's foot, 17.6pt under.)
        // (A table floating against the text, anchored to a paragraph after a block that stepped down below
        // floating tables, keeps the place it had before the block did: `_avoidPush`.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, float.againstText, image.name == "table", i < _cells.count, let d = _cells[i] {
            var k = i - 1
            while k >= 0, k < _cells.count, let e = _cells[k], e.table == d.table, e.row == d.row, e.column == d.column {
                if let pushed = _blockPush[k] { y -= pushed }
                k -= 1
            }
        }
        if theme.wordRules, RichTextTheme.wordWindowsPages, float.againstText, image.name == "table",
           i < _cells.count, let d = _cells[i], !d.vertical {
            var k = i - 1
            while k >= 0, k < _cells.count, let e = _cells[k], e.table == d.table, e.row == d.row, e.column == d.column {
                if k < _floatImages.count, let q = _floatImages[k], q.name == "table", let qf = q.float, qf.againstText,
                   qf.x == float.x, qf.y == float.y, qf.horizontalAlign == float.horizontalAlign,
                   k < _imageSize.count, let size = _imageSize[k] {
                    RuleTrace.hit("nested-floating-table-stands-under-the-one-before")
                    // (Under its foot, not that much further down: an empty paragraph
                    // between them has already carried this one part of the way —
                    // lo-d096abe2, the same cell with one more line.)
                    y = max(y, d.rowTop + d.pad.top + _px(qf.y) + size.height + _px(qf.distanceBottom) + _px(float.distanceTop))
                }
                k -= 1
            }
        }
        if theme.wordRules, float.wraps, float.verticalAlign == nil, ["paragraph", "line"].contains(float.verticalFrom),
           i < _cells.count, let d = _cells[i], !d.vertical, y < d.rowTop { y = d.rowTop }
        if theme.wordRules, float.wraps, float.verticalAlign == nil, ["page", "margin"].contains(float.verticalFrom),
           i < _cells.count, let d = _cells[i], !d.vertical, y < d.rowTop,
           x + w > d.colLeft, x < d.colLeft + d.colWidth { y = d.rowTop }
        // (Nor further left than the cell's edge, its effect extent
        // inside: drawing.docx p9's icon, 85.05pt left of its column, is
        // at 86.6 in Word's print — its cell's 85.05 and a 1.5pt effect —
        // where ours stood at the page's edge.)
        if theme.wordRules, float.wraps, float.horizontalAlign == nil, float.horizontalFrom != "page",
           i < _cells.count, let d = _cells[i], !d.vertical, x < d.colLeft + d.pad.left + _px(image.effectLeft) {
            x = d.colLeft + d.pad.left + _px(image.effectLeft)
        }
        // (An anchor in a cell, `layoutInCell`, set from the page at both
        // offsets, is set from the cell's own corner: zh-d8247da5's two 14pt
        // marks "面" and "積" in a header cell, 16.3 and 25.8pt over and 29.1
        // and 48.9pt down "the page", are 16.3 and 25.8 over and 29.1 and
        // 48.9 down the cell's corner in Word's print; ours drew them at
        // the page's corner.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, float.horizontalFrom == "page", float.verticalFrom == "page",
           float.horizontalAlign == nil, float.verticalAlign == nil, i < _cells.count, let d = _cells[i], !d.vertical,
           image.name != "table", !float.leavesCell {
            RuleTrace.hit("page-offsets-of-an-anchor-in-a-cell-are-from-the-cell")
            x = d.colLeft + _px(float.x)
            y = d.rowTop + _px(float.y)
        }
        // (An anchor in a cell, `layoutInCell`, aligned to the page's right or left edge and its top, is aligned
        // to the cell's: lo-099d1f3b's logo, right/top of "the page", stands at the top right of the bordered
        // cell it is anchored in in Word's print, ours at the page's corner.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, float.horizontalFrom == "page", float.verticalFrom == "page",
           let ha = float.horizontalAlign, ha == "right" || ha == "left", float.verticalAlign == "top",
           i < _cells.count, let d = _cells[i], !d.vertical, image.name != "table", !float.leavesCell {
            RuleTrace.hit("page-aligned-anchor-in-a-cell-is-aligned-to-the-cell")
            x = ha == "right" ? d.colLeft + d.colWidth - w : d.colLeft
            y = d.rowTop
        }
        // (An anchor in a cell set from the page down and from its column across
        // is set down from the cell's top too: zh-3da9d7f2's red title, 8.45pt
        // "down the page", stands there in Word's print under the table that
        // floats 29pt down the text, where ours drew it on the page's top.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, float.verticalFrom == "page", float.horizontalFrom == "column",
           float.verticalAlign == nil, !float.wraps, i < _cells.count, let d = _cells[i], !d.vertical,
           image.name != "table", !float.leavesCell {
            RuleTrace.hit("page-offset-down-of-an-anchor-in-a-cell-is-from-the-cell")
            y = d.rowTop + _px(float.y)
            // (Under the cell's top margin: lo-152d87fe's header group, 39.5pt up "the page" in a cell
            // with a 41pt top margin, has its banner 33pt down the group at 63pt in Word's print,
            // the cell's text at 69.8 less 39.5; ours stood 25pt higher.)
            if float.y < 0 { y += d.pad.top; RuleTrace.hit("page-offset-up-of-an-anchor-in-a-cell-counts-from-the-cell-text") }
        }
        // (A picture as big as the page, set from the text far off it, is
        // kept on the page, at its corner: lo-4dec07ec's 595 by 842pt
        // background, 430pt left and 1006pt up from its paragraph, covers
        // the page in Word's print, black with the white shape, and hides
        // the title; ours dropped it off the page.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, !floatsFrames, float.horizontalAlign == nil, float.verticalAlign == nil,
           i >= _cells.count || _cells[i] == nil, page.height > 0 {
            let setup = _setup(ofParagraph: i)
            if abs(w - _px(setup.width)) < _px(3), abs(h - page.height) < _px(3), x < -_px(1) || y < -_px(1) || x + w > _px(setup.width) + _px(1) || y + h > page.height + _px(1) {
                RuleTrace.hit("page-sized-picture-set-off-the-page-is-kept-on-it")
                x = g.textLeft - _textLeftInColumn(i) - _px(setup.marginLeft + setup.gutter)
                y = -page.top
            }
        }
        let box = Rect.fromLTWH(x + (_floatShift[image.id] ?? 0), y + (_floatShiftY[image.id] ?? 0), w, h)
        // (Turned a quarter, about its centre: as tall as it is wide.
        // Word's print of zh-37b6536f puts a photo of 236.8 by 222.4
        // turned 90° in a box of 222.4 by 236.8 with the same centre.)
        guard Self._quarterTurned(image) else { return box }
        let c = box.center
        return Rect.fromLTWH(c.dx - h / 2, c.dy - w / 2, h, w)
    }

    /// The `w:position` of a run's saved properties, in points (half-points in the file).
    static func _runPosition(_ xml: String?) -> Double? {
        guard let xml, let at = xml.rangeOfSubstring("w:position") else { return nil }
        let rest = String(xml[at.upperBound...])
        guard let q = rest.rangeOfSubstring("w:val=\"") else { return nil }
        let value = String(rest[q.upperBound...])
        guard let end = value.rangeOfSubstring("\"") else { return nil }
        return Double(String(value[..<end.lowerBound])).map { $0 / 2 }
    }

    /// The room a picture in the line takes round its box, in pixels:
    /// its effect extent on each side, and its run's character border
    /// (`ImageAttachment.frame`) `space + width` out on every side.
    /// (Only at the size the file gave it: resized in the editor, the
    /// picture is written afresh, without either.)
    func _pictureRoom(_ image: ImageAttachment) -> (top: Double, bottom: Double, left: Double, right: Double) {
        // (Not once resized: its effect extent was the old size's. A kept
        // object, a chart, has no source size and keeps its own.)
        guard image.sourceWidth == nil || (image.sourceWidth == image.width && image.sourceHeight == image.height) else { return (0, 0, 0, 0) }
        let frame = image.frame.map { _px($0.space + $0.width) } ?? 0
        return (_px(image.effectTop) + frame, _px(image.effectBottom) + frame,
                _px(image.effectLeft) + frame, _px(image.effectRight) + frame)
    }

    /// A picture's character border, round `box` (the picture's own) and
    /// its effect extent.
    func _paintFrame(_ image: ImageAttachment, _ box: Rect, _ canvas: any Canvas) {
        guard theme.wordRules, let frame = image.frame, frame.width > 0 else { return }
        let out = _px(frame.space + frame.width / 2)
        let paint = Paint()
        paint.style = .stroke
        paint.strokeWidth = _px(frame.width)
        paint.color = frame.color ?? theme.textColor
        let originalSize = image.sourceWidth == nil || (image.sourceWidth == image.width && image.sourceHeight == image.height)
        let left = image.float == nil && originalSize ? _px(image.effectLeft) : 0
        let right = image.float == nil && originalSize ? _px(image.effectRight) : 0
        canvas.drawRect(Rect.fromLTRB(box.left - left - out, box.top - _px(image.effectTop) - out,
                                      box.right + right + out, box.bottom + _px(image.effectBottom) + out), paint)
    }

    /// A table set wider than the column it hangs from is not cut at the
    /// column's edge: Word's print of lo-ed539d0e226f93bf draws a 425pt
    /// floating table, in the 263pt first column of a two-column section,
    /// out to its own right edge (469.8), its text included.
    @inline(never)
    func _tableOverflowsColumn(_ paragraph: Int, _ columnW: Double) -> Bool {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, paragraph < _cells.count, let d = _cells[paragraph],
              let widths = _columnWidths[d.table] else { return false }
        return widths.reduce(0, +) > columnW + 1
    }

    /// A picture in the line wider than the table cell it stands in is
    /// cut at the cell's sides, as Word prints one (drawing.docx p9: a
    /// 303.75pt banner in a 296pt cell ends at the cell's 381.12, and a
    /// 175.5pt one in a nested cell at 552.72). Lab `dr/clip1` on Word
    /// for Windows: the cut is at the cell's edge, not its text's (18pt
    /// cell margins change nothing), the picture still starts at the
    /// text's left when its paragraph is centred or set right, and only
    /// across, never down. Saves the canvas and clips it, true, where it
    /// does; the caller restores.
    func _clipToCell(_ i: Int, _ image: ImageAttachment, _ box: Rect, _ canvas: any Canvas) -> Bool {
        guard theme.wordRules, image.float == nil, i < _cells.count, let d = _cells[i], !d.vertical,
              box.left < d.colLeft - 0.5 || box.right > d.colLeft + d.colWidth + 0.5 else { return false }
        canvas.save()
        canvas.clipRect(Rect.fromLTRB(d.colLeft, box.top - 1, d.colLeft + d.colWidth, box.bottom + 1), clipOp: .intersect, doAntiAlias: false)
        return true
    }

    /// Whether a floating picture is turned by an odd number of quarters.
    static func _quarterTurned(_ image: ImageAttachment) -> Bool {
        let r = (image.rotation.truncatingRemainder(dividingBy: 180) + 180).truncatingRemainder(dividingBy: 180)
        return abs(r - 90) < 1 && image.float != nil
    }

    /// A decoded picture into its box, turned as the file turns it: the
    /// box is the turned one, and the picture is drawn unturned about
    /// the same centre and then turned.
    func _drawPicture(_ decoded: Image, _ image: ImageAttachment, _ box0: Rect, _ canvas: any Canvas) {
        // (In its canvas, smaller than the box it is the only thing in: lo-587930f8's bus stands
        // 89pt in a 432 by 252pt canvas.)
        let box = _insetBox(image, box0)
        var src = Rect.fromLTWH(0, 0, Double(decoded.width), Double(decoded.height))
        // (Cut to the part Word shows, from the file's crop: zh-6aa8bd7c's satellite
        // picture is a browser screenshot cropped to the picture inside it.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, let crop = image.crop {
            src = Rect.fromLTRB(src.width * crop.left, src.height * crop.top, src.width * (1 - crop.right), src.height * (1 - crop.bottom))
        }
        guard image.float != nil, abs(image.rotation) > 0.01 else {
            canvas.drawImageRect(decoded, src, box, Paint())
            return
        }
        let c = box.center
        let (w, h) = Self._quarterTurned(image) ? (box.height, box.width) : (box.width, box.height)
        canvas.save()
        canvas.translate(c.dx, c.dy)
        canvas.rotate(image.rotation * Double.pi / 180)
        canvas.drawImageRect(decoded, src, Rect.fromLTWH(-w / 2, -h / 2, w, h), Paint())
        canvas.restore()
    }

    /// A span with every stretch's extra height set half above and half
    /// below its text (`TextLeadingDistribution.even`).
    /// (With a font feature no face has, which shaping ignores:
    /// skparagraph's cache of shaped paragraphs tells text styles apart
    /// by `equalsByFonts`, which never looks at the leading, and served
    /// this paragraph's proportional layout back — every paragraph so
    /// laid out but one after a different one. Font features it
    /// compares.)
    static func _evenLeading(_ span: InlineSpan) -> InlineSpan {
        guard let t = span as? TextSpan else { return span }
        return TextSpan(text: t.text, children: t.children?.map { _evenLeading($0) },
                        style: t.style.map { $0.copyWith(leadingDistribution: .even,
                                                         fontFeatures: ($0.fontFeatures ?? []) + [FontFeature("zevn", 1)]) },
                        recognizer: t.recognizer, locale: t.locale)
    }

    /// The height of one line of paragraph `i` in its mark's look, as if
    /// it held nothing else (px).
    func _markLineHeight(_ i: Int, _ document: RichDocument, single: Bool = false, using run: CharStyle? = nil) -> Double {
        let p = document.paragraphs[i]
        var mark = run ?? p.style.mark ?? p.runs.first?.style ?? CharStyle()
        mark.inlineImage = nil
        var style = p.style
        style.lineCollapsed = false
        // (At single spacing: the text's own line, without what a
        // multiple or a stated height adds.)
        if single {
            style.lineSpacing = 1
            style.lineHeightPoints = nil
            style.lineHeightIsMinimum = false
        }
        let empty = RichParagraph(text: "\u{FFFC}", runs: [Run(length: 1, style: mark)], style: style)
        let width = max(1, _flowWidth(i))
        let (span, held, _) = _span(for: empty, at: i, document, textWidth: width)
        let probe = TextPainter(text: span, textAlign: .left, textDirection: .ltr, strutStyle: _strut(span))
        probe.fractionalLineHeights = theme.wordRules
        if !held.isEmpty { probe.setPlaceholderDimensions(held.map { $0.dimensions }) }
        probe.layout(minWidth: 0, maxWidth: width)
        defer { probe.dispose() }
        return probe.height
    }

    /// A paragraph that opens on a line break: the break's line is the height of the runs on it (the
    /// break's own, as an empty mark's would be), not the paragraph-wide minimum the text under it
    /// holds. dx2 17a0d0c7's Telugu paragraphs open on a `w:br` set in Arial: Word's line is 15.0 pt, ours
    /// was Telugu's 17.3. The lines after it are painted that much higher, the box that much shorter.
    @inline(never)
    func _leadingBreakCut(_ i: Int, _ p: RichParagraph, _ painter: TextPainter, _ document: RichDocument, bodyHeight: inout Double) {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, p.style.lineHeightPoints == nil, p.image == nil,
              p.text.unicodeScalars.first == "\n", let run = p.runs.first?.style else { return }
        let lines = painter.computeLineMetrics()
        guard lines.count >= 2, let first = lines.first else { return }
        let own = _markLineHeight(i, document, using: run)
        let cut = first.height - own
        guard own > 1, cut > 0.5 else { return }
        RuleTrace.hit("leading-break-own-line")
        bodyHeight -= cut
        _inkShift[i] -= cut
    }

    /// The single line of the tallest text run in paragraph `i` (no picture runs), or nil with no text.
    @inline(never)
    func _tallestTextLine(_ i: Int, _ document: RichDocument) -> Double? {
        let p = document.paragraphs[i]
        var best: Double?
        var seen: [CharStyle] = []
        for r in p.runs where r.style.inlineImage == nil && r.length > 0 {
            if seen.count >= 4 { break }
            if seen.contains(where: { $0 == r.style }) { continue }
            seen.append(r.style)
            best = max(best ?? 0, _markLineHeight(i, document, single: true, using: r.style))
        }
        return best
    }

    /// Whether paragraph `i` holds nothing but floating objects: its
    /// line is empty, and its objects stand where its anchor puts them.
    func _anchorsOnly(_ i: Int, _ document: RichDocument) -> Bool {
        guard i < document.paragraphs.count, _cells[i] == nil else { return false }
        let p = document.paragraphs[i]
        if let image = p.image { return image.float.map { !$0.takesRoom } ?? false }
        return !p.inlineImages.isEmpty && !p.text.isEmpty && p.text.unicodeScalars.allSatisfy { $0.value == 0xFFFC }
            && p.inlineImages.values.allSatisfy { $0.float.map { !$0.takesRoom } ?? false }
    }

    /// The pictures paragraph `i` anchors that text wraps round (Word's
    /// square, tight and through wrapping, placed from the paragraph):
    /// each one's id and box in the flow, x from the column's edge.
    func _wrapBoxes(_ i: Int) -> [(id: String, rect: Rect, above: Double, below: Double)] {
        guard theme.wordRules, i < count, _cells[i] == nil, _painters[i] != nil else { return [] }
        var images: [ImageAttachment] = []
        if i < _floatImages.count, let image = _floatImages[i] { images.append(image) }
        if i < _inline.count { images += _inline[i] }
        let g = geometry(i)
        var out: [(id: String, rect: Rect, above: Double, below: Double)] = []
        for image in images {
            guard let float = image.float, float.wraps, !float.takesRoom, float.verticalAlign == nil,
                  ["paragraph", "line"].contains(float.verticalFrom), float.horizontalFrom != "page",
                  // (A chart, drawn or not, takes its room like a picture:
                  // zh-37b6536f's caption stands under its 145pt chart; so
                  // does any object the app draws, `drawsObject`, and a
                  // text box with text in it — bib-chernigovka's cover
                  // title, a 475pt box wrapped square, has the year under
                  // it at the page's foot and the calendar from page 2.)
                  !image.data.isEmpty || Self.drawsObject?(image) == true || image.textBox != nil
                    || (image.textBox == nil && image.sourceXML?.containsSubstring("drawingml/2006/chart") == true) else { continue }
            // (Text on one side only: the other is kept clear to the
            // column's edge. zh-f47b8a74's "第  页共  页" boxes, wrapped
            // square with text on their right, stand at the right of the
            // column 21pt under an empty line, and Word's print sets that
            // line and the "制作指引：" after it under the box; ours ran
            // them past its left.)
            var r = _floatRect(float, image, g, i)
            // ("largest": the side with more room, whichever that is.)
            let side = float.wrapSide == "largest" ? ((r.left + r.right) / 2 >= g.textLeft - _textLeftInColumn(i) + _flowWidth(i) / 2 ? "left" : "right") : float.wrapSide
            _wrapOwnSpan[image.id] = (r.left, r.right)
            if side == "right" { r = Rect.fromLTRB(-1_000_000, r.top, r.right, r.bottom) }
            if side == "left" { r = Rect.fromLTRB(r.left, r.top, 1_000_000, r.bottom) }
            // (Its drawn effects' reach below its box is part of what the
            // text clears: zh-8e8d4c40's 【附件五】 box, wrapped square
            // with b 11430 EMU, has the title under it 0.9pt lower in Word
            // for Windows than its frame's foot — lab t8e.)
            out.append((image.id, r, _px(float.distanceTop), _px(float.distanceBottom + (theme.wordRules ? float.effectBottom : 0))))
        }
        return out
    }
    func _pageFloat(_ i: Int) -> Bool {
        let images = (i < _floatImages.count ? _floatImages[i].map { [$0] } ?? [] : []) + (i < _inline.count ? _inline[i] : [])
        return images.contains { $0.float?.horizontalFrom == "page" && $0.float?.horizontalAlign == nil }
    }
    func _marginFloat(_ i: Int) -> Bool {
        let images = (i < _floatImages.count ? _floatImages[i].map { [$0] } ?? [] : []) + (i < _inline.count ? _inline[i] : [])
        return images.contains { $0.float?.horizontalFrom == "margin" }
    }
    func _textLeftInColumn(_ i: Int) -> Double {
        guard i < _cells.count, _cells[i] == nil else { return 0 }
        return _textLeft[i]
    }

    /// A page number as the document writes them.
    func _pageNumber(_ n: Int, _ document: RichDocument, format: String? = nil) -> String {
        switch format ?? document.pageNumberFormat {
        case "lowerRoman": return ListNumberFormat.lowerRoman.string(n)
        case "upperRoman": return ListNumberFormat.upperRoman.string(n)
        case "lowerLetter": return ListNumberFormat.lowerLetter.string(n)
        case "upperLetter": return ListNumberFormat.upperLetter.string(n)
        case "numberInDash": return "- \(n) -"
        // (The East Asian, Thai, Arabic and Hebrew ones: the list formats' own.)
        case let f? where !["decimal", "none", "bullet"].contains(f):
            var level = ListLevelFormat(text: "%1", format: .decimal)
            level.rawFormat = f
            return level.number(n)
        default: return String(n)
        }
    }

    /// The page number paragraph `k` starts on, as the document writes it —
    /// what a page reference (`PAGEREF`) to a bookmark in it comes to; nil
    /// where the paragraph has no place on a page (laid out nowhere).
    public func pageLabel(ofParagraph k: Int, _ document: RichDocument) -> String? {
        guard k >= 0, k < _pieceStart.count, _pieceStart[k] < _allPieces.count else { return nil }
        let page = _allPieces[_pieceStart[k]].page / _columns
        guard page >= 0, page < _pages.count else { return nil }
        return _pageNumber(_pageNumberOf(page, document), document, format: _pageNumberFormat(page, document))
    }

    /// Page `p`'s number: on from the page before, unless its section
    /// starts on it and says where to number from (Word's
    /// `w:pgNumType w:start` per section — zh-9e08ed28's body is page 1
    /// after a cover and two pages of contents, which were 8).
    func _pageNumberOf(_ p: Int, _ document: RichDocument) -> Int {
        func start(_ section: (index: Int, last: Bool)) -> Int? {
            _sectionNumberStart(section.index, document)
        }
        guard _sectionSetups.count > 1 else { return p + (document.pageNumberStart ?? 1) }
        // (A section that begins down a page counts that page its first,
        // though the page's footer is the section it began in: zh-b5359de4's
        // body, continuous from start 1 under its contents on page 4, is
        // "2" on page 5 in Word's print, page 4 keeping the contents' "2".)
        // (And a continuous one begins where the mark of the section before
        // it stands, though a page break in that mark's paragraph sets its
        // first line on the next page: zh-e2dc9dce's contents end on page 2
        // with the mark and a break, and its body, continuous from 1, is "2"
        // on page 3 in Word's print.)
        func begins(_ index: Int) -> Int? {
            guard theme.wordRules, let k = _sectionOf.firstIndex(of: index), k < _pieceStart.count,
                  _pieceStart[k] < _allPieces.count else { return nil }
            let own = _allPieces[_pieceStart[k]].page / _columns
            // (The mark's paragraph, its line taken by the break, may stand
            // nowhere: the page is that of whatever was set last before.)
            if k > 0, document.paragraphs[k - 1].style.sectionXML != nil, document.paragraphs[k - 1].style.sectionBreaksPage == false,
               _pieceStart[k] > 0, case let mark = _allPieces[_pieceStart[k] - 1], mark.paragraph < k, mark.page / _columns < own {
                return mark.page / _columns
            }
            return own
        }
        var number = 0
        var previous = -1
        for q in 0 ... max(0, p) {
            if q > 0, _blankPages.contains(q) {
                if _numberedBlankPages.contains(q) { number += 1 }
                continue
            }
            let section = _headerFooterSection(q)
            if q == 0 || section.index != previous {
                if let first = start(section), let at = begins(section.index), at < q, at >= 0, q > 0,
                   _headerFooterSection(at).index != section.index {
                    number = first + (q - at)
                } else {
                    // (A first section that starts on an even page is numbered
                    // from 2, no blank page before it: lo tdf135216_evenOddFooter's
                    // print opens with the even footer and "2".)
                    number = start(section) ?? (q == 0 ? (theme.wordRules && section.index == 0 && _sectionSetups[0].sectionStartParity == .even ? 2 : 1) : number + 1)
                }
            } else {
                number += 1
            }
            previous = section.index
        }
        return number
    }

    /// Where section `index` numbers its pages from, if it says.
    func _sectionNumberStart(_ index: Int, _ document: RichDocument) -> Int? {
        let number = index >= _sectionSetups.count - 1 ? document.pageNumberStart
            : (index < _sectionSetups.count ? _sectionSetups[index].pageNumberStart : nil)
        guard let number, index > 0, index < _sectionSetups.count,
              let parity = _sectionSetups[index].sectionStartParity else { return number }
        return number % 2 == parity.rawValue ? number : number + 1
    }

    /// The chapter's number and its separator in front of page `p`'s number,
    /// where the section's `w:pgNumType` names a heading level
    /// (`w:chapStyle`): LibreOffice's tdf149089, chapStyle 1 over a numbered
    /// "heading 1", is "1-1", "1-2", "1-3" in Word's print. The chapter is
    /// the first heading of that level on the page, else the last before it
    /// (as STYLEREF reads), else the first after it: the title page of
    /// tdf149089 stands before its only chapter heading and is "1-1" in
    /// Word's print too.
    func _chapterPrefix(_ p: Int, _ document: RichDocument) -> String {
        guard theme.wordRules else { return "" }
        let section = _headerFooterSection(p)
        let level: Int?, separator: String?
        if section.last || section.index >= _sectionSetups.count {
            level = document.chapterStyle; separator = document.chapterSeparator
        } else {
            level = _sectionSetups[section.index].chapterStyle; separator = _sectionSetups[section.index].chapterSeparator
        }
        guard let level, level >= 1, p < _pages.count else { return "" }
        let onPage = _pages[p].map(\.paragraph).filter { $0 >= 0 && $0 < document.paragraphs.count }
        guard let first = onPage.min() else { return "" }
        let isChapter: (Int) -> Bool = { document.paragraphs[$0].style.heading == level && self.listLabel($0, document) != nil }
        let last = onPage.max() ?? first
        guard let chapter = onPage.sorted().first(where: isChapter) ?? (0 ..< first).reversed().first(where: isChapter)
                ?? (last + 1 ..< document.paragraphs.count).first(where: isChapter),
              var label = listLabel(chapter, document) else { return "" }
        label = label.trimmingWhitespace()
        while let last = label.last, ".、．)）".contains(last) { label.removeLast() }
        guard !label.isEmpty else { return "" }
        let sep: String
        switch separator {
        case "period": sep = "."
        case "colon": sep = ":"
        case "emDash": sep = "\u{2014}"
        case "enDash": sep = "\u{2013}"
        default: sep = "-"
        }
        return label + sep
    }

    /// How page `p`'s section writes its numbers.
    func _pageNumberFormat(_ p: Int, _ document: RichDocument) -> String? {
        let section = _headerFooterSection(p)
        if section.last || section.index >= _sectionSetups.count { return document.pageNumberFormat }
        // (A section that names no format writes plain numbers, whatever
        // the last says: zh-c8eb6e92's last section is "numberInDash", and
        // Word's print numbers its earlier pages "1", "2" — ours "- 1 -".)
        return _sectionSetups[section.index].pageNumberFormat ?? (theme.wordRules ? "decimal" : nil)
    }

    /// The section page `p` is of, as `RichHeaderFooter.section` counts
    /// them, and whether that is the last (the document's own).
    func _headerFooterSection(_ p: Int) -> (index: Int, last: Bool) {
        let last = max(0, _sectionSetups.count - 1)
        guard _sectionSetups.count > 1, p >= 0, p < _pageSection.count else { return (last, true) }
        let section = _pageHeaderSection[p] ?? _pageSection[p]
        return (section, section >= last)
    }

    /// Whether page `p` is the first of a section that gives its first
    /// page a header and footer of its own.
    func _titlePage(_ p: Int, _ document: RichDocument) -> Bool {
        let section = _headerFooterSection(p)
        guard p == 0 || _headerFooterSection(p - 1).index != section.index || _blankPages.contains(p - 1) else { return false }
        // (A section that began on an earlier page, as a continuous one does
        // under the page its predecessor ends on, has its first page there:
        // lo 090716_Studentische_Arbeit_VWS's second section opens on page 1
        // and breaks to page 2, which Word's print gives the section's
        // default header, not the first-page one the title page has.)
        if theme.wordRules, p > 0, let first = _sectionOf.firstIndex(of: section.index),
           first < _pieceStart.count, _pieceStart[first] < _allPieces.count,
           _allPieces[_pieceStart[first]].page / _columns < p, !_blankPages.contains(p - 1) {
            RuleTrace.hit("title-page-of-a-section-begun-earlier")
            return false
        }
        // (The same while the pages are still being set: the section's first paragraph is on the page before.)
        if theme.wordRules, p > 0, let first = _sectionOf.firstIndex(of: section.index),
           !(first < _pieceStart.count && _pieceStart[first] < _allPieces.count), p * _columns - 1 < _pages.count,
           // (Any column of the page before: a section opened in the first column of a two-column page has not reached the last one.)
           _pages[(p - 1) * _columns ..< p * _columns].contains(where: { $0.contains(where: { $0.paragraph == first }) }), !_blankPages.contains(p - 1) {
            RuleTrace.hit("title-page-of-a-section-begun-earlier")
            return false
        }
        // (A page given the next section's headers has that section's
        // title-page setting: lo 090716's page 3, whose section has none.)
        if theme.wordRules, _pageHeaderSection[p] != nil, section.index < _sectionSetups.count, !section.last { return _sectionSetups[section.index].titlePage }
        return section.last ? document.titlePage : pageSetup(forPage: p).titlePage
    }

    /// The file's header or footer for page `p`, laid out — or nil where
    /// the page has none, or the editor's own one-line text stands (it
    /// was edited, or holds tabs, whose stops only that form sets).
    func _headerFooter(_ kind: KeptHeaderFooter.Kind, page p: Int, _ document: RichDocument,
                               pageCount: Int? = nil) -> _HeaderFooter? {
        guard theme.wordRules, !document.headerFooters.isEmpty, !_blankPages.contains(p) else { return nil }
        if document.headerFooters != _headerFooterSource {
            for hf in _headerFooterCache.values { hf.layout.invalidateAll() }
            _headerFooterCache = [:]
            _headerFooterSource = document.headerFooters
        }
        let number = _pageNumberOf(p, document)
        let type = _titlePage(p, document) ? "first" : document.evenAndOddHeaders && number % 2 == 0 ? "even" : "default"
        let section = _headerFooterSection(p)
        guard let source = document.headerFooters.first(where: {
            $0.kind == kind && $0.type == type && ($0.section == nil || $0.section == section.index)
        }) else { return nil }
        if type == "default", section.last {
            // (One an earlier section named has no line of the editor's.)
            let own = kind == .header ? document.header : document.footer
            if let kept = document.keptHeaderFooters.first(where: { $0.kind == kind && $0.type == type })?.text {
                // (A tab no longer sends it to the editor's line: the
                // paragraphs keep their styles' stops; bug57031's footer
                // was drawn as a plain 12pt line, its 10pt text, rule and
                // second paragraph gone.)
                if kept != own { return nil }
            }
        }
        let setup = pageSetup(forPage: p)
        let shown = _chapterPrefix(p, document) + _pageNumber(number, document, format: _pageNumberFormat(p, document))
        let count = String(pageCount ?? self.pageCount)
        let key = "\(kind.rawValue)|\(type)|\(section.index)|\(shown)|\(number % 2)|\(p % 2)|\(count)|\(setup.contentWidth)|\(setup.vertical)|\(setup.lineGridPitch ?? 0)|\(scale)"
        if let hit = _headerFooterCache[key] { return hit }
        // The paragraphs with this page's number and the count in their
        // fields — and those of the text boxes among them, where a page
        // number often is.
        func filled(_ source: [RichParagraph]) -> [RichParagraph] {
            var paragraphs = source
            for k in paragraphs.indices {
                let old = paragraphs[k]
                var fresh = old
                if old.runs.contains(where: { $0.style.field != nil }) {
                    var text = ""
                    var runs: [Run] = []
                    var at = old.text.utf16.startIndex
                    var lastField: String? = nil
                    for run in old.runs {
                        let end = old.text.utf16.index(at, offsetBy: run.length)
                        var piece = String(old.text[at ..< end])
                        at = end
                        if let field = run.style.field {
                            // (One number per field, however many runs its old result was in.)
                            let word = field.trimmingWhitespace().uppercased().split(separator: " ").first.map(String.init) ?? ""
                            // (In full-width digits where the result it keeps was:
                            // zh-1b74ed91's footer holds "PAGE \* MERGEFORMAT" with
                            // "２０" as its result, and Word for Windows prints each
                            // page's "１４" so, in the East Asian face — whose line
                            // stands its footer 0.6pt taller than "14" in Times, and
                            // p14's empty paragraph over the table's title no longer
                            // fits above it.)
                            let wide = !piece.isEmpty && piece.unicodeScalars.allSatisfy { $0.value >= 0xFF10 && $0.value <= 0xFF19 }
                            piece = lastField == field ? "" : (word == "PAGE" ? shown : count)
                            if wide { piece = String(piece.unicodeScalars.map { $0.value >= 0x30 && $0.value <= 0x39 ? Character(Unicode.Scalar($0.value - 0x30 + 0xFF10)!) : Character($0) }) }
                            // (A field's result is one piece: Word parts
                            // "- 10 -" (numberInDash) at none of its spaces
                            // — zh-c3dd22c4's, in a box sized by "- 1 -",
                            // stays on one line in its print — so each
                            // space is joined to what follows it.)
                            if piece.containsSubstring(" ") { piece = piece.replacingAll(" ", with: " \u{2060}") }
                        }
                        lastField = run.style.field
                        guard !piece.isEmpty else { continue }
                        text += piece
                        runs.append(Run(length: piece.utf16.count, style: run.style))
                    }
                    fresh = RichParagraph(text: text, runs: runs.isEmpty ? nil : runs, style: old.style)
                    fresh.cell = old.cell
                    fresh.inlineImages = old.inlineImages
                }
                if var image = fresh.image, let box = image.textBox {
                    image.textBox?.paragraphs = filled(box.paragraphs)
                    fresh.image = image
                }
                for (id, var image) in fresh.inlineImages {
                    guard let box = image.textBox else { continue }
                    image.textBox?.paragraphs = filled(box.paragraphs)
                    fresh.inlineImages[id] = image
                }
                paragraphs[k] = fresh
            }
            return paragraphs
        }
        let paragraphs = filled(source.paragraphs)
        var sub = RichDocument(paragraphs: paragraphs)
        sub.styles = document.styles
        sub.fontUsb0 = document.fontUsb0
        sub.listFormats = document.listFormats
        sub.listCounterOf = document.listCounterOf
        sub.listRestarts = document.listRestarts
        sub.tableColumns = document.tableColumns
        sub.tableStyles = document.tableStyles
        // (A header's or footer's lines keep to no line grid: Word sets
        // zh-90e0cea8's 10.5pt header 10.35pt under its top, where a
        // line centred in the body's 15.6pt pitch stands 11.44 under,
        // and every page's text then that much lower.)
        sub.lineGridPitch = nil
        sub.characterGridSpace = section.last ? document.characterGridSpace : setup.characterGridSpace
        sub.characterGridCellBase = section.last ? document.characterGridCellBase : setup.characterGridCellBase
        sub.usesEastAsianLayout = document.usesEastAsianLayout
        sub.hasKana = document.hasKana
        sub.hangsLatinStops = document.hangsLatinStops
        sub.hangsStopsMinorEA = document.hangsStopsMinorEA
        sub.indentNotNumberingTabStop = document.indentNotNumberingTabStop
        sub.characterSpacingControl = document.characterSpacingControl
        sub.kernsPunctuation = document.kernsPunctuation
        sub.balancesSpaceWidth = document.balancesSpaceWidth
        sub.joinsHanAfterSpace = document.joinsHanAfterSpace
        sub.compatibilityMode = document.compatibilityMode
        sub.hangsHalf = document.hangsHalf
        sub.breakRulesOnlyForEastAsian = document.breakRulesOnlyForEastAsian
        sub.defaultLangXML = document.defaultLangXML
        sub.htmlAutoSpacing = document.htmlAutoSpacing
        sub.defaultTabStop = document.defaultTabStop
        let layout = RichLayout(theme: theme, paragraphCount: sub.paragraphs.count)
        layout.scale = scale
        layout.floatsFrames = true
        layout.frameMargins = (setup.marginLeft + setup.gutter, setup.marginRight)
        layout.leftHandPage = number % 2 == 0
        layout.headerTopOnPage = kind == .header ? _px(setup.headerDistance) : nil
        // (A floating shape aligned outside goes by the sheet, counted from
        // the document's first number — a later section's restart counts
        // for nothing: in Word for Windows' prints zh-ab1ea005's footer box
        // (against the margin) stands left on sheets 2 and 10, though both
        // are numbered 1, zh-f1f73836's right on sheet 5 and left on 6, both
        // numbered 5, and zh-4f70ee2d's, numbered from 2, left on sheet 1.
        // By the number, ours put zh-ab1ea005's on the other side; a frame
        // keeps the number's: see `leftHandPage`.)
        let firstNumber = (_sectionSetups.count > 1 ? _sectionNumberStart(0, document) : document.pageNumberStart) ?? 1
        layout.leftHandFloat = theme.wordRules ? (p + firstNumber) % 2 == 0 : number % 2 == 0
        // (A vertical section's running header and footer stay horizontal on the paper: as wide as the
        // paper's text width, which is the transposed page's height less its margins.)
        layout.width = _px(setup.vertical ? setup.contentHeight : setup.contentWidth)
        // (Its fit-to-text boxes as wide as on the first page this one is
        // on: see `inheritedFitWidths`.)
        // (In Word for Windows, the first page the same part is on, in any
        // section: zh-d0a207ac's sections after the first link to its
        // footer, a VML "— PAGE —" fit to its text, and the one starting on
        // page 10 wraps its closing dash under "— 10" there and on, in a box
        // sized by page 1's "— 1 —"; ours sized it afresh on page 10.)
        func sameSource(_ q: Int) -> Bool {
            let own = _titlePage(q, document) ? "first" : document.evenAndOddHeaders && _pageNumberOf(q, document) % 2 == 0 ? "even" : "default"
            guard own == type else { return false }
            let theirs = _headerFooterSection(q)
            if theirs.index == section.index { return true }
            guard RichTextTheme.wordWindowsPages, let other = document.headerFooters.first(where: {
                $0.kind == kind && $0.type == type && ($0.section == nil || $0.section == theirs.index)
            }) else { return false }
            return other.paragraphs == source.paragraphs
        }
        if let first = (0 ..< p).first(where: { q in !_blankPages.contains(q) && sameSource(q) }),
           let earlier = _headerFooter(kind, page: first, document, pageCount: pageCount) {
            for (k, w) in earlier.layout._fitWidths {
                guard let bar = k.firstIndex(of: "|") else { continue }
                layout.inheritedFitWidths[String(k[..<bar])] = w
            }
        }
        layout.ensureLaidOut(sub)
        // (A frame anchored to the page, at a y it states, stands there: Word
        // clamps it only at the page's foot, not at the footer's bottom.
        // Lab fr148b (Word for Windows): a framed line's top is the frame's y
        // for any y up to the page's bottom, in exact and auto-height frames
        // alike; an exact frame that would pass the foot moves up to fit.
        // lo tdf148671's footer frame, y 796.25 under a footer bottom of
        // 806.2, has its line at 796.26 in Word's print; ours stood 3.5pt up.)
        if theme.wordRules, RichTextTheme.wordWindowsPages {
            let region = kind == .header ? _px(setup.headerDistance) : _px(setup.height) - _px(setup.footerDistance) - layout.totalHeight
            for (k, para) in sub.paragraphs.enumerated() where para.cell == nil && k < layout._tops.count && k < layout._spaceBefore.count {
                guard let f = para.style.frame, f.verticalAnchor == "page", f.verticalAlign == nil,
                      let xml = para.style.frameXML, xml.containsSubstring("w:y=\"") else { continue }
                var target = _px(f.y)
                var room = layout._painters[k]?.height ?? 0
                if xml.containsSubstring("w:hRule=\"exact\""), let r = xml.firstRange(of: "w:h=\""),
                   let h = Double(xml[r.upperBound...].prefix { $0 != "\"" }), h > 0 { room = _px(h / 20) }
                target = min(target, _px(setup.height) - room)
                layout._spaceBefore[k] = target - region - layout._tops[k]
            }
        }
        let made = _HeaderFooter(layout: layout, document: sub)
        _headerFooterCache[key] = made
        return made
    }

    /// How far below the paper's top a header's picture that the text goes over and under, set from its paragraph, ends
    /// (pixels), if it has one.
    func _headerParagraphPictureEnd(_ header: _HeaderFooter, _ setup: PageSetup) -> Double? {
        var end: Double? = nil
        for (j, hp) in header.document.paragraphs.enumerated() where hp.cell == nil && j < header.layout._tops.count {
            for image in hp.inlineImages.inOrder + (hp.image.map { [$0] } ?? []) {
                guard let f = image.float, f.takesRoom || f.bandsPage, !f.wraps, f.verticalFrom == "paragraph", f.verticalAlign == nil,
                      f.y >= 0, image.height > 0 else { continue }
                RuleTrace.hit("header-picture-from-its-paragraph-ends-the-header")
                end = max(end ?? 0, _px(setup.headerDistance) + header.layout._tops[j] + _px(f.y) + _px(image.height) + _px(f.distanceBottom))
            }
        }
        return end
    }

    /// How far from the page's foot a footer's picture that the text goes over and under, set up from its paragraph,
    /// reaches (pixels), if it has one: Word stands it wholly above that paragraph (or as far up as it says, if
    /// that is more).
    func _footerPictureEnd(_ footer: _HeaderFooter, _ setup: PageSetup) -> Double? {
        var end: Double? = nil
        for (j, hp) in footer.document.paragraphs.enumerated() where hp.cell == nil && j < footer.layout._tops.count {
            for image in hp.inlineImages.inOrder + (hp.image.map { [$0] } ?? []) {
                guard let f = image.float, f.bandsPage, f.wrapSide == nil, f.verticalFrom == "paragraph", f.verticalAlign == nil,
                      image.height > 0 else { continue }
                // (Not one raised clear of its paragraph by more than its height: the body knows nothing of that —
                // floattable-footer-nofit, raised 200pt, keeps five rows a page.)
                let reach = _px(image.height) + _px(f.effectBottom)
                guard -_px(f.y) < reach else { continue }
                RuleTrace.hit("footer-picture-above-its-paragraph-ends-the-body")
                end = max(end ?? 0, _px(setup.footerDistance) + footer.height - footer.layout._tops[j] + reach)
            }
        }
        return end
    }

    /// How tall Word makes a footer that holds a full-width square-wrapped shape set from the bottom margin, when that
    /// shape's band (distances included) lies across the footer's first lines (pixels): Word stands the footer's paragraphs
    /// from the top of the bottom margin area, moves the paragraph the band covers to the band's foot, and then sets the
    /// grown footer on the page's foot, so the shape rides up with it (LibreOffice's lo-9c6cc479, a 2.85pt rule 20.25pt
    /// under the margin's top: the footer is 64.5pt, not 46, and page 1 loses a contents line).
    func _footerBandHeight(_ footer: _HeaderFooter, _ setup: PageSetup) -> Double? {
        var best: Double? = nil
        for (j, hp) in footer.document.paragraphs.enumerated() where hp.cell == nil && j < footer.layout._tops.count {
            for image in hp.inlineImages.inOrder + (hp.image.map { [$0] } ?? []) {
                guard let f = image.float, f.wraps, !f.wrapsTight, f.wrapSide == nil, f.verticalFrom == "bottomMargin",
                      f.verticalAlign == nil, image.height > 0,
                      image.width >= setup.width - setup.marginLeft - setup.marginRight - 1 else { continue }
                let top = _px(f.y) - _px(f.distanceTop), foot = _px(f.y) + _px(image.height) + _px(f.distanceBottom)
                let at = footer.layout._tops[j]
                guard at < foot, at + _px(8) > top else { continue }
                RuleTrace.hit("footer-moves-below-its-square-wrapped-shape-and-grows")
                best = max(best ?? 0, foot + footer.height - at)
            }
        }
        return best
    }

    /// How far below the paper's top page `p`'s text starts, and how far
    /// above its bottom it ends (pixels): the margins, or the header's
    /// and the footer's extent where that is more.
    func _bodyInsets(page p: Int, _ document: RichDocument) -> (top: Double, bottom: Double) {
        let setup = pageSetup(forPage: p)
        var top = _px(setup.marginTop), bottom = _px(setup.marginBottom)
        let exactTop = theme.wordRules && RichTextTheme.wordWindowsPages && setup.marginTopExact
        let exactBottom = theme.wordRules && RichTextTheme.wordWindowsPages && setup.marginBottomExact
        if exactTop || exactBottom { RuleTrace.hit("negative-margin-is-exact") }
        if !exactTop, let header = _headerFooter(.header, page: p, document, pageCount: 1) {
            top = max(top, (header.pageAnchoredTop.map { min(_px($0), _px(setup.headerDistance)) } ?? _px(setup.headerDistance)) + header.height)
            // (A header of one paragraph whose picture, with the text above and below it, is set against the PAGE's top: Word
            // puts the picture there and the paragraph's one line under its foot, so the body starts at the foot plus that
            // line, not at the header distance plus the picture's height as our flow has it. dx2 b785c95e and 4bc34886: a
            // 120.5pt picture at the page's top, an 11pt empty line under it at 130.8; the body from 133.2, ours 156.1.)
            if let lowered = _headerPictureBodyTop(header, top: top, marginTop: _px(setup.marginTop)) { top = lowered }
            // (A picture set from its paragraph in the header with the text above and below it: Word ends the header at
            // the picture's foot, and the body starts there, not at the header's line height. xa gv-d1907c960c: a 103.5pt
            // logo on the header's second paragraph, 41.3 to 144.8 on the paper, the body from 144.8; ours from the margin.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, let end = _headerParagraphPictureEnd(header, setup) { top = max(top, end) }
        }
        if !exactBottom, let footer = _headerFooter(.footer, page: p, document, pageCount: 1) {
            // (Its frames too, where they stand above it — a page number
            // set 11.75pt up from the footer's empty paragraph keeps the
            // body clear of it in Word's print: zh-6cd1befe's last row on
            // page 48, which would end beside the number, opens page 49.
            // Not one far up the page: Word wraps the body round that.)
            let rise = footer.frameRise
            bottom = max(bottom, _px(setup.footerDistance) + footer.height + (rise <= _px(36) ? rise : 0))
            // (A table placed against the page opens the footer where it says, when that is above where the footer would
            // begin: LibreOffice's tdf122878, tblpY 14743 twips under a 36pt footer distance, ends the body 13pt higher in
            // Word's print — one line fewer on page 1 — and sets its "A1 A2" row there.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, let off = footer.pageAnchoredTop {
                bottom = max(bottom, _px(setup.height) - _px(off))
            }
            // (And a picture in it that the text goes over and under, set up from its paragraph: Word stands it wholly
            // above that paragraph and ends the body at its top — LibreOffice's floattable-footer-object, a picture 88.5pt
            // high raised 81pt, ends the body 91pt higher than the footer's line alone does, three rows a page, not five.)
            if theme.wordRules, RichTextTheme.wordWindowsPages, let end = _footerPictureEnd(footer, setup) { bottom = max(bottom, end) }
            if theme.wordRules, RichTextTheme.wordWindowsPages, let grown = _footerBandHeight(footer, setup) { bottom = max(bottom, _px(setup.footerDistance) + grown) }
        }
        return (top, bottom)
    }

    /// Where the body of page `p` stands, in points down the paper: its top and its foot once a tall header or
    /// footer has pushed the margins out (what the balloon column of a marked-up print packs against).
    public func bodyBandPoints(page p: Int, _ document: RichDocument) -> (top: Double, bottom: Double) {
        let setup = pageSetup(forPage: p), k = theme.pixelsPerPoint * scale
        let ins = _bodyInsets(page: p, document)
        return (ins.top / k, setup.height - ins.bottom / k)
    }

    /// Running header (left) and footer (centred), fields filled per
    /// page, in Normal's face: the header's top and the footer's bottom
    /// at the page setup's distances from the paper's edges, as Word
    /// places them. The file's own, where it has them, as it wrote them.
    func _paintHeaderFooter(_ p: Int, _ canvas: any Canvas, _ document: RichDocument) {
        // (A page left blank for a section's side has neither.)
        guard pageSetup != nil, !_blankPages.contains(p) else { return }
        let setup = pageSetup(forPage: p)
        let rect = pageRect(p)
        let n = pageCount
        var drawn: Set<KeptHeaderFooter.Kind> = []
        for kind in [KeptHeaderFooter.Kind.header, .footer] {
            guard let hf = _headerFooter(kind, page: p, document) else {
                // (A first or even page that names none shows none. Nor
                // does a page of an earlier section that names none, with
                // none before it to go on with: the editor's own line is
                // the last section's — zh-10e3a42b's first page, whose
                // section has a header only, printed the last section's
                // "— 28 —" at its foot, where Word's print has nothing.)
                if theme.wordRules, document.headerFooters.contains(where: { $0.kind == kind }),
                   _titlePage(p, document) || !_headerFooterSection(p).last { drawn.insert(kind) }
                continue
            }
            let headerAt = hf.pageAnchoredTop.map { min(_px($0), _px(setup.headerDistance)) } ?? _px(setup.headerDistance)
            var top = kind == .header ? rect.top + headerAt : rect.bottom - _px(setup.footerDistance) - hf.height
            if kind == .footer, theme.wordRules, RichTextTheme.wordWindowsPages, let off = hf.pageAnchoredTop { top = min(top, rect.top + _px(off)) }
            hf.layout.regionTopOnPage = top - rect.top
            hf.layout.regionMarginTop = _px(setup.marginTop)
            hf.layout.regionMarginBottom = _px(setup.marginBottom)
            hf.layout.regionPageHeight = _px(setup.height)
            canvas.save()
            if setup.vertical {
                // (The page canvas is turned a quarter for the section: stand the running text back up
                // at its place on the paper, left margin = the transposed bottom margin.)
                let physTop = kind == .header ? _px(setup.headerDistance) : _px(setup.width) - _px(setup.footerDistance) - hf.height
                canvas.translate(rect.left + physTop, rect.top + _px(setup.height) - _px(setup.marginBottom))
                canvas.rotate(-Double.pi / 2)
            } else {
                canvas.translate(rect.left + _pxMarginLeft(p), top)
            }
            hf.layout.paint(canvas, visible: Rect.fromLTWH(-100_000, -100_000, 200_000, 200_000), document: hf.document,
                            selection: nil, caret: nil)
            canvas.restore()
            drawn.insert(kind)
        }
        let style = theme.textStyle(for: CharStyle(color: theme.textColor.withOpacity(0.7)),
                                    in: .body, named: document.styles[RichNamedStyle.normalId], scale: scale)
        let left = _pxMarginLeft(p)
        let width = _px(setup.contentWidth)
        /// One line at `centerY`: as a whole in `align`, or — with tabs —
        /// Word's header/footer thirds: left, centre and right parts.
        func line(_ template: String, align: TextAlign, top: Double? = nil, bottom: Double? = nil) {
            let text = RichDocument.fill(template, page: p + 1, pageCount: n)
            var parts: [(String, TextAlign)]
            if text.contains("\t" as Character) {
                let pieces = text.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                parts = [(pieces[0], .left)]
                if pieces.count > 1 { parts.append((pieces[1], .center)) }
                if pieces.count > 2 { parts.append((pieces[2...].joined(), .right)) }
            } else {
                parts = [(text, align)]
            }
            for (piece, a) in parts where !piece.isEmpty {
                let tp = TextPainter(text: TextSpan(text: piece, style: style), textAlign: a, textDirection: .ltr)
                tp.layout(minWidth: width, maxWidth: width)
                tp.paint(canvas, Offset(rect.left + left, top ?? ((bottom ?? 0) - tp.height)))
                tp.dispose()
            }
        }
        if !document.header.isEmpty, !drawn.contains(.header) {
            line(document.header, align: .left, top: rect.top + _px(setup.headerDistance))
        }
        if !document.footer.isEmpty, !drawn.contains(.footer) {
            line(document.footer, align: .center, bottom: rect.bottom - _px(setup.footerDistance))
        }
    }

    /// The footnotes set at page `p`'s foot: the separator — a rule
    /// 144pt long in its own empty paragraph (Word's print: 0.72pt thick,
    /// from the left margin) — and the notes under it, the last ending
    /// where the page's text area does.
    func _paintFootnotes(_ p: Int, _ canvas: any Canvas, _ document: RichDocument) {
        if _slotNotes { _paintSlotFootnotes(p, canvas, document); return }
        guard theme.wordRules, let ids = _pageNotes[p], !ids.isEmpty, pageSetup != nil else { return }
        let setup = pageSetup(forPage: p)
        if _columns > 1, RichTextTheme.wordWindowsPages { _paintColumnFootnotes(p, ids, canvas, document); return }
        let width = _px(setup.contentWidth)
        // (Each from `from` to `to` of its height: a note parted over the
        // page before or the next — `_noteCarryIn`, `_noteCutOut`.)
        let notes: [(note: _HeaderFooter, from: Double, to: Double)] = ids.compactMap { id in
            guard let note = _note(id, width: width, document) else { return nil }
            let from = _noteCarryIn[p]?.id == id ? _noteCarryIn[p]!.from : 0
            let to = _noteCutOut[p]?.id == id ? _noteCutOut[p]!.keep : note.height
            return (note, from, max(from, to))
        }
        guard !notes.isEmpty else { return }
        let rect = pageRect(p)
        let bottom = rect.bottom - _bodyInsets(page: p, document).bottom
        let separator = _note(-1, width: width, document)
        var top = bottom - notes.reduce(0.0) { $0 + $1.to - $1.from } - (separator?.height ?? 0)
        let left = rect.left + _pxMarginLeft(p)
        if let separator {
            let line = Paint()
            line.color = theme.textColor
            // (A separator that holds text after its line — lo
            // tdf123262_textFootnoteSeparators' "Text in footnote separator" —
            // has the line in its first paragraph's middle and the rest
            // set under it, as Word prints it.)
            let texted = separator.document.paragraphs.count > 1 && separator.document.paragraphs.dropFirst().contains { !$0.text.isEmpty }
            let first = texted && separator.layout._tops.count > 1 ? separator.layout._tops[1] : separator.height
            // (A right-to-left section's rule starts at the right margin and
            // runs left: lo-ccca8bf3 (tdf129659) in Word's print.)
            let mirrored = theme.wordRules && notes.first?.note.document.paragraphs.first?.style.rightToLeft == true
            canvas.drawRect(Rect.fromLTWH(mirrored ? left + width - _px(144) : left, top + first / 2 - _px(0.36), _px(144), _px(0.72)), line)
            if texted {
                canvas.save()
                canvas.translate(left, top)
                separator.layout.paint(canvas, visible: Rect.fromLTWH(-100_000, -100_000, 200_000, 200_000), document: separator.document,
                                       selection: nil, caret: nil)
                canvas.restore()
            }
            top += separator.height
        }
        for (note, from, to) in notes {
            canvas.save()
            if from > 0 || to < note.height { canvas.clipRect(Rect.fromLTRB(rect.left, top, rect.right, top + to - from)) }
            canvas.translate(left, top - from)
            note.layout.paint(canvas, visible: Rect.fromLTWH(-100_000, -100_000, 200_000, 200_000), document: note.document,
                              selection: nil, caret: nil)
            canvas.restore()
            top += to - from
        }
    }

    /// The notes of a page of columns set with its text (`slotNotes`): each
    /// column's own, bottom-aligned at the page's foot under a rule of its
    /// own — 144pt, the column's whole width where a note goes on from the
    /// page before (Word's labs fn-cols-long2 and -short).
    func _paintSlotFootnotes(_ p: Int, _ canvas: any Canvas, _ document: RichDocument) {
        let setup = pageSetup(forPage: p)
        let width = _px(setup.columnWidth)
        let rect = pageRect(p)
        let bottom = rect.bottom - _bodyInsets(page: p, document).bottom
        guard let separator = _note(-1, width: width, document) else { return }
        for c in 0 ..< _columns {
            let slot = p * _columns + c
            guard let ids = _pageNotes[slot], !ids.isEmpty else { continue }
            let notes: [(note: _HeaderFooter, from: Double, to: Double)] = ids.compactMap { id in
                guard let note = _note(id, width: width, document) else { return nil }
                let from = _noteCarryIn[slot]?.id == id ? _noteCarryIn[slot]!.from : 0
                let to = _noteCutOut[slot]?.id == id ? _noteCutOut[slot]!.keep : note.height
                return (note, from, max(from, to))
            }
            guard !notes.isEmpty else { continue }
            var top = bottom - notes.reduce(0.0) { $0 + $1.to - $1.from } - separator.height
            let left = rect.left + _pxMarginLeft(p) + _px(setup.columnOffset(c))
            let line = Paint()
            line.color = theme.textColor
            let long = _noteCarryIn[slot] != nil
            canvas.drawRect(Rect.fromLTWH(left, top + separator.height / 2 - _px(0.36), long ? width : _px(144), _px(0.72)), line)
            top += separator.height
            for (note, from, to) in notes {
                canvas.save()
                if from > 0 || to < note.height { canvas.clipRect(Rect.fromLTRB(left, top, left + width, top + to - from)) }
                canvas.translate(left, top - from)
                note.layout.paint(canvas, visible: Rect.fromLTWH(-100_000, -100_000, 200_000, 200_000), document: note.document,
                                  selection: nil, caret: nil)
                canvas.restore()
                top += to - from
            }
        }
    }

    /// The footnotes of a page of columns, laid in its columns: shared out
    /// in order, each column as tall as the notes need when they are
    /// shared out evenly, the notes whole (lo-9749f2b5: ten one-line notes
    /// stand 4, 4 and 2 in Word's print). `height` is the tallest column's
    /// notes, `separator` the room of the rule above them.
    func _columnNoteLayout(_ p: Int, _ ids: [Int], _ document: RichDocument)
        -> (notes: [_HeaderFooter], column: [Int], offset: [Double], height: Double, separator: Double, rule: _HeaderFooter?, colHeights: [Double])? {
        guard let geo = _columnNoteGeometry[p] else { return nil }
        let n = geo.columns
        let notes = ids.compactMap { _note($0, width: geo.width, document) }
        guard !notes.isEmpty else { return nil }
        // (A page of equal columns: each note under the column its mark stands
        // in, the column's notes stacked from the top of its room.)
        if geo.perColumn, RichTextTheme.wordWindowsPages {
            var column: [Int] = [], offset: [Double] = [], used = Array(repeating: 0.0, count: n)
            for (k, note) in notes.enumerated() {
                let id = ids.indices.contains(k) ? ids[k] : -1
                let c = min(n - 1, max(0, _noteColumn[id] ?? 0))
                column.append(c); offset.append(used[c]); used[c] += note.height
            }
            let rule = _note(-1, width: geo.width, document)
            return (notes, column, offset, used.max() ?? 0, rule?.height ?? 0, rule, used)
        }
        // The least height at which the notes fill the n columns in order.
        func fits(_ h: Double) -> Bool {
            var col = 0, used = 0.0
            for note in notes {
                if note.height > h + 0.01 { return false }
                if used + note.height > h + 0.01 { col += 1; used = 0 }
                if col >= n { return false }
                used += note.height
            }
            return true
        }
        var lo = notes.map { $0.height }.max() ?? 0, hi = notes.reduce(0.0) { $0 + $1.height }
        if !fits(hi) { hi += 1 }
        for _ in 0 ..< 40 { let mid = (lo + hi) / 2; if fits(mid) { hi = mid } else { lo = mid } }
        var column: [Int] = [], offset: [Double] = []
        var col = 0, used = 0.0
        for note in notes {
            if used + note.height > hi + 0.01 { col += 1; used = 0 }
            column.append(col); offset.append(used)
            used += note.height
        }
        let rule = _note(-1, width: geo.width, document)
        var heights = Array(repeating: 0.0, count: n)
        for (k, note) in notes.enumerated() { heights[column[k]] = max(heights[column[k]], offset[k] + note.height) }
        return (notes, column, offset, hi, rule?.height ?? 0, rule, heights)
    }

    func _paintColumnFootnotes(_ p: Int, _ ids: [Int], _ canvas: any Canvas, _ document: RichDocument) {
        guard let geo = _columnNoteGeometry[p], let lay = _columnNoteLayout(p, ids, document) else { return }
        let rect = pageRect(p)
        let bottom = rect.bottom - _bodyInsets(page: p, document).bottom
        let left = rect.left + geo.left
        // (Each column's notes stand at the page's foot, its rule over them:
        // lab fn-cols-long2, every column's last line at the same y.)
        func columnTop(_ c: Int) -> Double { bottom - (lay.colHeights.indices.contains(c) ? lay.colHeights[c] : lay.height) - lay.separator }
        if let rule = lay.rule {
            let line = Paint()
            line.color = theme.textColor
            // (Under each column that holds notes: its own rule, 144pt from
            // the column's edge — Word's lab fn-cols-long. A page of sections
            // that differ in columns has one, at the first.)
            let used = geo.perColumn ? Set(lay.column).sorted() : [0]
            for c in used {
                let t = geo.perColumn ? columnTop(c) : bottom - lay.height - lay.separator
                canvas.drawRect(Rect.fromLTWH(left + Double(c) * geo.stride, t + rule.height / 2 - _px(0.36), _px(144), _px(0.72)), line)
            }
        }
        for (k, note) in lay.notes.enumerated() {
            let c = lay.column[k]
            let top = (geo.perColumn ? columnTop(c) : bottom - lay.height - lay.separator) + lay.separator
            canvas.save()
            canvas.translate(left + Double(c) * geo.stride, top + lay.offset[k])
            note.layout.paint(canvas, visible: Rect.fromLTWH(-100_000, -100_000, 200_000, 200_000), document: note.document,
                              selection: nil, caret: nil)
            canvas.restore()
        }
    }

    /// The endnotes, after the body's last paragraph on its page, as Word
    /// sets them at the document's end: the separator — the footnotes'
    /// rule, 144pt in its own empty paragraph — then the notes. (Only
    /// where they fit on that page: notes that run on to pages of their
    /// own are not set.)
    func _paintEndnotes(_ canvas: any Canvas, _ document: RichDocument, pages: ClosedRange<Int>) {
        if theme.wordRules, RichTextTheme.wordWindowsPages, document.endnotesAtSectionEnd, isPaged, pageSetup != nil, !document.endnotes.isEmpty, !_sectionOf.isEmpty {
            // (At each section's end, under its last paragraph's last piece.)
            var ends: [Int] = []
            for k in 1 ..< max(1, min(count, _sectionOf.count)) where _sectionOf[k] != _sectionOf[k - 1] { ends.append(k) }
            ends.append(min(count, _sectionOf.count))
            for e in ends {
                let range: Range<Int> = {
                    var first = e - 1
                    while first > 0, _sectionOf[first - 1] == _sectionOf[e - 1] { first -= 1 }
                    return first ..< e
                }()
                let ids = _endnoteIDs(in: range, document)
                guard !ids.isEmpty, let slot = _pages.indices.last(where: { k in _pages[k].contains { $0.paragraph == e - 1 } }),
                      let piece = _pages[slot].last(where: { $0.paragraph == e - 1 }) else { continue }
                let p = slot / max(1, _columns)
                guard pages.contains(p) else { continue }
                let setup = pageSetup(forPage: p)
                let width = _px(setup.contentWidth)
                let notes = ids.compactMap { _endnote($0, width: width, document) }
                guard !notes.isEmpty else { continue }
                var top = pageRect(p).top + _pxMarginTop(p) + piece.pageY + piece.height
                let left = pageRect(p).left + _pxMarginLeft(p)
                if let separator = _endnote(-1, width: width, document) {
                    let line = Paint()
                    line.color = theme.textColor
                    canvas.drawRect(Rect.fromLTWH(left, top + separator.height / 2 - _px(0.36), _px(144), _px(0.72)), line)
                    top += separator.height
                }
                for note in notes {
                    canvas.save()
                    canvas.translate(left, top)
                    note.layout.paint(canvas, visible: Rect.fromLTWH(-100_000, -100_000, 200_000, 200_000), document: note.document, selection: nil, caret: nil)
                    canvas.restore()
                    top += note.height
                }
            }
            return
        }
        guard theme.wordRules, isPaged, pageSetup != nil, let last = document.paragraphs.indices.last, last < count else { return }
        let ids = _endnoteOrder(document)
        guard !ids.isEmpty else { return }
        // (Under the last paragraph's last piece, on its page.)
        guard let slot = _pages.indices.last(where: { k in _pages[k].contains { $0.paragraph == last } }),
              let piece = _pages[slot].last(where: { $0.paragraph == last }) else { return }
        let p = slot / max(1, _columns)
        guard pages.contains(p) else { return }
        var top = pageRect(p).top + _pxMarginTop(p) + piece.pageY + piece.height
        let setup = pageSetup(forPage: p)
        let width = _px(setup.contentWidth)
        let notes = ids.compactMap { _endnote($0, width: width, document) }
        guard !notes.isEmpty else { return }
        let separator = _endnote(-1, width: width, document)
        let rect = pageRect(p)
        let bottom = rect.bottom - _bodyInsets(page: p, document).bottom
        guard top + notes.reduce(0.0, { $0 + $1.height }) + (separator?.height ?? 0) <= bottom + 0.5 else { return }
        let left = rect.left + _pxMarginLeft(p)
        if let separator {
            let line = Paint()
            line.color = theme.textColor
            let mirrored = notes.first?.document.paragraphs.first?.style.rightToLeft == true
            canvas.drawRect(Rect.fromLTWH(mirrored ? left + width - _px(144) : left, top + separator.height / 2 - _px(0.36), _px(144), _px(0.72)), line)
            top += separator.height
        }
        for note in notes {
            canvas.save()
            canvas.translate(left, top)
            note.layout.paint(canvas, visible: Rect.fromLTWH(-100_000, -100_000, 200_000, 200_000), document: note.document,
                              selection: nil, caret: nil)
            canvas.restore()
            top += note.height
        }
    }

    /// Paint everything intersecting `visible` (CANVAS space), the canvas
    /// already translated so canvas (0, 0) is at the origin. `caret` is in
    /// canvas space too. `pageBackground` paints each visible page's paper
    /// before its text.
    public func paint(_ canvas: any Canvas, visible: Rect, document: RichDocument,
                      selection: RichSelection?, caret: Rect?,
                      pageBackground: ((Int, Rect) -> Void)? = nil) {
        _paintCaret = selection.flatMap { $0.isCollapsed ? $0.focus : nil }
        _behindDrawn = []
        if isPaged {
            let firstPage = page(atCanvasY: visible.top)
            let lastPage = page(atCanvasY: visible.bottom)
            for p in firstPage ... lastPage {
                pageBackground?(p, pageRect(p))
                _paintPageTile(p, canvas, document)
                _paintPageBorders(p, canvas, document)
                _paintHeaderFooter(p, canvas, document)
                _paintFootnotes(p, canvas, document)
            }
            _paintEndnotes(canvas, document, pages: firstPage ... lastPage)
        }
        // Three layers: table shading, the selection over it, then the text
        // and rules. (Shading painted with its paragraph covered a selected
        // cell's highlight.)
        _paintFlow(canvas, visible: visible, document: document, shading: true)
        if let selection, !selection.isCollapsed {
            let paint = Paint()
            paint.color = theme.selectionColor
            paint.style = .fill
            for r in canvasSelectionRects(selection, document)
            where r.bottom >= visible.top && r.top <= visible.bottom {
                canvas.drawRect(r, paint)
            }
        }
        if theme.wordRules, RichTextTheme.wordWindowsPages, isPaged, _inline.contains(where: { $0.contains { $0.isDropCap } }) {
            _dropCapPass = 1
            _paintFlow(canvas, visible: visible, document: document, shading: false)
            _dropCapPass = 2
            _paintFlow(canvas, visible: visible, document: document, shading: false)
            _dropCapPass = 0
        } else {
            _paintFlow(canvas, visible: visible, document: document, shading: false)
        }
        if let caret {
            let paint = Paint()
            paint.color = theme.caretColor
            paint.style = .fill
            canvas.drawRRect(RRect(fromRectAndRadius: caret, Radius(circular: 1)), paint)
        }
    }

    /// The lines a table row parted over a page's foot is closed with
    /// there and opened with on the next page, as Word draws them: the
    /// table's inside line, across the table, wherever a piece of the
    /// row's rules stops short of the row's own top or bottom.
    /// Whether every cell of the row of paragraphs `i ..< j` says it has
    /// no top line (`w:top` nil or none): a part of it that goes over to a
    /// new page opens with none (lab `tb`).
    static func _rowOpensBare(_ i: Int, _ j: Int, _ document: RichDocument) -> Bool {
        j > i && (i ..< min(j, document.paragraphs.count)).allSatisfy { document.paragraphs[$0].cell?.edges?.top == false }
    }

    /// A table with outer top and bottom lines and none between its rows.
    static func _partedFrame(_ ts: TableStyle) -> Bool {
        !ts.headerRow && ts.edges?.insideH == false && (ts.edges?.top ?? ts.borders) && (ts.edges?.bottom ?? ts.borders)
    }

    func _paintPartedRules(_ piece: PagePiece, _ canvas: any Canvas, _ document: RichDocument) {
        guard theme.wordRules, !piece.repeated, piece.part != .text, let c = _cells[piece.paragraph], c.firstInRow else { return }
        let ts = document.tableStyles[c.table]
        let framed = RichTextTheme.wordWindowsPages && ts.map(Self._partedFrame) == true
        guard ts?.edges?.insideH ?? ts?.borders ?? true || framed else { return }
        // (And over a row that starts a page under cells merged down
        // from the page before, which have no top of their own there.)
        let parted = piece.part == .rules && !piece.inner
        var end = piece.paragraph
        while end < _cells.count, let d = _cells[end], d.table == c.table, d.row == c.row { end += 1 }
        let opens = ((parted && piece.flowTop > c.rowTop + 0.5) || (piece.pageY < 0.01 && c.row > 0 && piece.flowTop < c.rowTop + 0.5))
            && !Self._rowOpensBare(piece.paragraph, end, document)
        let closes = parted && piece.flowBottom < c.rowTop + c.ownRowHeight - 0.5
        guard opens || closes else { return }
        let widths = _columnWidths[c.table] ?? []
        let left = (c.colLeft - widths.prefix(c.column).reduce(0, +)).rounded()
        let right = (left + widths.reduce(0, +)).rounded()
        let stroke = Paint()
        stroke.style = .stroke
        stroke.strokeWidth = max(1, _px(ts?.edgeWidths[framed ? "top" : "insideH"] ?? ts?.borderWidth ?? 0.5).rounded())
        stroke.color = ts?.borderColor ?? (theme.wordRules && RichTextTheme.wordWindowsPages ? Color(0xFF000000) : theme.textColor.withOpacity(0.6))
        let half = stroke.strokeWidth / 2
        if opens { canvas.drawLine(Offset(left, piece.flowTop + half), Offset(right, piece.flowTop + half), stroke) }
        // (Closed with the table's bottom line where that is the heavier,
        // from mode 14 on, as a page's part of a table is closed — lab
        // `ef2b` (Word 16 Mac): a row parted under a 2.25pt bottom line
        // and 0.5 inside ones has the heavy line under its part, straight
        // under its last line kept; zh-e1b09977 p14's part, 2.16 in
        // Word's print, was 0.5 in ours.)
        if closes {
            var width = stroke.strokeWidth
            if (document.compatibilityMode ?? 12) >= 14, let ts, ts.edges?.bottom ?? (ts.borders && !ts.bordersFromCells) {
                width = max(width, _px(ts.edgeWidths["bottom"] ?? ts.borderWidth ?? 0.5).rounded())
            }
            let close = Paint()
            close.style = .stroke
            close.strokeWidth = width
            close.color = stroke.color
            canvas.drawLine(Offset(left, piece.flowBottom - width / 2), Offset(right, piece.flowBottom - width / 2), close)
        }
    }

    /// Page `p`'s pieces moved down by the section's `w:vAlign` (keyed as
    /// `_lineNumberOrdinals`), nil where the page keeps to the top: the
    /// text's block centred between the margins, set on their foot, or
    /// (`both`) its paragraphs spread so the first stands at the top and
    /// the last at the foot.
    func _verticalAlignShifts(_ p: Int, _ document: RichDocument) -> [Int: Double]? {
        guard theme.wordRules, p >= 0, p < pageCount else { return nil }
        var members: [(key: Int, piece: PagePiece)] = []
        var extent = 0.0
        for column in 0 ..< _columns {
            let slot = p * _columns + column
            guard _pages.indices.contains(slot) else { continue }
            for (index, piece) in _pages[slot].enumerated() where piece.part != .rules && !piece.repeated {
                members.append((slot * 1_000_000 + index, piece))
                extent = max(extent, piece.pageY + piece.height)
            }
        }
        guard let first = members.first?.piece.paragraph, first < document.paragraphs.count,
              let align = _setup(ofParagraph: first).verticalAlign, align != "top" else { return nil }
        let setup = pageSetup(forPage: p)
        let room = _pxPageH(p) - _pxMarginTop(p) - _px(setup.marginBottom)
        // (The block runs down to the foot of a box the text goes round that
        // is placed from the page or margin: lo tdf36117's centred page, text
        // from the top margin to its 450pt frame's foot, 549pt, stands 50pt
        // down in Word's print, the frame where it is placed.)
        if theme.wordRules, let first = members.first?.piece.paragraph, first < document.paragraphs.count {
            for m in members where m.piece.part == .all {
                let i = m.piece.paragraph
                guard i < _inline.count, i < _tops.count, m.piece.flowTop <= _tops[i] + 0.5 else { continue }
                for image in _inline[i] {
                    guard let float = image.float, !float.takesRoom, float.wraps, float.verticalFrom == "page" || float.verticalFrom == "margin" else { continue }
                    let r = _floatRect(float, image, geometry(i), i)
                    extent = max(extent, m.piece.pageY - m.piece.flowTop + r.bottom)
                }
            }
        }
        let spare = room - extent
        guard spare > 0.5 else { return nil }
        var out: [Int: Double] = [:]
        switch align {
        case "center": for m in members { out[m.key] = spare / 2 }
        case "bottom": for m in members { out[m.key] = spare }
        case "both":
            // (By paragraph: a paragraph's pieces move together.)
            var order: [Int] = []
            for m in members where !order.contains(m.piece.paragraph) { order.append(m.piece.paragraph) }
            guard order.count > 1 else { return nil }
            for m in members { out[m.key] = spare * Double(order.firstIndex(of: m.piece.paragraph) ?? 0) / Double(order.count - 1) }
        default: return nil
        }
        return out
    }

    /// The lines of `piece` that Word numbers: those of a body paragraph
    /// (not a table's, a frame's or one that suppresses them) whose tops
    /// stand in the piece. Positions are the paragraph painter's own.
    func _numberedLines(_ piece: PagePiece, _ document: RichDocument) -> [LineMetrics] {
        let i = piece.paragraph
        guard i < document.paragraphs.count, i < _cells.count, i < _heights.count, piece.part != .rules, !piece.repeated,
              _cells[i] == nil, _heights[i] > 0 else { return [] }
        let p = document.paragraphs[i]
        guard p.style.frame == nil, p.style.eastAsian["w:suppressLineNumbers"] != "1",
              (p.style.eastAsian["w:suppressLineNumbers"] == "0" || document.styles.resolve(p.style)?.paragraph.eastAsian["w:suppressLineNumbers"] != "1") else { return [] }
        let g = geometry(i)
        // (A line is the piece's when its baseline stands in it.)
        let from = piece.flowTop - g.textTop, to = piece.flowBottom - g.textTop + 0.5
        return g.painter.computeLineMetrics().filter { $0.baseline > from && $0.baseline <= to }
    }

    /// How many numbered lines come before each piece, in its section's
    /// count (`restart`): keyed by slot * 1_000_000 + the piece's index.
    func _lineNumberOrdinals(_ document: RichDocument) -> [Int: Int] {
        var table: [Int: Int] = [:]
        var count = 0, lastPage = -1, lastSection = -1
        for slot in _pages.indices {
            let page = slot / max(1, _columns)
            for (index, piece) in _pages[slot].enumerated() {
                let i = piece.paragraph
                guard i < document.paragraphs.count, let numbering = _setup(ofParagraph: i).lineNumbers else { continue }
                let section = i < _sectionOf.count ? _sectionOf[i] : 0
                switch numbering.restart {
                case .newPage: if page != lastPage { count = 0 }
                case .newSection: if section != lastSection { count = 0 }
                case .continuous: break
                }
                lastPage = page; lastSection = section
                let lines = _numberedLines(piece, document)
                if lines.isEmpty { continue }
                table[slot * 1_000_000 + index] = count
                count += lines.count
            }
        }
        return table
    }

    /// The numbers' own character style: the file's "line number" style
    /// (its size), and never the paragraph's bold: jpn-fd00b5's numbers are
    /// 8 pt regular in Word, ours were 11 pt, bold in bold paragraphs.
    @inline(never) func _lineNumberChar(_ document: RichDocument) -> CharStyle {
        var c = CharStyle()
        guard theme.wordRules, RichTextTheme.wordWindowsPages, document.readFromFile else { return c }
        c.bold = false; c.off.insert(.bold)
        guard let id = document.keptCharacterStyleIds["line number"], let xml = document.keptCharacterStyles[id],
              let r = xml.rangeOfSubstring("<w:sz w:val=\"") else { return c }
        let rest = xml[r.upperBound...]
        if let q = rest.firstIndex(of: "\""), let half = Double(rest[..<q]) { c.fontSize = half / 2 }
        return c
    }

    func _paintLineNumbers(_ piece: PagePiece, ordinal: Int, origin: Offset, _ canvas: any Canvas, _ document: RichDocument) {
        let i = piece.paragraph
        guard let numbering = _setup(ofParagraph: i).lineNumbers else { return }
        let lines = _numberedLines(piece, document)
        guard !lines.isEmpty else { return }
        let p = document.paragraphs[i]
        // (In the paragraph's style, not its runs': Word's "Line Number"
        // is a character style on the paragraph's own.)
        let style = theme.textStyle(for: _lineNumberChar(document), in: p.style, named: _named(p, document), normal: _normalChar(document),
                                    scale: scale, fontScale: fontScale, gridPitch: nil)
        let g = geometry(i)
        let distance = _px(numbering.distance ?? 18)
        canvas.save()
        canvas.translate(origin.dx, origin.dy)
        for (k, m) in lines.enumerated() {
            let n = ordinal + k + 1
            guard n % numbering.countBy == 0 else { continue }
            let tp = TextPainter(text: TextSpan(text: String(numbering.start + n - 1), style: style), textDirection: .ltr)
            tp.layout(minWidth: 0, maxWidth: .infinity)
            let base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)
            tp.paint(canvas, Offset(-distance - tp.width, g.inkTop + _baselineShift(i, document) + m.baseline - base))
            tp.dispose()
        }
        canvas.restore()
    }

    /// Every visible paragraph, page by page and column by column: its
    /// table row's shading only (`shading`), or everything else.
    func _paintFlow(_ canvas: any Canvas, visible: Rect, document: RichDocument, shading: Bool) {
        if isPaged {
            let firstPage = page(atCanvasY: visible.top)
            let lastPage = page(atCanvasY: visible.bottom)
            let numbered = !shading && theme.wordRules && (pageSetup?.lineNumbers != nil || _sectionSetups.contains { $0.lineNumbers != nil })
            let ordinals = numbered ? _lineNumberOrdinals(document) : [:]
            for p in firstPage ... lastPage {
                let pageTop = pageRect(p).top + _pxMarginTop(p)
                let verticalShifts = _verticalAlignShifts(p, document)
                for column in 0 ..< _columns {
                    let slot = p * _columns + column
                    guard _pages.indices.contains(slot) else { continue }
                    let pageLeft = _pxMarginLeft(p) + Double(column) * _pxColumnStride(p)
                    for (pieceIndex, piece) in _pages[slot].enumerated() {
                        // (Each section's columns are its own: `_perSection`.)
                        var left = _perSection ? _pxColumnLeft(p, column: column, paragraph: piece.paragraph) : pageLeft
                        // (A continuous section with a side margin of its own
                        // sets its text from that: lo-eae9bbb1.)
                        if !_perSection, theme.wordRules, RichTextTheme.wordWindowsPages, !_mirrorsMargins, _columns == 1, _sectionSetups.count > 1 {
                            let s = _setup(ofParagraph: piece.paragraph)
                            if s.marginLeft != pageSetup(forPage: p).marginLeft { left = _px(s.marginLeft + s.gutter) }
                        }
                        let acrossTable = _cells[piece.paragraph].map { _acrossColumns($0.table, document) } ?? false
                        if acrossTable { left = _perSection ? _pxColumnLeft(p, column: 0, paragraph: piece.paragraph) : _pxMarginLeft(p) }
                        let columnW = _perSection ? _px(_setup(ofParagraph: piece.paragraph).columnWidth) : _pxColumnW(p)
                        let manyColumns = _perSection ? _columnsOf(paragraph: piece.paragraph) > 1 : _columns > 1
                        // One column clips to its own width; a lone column keeps
                        // the page, so a table wider than the text can still show.
                        // (Its side borders stand outside the text, by their space and width and the 1.4pt
                        // of Word's box: lo-cbb7657e's boxes in two columns lost their lines to this window.)
                        let sideBorders = manyColumns && theme.wordRules && RichTextTheme.wordWindowsPages
                            ? document.paragraphs[piece.paragraph].style.borders : nil
                        let columnClipL = manyColumns ? left - 1 - (sideBorders?.left.map { _px($0.space + $0.width + 1.4) } ?? 0) : 0
                        let columnClipR = manyColumns ? left + columnW + 1 + (sideBorders?.right.map { _px($0.space + $0.width + 1.4) } ?? 0) : _pxPageW(p)
                        // (A cover's one-column section, set across the page:
                        // `_fullWidthCover`.)
                        // (A margin-aligned float of a multi-column section
                        // stands outside its anchor's column: lo-7afc5602.)
                        let across = acrossTable || _fullWidthCover.contains(piece.paragraph)
                            || (_perSection && manyColumns && _marginFloat(piece.paragraph))
                            || (manyColumns && RichTextTheme.wordWindowsPages && _pageFloat(piece.paragraph) && _cells[piece.paragraph] == nil)
                            || (manyColumns && _tableOverflowsColumn(piece.paragraph, columnW))
                        let clipL = across ? 0 : columnClipL
                        let clipR = across ? _pxPageW(p) : columnClipR
                        let top = pageTop + piece.pageY + (verticalShifts?[slot * 1_000_000 + pieceIndex] ?? 0)
                        let bottom = top + piece.height
                        if bottom < visible.top || top > visible.bottom { continue }
                        canvas.save()
                        let lines = shading ? nil : _linesPainter(piece, document)
                        // A paragraph shown whole that carries a floating
                        // object is not cut to its own lines: the object
                        // stands where its anchor puts it, below or above
                        // them — four photos anchored to empty paragraphs
                        // were each a strip one line tall (zh-37b6536f).
                        let i = piece.paragraph
                        // (Whole, too, where all it left behind is its space
                        // before, dropped at the page's head: zh-4e5fe46f's
                        // 496pt table in a box, anchored in a one-line
                        // paragraph that opens page 7, was cut to that line
                        // and showed one row of eleven.)
                        let whole = piece.flowTop <= _tops[i] + (i < _spaceBefore.count ? _spaceBefore[i] : 0) + 0.5
                            && piece.flowBottom >= _tops[i] + _heights[i] - 0.5
                        // (A cell's text drawn whole too — a row's piece is
                        // its `.text`: zh-e49d7943's "附件3" box, 36pt over
                        // the title in the calendar's first row, was cut off
                        // at the row's top and drawn nowhere.)
                        let floats = theme.wordRules && (!shading || (piece.part != .rules && !_behindPictures(i).isEmpty)) && whole && (piece.part == .all || (piece.part == .text && _cells[i] != nil))
                            && ((i < _floatImages.count && _floatImages[i] != nil)
                                || (i < _inline.count && _inline[i].contains { $0.float.map { !$0.takesRoom } ?? false }))
                        // (The first piece of a paragraph that parts, its
                        // floats above it: nothing of the paragraph stands
                        // over its first line but them. zh-e49d7943's
                        // "附件2" box, 30.65pt over a title whose 660pt
                        // picture goes to the next page, was drawn nowhere.)
                        let opensWithFloats = theme.wordRules && !shading && !whole && piece.part == .all
                            && piece.flowTop <= _tops[i] + 0.5 && lines == nil
                            && ((i < _floatImages.count && _floatImages[i] != nil)
                                || (i < _inline.count && _inline[i].contains { $0.float.map { !$0.takesRoom } ?? false }))
                        // (A cell's text past its row of exact height, where
                        // nothing stands under the row on the page: Word draws
                        // it on, down the page. zh-340d52e9's "其他里內公共區域
                        // 認養之必要支出", five lines in a 48.8pt row that ends
                        // page 5, runs to 791 in Word's print; ours cut it at
                        // the row's foot.)
                        let overflowsExactRow: Bool = {
                            guard theme.wordRules, !shading, lines == nil, piece.part == .all, let c = _cells[i],
                                  document.tableStyles[c.table]?.rowsExactHeight.contains(c.row) == true,
                                  piece.flowBottom < _tops[i] + _heights[i] - 0.5 else { return false }
                            // (Rows of the same table under it do not stop it: zh-340d52e9's p5 cell, five lines
                            // in a 48.8pt exact row with more rows under, has all five in Word's print.)
                            return !_pages[slot].contains { $0.pageY > piece.pageY + piece.height - 0.5 && _cells[$0.paragraph].map { $0.table != c.table } ?? true }
                        }()
                        // (A later part of a paragraph that runs on, holding a float
                        // that stands in it: lo-ff3b52d1's rectangle, set from the
                        // column its anchor's line is in.)
                        let laterFloats: [(ImageFloat, ImageAttachment)] = {
                            guard theme.wordRules, RichTextTheme.wordWindowsPages, _columns > 1, !shading, !whole, piece.part == .all, lines == nil,
                                  piece.flowTop > _tops[i] + 0.5, i < _inline.count, _cells[i] == nil else { return [] }
                            let g = geometry(i)
                            return _inline[i].compactMap { image in
                                guard let float = image.float, !float.takesRoom, float.verticalFrom == "paragraph", float.verticalAlign == nil else { return nil }
                                let r = _floatRect(float, image, g, i)
                                return r.top >= piece.flowTop - 0.5 && r.top < piece.flowBottom ? (float, image) : nil
                            }
                        }()
                        if !laterFloats.isEmpty {
                            let g = geometry(i)
                            let window = Path()
                            window.addRect(Rect.fromLTRB(clipL, top, clipR, bottom + _baselineShift(i, document)))
                            for (float, image) in laterFloats {
                                window.addRect(_floatRect(float, image, g, i).shift(Offset(left, top - piece.flowTop)))
                            }
                            canvas.clipPath(window, doAntiAlias: false)
                        } else if lines != nil || floats || (theme.wordRules && !shading && whole && piece.part == .all && (document.paragraphs[i].image != nil || _inlinePictureOnly(i, document))) {
                            // Its own lines and no others: nothing to cut off above or below.
                            canvas.clipRect(Rect.fromLTRB(clipL, top - 1_000_000, clipR, bottom + 1_000_000))
                        } else if overflowsExactRow {
                            canvas.clipRect(Rect.fromLTRB(clipL, top + _baselineShift(i, document), clipR, pageRect(p).bottom))
                        } else if opensWithFloats {
                            // (… and those floats whole below it too, its own
                            // text still cut at the piece: zh-4e5fe46f's
                            // 496pt table in a box, anchored 38pt over a
                            // paragraph that parts at page 6's foot (a second
                            // picture in it), runs on down to the paper's edge
                            // in Word's print; ours showed its header row.)
                            let window = Path()
                            window.addRect(Rect.fromLTRB(clipL, top - 1_000_000, clipR, bottom + _baselineShift(i, document)))
                            if theme.wordRules, i < _inline.count {
                                let g = geometry(i)
                                for image in _inline[i] {
                                    guard let float = image.float, !float.takesRoom else { continue }
                                    window.addRect(_floatRect(float, image, g, i).shift(Offset(left, top - piece.flowTop)))
                                }
                            }
                            canvas.clipPath(window, doAntiAlias: false)
                        } else {
                            // The window moves with the text: a paragraph drawn
                            // above its line box (`baselineShift`) would
                            // otherwise show the tops of its next line here.
                            let dy = shading ? 0 : _baselineShift(piece.paragraph, document)
                            // (A piece that goes on from a line's cut starts a
                            // pixel under it: the engine's line boxes are whole
                            // pixels and the glyphs' ink is not, so the line
                            // above's descenders reach a hair past its cut, and
                            // their tips were drawn again at the next page's
                            // head — bug59058's "g g y" over page 25, which
                            // PDFKit reads as a line of text there.)
                            let inset = !shading && piece.flowTop > _tops[i] + 0.5 ? _px(0.75) : 0
                            // (A heavy rule under a row is centred on its edge: the half below stays inside the clip —
                            // lo-5b86b731's 6pt inside rules.)
                            var heavy = 0.0
                            if theme.wordRules, RichTextTheme.wordWindowsPages, !shading, let c = _cells[piece.paragraph],
                               let w = document.tableStyles[c.table]?.borderWidth, w >= 2 {
                                heavy = _px(w) / 2
                                RuleTrace.hit("word-heavy-table-rule-paints-its-lower-half-past-the-row")
                            }
                            canvas.clipRect(Rect.fromLTRB(clipL, top + dy + inset, clipR, bottom + dy + heavy))
                        }
                        canvas.translate(left, top - piece.flowTop)
                        if shading { _shadingFloats = floats; _paintShading(piece.paragraph, canvas, document, part: piece.part); _shadingFloats = false } else {
                            _floatColumnShift = (manyColumns && RichTextTheme.wordWindowsPages && _cells[piece.paragraph] == nil) ? left - _pxMarginLeft(p) : 0
                            if _dropCapPass == 2 { _paintDropCaps(piece.paragraph, canvas, document) } else { _paintParagraph(piece.paragraph, canvas, document, part: piece.part, lines: lines) }
                            _floatColumnShift = 0
                            if _dropCapPass != 2 { _paintPartedRules(piece, canvas, document) }
                            // (Word's print keeps the text an exact-height row
                            // cuts off, clipped and unseen, and a reader of the
                            // page finds it there: lo-c6cd222f's "BAR BBB" and
                            // "BAZ CCC", 20pt of space above lines in rows 17pt
                            // tall. The engine drops text wholly outside the
                            // clip, so the whole paragraph is drawn again at
                            // an alpha no eye sees.)
                            // (A centred cell's too where it is merged down, its text too tall to centre and set from the
                            // top: zh-df9310bd p8's "3.项目时间以证书时间为准；" and "4.专利申请项目…", under three exact
                            // rows of 25.7pt. Not one row's own: zh-16e0a12a's "经办人（签字）" form rows have none of it.)
                            if _dropCapPass != 2, theme.wordRules, RichTextTheme.wordWindowsPages, lines == nil, piece.part == .all || (piece.flowBottom >= _tops[piece.paragraph] - 0.5 && _heights[piece.paragraph] < 0.02 && document.paragraphs[piece.paragraph].text.isEmpty), !overflowsExactRow, let c = _cells[piece.paragraph], c.verticalAlign == nil || c.verticalAlign == "top" || (c.verticalAlign == "center" && c.rowSpan > 1),
                               document.tableStyles[c.table]?.rowsExactHeight.contains(c.row) == true,
                               // (An empty closing paragraph given no height — see `_heights[k] = 0.01` in the cell's
                               // layout — still has its number below the cut: lo-8ab44df5's "b)".)
                               piece.flowBottom < _tops[piece.paragraph] + (_heights[piece.paragraph] < 0.02 && document.paragraphs[piece.paragraph].text.isEmpty
                                                                              ? geometry(piece.paragraph).painter.height : _heights[piece.paragraph]) - 0.5 {
                                canvas.restore()
                                canvas.save()
                                // (Only what lies under the cut: the lines the
                                // row shows are not drawn twice.)
                                canvas.clipRect(Rect.fromLTRB(clipL, bottom + _baselineShift(piece.paragraph, document), clipR, pageRect(p).bottom))
                                canvas.translate(left, top - piece.flowTop)
                                let ghost = Paint()
                                ghost.color = Color(0x01000000)
                                canvas.saveLayer(nil, ghost)
                                _paintParagraph(piece.paragraph, canvas, document, part: piece.part, lines: nil)
                                canvas.restore()
                            }
                        }
                        lines?.painter.dispose()
                        canvas.restore()
                        // (A shaded paragraph that opens with a page break, after
                        // text on the page: Word shades a line-high strip at the
                        // flow cursor of the page it leaves: pbmid lab, sbox b2.)
                        if shading, theme.wordRules, RichTextTheme.wordWindowsPages, pieceIndex == _pages[slot].count - 1,
                           piece.part != .rules, _cells[piece.paragraph] == nil, piece.paragraph + 1 < document.paragraphs.count {
                            let nx = document.paragraphs[piece.paragraph + 1]
                            if nx.style.pageBreakInline, !nx.style.columnBreak, let fill = nx.style.fill, nx.text != "\u{FFFC}",
                               _cells[piece.paragraph + 1] == nil, let line = geometry(piece.paragraph + 1).painter.computeLineMetrics().first {
                                let paint = Paint()
                                paint.style = .fill
                                paint.color = fill
                                let y = bottom
                                if y + line.height <= pageRect(p).top + _pxPageH(p) - _px(pageSetup(forPage: p).marginBottom) + 0.5 {
                                    canvas.drawRect(Rect.fromLTRB((left - _px(1.4)).rounded(), y.rounded(), (left + columnW + _px(1.4)).rounded(), (y + line.height).rounded()), paint)
                                    RuleTrace.hit("word-shaded-page-break-paints-a-strip-on-the-page-it-leaves")
                                }
                            }
                        }
                        if _dropCapPass != 2, numbered, let ordinal = ordinals[slot * 1_000_000 + pieceIndex] {
                            _paintLineNumbers(piece, ordinal: ordinal, origin: Offset(left, top - piece.flowTop), canvas, document)
                        }
                    }
                }
            }
        } else {
            for i in paragraphs(intersecting: visible.top, visible.bottom) {
                let g = geometry(i)
                if g.bottom < visible.top || g.top > visible.bottom { continue }
                if shading { _paintShading(i, canvas, document) } else { _paintParagraph(i, canvas, document) }
            }
        }
    }
}

extension RichLayout {
    /// Where the body starts under a header whose picture is set against the page's top (nil: unchanged).
    /// Kept out of `_bodyInsets`, which is on the stack while the header is laid out.
    @inline(never)
    func _headerPictureBodyTop(_ header: _HeaderFooter, top: Double, marginTop: Double) -> Double? {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, let hp = header.document.paragraphs.first, hp.cell == nil,
              let natural = header.layout.theme.naturalLine(for: hp.runs.first?.style ?? CharStyle(), named: header.layout._named(hp, header.document), eastAsian: false) else { return nil }
        for image in hp.inlineImages.values {
            guard let float = image.float, float.takesRoom || float.bandsPage, !float.wraps, float.verticalFrom == "page",
                  (float.verticalAlign == nil || float.verticalAlign == "top"), float.y >= 0, float.y < 1, image.height > 0 else { continue }
            let foot = _px(float.y + image.height + float.distanceBottom + natural)
            if foot < top - 0.5 {
                RuleTrace.hit("word-header-picture-at-the-page-top-stands-from-the-page")
                return max(marginTop, foot)
            }
            return nil
        }
        return nil
    }
}

extension RichLayout {
    func _hasVisibleText(_ p: RichParagraph) -> Bool {
        p.text.unicodeScalars.contains { $0.value != 0xFFFC && $0.value != 0x20 }
    }

    /// Lab picline2 (Word for Windows, 11pt Malgun beside a 80pt picture, line 240/216/192/360): with `w:textAlignment`
    /// "bottom" the whole line stands 2.0 higher than without (baseline 171.3 against 173.4), and the next line is
    /// 1.1 lower than ours without it. A multiple under 1 shrinks the text's line (1.9 a tenth, the baseline taking
    /// 0.8 of it). Not for a picture alone: its mark's line follows `bodyHeight += (multiple - 1) * single`.
    @inline(never) func _pictureTextLineAdjust(_ i: Int, _ p: RichParagraph, multiple: Double, single: Double, bodyHeight: inout Double) {
        let bottom = p.style.eastAsian["w:textAlignment"] == "bottom"
        // (Only the cases the lab proved: with a multiple above 1 and no bottom alignment the 1.1 dropped zh-264d7516 and a8f4dfcd.)
        guard _hasVisibleText(p), bottom || multiple < 0.999 else { return }
        RuleTrace.hit("picture-text-line-lab-picline2")
        bodyHeight += _px(1.1)
        if bottom {
            _inkShift[i] -= _px(2.0)
            bodyHeight -= _px(2.0)
        }
        if multiple < 0.999 {
            let cut = (1 - multiple) * single  // (single is in pixels already)
            _inkShift[i] -= 0.8 * cut
            bodyHeight -= cut
        }
    }

    /// Whether a paragraph of several lines holds its equations after the first line, probed without a strut.
    @inline(never) func _equationsAfterFirstLine(_ span: TextSpan, _ dims: [PlaceholderDimensions], align: TextAlign, rtl: Bool, width: Double, indents: [LineIndent]) -> Bool {
        let probe = TextPainter(text: span, textAlign: align, textDirection: rtl ? .rtl : .ltr)
        defer { probe.dispose() }
        probe.fractionalLineHeights = theme.wordRules
        probe.lineIndents = indents
        probe.setPlaceholderDimensions(dims)
        probe.layout(minWidth: width, maxWidth: width)
        let lines = probe.computeLineMetrics()
        guard lines.count > 1, let first = lines.first, let boxes = probe.inlinePlaceholderBoxes, !boxes.isEmpty else { return false }
        return boxes.allSatisfy { $0.toRect().top >= first.height - 1 }
    }

    @inline(never) func _picturesOnFirstLineOnly(_ span: TextSpan, _ dims: [PlaceholderDimensions], align: TextAlign, rtl: Bool, width: Double, indents: [LineIndent]) -> Bool {
        let probe = TextPainter(text: span, textAlign: align, textDirection: rtl ? .rtl : .ltr)
        defer { probe.dispose() }
        probe.fractionalLineHeights = theme.wordRules
        probe.lineIndents = indents
        probe.setPlaceholderDimensions(dims)
        probe.layout(minWidth: width, maxWidth: width)
        let lines = probe.computeLineMetrics()
        guard lines.count > 1, let first = lines.first, let boxes = probe.inlinePlaceholderBoxes, !boxes.isEmpty else { return false }
        return boxes.allSatisfy { $0.toRect().bottom <= first.height + 0.5 }
    }

    /// Whether every box of the paragraph is an equation no taller than the line its strut holds once the multiple is taken off it (a taller one makes its line a multiple of its own height).
    @inline(never) func _equationsWithinStrut(_ span: TextSpan, _ dims: [PlaceholderDimensions], whole: [Double], near: Bool, wide: Bool, multiple: Double) -> Bool {
        guard !dims.isEmpty, let ref = _strut(span, near: near, wide: wide), let size = ref.fontSize, let h = ref.height else { return false }
        return dims.enumerated().allSatisfy { max($1.size.height, $0 < whole.count ? whole[$0] : 0) * multiple <= size * h + 0.01 }
    }
}
