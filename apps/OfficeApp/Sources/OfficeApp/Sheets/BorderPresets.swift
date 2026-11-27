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
        let r = selection
        let topRow = CellRange(top: r.top, left: r.left, bottom: r.top, right: r.right)
        let bottomRow = CellRange(top: r.bottom, left: r.left, bottom: r.bottom, right: r.right)
        let leftCol = CellRange(top: r.top, left: r.left, bottom: r.bottom, right: r.left)
        let rightCol = CellRange(top: r.top, left: r.right, bottom: r.bottom, right: r.right)
        // A side on, in a line kind ("thin" is the file's default and is not written), automatic colour.
        func draw(_ range: CellRange, _ side: WritableKeyPath<CellStyle.Borders, Bool>, _ name: String, _ kind: String = "thin") {
            setStyle({ st in
                st.borders[keyPath: side] = true
                st.borders.kinds[name] = kind == "thin" ? nil : kind
                st.borders.colors[name] = nil
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
}
