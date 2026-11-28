// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-FM-3: Home > Borders, Excel's preset list. A preset draws on the
// selection's edges (Bottom Border is the bottom row's bottom, not every
// cell's), and each is one undo step.

extension WorkbookController {
    enum BorderPreset: CaseIterable {
        case bottom, top, left, right, none, all, outside, thickOutside
        case doubleBottom, thickBottom, topAndBottom, topAndThickBottom, topAndDoubleBottom

        /// The menu label, in Excel's order and wording.
        var title: String {
            switch self {
            case .bottom: return "Bottom Border"
            case .top: return "Top Border"
            case .left: return "Left Border"
            case .right: return "Right Border"
            case .none: return "No Border"
            case .all: return "All Borders"
            case .outside: return "Outside Borders"
            case .thickOutside: return "Thick Outside Borders"
            case .doubleBottom: return "Bottom Double Border"
            case .thickBottom: return "Thick Bottom Border"
            case .topAndBottom: return "Top and Bottom Border"
            case .topAndThickBottom: return "Top and Thick Bottom Border"
            case .topAndDoubleBottom: return "Top and Double Bottom Border"
            }
        }
    }

    /// Draw a Borders preset on the selection, as one undo step.
    func applyBorders(_ preset: BorderPreset) {
        if refuses("formatCells") { return }
        borderDrawMode = nil  // a preset puts the pen down, as in Excel
        if _eachRange({ applyBorders(preset) }) { return }
        let r = selection
        let topRow = CellRange(top: r.top, left: r.left, bottom: r.top, right: r.right)
        let bottomRow = CellRange(top: r.bottom, left: r.left, bottom: r.bottom, right: r.right)
        let leftCol = CellRange(top: r.top, left: r.left, bottom: r.bottom, right: r.left)
        let rightCol = CellRange(top: r.top, left: r.right, bottom: r.bottom, right: r.right)
        // A side on in the pen's colour. A preset's own weight (thick, double) wins; a plain
        // preset draws in the pen's Line Style, as Excel does. "thin" is the file's default
        // and is not written.
        let pen = (color: borderPenColor, kind: borderPenKind)
        func draw(_ range: CellRange, _ side: WritableKeyPath<CellStyle.Borders, Bool>, _ name: String, _ preset: String = "thin") {
            let kind = preset == "thin" ? pen.kind : preset
            setStyle({ st in
                st.borders[keyPath: side] = true
                st.borders.kinds[name] = kind == "thin" ? nil : kind
                st.borders.colors[name] = pen.color
            }, range: range)
        }
        asOneStep {
            switch preset {
            case .bottom: draw(bottomRow, \.bottom, "bottom")
            case .top: draw(topRow, \.top, "top")
            case .left: draw(leftCol, \.left, "left")
            case .right: draw(rightCol, \.right, "right")
            case .none: setStyle({ $0.borders = .init() }, range: r)
            case .all:
                setStyle({ st in
                    st.borders.top = true; st.borders.left = true; st.borders.bottom = true; st.borders.right = true
                    st.borders.kinds = [:]; st.borders.colors = [:]
                    for side in ["top", "left", "bottom", "right"] {
                        if pen.kind != "thin" { st.borders.kinds[side] = pen.kind }
                        if let c = pen.color { st.borders.colors[side] = c }
                    }
                }, range: r)
            case .outside, .thickOutside:
                let k = preset == .outside ? "thin" : "thick"
                draw(topRow, \.top, "top", k); draw(bottomRow, \.bottom, "bottom", k)
                draw(leftCol, \.left, "left", k); draw(rightCol, \.right, "right", k)
            case .doubleBottom: draw(bottomRow, \.bottom, "bottom", "double")
            case .thickBottom: draw(bottomRow, \.bottom, "bottom", "thick")
            case .topAndBottom: draw(topRow, \.top, "top"); draw(bottomRow, \.bottom, "bottom")
            case .topAndThickBottom: draw(topRow, \.top, "top"); draw(bottomRow, \.bottom, "bottom", "thick")
            case .topAndDoubleBottom: draw(topRow, \.top, "top"); draw(bottomRow, \.bottom, "bottom", "double")
            }
        }
    }

    enum BorderDrawMode: Equatable { case draw, grid, erase }

    /// Draw Border draws the range's outline, Draw Border Grid every cell's edges, both with the
    /// pen; Erase Border takes every line in and around the range away (the neighbour's side of a
    /// shared edge too, since either cell may hold it). One undo step.
    func drawBorders(on r: CellRange, mode: BorderDrawMode) {
        if refuses("formatCells") { return }
        let pen = (color: borderPenColor, kind: borderPenKind)
        func on(_ st: inout CellStyle, _ side: WritableKeyPath<CellStyle.Borders, Bool>, _ name: String) {
            st.borders[keyPath: side] = true
            st.borders.kinds[name] = pen.kind == "thin" ? nil : pen.kind
            st.borders.colors[name] = pen.color
        }
        func off(_ st: inout CellStyle, _ side: WritableKeyPath<CellStyle.Borders, Bool>, _ name: String) {
            st.borders[keyPath: side] = false
            st.borders.kinds[name] = nil; st.borders.colors[name] = nil
        }
        func row(_ y: Int) -> CellRange { CellRange(top: y, left: r.left, bottom: y, right: r.right) }
        func col(_ x: Int) -> CellRange { CellRange(top: r.top, left: x, bottom: r.bottom, right: x) }
        asOneStep {
            switch mode {
            case .draw:
                setStyle({ on(&$0, \.top, "top") }, range: row(r.top))
                setStyle({ on(&$0, \.bottom, "bottom") }, range: row(r.bottom))
                setStyle({ on(&$0, \.left, "left") }, range: col(r.left))
                setStyle({ on(&$0, \.right, "right") }, range: col(r.right))
            case .grid:
                setStyle({ st in
                    on(&st, \.top, "top"); on(&st, \.bottom, "bottom"); on(&st, \.left, "left"); on(&st, \.right, "right")
                }, range: r)
            case .erase:
                setStyle({ $0.borders = .init() }, range: r)
                if r.top > 0 { setStyle({ off(&$0, \.bottom, "bottom") }, range: row(r.top - 1)) }
                if r.bottom + 1 < CellAddress.maxRows { setStyle({ off(&$0, \.top, "top") }, range: row(r.bottom + 1)) }
                if r.left > 0 { setStyle({ off(&$0, \.right, "right") }, range: col(r.left - 1)) }
                if r.right + 1 < CellAddress.maxCols { setStyle({ off(&$0, \.left, "left") }, range: col(r.right + 1)) }
            }
        }
    }

    /// A Line Color or Line Style pick arms the pen: Draw Border, unless Grid is already on.
    func penPicked() { if borderDrawMode != .grid { borderDrawMode = .draw } }
}
