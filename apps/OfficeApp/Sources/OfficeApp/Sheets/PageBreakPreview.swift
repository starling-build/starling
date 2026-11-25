// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// View > Page Break Preview (X-PR-1): where the printed pages are cut, as
// blue lines over the grid. A manual break is a solid line, one the page
// size forces is dashed. The cut is the print layout's own (SheetPrintLayout.pages),
// fed the editor's column widths and row heights in points.

import Flutter
import FlutterSwiftBridge
import Foundation

struct PageBreakLines: Equatable {
    /// First row / column of each page after the first, with whether the user set it.
    var rows: [(at: Int, manual: Bool)] = []
    var cols: [(at: Int, manual: Bool)] = []
    var area: CellRange? = nil
    static func == (a: PageBreakLines, b: PageBreakLines) -> Bool {
        a.area == b.area && a.rows.map(\.at) == b.rows.map(\.at) && a.cols.map(\.at) == b.cols.map(\.at)
            && a.rows.map(\.manual) == b.rows.map(\.manual) && a.cols.map(\.manual) == b.cols.map(\.manual)
    }
}

extension PageBreakLines {
    /// The cut (index in `cuts`) whose line lies within 4 px of `pos`; `edge` gives a line's screen position.
    static func grab(_ cuts: [Int], at pos: Double, edge: (Int) -> Double) -> Int? {
        cuts.first { abs(edge($0) - pos) <= 4 }
    }
    /// Which row/column edge a dragged line is nearest to: the start of `index`, or of the next one.
    static func nearestEdge(index: Int, pos: Double, start: (Int) -> Double, size: (Int) -> Double) -> Int {
        pos - start(index) > size(index) / 2 ? index + 1 : index
    }

    /// The cuts of the controller's active sheet, given each column's width and row's height in points.
    static func compute(_ c: WorkbookController, width: (Int) -> Double, height: (Int) -> Double) -> PageBreakLines {
        let ws = c.sheet, book = c.book
        guard !ws.isChartSheet else { return PageBreakLines() }
        let names = SheetPrintLayout.printNames(book, sheet: c.activeSheet)
        guard let area = names.areas.first ?? SheetPrintLayout.usedArea(ws, book: book) else { return PageBreakLines() }
        let setup = SheetPrintSetup.read(ws)
        let job = SheetPrintLayout.pages(area: area, setup: setup, width: width, height: height)
        var out = PageBreakLines(area: area)
        var seenR = Set<Int>(), seenC = Set<Int>()
        for p in job.pages {
            if let r = p.rows.first, r > area.top, seenR.insert(r).inserted { out.rows.append((r, setup.rowBreaks.contains(r))) }
            if let c = p.cols.first, c > area.left, seenC.insert(c).inserted { out.cols.append((c, setup.colBreaks.contains(c))) }
        }
        out.rows.sort { $0.at < $1.at }; out.cols.sort { $0.at < $1.at }
        return out
    }
}

extension SheetGridState {
    /// The page cuts of the active sheet: its print area, else what holds data.
    func pageBreakLines() -> PageBreakLines {
        let ca = cols, ra = rows
        let k = 0.75 / max(zoom, 0.01)          // pixels at this zoom to points
        return PageBreakLines.compute(controller, width: { ca.size($0) * k }, height: { ra.size($0) * k })
    }

    /// Paint the cuts over the cell area (`hw`, `hh`: the headers' size).
    func paintPageBreaks(_ canvas: any Canvas, _ size: Size, dragging: (isRow: Bool, at: Int, to: Int)? = nil) {
        var lines = pageBreakLines()
        guard let area = lines.area else { return }
        if let d = dragging {
            // The line follows the pointer; the one it was dragged from is not drawn where it was.
            if d.isRow { lines.rows.removeAll { $0.at == d.at }; lines.rows.append((d.to, true)) }
            else { lines.cols.removeAll { $0.at == d.at }; lines.cols.append((d.to, true)) }
        }
        let hw = headerWidth, hh = headerHeight
        // Outside the print area is shaded, as Excel's preview shows it.
        let shade = Paint()
        shade.style = .fill
        shade.color = Color(0x40808080)
        let ax0 = max(hw, colX(area.left)), ax1 = min(size.width, colX(area.right) + cols.size(area.right))
        let ay0 = max(hh, rowY(area.top)), ay1 = min(size.height, rowY(area.bottom) + rows.size(area.bottom))
        if ay0 > hh { canvas.drawRect(Rect.fromLTRB(hw, hh, size.width, ay0), shade) }
        if ay1 < size.height { canvas.drawRect(Rect.fromLTRB(hw, max(ay1, hh), size.width, size.height), shade) }
        if ax0 > hw { canvas.drawRect(Rect.fromLTRB(hw, ay0, ax0, max(ay0, ay1)), shade) }
        if ax1 < size.width { canvas.drawRect(Rect.fromLTRB(ax1, ay0, size.width, max(ay0, ay1)), shade) }
        let blue = Paint()
        blue.style = .stroke
        blue.strokeWidth = 2
        blue.color = Color(0xFF1F5FBF)
        let top = max(hh, rowY(area.top)), bottom = min(size.height, rowY(area.bottom) + rows.size(area.bottom))
        let left = max(hw, colX(area.left)), right = min(size.width, colX(area.right) + cols.size(area.right))
        func dashed(_ a: Offset, _ b: Offset) {
            let horizontal = a.dy == b.dy
            var t = horizontal ? a.dx : a.dy
            let end = horizontal ? b.dx : b.dy
            while t < end {
                let u = min(t + 6, end)
                canvas.drawLine(horizontal ? Offset(t, a.dy) : Offset(a.dx, t), horizontal ? Offset(u, a.dy) : Offset(a.dx, u), blue)
                t += 10
            }
        }
        for r in lines.rows {
            let y = rowY(r.at).rounded()
            guard y > hh, y < size.height else { continue }
            if r.manual { canvas.drawLine(Offset(left, y), Offset(right, y), blue) } else { dashed(Offset(left, y), Offset(right, y)) }
        }
        for c in lines.cols {
            let x = colX(c.at).rounded()
            guard x > hw, x < size.width else { continue }
            if c.manual { canvas.drawLine(Offset(x, top), Offset(x, bottom), blue) } else { dashed(Offset(x, top), Offset(x, bottom)) }
        }
    }
}

extension WorkbookController {
    /// Drag a break to a new place: the cut at `from` moves to `to` (rows when `isRow`). One undo step.
    func moveBreak(isRow: Bool, from: Int, to: Int) {
        guard from != to, to > 0 else { return }
        let ws = sheet
        let name = isRow ? "rowBreaks" : "colBreaks"
        structural {
            ws.setBreaks(name, ws.breakIds(name).filter { $0 != from } + [to], max: isRow ? 16383 : 1048575)
        }
    }
}
