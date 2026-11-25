// Saving a document that came from a file: keep the file's own styles part and patch only the styles the
// user created, changed or deleted. Rebuilding it from the flattened sheet lost basedOn chains, linked
// character styles, latent styles, aliases and rsids (Modify Normal in Word then stopped reaching the
// styles based on it).
import Foundation
import OfficeText

extension DocxFormat {
    static func _patchedStyles(original: String, generated: String, doc: RichDocument, usedIn: String = "") -> String? {
        guard let root = XNode.parse(Data(original.utf8)), root.name == "w:styles",
              let gen = XNode.parse(Data(generated.utf8)) else { return nil }
        let sheet = doc.styles
        var snapshot: [String: RichNamedStyle] = [:]
        for s in doc.styleSnapshot { snapshot[s.id] = s }
        var genById: [String: XNode] = [:]
        for n in gen.children where n.name == "w:style" { if let id = n["w:styleId"] { genById[id] = n } }
        func nameOf(_ n: XNode) -> String { (n.children.first { $0.name == "w:name" }?["w:val"] ?? "").lowercased() }

        var out: [XNode] = []
        var present = Set<String>(), names = Set<String>()
        var removed: [String: String?] = [:]   // a deleted file style's id -> what it was based on
        var defaultParagraphId = "Normal"
        for child in root.children {
            guard child.name == "w:style" else { out.append(child); continue }
            let fid = child["w:styleId"] ?? ""
            if child["w:type"] == "paragraph", child["w:default"] == "1" { defaultParagraphId = fid }
            if child["w:type"] == "paragraph", let ours = doc.styleFileIds[fid] {
                if sheet[ours] == nil, ours != RichNamedStyle.normalId {
                    removed[fid] = child.children.first { $0.name == "w:basedOn" }?["w:val"]
                    continue
                }
                if let entry = sheet[ours], let was = snapshot[ours], entry != was, doc.styleSource[ours] == fid,
                   let g = genById[ours] {
                    child.children.removeAll { $0.name == "w:pPr" || $0.name == "w:rPr" }
                    for tag in ["w:pPr", "w:rPr"] { if let n = g.children.first(where: { $0.name == tag }) { child.children.append(n) } }
                    if let next = entry.next, entry.next != was.next {
                        child.children.removeAll { $0.name == "w:next" }
                        let at = child.children.firstIndex { $0.name == "w:link" || $0.name == "w:uiPriority" || $0.name == "w:qFormat" || $0.name == "w:pPr" } ?? child.children.count
                        child.children.insert(XNode(name: "w:next", attrs: ["w:val": next]), at: at)
                    }
                }
            }
            out.append(child)
            present.insert(fid); names.insert(nameOf(child))
        }
        // What pointed at a deleted style: based on its parent, no link, next is the default style.
        if !removed.isEmpty {
            for n in out where n.name == "w:style" {
                for c in n.children {
                    guard let v = c["w:val"], removed[v] != nil else { continue }
                    switch c.name {
                    case "w:basedOn": if let parent = removed[v] ?? nil { c.attrs["w:val"] = parent } else { c.name = "w:removed" }
                    case "w:next": c.attrs["w:val"] = defaultParagraphId
                    case "w:link": c.name = "w:removed"
                    default: break
                    }
                }
                n.children.removeAll { $0.name == "w:removed" }
            }
        }
        func add(_ n: XNode) {
            guard let id = n["w:styleId"], !present.contains(id) else { return }
            // The writer says "Normal"; this file's default paragraph style may have another id (Chinese Word: "a").
            if defaultParagraphId != "Normal" {
                for c in n.children where (c.name == "w:basedOn" || c.name == "w:next") && c["w:val"] == "Normal" && !present.contains("Normal") {
                    c.attrs["w:val"] = defaultParagraphId
                }
            }
            out.append(n); present.insert(id); names.insert(nameOf(n))
        }
        // Created styles, and our id for a style the file knows under another one.
        for entry in sheet.styles where entry.id != RichNamedStyle.normalId {
            if snapshot[entry.id] == nil {
                // A built-in the sheet always carries is not the user's; it goes in only when the text uses it.
                let builtIn = RichStyleSheet.word[entry.id] != nil
                if let g = genById[entry.id], !builtIn || usedIn.containsSubstring("\"\(entry.id)\"") { add(g) }
            } else if let src = doc.styleSource[entry.id], src != entry.id, !present.contains(entry.id), present.contains(src),
                      usedIn.containsSubstring("\"\(entry.id)\"") {
                let shim = XNode(name: "w:style", attrs: ["w:type": "paragraph", "w:styleId": entry.id])
                shim.children = [XNode(name: "w:name", attrs: ["w:val": "\(entry.id) \(src)"]),
                                 XNode(name: "w:basedOn", attrs: ["w:val": src])]
                add(shim)
            }
        }
        // Whatever else the writer needs (List Paragraph, Hyperlink, the notes' styles) that the file lacks.
        for n in gen.children where n.name == "w:style" {
            guard let id = n["w:styleId"], !present.contains(id), !names.contains(nameOf(n)) else { continue }
            if doc.styleAliases[id] != nil { continue }
            // Only a style the saved text actually refers to; the writer's whole built-in set is not the user's.
            guard usedIn.containsSubstring("\"\(id)\"") else { continue }
            add(n)
        }
        root.children = out
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" + PptxXML.serialize(root)
    }
}
