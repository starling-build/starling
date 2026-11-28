// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

/// W-TB-5: where a floating table stands, as Word's Table Positioning dialog sets it and as the file says it
/// (`w:tblpPr`, and `w:tblOverlap` after it). Lengths in points.
public struct TablePosition: Equatable {
    /// What the horizontal place is measured from: `w:horzAnchor` ("text" is Word's Column).
    public enum HorizontalFrom: String, CaseIterable { case column = "text", margin, page }
    /// What the vertical place is measured from: `w:vertAnchor` ("text" is Word's Paragraph).
    public enum VerticalFrom: String, CaseIterable { case paragraph = "text", margin, page }

    /// Left, center, right, inside or outside (`w:tblpXSpec`); nil: the distance `x`.
    public var horizontalAlign: String? = nil
    public var x: Double = 0
    public var horizontalFrom: HorizontalFrom = .column
    /// Top, center, bottom, inside or outside (`w:tblpYSpec`); nil: the distance `y`.
    public var verticalAlign: String? = nil
    public var y: Double = 0
    public var verticalFrom: VerticalFrom = .paragraph
    /// Distance from surrounding text.
    public var top: Double = 0, bottom: Double = 0, left: Double = 9, right: Double = 9
    /// Word's Allow overlap (`w:tblOverlap`, "never" when off).
    public var allowOverlap = true

    public init() {}

    /// Word's Move with text: the table follows its paragraph (measured from it).
    public var movesWithText: Bool {
        get { verticalFrom == .paragraph }
        set { verticalFrom = newValue ? .paragraph : (verticalFrom == .paragraph ? .margin : verticalFrom) }
    }

    /// Read from kept XML; nil when it holds no `w:tblpPr`.
    public init?(xml: String?) {
        guard let xml, let tag = Self._tag(xml, "w:tblpPr") else { return nil }
        func num(_ n: String) -> Double? { Self._attr(tag, n).flatMap(Double.init).map { $0 / 20 } }
        horizontalAlign = Self._attr(tag, "w:tblpXSpec")
        x = num("w:tblpX") ?? 0
        horizontalFrom = Self._attr(tag, "w:horzAnchor").flatMap(HorizontalFrom.init(rawValue:)) ?? .column
        verticalAlign = Self._attr(tag, "w:tblpYSpec")
        y = num("w:tblpY") ?? 0
        // (No w:vertAnchor stated is measured from the margin in Word's print: fdo68607.)
        verticalFrom = Self._attr(tag, "w:vertAnchor").flatMap(VerticalFrom.init(rawValue:)) ?? .margin
        top = num("w:topFromText") ?? 0; bottom = num("w:bottomFromText") ?? 0
        left = num("w:leftFromText") ?? 0; right = num("w:rightFromText") ?? 0
        allowOverlap = Self._tag(xml, "w:tblOverlap").flatMap { Self._attr($0, "w:val") } != "never"
    }

    /// As Word writes it.
    public var xml: String {
        func tw(_ v: Double) -> String { String(Int((v * 20).rounded())) }
        var a = "<w:tblpPr w:leftFromText=\"\(tw(left))\" w:rightFromText=\"\(tw(right))\""
        if top != 0 { a += " w:topFromText=\"\(tw(top))\"" }
        if bottom != 0 { a += " w:bottomFromText=\"\(tw(bottom))\"" }
        a += " w:vertAnchor=\"\(verticalFrom.rawValue)\""
        if horizontalFrom != .column { a += " w:horzAnchor=\"\(horizontalFrom.rawValue)\"" }
        if let h = horizontalAlign { a += " w:tblpXSpec=\"\(h)\"" } else if x != 0 { a += " w:tblpX=\"\(tw(x))\"" }
        if let v = verticalAlign { a += " w:tblpYSpec=\"\(v)\"" } else { a += " w:tblpY=\"\(tw(y))\"" }
        a += "/>"
        if !allowOverlap { a += "<w:tblOverlap w:val=\"never\"/>" }
        return a
    }

    static func _tag(_ xml: String, _ name: String) -> String? {
        guard let r = xml.rangeOfSubstring("<\(name)"), let e = xml.rangeOfSubstring(">", in: r.upperBound ..< xml.endIndex) else { return nil }
        let after = xml[r.upperBound]
        guard after == " " || after == "/" || after == ">" else { return nil }
        return String(xml[r.lowerBound ..< e.upperBound])
    }

    static func _attr(_ tag: String, _ name: String) -> String? {
        guard let r = tag.rangeOfSubstring(" \(name)=\""), let e = tag.rangeOfSubstring("\"", in: r.upperBound ..< tag.endIndex) else { return nil }
        return String(tag[r.upperBound ..< e.lowerBound])
    }
}
