// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The active sheet as the grid lays it out at 100%, as text: every used
// column's width and row's height in points, and every cell with a value
// — its address, how it aligns, what it shows, whether that text is wider
// than its cell (and so spills or is cut), how many lines it wraps to, and
// whether a number shows as ####. Discrete outcomes only: the browser
// measures text a pixel narrower than the Mac does, and a width in the
// dump would differ on every line while nothing drawn differs. The same
// text from `OfficeApp --sheet-layout file.xlsx`
// natively and from `starling.debug('sheet')` in the browser; `diff`
// them to find where the two platforms measure or format differently.

import Flutter
import FlutterSwiftBridge
import Foundation

enum SheetLayoutDump {
    static func text(_ c: WorkbookController) -> String {
        let ws = c.sheet, book = c.book
        let scale = 96.0 / 72.0
        let used = ws.usedExtent
        var out = "sheet \(ws.name) rows=\(used.row + 1) cols=\(used.col + 1)\n"
        for col in 0 ... used.col where !ws.hiddenCols.contains(col) {
            out += "col \(CellAddress.columnName(col)) \(_pt(ws.colWidth(col)))\n"
        }
        for row in 0 ... used.row where !ws.hiddenRows.contains(row) && !ws.filteredRows.contains(row) {
            out += "row \(row + 1) \(_pt(ws.rowHeight(row)))\n"
        }
        for row in 0 ... used.row {
            for col in 0 ... used.col {
                let a = CellAddress(row: row, col: col)
                let value = ws.value(a)
                guard !value.isEmpty, let cell = ws.cells[a] else { continue }
                let st = book.style(cell.style)
                let width = ws.colWidth(col) * scale
                let chars = max(1, Int(width / (7 * 1.0)))
                var (shown, _) = NumberFormat.display(value, st.numberFormat, width: chars)
                var align = st.hAlign
                if align == .general {
                    switch value {
                    case .number: align = .right
                    case .bool, .error: align = .center
                    default: align = .left
                    }
                }
                let style = GridTextStyle(family: OfficeFonts.substitute(st.fontName ?? OfficeFonts.defaultFamily),
                                          size: (st.fontSize ?? 11) * scale * SheetGridState.excelTextScale,
                                          bold: st.bold, italic: st.italic, underline: st.underline, strike: st.strike,
                                          color: Int64(0xFF00_0000))
                let pad = 2.0
                let wraps = st.wrap && value.isText
                let tp = TextPainter(text: TextSpan(text: shown, style: style.flutter), textDirection: .ltr)
                tp.layout(minWidth: 0, maxWidth: wraps ? max(1, width - pad * 2) : .infinity)
                var note = ""
                if case .number = value, tp.width > width - pad * 2 {
                    shown = "####"
                } else if wraps {
                    let lines = Int((tp.height / max(1, tp.preferredLineHeight)).rounded())
                    note = "\tlines=\(lines)"
                } else if tp.width > width - pad * 2 {
                    note = "\tover"
                }
                tp.dispose()
                out += "\(a.a1)\t\(align.rawValue)\t\(shown)\(note)\n"
            }
        }
        return out
    }

    private static func _pt(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(r)
    }
}
