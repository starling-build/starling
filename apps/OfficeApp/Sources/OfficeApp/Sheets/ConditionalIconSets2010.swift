import Foundation

/// The three icon sets Excel 2010 added (3Stars, 3Triangles, 5Boxes). The 2007 file format has no name for
/// them, so Excel writes them only in the sheet's x14 extension (no copy in the main part), and so do we.
enum IconSets2010 {
    static let names: Set<String> = ["3Stars", "3Triangles", "5Boxes"]
    static let extURI = "{78C0D931-6437-407d-A8EE-F0AAD7539E65}"

    /// The rules the x14 extension holds for these sets.
    static func rules(_ ws: Worksheet) -> [CFRule] {
        var out: [CFRule] = []
        for (name, text) in ws.keptElements where name == "extLst" {
            guard let root = XNode.parse(Data(text.utf8)) else { continue }
            for block in root.descendants("x14:conditionalFormatting") {
                let ranges = (block.first("xm:sqref")?.text ?? "").split(separator: " ").compactMap { CellRange(String($0)) }
                guard !ranges.isEmpty else { continue }
                for r in block.all("x14:cfRule") where r["type"] == "iconSet" {
                    guard let set = r.first("x14:iconSet"), let n = set["iconSet"], names.contains(n), set["custom"] != "1" else { continue }
                    let vals = set.all("x14:cfvo").map { CFValue(type: $0["type"] ?? "percent", value: Double($0.first("xm:f")?.text ?? "")) }
                    guard vals.count >= 3 else { continue }
                    out.append(CFRule(ranges: ranges, priority: Int(r["priority"] ?? "") ?? Int.max, dxf: nil,
                                      stopIfTrue: r["stopIfTrue"] == "1",
                                      kind: .iconSet(n, Array(vals.dropFirst()).map { ($0, true) },
                                                     reverse: set["reverse"] == "1", showValue: set["showValue"] != "0")))
                }
            }
        }
        return out
    }

    /// One `x14:conditionalFormatting` block for `name` over `sqref`, with Excel's default thresholds.
    static func block(_ name: String, sqref: String, priority: Int) -> String {
        let n = Int(name.prefix(1)) ?? 3
        var cfvo = "<x14:cfvo type=\"percent\"><xm:f>0</xm:f></x14:cfvo>"
        for i in 1 ..< n { cfvo += "<x14:cfvo type=\"percent\"><xm:f>\((100 * i + n / 2) / n)</xm:f></x14:cfvo>" }
        let id = "{00000000-0000-0000-0000-" + String(repeating: "0", count: max(0, 12 - String(priority).count)) + String(priority) + "}"
        return "<x14:conditionalFormatting xmlns:xm=\"http://schemas.microsoft.com/office/excel/2006/main\">"
            + "<x14:cfRule type=\"iconSet\" priority=\"\(priority)\" id=\"\(id)\"><x14:iconSet iconSet=\"\(name)\">\(cfvo)</x14:iconSet></x14:cfRule>"
            + "<xm:sqref>\(sqref)</xm:sqref></x14:conditionalFormatting>"
    }

    /// `block` added to the sheet's extension list text (which may be nil), keeping everything already there.
    static func inserting(_ block: String, into ext: String?) -> String {
        let x14 = "xmlns:x14=\"http://schemas.microsoft.com/office/spreadsheetml/2009/9/main\""
        let wrapped = "<ext uri=\"\(extURI)\" \(x14)><x14:conditionalFormattings>\(block)</x14:conditionalFormattings></ext>"
        guard var t = ext else { return "<extLst>" + wrapped + "</extLst>" }
        if let c = lastRange(of: "</x14:conditionalFormattings>", in: t) {
            t.insert(contentsOf: block, at: c.lowerBound)
        } else if let e = lastRange(of: "</extLst>", in: t) {
            t.insert(contentsOf: wrapped, at: e.lowerBound)
        }
        return t
    }

    private static func lastRange(of s: String, in t: String) -> Range<String.Index>? {
        var found: Range<String.Index>?
        var from = t.startIndex
        while let r = t.findRange(of: s, in: from ..< t.endIndex) { found = r; from = r.upperBound }
        return found
    }

    /// Take `cut` off the x14 icon blocks. A block left with nothing goes; one cut in part keeps what is left.
    static func clearing(_ text: String, _ cut: [CellRange]) -> String {
        var t = text
        var from = t.startIndex
        while let a = t.findRange(of: "<x14:conditionalFormatting ", in: from ..< t.endIndex),
              let e = t.findRange(of: "</x14:conditionalFormatting>", in: a.upperBound ..< t.endIndex) {
            let blockRange = a.lowerBound ..< e.upperBound
            let block = String(t[blockRange])
            guard block.containsSubstring("type=\"iconSet\""), IconSets2010.names.contains(where: { block.containsSubstring("iconSet=\"\($0)\"") }),
                  let s1 = block.findRange(of: "<xm:sqref>"), let s2 = block.findRange(of: "</xm:sqref>") else { from = e.upperBound; continue }
            let old = block[s1.upperBound ..< s2.lowerBound].split(separator: " ").compactMap { CellRange(String($0)) }
            let left = old.flatMap { r in cut.reduce([r]) { ps, c in ps.flatMap { WorkbookController._subtract($0, c) } } }
            if left == old { from = e.upperBound; continue }
            if left.isEmpty {
                t.removeSubrange(blockRange)
                from = a.lowerBound
            } else {
                var nb = block
                nb.replaceSubrange(s1.upperBound ..< s2.lowerBound, with: left.map { $0.isSingle ? $0.topLeft.a1 : $0.a1 }.joined(separator: " "))
                t.replaceSubrange(blockRange, with: nb)
                from = t.index(a.lowerBound, offsetBy: nb.count)
            }
        }
        return t
    }
}
