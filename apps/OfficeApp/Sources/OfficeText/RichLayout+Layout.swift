// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// RichLayout, part "Layout": moved out of RichLayout.swift by test/tools/split-richlayout.py (a pure move, so that
// the parts compile side by side).

import Flutter
import FlutterSwiftBridge
import Foundation

extension RichLayout {

    /// Check the paragraphs paint queued, newest first, within `budget`
    /// milliseconds; true when anything was checked (a repaint is due).
    @discardableResult
    public func runSpellChecks(_ document: RichDocument, budget: Double = 8) -> Bool {
        guard let checker = spellChecker else { pendingSpellChecks = []; return false }
        if checker.version != _spellVersion { _spellCache = [:]; _spellVersion = checker.version }
        if _spellCache.count > 4096 { _spellCache = [:] }
        let start = Date()
        var checked = false
        var queue = pendingSpellChecks
        pendingSpellChecks = []
        while !queue.isEmpty {
            let i = queue.removeFirst()
            guard i < document.paragraphs.count else { continue }
            let text = document.paragraphs[i].text
            if _spellCache[text] != nil { continue }
            _spellCache[text] = checker.misspelledRanges(in: text)
            checked = true
            if Date().timeIntervalSince(start) * 1000 > budget { break }
        }
        pendingSpellChecks = queue
        return checked
    }

    /// The misspelled range at `pos`, if that paragraph has been checked.
    public func misspelling(at pos: RichPosition, _ document: RichDocument) -> Range<Int>? {
        guard pos.paragraph < document.paragraphs.count,
              let ranges = _spellCache[document.paragraphs[pos.paragraph].text] else { return nil }
        return ranges.first { $0.lowerBound <= pos.offset && pos.offset <= $0.upperBound }
    }

    func _paintSpelling(_ i: Int, _ g: ParagraphGeometry, _ canvas: any Canvas, _ document: RichDocument) {
        guard let checker = spellChecker else { return }
        if checker.version != _spellVersion { _spellCache = [:]; _spellVersion = checker.version }
        let para = document.paragraphs[i]
        guard !para.isImage, !para.text.isEmpty else { return }
        guard let ranges = _spellCache[para.text] else {
            if !pendingSpellChecks.contains(i) { pendingSpellChecks.append(i) }
            return
        }
        guard !ranges.isEmpty else { return }
        let map = _map(i)
        let paint = Paint()
        paint.style = .stroke
        paint.strokeWidth = 1
        paint.color = theme.spellingColor
        for r in ranges {
            if let c = _paintCaret, c.paragraph == i, r.lowerBound <= c.offset, c.offset <= r.upperBound { continue }
            for box in g.painter.getBoxesForSelection(TextSelection(baseOffset: map.painter(r.lowerBound), extentOffset: map.painter(r.upperBound)),
                                                      boxHeightStyle: .max) {
                let y = (g.inkTop + box.bottom - 1.5).rounded() + 0.5
                let x0 = g.textLeft + box.left, x1 = g.textLeft + box.right
                let path = Path()
                path.moveTo(x0, y)
                var x = x0
                var up = true
                while x < x1 {
                    x = min(x + 2, x1)
                    path.lineTo(x, up ? y - 1.5 : y)
                    up.toggle()
                }
                canvas.drawPath(path, paint)
            }
        }
    }

    public var count: Int { _painters.count }

    func _resize(_ n: Int) {
        _painters = Array(repeating: nil, count: n)
        _imageSize = Array(repeating: nil, count: n)
        _imageShift = Array(repeating: 0, count: n)
        _imageDrop = Array(repeating: 0, count: n)
        _inline = Array(repeating: [], count: n)
        _inlineBoxes = Array(repeating: [], count: n)
        _floats = Array(repeating: nil, count: n)
        _floatImages = Array(repeating: nil, count: n)
        _cells = Array(repeating: nil, count: n)
        _rowTops = Array(repeating: 0, count: n)
        _floatReach = Array(repeating: 0, count: n)
        _textLeft = Array(repeating: 0, count: n)
        _textWidth = Array(repeating: 0, count: n)
        _turnedFull = [:]
        _spaceBefore = Array(repeating: 0, count: n)
        _inkShift = Array(repeating: 0, count: n)
        _lineLift = Array(repeating: [], count: n)
        _overhang = Array(repeating: 0, count: n)
        _firstLineLift = Array(repeating: 0, count: n)
        _lineOverhang = Array(repeating: [], count: n)
        _floatPush = Array(repeating: 0, count: n)
        _floatTight = Array(repeating: false, count: n)
        _leadWidth = Array(repeating: 0, count: n)
        _besideLead = Array(repeating: 0, count: n)
        _besideRightSide = Array(repeating: false, count: n)
        _boxFirstLineShift = Array(repeating: 0, count: n)
        _leaders = Array(repeating: [], count: n)
        _inserts = Array(repeating: [], count: n)
        _heights = Array(repeating: 0, count: n)
        _tops = Array(repeating: 0, count: n)
        _listLabels = Array(repeating: nil, count: n)
        _listSig = Array(repeating: ListSig(kind: nil, level: 0, id: nil), count: n)
        _wasCell = Array(repeating: false, count: n)
        _pageBreak = Array(repeating: false, count: n)
        _tablesDirty = true
        _dirty = nil
        _firstDirty = 0
        _lastDirty = Int.max
        _topsValid = false
        _listValid = false
    }

    public func invalidateAll() {
        _cellMins.removeAll()
        for i in _painters.indices {
            _painters[i]?.dispose()
            _painters[i] = nil
        }
        _topsValid = false
        _listValid = false
        _pagesValid = false
        _dirty = nil
        _firstDirty = 0
        _lastDirty = Int.max
    }

    /// Apply the controller's change log, keeping every untouched painter.
    public func apply(_ changes: [RichChange], paragraphCount: Int) {
        for change in changes {
            switch change {
            case .all:
                invalidateAll()
                _resize(paragraphCount)
            case .lists:
                _listValid = false
            case .changed(let i):
                if i < _painters.count {
                    _painters[i]?.dispose()
                    _painters[i] = nil
                    _dirty?.append(i)
                    _firstDirty = min(_firstDirty ?? i, i)
                    _lastDirty = max(_lastDirty, i)
                    // A cell's text can change a row's height; its table's
                    // widths do not depend on it, but re-check cheaply.
                    if _wasCell[i] { _tablesDirty = true }
                    _cellMins[i] = nil
                }
            case .inserted(let at, let n):
                _mirrored.removeAll()
                _cellMins.removeAll()
                let at = min(at, _painters.count)
                _painters.insert(contentsOf: Array(repeating: nil, count: n), at: at)
                _imageSize.insert(contentsOf: Array(repeating: nil, count: n), at: at)
                _imageShift.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _imageDrop.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _inline.insert(contentsOf: Array(repeating: [], count: n), at: at)
                _inlineBoxes.insert(contentsOf: Array(repeating: [], count: n), at: at)
                _floats.insert(contentsOf: Array(repeating: nil, count: n), at: at)
                _floatImages.insert(contentsOf: Array(repeating: nil, count: n), at: at)
                _cells.insert(contentsOf: Array(repeating: nil, count: n), at: at)
                _rowTops.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _floatReach.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _textLeft.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _textWidth.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _spaceBefore.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _inkShift.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _lineLift.insert(contentsOf: Array(repeating: [], count: n), at: at)
                _overhang.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _firstLineLift.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _lineOverhang.insert(contentsOf: Array(repeating: [], count: n), at: at)
                _floatPush.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _floatTight.insert(contentsOf: Array(repeating: false, count: n), at: at)
                _leadWidth.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _besideLead.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _besideRightSide.insert(contentsOf: Array(repeating: false, count: n), at: at)
                _boxFirstLineShift.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _leaders.insert(contentsOf: Array(repeating: [], count: n), at: at)
                _inserts.insert(contentsOf: Array(repeating: [], count: n), at: at)
                _heights.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _tops.insert(contentsOf: Array(repeating: 0, count: n), at: at)
                _listLabels.insert(contentsOf: Array(repeating: nil, count: n), at: at)
                _listSig.insert(contentsOf: Array(repeating: ListSig(kind: nil, level: 0, id: nil), count: n), at: at)
                _wasCell.insert(contentsOf: Array(repeating: false, count: n), at: at)
                _pageBreak.insert(contentsOf: Array(repeating: false, count: n), at: at)
                _tablesDirty = true
                _listValid = false
                _dirty = nil
                _firstDirty = min(_firstDirty ?? at, at)
                _lastDirty = Int.max
            case .removed(let at, let n):
                _mirrored.removeAll()
                _cellMins.removeAll()
                let at = min(at, _painters.count)
                let end = min(at + n, _painters.count)
                for i in at ..< end { _painters[i]?.dispose() }
                _painters.removeSubrange(at ..< end)
                _imageSize.removeSubrange(at ..< end)
                _imageShift.removeSubrange(at ..< end)
                _imageDrop.removeSubrange(at ..< end)
                _inline.removeSubrange(at ..< end)
                _inlineBoxes.removeSubrange(at ..< end)
                _floats.removeSubrange(at ..< end)
                _floatImages.removeSubrange(at ..< end)
                _cells.removeSubrange(at ..< end)
                _rowTops.removeSubrange(at ..< end)
                _floatReach.removeSubrange(at ..< end)
                _textLeft.removeSubrange(at ..< end)
                _textWidth.removeSubrange(at ..< end)
                _spaceBefore.removeSubrange(at ..< end)
                _inkShift.removeSubrange(at ..< end)
                _lineLift.removeSubrange(at ..< end)
                _overhang.removeSubrange(at ..< end)
                _firstLineLift.removeSubrange(at ..< end)
                _lineOverhang.removeSubrange(at ..< end)
                _floatPush.removeSubrange(at ..< end)
                _floatTight.removeSubrange(at ..< end)
                _leadWidth.removeSubrange(at ..< end)
                _besideLead.removeSubrange(at ..< end)
                _besideRightSide.removeSubrange(at ..< end)
                _boxFirstLineShift.removeSubrange(at ..< end)
                _leaders.removeSubrange(at ..< end)
                _inserts.removeSubrange(at ..< end)
                _heights.removeSubrange(at ..< end)
                _tops.removeSubrange(at ..< end)
                _listLabels.removeSubrange(at ..< end)
                _listSig.removeSubrange(at ..< end)
                _wasCell.removeSubrange(at ..< end)
                _pageBreak.removeSubrange(at ..< end)
                _tablesDirty = true
                _dirty = nil
                _firstDirty = min(_firstDirty ?? at, at)
                _lastDirty = Int.max
                _listValid = false
            }
            _topsValid = false
            _pagesValid = false
        }
        if _painters.count != paragraphCount {
            // Defensive: the log and the document disagree — start over
            // rather than index past the end.
            invalidateAll()
            _resize(paragraphCount)
        }
    }

    // MARK: Laying out

    func _px(_ points: Double) -> Double { points * theme.pixelsPerPoint * scale }

    /// Lay out every invalidated paragraph and recompute the tops.
    static let _perf = ProcessInfo.processInfo.environment["STARLING_RICHTEXT_PERF"] != nil

