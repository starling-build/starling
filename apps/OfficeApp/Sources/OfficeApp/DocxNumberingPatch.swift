import Foundation
import OfficeText
import FlutterSwiftBridge

extension DocxFormat {
    /// The file's numbering.xml with only what the user changed or added replaced: its nsid, tmpl,
    /// tentative, tplc and tab survive, as do abstract definitions of lists nobody touched.
    /// `generated` is what the writer would have built from scratch.
    static func _patchedNumbering(original: String, generated: String, doc: RichDocument, usedIds: Set<Int>? = nil) -> String? {
        guard let root = XNode.parse(Data(original.utf8)), root.name == "w:numbering",
              let gen = XNode.parse(Data(generated.utf8)) else { return nil }
        var origNums: [Int: XNode] = [:]
        var abstractIds = Set<Int>()
        for n in root.children {
            if n.name == "w:num", let id = Int(n["w:numId"] ?? "") { origNums[id] = n }
            if n.name == "w:abstractNum", let id = Int(n["w:abstractNumId"] ?? "") { abstractIds.insert(id) }
        }
        func changed(_ id: Int) -> Bool {
            let k = String(id)
            return doc.listFormats[k] != doc.listFormatsSnapshot[k] || doc.listRestarts[k] != doc.listRestartsSnapshot[k]
        }
        var genAbstract: [Int: XNode] = [:]
        for n in gen.children where n.name == "w:abstractNum" { if let id = Int(n["w:abstractNumId"] ?? "") { genAbstract[id] = n } }
        var nextAbstract = (abstractIds.max() ?? -1) + 1
        var mapped: [Int: Int] = [:]          // generated abstract id -> id in the patched file
        var newAbstracts: [XNode] = []
        func target(_ genAbs: Int, forNum numId: Int) -> Int {
            if let m = mapped[genAbs] { return m }
            // The generated abstract of a list that shares another's: the other's, when it stays as the file has it.
            let leader = genAbs - 1
            if leader != numId, let o = origNums[leader], !changed(leader), let v = Int(o.children.first { $0.name == "w:abstractNumId" }?["w:val"] ?? "") {
                return v
            }
            let id = nextAbstract; nextAbstract += 1
            mapped[genAbs] = id
            if let a = genAbstract[genAbs] { a.attrs["w:abstractNumId"] = String(id); newAbstracts.append(a) }
            return id
        }
        var appended: [XNode] = []
        for n in gen.children where n.name == "w:num" {
            guard let id = Int(n["w:numId"] ?? "") else { continue }
            let known = origNums[id] != nil
            // The writer's own bullet and decimal lists are added only when some paragraph uses them.
            if !known, let usedIds, !usedIds.contains(id) { continue }
            if known && !changed(id) { continue }
            if let ab = n.children.first(where: { $0.name == "w:abstractNumId" }), let g = Int(ab["w:val"] ?? "") {
                ab.attrs["w:val"] = String(target(g, forNum: id))
            }
            if known, let at = root.children.firstIndex(where: { $0 === origNums[id]! }) { root.children[at] = n } else { appended.append(n) }
        }
        let lastAbstract = root.children.lastIndex { $0.name == "w:abstractNum" } ?? -1
        root.children.insert(contentsOf: newAbstracts, at: lastAbstract + 1)
        let tail = root.children.firstIndex { $0.name == "w:numIdMacAtCleanup" } ?? root.children.count
        root.children.insert(contentsOf: appended, at: tail)
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" + PptxXML.serialize(root)
    }

    /// Every numId the file's numbering.xml defines, so the writer's own lists start above them.
    static func _numIdsIn(_ xml: String?) -> [Int] {
        guard let xml, let root = XNode.parse(Data(xml.utf8)) else { return [] }
        return root.children.compactMap { $0.name == "w:num" ? Int($0["w:numId"] ?? "") : nil }
    }
}
