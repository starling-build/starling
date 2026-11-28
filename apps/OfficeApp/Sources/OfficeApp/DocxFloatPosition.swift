// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation
import OfficeText

extension DocxFormat {
    /// A floating table's place (`w:tblpPr`, and `w:tblOverlap` after it) into the fields the layout reads. The reader
    /// and the editor's Positioning dialog and move handle (W-TB-5) both go through here, so a table placed in the
    /// editor lays out as the same file opened would.
    static func readFloatPosition(_ pos: XNode, overlap: XNode?, bidiVisual: Bool, shapesLeaveCell: Bool, into style: inout TableStyle) {
        if pos["w:vertAnchor"] == "page" { style.pageAnchored = true }
        if pos["w:vertAnchor"] == "page", pos["w:tblpYSpec"] == nil, let v = Double(pos["w:tblpY"] ?? "") { style.pageOffsetY = v / 20 }
        if pos["w:tblpYSpec"] == "bottom", pos["w:tblpY"] == nil { style.pageAnchored = true; style.bottomAligned = true }
        style.keptPosition = PptxXML.serialize(pos) + (overlap.map { PptxXML.serialize($0) } ?? "")
        // (No `w:vertAnchor` is the text's, the schema's default: LibreOffice's fdo68607, `w:tblpY` 495
        // and none, stands 24.75pt under the margin in Word for Windows' print, where ours stood at it.)
        let vertText = (pos["w:vertAnchor"] ?? "text") == "text"
        if vertText, pos["w:tblpYSpec"] == nil, let v = Double(pos["w:tblpY"] ?? ""), v > 0 {
            if pos["w:vertAnchor"] == nil { style.marginOffsetY = v / 20 } else { style.floatOffsetY = v / 20 }
        }
        // (A table anchored to the margin stands w:tblpY under the nominal top margin, as one
        // with no anchor stated does: Word's print of lab tblhdr h2, first baseline 151.82.)
        if Self.wordOnWindows, pos["w:vertAnchor"] == "margin", pos["w:tblpYSpec"] == nil, let v = Double(pos["w:tblpY"] ?? ""), v > 0 {
            style.marginOffsetY = v / 20
        }
        if Self.wordOnWindows, pos["w:vertAnchor"] == "margin", pos["w:tblpYSpec"] == nil, style.marginOffsetY != nil { style.floatOffsetY = style.marginOffsetY }
        // (`w:tblpYSpec="top"` with no anchor stated stands at the margin's top, over the empty
        // paragraph before it: LibreOffice's lo-0dd5bc0a, a cover-page SDT; Word's print has it 26pt
        // higher than ours, which set it under that paragraph.)
        if let v = Double(pos["w:bottomFromText"] ?? ""), v > 0, style.floatOffsetY != nil, pos["w:tblpYSpec"] == nil { style.floatBottomGap = v / 20 }
        if pos["w:tblpYSpec"] == "top", pos["w:vertAnchor"] == nil || pos["w:vertAnchor"] == "margin", pos["w:tblpY"] == nil {
            style.marginOffsetY = 0
        }
        // (A table placed "inside" the text's line takes no room in it either: LibreOffice's
        // tdf-less lo-4c84a541 has "After table1" level with it in Word's print.)
        if vertText || (Self.wordOnWindows && pos["w:vertAnchor"] == "margin" && style.marginOffsetY != nil), pos["w:tblpYSpec"] == nil || pos["w:tblpYSpec"] == "inside" { style.floatsOverText = true }
        if pos["w:vertAnchor"] == "text", pos["w:tblpYSpec"] == "top" { style.floatsTopByText = true }
        // (A drawing the table holds that is not laid out in its cell.)
        if shapesLeaveCell { style.shapesLeaveCell = true }
        if vertText, pos["w:tblpYSpec"] == nil, let v = Double(pos["w:tblpY"] ?? ""), v < 0 {
            style.floatRaiseY = -v / 20
        }
        if pos["w:tblpXSpec"] == nil, let v = Double(pos["w:tblpX"] ?? "") {
            style.floatX = v / 20
            style.floatXAnchor = pos["w:horzAnchor"] ?? "text"
        } else if let spec = pos["w:tblpXSpec"], (pos["w:horzAnchor"] ?? "text") != "page" || (spec == "center" && DocxFormat.wordOnWindows) {
            // (Centred on the PAGE, as zh-a4e8599d p3's: its first rule at 67.8 in Word's print, the middle of 595pt
            // for 460pt of table, where ours stood at the margin, 84.6. On a page of equal margins the two middles are one.)
            // Or aligned in its margin or column, a table wider
            // than it standing out on both sides: zh-0243e7fc
            // p11's 539pt form, centred on its 415pt margin, has
            // its first column's text at 54pt in Word's print,
            // where ours, at the margin, stood at 115.
            if spec == "center" { style.alignment = .center }
            if spec == "center", DocxFormat.wordOnWindows, bidiVisual { style.floatCentredBidi = true }
            if spec == "right" { style.alignment = .right }
            style.floatXAnchor = pos["w:horzAnchor"] ?? "text"   // (read only for the table's x in columns)
        }
    }

    /// The same, from a position kept as XML (`TableStyle.keptPosition`): every float field cleared first, then read
    /// again. Nil or unreadable XML leaves the table in the flow.
    static func applyKeptPosition(_ xml: String?, to style: inout TableStyle) {
        let plain = TableStyle()
        if style.keptPosition?.containsSubstring("w:tblpXSpec=") == true, style.floatX == nil { style.alignment = plain.alignment }
        style.keptPosition = nil
        style.pageAnchored = plain.pageAnchored; style.pageOffsetY = plain.pageOffsetY; style.bottomAligned = plain.bottomAligned
        style.marginOffsetY = plain.marginOffsetY; style.floatOffsetY = plain.floatOffsetY; style.floatBottomGap = plain.floatBottomGap
        style.floatsOverText = plain.floatsOverText; style.floatsTopByText = plain.floatsTopByText; style.floatRaiseY = plain.floatRaiseY
        style.floatX = plain.floatX; style.floatXAnchor = plain.floatXAnchor; style.floatCentredBidi = plain.floatCentredBidi
        guard let xml, let root = XNode.parse(Data(("<r xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">" + xml + "</r>").utf8)),
              let pos = root.first("w:tblpPr") else { return }
        readFloatPosition(pos, overlap: root.first("w:tblOverlap"), bidiVisual: style.bidiVisual, shapesLeaveCell: style.shapesLeaveCell, into: &style)
    }
}