    public func ensureLaidOut(_ document: RichDocument) {
        _shapesLeaveCell = Set(document.tableStyles.filter { $0.value.shapesLeaveCell }.map { $0.key })
        let t0 = Self._perf ? DispatchTime.now().uptimeNanoseconds : 0
        var marks: [(String, UInt64)] = []
        func mark(_ name: String) { if Self._perf { marks.append((name, DispatchTime.now().uptimeNanoseconds)) } }
        defer {
            if Self._perf, marks.count > 1 {
                var prev = t0
                var line = "richlayout:"
                for (name, t) in marks { line += " \(name)=\((t - prev) / 1000)us"; prev = t }
                FileHandle.standardError.write(Data((line + "\n").utf8))
            }
        }
        if _painters.count != document.paragraphs.count {
            invalidateAll()
            _resize(document.paragraphs.count)
        }
        _imageParagraphs = nil
        if _resolveSections(document) {
            // A section's page changed, or which paragraphs are in it:
            // everything wraps and paginates again.
            invalidateAll()
            _resize(document.paragraphs.count)
        }
        // The paragraphs to lay out: the ones changed since the last pass,
        // or every one without a painter after a structural change.
        let toLayout: [Int]
        if let dirty = _dirty {
            toLayout = dirty.count > 1 ? Array(Set(dirty)).sorted() : dirty
        } else {
            toLayout = _painters.indices.filter { _painters[$0] == nil }
        }
        _dirty = []
        // A paragraph whose list membership or cell changed since its last
        // layout invalidates the passes that depend on the whole document.
        for i in toLayout {
            let st = document.paragraphs[i].style
            let sig = ListSig(kind: st.list, level: st.listLevel, id: st.listId)
            if sig != _listSig[i] { _listValid = false; _listSig[i] = sig }
            let isCell = document.paragraphs[i].cell != nil
            if isCell != _wasCell[i] { _tablesDirty = true; _wasCell[i] = isCell }
            _pageBreak[i] = st.pageBreakBefore
        }
        mark("sigs")
        if !_listValid { _renumberLists(document) }
        var toLayoutNow = toLayout
        if _tablesDirty {
            _updateTables(document)
            _tablesDirty = false
            toLayoutNow = _painters.indices.filter { _painters[$0] == nil }
        }
        mark("lists+tables")
        var changed = false
        for i in toLayoutNow where _painters[i] == nil {
            _layoutParagraph(i, document.paragraphs[i], document)
            changed = true
        }
        mark("paragraphs")
        // Placement and pagination restart at the first changed paragraph
        // (its row's first member); everything above is as it was.
        // (_topsValid only says the tops need recomputing; the ones above
        // the first change are still right, which is what makes the
        // restart possible.)
        var from = min(_firstDirty ?? 0, max(0, _heights.count - 1))
        // Inside a table, restart at the table's first paragraph: a cell
        // spanning rows above the change decides heights below it.
        while from > 0, let c = _cells[from], let d = _cells[from - 1], c.table == d.table { from -= 1 }
        let settled = _lastDirty   // paragraphs above this may have moved
        if changed || !_topsValid {
            _placeBlocks(document, from: from, settled: settled)
            _topsValid = true
            _pagesValid = false
        }
        mark("place")
        if pageSetup != nil && !_pagesValid { _paginate(document, from: from, settled: settled) }
        _firstDirty = nil
        _lastDirty = 0
        mark("paginate")
        // Indents that depend on the page: Word mirrors a paragraph's
        // indents (`w:mirrorIndents`) on pages 2, 4… and sets them as
        // written on 1, 3… where the file's compatibility settings say
        // `doNotFlipMirrorIndents` (lab `mirch1`, in zh-06c46ba9's
        // package: a first line of 28pt ends every line that much short
        // of the right margin on page 2, not on page 1); without it, the
        // other way round (zh-e27cd8bf's first lines of 30.6pt end its
        // lines short on pages 17 and 19, not 18).
        // Laid out again where a paragraph's page says otherwise than
        // last time, until nothing moves (a few passes at most).
        // The paragraphs set beside a table floating by the text: the stretch of
        // it they share is the part of it on their page (zh: LibreOffice's
        // floattable-leftover-para-portion has only the last row of its table
        // on page 2, and two lines beside it). Laid out again where the page
        // says otherwise than the last layout did.
        if theme.wordRules, RichTextTheme.wordWindowsPages, pageSetup != nil, !_besidePassing, _besideLead.contains(where: { $0 > 0 }) {
            _besidePassing = true
            defer { _besidePassing = false }
            for _ in 0 ..< 3 {
                var changes: [RichChange] = []
                for k in _besideLead.indices where _besideLead[k] > 0 {
                    guard !_besideUnion.contains(k), k < _pieceStart.count, _pieceStart[k] < _allPieces.count, k > 0, let table = _besideSource(k, document)?.cell.table else { continue }
                    let first = _allPieces[_pieceStart[k]]
                    let mine = _pages[first.page].filter { _cells[$0.paragraph]?.table == table && !$0.repeated }
                    guard let floor = mine.map({ $0.pageY + ($0.flowBottom - $0.flowTop) }).max(),
                          let ceiling = mine.map({ $0.pageY }).min() else { continue }
                    // (The room under it that its bottomFromText keeps is beside it too: lo-f48e444e's
                    // second paragraph has its fourth line 50pt under the table's foot, inside its
                    // 56.7pt distance, beside it in Word's print, and the fifth at the margin.)
                    let keep = _px(document.tableStyles[table]?.floatBottomGap ?? 0)
                    let band = (top: max(0, ceiling - first.pageY), bottom: max(0, floor + keep - first.pageY))
                    // (… and on the pages after it: the paragraph's piece there, level with
                    // the rest of the float.)
                    var more: [(top: Double, bottom: Double)] = []
                    let end = k + 1 < _pieceStart.count ? _pieceStart[k + 1] : _allPieces.count
                    for piece in _allPieces[(_pieceStart[k] + 1) ..< max(_pieceStart[k] + 1, min(end, _allPieces.count))] where piece.page != first.page {
                        let rows = _pages[piece.page].filter { _cells[$0.paragraph]?.table == table && !$0.repeated }
                        guard let f = rows.map({ $0.pageY + ($0.flowBottom - $0.flowTop) }).max(), let c = rows.map(\.pageY).min() else { continue }
                        more.append((top: piece.flowTop - first.flowTop + max(0, c - piece.pageY), bottom: piece.flowTop - first.flowTop + max(0, f - piece.pageY)))
                    }
                    let sameMore = (_besideMoreBands[k] ?? []).count == more.count && zip(_besideMoreBands[k] ?? [], more).allSatisfy { abs($0.top - $1.top) < 0.5 && abs($0.bottom - $1.bottom) < 0.5 }
                    if sameMore, let old = _besideBandUse[k], abs(old.top - band.top) < 0.5, abs(old.bottom - band.bottom) < 0.5 { continue }
                    if sameMore, _besideBandUse[k] == nil, let was = _besideBand(k, document), abs(was.top - band.top) < 0.5, abs(was.bottom - band.bottom) < 0.5 { continue }
                    _besideBandUse[k] = band
                    _besideMoreBands[k] = more
                    changes.append(.changed(k))
                }
                if changes.isEmpty { break }
                apply(changes, paragraphCount: document.paragraphs.count)
                ensureLaidOut(document)
            }
        }
        // The text round what the page fixes: a style's frame, centred and aligned on the
        // margins (lo special_styles), or a box that wraps the text, aligned on the page or
        // its margins (lo tdf36117's centred ones). Their place does not depend on the flow.
        // The page is where the paragraph holding them stands; every line there level with
        // one is held in to the side with the room, and laid out again until the lines settle.
        if theme.wordRules, RichTextTheme.wordWindowsPages, pageSetup != nil, _columns == 1, !_stripPassing,
           document.paragraphs.contains(where: { ($0.cell == nil && Self._stripFrame($0.style)) || Self._pageBox($0) != nil })
            || (theme.wordRules && RichTextTheme.wordWindowsPages && pageSetup != nil && _columns == 1 && !_stripPassing
                && document.headerFooters.contains(where: { $0.paragraphs.contains { Self._hfBox($0) != nil } }))
            || (theme.wordRules && RichTextTheme.wordWindowsPages && pageSetup != nil && _columns == 1 && !_stripPassing
                && document.tableStyles.values.contains(where: { Self._floatTopGap($0) > 0 })) {
            _stripPassing = true
            defer { _stripPassing = false }
            for _ in 0 ..< 4 {
                var want: [Int: (indent: Double, band: (top: Double, bottom: Double), right: Bool)] = [:]
                // (What stands in the way: its page, its place from the text area's top and
                // from the page's left, its room kept clear at each side, the sides text may
                // take, and the paragraph that is itself the frame, set apart.)
                var blocks: [(page: Int, frame: Int?, top: Double, h: Double, x0: Double, w: Double, spaceL: Double, spaceR: Double, side: String?)] = []
                for (f, fp) in document.paragraphs.enumerated() where fp.cell == nil && f < _pieceStart.count && _pieceStart[f] < _allPieces.count {
                    let first = _allPieces[_pieceStart[f]]
                    let setup = pageSetup(forPage: first.page)
                    if Self._stripFrame(fp.style), let frame = fp.style.frame, let fw = frame.width, let fh = frame.height,
                       frame.horizontalAnchor == "page", frame.horizontalAlign == "center" {
                        let insets = _bodyInsets(page: first.page, document)
                        let contentH = max(1, _px(setup.height) - insets.top - insets.bottom)
                        let h = _px(fh), w = _px(fw)
                        let top = frame.verticalAlign == "top" ? 0 : frame.verticalAlign == "center" ? (contentH - h) / 2 : contentH - h
                        let xml = fp.style.frameXML ?? ""
                        let space = xml.firstRange(of: "w:hSpace=\"").flatMap { r in Double(xml[r.upperBound...].prefix { $0 != "\"" }) }.map { _px($0 / 20) } ?? 0
                        blocks.append((first.page, f, top, h, (_px(setup.width) - w) / 2, w, space, space, nil))
                    }
                    if let box = Self._pageBox(fp) {
                        let float = box.float, image = box.image
                        let pageH = _px(setup.height), marginTop = _px(setup.marginTop), marginBottom = _px(setup.marginBottom)
                        let h = _px(image.height), w = _px(image.width)
                        let whole = h + _px(float.effectBottom)
                        let base = float.verticalFrom == "page" ? 0 : marginTop
                        let span = float.verticalFrom == "page" ? pageH : pageH - marginTop - marginBottom
                        let a = float.verticalAlign ?? "top"
                        let onPage = base + (a == "center" ? (span - whole) / 2 : a == "bottom" ? span - whole : 0)
                        let physical = first.page / _columns
                        let insetTop = physical < _pageInsetTop.count ? _pageInsetTop[physical] : marginTop
                        let left = float.horizontalFrom == "page" ? 0 : _px(setup.marginLeft + setup.gutter)
                        let across = float.horizontalFrom == "page" ? _px(setup.width) : _px(setup.contentWidth)
                        let x0: Double
                        switch float.horizontalAlign {
                        case "center": x0 = left + (across - w) / 2
                        case "right": x0 = left + across - w
                        case "left": x0 = left
                        default: x0 = left + _px(float.x)
                        }
                        blocks.append((first.page, nil, onPage - insetTop, whole, x0, w, _px(float.distanceLeft ?? 9), _px(float.distanceRight ?? 9), float.wrapSide))
                    }
                }
                // (And a header's or footer's own boxes that the text goes round: Word wraps the
                // body round a sidebar picture anchored in the header — lo tdf38575's, 84pt wide
                // and the page's height, holds every line of the body in 18pt.)
                if document.headerFooters.contains(where: { $0.paragraphs.contains { Self._hfBox($0) != nil } }) {
                    for page in _pages.indices {
                        let setup = pageSetup(forPage: page)
                        let pageH = _px(setup.height), marginTop = _px(setup.marginTop), marginBottom = _px(setup.marginBottom)
                        let insetTop = page < _pageInsetTop.count ? _pageInsetTop[page] : marginTop
                        for kind in [KeptHeaderFooter.Kind.header, .footer] {
                            guard let hf = _headerFooter(kind, page: page, document, pageCount: 1) else { continue }
                            let region = kind == .header
                                ? hf.pageAnchoredTop.map { min(_px($0), _px(setup.headerDistance)) } ?? _px(setup.headerDistance)
                                : pageH - _px(setup.footerDistance) - hf.height
                            for (j, hp) in hf.document.paragraphs.enumerated() {
                                guard let box = Self._hfBox(hp) else { continue }
                                let float = box.float, image = box.image
                                let w = _px(image.width), whole = hf.layout._fittedBoxHeight(image, hf.document) + _px(float.effectBottom)
                                var onPage: Double
                                switch float.verticalFrom {
                                case "page", "margin", "topMargin":
                                    let base = float.verticalFrom == "page" ? 0 : marginTop
                                    let span = float.verticalFrom == "page" ? pageH : pageH - marginTop - marginBottom
                                    switch float.verticalAlign {
                                    case "center": onPage = base + (span - whole) / 2
                                    case "bottom": onPage = base + span - whole
                                    case "top": onPage = base
                                    default: onPage = base + _px(float.y)
                                    }
                                default:
                                    guard float.verticalAlign == nil else { continue }
                                    onPage = region + (j < hf.layout._tops.count ? hf.layout._tops[j] : 0) + _px(float.y)
                                }
                                let left = float.horizontalFrom == "page" ? 0 : _px(setup.marginLeft + setup.gutter)
                                let across = float.horizontalFrom == "page" ? _px(setup.width) : _px(setup.contentWidth)
                                let x0: Double
                                switch float.horizontalAlign {
                                case "center": x0 = left + (across - w) / 2
                                case "right": x0 = left + across - w
                                case "left": x0 = left
                                default: x0 = left + _px(float.x)
                                }
                                blocks.append((page, nil, onPage - insetTop, whole, x0, w, _px(float.distanceLeft ?? 9), _px(float.distanceRight ?? 9), float.wrapSide))
                            }
                        }
                    }
                }
                for block in blocks {
                    let colLeft = _px(pageSetup(forPage: block.page).marginLeft + pageSetup(forPage: block.page).gutter)
                    for piece in _pages[block.page] where piece.paragraph != block.frame && !piece.repeated {
                        let k = piece.paragraph
                        let q = document.paragraphs[k]
                        guard q.cell == nil, q.style.frame == nil, !q.text.isEmpty, !q.style.rightToLeft, k < _heights.count, want[k] == nil else { continue }
                        let rise = piece.flowBottom - piece.flowTop
                        guard piece.pageY < block.top + block.h - 0.01, piece.pageY + rise > block.top + 0.01 else { continue }
                        let column = _flowWidth(k)
                        let size = _px(q.runs.first?.style.fontSize ?? theme.fontSize)
                        let own = _px(q.style.indentLeft), rightGap = _px(q.style.indentRight)
                        var leftRoom = (block.x0 - block.spaceL - colLeft) - own
                        var rightRoom = (colLeft + column - rightGap) - (block.x0 + block.w + block.spaceR)
                        if block.side == "left" { rightRoom = 0 } else if block.side == "right" { leftRoom = 0 }
                        guard max(leftRoom, rightRoom) >= size * 2 else { continue }
                        // (The piece's flow offsets are the flow's; the band is from the paragraph's top.)
                        let fromTop = piece.flowTop - (k < _tops.count ? _tops[k] : 0)
                        let band = (top: block.top - piece.pageY + fromTop, bottom: block.top + block.h - piece.pageY + fromTop)
                        if rightRoom >= leftRoom {
                            want[k] = ((block.x0 + block.w + block.spaceR) - colLeft - own, band, false)
                        } else {
                            want[k] = (column - rightGap - (block.x0 - block.spaceL - colLeft), band, true)
                        }
                    }
                }
                // (A table floating by the text whose room above it, `w:topFromText`, reaches up into
                // the text before it on its page: the lines level with that room or the table wrap
                // beside it, as the text after it does, and the table keeps the place it had before
                // they did. lo-f48e444e, a 319pt table at tblpY 1 twip with 567 twips kept above it
                // and 1134 below: Word's print sets all four lines of the 21-word paragraph before it
                // beside it at 390.3, where ours had one line across the page; the table stays at
                // 121.8, where that one line leaves it; and the paragraph after it goes on under the
                // four lines, 170.2, beside it still.)
                var pins: [String: (page: Int, y: Double)] = [:]
                var firstOf: [String: Int] = [:]
                for (k, c) in _cells.enumerated() { if let c, firstOf[c.table] == nil { firstOf[c.table] = k } }
                for (t, f) in firstOf.sorted(by: { $0.value < $1.value }) {
                    guard let ts = document.tableStyles[t], case let gap = Self._floatTopGap(ts), gap > 0, ts.floatsOverText,
                          !ts.pageAnchored, ts.floatRaiseY == nil, f < _pieceStart.count, _pieceStart[f] < _allPieces.count else { continue }
                    let page = _allPieces[_pieceStart[f]].page
                    let rows = _pages[page].filter { _cells[$0.paragraph]?.table == t && !$0.repeated }
                    guard let ceiling = rows.map(\.pageY).min(),
                          let floor = rows.map({ $0.pageY + ($0.flowBottom - $0.flowTop) }).max() else { continue }
                    let top = ceiling - _px(gap), bottom = floor + _px(ts.floatBottomGap ?? 0)
                    var reached = false
                    for piece in _pages[page] where piece.paragraph < f && !piece.repeated {
                        let k = piece.paragraph
                        let q = document.paragraphs[k]
                        guard q.cell == nil, q.style.frame == nil, k < _heights.count, want[k] == nil else { continue }
                        let rise = piece.flowBottom - piece.flowTop
                        guard piece.pageY < bottom - 0.01, piece.pageY + rise > top + 0.01,
                              let side = _besideIndent(k, q, document, table: t) else { continue }
                        let fromTop = piece.flowTop - (k < _tops.count ? _tops[k] : 0)
                        want[k] = (side.indent, (top: top - piece.pageY + fromTop, bottom: bottom - piece.pageY + fromTop), side.right)
                        reached = true
                    }
                    if reached {
                        RuleTrace.hit("word-text-before-a-float-wraps-beside-it-where-its-top-distance-reaches")
                        pins[t] = _floatPin[t] ?? (page, ceiling - _px(ts.floatOffsetY ?? 0))
                    }
                }
                var changes: [RichChange] = []
                for t in Set(pins.keys).union(_floatPin.keys) {
                    if let a = pins[t], let b = _floatPin[t], a.page == b.page, abs(a.y - b.y) < 0.01 { continue }
                    if let f = firstOf[t] { changes.append(.changed(f)) }
                }
                _floatPin = pins
                for k in Set(want.keys).union(_stripUse.keys) {
                    let a = want[k], b = _stripUse[k]
                    if let a, let b, abs(a.indent - b.indent) < 0.5, a.right == b.right, abs(a.band.top - b.band.top) < 0.5, abs(a.band.bottom - b.band.bottom) < 0.5 { continue }
                    if a == nil, b == nil { continue }
                    _stripUse[k] = a
                    changes.append(.changed(k))
                }
                if changes.isEmpty { break }
                apply(changes, paragraphCount: document.paragraphs.count)
                ensureLaidOut(document)
            }
        }
        // (A paragraph that parts at a page's foot is held in by the box beside it on its first page
        // only: the lines that go on are set across the page, in Word's print — lo
        // tdf154703_framePrWrapSpacing's page 2 opens "happening of course. On each round-trip, you
        // can clearly", where ours set "happening of" short of a frame that stands on page 1.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, pageSetup != nil, _columns == 1, !_capPassing, !_stripPassing, !_colWrapPassing {
            _capPassing = true
            defer { _capPassing = false }
            for _ in 0 ..< 3 {
                var changes: [RichChange] = []
                for (k, q) in document.paragraphs.enumerated() where q.cell == nil && !q.text.isEmpty && k < _pieceStart.count && _pieceStart[k] < _allPieces.count && k < _tops.count {
                    let end = k + 1 < _pieceStart.count ? _pieceStart[k + 1] : _allPieces.count
                    let mine = _allPieces[_pieceStart[k] ..< min(end, _allPieces.count)].filter { !$0.repeated }
                    var want: Double? = nil
                    if let first = mine.first, let last = mine.last, first.page != last.page, _bandCap[k] != nil || _besideLead[k] == 0,
                       k < _inline.count, _inline[k].contains(where: { $0.float.map { $0.wraps && !$0.takesRoom } ?? false }),
                       let own = _besideOwn(k, q, document), own.leftRoom == nil {
                        let cap = first.flowBottom - _tops[k]
                        if own.band.bottom > cap + 0.5, own.band.top < cap { want = cap }
                    }
                    if let a = want, let b = _bandCap[k], abs(a - b) < 0.5 { continue }
                    if want == nil, _bandCap[k] == nil { continue }
                    _bandCap[k] = want
                    changes.append(.changed(k))
                }
                if changes.isEmpty { break }
                RuleTrace.hit("word-box-holds-in-only-its-pages-lines")
                apply(changes, paragraphCount: document.paragraphs.count)
                ensureLaidOut(document)
            }
        }
        // (A box the text keeps above and below, in a paragraph that runs on into
        // another column: its lines clear it where it stands in the column its
        // anchor's line is in — lo-ff3b52d1's rectangle, 81pt under the head of
        // that column's part, with the line that would meet it set under it.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, pageSetup != nil, _columns > 1, !_clearPassing, !_colWrapPassing, !_stripPassing {
            _clearPassing = true
            defer { _clearPassing = false }
            for _ in 0 ..< 3 {
                var changes: [RichChange] = []
                for (k, q) in document.paragraphs.enumerated() where q.cell == nil && !q.text.isEmpty && !q.style.rightToLeft && k < _pieceStart.count && _pieceStart[k] < _allPieces.count && k < _tops.count {
                    var want: (top: Double, bottom: Double)? = nil
                    let end = k + 1 < _pieceStart.count ? _pieceStart[k + 1] : _allPieces.count
                    let mine = _allPieces[_pieceStart[k] ..< min(end, _allPieces.count)].filter { !$0.repeated }
                    if mine.count > 1, k < _inline.count, k < _inlineBoxes.count, let g = Optional(geometry(k)), let all = g.painter.inlinePlaceholderBoxes {
                        for (n, image) in _inline[k].enumerated() {
                            guard let float = image.float, float.takesRoom || float.bandsPage, !float.wraps, float.verticalAlign == nil,
                                  float.verticalFrom == "paragraph", float.y > 0, n < _inlineBoxes[k].count, _inlineBoxes[k][n] < all.count else { continue }
                            let at = g.inkTop + all[_inlineBoxes[k][n]].top
                            guard let piece = mine.last(where: { $0.flowTop <= at + 0.01 }) else { break }
                            let base = piece.flowTop - _tops[k]
                            want = (base + _px(float.y - float.distanceTop), base + _px(float.y + image.height + float.effectBottom + float.distanceBottom))
                            break
                        }
                    }
                    if let a = want, let b = _clearBand[k], abs(a.top - b.top) < 0.5, abs(a.bottom - b.bottom) < 0.5 { continue }
                    if want == nil, _clearBand[k] == nil { continue }
                    _clearBand[k] = want
                    changes.append(.changed(k))
                }
                if changes.isEmpty { break }
                RuleTrace.hit("word-box-kept-clear-in-the-column-its-anchor-is-in")
                apply(changes, paragraphCount: document.paragraphs.count)
                ensureLaidOut(document)
            }
        }
        if theme.wordRules, RichTextTheme.wordWindowsPages, pageSetup != nil, _columns > 1, !_colWrapPassing, !_stripPassing {
            _colWrapPassing = true
            defer { _colWrapPassing = false }
            for _ in 0 ..< 4 {
                var changes: [RichChange] = []
                for (k, q) in document.paragraphs.enumerated() where q.cell == nil && !q.text.isEmpty && k < _pieceStart.count && _pieceStart[k] < _allPieces.count && k < _tops.count {
                    var want: [ColWrapBox] = []
                    if let box = Self._otherColumnsBox(q) {
                        let float = box.float, image = box.image
                        let end = k + 1 < _pieceStart.count ? _pieceStart[k + 1] : _allPieces.count
                        let mine = _allPieces[_pieceStart[k] ..< min(end, _allPieces.count)].filter { !$0.repeated }
                        if let first = mine.first {
                            let physical = first.page / _columns
                            let colW = _flowWidth(k)
                            let anchorLeft = _pxColumnLeft(first.page, column: first.page % _columns, paragraph: k)
                            if image.textBox?.fitsText == true { _ = _textBox(image, document) }
                            // (A fit-to-text box that outgrew its stored width stands as wide as its text: zh-2e7ef069's
        // "- 11 -" in a 36pt box is set from the margin at 479 in Word's print, 42pt in.)
        let fitted = image.textBox.flatMap { _fitWidths["\(image.id)|\($0.hashValue)"] }
        let w = theme.wordRules && RichTextTheme.wordWindowsPages && image.textBox?.fitsOnce == true
            ? (fitted ?? _px(image.width)) : min(_px(image.width), fitted ?? .infinity), h = _px(image.height)
                            let floatL = anchorLeft + _px(float.x) - _px(float.distanceLeft ?? 9)
                            let floatR = anchorLeft + _px(float.x) + w + _px(float.distanceRight ?? 9)
                            // (Whether it reaches out of its own column at all: the ones that stay in it
                            // are the paragraph's own `_besideOwn`.)
                            if floatR > anchorLeft + colW + 0.5 || floatL < anchorLeft - 0.5 {
                                let top0 = first.pageY - (first.flowTop - _tops[k]) + _px(float.y) - _px(float.distanceTop)
                                let bottom0 = first.pageY - (first.flowTop - _tops[k]) + _px(float.y) + h + _px(float.effectBottom) + _px(float.distanceBottom)
                                let size = _px(q.runs.first?.style.fontSize ?? theme.fontSize)
                                let own = _px(q.style.indentLeft), rightGap = _px(q.style.indentRight)
                                for piece in mine where piece.page / _columns == physical {
                                    let left = _pxColumnLeft(piece.page, column: piece.page % _columns, paragraph: k)
                                    guard floatR > left + 0.5, floatL < left + colW - 0.5 else { continue }
                                    let fromTop = piece.flowTop - _tops[k]
                                    let top = top0 - piece.pageY + fromTop, bottom = bottom0 - piece.pageY + fromTop
                                    guard bottom > 0.01 else { continue }
                                    let leftRoom = floatL - (left + own)
                                    let rightRoom = (left + colW - rightGap) - floatR
                                    guard max(leftRoom, rightRoom) >= size * 2 else { continue }
                                    if rightRoom >= leftRoom {
                                        want.append(ColWrapBox(top: top, bottom: bottom, left: floatR - left - own, right: 0))
                                    } else {
                                        want.append(ColWrapBox(top: top, bottom: bottom, left: 0, right: colW - rightGap - (floatL - left)))
                                    }
                                }
                            }
                        }
                    }
                    if _setup(ofParagraph: k).columnSpec != nil {
                        let end = k + 1 < _pieceStart.count ? _pieceStart[k + 1] : _allPieces.count
                        want += _specInsetBoxes(k, _allPieces[_pieceStart[k] ..< min(end, _allPieces.count)])
                    }
                    if want.isEmpty, _colWrap[k] == nil { continue }
                    if let old = _colWrap[k], old.count == want.count, zip(old, want).allSatisfy({ abs($0.top - $1.top) < 0.5 && abs($0.bottom - $1.bottom) < 0.5 && abs($0.left - $1.left) < 0.5 && abs($0.right - $1.right) < 0.5 }) { continue }
                    _colWrap[k] = want.isEmpty ? nil : want
                    changes.append(.changed(k))
                }
                if changes.isEmpty { break }
                RuleTrace.hit("word-wraps-the-other-columns-round-a-shape")
                apply(changes, paragraphCount: document.paragraphs.count)
                ensureLaidOut(document)
            }
        }
        // (A page's text starts under its header's boxes that reach into the body and leave no
        // room beside them: `_headerBoxFloor`. The first paragraph's line goes down, as under a
        // float of its own, and the objects it holds keep their place.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, pageSetup != nil, _columns == 1, !_headPassing,
           document.headerFooters.contains(where: { $0.paragraphs.contains { Self._hfWrapBoxes($0).contains { $0.float.wraps || $0.float.bandsPage } } }) {
            _headPassing = true
            defer { _headPassing = false }
            for _ in 0 ..< 3 {
                var want: [Int: Double] = [:]
                for page in _pages.indices {
                    let physical = page / max(1, _columns)
                    guard physical < _pageInsetTop.count, let hf = _headerFooter(.header, page: page, document, pageCount: 1),
                          let floor = _headerBoxFloor(hf, pageSetup(forPage: page)),
                          let first = _pages[page].first(where: { !$0.repeated }), first.paragraph < document.paragraphs.count,
                          first.paragraph < _cells.count, _cells[first.paragraph] == nil,
                          first.paragraph < _pieceStart.count, _pieceStart[first.paragraph] < _allPieces.count,
                          _allPieces[_pieceStart[first.paragraph]] == first else { continue }
                    let under = floor - _pageInsetTop[physical] - first.pageY
                    if under > 0.5 { want[first.paragraph] = under }
                }
                var changes: [RichChange] = []
                for k in Set(want.keys).union(_headPushUse.keys) {
                    if let a = want[k], let b = _headPushUse[k], abs(a - b) < 0.5 { continue }
                    _headPushUse[k] = want[k]
                    changes.append(.changed(k))
                }
                if changes.isEmpty { break }
                apply(changes, paragraphCount: document.paragraphs.count)
                ensureLaidOut(document)
            }
        }
        if theme.wordRules, pageSetup != nil, !_mirrorPassing {
            _mirrorPassing = true
            defer { _mirrorPassing = false }
            for _ in 0 ..< 4 {
                var flips: [RichChange] = []
                for (k, para) in document.paragraphs.enumerated() where para.style.eastAsian["w:mirrorIndents"] == "1" && para.cell == nil {
                    guard k < _pieceStart.count, _pieceStart[k] < _allPieces.count else { continue }
                    let mirrors = (_allPieces[_pieceStart[k]].page / _columns) % 2 == (document.flipsMirrorIndents ? 0 : 1)
                    if mirrors != _mirrored.contains(k) {
                        if mirrors { _mirrored.insert(k) } else { _mirrored.remove(k) }
                        flips.append(.changed(k))
                    }
                }
                if flips.isEmpty { break }
                apply(flips, paragraphCount: document.paragraphs.count)
                ensureLaidOut(document)
            }
        }
    }

    /// Where a table's first column starts: the text column's left edge,
    /// or further in for a table narrower than the column that the document
    /// centres or right-aligns (Word's table alignment).
    /// A table's cell insets (px): its own margins where it has them, the
    /// layout's padding where not.
    /// One side of a cell's own borders as the file wrote them
    /// (`CellRef.bordersXML`): its line style and width in points, nil
    /// where the cell names no such side or says none.
    static func _cellSide(_ xml: String?, _ side: String) -> (style: String, width: Double)? {
        // (`firstRange(of:)`, the standard library's: `range(of:)` is the
        // legacy Foundation layer, which the web build does not link.)
        guard let xml, let a = xml.firstRange(of: "<w:\(side) "), let b = xml[a.upperBound...].firstRange(of: ">") else { return nil }
        let element = xml[a.upperBound ..< b.lowerBound]
        func value(_ name: String) -> Substring? {
            guard let s = element.firstRange(of: name + "=\""), let e = element[s.upperBound...].firstRange(of: "\"") else { return nil }
            return element[s.upperBound ..< e.lowerBound]
        }
        guard let style = value("w:val"), style != "nil", style != "none" else { return nil }
        return (String(style), max(0.25, (value("w:sz").flatMap { Double($0) } ?? 4) / 8))
    }

    /// The colour a side's `w:color` says (auto, or none said: nil).
    static func _cellSideColor(_ xml: String?, _ side: String) -> Color? {
        guard let xml, let a = xml.firstRange(of: "<w:\(side) "), let b = xml[a.upperBound...].firstRange(of: ">") else { return nil }
        let element = xml[a.upperBound ..< b.lowerBound]
        guard let s = element.firstRange(of: "w:color=\""), let e = element[s.upperBound...].firstRange(of: "\"") else { return nil }
        let hex = String(element[s.upperBound ..< e.lowerBound])
        guard hex.count == 6, let v = Int(hex, radix: 16) else { return nil }
        return Color(argb: 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
    }

    func _cellInsets(_ table: String, _ document: RichDocument) -> (top: Double, left: Double, bottom: Double, right: Double) {
        let s = document.tableStyles[table]
        // A table that states no cell margins — one made in the editor —
        // has Word's where Word's rules are followed: none above or
        // below, 5.4pt at the sides. That is what its file will mean
        // when it is saved saying nothing, to Word and to this app on
        // reopening: with the editor's own padding its rows came back a
        // fifth shorter (seen on screen 2026-10-13).
        let side = theme.wordRules ? _px(5.4) : cellPadding, end = theme.wordRules ? 0 : cellPadding
        return (s?.cellMarginTop.map(_px) ?? end, s?.cellMarginLeft.map(_px) ?? side,
                s?.cellMarginBottom.map(_px) ?? end, s?.cellMarginRight.map(_px) ?? side)
    }
    func _acrossColumns(_ table: String, _ document: RichDocument) -> Bool {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, _columns > 1, let style = document.tableStyles[table],
              style.floatsOverText, style.floatX == nil, style.floatXAnchor == "margin",
              style.alignment == .right || style.alignment == .center,
              let first = _tableFirstParagraph[table] else { return false }
        return _perSection ? _columnsOf(paragraph: first) > 1 : true
    }

    func _tableLeft(_ table: String, _ document: RichDocument) -> Double {
        let sum = (_columnWidths[table] ?? []).reduce(0, +)
        // (A table aligned in the MARGINS of a section of columns is set across all
        // of them, not in the column it hangs from: lo-20f5d558's, right-aligned,
        // stands at the margin's right in Word's print. Painted from the first
        // column's edge: see `_acrossColumns`.)
        let width = _acrossColumns(table, document) ? _px(_setup(ofParagraph: _tableFirstParagraph[table] ?? 0).contentWidth) : (_tableFlowWidth[table] ?? self.width)
        // Set out by its cell margin, as Word sets it before its 2013
        // layout: a left-aligned table's edge stands its left cell margin
        // left of its indent, so that the first column's text lines up
        // with the paragraphs'; a right-aligned one its right margin past
        // the right margin; a centred one is centred as it is. From
        // compatibility mode 15 on the indent is the edge's place and
        // nothing is set out (labs `tc` and `tc15`, 2026-10-14: zh-4c3793e8's
        // centred table had been 5.4pt left of Word's).
        let old = theme.wordRules && (document.compatibilityMode ?? 0) < 15 && !(RichTextTheme.wordWindowsPages && _nestedBlock)
        let style = document.tableStyles[table]
        // (One of cell spacing by its first cell's whole text inset —
        // its own margin, the spacing twice and half its line — the
        // indent being where that text starts: zh-9c5d0c3f's road signs,
        // a table at -685 twips of 15-twip spacing over cells of 60-twip
        // margins, stand 4.5pt left of ours in Word's print, set out by
        // the table's margin alone; bug57031's SAS tables put their text
        // at the margin.)
        // (Lab tbl14, Word for Windows, mode 14: a table of no cell margin stands half its left
        // line out as well, and its text starts where the page's margin is, at the line's middle
        // plus the larger of the margin and half the line.)
        var ruleHalf = 0.0
        if old, RichTextTheme.wordWindowsPages, document.compatibilityMode == 14, _tableSpacedOutdent[table] == nil, let ts = style, ts.cellSpacing == nil, ts.floatX == nil,
           ts.edges?.left ?? (ts.borders && !ts.bordersFromCells) {
            ruleHalf = (ts.edgeWidths["left"] ?? ts.borderWidth ?? 0.5) / 2
        }
        let left = old ? _px(max(_tableSpacedOutdent[table] ?? style?.textOutdent ?? 5.4, ruleHalf)) : 0
        let right = old ? _px(style?.textOutdentRight ?? 5.4) : 0
        // A floating table placed across (`w:tblpX`): from the page's edge,
        // the margin or the column, set out by its cell margin before 2013's
        // layout as an indent is. zh-92373179's 507pt roster, tblpX 1129
        // twips from the page, has its left rule at 50.6 in Word's print,
        // where ours stood at the column's, 71.2, its right side 20pt
        // further over the margin.
        if theme.wordRules, let x = style?.floatX {
            let first = _tableFirstParagraph[table] ?? 0
            let setup = _setup(ofParagraph: first)
            let from: Double
            switch style?.floatXAnchor {
            // (A header's or footer's own layout knows no section: the page's margin
            // is what `frameMargins` carries. lo-198cd200's header table, tblpX 500
            // against the page, stands at 25pt in Word's print, not 47 left of the
            // margin of 25 as the default setup's 72 put it.)
            case "page": from = floatsFrames ? x - frameMargins.left : x - setup.marginLeft - setup.gutter
            case "margin": from = floatsFrames ? x : x - setup.gutter
            default: from = x
            }
            // (A table that is also centred (`w:jc`) against the page is centred on it, its
            // tblpX not read: zh-f43c9edf's tblpX 1690 jc center 8815-twip table stands at
            // 77.3, the page's middle, in Word's print, where ours stood 84.5.)
            if style?.alignment == .center, style?.floatXAnchor == "page", !floatsFrames {
                return (_px(setup.width) - sum) / 2 - _px(setup.marginLeft + setup.gutter) - left
            }
            return _px(from) - left
        }
        switch style?.alignment ?? .left {
        case .center: return theme.wordRules ? (width - sum) / 2 : max(0, ((width - sum) / 2).rounded(.down))
        case .right: return theme.wordRules ? width - sum + right : max(0, (width - sum).rounded(.down))
        default: return theme.wordRules ? _px(style?.indent ?? 0) - left + _edgeShift(table, document) + (_besideWideFloatShift(table, document) ?? 0) : _px(style?.indent ?? 0).rounded()
        }
    }

    /// How far a table's columns stand right of its indent: from Word
    /// 2013's layout on, half its left edge line. The line
    /// lies inside the table there, its outer edge at the indent, and the
    /// columns are measured from its middle. Lab ci (zh-8628cfbe's table:
    /// tblW 5000 pct, tblInd -114, fixed, 28-twip margins, a 1.5pt rim
    /// and 0.5pt inside lines) prints the left line's middle 0.72 right of
    /// the indent, 0.24 for a 0.5pt rim, with no indent too and with dxa
    /// widths; ours stood the line's middle on the indent.
    func _edgeShift(_ table: String, _ document: RichDocument) -> Double {
        guard theme.wordRules, (document.compatibilityMode ?? 12) >= 15,
              let ts = document.tableStyles[table], ts.cellSpacing == nil, ts.floatX == nil else { return 0 }
        let ruled = ts.edges?.left ?? (ts.borders && !ts.bordersFromCells)
        // (A first column whose cells state a wider line of their own
        // stands by that: zh-e329b438's "Table Grid" (0.5pt) with 1.5pt
        // left lines on its cells puts the line's middle 0.75 in, and lab ci's
        // cells of 3pt lines 1.5.)
        let width = ts.edgeWidths["left"] ?? ts.borderWidth ?? 0.5
        let room = ruled ? Self._ruleRoom(ts.edgeStyles["left"] ?? ts.borderStyle, width) : 0
        let own = _tableOwnLeft[table].map { Self._ruleRoom($0.style, $0.width) } ?? 0
        return _px(max(room, own)) / 2
    }

    /// Column widths per table (px); a table whose widths changed has every
    /// cell re-laid out.
    func _updateTables(_ document: RichDocument) {
        var columns: [String: Int] = [:]
        _tableRows = [:]
        _tableMerged = [:]
        _tableFirstParagraph = [:]
        _tableOwnLeft = [:]
        _tableOwnRight = [:]
        var rightSides: [String: [(end: Int, side: (style: String, width: Double))]] = [:]
        for (k, p) in document.paragraphs.enumerated() {
            if let c = p.cell {
                if let own = Self._cellSide(c.bordersXML, "right") ?? Self._cellSide(c.rowBordersXML, "right") {
                    rightSides[c.table, default: []].append((c.column + c.span, own))
                }
                if _tableFirstParagraph[c.table] == nil { _tableFirstParagraph[c.table] = k }
                if c.column == 0, let own = Self._cellSide(c.bordersXML, "left") ?? Self._cellSide(c.rowBordersXML, "left"),
                   own.width > _tableOwnLeft[c.table]?.width ?? 0 { _tableOwnLeft[c.table] = own }
                columns[c.table] = max(columns[c.table] ?? 1, c.column + c.span)
                _tableRows[c.table] = max(_tableRows[c.table] ?? 0, c.row + c.rowSpan - 1)
                if c.rowSpan > 1 { _tableMerged[c.table, default: []].append(k) }
            }
        }
        for (table, sides) in rightSides {
            for r in sides where r.end >= columns[table] ?? 1 && r.side.width > _tableOwnRight[table]?.width ?? 0 { _tableOwnRight[table] = r.side }
        }
        var widths: [String: [Double]] = [:]
        _tableFlowWidth = [:]
        _tableSpacedOutdent = [:]
        for (i, p) in document.paragraphs.enumerated() {
            guard let c = p.cell, widths[c.table] == nil else { continue }
            let cols = columns[c.table] ?? 1
            // (The table's section's column.)
            let width = _flowWidth(i)
            _tableFlowWidth[c.table] = width
            if let ts = document.tableStyles[c.table], let sp = ts.cellSpacing, sp > 0, !(RichTextTheme.wordWindowsPages && ts.inWrapperCell) {
                _tableSpacedOutdent[c.table] = (c.padding?.left ?? ts.cellMarginLeft ?? ts.textOutdent ?? 5.4) + 2 * sp
                    + (ts.borders ? (ts.borderWidth ?? 0.5) / 2 : 0)
            }
            if let pts = _columnPreview[c.table] ?? document.tableColumns[c.table], pts.count == cols {
                // Wider than the column: scaled to fit, as Word autofits a
                // table whose grid outgrows the page; a preferred width
                // (a share of the column, or points) scales the grid to it.
                let sum = pts.reduce(0, +)
                var scale = sum > 0 && _px(sum) > width ? width / _px(sum) : 1
                if sum > 0, _columnPreview[c.table] == nil, let ts = document.tableStyles[c.table] {
                    // (A width the table states is its width, past the
                    // margin too where Word's rules are followed: a form
                    // 482pt wide in a 439pt column, set out to the left by
                    // its indent, keeps its columns.)
                    if let pct = ts.widthPercent {
                        // (Its outer rules inside the share there too, half each side's width in: zh-81aa310b's
                        // table, 101.52% of a 487.3pt column with half-point rules, has its grid 1807 + 8077
                        // twips — the share less 10 — and its second column's 81.72% is the 8077, where Word's
                        // lines wrap; ours, 0.4pt wider, took a "及" there that Word leaves.)
                        // (The edge cells' own wider lines count, as at the left edge: zh-147bdae0's 100% tables,
                        // 0.5pt rules with 1.5pt ones on the last column's cells' right, have the grid
                        // 13938 of a 13958-twip share — 20 in, half of 0.5 + 1.5 — ruled so in Word's print,
                        // where ours, 0.3pt wider, left "應" and "月" lines a quarter-point short.)
                        let outerInset: Double = {
                            guard theme.wordRules, ts.borders else { return 0 }
                            let side: Double = ts.borderWidth ?? 0.5
                            let left: Double = max(ts.edgeWidths["left"] ?? side, _tableOwnLeft[c.table]?.width ?? 0)
                            let right: Double = max(ts.edgeWidths["right"] ?? side, _tableOwnRight[c.table]?.width ?? 0)
                            return _px((left + right) / 2)
                        }()
                        scale = (theme.wordRules ? width * pct / 100 - outerInset : min(width, width * pct / 100)) / _px(sum)
                        // (A table whose grid — Word's own last fit of it —
                        // is wider than its share keeps the grid: zh-06c46ba9's
                        // table 4 says 100% of 415.6pt and Word sets its
                        // 426.4pt grid, columns where the grid has them. A
                        // fixed one too: zh-540dc149's form says 98% of
                        // 640.6pt and Word rules its 638.6pt grid, where ours,
                        // 627.7 wide, wrapped its cells a word early.)
                        // (Not a fixed one under Word 2013's layout (mode 15)
                        // whose grid is wider than the column: Word sets it to
                        // its share. zh-8628cfbe's fixed tables, 100% to 102.5%
                        // of a 453.5pt column over grids 2.8pt wider still,
                        // have their rules where the shares put them in Word's
                        // print — ours 1.6pt right at the third column, whose
                        // lines took a character Word's wrap; with tblW at 100%
                        // the columns scale by 5000/5126 exactly, and neither
                        // the cells' widths nor their margins move them (lab
                        // `pt`, Word for Mac). Before mode 15 the grid stands:
                        // zh-fec5fa30, zh-77bd4900, zh-937b8442, zh-ec8f908f and
                        // zh-c25d08c5 (modes 12 and 14) are drawn at their grids.)
                        // (Its outer rules inside the share, half each side's
                        // width in from its edges: the table's 1.5pt sides make
                        // it 452.1 of a 453.5pt share in Word's print, its
                        // 2.25pt ones 462.7 of 464.95.)
                        let sharesShare = theme.wordRules && ts.fixedLayout && (document.compatibilityMode ?? 12) >= 15 && _px(sum) > width + _px(0.5)
                        if sharesShare {
                            let side: Double = ts.borderWidth ?? 0.5
                            let left: Double = ts.edgeWidths["left"] ?? side
                            let right: Double = ts.edgeWidths["right"] ?? side
                            let inset: Double = ts.borders ? _px((left + right) / 2) : 0
                            let share: Double = width * pct / 100
                            scale = max(0.01, share - inset) / _px(sum)
                        }
                        if theme.wordRules, !_nestedInFixedTable, !_nestedNarrowed, scale < 1, !sharesShare { scale = 1 }
                        // (Before mode 15, Word for Windows sets a fixed table of 100% whose grid is its
                        // share, to the share and the left cell margin more — lab b60 (lo-b60b7299): a
                        // 225pt share and 5.4 margin, the grid's 224.95, ruled 230.5 wide; the second
                        // column's "paragraph" then fits one line, as it does in Word's print.)
                        if theme.wordRules, RichTextTheme.wordWindowsPages, ts.fixedLayout, (document.compatibilityMode ?? 12) < 15,
                           !_nestedBlock, pct == 100, _px(sum) <= width, width - _px(sum) <= _px(1) {
                            RuleTrace.hit("word-fixed-100-percent-table-is-the-share-and-a-cell-margin")
                            // (… and half the last column's right rule more: 3, 6 and 12pt rules put the
                            // table's right edge 1.5, 3 and 6pt out, the columns in share.)
                            var rule = 0.0
                            for q in document.paragraphs {
                                guard let qc = q.cell, qc.table == c.table, qc.column + qc.span >= cols,
                                      let side = Self._cellSide(qc.bordersXML, "right") ?? Self._cellSide(qc.rowBordersXML, "right") else { continue }
                                rule = max(rule, side.width)
                            }
                            scale = (width + _px((ts.cellMarginLeft ?? 5.4) + rule / 2)) / _px(sum)
                        }
                    }
                    else if let w = ts.width {
                        scale = (theme.wordRules ? _px(w) : min(width, _px(w))) / _px(sum)
                        // (So too one that states points: bug59058's
                        // centred article table says 552.75pt over a grid
                        // of 553.5, and Word centres the grid — ours stood
                        // 0.4pt right, and "logistic" no longer fitted.)
                        if theme.wordRules, !ts.fixedLayout, scale < 1 { scale = 1 }
                    }
                    // (A fixed layout keeps its grid, past the margin too:
                    // zh-454e2e29's 482pt in a column of 468, whose second
                    // column then holds "個案事實" on one line, as Word's
                    // print has it.)
                    // (Not a nested one, in a cell that is not fixed itself, whose grid outgrows the cell: Word sets it to
                    // the room it has — lo-660753a9's inner table, a 117.6pt grid in a 76.5pt cell, wraps "inner table
                    // row 1" in two lines.)
                    else if theme.wordRules, ts.fixedLayout, !(RichTextTheme.wordWindowsPages && _nestedBlock && !_nestedInFixedTable) { scale = 1 }
                    // (So does an autofit one of no stated width whose grid
                    // is wider by no more than its cells' side margins —
                    // Word's own fit of a table filling the column, set out
                    // by a margin on each side: zh-69bbcc3c's plan tables
                    // are 708.7pt in a column of 697.9 in Word's print, and
                    // ours, scaled to the column, wrapped "序号" at 15pt in
                    // a cell of 29.4.)
                    // (… and by what it is set out into the left margin as
                    // well: zh-9ba2ead7's 446.6pt score tables, set out
                    // 20.7pt in a column of 415, stand at their grids in
                    // Word for Windows' print — from the margin less the
                    // outdent and a cell margin to the margin and the
                    // other — where ours, scaled to the column, wrapped
                    // "物业服务企业".)
                    else if theme.wordRules,
                            _px(sum) <= width + _px((ts.cellMarginLeft ?? 5.4) + (ts.cellMarginRight ?? 5.4) + max(0, -ts.indent)) + 1 { scale = 1 }
                }
                // (Whole pixels, down — from a hair over: 63.5pt is 1270px
                // at the print's scale, which the scale's 4/3 times 15
                // makes 1269.9999…, and bug57031's autofit column, exactly
                // as wide as "Transform", lost a pixel and wrapped it.)
                widths[c.table] = pts.map { (_px($0) * scale + 0.001).rounded(.down) }
                // (An autofit table of no stated width whose grid outgrows the room is
                // shrunk by each column's share of what it has over its narrowest —
                // its text's longest unbreakable piece and its margins — not by one
                // factor. Lab ovfit, Word for Windows: grids of 60/180/300pt and
                // 30/300/300 over 468 lose 5.9/23.9/42.2 and 2.5/79.6/79.9pt, the
                // shares of (width - narrowest) at 20.8pt apiece to 0.1pt; equal
                // columns still scale evenly. lo fdo63164-1's 2nd column is 3pt
                // wider so.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, scale < 1, !_nestedInFixedTable, _columnPreview[c.table] == nil,
                   let ts = document.tableStyles[c.table], !ts.fixedLayout, ts.widthPercent == nil, ts.width == nil, (ts.cellSpacing ?? 0) == 0,
                   // (An outdent keeps the old way, untested.)
                   ts.indent > -0.5 {
                    let ins = _cellInsets(c.table, document)
                    var need = Array(repeating: 0.0, count: pts.count)
                    for (k, q) in document.paragraphs.enumerated() {
                        guard let cc = q.cell, cc.table == c.table, cc.span == 1, cc.column < pts.count else { continue }
                        let sides = cc.padding.map { _px($0.left) + _px($0.right) } ?? ins.left + ins.right
                        need[cc.column] = max(need[cc.column], sides + _minContent(k, q, document))
                    }
                    let grid = pts.map { _px($0) }
                    // (Room: the column, less the table's indent; before 2013's layout the
                    // table also reaches a cell margin past each side of the column — lab
                    // cbcol, Word for Windows, no compat setting: its right edge stands at
                    // the margin + 5.4 whatever the indent, the indent moving the left edge
                    // alone, so the room is the column + 10.8 - indent. Lab ovfit's A3 (2013's
                    // layout) lost the indent from a room of the column's width.)
                    let reach = (document.compatibilityMode ?? 12) >= 15 ? 0 : _px((ts.cellMarginLeft ?? 5.4) + (ts.cellMarginRight ?? 5.4))
                    let room = width + reach - _px(max(0, ts.indent))
                    let over = grid.reduce(0, +) - room
                    let spare = zip(grid, need).map { max(0, $0 - $1) }
                    let spareSum = spare.reduce(0, +)
                    if over > 0.5, spareSum > over {
                        RuleTrace.hit("autofit-shrink-follows-width-over-narrowest")
                        widths[c.table] = zip(grid, spare).map { ($0 - over * $1 / spareSum + 0.001).rounded(.down) }
                    }
                }
                if theme.wordRules, !_nestedInFixedTable, _columnPreview[c.table] == nil, let ts = document.tableStyles[c.table],
                   !ts.fixedLayout, (ts.cellSpacing ?? 0) == 0, let base = widths[c.table] {
                    widths[c.table] = _autofit(c.table, base, document)
                    // (A table of a stated share whose cells state a share of
                    // it in every column, and not the grid's: the columns are
                    // those shares of its width — LibreOffice's
                    // floattable-nested-rowspan, a 4997-pct form on a grid of
                    // 1444 + 5159 twips whose cells say 727 and 4273 of 5000:
                    // its first column is 48.0pt in Word's print, not 72.2.)
                    if theme.wordRules, RichTextTheme.wordWindowsPages, _nestedBlock, ts.widthPercent != nil, ts.columnPercents.count == base.count, base.count > 1 {
                        widths[c.table] = _pctColumns(c.table, widths[c.table] ?? base, ts, document)
                    }
                } else if theme.wordRules, _columnPreview[c.table] == nil, let ts = document.tableStyles[c.table],
                          !ts.fixedLayout, (ts.cellSpacing ?? 0) > 0, !ts.columnPercents.isEmpty, let base = widths[c.table] {
                    widths[c.table] = _pctColumns(c.table, base, ts, document)
                }
            } else {
                // (A table with no grid and cells of no width, a share of the column wide, is that share,
                // not the whole column: LibreOffice's sdt-around-float-table, 40% and aligned right,
                // stands at the right margin's share in Word's print and ran the column's width.)
                var room = width
                if theme.wordRules, let pct = document.tableStyles[c.table]?.widthPercent, pct > 0, pct < 100 { room = width * pct / 100 }
                widths[c.table] = Array(repeating: (room / Double(cols)).rounded(.down), count: cols)
            }
        }
        for (table, w) in widths where _columnWidths[table] != w {
            for i in document.paragraphs.indices where document.paragraphs[i].cell?.table == table {
                _painters[i]?.dispose()
                _painters[i] = nil
                _firstDirty = min(_firstDirty ?? i, i)
                _lastDirty = max(_lastDirty, i)
            }
        }
        _columnWidths = widths
    }

    /// Word's vertical writing: a line of the cell's text, laid out
    /// across and turned a quarter by the caller, drawn a character at a
    /// time, each ideograph turned back upright in the box it has on the
    /// line — so they stack down the cell a character's advance apart,
    /// as Word's print has zh-2b955411's "评估目的". Only a paragraph of
    /// East Asian characters (and spaces) is drawn so; false leaves any
    /// other to be painted turned, as its Latin letters are in Word.
    /// Set `distribute` (`w:jc` distribute), the first character starts
    /// the line and the last ends it, the rest evenly between: Word's
    /// "经济行为类型" down a 77.3pt cell, 13.64pt apart at 9pt.
    /// The marks Word sets in their vertical forms down a vertical line
    /// (Unicode's CJK compatibility forms, U+FE10 to U+FE44). Word's
    /// prints of tbRlV cells hold "︑", "︐", "︵" and "︶" where the files
    /// have "、", "，", "（" and "）" (zh-b0401810's "职业资格证书︑职业技能…",
    /// zh-cec9d337, zh-e49d7943, zh-65e6c317, zh-74b34f3b); the rest
    /// follow the same table.
    static let _verticalForms: [Unicode.Scalar: Unicode.Scalar] = [
        "，": "\u{FE10}", "、": "\u{FE11}", "。": "\u{FE12}", "：": "\u{FE13}", "；": "\u{FE14}",
        "！": "\u{FE15}", "？": "\u{FE16}", "〖": "\u{FE17}", "〗": "\u{FE18}", "…": "\u{FE19}",
        "‥": "\u{FE30}", "—": "\u{FE31}", "–": "\u{FE32}", "＿": "\u{FE33}",
        "（": "\u{FE35}", "）": "\u{FE36}", "｛": "\u{FE37}", "｝": "\u{FE38}", "〔": "\u{FE39}", "〕": "\u{FE3A}",
        "【": "\u{FE3B}", "】": "\u{FE3C}", "《": "\u{FE3D}", "》": "\u{FE3E}", "〈": "\u{FE3F}", "〉": "\u{FE40}",
        "「": "\u{FE41}", "」": "\u{FE42}", "『": "\u{FE43}", "』": "\u{FE44}",
    ]

    /// How far down its box Word sets a mark's vertical form, in ems: its
    /// ink, which the form keeps to one side of its square, comes out
    /// about the middle of the character's place. Word's prints in
    /// Microsoft YaHei: "︑" 5.9pt under its place at 10.56pt
    /// (zh-b0401810), "︐" 6.2 under and "︵" / "︶" 2.3 over and under
    /// at 12 (zh-cec9d337, zh-e49d7943). Ours stood in the square, and
    /// "︑" and "︐" missed their lines. Other forms are not measured.
    static let _verticalFormDrop: [Unicode.Scalar: Double] = [
        "\u{FE10}": 0.52, "\u{FE11}": 0.56, "\u{FE35}": -0.19, "\u{FE36}": 0.19,
    ]

    /// (`mixed`: what is not an ideograph is drawn too, turned with the
    /// line as Word's `eaVert` sets Latin text — zh-6d402586's "(" and its
    /// spaces lie on their sides between upright ideographs in Word's
    /// print. A vertical cell's too: zh-74b34f3b's tbRlV "東引鄉活動中心
    /// 2樓" keeps its ideographs upright and lays the "2" on its side,
    /// where its "2" had turned ours whole.)
    func _paintUpright(_ painter: TextPainter, at origin: Offset, _ canvas: Canvas, distribute: Bool = false, justify: Bool = false, mixed: Bool = false, centred: Bool = false) -> Bool {
        guard let root = painter.text else { return false }
        let text = Array(root.toPlainText(includeSemanticsLabels: false, includePlaceholders: true).utf16)
        // (※ ☆ ★ stand upright in a Japanese face's column — dx2 934bd3e5's Meiryo — and lie on their side in
        // a Chinese one: zh-6e7ff836's 新細明體 "※".)
        var japaneseMarks = false
        func wide(_ u: UInt16) -> Bool { (u >= 0x2E80 && !(u >= 0xD800 && u <= 0xDFFF) && u != 0xFFFC) || japaneseMarks && (u == 0x203B || u == 0x2605 || u == 0x2606) }
        func blank(_ u: UInt16) -> Bool { u == 0x20 || u == 0x200B || u == 0x2060 || u == 0xFEFF || u == 0x3000 }
        guard text.contains(where: wide), mixed || text.allSatisfy({ wide($0) || blank($0) }) else { return false }
        // The style each offset is set in, the spans' own over those
        // they are in.
        var styles: [TextStyle?] = []
        func walk(_ span: InlineSpan, _ inherited: TextStyle?) {
            guard let t = span as? TextSpan else {
                styles.append(inherited)
                return
            }
            let own = inherited.map { $0.merge(t.style) } ?? t.style
            if let s = t.text { styles.append(contentsOf: repeatElement(own, count: s.utf16.count)) }
            for child in t.children ?? [] { walk(child, own) }
        }
        walk(root, nil)
        guard styles.count == text.count else { return false }
        japaneseMarks = styles.contains { s in
            let f = (s?.debugLabel ?? s?.fontFamily ?? "").lowercased()
            return ["meiryo", "メイリオ", "ms mincho", "ms gothic", "ＭＳ", "yu mincho", "yu gothic", "游"].contains { f.containsSubstring($0) }
        }
        let shown = text.indices.filter { wide(text[$0]) }
        if mixed {
            // The rest on its side, where the line set it, on its baseline.
            let lines = painter.computeLineMetrics()
            for k in text.indices where !wide(text[k]) && !blank(text[k]) && !(text[k] >= 0xD800 && text[k] <= 0xDBFF && k + 1 < text.count && wide(text[k + 1])) {
                guard let box = painter.getBoxesForSelection(TextSelection(baseOffset: k, extentOffset: k + 1)).first else { continue }
                let unit = text[k]
                let end = (unit >= 0xD800 && unit <= 0xDBFF && k + 1 < text.count) ? k + 2 : k + 1
                let piece = String(decoding: text[k ..< end], as: UTF16.self)
                let glyph = TextPainter(text: TextSpan(text: piece, style: styles.indices.contains(k) ? styles[k]?.copyWith(letterSpacing: 0) : nil), textDirection: .ltr)
                glyph.layout()
                let mid = (box.top + box.bottom) / 2
                let baseline = lines.first(where: { mid >= $0.baseline - $0.ascent - 0.5 && mid <= $0.baseline + $0.descent + 0.5 })?.baseline ?? box.bottom
                glyph.paint(canvas, Offset(origin.dx + box.left, origin.dy + baseline - glyph.computeDistanceToActualBaseline(.alphabetic)))
                glyph.dispose()
            }
        }
        // (Each ideograph centred across the line on the tallest one
        // beside it, not on its own run's box: zh-74b34f3b's tbRlV
        // "東引鄉活動中心2樓", 16pt with a 20pt "樓", is one column down
        // the middle in Word's print, every character 79.4pt across;
        // ours set the 16pt ones 1.6pt to the side of the "樓".)
        let ownBoxes = shown.map { painter.getBoxesForSelection(TextSelection(baseOffset: $0, extentOffset: $0 + 1)).first }
        func across(_ box: TextBox) -> Double {
            var tallest = box
            // (Overlapping by more than half, and taller by more than
            // rounding: exact-height lines overlap their neighbours by a
            // sliver, and equal boxes differing in the last bit made
            // every character take the next column's place — zh-264d7516.)
            let half = (box.bottom - box.top) / 2
            for case let other? in ownBoxes where min(other.bottom, box.bottom) - max(other.top, box.top) > half
                && other.bottom - other.top > tallest.bottom - tallest.top + 0.01 { tallest = other }
            return (tallest.top + tallest.bottom) / 2
        }
        // (Each column on by half its first character's letter spacing, as
        // the engine set lines until skia-no-line-spacing-shift took that
        // out — what the places below were measured against: zh-b0401810's
        // spaced "职业资格证书…", and zh-f2835e26's "综 合 实 力" (36 and 33
        // twips), which stood 2pt high in Word's print without it.)
        // (Not where the engine set the line centred or to the right with
        // room to spare: there its alignment replaced that shift — Skia's
        // TextLine::format assigns it — and zh-b0401810's centred
        // "职业资格证书…" (51 twips) never had it.)
        let lineMetrics = painter.computeLineMetrics()
        func lead(_ k: Int) -> Double {
            let start = painter.getLineBoundary(TextPosition(offset: k)).start
            if painter.textAlign == .center || painter.textAlign == .right || painter.textAlign == .end,
               let line = lineMetrics.first(where: { m in
                   let b = painter.getLineBoundary(TextPosition(offset: k))
                   return painter.getLineBoundary(painter.getPositionForOffset(Offset(m.left + 0.01, m.baseline))).start == b.start
               }), line.width < painter.width - 0.01 { return 0 }
            return (styles.indices.contains(start) ? styles[start]?.letterSpacing ?? 0 : 0) / 2
        }
        for (n, k) in shown.enumerated() {
            guard var box = ownBoxes[n],
                  let ch = Unicode.Scalar(text[k]) else { continue }
            if distribute, shown.count > 1 {
                let advance = box.right - box.left
                let left = Double(n) * (painter.width - advance) / Double(shown.count - 1)
                box = TextBox(fromLTRBD: left, box.top, left + advance, box.bottom, box.direction)
            }
            // (A justified paragraph's full columns spread over the
            // width, the last one not: zh-264d7516's tbRlV "被征地农户人员信息"
            // in a 33pt cell, two to a column 16.2pt apart in Word's print.)
            if justify, !distribute {
                let first = painter.getLineBoundary(TextPosition(offset: k)).start
                let mates = shown.filter { painter.getLineBoundary(TextPosition(offset: $0)).start == first }
                if mates.count > 1, let at = mates.firstIndex(of: k), shown.last.map({ painter.getLineBoundary(TextPosition(offset: $0)).start != first }) ?? false {
                    let head = ownBoxes[shown.firstIndex(of: mates[0]) ?? n]
                    let advance = head.map { $0.right - $0.left } ?? box.right - box.left
                    let left = Double(at) * (painter.width - advance) / Double(mates.count - 1)
                    box = TextBox(fromLTRBD: left, box.top, left + advance, box.bottom, box.direction)
                }
            }
            // (DFKai-SB has no vertical forms: Word's prints of its tbRlV
            // columns hold the plain "、" at the plain step, none of
            // U+FE10 to FE19 — zh-74b34f3b's "會議、研習、喜宴", where the
            // drop below stood ours 9pt low.)
            let family = styles[k]?.debugLabel ?? styles[k]?.fontFamily ?? ""
            let plain = family.containsSubstring("楷") || family.lowercased().containsSubstring("dfkai") || family.lowercased().containsSubstring("kaiti")
            let form = plain ? ch : (Self._verticalForms[ch] ?? ch)
            // (Its own advance, without the run's letter spacing: that
            // follows it — below.)
            let glyph = TextPainter(text: TextSpan(text: String(Character(form)), style: styles[k]?.copyWith(letterSpacing: 0)), textDirection: .ltr)
            glyph.layout()
            // (Its em square centred in its box — the square stands 0.88
            // em over the baseline and 0.12 under it — not its line, which
            // an exact line height makes far taller than the character,
            // with the character low in it: zh-2b955411's 28pt lines set
            // "评估目的" 5pt below Word's.)
            let em = styles[k]?.fontSize ?? 14
            // (A 標楷體 column stands 0.085 em further toward the line's
            // start than the square centred in its box: lab vlab1, a 12 pt
            // column 1.0 to 1.1 pt left of ours at every exact, auto and
            // aligned line, 10 to 20 pt scaling with the size; zh-20c1d74a's
            // 0.95 pt.)
            let middle = glyph.computeDistanceToActualBaseline(.alphabetic) - 0.38 * em
            canvas.save()
            // (A mark's vertical form further down its box or up it, as
            // Word sets it: `_verticalFormDrop`.)
            // (At the start of its place, the letter spacing after it, as
            // Word sets a spaced run: zh-b0401810's "职业资格证书…" (51
            // twips, 15.6pt apart) stands 2.55pt higher in Word's print —
            // half its spacing — than ours, centred in each place, did.)
            // (A centred DFKai-SB column — the 1.3 line the face is set in — stands 0.11 em higher in Word's
            // print than the places it is set in, zh-74b34f3b's 16pt
            // "東引鄉活動中心2樓" 1.8pt: windows' measurement.)
            let higher = centred && abs((styles[k]?.height ?? 0) - 1.3) < 0.001 ? 0.11 * em : 0
            let along = box.left + min(box.right - box.left, glyph.width) / 2 + lead(k) - higher
            // (Meiryo and the other Japanese faces carry their own vertical marks in place: Word's print of
            // dx2 934bd3e5 sets "、" right after its character, where the YaHei drop stood it 5.7pt low.)
            let japanese = ["meiryo", "メイリオ", "ms mincho", "ms gothic", "ＭＳ", "yu mincho", "yu gothic", "游"].contains { family.lowercased().containsSubstring($0) }
            canvas.translate(origin.dx + along + (japanese ? 0 : (Self._verticalFormDrop[form] ?? 0)) * em, origin.dy + across(box) + (plain ? 0.085 * em : 0))
            canvas.rotate(-Double.pi / 2)
            glyph.paint(canvas, Offset(-glyph.width / 2, -middle))
            canvas.restore()
            glyph.dispose()
        }
        return true
    }

    /// A cell's paragraph stacked (PowerPoint's `wordArtVert`): every character upright, one to a square place
    /// 1.414 em on a side, down the cell and then on to the next column to its right when the cell's height
    /// is spent. PowerPoint's print of lo-tcPr-vert-roundtrip: 18pt "Stacked text" in a 173pt row is six
    /// to a column, 25.45pt apart both ways, each letter centred in its place and a space holding one.
    func _paintStacked(_ i: Int, _ painter: TextPainter, _ c: _CellGeo, _ document: RichDocument, _ canvas: Canvas) -> Bool {
        guard let root = painter.text else { return false }
        let text = Array(root.toPlainText(includeSemanticsLabels: false, includePlaceholders: true).utf16)
        var styles: [TextStyle?] = []
        func walk(_ span: InlineSpan, _ inherited: TextStyle?) {
            guard let t = span as? TextSpan else { styles.append(inherited); return }
            let own = inherited.map { $0.merge(t.style) } ?? t.style
            if let s = t.text { styles.append(contentsOf: repeatElement(own, count: s.utf16.count)) }
            for child in t.children ?? [] { walk(child, own) }
        }
        walk(root, nil)
        guard styles.count == text.count, !text.isEmpty else { return false }
        let height = c.rowSpan > 1 ? c.turnedPart ?? c.rowHeight : c.ownRowHeight
        func rows(_ size: Double) -> Int { max(1, Int((height - c.pad.top - c.pad.bottom) / (1.414 * size) + 1e-6)) }
        // (The columns the cell's earlier paragraphs took: the next one starts beyond them.)
        var taken = 0
        for j in 0 ..< i {
            guard let o = _cells[j], o.table == c.table, o.row == c.row, o.column == c.column,
                  document.paragraphs[j].cell?.stackedUpright == true else { continue }
            let n = document.paragraphs[j].text.utf16.count
            let size = max(1, document.paragraphs[j].runs.first?.style.fontSize ?? 18)
            taken += max(1, (n + rows(size) - 1) / rows(size))
        }
        let firstSize = styles.first??.fontSize ?? 18
        var row = 0, column = taken
        var k = 0
        while k < text.count {
            let size = styles[k]?.fontSize ?? firstSize
            let pitch = 1.414 * size
            let perColumn = rows(size)
            if row >= perColumn { row = 0; column += 1 }
            let unit = text[k]
            let end = (unit >= 0xD800 && unit <= 0xDBFF && k + 1 < text.count) ? k + 2 : k + 1
            if unit != 0x20 && unit != 0x00A0 {
                let glyph = TextPainter(text: TextSpan(text: String(decoding: text[k ..< end], as: UTF16.self),
                                                       style: styles[k]?.copyWith(letterSpacing: 0)), textDirection: .ltr)
                glyph.layout()
                let left = c.colLeft + c.pad.left + Double(column) * pitch + pitch / 2 - glyph.width / 2
                let baseline = c.rowTop + c.pad.top + Double(row) * pitch + pitch / 2 + 0.54 * size
                glyph.paint(canvas, Offset(left, baseline - glyph.computeDistanceToActualBaseline(.alphabetic)))
                glyph.dispose()
            }
            row += 1
            k = end
        }
        return true
    }

    /// Word's re-fit of an autofit table (`w:tblLayout` autofit, the
    /// default), as office.md's "Autofit tables" has it (labs `at1`–`at5`,
    /// `sp1`, `sp2`, `cap*`): the saved grid is kept, as a fixed table's
    /// is, until a cell's narrowest setting — its longest piece that
    /// cannot part, with its margins and side indents — is wider than
    /// the columns it covers. Then that cell is exactly that wide, the
    /// other columns give way toward their own narrowest, and the table
    /// keeps its width while that suffices and grows past it when the
    /// narrowest need it (a span of 62 Courier "W"s: 479.5pt, its other
    /// column at one character and its margins). zh-0aac9d1a's first
    /// form: 34.6/187.6/110.5/156.4pt in Word's print, from a grid of
    /// 67.5/151.1/76.3/134.0, for its stamp line's 444pt piece.
    /// A spaced table of a stated share whose cells state shares of it
    /// (`TableStyle.columnPercents`): each such column its share of the
    /// table — the grid as scaled to the table's share — or what its
    /// cells' text needs, whole where they do not wrap; the rest of the
    /// width to the other columns, as the grid shares it among them.
    /// (Lab nt, Word for Mac — zh-045c5a75's article table, 85% with
    /// cells of 12% noWrap, 2% and auto, over a grid of 1375/146/7571
    /// that puts its first column at 15%: column 1 stands 54pt wide, 12%
    /// of its 450pt, in a one-row copy, and the text of column 3 from
    /// 127.2 where the grid's put it at 135.7; in the document, whose
    /// first column holds "第 9-1 條" unbroken, from 138.24.)
    func _pctColumns(_ table: String, _ base: [Double], _ style: TableStyle, _ document: RichDocument) -> [Double] {
        let total = base.reduce(0, +)
        guard total > 0, style.columnPercents.keys.allSatisfy({ $0 < base.count }) else { return base }
        let ins = _cellInsets(table, document)
        var need = Array(repeating: 0.0, count: base.count)
        for (i, p) in document.paragraphs.enumerated() {
            guard let c = p.cell, c.table == table, c.span == 1, c.column < base.count, style.columnPercents[c.column] != nil else { continue }
            // (Its text, its margins, and the cell spacing it gives up.)
            let sides = (c.padding.map { _px($0.left) + _px($0.right) } ?? ins.left + ins.right) + _px(style.cellSpacing ?? 0)
            let w = sides + (style.noWrapColumns.contains(c.column) ? _maxContent(i, p, document) : _minContent(i, p, document))
            need[c.column] = max(need[c.column], w)
        }
        var out = base
        var taken = 0.0
        for (k, share) in style.columnPercents {
            out[k] = (max(total * share / 100, need[k]) + 0.001).rounded(.up)
            taken += out[k]
        }
        let rest = (0 ..< base.count).filter { style.columnPercents[$0] == nil }
        let restBase = rest.reduce(0) { $0 + base[$1] }
        if rest.isEmpty, (style.cellSpacing ?? 0) == 0 { return out }
        guard !rest.isEmpty, restBase > 0, total - taken > 0 else { return base }
        for k in rest { out[k] = ((total - taken) * base[k] / restBase + 0.001).rounded(.down) }
        if Self.debugAutofit {
            let pt = theme.pixelsPerPoint * scale
            FileHandle.standardError.write(Data("pct columns \(table): \(base.map { ($0 / pt * 10).rounded() / 10 }) -> \(out.map { ($0 / pt * 10).rounded() / 10 })\n".utf8))
        }
        return out
    }

    /// Word for Windows (compat 15): each side of a column's least width is the larger of the cell
    /// margin and half the rule on that side (lab tfit: 0.5/1/2 pt rules and no margin grow the
    /// column 0.5/1/2 pt; with 5.4 pt margins nothing is added).
    @inline(never)
    func _autofitRuleRoom(_ table: String, _ document: RichDocument, _ padL: Double, _ padR: Double) -> Double {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, (document.compatibilityMode ?? 0) >= 15,
              let ts = document.tableStyles[table], ts.cellSpacing == nil, ts.contentFit != true, ts.widthPercent == nil,
              ts.edges?.left ?? (ts.borders && !ts.bordersFromCells) else { return 0 }
        let l = ts.edgeWidths["left"] ?? ts.borderWidth ?? 0.5
        let r = ts.edgeWidths["right"] ?? ts.borderWidth ?? 0.5
        return max(0, _px(l / 2) - padL) + max(0, _px(r / 2) - padR)
    }

    /// The room a content-fitted table shares out (lab atcol1, Word for Windows): a share of the
    /// column is that share of the column plus both cell margins (50% of a 468pt column: 239.4 for
    /// 25%); a width in twips is that width; otherwise the column plus margins.
    @inline(never)
    func _contentFitRoom(_ table: String, _ base: [Double], _ document: RichDocument, _ margins: Double) -> Double {
        // (Compat 15 lines the cell TEXT up with the margin, so a share is of the column alone: atcol3c15 100% is 468.1, not 478.9.)
        let flow = (_tableFlowWidth[table] ?? width) + ((document.compatibilityMode ?? 0) >= 15 && RichTextTheme.wordWindowsPages ? 0 : margins)
        guard let ts = document.tableStyles[table] else { return flow }
        // No compat mode (lab atcol4): a percentage share is of the column plus margins too (478.9 for 100% of 468), as at compat 14.
        if theme.wordRules, RichTextTheme.wordWindowsPages {
            if let pct = ts.widthPercent, pct > 0 { return flow * pct / 100 }
            if document.compatibilityMode != nil, let w = ts.width, w > 0 { return _px(w) }
        }
        return ts.widthPercent != nil ? base.reduce(0, +) : flow
    }

    static func _autofitDictionaryScript(_ u: UInt16) -> Bool {
        (u >= 0x0E00 && u <= 0x0EFF) || (u >= 0x1780 && u <= 0x17FF) || (u >= 0x1000 && u <= 0x109F)
    }

    func _autofit(_ table: String, _ base: [Double], _ document: RichDocument) -> [Double] {
        struct Cell { var column: Int; var span: Int; var min: Double; var whole: Double; var max: Double; var picture: Bool }
        var cells: [Cell] = []
        var at: [Int: Int] = [:]   // (row, column) → its cell in `cells`
        var wholeNeed: [Int: Double] = [:]   // a noWrap column's whole text (Mac Word): see below
        // (In a table a share of its room wide: zh-8415d258's and zh-d0a207ac's,
        // of no width or a width in twips, fell 60 and 20 points with it.)
        let pctTable = document.tableStyles[table]?.widthPercent != nil
        let ins = _cellInsets(table, document)
        for (i, p) in document.paragraphs.enumerated() {
            guard let c = p.cell, c.table == table else { continue }
            guard c.column + c.span <= base.count else { return base }
            // (Turned text runs along the row, not across the column.)
            guard c.textDirection == .horizontal else { continue }
            let padL = c.padding.map { _px($0.left) } ?? ins.left, padR = c.padding.map { _px($0.right) } ?? ins.right
            let sides = padL + padR + _autofitRuleRoom(table, document, padL, padR)
            let w = sides + _minContent(i, p, document)
            var wWhole = document.compatibilityMode == nil ? sides + _minContent(i, p, document, contentFit: true) : w
            var widest = sides + _maxContent(i, p, document)
            // (PROVISIONAL, labs atcol5-8 t12-c1only, t29-c1only, t29-no3, t12-c12, t29-c12: an
            // empty cell paragraph in a no-compat percentage table adds a quarter pixel
            // to its whole and widest settings, not to its narrowest.)
            if document.compatibilityMode == nil, pctTable, RichTextTheme.wordWindowsPages, p.text.isEmpty, p.image == nil {
                wWhole += _px(0.25); widest += _px(0.25)
            }
            if theme.wordRules, !RichTextTheme.wordWindowsPages, c.span == 1, widest > w + 0.01, pctTable,
               let kept = c.keptPropertiesXML, kept.containsSubstring("<w:noWrap"),
               !kept.containsSubstring("<w:noWrap w:val=\"0\"") && !kept.containsSubstring("<w:noWrap w:val=\"false\"") {
                wholeNeed[c.column] = max(wholeNeed[c.column] ?? 0, widest)
            }
            let picture = theme.wordRules && p.text.isEmpty && p.image.map { $0.float == nil && !Self._isEquation($0) } == true
            let key = c.row * 4096 + c.column
            if let k = at[key] {
                if w > cells[k].min { cells[k].picture = picture }
                cells[k].min = max(cells[k].min, w)
                cells[k].whole = max(cells[k].whole, wWhole)
                cells[k].max = max(cells[k].max, widest)
            } else {
                at[key] = cells.count
                cells.append(Cell(column: c.column, span: c.span, min: w, whole: wWhole, max: widest, picture: picture))
            }
        }
        // A table that states no width, nor any of its cells, is fitted
        // to its content, its grid set aside (office.md's "All-auto
        // tables"; labs `aa`, `ab`, `ac` on Word for Windows). Each column
        // lies between its cells' narrowest and widest settings, a span's
        // over its columns' shared out as theirs are; the table is as
        // wide as the widest if they fit its room, and otherwise the room
        // wide, each column the same share of the way from its narrowest
        // to its widest. zh-e49d7943's calendar: 69.1/57.6/63.0/62.9/62.9/
        // 71.9pt inside in Word's print, over a grid of 67.55/60.25/
        // 63.55×3/70.0, and "星期二" parted. (A cell's widest is taken as
        // 1580pt at most, about the 22 inches Word allows a table — lab
        // `ae`: a cell of 1720, 1985 or 2975pt of words sets its table as
        // one of 1580 does; zh-12f87285's descriptions, 4400pt unparted,
        // leave its 194 rows at the grid WPS saved, Word's own fit.)
        if theme.wordRules, document.tableStyles[table]?.contentFit == true, (document.compatibilityMode != nil || document.tableStyles[table]?.width == nil), _nestedCap == nil, !cells.isEmpty {
            let cap = _px(1580)
            var low = Array(repeating: 0.0, count: base.count), high = low
            for c in cells where c.span == 1 {
                low[c.column] = max(low[c.column], c.whole)
                high[c.column] = max(high[c.column], min(c.max, cap))
            }
            for c in cells.filter({ $0.span > 1 }).sorted(by: { $0.span < $1.span }) {
                let cols = c.column ..< c.column + c.span
                func share(_ widths: inout [Double], _ need: Double) {
                    let has = cols.reduce(0) { $0 + widths[$1] }
                    guard need > has else { return }
                    for k in cols { widths[k] = has > 0 ? widths[k] * need / has : need / Double(c.span) }
                }
                share(&low, c.whole)
                share(&high, min(c.max, cap))
            }
            for (column, points) in document.tableStyles[table]?.contentFitFixed ?? [:] where column < low.count {
                low[column] = max(low[column], _px(points))
                high[column] = low[column]
            }
            // (Not where a column holds nothing measured: turned cells only.)
            if !low.contains(0) {
                high = zip(low, high).map { max($0, $1) }
                let room = _contentFitRoom(table, base, document, ins.left + ins.right)
                // (No compat mode, lab atcol4: an over-full table has no column minimum; each column is its margins plus a share of the
                // room in proportion to its widest content: 24.5 / 429.8 / 24.6 for 2 / 60 / 2 ideographs.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, document.compatibilityMode == nil, pctTable, high.reduce(0, +) > room {
                    let m = ins.left + ins.right
                    // (Shares follow the narrowest each column can be, its longest whole run: jpn-z21601833-acd729's table of 4 / 32
                    // ideographs and a Latin-and-ideograph column, Word 33.7 / 269.4 / 143.4 inside.)
                    if low.reduce(0, +) > room { high = low; low = high.map { min($0, m) } }
                }
                let narrowest = low.reduce(0, +), widest = high.reduce(0, +)
                let k = widest <= room ? 1 : narrowest >= room ? 0 : (room - narrowest) / (widest - narrowest)
                // (Whole pixels: up where each is its widest, so that it
                // still fits.)
                // (A table that states its width and whose content fits is stretched to it, each column in
                // proportion to its widest: lab atcol3 v5, three short cells, 159.6 each in every compat mode.)
                let stated = document.tableStyles[table]?.widthPercent != nil || document.tableStyles[table]?.width != nil
                // (No compat mode: a percentage-width table stretches too, to its room of 478.9: jpn-z21601833-acd729's 3-column 100% tables, Word 230.2 / 151.5 / 97.2.)
                let stretch = widest < room && widest > 0 && stated && RichTextTheme.wordWindowsPages && (document.compatibilityMode != nil || document.tableStyles[table]?.widthPercent != nil)
                let fitted = stretch ? high.map { ($0 * room / widest + 0.001).rounded(.down) }
                    : zip(low, high).map { k >= 1 || $0 == $1 ? ($1 - 0.001).rounded(.up) : ($0 + ($1 - $0) * k + 0.001).rounded(.down) }
                if Self.debugAutofit {
                    let pt = theme.pixelsPerPoint * scale
                    FileHandle.standardError.write(Data("autofit \(table): content fit \(fitted.map { ($0 / pt * 10).rounded() / 10 })\n".utf8))
                }
                // (A grid within a point of it in every column is the
                // saving program's own fit, and ours is Word's to within a
                // little, as below: zh-12f87285's comes out 0.3pt narrower
                // in its description column, which then parted lines Word
                // keeps whole.)
                if fitted.count == base.count, zip(fitted, base).allSatisfy({ abs($0 - $1) <= _px(1) }) { return base }
                return fitted
            }
        }
        func room(_ c: Cell) -> Double { base[c.column ..< c.column + c.span].reduce(0, +) }
        // (Over by a point at least: ours are Word's widths to within a
        // little, and the grid is down to whole pixels. bug57031's HTML
        // tables are saved at Word's own fit of their text, and ours
        // measure their widest words 0.6 to 0.75pt over it.)
        let tolerance = _px(0.05)
        let over = cells.filter { $0.min > room($0) + tolerance }
        if Self.debugAutofit {
            let pt = theme.pixelsPerPoint * scale
            FileHandle.standardError.write(Data("autofit \(table): grid \(base.map { ($0 / pt * 10).rounded() / 10 })\n".utf8))
            for c in over {
                FileHandle.standardError.write(Data("  over: column \(c.column) span \(c.span) needs \((c.min / pt * 10).rounded() / 10) of \((room(c) / pt * 10).rounded() / 10)\n".utf8))
            }
        }
        guard !over.isEmpty || wholeNeed.contains(where: { $0.key < base.count && $0.value > base[$0.key] + 0.01 }) else { return base }
        // Each column's own narrowest: its one-column cells'. (One with
        // none — every cell over it spans — is not known to give: it
        // keeps its width. drawing.docx's nested tables had a column
        // given away to nothing.)
        var floor = base
        var measured = Set<Int>()
        for c in cells where c.span == 1 {
            floor[c.column] = measured.contains(c.column) ? max(floor[c.column], c.min) : c.min
            measured.insert(c.column)
        }
        var widths = base
        var set = Set<Int>()
        // A cell of one column sets it; a span shares out what is left
        // over its columns' own narrowest as the grid shares its width.
        // (Word's sharing is not this: zh-0aac9d1a's span came out
        // 187.6/110.5/156.4 where this gives 182.3/109.3/162.9. One
        // print measured; the lab to find it is still to do.)
        for c in over.sorted(by: { $0.span < $1.span }) {
            if c.span == 1 {
                widths[c.column] = set.contains(c.column) ? max(widths[c.column], c.min) : c.min
                set.insert(c.column)
                continue
            }
            let cols = Array(c.column ..< c.column + c.span)
            let free = cols.filter { !set.contains($0) }
            let left = c.min - cols.filter { set.contains($0) }.reduce(0) { $0 + widths[$1] }
            guard !free.isEmpty, left > 0 else { continue }
            let floors = free.reduce(0) { $0 + floor[$1] }
            let weight = free.reduce(0) { $0 + base[$1] }
            for k in free {
                let share = weight > 0 ? base[k] / weight : 1 / Double(free.count)
                widths[k] = floor[k] + max(0, left - floors) * share
                set.insert(k)
            }
        }
        // The rest give way, as far as their own narrowest, to keep the
        // table its width.
        let others = base.indices.filter { !set.contains($0) }
        let excess = widths.reduce(0, +) - base.reduce(0, +)
        let slack = others.reduce(0) { $0 + max(0, base[$1] - floor[$1]) }
        if excess > 0, slack > 0 {
            for k in others {
                let give = max(0, base[k] - floor[k])
                widths[k] = base[k] - min(give, excess * give / slack)
            }
        }
        // (Then, in Mac Word, in a table a share of its room wide, a column
        // whose cells do not wrap (`w:noWrap`, on) and could part takes its text's whole width, every other column
        // giving it as it is wide — down past its own narrowest. Lab a6nw
        // (zh-6aa8bd7c's contact table, 100%, every cell a share): its
        // home-telephone column, "328004　" noWrap, stands 56.9 where its
        // share is 50.9, and the mobile column, fitted to "0932-838898"
        // at 78.4, gives 0.4 and wraps the last digit, the table a page
        // longer; without the noWrap, or the "　", or with the mobiles a
        // digit shorter, nothing wraps. The mobile column's own noWrap
        // claims nothing: its text cannot part anyway.)
        for (k, need) in wholeNeed.sorted(by: { $0.key < $1.key }) where k < widths.count && need > widths[k] + 0.01 {
            let rest = widths.indices.filter { $0 != k && wholeNeed[$0] == nil }
            let pool = rest.reduce(0) { $0 + widths[$1] }
            let d = need - widths[k]
            guard pool > d else { continue }
            for j in rest { widths[j] -= d * widths[j] / pool }
            widths[k] = need
            set.insert(k)
        }
        // (A picture, or a table nested in a cell, that would take the
        // table past its column and its side margins shares that room out
        // instead, each column as its narrowest is of all of theirs. Lab
        // dr2/k on Word for Windows: a 450pt picture beside "right cell"
        // in a 467.75pt column sets 445.4 / 22.9, the text parted "righ" /
        // "t" and the picture cut; drawing.docx's p9 logo, 306pt beside a
        // nested table of 177, keeps the 296.15 of its grid, where the
        // share gives 296.3. Text alone still takes a table past: the 62
        // "W"s above.) (Nor narrower than a grid already wider.)
        let room = max((_tableFlowWidth[table] ?? width) + ins.left + ins.right, base.reduce(0, +))
        let total = widths.reduce(0, +)
        if theme.wordRules, total > room + _px(1), over.contains(where: { $0.picture }) {
            widths = widths.map { $0 * room / total }
        }
        // (Not past the room an autofitting parent that spans its page
        // leaves it: `_nestedCap`.)
        if let cap = _nestedCap, widths.reduce(0, +) > cap + _px(1), base.reduce(0, +) <= cap + _px(1) { return base }
        // (Whole pixels: up for a column a cell's narrowest set, so that
        // its piece still fits it.)
        let fitted = widths.indices.map { set.contains($0) ? (widths[$0] - 0.001).rounded(.up) : (widths[$0] + 0.001).rounded(.down) }
        if Self.debugAutofit {
            let pt = theme.pixelsPerPoint * scale
            FileHandle.standardError.write(Data("  fitted \(fitted.map { ($0 / pt * 10).rounded() / 10 })\n".utf8))
        }
        return fitted
    }

    /// Whether an object is an Office Math equation (`m:oMath`,
    /// `m:oMathPara`), which the reader keeps as an attachment.
    static func _isEquation(_ image: ImageAttachment) -> Bool { image.name == "m:oMath" || image.name == "m:oMathPara" }

    /// The narrowest this document's tables can be set (px), the widest
    /// of them: each row its cells' narrowest settings side by side, with
    /// their margins, as `_autofit` measures them.
    func _narrowestTables(_ document: RichDocument) -> Double {
        var cells: [String: Double] = [:]   // "table|row|column" → narrowest
        var rows: [String: [String]] = [:]  // "table|row" → its cells
        for (i, p) in document.paragraphs.enumerated() {
            guard let c = p.cell, c.textDirection == .horizontal else { continue }
            let ins = _cellInsets(c.table, document)
            let sides = c.padding.map { _px($0.left) + _px($0.right) } ?? ins.left + ins.right
            let row = "\(c.table)|\(c.row)", key = "\(row)|\(c.column)"
            if cells[key] == nil { rows[row, default: []].append(key) }
            cells[key] = max(cells[key] ?? 0, sides + _minContent(i, p, document))
        }
        return rows.values.map { $0.reduce(0) { $0 + (cells[$1] ?? 0) } }.max() ?? 0
    }

    /// The narrowest a paragraph of a cell can be set (px): its longest
    /// piece that cannot part, and its side indents. The pieces are
    /// parted where the line fitting parts them (`_glued`, and the
    /// breaks `_span` puts in), after a run of spaces, and at a line
    /// break; each is as wide as the paragraph sets it. Word's autofit
    /// measure joins a run of ordinary spaces that follows a no-break
    /// space to what is on both sides of it (labs `sp2`, `caplong`:
    /// "nbsp×30 + 26 spaces + 年" is one piece 528pt wide), though its
    /// line breaking parts there as ever (lab `sp1`).
    /// (Not the engine's minimum intrinsic width: a paragraph of one
    /// run that fits its line is never parted for it, and a line of
    /// ideographs came out as wide as all of them.)
    static func _isIndicUnit(_ u: UInt16) -> Bool { (u >= 0x900 && u <= 0xDFF) || u == 0x200C || u == 0x200D }
    func _minContent(_ i: Int, _ p: RichParagraph, _ document: RichDocument, contentFit: Bool = false) -> Double {
        if !contentFit, let m = _cellMins[i] { return m.min }
        var m = 0.0, first = 0.0   // the pieces after the first; the first
        var widest = 0.0, opening = 0.0   // its lines unparted after the first; the first
        let units = Array(p.text.utf16)
        if !units.isEmpty {
            var gaps: [Int: Double] = [:]
            let (span, inline, inserts) = _span(for: p, at: i, document, textWidth: 100_000, autoSpaces: { gaps[$0] = $1 })
            let probe = TextPainter(text: span, textAlign: .left, textDirection: .ltr)
            if !inline.isEmpty { probe.setPlaceholderDimensions(inline.map { $0.dimensions }) }
            probe.layout(minWidth: 0, maxWidth: 100_000)
            let map = _OffsetMap(lead: 0, inserts: inserts)
            let percentStarts = _percentStarts(document)
            let pctWidthTable = p.cell.map { document.tableStyles[$0.table]?.widthPercent != nil } ?? false
            // (And where `w:wordWrap` off parts a Latin word: zh-f2441f00's
            // 42.2pt column holds "平台(iC" / "ulture)" in Word's print,
            // its grid kept; ours measured "(iCulture)" whole and widened
            // the column to 44.5, narrowing the table's others.)
            let breakBefore = Set(inserts.filter { o in
                guard o > 0, o < units.count, let a = Unicode.Scalar(units[o - 1]), let b = Unicode.Scalar(units[o]) else { return false }
                return Self._breaksBetween(Character(a), Character(b), percentStarts: percentStarts,
                                           timesEastAsian: !Self._eastAsianSigns.contains(units[o - 1]) || _setEastAsian(p, document, at: o - 1),
                                           shapesPart: (document.compatibilityMode ?? 12) >= 15 || RichTextTheme.wordWindowsPages,
                                           latinQuotes: theme.wordRules && !_setEastAsian(p, document, at: o - 1) && !_setEastAsian(p, document, at: o))
            }).union(_looseWordOffsets(p, document, textWidth: 100_000, named: _named(p, document),
                                       pitch: _offGrid(i, document) ? nil : _grid(i, document).pitch))
            func space(_ u: UInt16) -> Bool { u == 0x20 || u == 0x3000 || u == 0x09 }
            func piece(_ a: Int, _ b: Int) -> Double {
                var e = b
                while e > a, space(units[e - 1]) { e -= 1 }
                guard e > a else { return 0 }
                var w = 0.0
                for box in probe.getBoxesForSelection(TextSelection(baseOffset: map.painter(a), extentOffset: map.painter(e - 1) + 1)) {
                    w += box.right - box.left
                }
                // (Less the automatic space after it, which is no part of
                // it: zh-e329b438's label cells "接聽速度30分" (mode 15, 14pt)
                // set their column at 28.08 in Word's print, "30" bare —
                // 17.2 — between its margins, and the "3" and "0" a line
                // each; ours took "30" and the space after it, 20.8, and
                // widened the column to 31.6.)
                if theme.wordRules, let gap = gaps[e - 1] { w -= gap }
                return w
            }
            var start = 0, line = 0
            for k in 1 ..< units.count {
                let a = units[k - 1], b = units[k]
                if a == 0x0A || a == 0x0B || a == 0x2028 {
                    if line == 0 { opening = piece(line, k) } else { widest = max(widest, piece(line, k)) }
                    line = k
                }
                let parts: Bool
                if a == 0x0A || a == 0x0B || a == 0x2028 { parts = true }
                else if space(b) { parts = false }
                // (A no-break space holds both its neighbours, a space or an
                // ideograph too, though the line may part there:
                // zh-0aac9d1a's last form (Word for Windows) re-fits as its
                // first three do, its stamp line "年␣␣••␣月…（盖章）" one
                // piece; ours parted it at "␣|•" and kept its grid, page
                // 10's first column three characters too wide.)
                else if theme.wordRules, a == 0xA0 || b == 0xA0 { parts = false }
                else if space(a) {
                    var j = k - 1
                    while j >= 0, units[j] == 0x20 { j -= 1 }
                    parts = !(j >= 0 && j < k - 1 && units[j] == 0xA0)
                }
                // (No compat mode on Word for Windows, labs atcol5-8, docs/plans/word-table-autofit.md: a column's narrowest is its longest run between spaces; it parts only just after an em dash, at a hyphen or en dash (unmeasured, left to the chain below) and in Thai, Lao, Khmer and Myanmar text (dictionary breaks).)
                else if theme.wordRules, RichTextTheme.wordWindowsPages, document.compatibilityMode == nil, p.cell != nil, pctWidthTable, contentFit, a == 0x2014 { parts = true }
                else if theme.wordRules, RichTextTheme.wordWindowsPages, document.compatibilityMode == nil, p.cell != nil, pctWidthTable, contentFit,
                        !(a == 0x2D || a == 0x2010 || a == 0x2013), !Self._autofitDictionaryScript(a), !Self._autofitDictionaryScript(b) { parts = false }
                else if breakBefore.contains(k) { parts = true }
                // (After a hyphen before a digit in a time of day, where a
                // word wider than its cell must part: zh-b3e887f7's schedule keeps its
                // grid's 49.4pt time columns in Word's print, "9:00-" /
                // "9:10" in each, where ours took "9:00-9:10" for one piece
                // and widened them to 78.)
                // (… and any such, from 2013's layout or where nothing is
                // compressed, as the line breaking parts it there —
                // `_wideWordHyphens`: zh-e329b438's "29-30".)
                else if theme.wordRules, a == 0x2D, b >= 0x30, b <= 0x39, k > 1, Self._isLatinWordUnit(units[k - 2]),
                        units[k...].prefix(while: { !space($0) && $0 < 0x2E80 }).contains(0x3A) || units[..<k].reversed().prefix(while: { !space($0) && $0 < 0x2E80 }).contains(0x3A)
                        || document.usesEastAsianLayout && ((document.compatibilityMode ?? 12) >= 15 || !(document.characterSpacingControl?.hasPrefix("compressPunctuation") ?? false)) { parts = true }
                // (A full-width mark beside a Latin word is a piece of its
                // own to autofit, whatever the line breaking keeps together:
                // zh-82b166b4's "（WebHR）", 50pt glued, sits in its 51.1pt
                // column in Word's print — the grid kept, the word parted
                // "（W" / "ebHR）" — where ours widened the column to 61.)
                // (But not a closing one after it: lab `af` on Word for
                // Windows, zh-ae2dd08d p24's "【05-01】" under a 36pt hanging
                // indent widens its 70.9pt column to 73.7, "01】" one piece
                // at the indent; without the brackets, or the indent, the
                // grid stands.)
                else if theme.wordRules, (a >= 0x3000 && Self._isLatinWordUnit(b)) || (Self._isLatinWordUnit(a) && b >= 0x3000),
                        Self._openingUnits.contains(a) || Self._openingUnits.contains(b) || Self._closingUnits.contains(a) { parts = true }
                // (An Indic word is one piece to autofit, not a stretch per letter, in a table of a stated width in twips; a table a share of the
                // page wide is held at it and Word parts the word inside its cell — xd 6e011101's Tamil columns stay at the grid: bede0fbc's "নাম:" + 154 dots, 508.7pt in
                // Word's print, which widens its table to 519.6, ours measured "ম:" + the dots, 497.8, and parted the dots.)
                else if theme.wordRules, Self._isIndicUnit(a), Self._isIndicUnit(b), !pctWidthTable { parts = false }
                else { parts = !Self._glued(a, b, strict: Self._strictKinsoku(document)) }
                if parts {
                    if start == 0 { first = piece(start, k) } else { m = max(m, piece(start, k)) }
                    start = k
                }
            }
            if start == 0 { first = piece(start, units.count) } else { m = max(m, piece(start, units.count)) }
            if line == 0 { opening = piece(line, units.count) } else { widest = max(widest, piece(line, units.count)) }
            probe.dispose()
        }
        // (A picture that stands alone in its paragraph is one piece as
        // wide as it, its effect extent and border too, and a table
        // nested there is one as narrow as it can be set. Lab dr/clip1
        // on Word for Windows: a 303.75pt picture in an autofit cell of
        // 150pt widens the cell to 339.8 with its 18pt margins, where ours
        // kept the grid and cut the picture. Labs dr2/h: drawing.docx's
        // p9 logo widens its column too once the nested table beside it
        // has room, or gives way when it does not.)
        // (Not an equation: Word breaks a long one at its operators, and
        // ours, set on one line, asked its column for all of it —
        // zh-db07d44e's display formula on p22 widened its table's column
        // to ~400pt, and the document ran 78 pages to Word's 70.)
        else if theme.wordRules, let image = p.image, image.float == nil, !Self._isEquation(image) {
            if let box = image.textBox {
                if box.growsToFit, let inside = _textBox(image, document) { first = inside.layout._narrowestTables(inside.document) }
            } else {
                let room = _pictureRoom(image)
                first = _px(image.width) + room.left + room.right
            }
            opening = first
        }
        // (A form's check box is a drawn square, no glyph for the probe to
        // measure: it asks its width and the gap before it, 1.042 em. Lab
        // cbcol, Word for Windows: a box in an overfull table's first column
        // keeps it 30.1pt where an empty cell's goes to 29.2.)
        if theme.wordRules, p.runs.contains(where: { $0.style.formBox }), p.text.contains(where: { $0 == "\u{2610}" || $0 == "\u{2612}" }) {
            var at = 0, boxMin = 0.0
            for run in p.runs {
                let piece = p.text.utf16.index(p.text.utf16.startIndex, offsetBy: at) ..< p.text.utf16.index(p.text.utf16.startIndex, offsetBy: min(at + run.length, p.text.utf16.count))
                at += run.length
                if run.style.formBox, p.text[piece].contains(where: { $0 == "\u{2610}" || $0 == "\u{2612}" }) {
                    let size = run.style.fontSize ?? _named(p, document)?.char.fontSize ?? _normalChar(document)?.fontSize ?? theme.fontSize
                    boxMin = max(boxMin, size * 1.042)
                }
            }
            if boxMin > 0 {
                RuleTrace.hit("check-box-asks-its-width-of-a-cell")
                first = max(first, _px(boxMin)); m = max(m, _px(boxMin)); opening = max(opening, _px(boxMin))
            }
        }
        let sides = _sideIndents(p, document)
        // (Indents out into the cell's margins count against it:
        // bug65649's equipment table indents every paragraph -113 twips
        // a side, and its "№ п/п" column of 54pt holds "(согласно" in
        // Word's print, 49.3pt of text over the 43.2 between margins.)
        // (The first piece from where the first line starts: zh-fec5fa30's
        // calendar sets "14" under a hanging indent of 32pt, its line
        // at the cell's edge, and Word keeps the grid's 76pt column —
        // ours, counting the indent for it too, wanted 84.8 and gave
        // "18 連江縣" a column too narrow to hold it.)
        var unparted: Double
        // (An empty paragraph's one line starts where its first line
        // does, hanging indent and all, though `firstLineIndent` gives
        // such a paragraph none: zh-ae2dd08d's training-plan form has
        // empty cells indented 23.6pt hanging all of it in 22pt columns,
        // and Word keeps the grid, where ours asked 24.6 of each and
        // took the room from the next column's "訓練目標".)
        let lead = units.isEmpty && p.image == nil ? p.style.firstLineIndent : firstLineIndent(p, document)
        if theme.wordRules, _wordList(p, document) == nil {
            // (Before 2013's layout every piece is measured from where a
            // hanging line starts, and a first line set further in asks
            // nothing. Lab `af` on Word for Windows, mode 12 and 14: "表現"
            // under a 48pt indent hanging 24, "3樓/4樓" under 42.55
            // hanging all of it (zh-12c4f07a p19's floor column), and "表"
            // after a 75pt first line all keep a 51.1pt grid, where mode
            // 15 widens each, the later pieces set at the indent; a 100pt
            // indent, and a Latin word past the column from the hanging
            // start, widen it in both.)
            if (document.compatibilityMode ?? 12) < 15 {
                m = max(_px(sides.left + min(lead, 0)) + max(m, first), 0) + _px(sides.right)
            } else {
                m = max(m > 0 ? _px(sides.left) + m : 0, _px(sides.left + lead) + first, 0) + _px(sides.right)
            }
            unparted = max(widest > 0 ? _px(sides.left) + widest : 0, _px(sides.left + lead) + opening, 0) + _px(sides.right)
        } else {
            m = max(m, first) + (_wordList(p, document).map { _px($0.left) } ?? _px(sides.left)) + _px(sides.right)
            unparted = max(widest, opening) + (_wordList(p, document).map { _px($0.left) } ?? _px(sides.left)) + _px(sides.right)
        }
        if !contentFit { _cellMins[i] = (m, max(m, unparted)) }
        return m
    }

    /// The widest a paragraph of a cell is set (px): its longest line
    /// unparted, and its side indents, as `_minContent` measures them.
    func _maxContent(_ i: Int, _ p: RichParagraph, _ document: RichDocument) -> Double {
        _ = _minContent(i, p, document)
        return _cellMins[i]!.max
    }

    public func previewColumns(_ table: String, _ widths: [Double]?, _ document: RichDocument) {
        if widths == nil { _columnPreview[table] = nil } else { _columnPreview[table] = widths }
        _tablesDirty = true
        for i in document.paragraphs.indices where document.paragraphs[i].cell?.table == table {
            _painters[i]?.dispose()
            _painters[i] = nil
        }
        _topsValid = false
    }

    /// The column border under a document-space point, within `reach` px:
    /// the table and the index of the column whose right edge it is.
    public func columnBorder(at point: Offset, reach: Double = 4) -> (table: String, column: Int)? {
        guard !_rowTops.isEmpty else { return nil }
        let i = paragraphIndex(atY: point.dy)
        guard let c = _cells[i], point.dy >= c.rowTop, point.dy <= c.rowTop + c.rowHeight,
              let widths = _columnWidths[c.table] else { return nil }
        var x = c.colLeft - widths.prefix(c.column).reduce(0, +)
        for (k, w) in widths.enumerated() {
            x += w
            if abs(point.dx - x) <= reach { return (c.table, k) }
        }
        return nil
    }

    /// A table's column widths as laid out, in points.
    public func columnWidths(of table: String) -> [Double]? {
        _columnWidths[table].map { $0.map { $0 / (theme.pixelsPerPoint * scale) } }
    }

    /// Stack the blocks: ordinary paragraphs one under another, a table row's
    /// cells side by side with each column's paragraphs stacked inside it.
    func _placeBlocks(_ document: RichDocument, from start: Int = 0, settled: Int = Int.max) {
        let n = _heights.count
        var i = min(start, n)
        // Continue below the block before the restart, which is as it was;
        // the restart index's own top may belong to a paragraph that moved.
        var y = 0.0
        if i > 0 {
            if let c = _cells[i - 1] {
                y = c.rowTop + c.ownRowHeight
                // (A table floating over the text took none: the text
                // goes on from where the table began.)
                if _floatsOver(c.table, document) {
                    var k = i - 1
                    while k > 0, _cells[k - 1]?.table == c.table { k -= 1 }
                    y = _cells[k]!.rowTop - _px(document.tableStyles[c.table]?.floatOffsetY ?? 0)
                }
            } else { y = _tops[i - 1] + _heights[i - 1] }
        }
        while i < n {
            // Past the last change, a block whose top is unchanged means
            // every block below is too (heights above it are the same).
            guard let c = _cells[i] else {
                // The space before it lies over the space after the
                // paragraph above (`theme.collapsesParagraphSpacing`).
                // (Beside a float whose rows are measured by now: laid out again
                // with its lines held in — see `lineIndents`.)
                if _besidePending.contains(i) {
                    _besidePending.remove(i)
                    _layoutParagraph(i, document.paragraphs[i], document)
                }
                let top = y - _sharedSpace(i, document)
                if i > settled, _rowTops[i] == top { return }
                _tops[i] = top
                _rowTops[i] = top
                y = top + _heights[i]
                i += 1
                continue
            }
            if i > settled, _rowTops[i] == y { return }
            // The table: every row of it, placed in turn; a cell spanning
            // rows takes its height from the rows it covers, and stretches
            // the last of them when its own content is taller.
            let table = c.table
            let ins = _cellInsets(table, document)
            var rows: [(first: Int, end: Int, top: Double, height: Double)] = []
            // The room a rule takes (`theme.tableRulesTakeRoom`): the
            // first row's top one, and every row's bottom one.
            let ts = document.tableStyles[table]
            let floatsFrom = _floatsOver(table, document) ? y : nil
            // What of each cell paragraph's space before lies over the
            // space after the one above it in its cell (`_cellSharedSpace`).
            var sharedMemo: [Int: Double] = [:]
            func shared(_ k: Int) -> Double {
                if let v = sharedMemo[k] { return v }
                let v = _cellSharedSpace(k, document)
                sharedMemo[k] = v
                return v
            }
            if theme.wordRules, let down = ts?.floatOffsetY { y += _px(down) }
            // (A table floating over the text of a header or footer, raised by a negative
            // `w:tblpY`, stands that far above the line it hangs from — off the page's head
            // too: LibreOffice's tdf105688 header table, tblpY -1554 twips, has its
            // text 78pt higher in Word's print than the line set it in the flow.)
            else if theme.wordRules, floatsFrames, floatsFrom != nil, let up = ts?.floatRaiseY { y -= _px(up) }
            func rule(_ side: String, _ on: Bool?) -> Double {
                // (Under Word's rules each cell carries its own row's
                // rules in its margins — its own sides, the row above's,
                // a double line's three widths: `_layoutParagraph`.)
                guard theme.tableRulesTakeRoom, !theme.wordRules, on ?? ts?.borders ?? true else { return 0 }
                return _px(ts?.edgeWidths[side] ?? ts?.borderWidth ?? 0.5)
            }
            var rules: [(above: Double, below: Double)] = []
            var k0 = i
            while k0 < n, let d = _cells[k0], d.table == table {
                // A row with no paragraph of its own — every cell of it
                // merged down from above — is a row all the same: as
                // tall as the file says, and counted by the cells that
                // span it. (Left out, a cell merged over three rows was
                // measured against the row after them, never stretched
                // its own, and ran into the text below.)
                while rows.count < d.row {
                    let h = _px(document.tableStyles[table]?.rowHeights[rows.count] ?? 0)
                    rows.append((k0, k0, y, h))
                    rules.append((0, 0))
                    y += h
                }
                var j = k0
                while j < n, let d2 = _cells[j], d2.table == table, d2.row == d.row { j += 1 }
                // (A row the block's natural height puts in a band of a floating table of its cell steps
                // down to the band's foot, once for each: see `_avoidBands`.)
                if !_avoidBands.isEmpty || !_followBands.isEmpty, d.row > 0 {
                    var natural = 0.0
                    var column: [Int: Double] = [:]
                    for k in k0 ..< j { if let e = _cells[k], e.rowSpan == 1 { column[e.column, default: e.pad.top + e.pad.bottom] += _heights[k] } }
                    natural = column.values.max() ?? 0
                    for band in _avoidBands where band.top > 0.5 && y < band.bottom - 0.01 && y + natural > band.top + 0.01 { _avoidPush += band.bottom - y; y = band.bottom }
                    // (The floats anchored after the block stand from its natural foot, pushed by what it was not.)
                    if !(j < n && _cells[j]?.table == table) {
                        for follower in _followBands {
                            let top = y + natural - _avoidPush + follower.dy, bottom = top + follower.height
                            if y < bottom - 0.01 && y + natural > top + 0.01 { _avoidPush += bottom - y; y = bottom }
                        }
                    }
                }
                // (The empty paragraph that closes a merged cell of exact-height rows asks nothing of what
                // follows the table, though its number is still drawn: Word for Windows' lab amd5 b3,
                // lo-8ab44df5's empty "b)" — its spacing after 0, 6, 12 or 200 puts the next paragraph at the
                // same y, where in an unmerged cell it is a line like any other. Top-aligned cells only: a centred one
                // (zh-884c6e3e p2, zh-b0401810 p15) still holds the line, and the text above it stands as Word's.)
                if theme.wordRules, RichTextTheme.wordWindowsPages {
                    for k in k0 + 1 ..< j {
                        guard let cell = _cells[k], cell.rowSpan > 1, cell.verticalAlign == nil || cell.verticalAlign == "top", _cells[k - 1]!.column == cell.column,
                              k + 1 == j || _cells[k + 1]!.column != cell.column,
                              (cell.row ... min(rows.count + 1000, cell.row + cell.rowSpan - 1)).allSatisfy({ ts?.rowsExactHeight.contains($0) ?? false }) else { continue }
                        let q = document.paragraphs[k]
                        if q.text.isEmpty, q.image == nil, q.inlineImages.isEmpty { _heights[k] = 0.01 }
                    }
                }
                var stack: [Int: Double] = [:]
                var rowHeight = 0.0
                var ruled = 0.0
                var padded = 0.0
                var paddedBelow = 0.0
                var bareHeight = 0.0
                let ruleAbove = rows.isEmpty ? rule("top", ts?.edges?.top) : 0
                let lastRow = !(j < n && _cells[j]?.table == table)
                let ruleBelow = lastRow ? rule("bottom", ts?.edges?.bottom) : rule("insideH", ts?.edges?.insideH)
                for k in k0 ..< j {
                    let cell = _cells[k]!
                    if cell.rowSpan == 1 {
                        ruled = max(ruled, cell.rules); padded = max(padded, cell.pad.top + cell.pad.bottom)
                        // (The margin alone: `pad.bottom` holds the rule under it.)
                        paddedBelow = max(paddedBelow, cell.pad.bottom - cell.ruleBelow)
                    }
                    let offset = stack[cell.column].map { $0 - shared(k) } ?? 0
                    _tops[k] = y + ruleAbove + cell.pad.top + offset
                    if RichTextTheme.wordWindowsPages, let image = document.paragraphs[k].image, image.float == nil, image.textBox?.growsToFit == true {
                        _blockPush[k] = _textBox(image, document).map { $0.layout._avoidPush }.flatMap { $0 > 0.01 ? $0 : nil }
                    }
                    _rowTops[k] = y
                    stack[cell.column] = offset + _heights[k]
                    // A spanning cell's content counts against the rows it
                    // spans, below; a turned cell's against the placed height.
                    // (An empty cell whose end mark the file hides
                    // (`w:hideMark`) asks nothing of its row: Word sizes the
                    // row by its other cells and its stated height — lab
                    // `rm6`, zh-ae655121's floating signature table, 5pt
                    // shorter with the marks hidden than without.)
                    // (A picture is not nothing: LibreOffice's floattable-del-empty,
                    // a picture alone in a hideMark cell, stands 104pt tall in Word's
                    // print, where its row collapsed here and the picture was never drawn.)
                    let hidden = theme.wordRules && document.paragraphs[k].text.isEmpty
                        && document.paragraphs[k].image == nil && document.paragraphs[k].inlineImages.isEmpty
                        && (document.paragraphs[k].cell?.keptPropertiesXML?.containsSubstring("w:hideMark") ?? false)
                    if cell.rowSpan == 1, !cell.vertical, !hidden {
                        rowHeight = max(rowHeight, offset + _heights[k] + cell.pad.top + cell.pad.bottom)
                        bareHeight = max(bareHeight, offset + _heights[k] + cell.pad.top + cell.pad.bottom - cell.rules)
                        // (And as tall as a float its text wraps round reaches,
                        // where it stands in the cell (`_floatRect`, no higher
                        // than the row's top): zh-ab9cbe66's flow charts, 632pt
                        // groups held to their rows, have the text after their
                        // tables on the next page in Word's print, where ours
                        // set it over the chart.)
                        if theme.wordRules {
                            for image in document.paragraphs[k].inlineImages.inOrder + [document.paragraphs[k].image].compactMap({ $0 }) {
                                guard let f = image.float, f.wraps, f.verticalAlign == nil else { continue }
                                var h = _px(image.height + image.effectBottom + f.distanceBottom)
                                // (A table nested in the cell and floating is as tall as it
                                // lays out, not the 1pt its object says: LibreOffice's
                                // tdf170477, a 3547-twip row with a floating table down to
                                // 184.0pt, is 184.0 in Word's print and was 178.4 here.)
                                if image.textBox?.growsToFit == true, f.againstText || (RichTextTheme.wordWindowsPages && f.horizontalFrom == "cell"), k < _imageSize.count, let size = _imageSize[k] {
                                    h = size.height + _px(image.effectBottom + f.distanceBottom)
                                }
                                let top: Double
                                switch f.verticalFrom {
                                case "paragraph", "line":
                                    // (A float anchored after a block that stepped down keeps the place it had: `_avoidPush`.)
                                    var kept = 0.0
                                    if RichTextTheme.wordWindowsPages, !f.fromCellTop, f.againstText {
                                        var m = k - 1
                                        while m >= 0, let e = _cells[m], e.table == cell.table, e.row == cell.row, e.column == cell.column { kept += _blockPush[m] ?? 0; m -= 1 }
                                    }
                                    top = max(0, (f.fromCellTop && RichTextTheme.wordWindowsPages ? 0 : offset - kept) + cell.pad.top + _px(f.y))
                                // (From under the row's top line, as its text:
                                // Word's p17 row is the chart's 632.4pt and 0.7,
                                // 121.9 to 755.0 between its lines; from the
                                // row's very top ours was 632.3, and the next
                                // row parted where Word's goes over whole.)
                                // (And 0.72pt more, whatever its rules: lab
                                // `rb` (Mac, Word 16, zh-ab9cbe66's chart row
                                // alone, borders of ¼, ½, 1½pt and none) has
                                // the row's inside 633.12 every time, the
                                // 632.4pt extent and 0.72 — not the effect
                                // extent's 2.1.)
                                case "page", "margin": top = cell.pad.top + _px(0.72)
                                default: continue
                                }
                                rowHeight = max(rowHeight, top + h)
                                // (A table floating in the cell with no room beside it — wider than the cell's text
                                // from its offset — has the anchor's empty line set under it, and the row holds that
                                // line: lo-9fa3dedd's Table3 ends at 531 in a cell that ends at 545 in Word's print.)
                if RichTextTheme.wordWindowsPages, image.textBox?.growsToFit == true, f.horizontalFrom == "cell", f.fromCellText, !f.fromCellTop,
                                   f.horizontalAlign == nil, document.paragraphs[k].text.unicodeScalars.allSatisfy({ $0 == "\u{FFFC}" || $0 == "\n" }),
                                   _px(f.x) > 0, _px(f.x) + _px(image.width) > cell.colWidth + 0.01,
                                   rowHeight < top + h + max(_heights[k], _markLineHeight(k, document)) {
                                    RuleTrace.hit("word-cell-line-under-a-floating-table-with-no-room-beside-it")
                                    rowHeight = top + h + max(_heights[k], _markLineHeight(k, document))
                                }
                                if f.fromCellTop, RichTextTheme.wordWindowsPages, image.textBox?.growsToFit == true { _floatReach[k] = max(_floatReach[k], top + h - cell.pad.top) }
                            }
                        }
                    }
                }
                // (A cell merged down into this row rules it as its own
                // cells do, by the top line its continuation states, though
                // no line is drawn there: zh-ae655121's balance sheet heads
                // three cells merged over two rows, each continuation
                // stating a double line on top, and Word's second row is
                // 37.6pt "at least" and that line's 2.25 — ours took only
                // its own cells' half-point line, and every row after it
                // stood 1.75pt high.)
                if theme.wordRules, d.row > 0 {
                    var m = k0 - 1
                    while m >= 0, let e = _cells[m], e.table == table {
                        if let ref = document.paragraphs[m].cell, ref.row < d.row, ref.row + ref.rowSpan - 1 >= d.row {
                            let at = d.row - ref.row - 1
                            if at < ref.continuationBordersXML.count, let side = Self._cellSide(ref.continuationBordersXML[at], "top") {
                                ruled = max(ruled, _px(Self._ruleRoom(side.style, side.width)))
                            } else if !(at < ref.continuationBordersXML.count && (ref.continuationBordersXML[at]?.containsSubstring("<w:top ") ?? false)),
                                      ts?.edges?.insideH ?? ((ts?.borders ?? false) && !(ts?.bordersFromCells ?? false)) {
                                // (One that states no top at all takes the table's line
                                // between rows, as any cell's unstated top
                                // does: zh-db07d44e's indicator table, its
                                // first column merged down the rows and
                                // the others saying nil above and below,
                                // has rows of at least 22.7pt 23.2 apart
                                // in Word's print — the table's insideH
                                // half point — and ours 22.7, two rows a
                                // page more. Not one stating nil: its next
                                // table's continuations say nil above, and
                                // its rows stand 22.7 apart.)
                                ruled = max(ruled, _px(Self._ruleRoom(ts?.edgeStyles["insideH"] ?? ts?.borderStyle, ts?.edgeWidths["insideH"] ?? ts?.borderWidth ?? 0.5)))
                            }
                        }
                        m -= 1
                    }
                }
                // (A row stands as tall as its tallest cell's text and margins
                // and the line the row's other cells draw, even where the
                // tallest cell hides that line itself: zh-6e7ff836's p19 table,
                // insideH sz4, its text cells stating nil above and below while
                // the two cells beside them keep the line, has every such row
                // 48.48 in Word's print for three exact 16pt lines, ours 48.0 —
                // 4.6pt short by the page foot, a row's line left on the page.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, ruled > 0 {
                    RuleTrace.hit("word-row-takes-the-line-its-other-cells-draw")
                    rowHeight = max(rowHeight, bareHeight + ruled)
                }
                // (A row of spanning or turned cells alone is still its
                // margins tall.)
                // (The margins its own cells state, where they state them: lo-152d87fe's
                // footer table, a top margin of 32.4pt for its icon cells and 7.2 for its
                // text row's, set that row 32.4 tall by the table's, and its footer stood
                // 12.5pt too high under Word's print.)
                if theme.wordRules, RichTextTheme.wordWindowsPages, k0 < j {
                    let own = (k0 ..< j).map { _cells[$0]!.pad.top + _cells[$0]!.pad.bottom }.max() ?? 0
                    if abs(own - (ins.top + ins.bottom)) > 0.01 { RuleTrace.hit("word-row-is-its-cells-own-margins-tall") }
                    rowHeight = max(rowHeight, own)
                } else {
                    rowHeight = max(rowHeight, ins.top + ins.bottom)
                }
                // A row the file gave a height: at least that tall.
                // (And its rules: the height is the room between them.)
                // An exact one is that tall with its rules, whatever is in it.
                if let least = document.tableStyles[table]?.rowHeights[d.row] {
                    let exact = theme.wordRules && (document.tableStyles[table]?.rowsExactHeight.contains(d.row) ?? false)
                    // (An "at least" height is the room between the
                    // cells' margins, too, under Word's rules: labs `rm1`–
                    // `rm3`, Word 16 in modes 14 and 15, 2026-10-15 — rows
                    // that say at least 28.65pt are 29.15 with no margin,
                    // 29.9 with a cell's 0.75pt top margin, 34.15 with 5pt
                    // above, 39.15 with 5pt above and below, the table's
                    // margins as the cell's; an exact one stays 28.65.
                    // zh-a4b0f6ea's form of such rows ran 10pt short.)
                    let around = theme.wordRules ? max(ruled, padded) : ruled
                    // (The last row's own bottom line hangs under an exact
                    // height, not inside it: zh-ae655121's budget tables
                    // end on a 36.05pt row over a 0.75pt double line, and
                    // Word's print centres the row's text in all 36.05 and
                    // sets the text after the table the line's 2.2 lower.
                    // Ours had taken the line from the row's room, the text
                    // 1.1 high and the table that much short.)
                    // (A heavy line only: a single 0.5pt one stays inside, as
                    // the Mac's lab `rb` has it — an exact 567-twip last row
                    // ruled sz4 under is 28.32 between its rules' centres in
                    // Word's print, ours 28.84, and zh-5c6ff0d7's closing
                    // note lost its page by 3 twips.)
                    let below = (k0 ..< j).map { _cells[$0]!.ruleBelow }.max() ?? 0
                    // (In Word for Windows a single one the table draws hangs
                    // under it too: zh-884c6e3e's tables of exact rows, ruled
                    // sz4 by `w:tblBorders`, stand their rows' sum and the
                    // line apart in the word-win print, the text after each
                    // 0.47 lower than ours, and its p2 took a line Word's
                    // leaves for p3. Not one the cells state for themselves:
                    // zh-5c6ff0d7's, under no table line, stays inside as
                    // the Mac's does, and its note keeps its page.)
                    // (Word for Mac too: zh-884c6e3e's fresh Mac print sets the
                    // text after each such table about the line lower, and its
                    // p2 leaves "房交付之月…" for p3. The Mac's lab `rb`,
                    // which kept a single line inside, ruled its cells, not
                    // the table.)
                    // (Its cells stating the line as well change nothing
                    // where the table draws one: zh-78d8bd98's p7 table, sz4
                    // by `w:tblBorders` and by every cell's `w:tcBorders`,
                    // ends on an exact 25.3pt row whose text Word's print
                    // centres in all of it, the text after the table 0.5
                    // lower than ours, which had the row's text 0.25 high.)
                    let ownBottom = document.tableStyles[table].map { !$0.bordersFromCells && ($0.edges?.bottom ?? $0.borders) } ?? false
                    let tableLine = below > 0
                        && (ownBottom || !(k0 ..< j).contains { Self._cellSide(document.paragraphs[$0].cell?.bordersXML, "bottom") != nil })
                    let hung = exact && lastRow && (below > _px(1) || tableLine) ? below : 0
                    // (An exact one is that tall and its cells' bottom margin
                    // under it: the Mac's lab `rh` (zh-0243e7fc's package,
                    // modes 14 and 15) — its exact rows, the table's margins
                    // 0, 15 and 100 twips above and below, are 0.01, 0.76
                    // and 5.00pt over their height between rules on average
                    // over 18 rows; 100 above alone 0.01, 100 below alone
                    // 5.00. Its 15-twip margins had each row 0.75 short in
                    // ours, a line a page by page 9.)
                    let before = rowHeight
                    rowHeight = exact ? _px(least) + hung + (theme.wordRules ? paddedBelow : 0) : max(rowHeight, _px(least) + around)
                    // (A floating table's row that says it is taller than a page, with its
                    // content in less, is cut at the page in Word's print: lo-a48482e7's
                    // two 283pt rows are each one 166pt page, no second part follows.)
                    let pageRoom = _px(pageSetup(forPage: 0).height - pageSetup(forPage: 0).marginTop - pageSetup(forPage: 0).marginBottom)
                    if theme.wordRules, RichTextTheme.wordWindowsPages, !exact, document.tableStyles[table]?.keptPosition != nil,
                       rowHeight > pageRoom + 0.01, before <= pageRoom + 0.01 {
                        RuleTrace.hit("word-floating-row-taller-than-a-page-is-cut-at-the-page")
                        rowHeight = pageRoom - max(below, _px(0.5))
                    }
                }
                rowHeight += ruleAbove + ruleBelow
                rules.append((ruleAbove, ruleBelow))
                for k in k0 ..< j {
                    _cells[k]!.rowTop = y
                    _cells[k]!.rowHeight = rowHeight
                    _cells[k]!.ownRowHeight = rowHeight
                    _cells[k]!.firstInRow = k == k0
                }
                rows.append((k0, j, y, rowHeight))
                y += rowHeight
                k0 = j
            }
            // (… and so are such rows after the last that has one.)
            while theme.wordRules, !rows.isEmpty, rows.count <= _tableRows[table] ?? 0 {
                let h = _px(document.tableStyles[table]?.rowHeights[rows.count] ?? 0)
                rows.append((k0, k0, y, h))
                rules.append((0, 0))
                y += h
            }
            // A row in which no cell stands alone — each one merged on
            // into the row below, or down from the row above — Word
            // sizes by the cells themselves: one that starts there gives
            // its first line and the space after its first paragraph,
            // one that continues gives the (empty) paragraphs the file
            // wrote in it. Beside a cell of the row's own they give
            // nothing, and a merged cell's text counts where it ends.
            // (Measured off Word's rules, 2026-10-13: two rows merged
            // whole, a 14pt line with 8pt after in each cell, are 22 and
            // 22, not 22 over both; a thin cell beside them and they are
            // its height. A table of such rows ran a page short.)
            if theme.wordRules {
                var alone = rows.map { _ in false }
                var own = rows.map { _ in 0.0 }
                var measured: [RichParagraph: Double] = [:]
                // (Word for Windows lets a cell that starts in such a row
                // hold it up only where no row it reaches has a cell of its
                // own, which would take its text: zh-b8de3ae2's "比率(%)"
                // starts in an 11.3pt row and runs into the values' row, and
                // Word keeps the row at 11.3 (lab b8row9, Windows 01QbbApP),
                // where its first line made ours 13.55 and each year's rows
                // 1.9pt longer.)
                var standing = rows.map { _ in false }
                if RichTextTheme.wordWindowsPages {
                    for (r, row) in rows.enumerated() {
                        for k in row.first ..< row.end where _cells[k]!.rowSpan == 1 || _cells[k]!.vertical { standing[r] = true; break }
                    }
                }
                for (r, row) in rows.enumerated() {
                    var seen: Set<Int> = []
                    for k in row.first ..< row.end {
                        let cell = _cells[k]!
                        guard seen.insert(cell.column).inserted else { continue }
                        if cell.rowSpan == 1 || cell.vertical { alone[r] = true; continue }
                        let pads = cell.pad.top + cell.pad.bottom - cell.ruleBelow
                        let firstLine = _painters[k].flatMap { Self._lineBottoms($0).first }
                        let rests = (r + 1 ..< min(rows.count, r + cell.rowSpan)).contains { standing[$0] }
                        if !rests { own[r] = max(own[r], (firstLine.map { $0 + _spacing(k, document).after } ?? _heights[k]) + pads) }
                        let continued = document.paragraphs[k].cell?.continuationParagraphs ?? []
                        for offset in 1 ..< cell.rowSpan where r + offset < rows.count && offset - 1 < continued.count {
                            var h = 0.0
                            for p in continued[offset - 1] {
                                if measured[p] == nil { measured[p] = _detachedHeight(p, document, pair: cell.rowSpan == 2) }
                                h += measured[p]!
                            }
                            own[r + offset] = max(own[r + offset], h + pads + cell.ruleBelow)
                        }
                    }
                }
                var shift = 0.0
                for r in rows.indices {
                    rows[r].top += shift
                    guard !alone[r], !(ts?.rowsExactHeight.contains(r) ?? false) else { continue }
                    let want = (own[r] + rules[r].above + rules[r].below).rounded(.up)
                    if want > rows[r].height + 0.01 {
                        shift += want - rows[r].height
                        rows[r].height = want
                    }
                }
            }
            // Stretch for spanning cells, in the order of the rows they
            // end in; later rows shift. (By the rows they start in, a
            // cell over three rows was measured before the cell beside
            // it, over two, had stretched the second — and then stood
            // that much too tall.)
            var spanning: [(first: Int, last: Int, need: Double)] = []
            var stretched = rows.map { _ in 0.0 }
            for (r, row) in rows.enumerated() {
                var stackByColumn: [Int: Double] = [:]
                for k in row.first ..< row.end {
                    let cell = _cells[k]!
                    guard cell.rowSpan > 1, !cell.vertical else { continue }
                    stackByColumn[cell.column, default: 0] += _heights[k] - (stackByColumn[cell.column] == nil ? 0 : shared(k))
                    let need = stackByColumn[cell.column]! + cell.pad.top + cell.pad.bottom
                    spanning.append((r, min(rows.count - 1, r + cell.rowSpan - 1), need))
                }
            }
            for (_, cell) in spanning.enumerated().sorted(by: { ($0.element.last, $0.offset) < ($1.element.last, $1.offset) }) {
                let have = rows[cell.first ... cell.last].map(\.height).reduce(0, +)
                // (Not over rows of exact height alone, which Word does not
                // grow: zh-64044a1d's "離所方式", a 5.5pt line and a 12pt one
                // merged over two 18.5pt rows, is cut off in Word's print,
                // where ours stood the form's last rows 5pt low.)
                let exact = theme.wordRules && (cell.first ... cell.last).allSatisfy { ts?.rowsExactHeight.contains($0) ?? false }
                if cell.need > have + 0.01, !exact {
                    let extra = cell.need - have
                    rows[cell.last].height += extra
                    stretched[cell.last] += extra
                    for (rr, later) in rows.enumerated() where rr > cell.last { rows[rr].top = later.top + extra }
                }
            }
            // Turned cells: wrapped at the height the rows now have (as
            // PowerPoint wraps them), their lines stacking across the
            // column; a word longer than that height stretches the last
            // row the cell covers, as a spanning cell's content does.
            for (r, row) in rows.enumerated() {
                var k = row.first
                while k < row.end {
                    let cell = _cells[k]!
                    guard cell.vertical else { k += 1; continue }
                    var members = [k]
                    while members.last! + 1 < row.end, _cells[members.last! + 1]!.column == cell.column { members.append(members.last! + 1) }
                    k = members.last! + 1
                    let last = min(rows.count - 1, r + cell.rowSpan - 1)
                    let spanned = rows[r ... last].map(\.height).reduce(0, +)
                    var need = 0.0
                    for m in members {
                        let style = document.paragraphs[m].style
                        let inset = cell.pad.top + cell.pad.bottom + _px(style.indentLeft) + _px(style.indentRight)
                        guard let painter = _painters[m] else { continue }
                        var length = max(1, spanned - inset)
                        painter.layout(minWidth: length, maxWidth: length)
                        // No shorter than its longest word: the paragraph
                        // engine breaks the word instead, where PowerPoint
                        // makes the row taller. (The engine knows the word
                        // only once it has wrapped: after an unconstrained
                        // layout it reports nothing.)
                        let word = painter.minIntrinsicWidth.rounded(.up)
                        if word > length + 0.01 {
                            length = word
                            painter.layout(minWidth: length, maxWidth: length)
                        }
                        _textWidth[m] = length
                        _heights[m] = (_spaceBefore[m] + painter.height + _px(style.spaceAfter)).rounded(.up)
                        need = max(need, painter.longestLine + inset)
                    }
                    if need > spanned + 0.01 {
                        let extra = need - spanned
                        rows[last].height += extra
                        for (rr, later) in rows.enumerated() where rr > last { rows[rr].top = later.top + extra }
                    }
                }
            }
            // Second pass: final tops and heights, spanned heights for spanning cells.
            for (r, row) in rows.enumerated() {
                // Each cell's content height, for anchoring it in a taller
                // row (a turned cell's content width, across the column).
                var content: [Int: Double] = [:]
                for k in row.first ..< row.end {
                    let column = _cells[k]!.column
                    // (An empty last paragraph in a cell whose end mark is hidden
                    // (`w:hideMark`) is not part of what Word centres: zh-20c1d74a's
                    // "嘉義縣" over two rows, the empty line after it left out, stands
                    // 151.0, centred on its own; ours put it at the top, 142.0.)
                    var spare = 0.0
                    if theme.wordRules, RichTextTheme.wordWindowsPages, k > row.first, _cells[k - 1]!.column == column,
                       k + 1 == row.end || _cells[k + 1]!.column != column {
                        let q = document.paragraphs[k]
                        if q.text.isEmpty, q.image == nil, q.inlineImages.isEmpty,
                           q.cell?.keptPropertiesXML?.containsSubstring("w:hideMark") ?? false { spare = _heights[k] }
                    }
                    content[column] = (content[column].map { $0 - shared(k) } ?? 0) + _heights[k] - spare
                }
                // (… which reaches to the foot of a box floating over the
                // text from one of its paragraphs: Word centres
                // zh-454e2e29's two 18pt lines with the 37.75pt text box
                // anchored 4.35pt into the first — "娩假 42日" — as a
                // block 43.35pt tall, outline's effect extent and all;
                // centring the lines alone set them 3.5pt low.)
                if theme.wordRules {
                    var at: [Int: Double] = [:]
                    for k in row.first ..< row.end {
                        let column = _cells[k]!.column, top = at[column].map { $0 - shared(k) } ?? 0
                        let p = document.paragraphs[k]
                        // (Not in a cell merged down: lab `mc` on Word for Windows, zh-31d580df's
                        // "系統測試" in a centred two-row cell with a 68pt box anchored 38pt into
                        // it, stands at 264.17 on p27 whatever the box's size, height 5 to 68,
                        // top 0 or 38, text across or down: the box never counts there.)
                        // Only text boxes: zh-b24b396a's small line drawings in a
                        // centred two-row cell do count (Word agrees with the old rule).
                        let mergedDown = RichTextTheme.wordWindowsPages && _cells[k]!.rowSpan > 1
                        for image in p.inlineImages.inOrder + (p.image.map { [$0] } ?? []) {
                            guard let f = image.float, !f.takesRoom, !f.wraps, f.verticalFrom == "paragraph", f.verticalAlign == nil else { continue }
                            if mergedDown, image.textBox != nil { continue }
                            // (A float in a vertical cell is placed along the line, not across: its foot is no part of the width Word centres.)
                            if _cells[k]!.vertical { continue }
                            let foot = top + _spaceBefore[k] + _px(f.y + image.height + f.effectBottom)
                            content[column] = max(content[column] ?? 0, foot)
                        }
                        at[column] = top + _heights[k]
                    }
                }
                // The rows after it that hold no paragraph are drawn and
                // paged as part of this one: every cell of this row runs
                // on through them.
                var ghosts = 0.0, ghostCount = 0, given = stretched[r]
                var bounds: [Double] = []   // where each of those rows begins, under the row's top
                while r + ghostCount + 1 < rows.count, rows[r + ghostCount + 1].first == rows[r + ghostCount + 1].end {
                    bounds.append(row.height + ghosts)
                    ghostCount += 1
                    ghosts += rows[r + ghostCount].height
                    given += stretched[r + ghostCount]
                }
                // (And where they end at their own heights, where the text
                // merged down stretches the last: lab `gs` on Word for
                // Windows, zh-9ef811c8's "审批" row and its three (15.6,
                // 53.1, 48.95; 133.25 in all), its policy cell ten lines,
                // stands on page 6 at those heights, eight lines of it, the
                // two that stretch it going over — not parted at the last
                // row's top, as where the rows themselves do not fit.)
                if theme.wordRules, ghostCount > 0, given > 0.01 { bounds.append(row.height + ghosts - given) }
                var stack: [Int: Double] = [:]
                for k in row.first ..< row.end {
                    let cell = _cells[k]!
                    let offset = stack[cell.column].map { $0 - shared(k) } ?? 0
                    let last = min(rows.count - 1, r + cell.rowSpan - 1)
                    let spanned = cell.rowSpan > 1 ? rows[r ... last].map(\.height).reduce(0, +) : row.height
                    // (Text reading down runs from the cell's right margin to
                    // its very left edge, no margin there — lab `vs` on Word
                    // for Windows: set at the bottom, its ink stands 1.6pt
                    // off the left rule whatever the left margin (18pt) or
                    // the bottom (10); centred, half the right margin left
                    // of the middle — zh-b0401810's "职业资格证书…", which
                    // stood 3.3pt right of Word's.)
                    let endPad = theme.wordRules && cell.direction == .down ? 0 : cell.pad.left
                    let room = cell.vertical ? cell.colWidth - endPad - cell.pad.right
                        : spanned - cell.pad.top - cell.pad.bottom - rules[r].above - rules[last].below
                    // (The reach of a table floating in the cell is the whole cell's, not its own paragraph's:
                    // lo-158ec986's "outer B1" stands at the cell's top in Word, beside the 39.7pt table that
                    // is anchored to the paragraph above it in the same cell, where ours centred it.)
                    var reach = _floatReach[k]
                    if theme.wordRules, RichTextTheme.wordWindowsPages {
                        for m in row.first ..< row.end where _cells[m]!.column == cell.column { reach = max(reach, _floatReach[m]) }
                    }
                    let free = max(0, room - max(content[cell.column] ?? 0, reach))
                    let shift = cell.verticalAlign == "center" ? free / 2 : cell.verticalAlign == "bottom" ? free : 0
                    if cell.vertical {
                        _tops[k] = row.top
                        _cells[k]!.across = cell.acrossStart + offset + shift
                    } else {
                        _tops[k] = row.top + rules[r].above + cell.pad.top + offset + shift
                    }
                    _rowTops[k] = row.top
                    stack[cell.column] = offset + _heights[k]
                    _cells[k]!.rowTop = row.top
                    _cells[k]!.ownRowHeight = row.height + ghosts
                    _cells[k]!.ghostRows = ghostCount
                    _cells[k]!.ghostBounds = bounds
                    _cells[k]!.stretched = given
                    if cell.rowSpan > 1 {
                        _cells[k]!.rowHeight = spanned
                    } else {
                        _cells[k]!.rowHeight = row.height
                    }
                }
            }
            if let last = rows.last { y = floatsFrom ?? last.top + last.height }
            i = k0
        }
        _flowHeight = y
    }

    /// Re-wraps a turned merged cell's paragraphs `first ... last` to the rows
    /// of it that stand on the page (`turned`), or back to the whole merge's
    /// length where it stands whole, and puts its lines across the column again.
    func _wrapTurned(_ first: Int, _ last: Int, _ d: _CellGeo, _ turned: Double?, _ document: RichDocument) {
        var changed = false
        for m in first ... last {
            guard let painter = _painters[m] else { continue }
            let style = document.paragraphs[m].style
            let inset = d.pad.top + d.pad.bottom + _px(style.indentLeft) + _px(style.indentRight)
            let full = _turnedFull[m] ?? _textWidth[m]
            _turnedFull[m] = full
            var length = turned.map { max(1, $0 - inset) } ?? full
            if abs(length - _textWidth[m]) < 0.01 { continue }
            painter.layout(minWidth: length, maxWidth: length)
            let word = painter.minIntrinsicWidth.rounded(.up)
            if word > length + 0.01 { length = word; painter.layout(minWidth: length, maxWidth: length) }
            _textWidth[m] = length
            _heights[m] = (_spaceBefore[m] + painter.height + _px(style.spaceAfter)).rounded(.up)
            changed = true
        }
        guard changed else { return }
        let endPad = d.direction == .down ? 0 : d.pad.left
        let room = d.colWidth - endPad - d.pad.right
        var content = 0.0, stack: Double? = nil
        for m in first ... last {
            let offset = stack.map { $0 - _cellSharedSpace(m, document) } ?? 0
            stack = offset + _heights[m]
            content = stack!
        }
        let free = max(0, room - content)
        let shift = d.verticalAlign == "center" ? free / 2 : d.verticalAlign == "bottom" ? free : 0
        stack = nil
        for m in first ... last {
            let offset = stack.map { $0 - _cellSharedSpace(m, document) } ?? 0
            stack = offset + _heights[m]
            _cells[m]?.across = d.acrossStart + offset + shift
        }
        for m in first ... last { _cells[m]?.wrapsPart = turned != nil }
    }

    /// Whether `table` floats over the text after it, taking no room: a
    /// table anchored to the text in a header or footer. Word lays
    /// PageSpecificHeadFoot's page-number table (`w:tblpY` 1 twip) over
    /// its footer's line, the line where it would be with no table and
    /// the table's second row under the footer's bottom.
    func _floatsOver(_ table: String, _ document: RichDocument) -> Bool {
        guard floatsFrames && theme.wordRules, let ts = document.tableStyles[table], ts.floatsOverText else { return false }
        // (One that leaves no room beside it, wider than the text with the
        // clear on its sides, takes its place in the flow: the text that
        // follows goes under it. LibreOffice's tdf149089 header: a 509pt
        // table at tblpY -27 over a 499pt column, and the body starts at
        // 84 in Word's print, 12pt under ours.)
        if let kept = ts.keptPosition, let widths = _columnWidths[table], !kept.containsSubstring("w:tblpXSpec") {
            func twips(_ name: String) -> Double {
                guard let r = kept.rangeOfSubstring("\(name)=\"") else { return 0 }
                return Double(kept[r.upperBound...].prefix { $0 == "-" || $0.isNumber }) ?? 0
            }
            let room = (_tableFlowWidth[table] ?? width) - _px(twips("w:tblpX") / 20) - widths.reduce(0, +)
                - _px(twips("w:rightFromText") / 20)
            // (Not one placed down from its anchor, a tblpY of 1 as lab
            // PageSpecificHeadFoot's page-number table has: that one lies over.)
            if room < 0, twips("w:tblpY") < 0 { return false }
        }
        return true
    }

    // MARK: Pagination

    var _columns: Int { _perSection ? _maxSectionColumns : _oneColumn ? 1 : max(1, _bodyColumns ?? pageSetup?.columns ?? 1) }
    /// The columns of paragraph `i`'s section.
    func _columnsOf(paragraph i: Int) -> Int {
        guard _perSection, i >= 0, i < _sectionOf.count, _sectionOf[i] < _sectionColumnCounts.count else { return _columns }
        return _sectionColumnCounts[_sectionOf[i]]
    }
    /// A column's left edge on page `page` for a piece of paragraph `i`
    /// in column `column`.
    func _pxColumnLeft(_ page: Int, column: Int, paragraph i: Int) -> Double {
        guard _perSection else {
            let p = pageSetup(forPage: page)
            let at = p.rtlColumns ? max(0, p.columns - 1 - column) : column
            return _pxMarginLeft(page) + Double(at) * _pxColumnStride(page)
        }
        let s = _setup(ofParagraph: i)
        if s.rtlColumns, s.columns > 1 {
            RuleTrace.hit("rtl-section-columns-run-from-the-right")
            return _pxMarginLeft(page) + Double(max(0, s.columns - 1 - column)) * _px(s.columnWidth + s.columnGap)
        }
        // (A continuous section sets its columns from its own side margin:
        // lo-ff3b52d1's second section, 87.9pt after a first of 90.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, !_mirrorsMargins, s.marginLeft != pageSetup(forPage: page).marginLeft {
            RuleTrace.hit("continuous-section-columns-from-its-own-margin")
            return _px(s.marginLeft + s.gutter) + _px(s.columnOffset(column))
        }
        return _pxMarginLeft(page) + _px(s.columnOffset(column))
    }
    func _pxColumnW(_ page: Int) -> Double { _px(pageSetup(forPage: page).columnWidth) }
    func _pxColumnStride(_ page: Int) -> Double {
        let s = pageSetup(forPage: page)
        return _px(s.columnWidth + s.columnGap)
    }
    func _pxPageW(_ page: Int) -> Double { _px(pageSetup(forPage: page).width) }
    func _pxPageH(_ page: Int) -> Double { _px(pageSetup(forPage: page).height) }
    var _pxGap: Double { _px(pageSetup!.gap) }
    func _pxMarginTop(_ page: Int) -> Double {
        page >= 0 && page < _pageInsetTop.count ? _pageInsetTop[page] : _px(pageSetup(forPage: page).marginTop)
    }
    func _pxMarginLeft(_ page: Int) -> Double {
        let s = pageSetup(forPage: page)
        // Mirrored margins (Word's `w:mirrorMargins`): the left margin
        // and the gutter are the INSIDE ones, on the left of an odd
        // page and the right of an even one, where the text starts at
        // the right margin's distance instead (zh-457a8d62, a gutter
        // of 11.35pt: its even pages begin at 70.9 and its odd ones at
        // 82.25).
        if _mirrorsMargins, page % 2 == 1 { return _px(s.marginRight) }
        return _px(s.marginLeft + s.gutter)
    }

    /// Page `p`'s setup: its section's.
    public func pageSetup(forPage p: Int) -> PageSetup {
        guard p >= 0, p < _pageSection.count, _pageSection[p] < _sectionSetups.count else { return pageSetup ?? .letter }
        return _sectionSetups[_pageSection[p]]
    }

    func _setup(ofParagraph i: Int) -> PageSetup {
        guard i >= 0, i < _sectionOf.count, _sectionOf[i] < _sectionSetups.count else { return pageSetup ?? .letter }
        return _sectionSetups[_sectionOf[i]]
    }

    /// Unequal-width columns (`w:equalWidth` 0): text wraps at the widest column's width
    /// and each piece that falls in a narrower column is held in from the right by the
    /// difference, from its own flow stretch (Word wraps every column at its own width).
    @inline(never)
    func _specInsetBoxes(_ k: Int, _ pieces: ArraySlice<PagePiece>) -> [ColWrapBox] {
        let setup = _setup(ofParagraph: k)
        guard let spec = setup.columnSpec, spec.count == setup.columns, _columns > 0 else { return [] }
        let base = setup.columnWidth
        var out: [ColWrapBox] = []
        for piece in pieces where !piece.repeated {
            let c = piece.page % _columns
            guard c < spec.count, spec[c].width < base - 0.01 else { continue }
            let fromTop = piece.flowTop - (k < _tops.count ? _tops[k] : 0)
            out.append(ColWrapBox(top: fromTop, bottom: fromTop + (piece.flowBottom - piece.flowTop), left: 0, right: _px(base - spec[c].width), byStart: true))
        }
        return out
    }

    /// The width paragraph `i` wraps at: the layout's, in the measure of
    /// its section's column to the document's.
    func _flowWidth(_ i: Int) -> Double {
        guard let base = pageSetup, _sectionSetups.count > 1, base.columnWidth > 0 else { return width }
        if _fullWidthCover.contains(i) { return width * _setup(ofParagraph: i).contentWidth / base.columnWidth }
        return width * _setup(ofParagraph: i).columnWidth / base.columnWidth
    }

    /// The grid paragraph `i` keeps to: its section's, which for the
    /// last section (and a document of one) is the document's.
    /// Whether paragraph `i`'s lines keep off the line grid: it says
    /// `w:snapToGrid` 0, or it is a cell's in a file that does not set
    /// table text to the grid (`RichDocument.adjustsLineHeightInTable`).
    func _offGrid(_ i: Int, _ document: RichDocument) -> Bool {
        guard i >= 0, i < document.paragraphs.count else { return false }
        let p = document.paragraphs[i]
        if p.style.eastAsian["w:snapToGrid"] == "0" { return true }
        return theme.wordRules && p.cell != nil && !document.adjustsLineHeightInTable
    }

    func _grid(_ i: Int?, _ document: RichDocument) -> (pitch: Double?, chars: Double?) {
        guard let i, _sectionSetups.count > 1, i >= 0, i < _sectionOf.count, _sectionOf[i] < _sectionSetups.count - 1 else {
            return (document.lineGridPitch, document.characterGridSpace)
        }
        let setup = _sectionSetups[_sectionOf[i]]
        return (setup.lineGridPitch, setup.characterGridSpace)
    }

    /// The height of a paragraph that is not in the flow — one a
    /// vertically merged cell's continuation holds — with its spacing.
    func _detachedHeight(_ p: RichParagraph, _ document: RichDocument, pair: Bool = false) -> Double {
        func body(_ p: RichParagraph) -> Double {
            let (span, _, _) = _span(for: p, at: nil, document, textWidth: _px(1000))
            let painter = TextPainter(text: span, textAlign: .left, textDirection: .ltr, strutStyle: _strut(span))
            painter.fractionalLineHeights = theme.wordRules
            painter.layout()
            defer { painter.dispose() }
            return p.style.lineCollapsed ? 0 : painter.height
        }
        var height = body(p)
        // (Word does not snap an empty paragraph's line to the grid in a
        // merged cell's continuation row once it is taller than one pitch,
        // when the paragraph MARK names another Latin face than the one the
        // paragraph is set in by its style, at 12pt or less. Labs vm3-vm5:
        // 仿宋 or 宋体 in the mark's ascii slot over a YaHei style, alone or
        // with the other slots, leaves it; no mark properties, size alone,
        // kerning alone, YaHei in every slot over a YaHei style, or 仿宋 in
        // East Asian alone, snap it. zh-eec0747a's header marks say YaHei
        // over a theme-Calibri style: 18.02 + 8.52 where the snapped line
        // would be 31.2 + 8.)
        let styleFace = _named(p, document)?.char.fontFamily ?? _normalChar(document)?.fontFamily
        if pair, theme.wordRules, RichTextTheme.wordWindowsPages, p.text.isEmpty,
           let mark = p.style.mark, let ascii = mark.fontFamily, ascii != styleFace,
           (mark.fontSize ?? 12) <= 12,
           let pitch = _grid(nil, document).pitch {
            var loose = p
            loose.style.eastAsian["w:snapToGrid"] = "0"
            let natural = body(loose)
            if natural > _px(pitch) + 0.01 { height = natural }
        }
        return (_px(p.style.spaceBefore) + height + _px(p.style.spaceAfter)).rounded(.up)
    }

    /// Where each of a painter's lines ends below its top. The engine's
    /// line heights are the lines' own — a first line that opens with
    /// the indent's box is reported an ascent taller than it is set —
    /// and under a forced strut do not add up to the painter's height
    /// (585, 560, 560 for three lines of 560): there every line ends
    /// as far below its baseline as the last does.
    /// The grid's half of the room under a paragraph's first line's text,
    /// px: by the face of its first characters (not a box's place, nor
    /// the smallest on the line, `_overhang`). 0 off the grid.
    func _firstLineGridHalf(_ i: Int, _ document: RichDocument) -> Double {
        let p = document.paragraphs[i]
        guard theme.wordRules, p.image == nil, p.cell == nil, p.style.eastAsian["w:snapToGrid"] != "0",
              let pitch = _grid(i, document).pitch else { return 0 }
        var at = p.text.startIndex
        for run in p.runs {
            let end = p.text.utf16.index(at, offsetBy: run.length, limitedBy: p.text.endIndex) ?? p.text.endIndex
            let text = p.text[at ..< end]
            at = end
            guard text.contains(where: { !$0.isWhitespace && $0 != "\u{FFFC}" }) else { continue }
            let ea = text.contains { Self.isEastAsian($0, hinted: false) }
            return _px(theme.gridOverhang(for: run.style, in: p.style, named: _named(p, document), eastAsian: ea, gridPitch: pitch))
        }
        return i < _overhang.count ? _overhang[i] : 0
    }
    nonisolated(unsafe) static var _pairedLines: [ObjectIdentifier: _PairedLines] = [:]
    static func _paired(_ painter: TextPainter) -> _PairedLines? {
        guard let entry = _pairedLines[ObjectIdentifier(painter)], entry.painter === painter else { return nil }
        return entry
    }
    static func _registerPairs(_ painter: TextPainter, _ indents: [LineIndent], push: (top: Double, bottom: Double)? = nil) {
        _pairedLines = _pairedLines.filter { $0.value.painter != nil }
        let bottoms = _rawLineBottoms(painter)
        var shifts = [Double](repeating: 0, count: bottoms.count)
        // `acc` is how far the lines from here on are moved: up by a right piece
        // that stands level with the line before it, down past a box the text
        // keeps above and below (`push`, the box's stretch of the paragraph: the
        // first line that would meet it, and the lines after, go under it).
        var acc = 0.0
        var pushed = false
        for k in 0 ..< bottoms.count {
            let before = k == 0 ? 0 : bottoms[k - 1]
            if k > 0, k < indents.count, indents[k].left > 0, indents[k].right == 0 || indents[k - 1].right > 0.5 {
                let previous = before - (k >= 2 ? bottoms[k - 2] : 0), own = bottoms[k] - before
                shifts[k] = acc - previous
                acc -= min(own, previous)
            } else {
                if let band = push, !pushed, k > 0, bottoms[k] + acc > band.top + 0.01, before + acc < band.bottom - 0.01 {
                    acc += band.bottom - (before + acc)
                    pushed = true
                }
                shifts[k] = acc
            }
        }
        if abs(acc) > 0.001 { _pairedLines[ObjectIdentifier(painter)] = _PairedLines(painter: painter, shifts: shifts, saving: -acc) }
    }

    static func _lineBottoms(_ painter: TextPainter) -> [Double] {
        let raw = _rawLineBottoms(painter)
        guard let pair = _paired(painter), pair.shifts.count == raw.count else { return raw }
        return zip(raw, pair.shifts).map { $0 + $1 }
    }

    static func _rawLineBottoms(_ painter: TextPainter) -> [Double] {
        // (A paragraph whose lines keep their fractions is the sum of its
        // lines' advances: on the Mac a 1.5-spaced line of YaHei reports
        // an ascent and descent of 644.8 for an advance of 617.4, and
        // zh-34a6519a's page 5 drew page 6's first line.)
        if painter.fractionalLineHeights {
            var sum = 0.0
            return painter.computeLineAdvances().map { sum += $0; return sum }
        }
        let lines = painter.computeLineMetrics()
        var out: [Double] = []
        var sum = 0.0
        for line in lines { sum += line.height; out.append(sum) }
        guard let last = lines.last, abs(sum - painter.height) > 0.5, painter.strutStyle?.forceStrutHeight == true else { return out }
        let below = painter.height - last.baseline
        return lines.map { min(painter.height, $0.baseline + below) }
    }

    /// Reads the sections off the paragraphs; true when they changed.
    func _resolveSections(_ document: RichDocument) -> Bool {
        guard let last = pageSetup, theme.wordRules else {
            let had = _sectionSetups.count > 1
            _sectionSetups = []
            _sectionOf = []
            _mirrorsMargins = false
            return had
        }
        _mirrorsMargins = document.marginSettingsXML.map { $0.containsSubstring("<w:mirrorMargins") && !$0.containsSubstring("<w:mirrorMargins w:val=\"0\"") } ?? false
        var setups: [PageSetup] = []
        var of = Array(repeating: 0, count: document.paragraphs.count)
        var start = 0
        // (Not for the sections of a cover — those before the first that
        // ends on its page: set in the body's columns, the cover is still
        // its page. zh-b5359de4's title is a one-column section between
        // two-column ones on a page of empty paragraphs, its body two
        // columns of A3 landscape; set in one column, the whole file ran
        // 25 pages to Word's 14.)
        let cover = document.paragraphs.firstIndex { $0.cell == nil && $0.style.sectionPage != nil && $0.style.sectionBreaksPage == true } ?? -1
        _oneColumn = last.columns > 1 && document.paragraphs.enumerated().contains { i, p in
            p.cell == nil && i > cover && i < document.paragraphs.count - 1 && p.style.sectionPage.map { max(1, $0.columns) != last.columns } == true
        }
        // (… but its one-column section is set across the page: zh-b5359de4's
        // title "龙泉市城镇老旧小区改造十四五规划" is one line centred on the
        // page in Word's print, where ours wrapped it in a half-page column.)
        // (Sections that disagree on their columns, each with its own: the
        // continuous ones start where the section before them ends, and
        // that one's columns are balanced above them. Word's print of
        // LibreOffice's tdf139336, a page of nine sections of two and three
        // columns and one.)
        _perSection = false
        _sectionColumnCounts = []
        _maxSectionColumns = 1
        if theme.wordRules {
            // (A section whose columns the importer made a table of, the
            // one before its closing paragraph, is one column here: the
            // table's cells are the columns, `TableStyle.sectionColumns`.)
            func tableMakesColumns(_ i: Int) -> Bool {
                i > 0 && document.paragraphs[i - 1].cell.map { document.tableStyles[$0.table]?.sectionColumns == true } == true
            }
            var counts: [Int] = []
            for (i, p) in document.paragraphs.enumerated() where p.cell == nil && i < document.paragraphs.count - 1 {
                if let own = p.style.sectionPage { counts.append(tableMakesColumns(i) ? 1 : max(1, own.columns)) }
            }
            counts.append(document.paragraphs.last.map { $0.cell.map { document.tableStyles[$0.table]?.sectionColumns == true } == true } == true ? 1 : max(1, last.columns))
            // Unequal-width sections run per section too (columns set equal for now):
            // without it a 2-column section is never balanced at a continuous break (28abf02c).
            if Set(counts).count > 1, counts.contains(where: { $0 > 1 }) {
                _perSection = true
                _sectionColumnCounts = counts
                _maxSectionColumns = counts.max() ?? 1
                _oneColumn = false
            }
        }
        _fullWidthCover = []
        if theme.wordRules, !_oneColumn, !_perSection, last.columns > 1, cover > 0 {
            var from = 0
            for (i, p) in document.paragraphs.enumerated() where p.cell == nil && i <= cover {
                guard let own = p.style.sectionPage else { continue }
                if max(1, own.columns) == 1 { for k in from ... i where document.paragraphs[k].cell == nil { _fullWidthCover.insert(k) } }
                from = i + 1
            }
        }
        // (A body of columns closed by a section of one with nothing in it:
        // lenovo-2's fdo43573-2-min is one section of two unequal columns,
        // ending at a paragraph's sectPr, and a continuous section of one
        // holding the last, empty paragraph. Word sets the text in two
        // columns on 15 pages; ours took the last section's count for all
        // of it and set one column on 20. The body's count and gap stand,
        // and the closing paragraph is set in a column of it. Not where
        // that section holds text — unbalanced-columns-compat sets its
        // closing paragraph across the page under two short columns.)
        _bodyColumns = nil
        var bodyGap: Double? = nil
        if theme.wordRules, last.columns == 1, !_oneColumn, !_perSection {
            let owns = document.paragraphs.enumerated().filter { i, p in
                p.cell == nil && i < document.paragraphs.count - 1 && p.style.sectionPage != nil
            }
            if let first = owns.first?.element.style.sectionPage, first.columns > 1,
               owns.allSatisfy({ $0.element.style.sectionPage?.columns == first.columns }),
               let closing = owns.last?.offset, document.paragraphs.count - 1 - closing <= 3,
               document.paragraphs[(closing + 1)...].allSatisfy({ $0.cell == nil && $0.text.allSatisfy(\.isWhitespace) && $0.image == nil }) {
                _bodyColumns = first.columns
                bodyGap = first.columnGap
            }
        }
        for (i, p) in document.paragraphs.enumerated() where p.cell == nil {
            guard var setup = p.style.sectionPage, i < document.paragraphs.count - 1 else { continue }
            if !_perSection {
                setup.columns = _oneColumn ? 1 : _bodyColumns ?? last.columns
                setup.columnSpec = nil
                setup.columnGap = bodyGap ?? last.columnGap
            }
            if _perSection, i > 0, document.paragraphs[i - 1].cell.map({ document.tableStyles[$0.table]?.sectionColumns == true }) == true { setup.columns = 1; setup.columnSpec = nil }
            setup.gap = last.gap
            for k in start ... i { of[k] = setups.count }
            setups.append(setup)
            start = i + 1
        }
        if start < of.count { for k in start ..< of.count { of[k] = setups.count } }
        var final = last
        if _oneColumn { final.columns = 1; final.columnSpec = nil }
        if _perSection, let tail = document.paragraphs.last, tail.cell.map({ document.tableStyles[$0.table]?.sectionColumns == true }) == true { final.columns = 1; final.columnSpec = nil }
        if let body = _bodyColumns { final.columns = body; final.columnSpec = nil; final.columnGap = bodyGap ?? final.columnGap }
        // (One column of its own width, `w:equalWidth` 0 and a single `w:col`:
        // the text wraps at that, not at the page's. lo-eae9bbb1's last
        // section, a 100pt column under a first section of the page's width.)
        if theme.wordRules, RichTextTheme.wordWindowsPages, setups.count > 0, final.columns == 1, let xml = document.columnsXML,
           xml.containsSubstring("w:equalWidth=\"0\""), let r = xml.rangeOfSubstring("<w:col w:w=\""),
           let end = xml[r.upperBound...].firstIndex(of: "\""), let twips = Double(xml[r.upperBound ..< end]),
           twips / 20 > 20, twips / 20 < final.contentWidth - 1, xml.components(separatedBy: "<w:col ").count == 2 {
            RuleTrace.hit("single-unequal-column-sets-the-measure")
            final.marginRight += final.contentWidth - twips / 20
        }
        setups.append(final)
        let changed = setups != _sectionSetups || (setups.count > 1 && of != _sectionOf)
        _sectionSetups = setups
        _sectionOf = of
        return changed
    }
}
