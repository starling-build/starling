import Foundation

extension RichLayout {
    /// In a vertical (tbRl) section the page is laid out turned a quarter, and Word's text goes round the pictures and boxes the
    /// file sets from the page or its margins, on the paper: the offsets run across (x) and down (y) the paper. Here each such
    /// float of the paragraphs a physical page opens on (up to the first one with text) becomes a window on the page's columns:
    /// a column the float leaves no room beside for one em is open only above and below it, so its text starts under the first
    /// float and stops over the next, and a column the float fills is left empty. (ja-b852b9029c: the banner over the first column,
    /// a 289 by 546pt picture over the others, a box at their head; Word's page 1 holds three lines in each of the last four
    /// columns, ours ran every column from edge to edge and set the document on one page, not two.)
    @inline(never)
    func _pg_verticalWindow(_ pgs: inout _PState, _ document: RichDocument) {
        guard theme.wordRules, RichTextTheme.wordWindowsPages, pgs.i < count, pgs.i < _cells.count, _cells[pgs.i] == nil, _verticalBody(pgs.i) else { return }
        let physical = pgs.page / _columns, column = pgs.page % _columns
        let setup = pageSetup(forPage: physical)
        if column == 0 {
            var seeds: [(id: String, left: Double, right: Double, top: Double, bottom: Double)] = []
            var taken = Set<String>()
            for (page, list) in _verticalSeeds where page < physical { for s in list { taken.insert(s.id) } }
            var k = pgs.i
            let em = _px(12)
            let pitch = max(em, Self._lineBottoms(geometry(pgs.i).painter).first ?? em)
            var filled = 0.0
            while k < count, _cells[k] == nil, _verticalBody(k), k < pgs.i + 40 {
                var own: [ImageAttachment] = []
                if k < _floatImages.count, let image = _floatImages[k] { own.append(image) }
                if k < _inline.count { own += _inline[k] }
                for image in own where !taken.contains(image.id) {
                    guard let f = image.float, f.wraps, !f.takesRoom, !f.bandsPage, f.wrapSide == nil,
                          f.horizontalFrom == "margin" || f.horizontalFrom == "page", f.verticalFrom == "margin" || f.verticalFrom == "page",
                          image.width > 0, image.height > 0, image.textBox != nil || !image.data.isEmpty || image.outline != nil,
                          abs(image.rotation.truncatingRemainder(dividingBy: 180)) < 0.01 else { continue }
                    // (The turned page: its height is the paper's width, its left margin the paper's top, its top margin the paper's
                    // right, its bottom margin the paper's left.)
                    let paperW = setup.height, paperH = setup.width
                    let w = image.width, h = image.height
                    let baseX = f.horizontalFrom == "page" ? 0 : setup.marginBottom
                    let spanX = f.horizontalFrom == "page" ? paperW : paperW - setup.marginBottom - setup.marginTop
                    let baseY = f.verticalFrom == "page" ? 0 : setup.marginLeft
                    let spanY = f.verticalFrom == "page" ? paperH : paperH - setup.marginLeft - setup.marginRight
                    var x0 = baseX + f.x, y0 = baseY + f.y
                    switch f.horizontalAlign {
                    case "left"?: x0 = baseX
                    case "right"?: x0 = baseX + spanX - w
                    case "center"?: x0 = baseX + (spanX - w) / 2
                    default: break
                    }
                    switch f.verticalAlign {
                    case "top"?: y0 = baseY
                    case "bottom"?: y0 = baseY + spanY - h
                    case "center"?: y0 = baseY + (spanY - h) / 2
                    default: break
                    }
                    // (Paper x grows leftward in the flow: the paper's right side is its top. Its left and right distances run along the
                    // flow, its top and bottom ones across it.)
                    let flowTop = paperW - (x0 + w) - setup.marginTop - (f.distanceRight ?? 9)
                    let flowBottom = paperW - x0 - setup.marginTop + (f.distanceLeft ?? 9)
                    let across0 = y0 - setup.marginLeft - f.distanceTop
                    let across1 = y0 + h - setup.marginLeft + f.distanceBottom
                    seeds.append((image.id, _px(across0), _px(across1), _px(flowTop), _px(flowBottom)))
                }
                // (The next paragraph starts on this page only while the text so far leaves room in the columns the floats leave.)
                filled += Double(document.paragraphs[k].text.count)
                let flow = _px(setup.height - setup.marginTop - setup.marginBottom)
                var room = 0.0
                for c in 0..<_columns {
                    let a = _px(setup.columnOffset(c)), b = a + _px(setup.columnWidth)
                    var hit: [(Double, Double)] = []
                    for t in seeds where t.right > a && t.left < b && max(0, t.left - a) < em && max(0, b - t.right) < em {
                        hit.append((max(0, t.top), min(flow, t.bottom)))
                    }
                    hit.sort { $0.0 < $1.0 }
                    var free = flow, upto = 0.0
                    for h in hit where h.1 > upto { free -= h.1 - max(h.0, upto); upto = h.1 }
                    room += max(0, free) / pitch * _px(setup.columnWidth) / em
                }
                if filled >= room { break }
                k += 1
            }
            _verticalSeeds[physical] = seeds
        }
        guard let seeds = _verticalSeeds[physical], !seeds.isEmpty else { return }
        let spec = setup.columnOffset(column)
        let start = _px(spec), width = _px(setup.columnWidth)
        let em = _px(12)
        var blocked: [(Double, Double)] = []
        for s in seeds {
            // (Beside it, room for one em: the text there, as before.)
            let before = max(0, s.left - start), after = max(0, start + width - s.right)
            guard s.right > start, s.left < start + width, before < em, after < em else { continue }
            blocked.append((max(0, s.top), min(pgs.contentH, s.bottom)))
        }
        guard !blocked.isEmpty else { return }
        blocked.sort { $0.0 < $1.0 }
        let line = max(em, Self._lineBottoms(geometry(pgs.i).painter).first ?? em)
        var at = pgs.y
        for b in blocked where b.1 > at {
            if b.0 - at >= line - 0.01 { break }
            at = max(at, b.1)
        }
        var end = pgs.contentH
        for b in blocked where b.0 > at - 0.01 { end = min(end, b.0); break }
        if pgs.contentH - at < line - 0.01 || end - at < line - 0.01 {
            RuleTrace.hit("word-vertical-column-filled-by-a-float-is-left-empty")
            pgs.y = pgs.contentH
            return
        }
        RuleTrace.hit("word-vertical-column-window-between-floats")
        pgs.y = at
        pgs.contentH = end
    }
}
